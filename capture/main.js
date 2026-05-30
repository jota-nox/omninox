const { app, BrowserWindow, globalShortcut, ipcMain, dialog, Tray, Menu, nativeImage } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { execFile } = require('child_process');

// Config
const DEFAULT_VAULT_PATH = path.join(os.homedir(), 'Documents', 'omninox');
const CONFIG_FILE = path.join(os.homedir(), '.config', 'omninox-capture', 'config.json');

function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_FILE)) return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf-8'));
  } catch {}
  return {};
}

function saveConfig(config) {
  const dir = path.dirname(CONFIG_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2), 'utf-8');
}

function getVaultPath() {
  return loadConfig().vaultPath || DEFAULT_VAULT_PATH;
}

let mainWindow = null;
let tray = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 480,
    height: 180,
    minHeight: 140,
    maxHeight: 500,
    frame: false,
    transparent: true,
    resizable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    show: false,
    backgroundColor: '#00000000',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'src', 'index.html'));

  mainWindow.on('blur', () => {
    if (mainWindow && mainWindow.isVisible()) {
      hideWindow();
    }
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

function showWindow() {
  if (!mainWindow) createWindow();
  mainWindow.center();
  mainWindow.show();
  mainWindow.focus();
  mainWindow.webContents.send('window-shown');
}

function hideWindow() {
  if (mainWindow) {
    mainWindow.webContents.send('window-hidden');
    mainWindow.hide();
  }
}

function toggleWindow() {
  if (mainWindow && mainWindow.isVisible()) {
    hideWindow();
  } else {
    showWindow();
  }
}

async function showVaultPathPicker() {
  const result = await dialog.showOpenDialog({
    title: 'Selecionar pasta do vault Obsidian',
    defaultPath: getVaultPath(),
    properties: ['openDirectory'],
    buttonLabel: 'Selecionar vault',
  });
  if (!result.canceled && result.filePaths[0]) {
    const config = loadConfig();
    config.vaultPath = result.filePaths[0];
    saveConfig(config);
    buildTrayMenu();
  }
}

function createTray() {
  const icon = nativeImage.createFromPath(path.join(__dirname, 'assets', 'iconTemplate.png'));
  icon.setTemplateImage(true);
  tray = new Tray(icon);
  tray.setToolTip('OmniNox Capture — arraste arquivos aqui');

  buildTrayMenu();
  tray.on('click', toggleWindow);

  tray.on('drop-files', (_event, filePaths) => {
    showWindow();
    const sendFiles = () => {
      const files = filePaths.map((fp) => {
        const data = fs.readFileSync(fp).toString('base64');
        return { originalName: path.basename(fp), data };
      });
      mainWindow.webContents.send('tray-files-dropped', files);
    };
    if (mainWindow.webContents.isLoading()) {
      mainWindow.webContents.once('did-finish-load', sendFiles);
    } else {
      setTimeout(sendFiles, 100);
    }
  });
}

function buildTrayMenu() {
  const loginSettings = app.getLoginItemSettings();
  const vaultName = path.basename(getVaultPath());
  const contextMenu = Menu.buildFromTemplate([
    { label: 'Capture (Cmd+Shift+N)', click: showWindow },
    { type: 'separator' },
    { label: `Vault: ${vaultName}`, enabled: false },
    { label: 'Mudar vault...', click: showVaultPathPicker },
    { type: 'separator' },
    {
      label: 'Abrir no login',
      type: 'checkbox',
      checked: loginSettings.openAtLogin,
      click: (menuItem) => {
        app.setLoginItemSettings({ openAtLogin: menuItem.checked });
      },
    },
    { type: 'separator' },
    { label: 'Quit', click: () => app.quit() },
  ]);
  tray.setContextMenu(contextMenu);
}

function slugify(text, maxLen = 30) {
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

function saveNote(text, attachments) {
  const vaultPath = getVaultPath();
  const inboxPath = path.join(vaultPath, '00 Inbox');
  const attachmentsPath = path.join(inboxPath, 'attachments');

  if (!fs.existsSync(inboxPath)) fs.mkdirSync(inboxPath, { recursive: true });
  if (attachments.length > 0 && !fs.existsSync(attachmentsPath)) {
    fs.mkdirSync(attachmentsPath, { recursive: true });
  }

  const now = new Date();
  const dateStr = now.toISOString().slice(0, 10);
  const timeStr = now.toTimeString().slice(0, 5).replace(':', '');

  const lines = text.trim().split('\n');
  const title = lines[0].replace(/^#+\s*/, '').trim();
  const slug = slugify(title) || 'nota';
  const filename = `${dateStr}_${timeStr}_${slug}.md`;

  const attachmentRefs = [];
  for (const att of attachments) {
    const ext = path.extname(att.originalName) || '.bin';
    const attName = `${dateStr}_${timeStr}_${slugify(path.basename(att.originalName, ext))}${ext}`;
    const destPath = path.join(attachmentsPath, attName);

    const buffer = Buffer.from(att.data, 'base64');
    fs.writeFileSync(destPath, buffer);

    const isImage = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg'].includes(ext.toLowerCase());
    attachmentRefs.push(isImage ? `![[attachments/${attName}]]` : `[[attachments/${attName}]]`);
  }

  const frontmatter = [
    '---',
    'tags:',
    '  - status/inbox',
    `date: ${dateStr}`,
    '---',
  ].join('\n');

  let body = text.trim();
  if (attachmentRefs.length > 0) {
    body += '\n\n' + attachmentRefs.join('\n');
  }

  const content = `${frontmatter}\n\n${body}\n`;
  const filePath = path.join(inboxPath, filename);
  fs.writeFileSync(filePath, content, 'utf-8');

  return { filename, path: filePath };
}

// IPC handlers
ipcMain.handle('save-note', async (_event, { text, attachments }) => {
  try {
    const result = saveNote(text, attachments || []);
    return { success: true, ...result };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('hide-window', async () => {
  hideWindow();
});

ipcMain.handle('resize-window', async (_event, height) => {
  if (mainWindow) {
    const [width] = mainWindow.getSize();
    const newHeight = Math.max(140, Math.min(500, height));
    mainWindow.setSize(width, newHeight, true);
  }
});

ipcMain.handle('pick-file', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openFile', 'multiSelections'],
  });
  if (result.canceled) return [];

  return result.filePaths.map((fp) => {
    const data = fs.readFileSync(fp).toString('base64');
    return { originalName: path.basename(fp), data };
  });
});

ipcMain.handle('get-config', () => ({ vaultPath: getVaultPath() }));

ipcMain.handle('set-vault-path', (_event, newPath) => {
  const config = loadConfig();
  config.vaultPath = newPath;
  saveConfig(config);
  buildTrayMenu();
  return { success: true };
});

// OCR handler
const OCR_BIN = path.join(__dirname, 'ocr');

ipcMain.handle('run-ocr', async (_event, base64Data) => {
  const tmpPath = path.join(app.getPath('temp'), `omninox-ocr-${Date.now()}.png`);
  try {
    const buffer = Buffer.from(base64Data, 'base64');
    fs.writeFileSync(tmpPath, buffer);

    return await new Promise((resolve) => {
      execFile(OCR_BIN, [tmpPath], { timeout: 10000 }, (error, stdout, stderr) => {
        try { fs.unlinkSync(tmpPath); } catch {}

        if (error) {
          resolve({ success: false, error: stderr || error.message });
        } else {
          resolve({ success: true, text: stdout.trim() });
        }
      });
    });
  } catch (err) {
    try { fs.unlinkSync(tmpPath); } catch {}
    return { success: false, error: err.message };
  }
});

// App lifecycle
app.whenReady().then(() => {
  app.dock?.hide();

  createWindow();
  createTray();

  globalShortcut.register('CommandOrControl+Shift+N', toggleWindow);

  app.on('activate', () => {
    if (!mainWindow) createWindow();
  });
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});

app.on('window-all-closed', (e) => {
  e.preventDefault();
});
