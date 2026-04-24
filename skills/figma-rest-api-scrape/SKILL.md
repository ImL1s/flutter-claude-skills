---
name: figma-rest-api-scrape
description: |
  用 Figma REST API + Personal Access Token 抓設計稿（繞過 MCP View seat 限額）。
  比 Playwright 更快、PNG 原始解析度、零 UI 操作、零防毒告警風險。
  PAT 存在 macOS Keychain，不寫入 skill 或 commit。
  觸發條件：
  - 用戶說「抓 Figma」「提 Figma 資源」「Figma PNG」「Figma 設計稿」
  - Figma MCP 限額（View seat quota exhausted）
  - Playwright MCP 不可用（沒 register / 環境問題）
  - 需要批量抓高解析度圖片
---

## 為什麼用這個 skill

Figma REST API 是最**穩定、快、乾淨**的抓取方式：

| 維度 | Figma MCP | Playwright MCP | REST API + PAT |
|-----|-----------|----------------|---------------|
| 配額 | View seat 有限 | 不限 | 不限 |
| 速度 | ~3-5s/node | ~5-10s/node | **< 2s/node** |
| 解析度 | 預設 viewport | 1920×1200 viewport | **原始尺寸（可 scale 2-4x）** |
| 防毒告警 | 無 | 無 | 無 |
| 需登入 | 是 | 是 | **PAT 就夠** |
| UI 操作 | 有 | 有 | **零** |
| 缺點 | 配額限制 | 慢 + 裁剪 | **無 Dev Mode code snippet** |

**唯一缺陷**：拿不到 Figma MCP 的 Code Connect 代碼映射。但：
- PNG 圖 ✓
- JSON 完整 layout / style / fills / strokes / effects ✓
- Design token（color / font / spacing） ✓
- Layer 結構樹 ✓

## 前置條件

### 必須
- PAT 已存 Keychain：`security find-generic-password -s figma-pat -a "$USER" -w`
- 知道 Figma `fileKey`（從 URL 抽出：`figma.com/design/{fileKey}/...`）

### 如果沒 PAT
去 Figma Settings → Account → Personal Access Tokens → Generate 創建一個，然後：

```bash
security add-generic-password -s "figma-pat" -a "$USER" -w "<paste-token-here>" -U
```

Token 只放 Keychain，**不要**寫入任何檔案 / skill / commit。

## 核心工作流

### Step 0：讀 PAT 到 shell 變數

```bash
PAT=$(security find-generic-password -s "figma-pat" -a "$USER" -w)
```

不要 `export` 到環境變數（減少暴露面），只在單次命令中使用。

### Step 1：驗證 token

```bash
curl -s -H "X-FIGMA-TOKEN: $PAT" "https://api.figma.com/v1/me" | jq .
```

預期返回 `{"id":"...","email":"...","handle":"..."}`。若 `{"status":403,"err":"..."}` → token 無效，重新生成。

### Step 2：拿 file 結構（只列 pages）

```bash
FILE_KEY="YOUR_FIGMA_FILE_KEY"
curl -s -H "X-FIGMA-TOKEN: $PAT" \
  "https://api.figma.com/v1/files/$FILE_KEY?depth=1" \
  | jq '.document.children[] | {id, name}'
```

`depth=1` 只拿 pages 不拉完整 tree（避免大 file 很慢）。

### Step 3：找目標 page 的 node-id

如果要找特定 page（如「附件/紅包」）的頂層 frame，拿到該 page 的 node-id 後：

```bash
PAGE_ID="12116:222139"  # 附件/紅包
curl -s -H "X-FIGMA-TOKEN: $PAT" \
  "https://api.figma.com/v1/files/$FILE_KEY/nodes?ids=$PAGE_ID" \
  | jq '.nodes["'$PAGE_ID'"].document.children[] | {id, name, type}' \
  | head -50
```

這樣拿到 page 內所有頂層 frame 的 id + name + type（FRAME / COMPONENT / TEXT 等）。

### Step 4：批量拿 image URL

**⚠️ 限制**：一次抓太多 node 會 `Render timeout`。建議 **1-3 個/request**。

```bash
# 單 node（最穩）
NODE="42:643244"
curl -s -H "X-FIGMA-TOKEN: $PAT" \
  "https://api.figma.com/v1/images/$FILE_KEY?ids=$NODE&format=png&scale=2" \
  | jq -r ".images[\"$NODE\"]"
# 返回 S3 URL
```

**scale 建議**：
- `scale=1` 原始尺寸（快）
- `scale=2` 2x retina（設計稿對比最合適）
- `scale=4` 超清（適合放大細節）

**format 選項**：`png` / `jpg` / `svg` / `pdf`。一般用 `png`。要向量就 `svg`（但需要 node 本身是向量）。

### Step 5：下載 PNG

```bash
IMG_URL=$(curl -s -H "X-FIGMA-TOKEN: $PAT" \
  "https://api.figma.com/v1/images/$FILE_KEY?ids=$NODE&format=png&scale=2" \
  | jq -r ".images[\"$NODE\"]")

curl -s -o "screenshots/${NODE//:/-}.png" "$IMG_URL"
```

**⚠️ S3 URL 30 分鐘過期** — 拿到立刻下載，別存下來隔夜用。

### Step 6：批量抓多個 node

小 batch（每次 1-3 個）+ 循環：

```bash
FILE_KEY="YOUR_FIGMA_FILE_KEY"
PAT=$(security find-generic-password -s "figma-pat" -a "$USER" -w)
mkdir -p screenshots

for NODE in "42:643244" "24607:151163" "18912:184180" "25697:92757" "18912:184683" "28272:100896"; do
  echo "抓 $NODE..."
  URL=$(curl -s -H "X-FIGMA-TOKEN: $PAT" \
    "https://api.figma.com/v1/images/$FILE_KEY?ids=$NODE&format=png&scale=2" \
    | jq -r ".images[\"$NODE\"] // \"\"")
  if [ -n "$URL" ] && [ "$URL" != "null" ]; then
    curl -s -o "screenshots/${NODE//:/-}.png" "$URL"
    echo "  ✓ $(ls -la screenshots/${NODE//:/-}.png | awk '{print $5}') bytes"
  else
    echo "  ✗ 抓不到"
  fi
  sleep 1  # 避免 rate limit
done
```

### Step 7：拿 node 完整 JSON（layout / style / tokens）

```bash
curl -s -H "X-FIGMA-TOKEN: $PAT" \
  "https://api.figma.com/v1/files/$FILE_KEY/nodes?ids=$NODE" \
  | jq '.nodes["'$NODE'"].document'
```

返回完整 node tree 含：
- `absoluteBoundingBox` (x/y/width/height)
- `fills` (color/gradient/image)
- `strokes`
- `effects` (shadow/blur)
- `layoutMode` (AUTO/HORIZONTAL/VERTICAL)
- `paddingLeft/Right/Top/Bottom`
- `itemSpacing` (auto layout gap)
- `cornerRadius`
- `style` (fontFamily/fontWeight/fontSize/lineHeight/letterSpacing)
- `characters` (text content)

## 高階 Pattern

### Pattern A：抽 design token JSON

```bash
# 拿目標 node 的 style 欄位
curl -s -H "X-FIGMA-TOKEN: $PAT" \
  "https://api.figma.com/v1/files/$FILE_KEY/nodes?ids=$NODE" \
  | jq '.nodes["'$NODE'"].document |
         {
           size: .absoluteBoundingBox,
           fills: .fills,
           effects: .effects,
           cornerRadius: .cornerRadius,
           layout: {
             mode: .layoutMode,
             padding: [.paddingTop, .paddingRight, .paddingBottom, .paddingLeft],
             gap: .itemSpacing
           },
           typography: .style
         }'
```

### Pattern B：批量建 inventory

```bash
# 拿 page 所有 frame 的 name + id
curl -s -H "X-FIGMA-TOKEN: $PAT" \
  "https://api.figma.com/v1/files/$FILE_KEY/nodes?ids=$PAGE_ID" \
  | jq '.nodes["'$PAGE_ID'"].document.children[] |
        {id, name, type,
         size: .absoluteBoundingBox}' \
  > inventory.json
```

### Pattern C：抓 page 裡**所有** frame（遞迴）

```bash
# 用 jq 遞迴拿 page 內所有有 absoluteBoundingBox 的 node
curl -s -H "X-FIGMA-TOKEN: $PAT" \
  "https://api.figma.com/v1/files/$FILE_KEY/nodes?ids=$PAGE_ID&depth=3" \
  | jq '[.nodes["'$PAGE_ID'"].document | .. |
         select(type=="object" and has("id") and has("absoluteBoundingBox")) |
         {id, name, type}]'
```

`depth=3` 控制遞迴深度避免一次抓太多。

### Pattern D：跟蹤 Design System variables（如有）

```bash
curl -s -H "X-FIGMA-TOKEN: $PAT" \
  "https://api.figma.com/v1/files/$FILE_KEY/variables/local"
```

拿到的 `variables` + `variableCollections` 含項目所有 token 定義（color / number / string / boolean）。對齊到代碼最嚴謹。

## 常見問題

| 問題 | 解 |
|------|-----|
| `{"status":403,"err":"Token is invalid"}` | PAT 過期或錯誤。重新生成 + `security add-generic-password -U` 覆蓋 |
| `{"err":"Render timeout"}` | 一次抓太多 / node 太大。拆小 batch（1-3 個）+ `sleep 1` |
| `{"err":"Not found"}` | fileKey 或 nodeId 錯。用 file URL 重新驗證 |
| S3 URL 下載 403 | URL 過期（30 min）。重新 `/v1/images` 拿新 URL |
| image URL 返回 null | node 可能是 page root 或隱藏 frame，不能渲染。換子 node |

## 安全守則

1. **PAT 只存 Keychain** — 絕不寫入 .md / skill / commit / chat log
2. **不要 `export FIGMA_PAT=...`** — 環境變數會洩漏到 child process + history
3. **不要 echo PAT** — 在 shell history 留痕
4. **不把 PAT 當 argv 傳給 curl** — 用 header（`-H "X-FIGMA-TOKEN: $PAT"`），不用 `-u user:$PAT`
5. **懷疑洩漏立刻 rotate** — Figma Settings → PAT → Revoke + 生新的

## 和其他 skill 的關係

- `playwright-figma-scrape` — 無 PAT / 需要讀 Figma UI annotation / 需要跟 page 狀態交互（如滾動 Layers panel）時用。REST API 不能滾動 UI。
- `figma-playwright-fallback` — 精簡版 Playwright 路徑（本 skill 比它優先）
- `figma-implement-design` — 拿到設計稿後實作到代碼的 skill

## 觸發關鍵詞

- 「抓 Figma PNG」「Figma 截圖批量」「Figma 資源下載」
- 「Figma REST API」「Figma PAT」
- 「繞開 Figma MCP 配額」「View seat 用光」

## 引用 memory

`reference_figma_pat.md` — Figma 帳號 email / user ID / handle + Keychain 存取指令

## Related skills

- **`figma-use`** → **`figma-implement-design`** — use REST API to extract design context, then implement into code.
- **`playwright-figma-scrape`** — fallback when REST API has limitations (annotation reading, UI state interaction).
- **`figma-playwright-fallback`** — minimal Playwright-based scraping as a last resort.
