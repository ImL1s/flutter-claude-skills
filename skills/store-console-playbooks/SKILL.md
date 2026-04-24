---
name: store-console-playbooks
description: App Store Connect 和 Google Play Console 的瀏覽器自動化導航路徑，減少 browser automation 反覆摸索
---

# Store Console Browser Automation Playbooks

使用 browser automation 操作 App Store Connect 和 Google Play Console 時，參考以下標準導航路徑。

## 使用前提

- **單一 Agent 限制**：瀏覽器操作一次只能由一個 agent 執行。不可讓多個 agent 或 team workers 同時操作 store console（曾因多 agent 平行操作導致在錯誤專案下建立資源）
- 開始前先用 `mcp__claude-in-chrome__tabs_context_mcp` 確認當前 tab 狀態
- 優先開新 tab 操作，不要復用用戶正在用的 tab
- 操作前截圖確認頁面狀態，操作後截圖驗證結果

---

## App Store Connect

### 提交新版本審核

1. 導航到 `appstoreconnect.apple.com` → 登入
2. 選擇目標 App → "App Store" tab
3. 左側 sidebar 點擊目標版本（或建立新版本）
4. 填寫必要欄位：
   - "What's New in This Version" — 所有支援語系
   - Build — 選擇已上傳的 build（等 Processing 完成）
   - Screenshots — 確認每個裝置尺寸都有截圖
   - App Review Information — 確認聯絡資訊正確
5. 點擊 "Add for Review"
6. 點擊 "Submit to App Review"
7. **驗證**：確認狀態變為 "Waiting for Review"

### 常見失敗點

- Build 還在 Processing — 等待 5-15 分鐘後重新整理
- 缺少某語系的 release notes — 需逐一填寫
- 截圖尺寸不符 — 確認使用正確的裝置截圖

---

## Google Play Console

### 發布到 Production Track

1. 導航到 `play.google.com/console` → 登入
2. 選擇目標 App
3. 左側選單 "Release" → "Production"
4. 點擊 "Create new release"
5. 上傳 AAB 或選擇已上傳的 bundle
6. 填寫 Release notes（所有語系）
7. 點擊 "Review release"
8. 確認無 error/warning → "Start rollout to Production"
9. **驗證**：確認版本出現在 Production track 且狀態為 "In review" 或 "Available"

### ⚠️ Draft App 限制

- 如果 App 還在 draft 狀態，**無法直接發到任何 track**
- 必須先完成：
  1. App content → Content ratings questionnaire
  2. App content → Target audience
  3. App content → News app / Government app declarations
  4. Store listing → 完整填寫 description、screenshots
  5. Pricing and availability
- 全部完成後才能創建 release

### Permission Declarations (AD_ID)

1. 左側選單 "App content" → "App content"
2. 找到 "Advertising ID" section
3. 確認已宣告 AD_ID 使用目的
4. 如果使用 AdMob，勾選 "Advertising" 和 "Analytics"

### Data Safety

1. "App content" → "Data safety"
2. 逐項填寫資料收集和使用聲明
3. 常見必填項：Device identifiers、Crash logs、App interactions

---

## Firebase Console

### App Check 設定驗證

1. 導航到 `console.firebase.google.com`
2. 選擇專案 → "App Check"
3. 確認各 app 的 attestation provider 狀態為 "Registered"
4. iOS: App Attest
5. Android: Play Integrity
6. 如需 debug token → "Manage debug tokens" → 新增 token

---

## 通用技巧

- **元素找不到時**：先截圖確認頁面是否完全載入，可能需要滾動
- **上傳檔案失敗**：優先用 `mcp__claude-in-chrome__form_input` 嘗試，失敗再試 `mcp__chrome-devtools__upload_file`
- **頁面狀態不對**：重新整理頁面再截圖確認
- **多語系填寫**：使用 Play Console 的 "Manage translations" 批次上傳，或逐語系切換填寫