const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('capture', {
  saveNote: (data) => ipcRenderer.invoke('save-note', data),
  hideWindow: () => ipcRenderer.invoke('hide-window'),
  resizeWindow: (height) => ipcRenderer.invoke('resize-window', height),
  pickFile: () => ipcRenderer.invoke('pick-file'),
  runOcr: (base64Data) => ipcRenderer.invoke('run-ocr', base64Data),
  getConfig: () => ipcRenderer.invoke('get-config'),
  setVaultPath: (p) => ipcRenderer.invoke('set-vault-path', p),
  onWindowShown: (callback) => ipcRenderer.on('window-shown', callback),
  onWindowHidden: (callback) => ipcRenderer.on('window-hidden', callback),
  onTrayFilesDropped: (callback) => ipcRenderer.on('tray-files-dropped', (_e, files) => callback(files)),
});
