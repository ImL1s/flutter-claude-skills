---
name: playwright-figma-scrape
description: |
  用 Playwright MCP 系統性抓取 Figma 設計稿（screenshot / design token / layer inventory）的完整工作流。
  適用於：Figma MCP 限額耗盡 / 需要批量抓取多個 frame / 需要從 DOM 提取 token / 需要建立 frame-to-code 對照表。
  觸發條件：
  - 用戶說「抓 Figma 設計稿」「批量截圖 Figma」「提 Figma token」
  - Figma MCP 回報 "tool call limit" / "View seat"
  - 需要 Phase 對齊驗證（Figma vs 代碼實現）
  - 需要更新 design token 文件
---

## 為什麼用這個 skill

Figma 官方 MCP 工具（`get_design_context`、`get_screenshot`、`get_metadata`）有 View seat 配額限制，超限後所有 Figma MCP 工具同池鎖死。Playwright MCP 不算 Figma 配額，可以：

- **批量抓取** — 一次抓 N 個 frame（MCP 只能一個一個）
- **DOM 提取** — 從 Figma web UI 讀 Properties panel 提 token
- **畫 layer 結構圖** — 列出所有 node-id + 名稱建立 inventory
- **系統對齊驗證** — Figma 實際值 vs 代碼當前值逐項對照

**唯一缺陷**：Playwright 拿不到 Figma MCP 獨有的 Code Connect 代碼映射。但截圖、token、layer 結構、視覺對比都完全夠用。

---

## 環境前置條件

### 必須
- `mcp__playwright__browser_*` tools 可用（Claude Code session 有加載 Playwright MCP）
- Figma account 已登入（瀏覽器有 session cookie 或 Chrome extension bridge 模式）
- 知道 target Figma `fileKey`（從 URL 抽出）

### 推薦
- 知道至少一個 `nodeId` 當起始點（否則從 recents 找）
- 有 Figma PAT（Personal Access Token）備用 REST API 路徑

### 檢測工具可用性

```
ToolSearch query="select:mcp__playwright__browser_navigate,mcp__playwright__browser_resize,mcp__playwright__browser_take_screenshot,mcp__playwright__browser_evaluate,mcp__playwright__browser_press_key,mcp__playwright__browser_wait_for,mcp__playwright__browser_snapshot"
```

Playwright MCP 沒 load → **stop + report**：告訴用戶「需要重啟 Claude Code」。不要試 AppleScript / cliclick / mac-use 等野路子（見「環境合規」章節）。

---

## 核心工作流（8 步）

### Step 0：Load Playwright tools

用 ToolSearch 一次 select 所有需要的 Playwright tools（見上方 detect 命令）。

### Step 1：擴大 viewport

```
browser_resize width=1920 height=1200
```

預設 viewport 太窄，Figma canvas 會被側欄擠占。1920x1200 是 Figma 官方推薦的設計稿可讀寬度。

### Step 2：導航到 Figma file

**知道 fileKey + nodeId 時（最快）**：
```
browser_navigate url=https://www.figma.com/design/{fileKey}/?node-id={nodeA}-{nodeB}
```

> URL 裡 node-id 用 `-` 分隔（如 `18912-184525`），MCP tool 參數用 `:` 分隔（如 `18912:184525`）。

**只知道 fileKey 不知道 nodeId**：
```
browser_navigate url=https://www.figma.com/design/{fileKey}
```

**啥都不知道，從 recents 找**：
```
browser_navigate url=https://www.figma.com/files/recent
browser_snapshot depth=6
# 從 snapshot 找 role="group" 的 file 卡片 ref
browser_click ref={fileGroupRef} doubleClick=true
```

關鍵：**從 recents 開啟必須 doubleClick: true**，單 click 只是選中。

### Step 3：等 Figma 載入

```
browser_wait_for time=5
```

Figma 是 SPA，資源載入慢。首次開啟要至少 5 秒才能互動。後續 navigate 同 file 的不同 node 只需 2-3 秒。

### Step 4：切 Page（如需要）

Figma 檔案通常有多個 page，想抓的設計可能在特定 page（如「附件/紅包」）。

**A. 真實 click（優先）**
```
browser_snapshot depth=12
# 在 snapshot markdown 找目標 page 名 + ref=eXXX
browser_click ref=eXXX
```

**B. URL 直跳**
如果知道目標 page 裡任意一個 node-id，直接 `browser_navigate` URL 帶 `node-id={nodeA}-{nodeB}`，Figma 自動切到該 node 所在的 page。判斷當前 page：Pages 面板選中 page 的 `<button>` 帶 `aria-current="page"`。

**已知坑**：
- `dispatchEvent(MouseEvent)` 或 element.click() 切 Figma page **不會生效**（Figma 的 PagesRowWrapper 監聽 React synthetic events + pointerdown/up 序列，單發 click 不觸發）
- 必須用 `mcp__playwright__browser_click` 真實 click，不是 JS click

### Step 5：View 調整

Figma 快捷鍵：

| 快捷鍵 | 作用 | 何時用 |
|-------|------|-------|
| `Shift+1` | Fit view to entire page | 想看 page overview 結構 |
| `Shift+2` | Zoom to selected node | 精確對齊單個節點 |
| `Shift+0` | Zoom to 100% | 按 1:1 實際尺寸顯示 |
| `Cmd++` / `Cmd+-` | 縮放 | 微調 |

**典型順序**：先 `Shift+1` 看全貌確認方向 → 點某個 node → `Shift+2` zoom 上去截圖。

### Step 6：列 Layers（建 inventory）

用 `browser_evaluate` 執行 JS 從 Layers panel DOM 讀 node-id + 名稱。

**基本 snippet（單次查詢）**：

```js
() => {
  // Figma Layers panel 每個 row 有 data-testid="{nodeA}:{nodeB}-layers-panel-row"
  const rows = document.querySelectorAll('[data-testid$="-layers-panel-row"]');
  const out = [];
  rows.forEach(r => {
    const tid = r.getAttribute('data-testid');
    const m = tid.match(/^(.+?)-layers-panel-row$/);
    if (!m) return;
    const name = (r.innerText || r.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 60);
    out.push({ nodeId: m[1], name });
  });
  return out;
}
```

**⚠️ Virtual scroll 限制（實測 2026-04-23 ✓）**：Layers panel 只渲染可見 layer。不滾動只能拿到 ~62 個 node；滾動後可拿到 111 個（本次實測數字）。**必須滾動才能建完整 inventory**。

**滾動收集 snippet（正確做法）**：

```js
async () => {
  const container = document.querySelector('[class*="layersPanel"]') ||
                    document.querySelector('[data-testid*="layers"]');
  const seen = new Map();

  const collect = () => {
    document.querySelectorAll('[data-testid$="-layers-panel-row"]').forEach(r => {
      const tid = r.getAttribute('data-testid');
      const m = tid.match(/^(.+?)-layers-panel-row$/);
      if (!m) return;
      if (seen.has(m[1])) return;  // 去重
      const name = (r.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 60);
      seen.set(m[1], { nodeId: m[1], name });
    });
  };

  collect();  // 收集首批可見項

  if (container) {
    const scrollStep = 300;
    let lastScrollTop = -1;
    while (container.scrollTop !== lastScrollTop) {
      lastScrollTop = container.scrollTop;
      container.scrollTop += scrollStep;
      await new Promise(r => setTimeout(r, 200));  // 等虛擬列表渲染
      collect();
    }
  }

  return [...seen.values()];
}
```

> 每次 scrollTop += 300 → wait 200ms（等虛擬列表重繪）→ 再 collect → 直到 scrollTop 不再變化。
> 去重靠 Map key（nodeId），合併結果即完整 inventory。

**其他替代方法**（當 Layers panel 收合時）：
- 用 Figma `Cmd+F` Find 搜名字 → 精確定位
- 手動展開所有 group（點 chevron）後再 query

**已知坑**：
- node-id 看起來像 frame component 實際是 Text label —— 抓的時候 Shift+2 zoom 上去看到大字而非組件，就是命中了 Text node。要從 Layers 找父節點（通常是 `Frame xxx` 名的節點）。

### Step 7：逐個 frame 截圖

```
# 對每個 frame：
browser_navigate url=https://www.figma.com/design/{fileKey}/?node-id={nodeA}-{nodeB}
browser_wait_for time=2
browser_press_key key=Shift+2
browser_wait_for time=1
browser_take_screenshot filename=<absolute-path>/screenshots/{name}.png type=png
```

**檔名慣例**：`{category}-{descriptor}-{nodeA-nodeB}.png`，例如：
- `bubble-lucky-rp-18912-184525.png`（紅包氣泡類型）
- `detail-header-18912-184529.png`（詳情頁 header）
- `animation-frame-01-28272-99441.png`（動畫關鍵幀）

**截圖包含側欄**：Playwright `browser_take_screenshot` 預設截 viewport，左右側欄會被包含。要純 canvas 可以：
- 用 `clip` 參數限定區域（未來擴展）
- 或截完後 Bash 用 `sips -c` 裁剪

### Step 8：DOM 提取 design token

每個 frame 選中時，右側 Properties panel 顯示其 layout / typography / colors / padding / radius。JS 抽出：

```js
() => {
  // Figma 右側 Properties panel
  const panel = document.querySelector('[class*="right_panel"]') ||
                document.querySelector('[data-testid="properties-panel"]');
  if (!panel) return { error: 'properties panel not found, selection may have changed' };

  // 全文抓（最簡單可靠）—— 實測 2026-04-23 ✓：innerText 格式穩定，可用 regex 解析
  const fullText = panel.innerText || panel.textContent || '';

  // 結構化解析（需根據實際 DOM 調整 selector）
  const sections = {};
  panel.querySelectorAll('[class*="section"]').forEach(s => {
    const title = (s.querySelector('[class*="title"]')?.innerText || '').trim();
    if (title) sections[title] = (s.innerText || '').replace(title, '').trim().slice(0, 500);
  });

  return {
    fullText: fullText.slice(0, 3000),
    sections,
  };
}
```

常見 token 欄位（文字中會出現）：
- **Layout**: Width / Height
- **Typography**: Font / Weight / Size / Line height / Letter spacing
- **Colors**: Hex values (e.g., #E75140)、token label（如 `固定色/红包/红包颜色`）
- **Fills / Strokes**: fill color + opacity
- **Effects**: shadow (x y blur spread color alpha)
- **Padding**: vertical / horizontal
- **Gap**: auto layout spacing
- **Corner radius**: per-corner or uniform
- **Content**：Text node 的文字內容

### View seat 限制下 Properties panel 能讀什麼（實測 2026-04-23 ✓）

> 很多人誤以為 View seat = Properties panel 也看不到。**不對**。

| 可讀 ✅ | 不可讀 ❌ |
|--------|---------|
| Width / Height / Padding / Gap | Dev Mode code snippet（需 Editor seat） |
| Colors（含 token label 如 `固定色/红包/红包颜色`） | Code Connect 組件映射 |
| Typography（Font / Weight / Size / Line height） | Inspect panel 進階 API 數據 |
| Corner radius | — |
| Content（Text node 文字） | — |
| Modes / Component properties | — |
| Export 設定 | — |

**結論**：View seat 下 `innerText` 抽 Properties panel 完全可用，能拿到所有視覺 token。只有代碼生成相關功能需要升 seat。

---

## 高階 Pattern

### Pattern 1：系統性 frame inventory

抓完 Layers 後建 JSON 存檔：

```js
// 存到 .omc/figma-snapshots/<feature>/frame-inventory-raw.json
const inventory = [... /* from Step 6 snippet */];
// 按名稱前綴分類（如 "Frame xxx" = 設計稿 frame，"T xxx" = Text label）
```

然後逐個 navigate + screenshot，把 inventory 內容擴充 `screenshotPath` 欄位。

### Pattern 2：Figma vs 代碼 token 對照

1. Step 8 提取當前 frame token
2. Read 代碼的 colors.dart / font.dart / theme.dart
3. 生成對照表：

```markdown
| Token | Figma 原始值 | 當前代碼 | 一致? |
| xxx | #E75140 | 0xFFE75140 | ✅ |
| yyy | rgba(189,88,78,0.10) | 0x1ABD584E | ✅ |
| zzz | (Figma 無此 token) | 0x40BD584E | ⚠️ code 獨有 |
```

### Pattern 3：動畫關鍵幀抓取

Figma 沒有原生動畫時序，但設計師會畫**連續多個 frame** 表示動畫各階段。命名如：
- `animation-open-01-start`
- `animation-open-02-scale-up`
- `animation-open-03-reveal`

抓的時候按順序 screenshot，檔名保留順序 `animation-{stage}-{nn}-{nodeId}.png`，方便之後逐幀對齊實現。

### Pattern 4：REST API fallback（PAT 有時）

如果有 Figma PAT（不是 View seat 限制的 MCP token，是個人 API token），可繞開 Playwright：

```bash
# 單 node screenshot（PNG）
curl -H "X-FIGMA-TOKEN: $PAT" \
  "https://api.figma.com/v1/images/{fileKey}?ids={nodeId}&format=png&scale=2" | jq -r '.images["{nodeId}"]' | xargs curl -o {out}.png
```

```bash
# Node metadata（含完整 layer tree + style）
curl -H "X-FIGMA-TOKEN: $PAT" \
  "https://api.figma.com/v1/files/{fileKey}/nodes?ids={nodeId}"
```

**PAT 存 Keychain**：
```bash
security add-generic-password -s "figma-pat" -a "$USER" -w "<your-pat>" -U
# 讀取
PAT=$(security find-generic-password -s "figma-pat" -a "$USER" -w)
```

---

## 已知坑（別再踩）

| ✗ 不要 | 原因 |
|-------|-----|
| `dispatchEvent(MouseEvent)` 或 `element.click()` 切 Figma page | Figma 監聽 React synthetic events + pointerdown/up 序列，單發 click 不觸發 |
| `mac-use-mcp__click` | 操作的是真實用戶 Chrome，不是 Playwright 的 browser 實例 |
| `/` 快捷鍵搜 node | Figma `/` 是 Comment |
| `Cmd+P` | Figma Quick Actions 選單，不能搜 node |
| `Cmd+Shift+C` 想拿 SVG | 是 **Copy as PNG**，不是 SVG。要 SVG 走 Properties → Export panel |
| 靠 `a[href]` 查找 recents 文件 | Figma recents 卡片用 `role="group"`，不是 anchor |
| Shift+2 看到大字 = 組件 | 可能是 Text label（不是 frame），要從 Layers 找父節點 |
| 靠視覺「猜」設計規格 | 必須用 DOM 抽精確值，不要用估 |
| **`PageDown` 鍵在 Figma canvas 上按** | **PageDown 會切換整個 Figma Page**（不是 scroll canvas！）實測 2026-04-23 ✓：按 PageDown → 跳去下一個 page（如「聯系人·發現」），截圖就錯了。滾動 canvas 要用 `browser_scroll` 或 Layers panel container scroll，不要用 PageDown |
| 不滾 Layers panel 直接 query | 只拿到可見 ~62 個 node，完整 inventory 需滾動收集（見 Step 6 滾動 snippet）|

### Text label 判斷法（實測 2026-04-23 ✓）

navigate 到一個 node → `Shift+2` zoom → 若畫面中央出現 **超大字**（如 84px「幸運紅包」），這是 Figma 文件內部分區標題 Text label，**不是**用戶可見的 UI component。

快速辨識：
1. Properties panel 右側看 **Typography 區**：出現 Font / Weight / Size 就是 Text node
2. Layers panel 該行有 **T icon**（Text），Frame icon 是方塊
3. 尺寸是 `{n×84}px`（每個漢字 84px 寬），高度固定 84px

確認是 Text label 後，按 **Escape** 跳到父節點（Layers 面板自動選中父層）。找 `Frame 14200XXXXX` 或 `控制台` 命名的 Frame 才是真正的 UI component。

### Escape 跳父節點法（實測 2026-04-23 ✓）

在 Figma canvas 已選中某節點時按 `Escape`，會跳到該節點的直接父節點（等同 Layers panel 往上一層）。本次實測：從 Text label `18912:184525`（幸運紅包）按 Escape 後跳到父 Frame `12116:222139`（page root frame），確認氣泡 UI 無獨立 component 節點。

**用法**：
1. navigate 到未知節點
2. `Shift+2` zoom 確認是 Text label 或 sub-layer
3. 按 `Escape` → 看 URL + Layers panel 選中項變化 → 新 node-id 即父節點
4. 重複 Escape 可沿樹向上爬，直到找到目標 Frame

### Figma annotation text 藏 UX 決策（實測 2026-04-23 ✓）

截圖只捕捉視覺 UI。**Figma 文字標注**（設計師在 canvas 上附加的說明文字）含有截圖不可見的架構決策。

本次實測：node `18912:184683` 的 annotation text 為「查看詳情入口進入該頁面的都帶返回按鈕」，揭示詳情頁是 **full-screen page**（非 modal），這是與代碼現狀最大的架構偏離。純靠截圖無法發現。

**操作方式**：
```js
// 從 Properties panel innerText 抽取 annotation / comment
() => {
  const panel = document.querySelector('[class*="right_panel"]');
  return panel ? panel.innerText.slice(0, 3000) : 'not found';
}
```
或直接 `browser_snapshot depth=12` 看 Figma Annotations 面板（右側面板切換到「Annotations」tab）。

**何時特別重要**：
- 「這頁怎麼打開」（push vs modal）
- 「有沒有返回按鈕」
- 「是否支持手勢關閉」
- 任何涉及導航方式的 UX 決策

### Mobile mockup 內部 UI 無獨立 Figma node

Figma 設計師會把 UI 放在 mobile 手機框 mockup 內，**mockup 內的 UI sub-layer 不是獨立 reusable component**，無獨立 node-id 可直接訪問。

本次實測：紅包氣泡 UI 是 page root frame `12116:222139` 下的 mobile mockup sub-layer。9 個紅包 Text label 的父節點全部指向 `12116:222139`（page root），表示氣泡無獨立 component。

**含義**：
- 不要期望每個 UI 元素都有獨立 node-id
- 無 node-id 的 UI → **以代碼現狀為準**（不等 Figma node 抓取）
- 想看 mockup 內部 UI → 截 parent frame + `Shift+1` 全局截圖，用截圖推算比例

---

## 環境合規：別做疑似惡意軟體行為

> 企業環境可能裝有 EDR（如 CrowdStrike Falcon Sensor），任何看起來像惡意軟件的自動化手法會觸發安全告警。

### ❌ 禁止
- 隱藏 / 最小化 Terminal 視窗（「想偷偷切換 app」= 惡意軟件典型手法）
- AppleScript 跨 process event（`tell application "Chrome" to ...`）—— EDR 攔截，timeout -1712
- 操作用戶前台視窗（user 正在用的 Chrome / VSCode / IM app 等）
- cliclick / 鍵盤模擬 / 滑鼠模擬搶焦點
- 任何「偷偷進行」或「繞過 UI」的 workaround

### ✅ 正確做法
- **Playwright MCP** — Chrome extension bridge 模式。本 skill 推薦
- **Figma REST API + PAT** — 純 HTTP 零 UI 操作
- MCP 工具不可用 → **停 + 報告**，不試其他 stealth 手段
- 寧可任務失敗，不觸發安全警報

### Playwright MCP 的 browser 實際是什麼
本 skill 實測（2026-04-23）：`mcp__playwright__browser_*` 工具走 Chrome extension bridge（URL 顯示 `chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/connect.html`），是 **Chrome 原生 extension API 代理用戶 Chrome**，不是完全 isolated Chromium。

**含義**：
- ✅ 不觸發 EDR 惡意軟件檢測（是 Chrome 原生行為）
- ⚠️ 會操作用戶真實 Chrome tab（會開新 tab 或佔用現有 tab）
- ⚠️ 依賴用戶 Chrome 已登入 Figma（session cookie）

如果嚴格要求 isolated browser（不碰用戶 Chrome），需要另用 Playwright CLI（非 MCP）或 Puppeteer with `--user-data-dir=<tmp>`。

---

## 失敗模式 + 復原

| 失敗 | 診斷 | 復原 |
|-----|------|-----|
| `browser_navigate` 報 timeout | Figma 載入慢 / 網路問題 | 增加 `browser_wait_for time=10`，重試一次 |
| `browser_take_screenshot` 只拿到空白畫布 | Figma 還沒完全渲染 | `Shift+1` fit view + wait 3s 再截 |
| `browser_evaluate` 返回空 `[]` | Layers panel 收合了 / virtual scroll | `Cmd+F` Find 定位目標後再 query；或展開所有 group |
| Playwright MCP 工具不可用 | Claude Code session 沒 register | **停 + 重啟 Claude Code**，不要切 AppleScript / cliclick |
| Figma 顯示 "Request access" | Dev Mode / Code Connect 需要 seat 升級 | 不拿 code，只拿 screenshot + DOM token |
| File 顯示 login page | Chrome extension bridge 沒登入 Figma | 用戶在 Chrome 裡手動登入 Figma 後重試 |
| 抓的 screenshot 側欄佔一半 | viewport 太小 | `browser_resize 1920x1200` + 按 `\\` 切全屏模式（Figma 預設 shortcut） |

---

## 完整 workflow template（可複製）

```
# 1. Load tools
ToolSearch "select:mcp__playwright__browser_navigate,browser_resize,browser_take_screenshot,browser_evaluate,browser_press_key,browser_wait_for,browser_snapshot"

# 2. Prep
browser_resize 1920x1200
browser_navigate https://www.figma.com/design/{fileKey}/?node-id={root}
browser_wait_for time=5

# 3. Build inventory (Step 6 snippet)
browser_evaluate "<list-layers.js>"
# → save to .omc/figma-snapshots/{feature}/frame-inventory-raw.json

# 4. Overview screenshots (Shift+1 per section root)
for section in [附件, 紅包皮, 發包, ...]:
  browser_navigate url=...?node-id={section-root}
  browser_wait_for time=2
  browser_press_key key=Shift+1
  browser_wait_for time=1
  browser_take_screenshot filename=section-{name}.png

# 5. Detail screenshots (Shift+2 per frame)
for frame in inventory:
  browser_navigate url=...?node-id={frame.nodeId}
  browser_wait_for time=2
  browser_press_key key=Shift+2
  browser_wait_for time=1
  browser_take_screenshot filename=frame-{frame.name}-{frame.nodeId}.png
  browser_evaluate "<extract-properties.js>"
  # → append token to tokens-raw.json

# 6. Generate outputs
# frame-inventory.md（人類可讀版 inventory）
# tokens.md（Figma vs 代碼對照）
# README.md（抓取狀態彙總）
```

---

## 產出結構建議

```
.omc/figma-snapshots/{feature}/
├── README.md               # 抓取狀態彙總（成功/失敗/Phase 歸屬）
├── frame-inventory.md      # 人類可讀 frame 清單
├── frame-inventory-raw.json # 原始 inventory 數據
├── tokens.md               # Figma vs 代碼對照
├── tokens-raw.json         # 原始 DOM token
└── screenshots/
    ├── section-01-attachment.png
    ├── section-02-theme.png
    ├── frame-bubble-lucky-18912-184525.png
    ├── frame-detail-header-18912-184529.png
    ├── animation-open-01-xxx.png
    └── ...
```

---

## 觸發關鍵詞

當用戶說以下任何一個，考慮用本 skill：

- 「抓 Figma 設計稿」「批量截圖 Figma」「提 Figma token」
- 「Figma MCP 用不了」「View seat 限額」「tool call limit」
- 「對齊 Figma」「Figma vs 代碼」「驗證 Figma」
- 「列 Figma frame」「建 Figma inventory」
- 「用 Playwright 抓 Figma」「繞開 Figma MCP」

---

## Related skills

- **`figma-use`** — use the official Figma MCP when quota is available (preferred). playwright-figma-scrape is a fallback for when Figma MCP hits View seat limits.
- **`verify-ui`** — use after playwright-figma-scrape to do visual comparison verification between Figma mockups and actual code.
- **`visual-verdict`** — use for structured visual diff validation after scraping Figma designs.
- **`verify-ui-auto`** — use for automated pixel-based comparison via SSIM after playwright-figma-scrape screenshots.
