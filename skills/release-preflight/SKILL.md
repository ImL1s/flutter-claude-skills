---
name: release-preflight
description: Flutter 雙平台發版前的 pre-flight 檢查清單，確保 build number、signing、fastlane config、store metadata 都正確再開始 build
---

# Release Pre-flight Checklist

在執行任何 build 或 upload 之前，逐項檢查以下項目。任何一項失敗都必須先修好再繼續。

## 共用檢查

1. **Version & Build Number**
   - 確認 `pubspec.yaml` 的 version 已 bump
   - 確認 build number 沒有與已上傳的版本重複
   - iOS: `agvtool what-version` 檢查當前 build number
   - Android: 檢查 `pubspec.yaml` 的 build number

2. **Flutter 環境**
   - `fvm flutter doctor` 確認環境正常
   - `fvm flutter pub get` 確認依賴最新
   - `dart analyze` 確認沒有 error
   - 如果專案使用 FlutterFire，確認 `flutterfire` CLI 在 PATH 中

3. **測試**
   - `fvm flutter test` 跑完整測試
   - 全部通過才能繼續，不允許帶著失敗的測試發版

4. **模擬器實測**
   - 使用 mobile-mcp 在模擬器上啟動 app
   - 截圖驗證關鍵頁面（首頁、主要功能頁）正常顯示
   - 特別注意 API 回應結構是否與 UI 預期一致
   - ⚠️ 此步驟不可跳過（v1.4.10+52 事件：跳過模擬器測試導致 API 結構變動未被發現，需追加 hotfix）

## 瀏覽器操作限制

- Store console 操作必須由**單一 agent 順序執行**，不可讓多個 agent 平行操作瀏覽器
- 純 API（curl/CLI）的任務才能平行
- 操作 Dashboard 前必須確認當前專案/app 名稱正確

## iOS 專用檢查

4. **CocoaPods**
   - `pod repo update` 更新本地 spec repo
   - `cd ios && pod install` 確認 pods 安裝正確

5. **Signing**
   - 確認 signing certificate 有效（未過期）
   - 確認 provisioning profile 正確
   - `security find-identity -v -p codesigning` 列出可用證書

6. **Fastlane (iOS)**
   - 確認 `ios/Gemfile` 存在
   - `cd ios && bundle exec fastlane deliver --help` 確認 fastlane 可用
   - 確認 App Store Connect API key 或 session 有效

## Android 專用檢查

7. **App 狀態**
   - ⚠️ 確認 app 不是 draft 狀態（draft app 無法發到 beta/production）
   - 如果是 draft，警告用戶需先在 Play Console 手動完成初始設定

8. **Signing**
   - 確認 `key.properties` 或 signing config 存在且正確
   - 確認 keystore 檔案存在且密碼正確

9. **Fastlane (Android)**
   - 確認 `android/Gemfile` 存在
   - 確認 `supply` 的 `track` 設為正確值（production/beta/internal）
   - 確認 `release_status` 設為 `completed`（不是 `draft`）
   - 確認 Google Play service account JSON key 存在且有效

10. **Permission Declarations**
    - 確認 Play Console 已宣告所有必要的 permission（如 AD_ID）
    - 確認 Data Safety section 已填寫完整

## Store Metadata 檢查

11. **所有 locale 的 metadata**
    - description、keywords、support_url、release notes 都已準備
    - 截圖已上傳且符合各平台規格要求

## 完成後

- 所有項目通過 → 回報 "Pre-flight 全部通過，準備開始 build"
- 任何項目失敗 → 列出失敗項目和修復建議，不要跳過繼續 build

## Related skills

- **`flutter-verify`** — after preflight passes, verify the release build on real devices (not emulator). Catch platform-specific crashes.
- **`store-console-playbooks`** — review store listing (screenshots, description, release notes) after preflight succeeds.
- **`release-app`** — submit the build to App Store/Play Store after all checks pass.