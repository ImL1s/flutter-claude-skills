---
name: flutter-background-tasks
description: Flutter background task configuration guide for iOS (background_fetch/BGTaskScheduler) and Android (WorkManager). Use when setting up periodic background tasks, debugging background execution failures, or auditing platform configuration for background work.
---

# Flutter Background Tasks (iOS + Android)

Complete guide for configuring periodic background tasks in Flutter apps using `workmanager` (Android) and `background_fetch` (iOS).

## Package Versions

```yaml
dependencies:
  workmanager: ^0.9.0          # Android WorkManager wrapper
  background_fetch: ^1.5.0     # iOS BGTaskScheduler wrapper
```

## Architecture Overview

```
Foreground App                     Background Isolate
┌──────────────────┐               ┌──────────────────┐
│ RevenueCat SDK   │               │ SharedPreferences │
│ SubscriptionProv │──writes──►    │ (cached status)   │
│                  │  lobster_     │                   │
│                  │  subscription_│──reads──► Gate     │
│                  │  cached       │         .isSubscribed()
└──────────────────┘               └──────────────────┘

Background isolates CANNOT use:
- MethodChannel-based SDKs (RevenueCat, Firebase Auth listeners)
- EventChannel streams
- Platform views

Background isolates CAN use:
- SharedPreferences (read/write)
- HTTP requests (Dio, http)
- Firebase Core, Firestore, AppCheck (after re-init)
- Local file I/O
```

## iOS Setup (background_fetch)

### 1. Info.plist (CRITICAL)

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <!-- REQUIRED: background_fetch default task identifier -->
    <string>com.transistorsoft.fetch</string>
    <!-- Optional: custom scheduled tasks (must use this prefix) -->
    <string>com.transistorsoft.customtask</string>
</array>

<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>        <!-- Required for BackgroundFetch.configure() -->
    <string>processing</string>   <!-- Required for BackgroundFetch.scheduleTask() -->
</array>
```

**Common mistake**: Forgetting `com.transistorsoft.fetch` causes BGAppRefreshTask to **silently fail** with no error logs. This is the #1 cause of iOS background tasks not executing.

### 2. Xcode Capabilities

In Xcode: Target > Signing & Capabilities > Background Modes:
- [x] Background fetch
- [x] Background processing

### 3. AppDelegate.swift

**No changes needed for iOS 13+.** The SDK auto-registers from Info.plist.

If using workmanager for OTHER tasks (not background_fetch):
```swift
// Only for workmanager tasks, NOT background_fetch
WorkmanagerPlugin.registerPeriodicTask(
    withIdentifier: "com.example.myTask",
    frequency: NSNumber(value: 24 * 60 * 60)
)
WorkmanagerPlugin.setPluginRegistrantCallback { registry in
    GeneratedPluginRegistrant.register(with: registry)
}
```

### 4. Podfile

The `use_frameworks!` line should work for most projects. If you encounter linking errors:
```ruby
# Try static linkage if dynamic causes issues
use_frameworks! :linkage => :static
```

**Warning**: Changing linkage can break other SDKs (Appodeal, AdMob). Test thoroughly.

### 5. iOS Constraints & Limitations

| Constraint | Value |
|-----------|-------|
| Minimum interval | 15 minutes (iOS enforces, ignores higher values) |
| Background time limit | ~30 seconds |
| Scheduling control | Apple's ML algorithm decides when to run |
| After reboot | Automatically re-registered from Info.plist |
| App terminated | Works if `enableHeadless: true` |
| Must call finish | `BackgroundFetch.finish(taskId)` or task gets throttled |
| Custom taskId prefix | Must start with `com.transistorsoft.` |

### 6. iOS Timeout Handling

Always implement timeout with 2-second margin:
```dart
// iOS background time limit is ~30 seconds
// Use 28 seconds to leave margin for cleanup
final timeout = isIOSBackground ? 28 : 540; // seconds

await Future.any([
  _doWork(),
  Future.delayed(Duration(seconds: timeout)).then((_) {
    throw TimeoutException('Background task timed out');
  }),
]);
```

## Android Setup (WorkManager)

### 1. AndroidManifest.xml

```xml
<manifest>
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <!-- Required: WorkManager reschedules after device reboot -->
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    ...
</manifest>
```

### 2. build.gradle.kts

```kotlin
android {
    compileOptions {
        // Required for WorkManager + Kotlin
        isCoreLibraryDesugaringEnabled = true
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

### 3. ProGuard (if using R8 minification)

WorkManager's AAR includes consumer ProGuard rules automatically. Usually no explicit rules needed. If you see reflection errors in release builds:

```proguard
# Only if needed
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
```

### 4. Android Constraints & Limitations

| Constraint | Value |
|-----------|-------|
| Minimum interval | 15 minutes (WorkManager enforces) |
| Background time limit | ~10 minutes |
| Network constraint | `NetworkType.connected` recommended |
| After reboot | Automatic (requires RECEIVE_BOOT_COMPLETED) |
| App terminated | Always works (WorkManager is OS-level) |
| Battery optimization | May be delayed by Doze mode |
| Backoff | Exponential recommended for network tasks |

## Dart Implementation

### Entry Point Functions

**CRITICAL**: Both callback functions MUST have `@pragma('vm:entry-point')` to prevent tree-shaking in release builds.

```dart
// Android WorkManager callback
@pragma('vm:entry-point')
void myCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // Re-initialize plugins in background isolate
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    // Do work...
    return true; // success
  });
}

// iOS background_fetch headless callback
@pragma('vm:entry-point')
void myHeadlessTask(HeadlessTask task) async {
  final taskId = task.taskId;
  final isTimeout = task.timeout;

  if (isTimeout) {
    BackgroundFetch.finish(taskId);
    return;
  }

  // Re-initialize plugins
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Do work...

  BackgroundFetch.finish(taskId); // MUST call or task gets throttled
}
```

### Scheduler Pattern

```dart
class BackgroundScheduler {
  final String taskName;
  final String uniqueId;

  Future<void> register({
    required int intervalHours,
    required Function callbackDispatcher,
    Function(String)? iosCallback,
    Function(HeadlessTask)? headlessTask,
  }) async {
    if (Platform.isAndroid) {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        uniqueId,
        taskName,
        frequency: Duration(hours: intervalHours),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.exponential,
        initialDelay: const Duration(minutes: 1),
      );
    } else if (Platform.isIOS) {
      await BackgroundFetch.configure(
        BackgroundFetchConfig(
          minimumFetchInterval: 15, // iOS minimum
          stopOnTerminate: false,
          enableHeadless: true,
        ),
        iosCallback ?? (_) {},
        (taskId) => BackgroundFetch.finish(taskId), // timeout handler
      );
      if (headlessTask != null) {
        BackgroundFetch.registerHeadlessTask(headlessTask);
      }
    }
  }
}
```

### Subscription Gate Pattern (Background-Safe)

```dart
/// Reads cached subscription status from SharedPreferences.
/// Does NOT call any MethodChannel-based SDK.
class RevenueCatGate implements SubscriptionGate {
  final AgentRepository _repo;

  RevenueCatGate(this._repo);

  @override
  Future<bool> isSubscribed() async {
    return _repo.getCachedSubscriptionStatus();
    // Reads: prefs.getBool('${keyPrefix}_subscription_cached')
  }
}
```

**Foreground writes** (in SubscriptionProvider):
```dart
// Write to SharedPreferences when subscription state changes
await prefs.setBool('${keyPrefix}_subscription_cached', isSubscribed);
```

**Key consistency**: The foreground write key and background read key MUST match exactly. Use the same `keyPrefix` pattern.

## Debugging Background Tasks

### iOS Simulator

Force-trigger background fetch:
```bash
# In Xcode: Debug > Simulate Background Fetch
# Or via command line:
xcrun simctl background_fetch <device_id> <bundle_id>
```

### Android

```bash
# List WorkManager tasks
adb shell dumpsys jobscheduler | grep <package_name>

# Force run immediately (for testing)
adb shell cmd jobscheduler run -f <package_name> <job_id>
```

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| iOS: Tasks never execute | Missing `com.transistorsoft.fetch` in Info.plist | Add to BGTaskSchedulerPermittedIdentifiers |
| iOS: Tasks stop after a while | Not calling `BackgroundFetch.finish()` | Always call finish, even on timeout |
| iOS: Works in debug, not release | Missing `@pragma('vm:entry-point')` | Add pragma to both callback functions |
| Android: Tasks don't survive reboot | Missing RECEIVE_BOOT_COMPLETED | Add permission to AndroidManifest.xml |
| Android: Release build crash | R8 removing Worker classes | Add ProGuard keep rules |
| Both: SDK calls fail in background | Using MethodChannel SDK in isolate | Cache state in SharedPreferences, read in background |
| Both: Subscription check fails | Cache key mismatch foreground/background | Verify keyPrefix produces same SharedPreferences key |

## Audit Checklist

When reviewing a Flutter background task setup, verify:

### iOS
- [ ] `com.transistorsoft.fetch` in BGTaskSchedulerPermittedIdentifiers
- [ ] `fetch` in UIBackgroundModes
- [ ] `processing` in UIBackgroundModes (if using scheduleTask)
- [ ] Background Modes capability enabled in Xcode
- [ ] `@pragma('vm:entry-point')` on headless callback
- [ ] `BackgroundFetch.finish(taskId)` called in ALL paths (success + timeout)
- [ ] Timeout < 30 seconds (recommend 28s)
- [ ] No MethodChannel SDK calls in background isolate

### Android
- [ ] `RECEIVE_BOOT_COMPLETED` permission in AndroidManifest.xml
- [ ] Core library desugaring enabled in build.gradle
- [ ] `@pragma('vm:entry-point')` on callbackDispatcher
- [ ] `NetworkType.connected` constraint for network tasks
- [ ] Exponential backoff configured
- [ ] Firebase re-initialized in background isolate
- [ ] ProGuard rules if R8 minification enabled

### Cross-Platform
- [ ] SharedPreferences cache key matches between foreground write and background read
- [ ] No direct RevenueCat/Firebase Auth SDK calls in background
- [ ] Timeout handling with platform-appropriate limits
- [ ] Tests for cache key consistency

## Testing Strategy

### Unit Tests
```dart
test('foreground/background cache key consistency', () async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = AgentRepository(prefs, keyPrefix: 'myapp');

  // Simulate foreground write
  await prefs.setBool('myapp_subscription_cached', true);

  // Background read should match
  expect(repo.getCachedSubscriptionStatus(), true);
});
```

### Integration Tests
1. Build release APK/IPA
2. Install on device
3. Enable the background task
4. Kill the app
5. Wait for task to trigger (or force-trigger)
6. Check logs/SharedPreferences for evidence of execution

### iOS Simulator Testing
```bash
# 1. Run app on simulator
# 2. Background the app
# 3. Force fetch:
xcrun simctl background_fetch booted com.example.myapp
# 4. Check console logs in Xcode
```
