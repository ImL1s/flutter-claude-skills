// 列出当前 page 左侧 Layers 面板所有可见 layer + node-id
// 注意：virtual scroll 只渲染可见的；滚动/展开父节点后重跑
() => {
  const rows = document.querySelectorAll('[data-testid*="layers-panel-row"]');
  const layers = [];
  rows.forEach(r => {
    const tid = r.getAttribute('data-testid') || '';
    const nodeId = tid.replace('-layers-panel-row', ''); // 格式 "1405:10794"
    const text = (r.textContent || '').trim().substring(0, 100);
    layers.push({ nodeId, text });
  });
  return { count: layers.length, layers };
};
