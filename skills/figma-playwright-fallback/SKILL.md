---
name: figma-playwright-fallback
description: |
  Figma MCP View seat 限额耗尽时，用 Playwright MCP 导航 Figma desktop web 的完整工作流 +
  可复制的 JS 片段。涵盖：从 recents 找文件 → 切 page → 列 layers → 定位 frame →
  提取背景/颜色/token。触发条件：Figma MCP 报 "tool call limit"、View/starter seat、
  or user says "用 playwright 代替 figma mcp"。
---

## 为什么需要这个

Figma MCP 工具（`get_design_context`、`get_screenshot`、`get_metadata`）对 View seat 用户有
限额。打到上限后所有 Figma MCP 工具同池锁死。Playwright MCP 不算 Figma 配额，所以
可以用浏览器直进 Figma web 操作。

**唯一缺陷**：Playwright 拿不到 MCP 独有的 Code Connect 代码转换。但看 layout、找 node-id、
读颜色 token、截图对比都完全够用。

---

## 已知坑（别再踩）

| ✗ 不要 | 原因 |
|-------|-----|
| `dispatchEvent(MouseEvent)` 或 `element.click()` 切 Figma page | Figma 的 PagesRowWrapper 监听 React synthetic events + pointerdown/up 序列，单发 click 不触发 |
| `mac-use-mcp__click` | 它操作的是真实用户 Chrome，不是 Playwright 的 Chromium |
| `/` 快捷键搜 node | Figma `/` 是 Comment |
| `Cmd+P` | Figma Quick Actions 选单，不能搜 node |
| `Cmd+Shift+C` 想拿 SVG | 那是 **Copy as PNG**，不是 SVG。走 Properties → Export panel（见步骤 6.5） |
| 靠 `a[href]` 查找 recents 文件 | Figma recents 卡片用 `role="group"`，不是 anchor |
| 靠视觉"猜" logo path 比例 | 必须用步骤 6.5 拿 Figma 原始 SVG path。用户明确说过"不要用猜的" |

---

## 标准工作流

### 步骤 0：先 load 工具

```
ToolSearch query="select:mcp__playwright__browser_navigate,mcp__playwright__browser_snapshot,mcp__playwright__browser_click,mcp__playwright__browser_evaluate,mcp__playwright__browser_press_key,mcp__playwright__browser_take_screenshot,mcp__playwright__browser_resize,mcp__playwright__browser_wait_for"
```

### 步骤 1：扩大 viewport（默认太窄，canvas 被侧栏挤占）

```
browser_resize width=1920 height=1200
```

### 步骤 2：入口

**知道 fileKey 和 nodeId 时 —— 直接 URL**
```
browser_navigate url=https://www.figma.com/design/{fileKey}/?node-id={nodeA}-{nodeB}
```
URL 里 node-id 用 `-`，传给 Figma MCP 工具时用 `:`。

**不知道 fileKey 时 —— 从 recents 找**
```
browser_navigate url=https://www.figma.com/files/recent
browser_snapshot depth=6          # 拿 role="group" 的 file 卡片 ref
browser_click ref={fileGroup} doubleClick=true
```
关键：**必须 `doubleClick: true`** 才打开文件，单 click 只是选中。

### 步骤 3：切 page

Pages 面板的 row 是 `[data-testid="PagesRowWrapper"]`。**JS `.click()` 和 `dispatchEvent` 都打不过
Figma 的 page 切换**。两种可行方式：

A. **用 Playwright 真 click（优先）**：
```
browser_snapshot depth=12
# 在 snapshot 的 .md 文件里找目标 page 名 → 拿 ref=eXXX
browser_click ref=eXXX
```

B. **直接 URL 跳**：
如果知道目标 page 上任意一个 node 的 node-id，直接 `browser_navigate` URL 里带 `node-id={nodeA}-{nodeB}`，Figma 会自动切到那个 node 所在的 page。**判断当前在哪个 page 的标记**：Pages 面板里
选中 page 行的 `<button>` 带 `aria-current="page"`。

检查当前 page：读 `snippets/check-current-page.js`。

### 步骤 4：列 layers + 拿 node-id

左侧 Layers 面板每个 row 有 `data-testid="{nodeA}:{nodeB}-layers-panel-row"`。

读 `snippets/list-layers.js`。

**Virtual scroll 注意**：Layers 面板只渲染可见 layer。如果 layer 被滚出视区，需要先
`chevron` 展开父 group，或者直接用 Figma 的 `Cmd+F` Find。

### 步骤 5：导航到具体 node

```
browser_navigate url=https://www.figma.com/design/{fileKey}/?node-id={nodeA}-{nodeB}
browser_press_key key=Shift+2        # zoom to selection
```

常用快捷键：
- `Shift+2`：zoom to selected
- `Shift+1`：fit whole page
- `Meta+Equal` / `Meta+Minus`：放大/缩小
- `Meta+F`：Find（搜 text 定位 frame）

### 步骤 6：提取属性（颜色/尺寸/border）

选中 node 后，右侧 Properties 面板展示所有属性（Colors / Layout / Borders / Effects）。

读 `snippets/extract-properties.js`。

### 步骤 6.5：导出选中 node 为 SVG（要拿精确 path 时必用）

**场景**：logo/icon 只从 Figma 原始资源导出才精准。`Copy as SVG` 没键盘快捷键（`Cmd+Shift+C` 是 Copy as PNG，不是 SVG，**不要用**），Edit 主菜单走 Playwright 复杂。正确路径是**右侧 Properties panel 底部 Export section**。

**已验证流程**（三次分步 `browser_evaluate`，详细代码见 `snippets/export-svg-via-panel.js`）：

1. **hook + add export** — 在 `window` 上注入 `URL.createObjectURL` 拦截器（Figma 导出走 `URL.createObjectURL(Blob)`），然后点 `button[aria-label="Add export settings"]`
2. **切格式到 SVG**（两步）—
   - 点 PNG combobox（`[role="combobox"]` 里 `textContent=="PNG"` 那个），等 1s 下拉出来
   - 点 `[role="option"]` 里 `textContent=="SVG"` 的 option
3. **点 Export + 拿 blob** — 点 `button` textContent 以 `"Export "` 开头的那个，然后轮询 `window.__capturedBlobs` 拿 `type==='image/svg+xml'` 的 blob，`fetch(blob.url)` 取文字内容

**成功判据**：返回 `{ ok: true, length: 48000+, svg: "<svg ..." }`（整个选中 node 的 SVG 文字）。

**提取子元素**：如果导出的是整页 SVG（比如从 frame 级选中），想要 logo/icon 部分 → 在 SVG 文本里按 path 坐标或 `<linearGradient id="paint0_linear_XXX">` 找相关 `<path fill="url(#paint0_linear_XXX)">`，连同 mask + defs 一并拎出来。写新 SVG 时用 `viewBox="{x} {y} {size} {size}"` 正好截取 logo bbox 周围一个正方形区域（让 logo 在 widget 里居中）。

**陷阱**：
- `mask id` 别和页面其他 mask 冲突，自己改个 suffix（如 `mask0_logo` 替代 `mask0_1281_8037`）
- `linearGradient` 的 `x1/y1/x2/y2` 是**绝对坐标**（`gradientUnits="userSpaceOnUse"`），和 viewBox 坐标系同一套，**不要** 平移 path 而不平移 gradient 坐标，否则渐变方向会错
- 如果平移了 path，必须同步平移 gradient stops 坐标，或者改用 `gradientUnits="objectBoundingBox"`

### 步骤 7：截图对比

```
browser_take_screenshot filename=figma-target.png type=png
```

---

## 快速查找 snippets

| 需求 | Snippet | 一句话描述 |
|-----|---------|-----------|
| 列出 Pages 面板所有 page 名 | `snippets/list-pages.js` | 返回所有 `[data-testid="PagesRowWrapper"]` 的文字 |
| 检查当前选中的 page | `snippets/check-current-page.js` | 找 `aria-current="page"` 的 page row |
| 列出 Layers 面板 + node-id | `snippets/list-layers.js` | 返回 `{nodeId, text}` 数组 |
| 按 text 搜 layer → 拿 node-id | `snippets/find-layer-by-text.js` | 深度搜索目标 text 所在 layer 的 node-id |
| 拿当前选中 node 的 Properties | `snippets/extract-properties.js` | 读右侧面板 Colors/Layout/Borders |
| 关登录 dialog + AI promo popup | `snippets/dismiss-popups.js` | 页面载完后常见的两个 dialog |
| 导出选中 node 为 SVG | `snippets/export-svg-via-panel.js` | Properties → Export → +SVG → Export，截获 blob URL + fetch 内容 |

每个 snippet 都是一个 self-contained function，粘贴进 `browser_evaluate` 的 `function`
参数即可。

---

## 账号说明

| 字段 | 值 |
|-----|---|
| 账号 | <your-figma-email> |
| Seat | View（Organization: Design Sharing株式会社） |
| Tier | starter |
| Figma MCP 限额 | 是（限额后此 skill 生效） |

用 `mcp__claude_ai_Figma__whoami` 查当前登录状态。

---

## URL 格式速查

| 来源 | URL | 变换到 MCP nodeId |
|-----|-----|------------------|
| Figma 分享 URL `figma.com/design/{fileKey}/?node-id=1-2` | fileKey = `{fileKey}` | nodeId = `1:2`（`-` 换 `:`） |
| 带 branch `figma.com/design/:fileKey/branch/:branchKey/...` | fileKey 用 `branchKey` | 同上 |
| Figma Make `figma.com/make/:makeFileKey/...` | fileKey = `makeFileKey` | 需 get_figjam 读 |

---

## 与 MCP 工具互补

- **有配额时**：优先 `mcp__claude_ai_Figma__get_design_context`（一次拿代码+截图+属性）
- **配额耗尽时**：用本 skill 通过 Playwright 拿截图 + 从右侧 Properties 面板读 token
- **要 Code Connect**：只能等配额恢复，Playwright 拿不到
- **要大量截图**：Playwright 更好（没限额）
- **要精确 spec**：用 MCP（属性更全），Playwright 只拿可见属性

---

## 关联 memory

- `reference_figma_playwright_navigation.md` — 2026-03 第一次摸索的记录
- `feedback_figma_mcp_workflow.md` — MCP 限额规律
- `reference_figma_design.md` — project-specific Figma URL 清单

---

## 实战发现 2026-04-23（红包 Figma 抓取）

### 1. Chrome extension bridge mode ≠ isolated Chromium

本次实测 Playwright 打开的是 `chrome-extension://...` URL，是通过 Chrome 原生 extension API 代理
user Chrome，**不是** Playwright 隔离的 Chromium 实例。

对 CrowdStrike 等企业 EDR 环境的含义：
- **不触发恶意软件拦截**（走 Chrome extension API，非 `cliclick`/AppleScript 跨进程）
- 但会操作用户真实 browser tab，用户能看到 Figma 页面切换
- 与用户约定好 "Playwright 操作 Chrome tab 期间不要切走 Figma" 即可

与上次 session（2026-04 之前）的区别：之前因为 `~/.claude.json` worktree entry 缺失，
Playwright MCP 未注册；本次 session 已正确注册，工具可用。

### 2. node-id 可能是 Text label 而不是 frame component

红包抓取中，以下 node-id 均被 Shift+2 zoom 确认为 **Text label**，不是气泡组件：
- `18912:184525`（幸运红包）— SF Pro 400 84px，336×84，#FFFFFF
- `18912:184526`（普通红包）— 同上

**辨识方法**：
1. Shift+2 zoom 后若看到大字（全屏单个词语）而非组件框线 → Text node
2. Layers 面板图标是 **T**（Text）而非 **frame**（矩形框图标）
3. Properties 面板右侧会显示 "Typography" section 而非 "Variants"

真实气泡 frame 应从 Layers 面板找 `Frame 14200XXXXX` 型节点，或命名为 `控制台` 的 frame
（Figma 约定：实际可点组件放在 "控制台" frame 里）。

### 3. Shift+1 / Shift+2 实际差异

| 快捷键 | 行为 | 用途 |
|---|---|---|
| **Shift+2** | Zoom to selected node（精确对齐到选中节点） | 抓单个 frame 截图用这个 |
| **Shift+1** | Fit entire page（看整个 page 全貌） | 想拿大局 overview 用这个 |
| `Meta+=` | Zoom in 一级 | - |
| `Meta+-` | Zoom out 一级 | - |

Shift+2 之后截图才是 "该 node 居中铺满" 的效果；Shift+1 会看到整个 page，frame 很小。

### 4. DOM query 抽 token 的 JS snippet

**`list-layers.js` 模板**（抓 Layers 面板 node-id 用）：

```js
(() => {
  const rows = document.querySelectorAll('[data-testid$="-layers-panel-row"]');
  return Array.from(rows).map(el => {
    const testId = el.getAttribute('data-testid') || '';
    const match  = testId.match(/^(\d+):(\d+)-layers-panel-row$/);
    const nodeId = match ? `${match[1]}:${match[2]}` : null;
    const text   = el.innerText?.trim() || '';
    const scrollAt = el.getBoundingClientRect().top;
    return { nodeId, text, scrollAt };
  }).filter(r => r.nodeId);
})();
```

**`extract-properties.js` 模板**（抓右侧 Properties 面板 Colors 用）：

```js
(() => {
  const panel = document.querySelector('[data-testid="properties-panel"]')
             || document.querySelector('.properties-panel');
  if (!panel) return { error: 'panel not found' };
  const colorEls = panel.querySelectorAll('[data-testid*="color"], .color-swatch');
  return Array.from(colorEls).map(el => ({
    hex: el.getAttribute('data-color') || el.style.backgroundColor || el.innerText,
    label: el.closest('[data-testid*="row"]')?.innerText?.trim()
  }));
})();
```

> 注：Figma 会重构 DOM，data-testid 格式可能随版本变。如果上面 selector 失效，
> 用 `document.querySelector('[data-testid]')` 先探路，再调整。

### 5. 失败兜底原则

如果 Playwright 完全不可用（MCP 没 register，工具 list 里找不到 `mcp__playwright__*`）：

**禁止**：
- 试 AppleScript（CrowdStrike 拦截 -1712）
- 试 cliclick / mac-use 操作真实 Chrome 窗口
- 连续试 stealth workaround

**正确做法**：
1. 直接告知用户：Playwright MCP 未注册，需要重启 Claude Code（新 session 会读 `~/.claude.json` worktree entry）
2. 等用户重启后，先 ToolSearch 验证 `mcp__playwright__browser_navigate` 可用再继续
3. 如果连重启都无效，检查 `~/.claude.json` 里当前 worktree 路径是否有 `mcpServers.playwright` 条目

## Related skills

- **`figma-use`** → **`figma-implement-design`** — use as fallback when Figma MCP is unavailable. Primary path: figma-use; fallback: figma-playwright-fallback.
- **`playwright-figma-scrape`** — more feature-rich Playwright-based scraping when figma-playwright-fallback proves insufficient.
- **`verify-ui`** → **`visual-verdict`** — after scraping Figma, verify implementation matches design.
