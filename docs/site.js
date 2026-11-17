const toast = document.querySelector('.download-toast');
let dismissTimer;
for (const link of document.querySelectorAll('a[download]')) {
  link.addEventListener('click', () => {
    toast.hidden = false;
    clearTimeout(dismissTimer);
    dismissTimer = setTimeout(() => { toast.hidden = true; }, 12000);
  });
}
toast.querySelector('button').addEventListener('click', () => { toast.hidden = true; });
if (!/Macintosh|MacIntel/.test(navigator.userAgent) || navigator.maxTouchPoints > 1) {
  document.querySelector('#platform-note').hidden = false;
}
