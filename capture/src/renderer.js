const input = document.getElementById('input');
const attachmentsEl = document.getElementById('attachments');
const feedbackEl = document.getElementById('feedback');
const btnAttach = document.getElementById('btn-attach');
const appEl = document.getElementById('app');
const slugPreviewEl = document.getElementById('slug-preview');

let attachments = []; // { originalName, data (base64), isImage }
let ocrPending = 0;
let isSaving = false;

// --- Window events ---

window.capture.onWindowShown(() => {
  input.focus();
  adjustHeight();
});

// --- Slug preview ---

function slugifyPreview(text, maxLen = 30) {
  const slug = text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
  if (slug.length <= maxLen) return slug;
  const truncated = slug.slice(0, maxLen);
  const lastDash = truncated.lastIndexOf('-');
  return lastDash > 10 ? truncated.slice(0, lastDash) : truncated;
}

function updateSlugPreview() {
  const text = input.value.trim();
  if (!text) {
    slugPreviewEl.textContent = '';
    return;
  }
  const firstLine = text.split('\n')[0].replace(/^#+\s*/, '').trim();
  const slug = slugifyPreview(firstLine);
  if (slug) {
    const now = new Date();
    const dateStr = now.toISOString().slice(0, 10);
    const timeStr = now.toTimeString().slice(0, 5).replace(':', '');
    slugPreviewEl.textContent = `${dateStr}_${timeStr}_${slug}.md`;
  } else {
    slugPreviewEl.textContent = '';
  }
}

// --- Text area auto-resize ---

input.addEventListener('input', () => {
  adjustHeight();
  updateSlugPreview();
});

function adjustHeight() {
  input.style.height = 'auto';
  input.style.height = Math.min(input.scrollHeight, 260) + 'px';

  const content = document.querySelector('.content');
  const totalHeight = 12 + content.scrollHeight + 8;
  window.capture.resizeWindow(Math.ceil(totalHeight));
}

// --- Keyboard shortcuts ---

document.addEventListener('keydown', async (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
    e.preventDefault();
    await save();
    return;
  }

  if (e.key === 'Escape') {
    e.preventDefault();
    window.capture.hideWindow();
    return;
  }
});

// --- Save ---

async function save() {
  if (isSaving) return;
  const text = input.value.trim();
  if (!text && attachments.length === 0) return;

  isSaving = true;
  try {
    const result = await window.capture.saveNote({
      text: text || 'Nota sem texto',
      attachments: attachments.map((a) => ({ originalName: a.originalName, data: a.data })),
    });

    if (result.success) {
      input.value = '';
      attachments = [];
      renderAttachments();
      updateSlugPreview();
      showFeedback();
    }
  } finally {
    isSaving = false;
  }
}

function showFeedback() {
  feedbackEl.style.display = 'flex';
  setTimeout(() => {
    feedbackEl.style.display = 'none';
    window.capture.hideWindow();
  }, 400);
}

// --- Attachments ---

btnAttach.addEventListener('click', async () => {
  const files = await window.capture.pickFile();
  for (const file of files) {
    addAttachment(file.originalName, file.data);
  }
});

function addAttachment(name, base64Data) {
  const ext = name.split('.').pop().toLowerCase();
  const isImage = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].includes(ext);
  attachments.push({ originalName: name, data: base64Data, isImage });
  renderAttachments();

  if (isImage) {
    runOcrOnImage(base64Data);
  }
}

async function runOcrOnImage(base64Data) {
  ocrPending++;
  setOcrIndicator('loading');

  const result = await window.capture.runOcr(base64Data);

  ocrPending--;

  if (result.success && result.text) {
    if (ocrPending === 0) hideOcrIndicator();

    const rawLines = result.text.split('\n');
    const merged = [];
    for (const line of rawLines) {
      const prev = merged.length ? merged[merged.length - 1] : null;
      const startsNewBlock = /^\d+[\.\)]/.test(line.trim());
      const prevEnded = prev === null || /[.!?:;]$/.test(prev.trim());
      if (prevEnded || startsNewBlock) {
        merged.push(line);
      } else {
        merged[merged.length - 1] += ' ' + line.trim();
      }
    }

    const separator = input.value.trim() ? '\n\n---\n> **Texto extraído:**\n' : '';
    const formatted = merged.map((l) => '> ' + l).join('\n');
    input.value = input.value.trimEnd() + separator + formatted;
    adjustHeight();
    updateSlugPreview();
  } else {
    if (ocrPending === 0) setOcrIndicator('error');
  }
}

function setOcrIndicator(state) {
  let indicator = document.getElementById('ocr-indicator');
  if (!indicator) {
    indicator = document.createElement('div');
    indicator.id = 'ocr-indicator';
    document.querySelector('.footer').prepend(indicator);
  }
  if (state === 'loading') {
    indicator.className = 'ocr-indicator';
    indicator.textContent = 'Extraindo texto...';
  } else if (state === 'error') {
    indicator.className = 'ocr-indicator ocr-error';
    indicator.textContent = 'OCR falhou';
    setTimeout(() => hideOcrIndicator(), 2500);
  }
}

function hideOcrIndicator() {
  const indicator = document.getElementById('ocr-indicator');
  if (indicator) indicator.remove();
}

function removeAttachment(index) {
  attachments.splice(index, 1);
  renderAttachments();
}

function renderAttachments() {
  if (attachments.length === 0) {
    attachmentsEl.style.display = 'none';
    attachmentsEl.innerHTML = '';
    adjustHeight();
    return;
  }

  attachmentsEl.style.display = 'flex';
  attachmentsEl.innerHTML = attachments
    .map((att, i) => {
      const preview = att.isImage
        ? `<img src="data:image/${att.originalName.split('.').pop()};base64,${att.data}" alt="">`
        : `<svg class="file-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>`;
      return `
        <div class="attachment-item">
          ${preview}
          <span class="name">${att.originalName}</span>
          <span class="remove" onclick="removeAttachment(${i})">&times;</span>
        </div>
      `;
    })
    .join('');

  adjustHeight();
}

// --- Drag & Drop ---

let dragCounter = 0;
let dropOverlay = null;

document.addEventListener('dragenter', (e) => {
  e.preventDefault();
  dragCounter++;
  if (dragCounter === 1) showDropOverlay();
});

document.addEventListener('dragleave', (e) => {
  e.preventDefault();
  dragCounter--;
  if (dragCounter === 0) hideDropOverlay();
});

document.addEventListener('dragover', (e) => {
  e.preventDefault();
});

document.addEventListener('drop', (e) => {
  e.preventDefault();
  dragCounter = 0;
  hideDropOverlay();

  const files = Array.from(e.dataTransfer.files);
  for (const file of files) {
    const reader = new FileReader();
    reader.onload = () => {
      const base64 = reader.result.split(',')[1];
      addAttachment(file.name, base64);
    };
    reader.readAsDataURL(file);
  }
});

function showDropOverlay() {
  if (dropOverlay) return;
  dropOverlay = document.createElement('div');
  dropOverlay.className = 'drop-overlay';
  dropOverlay.textContent = 'Soltar aqui';
  appEl.appendChild(dropOverlay);
}

function hideDropOverlay() {
  if (dropOverlay) {
    dropOverlay.remove();
    dropOverlay = null;
  }
}

// --- Paste images ---

document.addEventListener('paste', (e) => {
  const items = Array.from(e.clipboardData?.items || []);
  for (const item of items) {
    if (item.type.startsWith('image/')) {
      e.preventDefault();
      const file = item.getAsFile();
      const ext = item.type.split('/')[1] || 'png';
      const name = `clipboard-${Date.now()}.${ext}`;
      const reader = new FileReader();
      reader.onload = () => {
        const base64 = reader.result.split(',')[1];
        addAttachment(name, base64);
      };
      reader.readAsDataURL(file);
    }
  }
});

// --- Files dropped on tray icon ---

window.capture.onTrayFilesDropped((files) => {
  for (const file of files) {
    addAttachment(file.originalName, file.data);
  }
});

// Initial sizing
adjustHeight();
