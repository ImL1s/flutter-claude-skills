---
name: release-app
description: >
  Global release skill for deploying Flutter apps to TestFlight, App Store, and Google Play.
  Use when user says "release", "deploy", "上架", "發版", "push to TF/store",
  or wants to publish an app update. Handles version bump, localized changelogs,
  build, and upload. Supports iOS (TestFlight/App Store) and Android (Play Store).
---

# Release App

Automated Flutter release workflow: version bump → changelogs → build → deploy.

## Execution Flow

### 0. Pre-flight

```bash
# Check current version
grep '^version:' pubspec.yaml

# Check uncommitted changes
git status

# Check project CLAUDE.md for project-specific deploy commands
# (fastlane lanes, build scripts, --dart-define-from-file, etc.)
```

Confirm with user:
- **Target**: iOS (App Store), Android, or all? **預設是雙平台 production**。只有用戶明確說 TestFlight/internal 才走測試軌道
- **Version bump type**: patch (1.0.4→1.0.5), minor (1.0→1.1), major (1→2)?
- Build number always increments (+7→+8)

> **⚠️ HARD RULE**: 預設一律 production track。不得自行降級到 TestFlight / internal testing / beta。

### 1. Bump Version

Edit `pubspec.yaml` `version:` field. Example: `1.0.4+7` → `1.0.5+8`

### 2. Write Changelogs (All Locales)

**MANDATORY**: Write for EVERY supported locale in the metadata directory.

#### Discover locales automatically:
```bash
# Android locales
ls android/fastlane/metadata/android/

# iOS locales
ls ios/fastlane/metadata/
```

#### Android: `android/fastlane/metadata/android/<locale>/changelogs/<versionCode>.txt`
- Max **500 chars** per file (fastlane rejects longer)

#### iOS: `ios/fastlane/metadata/<locale>/release_notes.txt`
- Max **4000 chars** per file

#### Content Rules (STRICT)
- Write from END USER perspective. Focus on value, not implementation.
- Use emojis sparingly for readability.
- NEVER include technical details, API changes, internal architecture.
- iOS: NEVER mention "Android", "Google Play" (Apple Guideline 2.3.10 rejection).
- Android: NEVER mention "iOS", "App Store", prices, or promotions.
- If app uses third-party AI (Gemini, OpenAI), description.txt must disclose data usage.

> **⚠️ Guideline 2.3.10 applies to the ENTIRE app binary, not just metadata.**
> L10n/ARB strings shown to the user must also be platform-specific.
> See "Cross-Platform Store Compliance" section below.

### 3. Commit & Push

```bash
git add pubspec.yaml android/fastlane/metadata/ ios/fastlane/metadata/
git commit -m "release: vX.Y.Z+N — <brief description>"
git push
```

### 4. Build & Deploy

Check project's CLAUDE.md / Makefile / Fastfile for exact commands. Below are common patterns.

#### iOS → TestFlight (Direct, No Draft)

```bash
# Option A: fastlane beta (recommended — builds + signs + uploads)
cd ios && fastlane beta

# Option B: Build separately, then upload
fvm flutter build ipa --release --dart-define-from-file=.env
cd ios && fastlane upload_only

# Option C: Manual upload (if fastlane issues)
# Note: xcrun altool is fully deprecated since Nov 2023.
# Use Transporter app or xcrun notarytool for notarization.
# For App Store / TestFlight uploads, use Apple's Transporter CLI:
/usr/bin/xcrun iTMSTransporter -m upload \
  -f "build/ios/ipa/<AppName>.ipa" \
  -apiKey "$APP_STORE_CONNECT_KEY_ID" \
  -apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
# Alternative: Use the Transporter app from Mac App Store (GUI)
```

TestFlight builds are immediately available to internal testers after Apple processing (~10-30 min).

#### iOS → App Store

```bash
cd ios && fastlane release
```

#### Android → Production (Direct, NOT Draft)

```bash
# Build
fvm flutter build appbundle --release --dart-define-from-file=.env

# Upload with metadata + changelogs (completed status)
cd android && fastlane release
```

> **CRITICAL**: Android release lane MUST use `release_status: "completed"`.
> Draft requires manual Console action and same version_code can't be re-uploaded.
> Recovery if accidentally used draft:
> ```bash
> fastlane run upload_to_play_store track:production version_code:<CODE> \
>   release_status:completed skip_upload_aab:true skip_upload_apk:true \
>   skip_upload_images:true skip_upload_screenshots:true \
>   skip_upload_metadata:true skip_upload_changelogs:true
> ```

#### Android → Internal Testing (First Release / Testing)
```bash
cd android && fastlane upload_internal
```

### 5. Cross-Platform Store Compliance Scan（MANDATORY — 每次 iOS release 前必跑）

Apple Guideline 2.3.10 rejects apps that mention competing platforms in the **binary** (not just metadata).
Apple Guideline 3.1.2(c) requires EULA link in description for subscription apps.

#### 5a. Binary text scan — find cross-platform references in app code
```bash
# iOS build: ensure NO "Google Play" text appears in non-Android-only code paths
# Check l10n strings (ARB files) — only paywallAutoRenewNoticeAndroid should contain "Google Play"
grep -rn "Google Play" lib/l10n/ --include="*.arb" | grep -v "Android"
# ^ Should return EMPTY. If not, those strings leak onto iOS.

# Check Dart source (non-generated) for unguarded Google Play references
grep -rn "Google Play\|play.google" lib/ --include="*.dart" | grep -v "_localizations" | grep -v "app_localizations.dart" | grep -v "Platform.isIOS\|Platform.isAndroid\|// "
# ^ Should return EMPTY.

# Reverse check: ensure no "iPhone"/"Apple" text leaks to Android
grep -rn "iPhone\|Apple ID\|App Store" lib/l10n/ --include="*.arb" | grep -v "Ios"
# ^ Should return EMPTY.
```

#### 5b. Platform-specific l10n pattern for store management text

Subscription auto-renew notices and store management instructions MUST use platform-specific ARB keys:
```
// ❌ BAD — rejected by Apple
"paywallAutoRenewNotice": "... iPhone Settings > Apple ID > Subscriptions or Google Play ..."

// ✅ GOOD — platform-specific keys
"paywallAutoRenewNoticeIos": "... iPhone Settings > Apple ID > Subscriptions."
"paywallAutoRenewNoticeAndroid": "... Google Play > Subscriptions."
```

In Dart code, select with `Platform.isIOS`:
```dart
Platform.isIOS ? l10n.paywallAutoRenewNoticeIos : l10n.paywallAutoRenewNoticeAndroid
```

Same pattern applies to any store URLs:
```dart
Platform.isIOS
    ? 'https://apps.apple.com/account/subscriptions'
    : 'https://play.google.com/store/account/subscriptions'
```

#### 5c. iOS description.txt EULA requirement (Guideline 3.1.2(c))

For apps with auto-renewable subscriptions, **each iOS locale's `description.txt` MUST end with**:
```
---

Terms of Use (EULA): https://example.com/terms.html
Privacy Policy: https://example.com/privacy.html
```

Verify:
```bash
for locale in $(ls ios/fastlane/metadata/); do
  if grep -q "EULA\|Terms of Use\|使用條款" "ios/fastlane/metadata/$locale/description.txt" 2>/dev/null; then
    echo "✓ $locale: EULA link present"
  else
    echo "✗ $locale: MISSING EULA link — will be rejected!"
  fi
done
```

### 6. Metadata 完整性驗證（MANDATORY — 不可跳過）

在宣布完成前，**必須逐項驗證**：

#### iOS metadata（每個 locale 都要檢查）
```bash
# 列出所有 locale 目錄
ls ios/fastlane/metadata/

# 每個 locale 必須包含：
for locale in $(ls ios/fastlane/metadata/); do
  echo "=== $locale ==="
  for f in description.txt keywords.txt support_url.txt release_notes.txt; do
    if [ -f "ios/fastlane/metadata/$locale/$f" ]; then
      chars=$(wc -c < "ios/fastlane/metadata/$locale/$f")
      echo "  ✓ $f ($chars bytes)"
    else
      echo "  ✗ MISSING: $f"
    fi
  done
done
```

#### Android metadata（每個 locale 都要檢查）
```bash
for locale in $(ls android/fastlane/metadata/android/); do
  echo "=== $locale ==="
  for f in full_description.txt short_description.txt title.txt; do
    if [ -f "android/fastlane/metadata/android/$locale/$f" ]; then
      chars=$(wc -c < "android/fastlane/metadata/android/$locale/$f")
      echo "  ✓ $f ($chars bytes)"
    else
      echo "  ✗ MISSING: $f"
    fi
  done
  # changelog
  ls android/fastlane/metadata/android/$locale/changelogs/ 2>/dev/null || echo "  ✗ MISSING: changelogs/"
done
```

> **缺少任何檔案 → 補齊後才能繼續。不得跳過。**

### 7. Upload 驗證

- fastlane output ends with "fastlane.tools finished successfully"
- iOS: App Store Connect → check build processing status
- Android: Google Play Console → Release dashboard → 確認是 **production** track
- Check email for Apple ITMS warnings (builds silently rejected if issues)

### 8. 完成宣言 Checklist

**以下全部打勾才能說「發布完成」**：

- [ ] 版本號已 bump 且 commit + push
- [ ] iOS build 已上傳到 App Store Connect
- [ ] Android appbundle 已上傳到 Google Play **production** track
- [ ] 所有 locale 的 metadata（description, keywords, release notes）已上傳
- [ ] 所有 locale 的 changelogs 已建立
- [ ] 兩個商店的提交狀態已確認（processing / pending review）
- [ ] git tag 已建立（`vX.Y.Z+N`）

## macOS 部署

完整流程 (6 步):
1. `flutter build macos --release` (ad-hoc 簽名)
2. 導出 App bundle
3. 嵌入 provisioning profile (`embedded.provisionprofile`)
4. 重新簽名 (Apple Distribution + Mac App Store entitlements)
5. `productbuild` PKG (3rd Party Mac Developer Installer)
6. 上傳至 App Store Connect（使用 Transporter CLI 或 fastlane，`xcrun altool` 已於 2023/11 完全廢棄）

```bash
export TEAM_ID="YOUR_TEAM_ID"
export API_KEY="YOUR_API_KEY_ID"
export API_ISSUER="YOUR_ISSUER_ID"

./scripts/macos_appstore_upload.sh
```

### 為什麼不用 xcodebuild archive?

Flutter 專案的 `CODE_SIGN_IDENTITY = "-"` (project-level) 導致 ad-hoc 簽名。
如果在命令列覆蓋為 `Apple Distribution`，CocoaPods targets 會因為 "conflicting provisioning settings" 而編譯失敗。
所以本腳本: 先用 flutter build (ad-hoc)，再手動重新簽名。

### 關鍵步驟說明

**Provisioning Profile** (自動處理):
- 腳本自動搜尋本地 `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` 中的 `.provisionprofile`
- 找不到時透過 App Store Connect API 自動建立 `MAC_APP_STORE` 類型 profile
- 需要 `python3` + `PyJWT` + `requests`

**Entitlements** (ITMS-90886 修復):
- Mac App Store 要求 entitlements 包含 `com.apple.application-identifier` 和 `com.apple.developer.team-identifier`
- 腳本自動合併專案的 `Release.entitlements` + 這兩個必要 key
- 缺少這些會導致上傳成功但 Apple 回報 ITMS-90886，build 無法用於 TestFlight

**簽名順序**:
- Frameworks/dylibs 先簽 (不需 app-specific entitlements)
- Helpers 接著簽
- 主 App bundle 最後簽 (使用完整 Mac App Store entitlements)
- 使用 SHA-1 hash 避免重複證書的 "ambiguous" 錯誤

### 可選環境變數

| 變數 | 說明 | 預設 |
|------|------|------|
| `USE_FVM` | 設為 "1" 使用 fvm | 自動偵測 `.fvmrc` |
| `SKIP_BUILD` | 設為 "1" 跳過構建 | 0 |
| `SIGN_IDENTITY` | 簽名身份 SHA-1 hash | 自動偵測 |
| `INSTALLER_IDENTITY` | Installer 簽名身份 | 自動偵測 |
| `ENTITLEMENTS` | 基礎 entitlements 路徑 | `macos/Runner/Release.entitlements` |
| `BUNDLE_ID` | Bundle ID | 從 Info.plist 讀取 |
| `PROVISION_PROFILE` | 手動指定 profile 路徑 | 自動偵測/建立 |
| `BUMP_BUILD` | 設為 "1" 自動遞增 build number | 0 |
| `API_KEY_PATH` | API Key (.p8) 路徑 | `~/.app_store_credentials/AuthKey_*.p8` |

## Web (Firebase Hosting) 部署

```bash
./scripts/web_firebase_deploy.sh [site-id]
```

需要：firebase CLI 登入、firebase.json 設定

## Xcode 26.x exportArchive Bug

看到此錯誤時：
```
error: exportArchive exportOptionsPlist error for key "method" expected one {}
```

**不要嘗試修復 plist 格式**。使用 `./scripts/ios_appstore_upload.sh` 或 `./scripts/macos_appstore_upload.sh` 繞過。

## 部署腳本

```bash
# 全平台一次部署
./scripts/deploy_all.sh

# 單平台
./scripts/ios_appstore_upload.sh
./scripts/macos_appstore_upload.sh
./scripts/android_playstore_upload.sh [track]
./scripts/web_firebase_deploy.sh [site]
```

## 取得憑證資訊

```bash
# Distribution 證書 hash
security find-identity -p codesigning -v | grep "Apple Distribution"

# Provisioning profiles
ls ~/Library/MobileDevice/Provisioning\ Profiles/

# 查看 profile 內容
security cms -D -i ~/Library/MobileDevice/Provisioning\ Profiles/YOUR.mobileprovision
```

## Common Issues

| Issue | Fix |
|-------|-----|
| iOS signing fails | Add `--export-options-plist=ios/ExportOptions.plist` |
| iOS build number mismatch with fastlane | Build with `fvm flutter build ipa --build-number=N` first |
| Android "draft app" error | First release → `upload_internal` not `release` |
| Changelog > 500 chars (Android) | Trim each locale to 500 chars |
| `No value found for 'key_id'` | Load creds: `source ~/.app_store_credentials/.env` |
| patrol in release build (ITMS-90338) | Comment out `patrol` in pubspec.yaml, re-run `pod install` |
| Xcode 16 Info.plist errors | Fix in Podfile `post_install` hook |
| Build uploads but never appears | Check Apple email for ITMS warnings, fix & re-upload |
| `objective_c.framework` IOSSIMULATOR tag | Use `vtool -set-build-version ios` to patch |
| Xcode 26.x exportArchive plist error | Use `./scripts/ios_appstore_upload.sh` to bypass |
| CocoaPods `source: unbound variable` | Add `local source=""` at top of `install_framework()` in `Pods-Runner-frameworks.sh` |
| **REJECTED 版本 `whatsNew` 無法編輯** | 409 STATE_ERROR — 用 `fastlane deliver` 上傳（它內建 workaround） |
| **"review submission already in progress"** | 用 API 查 `reviewSubmissions?filter[state]=READY_FOR_REVIEW`，reuse 既有 submission 加入 version item 後 submit |
| **僵屍 reviewSubmissions 無法刪除** | 不要用 API 亂建 `reviewSubmissions`！先查有無既有可用的 |
| **REJECTED 後如何 resubmit** | 參見 `store-publishing-automation` skill 的 REJECTED Resubmission Workflow 段落 |

## Related skills

- **`release-preflight`** — verify before submission. Run preflight checks first to catch signing/version issues before upload.
- **`store-console-playbooks`** — review store listing before using release-app. Verify screenshots, description, release notes are ready.
- **`mobile-store-upload-cli`** — track submission status after release-app submits the build. Monitor review progress and handle rejections.

