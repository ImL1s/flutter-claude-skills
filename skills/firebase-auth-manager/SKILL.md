---
name: firebase-auth-manager
description: Use when managing Firebase Authentication sign-in providers, authorized domains, or auth configuration via CLI. Covers enabling Apple/Google/GitHub/Microsoft providers, listing provider status, managing authorized domains, and querying auth config using Google Identity Toolkit Admin API v2. Also includes Apple Sign-In debugging for invalid-credential errors and Android Google Sign-In setup (SHA-1 fingerprints, OAuth clients, google-services.json, Credential Manager debugging).
---

# Firebase Auth Manager

Manage Firebase Authentication configuration via the Identity Toolkit Admin API v2. No Firebase Console UI needed.

## Prerequisites

- `gcloud` CLI authenticated (`gcloud auth login`)
- Editor/Owner role on the Firebase project
- Know your Firebase Project ID
- **Billing must be linked** to the GCP project (required for Identity Platform initialization)

## First-Time Initialization (CRITICAL)

If the project has **never had Firebase Auth enabled**, all Admin API v2 calls will return `CONFIGURATION_NOT_FOUND`. You must initialize Identity Platform first:

### Step 1: Enable the Identity Toolkit API
```bash
gcloud services enable identitytoolkit.googleapis.com --project=${PROJECT_ID}
```

### Step 2: Ensure Billing is Linked
```bash
# Check billing status
gcloud billing projects describe ${PROJECT_ID}

# If billingEnabled: false, link a billing account
gcloud billing accounts list
gcloud billing projects link ${PROJECT_ID} --billing-account=BILLING_ACCOUNT_ID
```

> **Note**: Firebase billing accounts have a 5-project quota. If quota is exceeded, unlink an unused project first:
> ```bash
> gcloud billing projects list --billing-account=BILLING_ACCOUNT_ID
> gcloud billing projects unlink UNUSED_PROJECT_ID
> ```

### Step 3: Initialize Identity Platform
```bash
curl -s -X POST \
  "https://identitytoolkit.googleapis.com/v2/projects/${PROJECT_ID}/identityPlatform:initializeAuth" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -d '{}'
```

A successful response is `{}`. After this, all Admin API v2 endpoints will work.

### Step 4: Enable Anonymous Auth
```bash
curl -s -X PATCH \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT_ID}/config?updateMask=signIn.anonymous.enabled" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -d '{"signIn":{"anonymous":{"enabled":true}}}'
```

## API Base

```
https://identitytoolkit.googleapis.com/admin/v2/projects/{PROJECT_ID}
```

All requests need:
```bash
ACCESS_TOKEN=$(gcloud auth print-access-token)
-H "Authorization: Bearer $ACCESS_TOKEN"
-H "x-goog-user-project: {PROJECT_ID}"
```

## Quick Reference

### List All Sign-In Providers

```bash
curl -s -X GET \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT_ID}/defaultSupportedIdpConfigs" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" | python3 -m json.tool
```

### Enable a Provider

| Provider | idpId | clientId | clientSecret |
|----------|-------|----------|--------------|
| Apple (iOS-only) | `apple.com` | **Bundle ID** (e.g. `com.example.app`) | `""` (empty) |
| Apple (cross-platform) | `apple.com` | Services ID | Needs Team ID + Key ID + .p8 |
| Google | `google.com` | OAuth client ID | OAuth client secret |
| GitHub | `github.com` | OAuth App client ID | OAuth App secret |
| Microsoft | `microsoft.com` | Azure App client ID | Azure App secret |

**Apple (iOS-only):**
```bash
curl -s -X POST \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT_ID}/defaultSupportedIdpConfigs?idpId=apple.com" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -d '{"enabled": true, "clientId": "YOUR_BUNDLE_ID", "clientSecret": ""}'
```

**Google / GitHub / others:**
```bash
curl -s -X POST \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT_ID}/defaultSupportedIdpConfigs?idpId=google.com" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -d '{"enabled": true, "clientId": "CLIENT_ID", "clientSecret": "CLIENT_SECRET"}'
```

### Update a Provider (e.g. change clientId)

```bash
curl -s -X PATCH \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT_ID}/defaultSupportedIdpConfigs/apple.com?updateMask=clientId" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -d '{"clientId": "NEW_CLIENT_ID"}'
```

### Disable a Provider

```bash
curl -s -X PATCH \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT_ID}/defaultSupportedIdpConfigs/apple.com?updateMask=enabled" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -d '{"enabled": false}'
```

### Get Auth Config (domains, email settings, MFA)

```bash
curl -s -X GET \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT_ID}/config" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: ${PROJECT_ID}" | python3 -m json.tool
```

### Add Authorized Domain

```bash
curl -s -X PATCH \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT_ID}/config?updateMask=authorizedDomains" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -d '{"authorizedDomains": ["localhost", "example.firebaseapp.com", "example.web.app", "yourdomain.com"]}'
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| `CONFIGURATION_NOT_FOUND` | Firebase Auth not initialized. Follow **First-Time Initialization** section above |
| 403 quota project error | Add `-H "x-goog-user-project: ${PROJECT_ID}"` header |
| Apple `clientId` set to Services ID | iOS-only must use **bundle ID**, not Services ID. Services ID is for web/Android only |
| Provider already exists (409) | Use PATCH to update instead of POST to create |
| Wrong gcloud account | `gcloud auth list` to check, `gcloud config set account EMAIL` to switch |
| `BILLING_NOT_ENABLED` on `initializeAuth` | Link a billing account to the project first |
| Google `clientId: "auto"` causes `Error code:40` | When using `signInWithCredential` (not `signInWithProvider`), the Google provider MUST have the actual Web OAuth client ID, not `"auto"`. Use PATCH with `updateMask=clientId` to set it. Find the Web client ID in `google-services.json` → `oauth_client` → `client_type: 3` entry. |

## Apple Sign-In: iOS-only vs Cross-Platform

| Config | iOS-only | Cross-platform (iOS + Web/Android) |
|--------|----------|-----------------------------------|
| `clientId` | **Bundle ID** (`com.example.app`) | Services ID (`com.example.app.service`) |
| `clientSecret` | `""` (empty) | JWT from .p8 key |
| Team ID / Key ID / .p8 | Not needed | Required |
| Apple Services ID | Not needed | Must create in Apple Developer Console |
| Callback URL | Not needed | `https://{project}.firebaseapp.com/__/auth/handler` |

## Apple Sign-In Checklist (iOS)

1. **Firebase**: Enable `apple.com` provider with `clientId` = **bundle ID** (this skill)
2. **Apple Developer Console**: App ID has "Sign in with Apple" capability
3. **Xcode**: `Runner.entitlements` has `com.apple.developer.applesignin`
4. **Provisioning Profile**: Regenerated after adding capability
5. **Flutter code**: `OAuthProvider('apple.com').credential()` must include **both**:
   - `idToken: appleCredential.identityToken`
   - `rawNonce: rawNonce`
   - `accessToken: appleCredential.authorizationCode` (CRITICAL - without this → `invalid-credential`)

## Android Google Sign-In Setup (SHA-1 + OAuth)

> **CRITICAL**: Android Google Sign-In (including `google_sign_in` v7+ with Credential Manager) requires SHA-1 fingerprints registered in Firebase AND matching OAuth clients in `google-services.json`. Missing any SHA-1 causes silent failures.

### Required SHA-1 Fingerprints (ALL THREE)

| SHA-1 Source | How to Get | When Used |
|-------------|-----------|-----------|
| **Debug keystore** | `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android` | `flutter run` / debug builds |
| **Release keystore** (upload key) | `keytool -list -v -keystore /path/to/release.jks -alias YOUR_ALIAS` | Locally signed release builds |
| **Play Store App Signing Key** | Play Console → App Integrity → App signing key certificate → SHA-1 | APKs downloaded from Play Store |

> **Most common mistake**: Only registering the debug SHA-1, then Google Sign-In fails for Play Store builds. The Play Store re-signs your AAB with Google's own key, so Firebase must know that key's SHA-1 too.

### Firebase CLI Commands

```bash
# Set variables
APP_ID="1:XXXXXXXXXX:android:YYYYYYYY"
PROJECT="your-project-id"

# 1. Add SHA-1 fingerprints (repeat for each SHA-1)
firebase apps:android:sha:create $APP_ID <SHA1_HEX_NO_COLONS> --project $PROJECT

# 2. List all registered SHA-1s
firebase apps:android:sha:list $APP_ID --project $PROJECT

# 3. Download updated google-services.json
firebase apps:sdkconfig ANDROID $APP_ID --project $PROJECT

# 4. Copy output JSON to android/app/google-services.json
```

> **IMPORTANT**: After adding SHA-1 via CLI, you MUST re-download `google-services.json` — Firebase auto-creates new OAuth clients for each SHA-1, and these must be in the config file.

### google-services.json Structure for Google Sign-In

```json
{
  "client": [{
    "oauth_client": [
      {
        "client_id": "...-debug.apps.googleusercontent.com",
        "client_type": 1,
        "android_info": {
          "package_name": "com.example.app",
          "certificate_hash": "<debug_sha1_lowercase_no_colons>"
        }
      },
      {
        "client_id": "...-release.apps.googleusercontent.com",
        "client_type": 1,
        "android_info": {
          "package_name": "com.example.app",
          "certificate_hash": "<release_sha1_lowercase_no_colons>"
        }
      },
      {
        "client_id": "...-playstore.apps.googleusercontent.com",
        "client_type": 1,
        "android_info": {
          "package_name": "com.example.app",
          "certificate_hash": "<playstore_signing_sha1_lowercase_no_colons>"
        }
      }
    ],
    "services": {
      "appinvite_service": {
        "other_platform_oauth_client": [
          {
            "client_id": "...-web.apps.googleusercontent.com",
            "client_type": 3
          }
        ]
      }
    }
  }]
}
```

**Key fields:**
- `oauth_client` with `client_type: 1` = Android OAuth clients (one per SHA-1)
- `other_platform_oauth_client` with `client_type: 3` = Web client → becomes `default_web_client_id` → used as `serverClientId`
- If `oauth_client` is `[]` (empty), Google Sign-In will **silently fail** (appears as "user cancelled")

### Play Store App Signing Key SHA-1

The Play Store App Signing Key SHA-1 is **NOT available via Google Play Developer API**. You must get it from the Play Console UI:

1. Navigate to: `https://play.google.com/console/u/0/developers/<DEV_ID>/app/<APP_ID>/keymanagement`
2. Or: Play Console → your app → Setup → App Integrity → App signing
3. Copy the **SHA-1 certificate fingerprint** under "App signing key certificate"
4. **NOT** the one under "Upload key certificate" (that's your release keystore)

### Debugging Android Google Sign-In

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| `CredManProvService: GetCredentialResponse error` caught as "user cancelled" | SHA-1 mismatch — no matching OAuth client for the signing key | Register ALL 3 SHA-1s in Firebase, re-download `google-services.json` |
| `oauth_client: []` in google-services.json | No SHA-1 fingerprints registered for this Android app | Add SHA-1 via `firebase apps:android:sha:create` |
| Works in debug, fails in release | Release keystore SHA-1 not registered | Add release keystore SHA-1 |
| Works locally, fails from Play Store | Play Store App Signing Key SHA-1 not registered | Get from Play Console App Signing page, add to Firebase |
| `serverClientId must be provided` | Missing `other_platform_oauth_client` with `client_type: 3` | Ensure Web client exists in GCP credentials |
| Error code 10 / `DEVELOPER_ERROR` | SHA-1 mismatch (legacy google_sign_in) | Same fix — register all SHA-1s |

### Android Google Sign-In Checklist

1. **Firebase Console/CLI**: Register ALL 3 SHA-1 fingerprints (debug, release, Play Store signing)
2. **google-services.json**: Re-download after adding SHA-1s, verify `oauth_client` is NOT empty
3. **GCP Console**: Ensure Web OAuth client exists (auto-created, provides `serverClientId`)
4. **Flutter code**: `serverClientId` should match the `client_type: 3` client ID
5. **Rebuild app**: `flutter clean && flutter run` — google-services.json is baked into the build
6. **Support email**: Set in Firebase Console → Project Settings → General (required for Google Sign-In)

## Debugging `invalid-credential`

`[firebase_auth/invalid-credential] Invalid OAuth response from apple.com`:

1. **Missing `accessToken`**: Firebase needs `authorizationCode` from Apple. Pass it as `accessToken` in `OAuthProvider.credential()`
2. **Wrong `clientId`**: iOS tokens have `aud` = bundle ID. If Firebase `clientId` is Services ID, audience won't match
3. **Provider not enabled**: Verify with List Providers API above

## Related skills

- **`firebase-flutter-setup`** — initialize Firebase services first. Firebase-auth-manager builds the sign-in UX on top.
- **`flutter-verify`** — after implementing auth, verify sign-in flows work end-to-end on real devices (email/password, social login, token refresh).
