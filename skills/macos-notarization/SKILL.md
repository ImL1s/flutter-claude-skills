---
name: macos-notarization
description: macOS 應用公證指南。當用戶需要打包 macOS 應用、進行公證（notarization）、或建立 DMG 時使用此 skill。包含 API 金鑰資訊和完整的公證流程。
---

# macOS 應用公證指南

## 公證憑證資訊

### Your Project

| 項目 | 值 |
|------|-----|
| **帳號名稱** | `<Your Apple Developer Account Name>` |
| **Issuer ID** | `<your-issuer-uuid-from-appstoreconnect>` |
| **Key ID** | `<YOUR_KEY_ID>` |
| **私鑰位置** | `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` |
| **鑰匙圈憑證名稱** | `<YOUR_PROFILE_NAME>` |
| **Team ID** | `<YOUR_TEAM_ID>` |
| **Bundle ID** | `com.example.yourapp` |

> 在 App Store Connect → Users and Access → Keys 創建 ASC API key 拿到 Issuer/Key ID 和下載 `.p8` 私鑰。

---

## 完整公證流程

### 1. 打包 Release 版本

```bash
cd /path/to/your/macos/app

# 清理並打包
fvm flutter clean && fvm flutter pub get
fvm flutter build macos --release --dart-define=environment=103
```

輸出位置：`build/macos/Build/Products/Release/<YourApp>.app`

### 2. 建立 DMG

**方法一：使用 flutter_distributor**
```bash
fvm dart pub global run flutter_distributor:flutter_distributor release \
  --name prod --jobs macos-dmg-release
```

**方法二：手動建立**
```bash
create-dmg --volname "<YourApp>" \
  --icon-size 140 \
  --icon "<YourApp>.app" 162 269 \
  --app-drop-link 640 269 \
  "<YourApp>.dmg" \
  "build/macos/Build/Products/Release/<YourApp>.app"
```

### 3. 提交公證

```bash
xcrun notarytool submit <YourApp>.dmg \
  --keychain-profile "YOUR_PROFILE_NAME" \
  --wait
```

### 4. 裝訂票據 (Staple)

```bash
xcrun stapler staple <YourApp>.dmg
```

### 5. 驗證

```bash
xcrun stapler validate <YourApp>.dmg
spctl -a -t open --context context:primary-signature -v <YourApp>.dmg
```

---

## 常用指令

### 查看公證歷史
```bash
xcrun notarytool history --keychain-profile "YOUR_PROFILE_NAME"
```

### 查看公證詳情（如果失敗）
```bash
xcrun notarytool log <submission-id> --keychain-profile "YOUR_PROFILE_NAME"
```

### 重新儲存憑證（如果遺失）
```bash
xcrun notarytool store-credentials "YOUR_PROFILE_NAME" \
  --key ~/.appstoreconnect/private_keys/AuthKey_<YOUR_KEY_ID>.p8 \
  --key-id "<YOUR_KEY_ID>" \
  --issuer "<YOUR_ISSUER_UUID>"
```

---

## 注意事項

1. **.p8 私鑰只能下載一次**，請妥善保管 `~/.appstoreconnect/private_keys/` 目錄
2. **Hardened Runtime** 必須啟用（專案已配置）
3. **簽名身份**必須是 `Developer ID Application`
4. DMG 和 .app 都可以單獨公證，但通常公證 DMG 即可
