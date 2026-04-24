---
name: firebase-ai-logic
description: Firebase AI Logic (formerly Vertex AI in Firebase) 設定與整合指南。當用戶需要在 Flutter App 中使用 Gemini AI（語音解析、OCR 解析、AI 分類等），或遇到 Firebase AI 相關錯誤時使用。包含 Token 優化、ThinkingConfig、System Instruction 最佳實踐。
---

# Firebase AI Logic 整合指南

> **最後更新**: 2026-03-13

## 核心概念：兩種後端

Firebase AI Logic SDK (`firebase_ai` package) 提供兩種方式存取 Gemini：

| 項目 | `FirebaseAI.googleAI()` | `FirebaseAI.vertexAI()` |
|---|---|---|
| 底層 API | Gemini Developer API | Vertex AI API |
| Firebase 方案要求 | **Spark（免費）即可** | **Blaze（付費）才行** |
| 計費 | Gemini Developer API 免費額度 | Vertex AI 按量計費 |
| API Key 管理 | Firebase SDK 自動透過 proxy gateway 處理，**不暴露在客戶端** | 透過 Firebase Auth token |
| App Check 支援 | 有（建議開啟） | 有（建議開啟） |
| 適用場景 | 免費方案、原型、小型 App | 企業級、需要 Vertex AI 特定功能 |

### 安全性說明

`googleAI()` 的 API Key **不會暴露在前端**。Firebase SDK 透過 Firebase proxy gateway 轉發請求到 Gemini Developer API，API Key 由 Firebase 後端管理。這跟直接在前端放 Gemini API Key 完全不同。

## 必要的 GCP API

必須在 GCP Console 啟用以下 API（針對 Firebase Project 所屬的 GCP Project）：

```bash
# 1. Firebase AI Logic API（核心）
gcloud services enable firebasevertexai.googleapis.com --project=PROJECT_ID

# 2. Gemini Developer API（googleAI() 後端需要）
gcloud services enable generativelanguage.googleapis.com --project=PROJECT_ID
```

**兩個都要啟用**，即使只用 `googleAI()`。`firebasevertexai.googleapis.com` 是 Firebase AI Logic SDK 的入口，`generativelanguage.googleapis.com` 是實際的 Gemini Developer API。

## Firebase Console 設定

啟用 API 後，還需要在 Firebase Console 完成 AI Logic 設定：

1. 前往 `https://console.firebase.google.com/project/PROJECT_ID/ailogic`
2. 用正確的 Google 帳號登入（查 `gcp-firebase-project-map` skill 確認帳號）
3. 完成初始設定（Firebase 會自動產生 managed API Key）
4. 選擇 Gemini Developer API（非 Vertex AI）

## Flutter 整合程式碼

```dart
import 'package:firebase_ai/firebase_ai.dart';

// Spark (免費) 方案 — 用 googleAI()
final model = FirebaseAI.googleAI().generativeModel(
  model: 'gemini-2.5-flash-lite',  // 輕量快速模型
  generationConfig: GenerationConfig(
    responseMimeType: 'application/json',
    maxOutputTokens: 1024,
    temperature: 0.1,
  ),
  systemInstruction: Content.text('你的系統指令...'),
);

// Blaze (付費) 方案 — 用 vertexAI()
final model = FirebaseAI.vertexAI().generativeModel(
  model: 'gemini-2.0-flash',
  // ... 同上
);
```

## 可用模型

| 模型 | 用途 | 速度 | 成本 | ThinkingConfig |
|---|---|---|---|---|
| `gemini-2.5-flash-lite` | 輕量任務（解析、分類） | 最快 | 最低 | `thinkingBudget` |
| `gemini-2.5-flash` | 一般任務 | 快 | 低 | `thinkingBudget` |
| `gemini-2.5-pro` | 複雜推理 | 中 | 高 | `thinkingBudget` |
| `gemini-3-flash` | 新一代快速模型 | 快 | 低 | `thinkingLevel` |
| `gemini-3-pro` | 新一代複雜推理 | 中 | 高 | `thinkingLevel` |

> **注意**: Gemini 2.5 用 `thinkingBudget`（整數），Gemini 3.x 用 `thinkingLevel`（enum）。

---

## Token 優化策略（重要！）

### 1. ThinkingConfig — 控制思考 Token

`firebase_ai 3.8.0+` 支援 `ThinkingConfig`，這是**最有效的 token 節省方式**。

```dart
import 'package:firebase_ai/firebase_ai.dart';

// ✅ 分類 / JSON 結構化輸出 → 關閉思考（節省 ~30% token）
final classifyModel = FirebaseAI.googleAI().generativeModel(
  model: 'gemini-2.5-flash-lite',
  generationConfig: GenerationConfig(
    temperature: 0.1,
    maxOutputTokens: 128,
    responseMimeType: 'application/json',
    thinkingConfig: ThinkingConfig.withThinkingBudget(0), // 🔑 關閉思考
    responseSchema: Schema.object(properties: { /* ... */ }),
  ),
);

// ✅ 聊天 / 對話 → 適度思考預算
final chatModel = FirebaseAI.googleAI().generativeModel(
  model: 'gemini-2.5-flash-lite',
  generationConfig: GenerationConfig(
    temperature: 0.2,
    maxOutputTokens: 512,
    thinkingConfig: ThinkingConfig.withThinkingBudget(1024), // 🔑 限制思考
  ),
);

// ✅ 複雜推理 → 不限制（預設）
final reasonModel = FirebaseAI.googleAI().generativeModel(
  model: 'gemini-2.5-pro',
  generationConfig: GenerationConfig(
    maxOutputTokens: 2048,
    // thinkingConfig 省略 = 使用預設預算
  ),
);
```

**ThinkingConfig 選擇指南：**

| 任務類型 | 模型 | 建議 | 說明 |
|---------|------|------|------|
| JSON 分類/結構化輸出 | flash-lite | 省略或 `thinkingBudget(0)` | flash-lite 預設就關了 |
| 簡單對話/問答 | flash-lite | **省略**（不要設！） | flash-lite 預設關閉，設 budget 反而會開啟 |
| 複雜推理 | flash/pro | `thinkingBudget(1024)` 或省略 | 這些模型預設開啟 |
| 動態模式 | flash/pro | `thinkingBudget: -1` | 模型自行決定 |
| Gemini 3.x | 3-flash/3-pro | `ThinkingConfig.withThinkingLevel(ThinkingLevel.low)` | 用 enum 而非 int |

> ⚠️ **重要陷阱**: `gemini-2.5-flash-lite` 預設**關閉**思考。如果你設 `ThinkingConfig.withThinkingBudget(1024)` 反而會**開啟**思考，增加 token 消耗！只有在你確實需要推理能力時才設定。

### 2. System Instruction 壓縮

**使用 XML 標籤結構**（Gemini 3.0+ 基準測試顯示 XML 比 Markdown 更不容易 instruction drift）：

```dart
const systemInstruction = '''
<identity>
你是 XX App 的 AI 助手。
</identity>

<knowledge>
## 知識區塊 A
內容用精簡格式：項目A/項目B/項目C（❌不要的：X/Y/Z）→處理步驟
</knowledge>

<rules>
1. 規則一
2. 規則二
</rules>
''';
```

**壓縮技巧：**
- 用 `/` 分隔同類項目，取代逐行列舉（省 ~40% token）
- 用 `→` 連接處理步驟
- 用 `|` 分隔平行選項
- 好/壞回答示範各給一個即可
- Schema description 越短越好（`'物品名稱'` 而非 `'辨識出的物品名稱'`）

### 3. Context 注入優化

動態注入到 user message 的上下文也要精簡：

```dart
// ❌ 浪費 token
'  - 車號 ABC-123：在你的東北方 1.2 km（1200 公尺），'
'車速 20 km/h，行駛中，2分鐘前更新，'
'GPS(25.0330, 121.5654)'

// ✅ 精簡（AI 不需要原始座標，方位+距離已足夠）
'  - 車號 ABC-123：東北方 1.2 km（1200 m），'
'車速 20 km/h，行駛中，2分鐘前更新'
```

### 4. maxOutputTokens 調配

| 用途 | 建議值 | 原因 |
|------|--------|------|
| JSON 分類（5 欄位） | `128` | 結構固定，128 綽綽有餘 |
| 簡短回答（廢物分類） | `512` | 含列表/emoji 足夠 |
| 長文生成（報告） | `1024-2048` | 視輸出長度而定 |
| 預設不設定 | 模型最大值 | 浪費 token，不建議 |

### 5. Schema Description 精簡

```dart
// ❌ 冗長
Schema.string(description: '辨識出的物品名稱')
Schema.string(description: '分類原因（繁體中文，含回收前處理步驟）')
Schema.string(description: '回收建議（繁體中文，含去哪丟的建議）')

// ✅ 精簡
Schema.string(description: '物品名稱')
Schema.string(description: '分類原因（繁體中文，含處理步驟）')
Schema.string(description: '回收建議（繁體中文）')
```

---

## 常見錯誤與解法

### "Firebase AI Logic API has not been used in project"
```
原因: 未啟用 firebasevertexai.googleapis.com
解法: gcloud services enable firebasevertexai.googleapis.com --project=PROJECT_ID
```

### "Firebase AI Logic is missing a configured Gemini Developer API key"
```
原因: 未在 Firebase Console 完成 AI Logic 初始設定
解法: 前往 Firebase Console → AI Logic 頁面完成設定
      Firebase 會自動產生 managed API Key
```

### "Model not found" / 404
```
原因: 模型名稱錯誤或該模型不支援 googleAI() 後端
解法: 確認模型名稱正確（如 gemini-2.5-flash-lite）
      確認用的是 googleAI() 還是 vertexAI()
```

### "Permission denied" / 403
```
原因: Firebase project 方案不符（vertexAI 需要 Blaze）
      或 API 未啟用
      或 App Check debug token 未設定（debug build）
解法: 確認方案（Spark vs Blaze）
      確認兩個 API 都已啟用
      Debug 環境需註冊 App Check debug token（見下方）
```

## App Check 整合（建議）

搭配 App Check 可防止未授權的 API 呼叫：

```dart
// 在 Firebase.initializeApp() 後啟用
await FirebaseAppCheck.instance.activate(
  androidProvider: AndroidProvider.playIntegrity,
  appleProvider: AppleProvider.appAttest,
);
```

### Debug Token 注冊（Debug Build 必須）

Debug build 時 Play Integrity / App Attest 無法運作，需要手動註冊 debug token：

```bash
# 1. 用 UUID 產生 debug token
uuidgen | tr '[:upper:]' '[:lower:]'

# 2. 查出 Android/iOS 的 App ID
gcloud firebase apps:list --project=PROJECT_ID

# 3. 註冊 debug token（Android）
curl -X POST \
  "https://firebaseappcheck.googleapis.com/v1beta/projects/PROJECT_ID/apps/ANDROID_APP_ID/debugTokens" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{"displayName":"dev-debug","token":"YOUR_UUID"}'

# 4. 同樣對 iOS 執行
# 5. 加入 .env：FIREBASE_DEBUG_TOKEN=YOUR_UUID
# 6. main.dart 中：
if (kDebugMode && debugToken.isNotEmpty) {
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
    appleProvider: AppleProvider.debug,
  );
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
}
```

## 絕對不要做的事

1. **不要在前端放 Gemini API Key** — Firebase SDK 自動管理
2. **不要用 `vertexAI()` 在 Spark (免費) 方案** — 會直接報錯
3. **不要改 `googleAI()` 為 `vertexAI()` 來「修復」問題** — 這是不同的後端，不是修復
4. **不要假設模型名稱錯誤** — 先查文件確認，不要猜測
5. **不要忘記設 ThinkingConfig** — 預設會消耗大量思考 token
6. **不要在 Schema description 寫長文** — 每個 description 都算 token

---

## 專案參考

### Your Project Example

| 項目 | 值 |
|---|---|
| Firebase Project | `<your-firebase-project-id>` |
| GCP 帳號 | `<your-gcp-account>@gmail.com` |
| 後端 | `FirebaseAI.googleAI(appCheck: FirebaseAppCheck.instance)` |
| 模型 | `gemini-2.5-flash-lite`（透過 `FIREBASE_AI_MODEL` env） |
| 方案 | Spark（免費）/ Blaze（付費） |
| Console URL | `https://console.firebase.google.com/project/<your-project-id>/ailogic` |

