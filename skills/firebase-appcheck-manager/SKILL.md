---
name: firebase-appcheck-manager
description: Use when managing Firebase App Check via CLI. Covers enabling the API, registering Android/iOS attestation providers (Play Integrity, App Attest), managing SHA-256 fingerprints, enforcing services, and managing debug tokens. Triggers on keywords like "App Check", "Play Integrity", "App Attest", "debug token", "attestation", "enforce Firebase".
---

# Firebase App Check Manager

> **⚠️ #1 ROOT CAUSE of "App attestation failed": Missing Team ID or API not enabled**
>
> Two things MUST be in place for iOS App Check to work:
> 1. **`firebaseappcheck.googleapis.com` API must be ENABLED** — even if you've configured providers in Console, if this API isn't enabled, all token exchanges fail silently.
> 2. **iOS App must have `teamId` set** — Without Team ID, App Attest cannot verify with Apple's servers.
>
> **Team ID can be set via REST API** (no Console UI needed):
> ```bash
> curl -X PATCH -H "Authorization: Bearer $ACCESS_TOKEN" \
>   -H "x-goog-user-project: ${PROJECT_ID}" \
>   -H "Content-Type: application/json" \
>   -d '{"teamId":"YOUR_TEAM_ID"}' \
>   "https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/iosApps/${IOS_APP_ID}?updateMask=teamId"
> ```
>
> If Team ID is already set and API is enabled, verify app registration through **Firebase Console → App Check → 應用程式 tab**.
> Required IAM role: `roles/editor` or `roles/owner` (not just `roles/firebase.viewer` or `roles/firebaseappcheck.admin`).

Manage Firebase App Check configuration entirely via CLI (`gcloud` + REST API). No Firebase Console UI needed for most steps, **except app registration (see Step 0)**.

## Concepts: How App Check Works

App Check is a **server-side gatekeeper** that protects your Firebase backend services from abuse. It works via a 3-step process:

```
┌─────────────┐     ①  Attestation      ┌────────────────────┐
│  Your App   │ ──────────────────────→  │  Attestation       │
│ (Flutter)   │                          │  Provider          │
│             │ ←────────────────────    │ (Play Integrity /  │
│             │     ② Attestation Token  │  App Attest)       │
│             │                          └────────────────────┘
│             │     ③ Exchange for
│             │        App Check Token   ┌────────────────────┐
│             │ ──────────────────────→  │  Firebase           │
│             │                          │  App Check Server   │
│             │ ←────────────────────    │                     │
│             │     ④ App Check Token    └────────────────────┘
│             │
│             │     ⑤ API call with      ┌────────────────────┐
│             │        App Check Token   │  Firebase Service   │
│             │ ──────────────────────→  │  (AI, Firestore,   │
│             │                          │   Storage, etc.)    │
│             │     ⑥ Response           └────────────────────┘
└─────────────┘     (or 403 if invalid)
```

**Critical understanding:**
- The `activate()` call in Flutter just tells the SDK to **start sending tokens**
- Without **enforcement** on the server side, those tokens are ignored — ANY request is accepted
- **Enforcement = server rejects requests without valid App Check tokens**
- You must enable enforcement per Firebase service independently

### Android: Three Signing Keys

Android apps have **three different signing keys**. All three produce different SHA-256 fingerprints. **All three must be registered in Firebase** for App Check to work across dev, testing, and production:

| Key | When Used | Where to Find |
|-----|-----------|---------------|
| **Debug Key** | Local `flutter run` / `flutter build --debug` | `cd android && ./gradlew signingReport` |
| **Upload Key** | Your local `.jks` keystore used for `flutter build appbundle --release` | Same `signingReport` or `keytool -list -keystore your.jks` |
| **App Signing Key** | Google Play Console re-signs your AAB with this key before distributing to users | **Google Play Console → Release → Setup → App signing** |

> ⚠️ **The #1 mistake**: Registering only the debug or upload key. Production users receive the app signed with the **App Signing Key** which is different — their App Check attestation will fail silently.

### iOS: App Attest vs DeviceCheck

| Provider | iOS Version | Strength | Recommendation |
|----------|-------------|----------|----------------|
| `AppleAppAttestProvider` | iOS 14.0+ | Strong (hardware-backed) | ⚠️ ~25% failure rate in production ([FlutterFire #10683](https://github.com/firebase/flutterfire/issues/10683)) |
| `AppleDeviceCheckProvider` | iOS 11.0+ | Medium | Standalone fallback only |
| `AppleAppAttestProviderWithDeviceCheckFallback` | All | Adaptive | ✅ **RECOMMENDED for production** |

> **⚠️ CRITICAL: Always use `appAttestWithDeviceCheckFallback` in production, NOT `appAttest` alone.**
>
> App Attest depends on Apple's attestation server. Even on iOS 14+ real devices, `ExchangeAppAttestAttestation` has a **~25% failure rate** due to:
> - Apple attestation server transient failures
> - First-time attestation timing issues on fresh installs
> - Network conditions during attestation handshake
> - Device state edge cases (not jailbreak related)
>
> `appAttestWithDeviceCheckFallback` tries App Attest first, and **automatically falls back to DeviceCheck** when App Attest fails. Both are Apple official attestation mechanisms with equivalent security for App Check purposes. This ensures near-100% token acquisition rate.
>
> Firebase Console must have **both** App Attest AND DeviceCheck providers registered for the iOS app.

> **iOS entitlement required**: You MUST add `com.apple.developer.devicecheck.appattest-environment` to your iOS entitlements for App Attest to work in production builds.

## Prerequisites

- `gcloud` CLI authenticated with the correct account (`gcloud auth list` / `gcloud config set account EMAIL`)
- Owner/Editor role on the Firebase project
- Know your Firebase Project ID and App IDs (`firebase apps:list --project=PROJECT_ID`)

## Common Header Pattern

All REST API calls need these headers:

```bash
ACCESS_TOKEN=$(gcloud auth print-access-token)
PROJECT_ID="your-project-id"
ANDROID_APP_ID="1:xxxx:android:xxxx"
IOS_APP_ID="1:xxxx:ios:xxxx"
PROJECT_NUMBER="123456789"  # from firebase projects:list
```

```bash
-H "Authorization: Bearer $ACCESS_TOKEN"
-H "x-goog-user-project: ${PROJECT_ID}"
-H "Content-Type: application/json"
```

> **Important**: The `x-goog-user-project` header is required for quota billing. Without it you get `SERVICE_DISABLED` errors.

## Quick Audit Script (One-Shot Health Check)

Run this script to get a full status of App Check for any Firebase project. Copy/paste the entire block:

```bash
#!/bin/bash
# Usage: Set the 5 variables below, then run the entire script

ACCESS_TOKEN=$(gcloud auth print-access-token)
PROJECT_ID="your-project-id"
PROJECT_NUMBER="123456789"
ANDROID_APP_ID="1:xxxx:android:xxxx"
IOS_APP_ID="1:xxxx:ios:xxxx"

echo "╔═══════════════════════════════════════════╗"
echo "║   Firebase App Check Audit: $PROJECT_ID   ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

# 1. API Enablement
echo "── 1. API Enablement ──"
AC=$(gcloud services list --enabled --filter="config.name:firebaseappcheck" --project=$PROJECT_ID --format="value(config.name)" 2>/dev/null)
PI=$(gcloud services list --enabled --filter="config.name:playintegrity" --project=$PROJECT_ID --format="value(config.name)" 2>/dev/null)
[ -n "$AC" ] && echo "  ✅ firebaseappcheck.googleapis.com ENABLED" || echo "  ❌ firebaseappcheck.googleapis.com NOT ENABLED"
[ -n "$PI" ] && echo "  ✅ playintegrity.googleapis.com ENABLED" || echo "  ❌ playintegrity.googleapis.com NOT ENABLED"
echo ""

# 2. Services Enforcement
echo "── 2. Services Enforcement ──"
SERVICES=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_NUMBER}/services")
if echo "$SERVICES" | python3 -c "import sys,json; d=json.load(sys.stdin); svcs=d.get('services',[]); [print(f'  {s[\"name\"].split(\"/\")[-1]}: {s.get(\"enforcementMode\",\"UNENFORCED\")}') for s in svcs]" 2>/dev/null; then
  :
else
  echo "  ⚠️  No services configured or empty response"
fi
echo ""

# 3. Android Play Integrity Config
echo "── 3. Android Play Integrity Config ──"
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_NUMBER}/apps/${ANDROID_APP_ID}/playIntegrityConfig" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ttl=d.get('tokenTtl','?')
lvl=d.get('deviceIntegrity',{}).get('minDeviceRecognitionLevel','?')
print(f'  Token TTL: {ttl}')
print(f'  Min Device Recognition: {lvl}')
if lvl == 'NO_INTEGRITY':
    print('  ⚠️  NO_INTEGRITY allows any device (including emulators)')
" 2>/dev/null
echo ""

# 4. iOS App Attest Config
echo "── 4. iOS App Attest Config ──"
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_NUMBER}/apps/${IOS_APP_ID}/appAttestConfig" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f'  Token TTL: {d.get(\"tokenTtl\",\"?\")}')
" 2>/dev/null
echo ""

# 4b. iOS App Team ID (CRITICAL for App Attest)
echo "── 4b. iOS App Team ID ──"
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/iosApps/${IOS_APP_ID}" | python3 -c "
import sys,json
d=json.load(sys.stdin)
tid=d.get('teamId','')
if tid:
    print(f'  ✅ Team ID: {tid}')
else:
    print('  ❌ Team ID: NOT SET — App Attest WILL FAIL!')
    print('  Fix: curl -X PATCH ... -d \'{\"teamId\":\"YOUR_TEAM_ID\"}\' .../iosApps/APP_ID?updateMask=teamId')
" 2>/dev/null
echo ""

# 5. Android SHA Fingerprints (SHA-1 + SHA-256)
echo "── 5. Android SHA Fingerprints ──"
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/androidApps/${ANDROID_APP_ID}/sha" | python3 -c "
import sys,json
d=json.load(sys.stdin)
certs=d.get('certificates',[])
sha1 = [c for c in certs if c.get('certType')=='SHA_1']
sha256 = [c for c in certs if c.get('certType')=='SHA_256']
print(f'  Total: {len(certs)} ({len(sha1)} SHA-1, {len(sha256)} SHA-256)')
for cert in certs:
    print(f'  - {cert.get(\"certType\",\"?\"):8s} : {cert.get(\"shaHash\",\"?\")}')
if len(sha256) < 3:
    print(f'  ⚠️  Only {len(sha256)} SHA-256 fingerprints. Need 3: debug + upload + app-signing')
    print(f'      App Check requires SHA-256, not SHA-1')
" 2>/dev/null
echo ""

# 6. Debug Tokens
echo "── 6. Debug Tokens ──"
echo "  Android:"
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_ID}/apps/${ANDROID_APP_ID}/debugTokens" | python3 -c "
import sys,json
d=json.load(sys.stdin)
tokens=d.get('debugTokens',[])
print(f'    Count: {len(tokens)}')
for t in tokens:
    print(f'    - {t.get(\"displayName\",\"unnamed\")} ({t[\"name\"].split(\"/\")[-1]})')
" 2>/dev/null
echo "  iOS:"
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_ID}/apps/${IOS_APP_ID}/debugTokens" | python3 -c "
import sys,json
d=json.load(sys.stdin)
tokens=d.get('debugTokens',[])
print(f'    Count: {len(tokens)}')
for t in tokens:
    print(f'    - {t.get(\"displayName\",\"unnamed\")} ({t[\"name\"].split(\"/\")[-1]})')
" 2>/dev/null
echo ""

echo "── Audit Complete ──"
```

## Step-by-Step Setup

### Step 0: Register App for App Check

#### Option A: Via REST API / CLI (Preferred)

You can now configure App Check entirely via CLI:

**1. Set iOS Team ID (required for App Attest):**
```bash
# Check if Team ID is already set
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/iosApps/${IOS_APP_ID}" | python3 -c "
import sys,json; d=json.load(sys.stdin); print(f'teamId: {d.get(\"teamId\",\"NOT SET\")}')"

# Set Team ID if missing
curl -X PATCH -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -d '{"teamId":"YOUR_APPLE_TEAM_ID"}' \
  "https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/iosApps/${IOS_APP_ID}?updateMask=teamId"
```

**2. Configure App Attest (iOS):**
```bash
curl -X PATCH -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -d '{"tokenTtl":"3600s"}' \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_NUMBER}/apps/${IOS_APP_ID}/appAttestConfig?updateMask=tokenTtl"
```

**3. Configure DeviceCheck (iOS fallback):**
```bash
curl -X PATCH -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -d '{"tokenTtl":"3600s"}' \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_NUMBER}/apps/${IOS_APP_ID}/deviceCheckConfig?updateMask=tokenTtl"
```

#### Option B: Via Firebase Console UI

If the REST API approach doesn't fully register the app (status still shows "未註冊"):

1. Go to **Firebase Console** → your project → **App Check** → **應用程式 (Apps)** tab
2. If the app's status shows **"未註冊" (Not registered)**, click the app row to expand it
3. Select the attestation provider:
   - **iOS**: Select **App Attest** (and optionally **DeviceCheck** for fallback)
   - **Android**: Select **Play Integrity**
4. For iOS: Fill in your **Apple Team ID** (e.g. `<YOUR_TEAM_ID>` (10-character alphanumeric) — find it at [Apple Developer → Membership](https://developer.apple.com/account#MembershipDetailsCard))
5. Set the **token TTL** (default 1 hour is fine for most apps)
6. Click **Save**
7. Verify the status changes from "未註冊" to **"已註冊" (Registered)**
8. Repeat for each app (iOS, Android) that needs App Check

> **IAM Role Requirement**: This operation requires `roles/editor` or `roles/owner` on the Firebase project. `roles/firebase.viewer` or even `roles/firebaseappcheck.admin` is NOT sufficient. Grant the required role with:
> ```bash
> gcloud projects add-iam-policy-binding PROJECT_ID --member="user:EMAIL" --role="roles/editor"
> ```

### Step 1: Enable Required APIs

```bash
# Enable App Check API
gcloud services enable firebaseappcheck.googleapis.com --project=${PROJECT_ID}

# Enable Play Integrity API (required for Android attestation)
gcloud services enable playintegrity.googleapis.com --project=${PROJECT_ID}
```

### Step 2: Register Android SHA-256 Fingerprints

You need **three** SHA-256 fingerprints for Android:

| Key Type | Where to Find |
|----------|---------------|
| Debug Key | `./gradlew signingReport` in android/ |
| Upload Key | Your local release .jks file (also in signingReport) |
| App Signing Key | Google Play Console → Release → App Integrity → App Signing |

#### List Current Fingerprints

```bash
curl -s \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/androidApps/${ANDROID_APP_ID}/sha"
```

#### Add a SHA-256 Fingerprint

Convert the colon-separated format to lowercase hex (remove colons):
`64:50:0E:EF:...` → `64500eef...`

```bash
curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -d '{"shaHash":"LOWERCASE_HEX_NO_COLONS","certType":"SHA_256"}' \
  "https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/androidApps/${ANDROID_APP_ID}/sha"
```

#### Getting All 3 SHA-256 Fingerprints

> **⚠️ `./gradlew signingReport` prerequisite**: This command requires Flutter plugin cache to exist. Run `flutter pub get` first, otherwise Gradle fails with `Plugin directory does not exist`.

> **⚠️ `keytool` locale issue**: On non-English systems (e.g. Chinese locale), `keytool -list -v` outputs labels in the local language (e.g. `憑證指紋` instead of `Certificate fingerprints`). Use `grep SHA` or pipe through python instead of `grep SHA-256`.

**Recommended: Direct keytool approach (locale-agnostic, no Gradle needed)**
```bash
# Debug key — default Android debug keystore
keytool -list -v -keystore ~/.android/debug.keystore -storepass android 2>&1 | head -30

# Upload key — project-specific release keystore (check android/key.properties for path/password)
keytool -list -v -keystore android/app/upload-keystore.jks -storepass YOUR_PASSWORD 2>&1 | head -30

# Look for the SHA256 line (may appear as `SHA256:` or `SHA-256:` depending on locale)
```

**Alternative: Gradle signingReport (requires `pub get` first)**
```bash
flutter pub get  # MUST run first
cd android && ./gradlew signingReport 2>/dev/null | head -60
```

**App Signing key (from Google Play Console)**

> ⚠️ **The Google Play Developer REST API does NOT expose the App Signing Key.** Endpoints like `/appSigningKey` and `/appIntegrity` return 404. You MUST use the Play Console UI or Playwright.

**Option A: Playwright (automated)**
Navigate to `https://play.google.com/console/u/0/developers/{DEVELOPER_ID}/app-list`, then:
1. Click on your app
2. Sidebar: "Test and release" (測試與發布) → "App integrity" (應用程式完整性)
3. Click "Play App Signing" (Play 應用程式簽署) setup
4. Find "App signing key certificate" section → SHA-256 fingerprint

**Option B: Play Console UI (manual)**
Play Console → Your App → Release → Setup → App integrity → App signing key certificate → SHA-256

**Convert and register:**
```bash
# Convert colon-separated to lowercase hex:
echo "64:50:0E:EF:..." | tr -d ':' | tr 'A-F' 'a-f'
# → 64500eef...
```

### Step 3: iOS App Attest Entitlement

**CRITICAL**: The iOS app must have the App Attest entitlement. Without it, App Attest silently fails on release builds and all iOS requests are rejected when services are ENFORCED.

#### Check if entitlement exists:
```bash
grep -r "appattest" ios/ --include="*.entitlements" 2>/dev/null || echo "❌ No App Attest entitlement found!"
```

#### Add the entitlement:

**Option A**: Create/update entitlements file manually:

Create `ios/Runner/Runner.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.devicecheck.appattest-environment</key>
    <string>production</string>
</dict>
</plist>
```

Then add it to Xcode project via `xcodeproj` gem:
```ruby
require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
target = project.targets.find { |t| t.name == 'Runner' }
target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end
project.save
```

**Option B**: Use Xcode → Runner target → Signing & Capabilities → + Capability → App Attest

### Step 3b: iOS DeviceCheck Private Key (REQUIRED for fallback)

**CRITICAL**: If you use `appAttestWithDeviceCheckFallback` (recommended), you **must** upload an Apple DeviceCheck private key (.p8) to Firebase Console. Without this key, when App Attest fails (~25% of the time), the DeviceCheck fallback **also fails** because Firebase has no way to validate DeviceCheck tokens. The result: you still get the same ~25% failure rate as `appAttest` alone.

#### Create the DeviceCheck Key

1. Go to [Apple Developer Console → Keys](https://developer.apple.com/account/resources/authkeys/list)
2. Click **+** to create a new key
3. Give it a name (e.g. `Firebase DeviceCheck`)
4. Check **DeviceCheck** capability (NOT "App Store Connect API" — that is a different key type)
5. Click Continue → Register
6. Download the `.p8` file (e.g. `AuthKey_ABCD1234.p8`) — you can only download it **once**
7. Note the **Key ID** shown on the confirmation page

> **Warning**: An App Store Connect API key (.p8) does **NOT** work for DeviceCheck. You must create a key specifically with the **DeviceCheck** capability checked. They are different key types even though both produce `.p8` files.

#### Upload to Firebase via REST API

```bash
ACCESS_TOKEN=$(gcloud auth print-access-token)
PROJECT_ID="your-project-id"
IOS_APP_ID="1:xxxx:ios:xxxx"

PRIVATE_KEY=$(cat path/to/AuthKey_KEYID.p8 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
curl -s -X PATCH \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -d "{\"keyId\":\"YOUR_KEY_ID\",\"privateKey\":${PRIVATE_KEY},\"tokenTtl\":\"3600s\"}" \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_ID}/apps/${IOS_APP_ID}/deviceCheckConfig?updateMask=keyId,privateKey,tokenTtl"
```

Replace `YOUR_KEY_ID` with the Key ID from Apple Developer Console (e.g. `ABCD1234`).

#### Notes

- This key can be **reused across all iOS apps** in the same Apple Developer team — you only need one DeviceCheck key.
- **Sharing DeviceCheck Keys across apps**: Because DeviceCheck keys are scoped to Apple Developer **team**, you can reuse one key across all iOS apps in the same team. Store the `.p8` file securely (e.g., 1Password or `~/.app_store_credentials/`) and set env vars `DEVICECHECK_KEY_ID` + `DEVICECHECK_KEY_PATH` in a local `.env` (NOT committed).
- To verify the key is configured, use the audit script or check directly:
  ```bash
  curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_NUMBER}/apps/${IOS_APP_ID}/deviceCheckConfig"
  ```
  A successful response will show `keyId` and `tokenTtl` (the `privateKey` is never returned).

### Step 4: Check Provider Configs

#### Android (Play Integrity)

```bash
curl -s \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_NUMBER}/apps/${ANDROID_APP_ID}/playIntegrityConfig"
```

#### iOS (App Attest)

```bash
curl -s \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_NUMBER}/apps/${IOS_APP_ID}/appAttestConfig"
```

### Step 5: Enforce Services

#### List All Services and Their Enforcement Status

```bash
curl -s \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_NUMBER}/services"
```

#### Set Service to ENFORCED

```bash
curl -s -X PATCH \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -d '{"enforcementMode":"ENFORCED"}' \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_NUMBER}/services/SERVICE_NAME?updateMask=enforcementMode"
```

#### Common Firebase Service Names

| Service | API Name |
|---------|----------|
| Firebase AI Logic (Gemini) | `firebaseml.googleapis.com` |
| Cloud Firestore | `firestore.googleapis.com` |
| Firebase Storage | `firebasestorage.googleapis.com` |
| Authentication | `identitytoolkit.googleapis.com` |
| Data Connect | `firebasedataconnect.googleapis.com` |
| Realtime Database | `firebasedatabase.googleapis.com` |

#### Batch Enforce Multiple Services

```bash
for SERVICE in firebaseml.googleapis.com firebasestorage.googleapis.com identitytoolkit.googleapis.com; do
  echo "Enforcing $SERVICE..."
  curl -s -X PATCH \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    -H "Content-Type: application/json" \
    -d '{"enforcementMode":"ENFORCED"}' \
    "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_NUMBER}/services/${SERVICE}?updateMask=enforcementMode"
  echo ""
done
```

### Step 6: Debug Tokens

Debug tokens allow debug/CI builds to pass App Check when services are ENFORCED.

#### Generate and Register a Debug Token

```bash
# Generate a UUID token
DEBUG_TOKEN=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
echo "Debug token: $DEBUG_TOKEN"

# Register for Android
curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -d "{\"displayName\":\"Local Dev Mac\",\"token\":\"${DEBUG_TOKEN}\"}" \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_ID}/apps/${ANDROID_APP_ID}/debugTokens"

# Register for iOS
curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -d "{\"displayName\":\"Local Dev Mac\",\"token\":\"${DEBUG_TOKEN}\"}" \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_ID}/apps/${IOS_APP_ID}/debugTokens"
```

#### List Debug Tokens

```bash
curl -s \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT_ID}/apps/${ANDROID_APP_ID}/debugTokens"
```

#### Delete a Debug Token

```bash
curl -s -X DELETE \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  "https://firebaseappcheck.googleapis.com/v1/TOKEN_RESOURCE_NAME"
```

## Flutter Code Integration

> **IMPORTANT**: Check your `firebase_core` version first to determine Gen 3 vs Gen 4. The API is different.

### Gen 4 (firebase_core ^4.4.0, firebase_app_check ^0.4.x)

```yaml
dependencies:
  firebase_app_check: ^0.4.1+4  # MUST use 0.4.x+ for new provider API
```

```dart
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

// After Firebase.initializeApp()
// kDebugMode is a compile-time constant — Dart tree-shakes the entire
// debug branch from release builds, so the token never leaks into production.
await FirebaseAppCheck.instance.activate(
  // Production: hardware-backed attestation
  // Debug: debug provider with pre-registered token (named param!)
  providerAndroid: kDebugMode
      ? const AndroidDebugProvider(debugToken: 'your-registered-uuid')
      : const AndroidPlayIntegrityProvider(),
  providerApple: kDebugMode
      ? const AppleDebugProvider(debugToken: 'your-registered-uuid')
      : const AppleAppAttestWithDeviceCheckFallbackProvider(),  // MUST use fallback — appAttest alone has ~25% failure rate
);
```

### Gen 3 (firebase_core ^3.x, firebase_app_check ^0.3.x)

```yaml
dependencies:
  firebase_app_check: ^0.3.2+10
```

```dart
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

// After Firebase.initializeApp()
await FirebaseAppCheck.instance.activate(
  // Gen 3 uses enum values, not class constructors
  appleProvider: kDebugMode
      ? AppleProvider.debug
      : AppleProvider.appAttestWithDeviceCheckFallback,  // MUST use fallback — appAttest alone has ~25% failure rate
  androidProvider: kDebugMode
      ? AndroidProvider.debug
      : AndroidProvider.playIntegrity,
);
```

### Sideloaded Release Builds (USE_DEBUG_APPCHECK pattern)

> **⚠️ PlayIntegrity inherently FAILS on sideloaded release APKs** — it only works for apps installed from Google Play.
> This means `adb install app-release.apk` will always fail PlayIntegrity attestation, even with correct SHA-256 fingerprints registered.

The fix is a `--dart-define` flag that lets you control the provider independently of `kDebugMode`:

**Flutter code (Gen 3):**
```dart
// USE_DEBUG_APPCHECK=true in .env → forces debug provider even on release builds
const useDebugAppCheck = bool.fromEnvironment('USE_DEBUG_APPCHECK');
await FirebaseAppCheck.instance.activate(
  androidProvider: (kDebugMode || useDebugAppCheck)
      ? AndroidProvider.debug
      : AndroidProvider.playIntegrity,
  appleProvider: (kDebugMode || useDebugAppCheck)
      ? AppleProvider.debug
      : AppleProvider.appAttestWithDeviceCheckFallback,
);
```

**Dual .env file pattern:**

| File | Usage | `USE_DEBUG_APPCHECK` | Build Command |
|------|-------|---------------------|---------------|
| `.env` | Local dev + sideloaded release testing | `true` | `flutter build apk --release --dart-define-from-file=.env` |
| `.env.prod` | Play Store / App Store builds | absent (false) | `flutter build appbundle --release --dart-define-from-file=.env.prod` |

**Key**: Debug provider still requires a **registered debug token**. Each fresh app install generates a new token (check logcat). Register it via the Debug Tokens REST API.

> **Fresh install = new debug token**: When you uninstall + reinstall a sideloaded release APK, the debug provider generates a NEW UUID. You must register it again. The old token becomes invalid.

> **Common Gen 3 mistake**: Using `AppleProvider.appAttest` alone. It has ~25% failure rate in production. Always use `AppleProvider.appAttestWithDeviceCheckFallback`.

### OPTIONAL: Verify token in debug mode (both Gen 3 & 4)

```dart
if (kDebugMode) {
  FirebaseAppCheck.instance
      .getToken(true)
      .timeout(const Duration(seconds: 10))
      .then((token) {
        debugPrint('[AppCheck] getToken ok=${token != null}');
      })
      .catchError((Object e) {
        debugPrint('[AppCheck] getToken failed: $e');
      });
}
```

### Firebase AI Integration

#### Gen 4 (firebase_ai ^3.7.0) — MUST pass appCheck explicitly

```dart
final model = FirebaseAI.googleAI(
  appCheck: FirebaseAppCheck.instance,  // Required in Gen 4!
).generativeModel(
  model: 'gemini-2.5-flash-lite',
  // ...
);
```

Without `appCheck: FirebaseAppCheck.instance`, the SDK won't attach App Check tokens to requests and `firebasevertexai.googleapis.com` will reject them.

#### Gen 3 (firebase_ai ^2.x) — MUST also pass appCheck explicitly

```dart
// Gen 3: FirebaseAI.googleAI() ALSO accepts and REQUIRES appCheck parameter
// Without it, App Check tokens are NOT attached to AI requests
// This causes "Firebase App Check token is invalid" errors when firebaseml is ENFORCED
final model = FirebaseAI.googleAI(
  appCheck: FirebaseAppCheck.instance,  // REQUIRED! Not auto-attached in Gen 3
).generativeModel(
  model: 'gemini-2.5-flash-lite',
  // ...
);
```

> **⚠️ Critical Gen 3 Gotcha**: The `appCheck` parameter is optional in `FirebaseAI.googleAI()` — if omitted, it defaults to `null` and **no App Check token will be attached** to AI requests. When `firebaseml.googleapis.com` is ENFORCED, this causes all requests to fail with "Firebase App Check token is invalid". The `getToken()` call may succeed locally, but the token is never sent to the server.

> **NOTE**: `firebasevertexai.googleapis.com` ALWAYS requires valid App Check tokens — it cannot be unenforced via App Check service configuration (both Gen 3 and Gen 4).

## Complete Setup Checklist

### Server-Side (Firebase Console / CLI)
- [ ] **CRITICAL**: Register iOS and Android apps in Firebase Console UI (App Check → 應用程式 tab → Not just REST API!)
- [ ] `gcloud services enable firebaseappcheck.googleapis.com`
- [ ] `gcloud services enable playintegrity.googleapis.com`
- [ ] Add 3 Android SHA-256 fingerprints (debug + upload + App Signing)
- [ ] Set desired services to `ENFORCED` (especially `firebaseml.googleapis.com`)
- [ ] Register debug tokens for dev/CI environments

### Client-Side (Flutter)
- [ ] Check Firebase generation (`pubspec.lock` → `firebase_core` version) to determine Gen 3 vs Gen 4 API
- [ ] Gen 4: `firebase_app_check ^0.4.x` + new `AndroidDebugProvider()` / `AppleAppAttestProvider()` API
- [ ] Gen 3: `firebase_app_check ^0.3.x` + old `AndroidProvider.debug` / `AppleProvider.appAttest` enum API
- [ ] Gen 4 only: Pass `appCheck: FirebaseAppCheck.instance` to `FirebaseAI.googleAI()` (Gen 3 auto-attaches)
- [ ] iOS: Add `com.apple.developer.devicecheck.appattest-environment` = `production` to entitlements
- [ ] iOS: Upload Apple DeviceCheck private key (.p8) to Firebase Console (required for `appAttestWithDeviceCheckFallback`)
- [ ] **Test**: Debug build passes App Check (debug provider + registered token)
- [ ] **Test**: Release build passes App Check (Play Integrity / App Attest)

## Firebase Package Version Compatibility

All Firebase packages must be on the same generation. Mixing versions causes dependency conflicts.

| Generation | firebase_core | firebase_app_check | firebase_ai | firebase_auth | firebase_crashlytics | firebase_analytics |
|------------|--------------|-------------------|-------------|---------------|---------------------|-------------------|
| **Gen 3** (OLD) | ^3.12.x | ^0.3.x | ^2.x | ^5.x | ^4.x | ^11.x |
| **Gen 4** (CURRENT) | ^4.4.0 | ^0.4.x | ^3.7.0 | ^6.x | ^5.x | ^12.x |

> If you upgrade ONE Firebase package, you likely need to upgrade ALL of them.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| 403 `SERVICE_DISABLED` | Add `x-goog-user-project` header OR enable the API |
| iOS App Attest silently fails | Missing `com.apple.developer.devicecheck.appattest-environment` in entitlements |
| iOS App Attest 403 / `com.firebase.appCheck error 0` intermittently | **App Attest has ~25% failure rate** ([FlutterFire #10683](https://github.com/firebase/flutterfire/issues/10683)). Switch from `AppleProvider.appAttest` to `AppleProvider.appAttestWithDeviceCheckFallback`. Ensure both App Attest AND DeviceCheck providers are registered in Firebase Console |
| Wrong gcloud account | `gcloud auth list` then `gcloud config set account EMAIL` |
| Play Integrity not working in production | Missing **App Signing Key** SHA-256 (only debug/upload registered) |
| Play Integrity not working at all | `playintegrity.googleapis.com` not enabled |
| Debug build rejected | No debug token registered, or token mismatch |
| REST API uses project number | Services endpoint uses `projects/PROJECT_NUMBER`, not project ID |
| SHA-256 format wrong | Must be lowercase hex without colons |
| "Firebase App Check token is invalid" with Firebase AI | **Gen 4**: Must pass `appCheck: FirebaseAppCheck.instance` to `FirebaseAI.googleAI()` + use `^0.4.x` provider API. **Gen 3**: Ensure `activate()` is called before any AI request — tokens auto-attach. Both: `firebasevertexai.googleapis.com` ALWAYS requires valid App Check |
| Old API `AndroidProvider.debug` not working | Upgrade to `firebase_app_check ^0.4.x` and use `AndroidDebugProvider()` instead |
| `firebase_app_check ^0.4.x` won't resolve | Requires `firebase_core ^4.4.0` — upgrade all Firebase packages together |
| iOS build fails `PhaseScriptExecution` after Crashlytics 5.x upgrade | Old `[firebase_crashlytics] Upload dSYM` script phase uses `${GOOGLE_APP_ID}` build setting which Gen 4 no longer injects. **Remove** the old script phase from `project.pbxproj` — the `FlutterFire: "flutterfire upload-crashlytics-symbols"` script phase replaces it |
| `activate()` called but services still accept unauthenticated requests | Client-side `activate()` only **sends** tokens. You must **enforce** each service server-side via REST API or Firebase Console |
| App works in debug but fails in production on Android | Register the **App Signing Key** SHA-256 from Play Console (different from your local upload key) |
| SHA-1 registered but Play Integrity still fails | App Check requires **SHA-256** fingerprints, not SHA-1. Many projects have SHA-1 from google-services.json setup. Check with audit script — it shows SHA-1 vs SHA-256 counts separately |
| Release APK sideloaded via `adb install` gets 401/403 | **PlayIntegrity ONLY works for Play Store installed apps**. Use `USE_DEBUG_APPCHECK=true` dart-define + debug provider for sideloaded release testing (see Sideloaded Release Builds section) |
| Sideloaded release worked before reinstall, now fails | Each fresh install generates a **new debug token**. Check logcat for the new UUID and register it via REST API |
| Cloud Function returns 401 but Firestore/Auth work | Cloud Functions with manual `admin.appCheck().verifyToken()` enforcement reject invalid tokens independently of Firebase service enforcement. Debug provider must produce a valid token (registered in Firebase) |
| Tried Gen 4 API but classes not found | Check `pubspec.lock` for actual `firebase_app_check` version. If `0.3.x`, you're on Gen 3 — use `AndroidProvider.debug` enum, not `AndroidDebugProvider()` class |
| `gradlew signingReport` fails with "Plugin directory does not exist" | Run `flutter pub get` first — Gradle needs the Flutter plugin cache to resolve the project |
| `keytool` SHA-256 grep returns empty on Chinese/Japanese locale | `keytool -list -v` outputs localized labels (e.g. `憑證指紋` not `Certificate fingerprints`). Use `head -30` instead of `grep SHA-256`, or pipe through python |
| Enforcement fails with `serviceusage.serviceUsageConsumer` permission error | `gcloud config get-value account` may show a different account than expected. Some API calls (SHA registration, provider config) succeed with any project member, but enforcement requires Owner/Editor. Run `gcloud config set account CORRECT_EMAIL` before enforcing |
| DeviceCheck fallback still fails after configuring provider | **Missing Apple DeviceCheck private key** in Firebase Console. Must create a key with DeviceCheck capability in Apple Developer Console → Keys, download .p8, and upload via REST API. ASC API keys do NOT have DeviceCheck capability. |
| Entitlements file created but Xcode doesn't use it | Must add `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` to all Runner build configs in `project.pbxproj`. Use Python regex or `xcodeproj` gem — search for `PRODUCT_BUNDLE_IDENTIFIER = com.your.app;` as anchor point |
| "App attestation failed" even though REST API configs exist | **App not registered in Firebase Console UI**. REST API `appAttestConfig`/`deviceCheckConfig` create configs but do NOT register the app. Must go to Firebase Console → App Check → 應用程式 → expand app → select provider → fill Team ID → Save. Requires `roles/editor` IAM role. |
