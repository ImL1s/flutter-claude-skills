// 按 text（或部分 text）搜 layer，返回其 node-id
// 用法：function body 里把 TARGET 换成要搜的字串，或用闭包传参：
//   function: "() => { const TARGET = '登录'; ... }"
() => {
  const TARGET = '登录'; // ← 改这里
  const rows = document.querySelectorAll('[data-testid*="layers-panel-row"]');
  const hits = [];
  rows.forEach(r => {
    const text = (r.textContent || '').trim();
    if (text.includes(TARGET)) {
      const tid = r.getAttribute('data-testid') || '';
      hits.push({
        nodeId: tid.replace('-layers-panel-row', ''),
        text: text.substring(0, 100),
      });
    }
  });
  return {
    hits,
    hint: hits.length === 0 ? 'Virtual scroll 可能未渲染目标 layer。展开父 group 或用 Cmd+F Figma Find' : null,
  };
};
