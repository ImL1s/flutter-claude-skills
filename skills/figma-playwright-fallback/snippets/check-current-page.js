// 快速判断当前 URL node-id 所在的 page 是哪个
// 用法：粘贴函数体到 browser_evaluate
() => {
  const active = document.querySelector('[data-testid="PagesRowWrapper"] button[aria-current="page"]');
  if (!active) return { found: false, hint: 'Pages 面板未渲染，先确认 File 标签展开' };
  // 往上找 PagesRowWrapper 拿 page 名
  let p = active;
  while (p && p.getAttribute('data-testid') !== 'PagesRowWrapper') p = p.parentElement;
  return {
    found: true,
    currentPageText: p?.textContent?.trim(),
  };
};
