// 读右侧 Properties 面板的 Colors / Layout / Borders / Effects
// 前置：已经选中目标 node（browser_navigate 到该 node-id 即可）
() => {
  const out = {};
  const rightSidebar = document.querySelector('[role="region"][aria-label*="Right sidebar" i]')
    || document.querySelector('aside')
    || document.body;
  const text = rightSidebar.textContent || '';

  // 抓 HEX 色值（可能多个 fill/stroke）
  const hexes = Array.from(text.matchAll(/#[0-9A-F]{6}(?:[0-9A-F]{2})?/gi)).map(m => m[0]);
  out.hexColors = [...new Set(hexes)];

  // 抓 Width / Height（Figma 格式 "1234px"）
  const widthMatch = text.match(/W(?:idth)?\s*(\d+(?:\.\d+)?)\s*(?:px)?/);
  const heightMatch = text.match(/H(?:eight)?\s*(\d+(?:\.\d+)?)\s*(?:px)?/);
  if (widthMatch) out.width = widthMatch[1] + 'px';
  if (heightMatch) out.height = heightMatch[1] + 'px';

  // 抓 Radius / Border
  const radiusMatch = text.match(/Radius\s*(\d+(?:\.\d+)?)\s*(?:px)?/);
  const borderMatch = text.match(/Border\s*(\d+(?:\.\d+)?)\s*(?:px)?/);
  if (radiusMatch) out.radius = radiusMatch[1] + 'px';
  if (borderMatch) out.border = borderMatch[1] + 'px';

  // 抓 Linear gradient stops（如果 fill 是渐变）
  const gradient = text.match(/(?:Linear|Radial)\s*gradient[^]*?(?=\n{2}|$)/);
  if (gradient) out.gradientRaw = gradient[0].substring(0, 300);

  // 完整 raw text 备查
  out.rawPreview = text.substring(0, 1000);

  return out;
};
