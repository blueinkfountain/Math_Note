
// Headings / theorem-like blocks to target
const targetSelectors = ['h1', 'h2', 'h3', '.theorem', '.definition', '.proof', '.equation'];

// Slugify text to an id
function slugify(text) {
  return text.toLowerCase()
    .replace(/[^a-z0-9가-힣\s-]/g, '')
    .trim()
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-');
}

function ensureIds() {
  const used = new Set();
  document.querySelectorAll(targetSelectors.join(',')).forEach(node => {
    if (!node.id || node.id.trim() === '') {
      const base = slugify(node.textContent || 'section').slice(0, 64) || 'sec';
      let id = base;
      let i = 1;
      while (used.has(id) || document.getElementById(id)) {
        id = `${base}-${i++}`;
      }
      node.id = id;
      used.add(id);
    }
  });
}

function injectButtons() {
  const selectorsWithIds = targetSelectors.map(s => `${s}[id]`);
  document.querySelectorAll(selectorsWithIds.join(',')).forEach(node => {
    const id = node.getAttribute('id');
    if (!id) return;
    if (node.querySelector('.comment-btn')) return;

    const btn = document.createElement('button');
    btn.textContent = '💬 댓글';
    btn.className = 'comment-btn';
    btn.type = 'button';
    btn.addEventListener('click', () => openCommentsFor(id));
    // place at end of heading line
    if (/^H[1-6]$/.test(node.tagName)) {
      node.appendChild(btn);
    } else {
      // theorem/definition blocks: add to first child or header area
      node.insertBefore(btn, node.firstChild);
    }
  });
}

function openCommentsFor(anchorId) {
  const dlg = document.getElementById('comment-dialog');
  const target = document.getElementById('comment-target');
  if (!dlg || !target) return;

  const threadKey = `${location.pathname}#${anchorId}`;
  target.dataset.thread = threadKey;

  const iframe = document.querySelector('iframe.giscus-frame');
  if (iframe && iframe.contentWindow) {
    iframe.contentWindow.postMessage({
      giscus: {
        setConfig: {
          term: threadKey,
          mapping: 'specific'
        }
      }
    }, 'https://giscus.app');
  }
  if (typeof dlg.showModal === 'function') dlg.showModal();
  else dlg.setAttribute('open', '');
}

function initClose() {
  const closeBtn = document.getElementById('comment-close');
  if (closeBtn) {
    closeBtn.addEventListener('click', () => {
      const dlg = document.getElementById('comment-dialog');
      if (dlg && typeof dlg.close === 'function') dlg.close();
      else dlg.removeAttribute('open');
    });
  }
}

document.addEventListener('DOMContentLoaded', () => {
  ensureIds();     // <-- assign IDs if headings lacked them
  injectButtons(); // <-- then add buttons
  initClose();
});
