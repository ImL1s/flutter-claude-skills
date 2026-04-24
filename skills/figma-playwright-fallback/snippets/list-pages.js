// 列出左侧 Pages 面板所有 page 名 + 判断哪个是当前选中
// 用法：粘贴函数体到 browser_evaluate 的 function 参数
//   function: "() => { ... 下面代码 ... }"
() => {
  const rows = document.querySelectorAll('[data-testid="PagesRowWrapper"]');
  const pages = [];
  rows.forEach(r => {
    const text = r.textContent?.trim() || '';
    // 当前选中 page 的内部 <button> 带 aria-current="page"
    const activeBtn = r.querySelector('button[aria-current="page"]');
    pages.push({
      text,
      isCurrent: !!activeBtn,
    });
  });
  return { count: pages.length, pages };
};
