const toast = document.querySelector('.download-toast');
const dialog = document.querySelector('#preview-dialog');
let lastPreviewTrigger;
let lastDownloadTrigger;

for (const link of document.querySelectorAll('a[download]')) {
  link.addEventListener('click', () => {
    lastDownloadTrigger = link;
    toast.hidden = false;
    // The browser owns the download. Keep the help link available until dismissed.
  });
}

toast.querySelector('button').addEventListener('click', () => {
  toast.hidden = true;
  lastDownloadTrigger?.focus();
});

toast.querySelector('a').addEventListener('click', () => {
  toast.hidden = true;
  document.querySelector('#install-title').focus({ preventScroll: true });
});

for (const trigger of document.querySelectorAll('[aria-controls="preview-dialog"]')) {
  trigger.addEventListener('click', event => {
    if (typeof dialog.showModal !== 'function') return;
    event.preventDefault();
    lastPreviewTrigger = trigger;
    dialog.showModal();
  });
}

dialog.querySelector('.dialog-close').addEventListener('click', () => dialog.close());
dialog.addEventListener('click', event => {
  const bounds = dialog.getBoundingClientRect();
  if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
});
dialog.addEventListener('close', () => lastPreviewTrigger?.focus());

if (!/Macintosh|MacIntel/.test(navigator.userAgent) || navigator.maxTouchPoints > 1) {
  document.querySelector('#platform-note').hidden = false;
}
