// ============================================================================
// Figma: 用 Playwright 通过右侧 Export panel 导出选中 node 的 SVG
// ============================================================================
// 前置：已经 navigate 到目标 node（URL 带 node-id，自动选中该 node）
//
// 流程（三步分别 evaluate / press_key）：
//   1. hookAndAddExport:         hook URL.createObjectURL + 点 "Add export settings"
//   2. changeFormatToSvg:        从 PNG 下拉切到 SVG
//   3. clickExportAndGetSvg:     点 Export button → 等 blob → fetch 内容返回
//
// 拿到的 SVG 是**整个选中 node 的 SVG**。如果只要 sub-element（比如 logo），需要
// 先深入选中 logo instance（Enter + Tab + layer row click），然后跑这套流程。
// 或者拿整页 SVG 后用 XML parse 提取目标 path。
// ============================================================================

// === Step 1: hookAndAddExport ===
// 把这个函数体粘到 browser_evaluate 的 function 参数。
() => {
  // hook URL.createObjectURL 截获所有后续 blob 创建
  if (!window.__capturedBlobs) {
    window.__capturedBlobs = [];
    const orig = URL.createObjectURL;
    URL.createObjectURL = function(obj) {
      const url = orig.call(URL, obj);
      window.__capturedBlobs.push({
        url,
        isBlob: obj instanceof Blob,
        size: obj instanceof Blob ? obj.size : null,
        type: obj instanceof Blob ? obj.type : null,
        timestamp: Date.now(),
      });
      return url;
    };
  }
  // 找右侧 Properties panel 里 "Add export settings" 按钮并点
  const btn = document.querySelector('button[aria-label="Add export settings"]');
  if (!btn) return { err: 'no Add export settings button — check that you are logged in and node is selected' };
  btn.click();
  return { clicked: true };
};

// === Step 2: changeFormatToSvg ===
// 点开 PNG combobox + 选 SVG option。
() => {
  // 找 value="PNG" 的 combobox
  const combos = document.querySelectorAll('[role="combobox"]');
  let pngCombo = null;
  combos.forEach(c => { if (c.textContent?.trim() === 'PNG') pngCombo = c; });
  if (!pngCombo) return { err: 'no PNG combobox — did Add export work?' };
  pngCombo.click();
  // 等下拉渲染后再点 SVG（调用方应该在此后 browser_wait_for time=1 再 evaluate 下面）
  // 或者直接 in-line 查找 SVG option
  setTimeout(() => {
    const items = document.querySelectorAll('[role="option"]');
    for (const item of items) {
      if (item.textContent?.trim() === 'SVG') {
        item.click();
        break;
      }
    }
  }, 200);
  return { clicked: 'PNG combobox opened' };
};

// 或者分两次 evaluate 更可靠：第一次点 combobox，browser_wait_for 1s，第二次点 SVG option:
() => {
  const items = document.querySelectorAll('[role="option"]');
  for (const item of items) {
    if (item.textContent?.trim() === 'SVG') {
      item.click();
      return { clicked: 'SVG' };
    }
  }
  return { err: 'no SVG option visible' };
};

// === Step 3: clickExportAndGetSvg ===
// 点 "Export {name}" button + 等 blob 被创建 + fetch 出 SVG 文字内容返回。
async () => {
  // 点 Export button（button text 以 "Export " 开头，后面是 node 名）
  const btns = document.querySelectorAll('button');
  let exportBtn = null;
  for (const b of btns) {
    if (b.textContent?.trim().startsWith('Export ')) { exportBtn = b; break; }
  }
  if (!exportBtn) return { err: 'no Export button' };
  exportBtn.click();

  // 轮询 __capturedBlobs 等待 SVG blob（Figma 异步生成）
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline) {
    const blobs = window.__capturedBlobs || [];
    const svgBlob = blobs.filter(b => b.type === 'image/svg+xml' && b.size > 100).pop();
    if (svgBlob) {
      try {
        const resp = await fetch(svgBlob.url);
        const text = await resp.text();
        return { ok: true, length: text.length, svg: text };
      } catch (e) {
        return { err: 'fetch failed: ' + e.message };
      }
    }
    await new Promise(r => setTimeout(r, 200));
  }
  return { err: 'timeout — no svg blob captured in 8s' };
};
