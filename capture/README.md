# OmniNox Capture

App Electron de menubar (macOS) para captura rápida no inbox do vault OmniNox.

- `Cmd+Shift+N` → abre a janela de captura em qualquer lugar
- Drag-and-drop de arquivos no ícone da menubar
- Paste de imagem do clipboard → OCR automático (binário Swift nativo)
- Salva em `<vault>/00 Inbox/` com frontmatter `tags: [status/inbox]`

## Configuração

Na primeira execução, o app aponta para `~/Documents/omninox` por default.
Use **Menubar → Mudar vault...** para apontar pro seu vault real.

A config persiste em `~/.config/omninox-capture/config.json`.

## Build

```bash
npm install
npm run build
# Resultado: dist/mac-arm64/OmniNox Capture.app
```

Para instalar:

```bash
cp -R dist/mac-arm64/"OmniNox Capture.app" /Applications/
```

## OCR

O binário `ocr` é pré-compilado para Mac ARM64 (Apple Silicon).
Para Intel Mac ou recompilação:

```bash
swiftc -O ocr.swift -o ocr
```

## Installer PKG (opcional)

Para gerar um `.pkg` distribuível que também instala Obsidian + dependências Homebrew:

```bash
cd installer
./build.sh
# Resultado: dist/OmniNox Install.pkg
```
