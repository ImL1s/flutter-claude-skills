---
name: flutter-mobile-debugging
description: Debug Flutter apps on real Android devices and iOS Simulators using Mobile MCP tools, adb, and xcrun simctl. Use when testing Flutter UI on devices, verifying widget behavior after code changes, debugging touch interactions, checking logs, or automating install-launch-interact-verify cycles. Triggers on keywords like "test on device", "adb logcat", "Flutter debug Android", "verify on phone", "mobile MCP", "screenshot device", "tap button on device", "install APK", "share intent test", "iOS simulator test", "simctl install", "flutter run hang".
---

# Flutter Mobile Debugging via Mobile MCP + ADB/simctl

## Overview

Workflow for debugging Flutter apps on real Android devices and iOS Simulators using the Mobile MCP tool suite, `adb`, and `xcrun simctl`. Covers the full cycle: build → install → launch → interact → capture → analyze logs.

## Prerequisites

- **Android:** Device connected via USB with `adb` accessible
- **iOS:** Simulator booted via Xcode or `xcrun simctl boot <UDID>`
- Get device ID: `mcp mobile_list_available_devices`, `adb devices`, or `xcrun simctl list devices booted`
- Flutter project buildable with `flutter build apk --debug` or `flutter build ios --simulator --debug`

## Core Workflow

### 1. Build and Install

**Android:**
```bash
flutter build apk --debug 2>&1 | tail -3
adb -s DEVICE_ID install -r build/app/outputs/flutter-apk/app-debug.apk
```

**iOS Simulator:**
```bash
flutter build ios --simulator --debug 2>&1 | tail -5
xcrun simctl install <SIMULATOR_UDID> build/ios/iphonesimulator/Runner.app
```

> ⚠️ **Do NOT use `flutter run`** if it hangs. `flutter run` calls `xcdevice list` which
> can freeze indefinitely when real iOS devices are connected. The build+simctl approach
> bypasses this entirely. See [Troubleshooting](#flutter-run-hangs-on-ios) below.

### 2. Launch App

**Android — direct launch:**
```bash
adb -s DEVICE_ID shell am start -n com.example.app/.MainActivity
```

**Android — share intent:**
```bash
adb -s DEVICE_ID shell am start -a android.intent.action.SEND \
  -t text/plain \
  --es android.intent.extra.TEXT "https://example.com" \
  -n com.example.app/.MainActivity
```

**Android — force-stop:**
```bash
adb -s DEVICE_ID shell am force-stop com.example.app
```

**iOS Simulator — launch:**
```bash
xcrun simctl launch <SIMULATOR_UDID> <BUNDLE_ID>
# Example: xcrun simctl launch 65115B75-... com.example.yourapp
```

**iOS Simulator — terminate:**
```bash
xcrun simctl terminate <SIMULATOR_UDID> <BUNDLE_ID>
```

### 3. Wait for UI to Settle

AI operations, network fetches, and animations need time:
```bash
sleep 10  # Adjust based on expected operation time
```

### 4. Interact with UI

**Discover elements:**
```
mcp mobile_list_elements_on_screen(device=DEVICE_ID)
```
Returns element types, text, labels, and **coordinates** — use coordinates for clicking.

**Click:**
```
mcp mobile_click_on_screen_at_coordinates(device=DEVICE_ID, x=872, y=2026)
```

**Swipe (scroll):**
```
mcp mobile_swipe_on_screen(device=DEVICE_ID, direction="up", distance=500)
```

**Type text:**
```
mcp mobile_type_keys(device=DEVICE_ID, text="hello", submit=false)
```

### 5. Capture and Analyze

**Screenshot:**
```
mcp mobile_take_screenshot(device=DEVICE_ID)          # View inline
mcp mobile_save_screenshot(device=DEVICE_ID, saveTo=path)  # Save to file
```

**Logcat (Flutter logs):**
```bash
# All flutter logs
adb -s DEVICE_ID logcat -d | grep "I flutter" | tail -30

# Clear log buffer before test
adb -s DEVICE_ID logcat -c
```

## Critical Tips

### `print()` vs `debugPrint()` for Logcat

**Always use `print()` when debugging via logcat**, not `debugPrint()`.

`debugPrint()` throttles output to avoid flooding the console. On real devices, this throttling can cause messages to **never appear** in `adb logcat`. `print()` outputs reliably.

```dart
// BAD — may not appear in logcat
debugPrint('[MyWidget] state changed to $value');

// GOOD — always appears in logcat
print('[MyWidget] state changed to $value');
```

### Logcat Filter Patterns

```bash
# Flutter only (tag-based filter)
adb -s DEVICE_ID logcat -d -s flutter

# Grep-based (more flexible)
adb -s DEVICE_ID logcat -d | grep "I flutter"

# Custom marker (recommended for targeted debugging)
adb -s DEVICE_ID logcat -d | grep "\[MyWidget\]"
```

### Full Test Cycle Command Chain

Combine steps for efficient single-command testing:

```bash
# Build, install, clear logs, force-stop, launch, wait, capture logs
flutter build apk --debug 2>&1 | tail -3 && \
adb -s DEVICE_ID install -r build/app/outputs/flutter-apk/app-debug.apk && \
adb -s DEVICE_ID logcat -c && \
adb -s DEVICE_ID shell am force-stop com.example.app && \
sleep 1 && \
adb -s DEVICE_ID shell am start -n com.example.app/.MainActivity && \
sleep 10 && \
adb -s DEVICE_ID logcat -d | grep "I flutter"
```

### Element Coordinates

`mobile_list_elements_on_screen` returns `coordinates` with `x`, `y`, `width`, `height`. Click the **center** of the element:
- Click X = `coordinates.x + coordinates.width / 2`
- Click Y = `coordinates.y + coordinates.height / 2`

### Debug Print Cleanup

After debugging, always remove all `print()` statements before committing. Search for leftover prints:

```bash
grep -rn "print(" lib/ --include="*.dart" | grep -v "// " | grep -v "debugPrint"
```

## Troubleshooting

### `flutter run` Hangs on iOS {#flutter-run-hangs-on-ios}

**Symptom:** `flutter run -d <simulator>` hangs with no output for minutes.

**Root cause:** `flutter run` calls `xcdevice list --timeout 5` which freezes when real iOS devices are connected (known Flutter/Xcode issue).

**Diagnosis:**
```bash
ps aux | grep xcdevice          # Stuck xcdevice list processes
ps aux | grep flutter_tools.snapshot | wc -l  # Multiple = zombie daemons
```

**Fix:**
```bash
# 1. Kill stuck processes
pkill -9 -f "flutter_tools.snapshot"
pkill -9 -f "xcdevice"

# 2. Use build + simctl install instead
flutter build ios --simulator --debug
xcrun simctl install <UDID> build/ios/iphonesimulator/Runner.app
xcrun simctl launch <UDID> <BUNDLE_ID>
```

**Prevention:** Disconnect real iOS devices when targeting simulator only.
