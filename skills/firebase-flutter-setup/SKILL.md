---
name: firebase-flutter-setup
description: Set up Firebase Authentication (Google Sign-In), AdMob, and RevenueCat IAP for Flutter Android apps. Use when enabling Firebase Auth providers, configuring Google Sign-In with OAuth clients, adding AdMob ad units, or integrating RevenueCat subscriptions. Covers the exact GCP console steps, SHA-1 registration, Gradle plugin setup, and real-device testing gotchas. Triggers on keywords like "Firebase setup", "Google Sign-In", "OAuth client", "ApiException 10", "DEVELOPER_ERROR", "AdMob Flutter", "RevenueCat setup", "SHA-1 fingerprint", "google-services.json".
---

# Firebase + AdMob + RevenueCat Setup for Flutter

## Prerequisites

- Firebase project created (`firebase projects:create` or Console)
- Billing account linked (`gcloud billing projects link <project> --billing-account=<id>`)
- `flutterfire` CLI installed (`dart pub global activate flutterfire_cli`)
- Debug keystore SHA-1 fingerprint obtained

## Step 1: Get SHA-1 Fingerprint

```bash
# Windows (Chinese locale will mislabel — MD5 line is actually SHA-1)
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android

# Verify: SHA-1 = 20 bytes (40 hex chars with colons = 59 chars)
# SHA-256 = 32 bytes (64 hex chars with colons = 95 chars)
```

> [!CAUTION]
> Chinese locale `keytool` mislabels fingerprints — the line labeled "MD5" is actually SHA-1 (20 bytes), and "SHA1" is actually SHA-256 (32 bytes). Always verify by byte count.

## Step 2: Configure Firebase + FlutterFire

```bash
# Initialize Identity Platform (required for Google Sign-In)
gcloud services enable identitytoolkit.googleapis.com --project=<PROJECT_ID>

# Run flutterfire
flutterfire configure --project=<PROJECT_ID> --platforms=android \
  --android-package-name=<PACKAGE_NAME> --yes

# Register SHA-1 via REST API (firebase CLI sha:create often fails)
ACCESS_TOKEN=$(gcloud auth print-access-token)
curl -X POST \
  "https://firebase.googleapis.com/v1beta1/projects/<PROJECT_ID>/androidApps/<APP_ID>/sha" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"shaHash":"<SHA1_NO_COLONS>","certType":"SHA_1"}'
```

## Step 3: Google Sign-In — The 3 OAuth Clients

> [!IMPORTANT]
> Google Sign-In requires **3 things** in GCP, not just 1. Missing any one causes `ApiException: 10` (DEVELOPER_ERROR).

### Required OAuth Clients in GCP

| Type | Purpose | How to Create |
|------|---------|---------------|
| **Web Client** | Provides `serverClientId` for ID token exchange | GCP Console → Auth Platform → Clients → Web |
| **Android Client** | Matches SHA-1 + package name for device auth | GCP Console → Auth Platform → Clients → Android |
| **OAuth Consent Screen** | Must exist (External for personal accounts) | GCP Console → Auth Platform → Branding |

### Why CLI/API Often Fails

- `gcloud` and IAP API for creating OAuth consent screens requires a GCP **Organization** — personal accounts must use the Console UI
- `firebase apps:android:sha:create` CLI command frequently fails — use REST API instead
- OAuth client creation via API also requires Organization — use browser automation for personal accounts

### Code Configuration

> [!WARNING]
> The code below uses **google_sign_in v6 API** which is outdated.
> For v7+ usage (with `initialize()` + `authenticationEvents` stream), see the **`flutter-social-login`** skill.

```dart
// auth_provider.dart (v6 — DEPRECATED, use flutter-social-login skill for v7+)
final googleUser = await GoogleSignIn(
  serverClientId: '<WEB_CLIENT_ID>.apps.googleusercontent.com',  // Web, NOT Android
).signIn();
```

```json
// google-services.json — add oauth_client with Web client
"oauth_client": [
  {
    "client_id": "<WEB_CLIENT_ID>.apps.googleusercontent.com",
    "client_type": 3
  }
]
```

### Enable Provider in Firebase

```bash
# Update Google Sign-In provider with real OAuth credentials
curl -X PATCH \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/<PROJECT_ID>/defaultSupportedIdpConfigs/google.com?updateMask=enabled,clientId,clientSecret" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled":true,"clientId":"<WEB_CLIENT_ID>","clientSecret":"<WEB_CLIENT_SECRET>"}'
```

## Step 4: Gradle Plugin Setup

> [!WARNING]
> `flutterfire configure` adds plugins to `app/build.gradle.kts` but does NOT add them to `settings.gradle.kts`. This causes `Plugin was not found` build failures.

### Required in `settings.gradle.kts`

```kotlin
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
    id("com.google.firebase.crashlytics") version "3.0.3" apply false  // MUST ADD
}
```

### Required in `app/build.gradle.kts`

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}
```

## Step 5: AdMob Integration

```xml
<!-- AndroidManifest.xml — inside <application> -->
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX"/>
```

Use `kDebugMode` to toggle test/production ad IDs in Dart code.

## Step 6: RevenueCat IAP Setup

1. Create project at https://app.revenuecat.com
2. Add Android app with package name
3. Create entitlement (e.g., `pro`)
4. Create offering (e.g., `default`) with packages
5. Get SDK key from API Keys page (`goog_...`)
6. Update Flutter code with SDK key

## Step 7: Real-Device Testing Checklist

| Issue | Symptom | Root Cause | Fix |
|-------|---------|------------|-----|
| `Plugin was not found` | Gradle build fails | Missing plugin in `settings.gradle.kts` | Add plugin with version |
| `MissingLibraryException: libflutter.so` | Crash on ARM device | `flutter build apk --debug` only includes x86_64 | Use `flutter run -d <device>` instead |
| `ApiException: 10` (DEVELOPER_ERROR) | Google Sign-In fails after account selection | Missing Android OAuth Client in GCP | Create Android client with SHA-1 + package |
| `ApiException: 12` (NOT_SUPPORTED) | Sign-In picker doesn't appear | Wrong `serverClientId` | Use **Web** client ID, not Android |
| Account picker shows but no login | Stays on login page | Emulator has no Google account | Add Google account to emulator settings |

## .gitignore Best Practices

```gitignore
# Firebase credentials — NEVER commit
app/android/app/google-services.json
app/ios/Runner/GoogleService-Info.plist

# FVM
app/.fvm/
```

## Related skills

- **`firebase-auth-manager`** — implement user sign-in after Firebase is initialized. Firebase-flutter-setup provides the backend infrastructure; firebase-auth-manager builds the auth UX.
- **`admob-ux-best-practices`** → **`revenuecat-manager`** — integrate monetization after Firebase is set up. Use these for ads and subscriptions.
- **`flutter-verify`** — after setup completes, verify Firebase services are accessible and auth flows work end-to-end.
