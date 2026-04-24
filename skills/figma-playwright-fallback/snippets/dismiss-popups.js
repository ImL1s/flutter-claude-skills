// 页面载完后常见的 dialog 一次性关掉
// - "You're currently signed in as ..."
// - "Unblock yourself with AI"
// - Cookie banner
() => {
  const dialogs = document.querySelectorAll('[role="dialog"], [role="alertdialog"]');
  const closed = [];
  dialogs.forEach(d => {
    const closeBtn = d.querySelector('button[aria-label*="Close" i], button[aria-label*="Dismiss" i], button[aria-label*="OK" i]');
    if (closeBtn) {
      closeBtn.click();
      closed.push(d.textContent?.substring(0, 60));
    }
  });
  // 也关 Figma 的 AI promo close-X
  document.querySelectorAll('button[aria-label="Dismiss prompt box"]').forEach(b => {
    b.click();
    closed.push('AI promo dismissed');
  });
  return { closed };
};
