// 展开 Layers 面板里某个 group，让子 layers 进入 virtual scroll 可渲染范围
// 用法：nodeId 参数换成目标 group 的 node-id（比如 "1215:18268"）
() => {
  const TARGET_NODE_ID = '1215:18268'; // ← 改这里
  const rows = document.querySelectorAll('[data-testid*="layers-panel-row"]');
  for (const r of rows) {
    const tid = r.getAttribute('data-testid') || '';
    if (tid.startsWith(TARGET_NODE_ID + '-')) {
      // chevron 通常是 row 内的第一个 button（不是 layer 本身的 visibility icon）
      const chevron = r.querySelector('button');
      if (chevron) {
        chevron.click();
        return { expanded: true, nodeId: TARGET_NODE_ID };
      }
      return { expanded: false, reason: 'chevron not found' };
    }
  }
  return { expanded: false, reason: 'row not rendered; scroll layers panel first' };
};
