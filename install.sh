#!/bin/bash
# OmniNox Installer
# Instala o sistema PARA + OmniNox com hooks do Claude Code.
# Uso: bash install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/template"

# ─── cores ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

ok()   { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${BLUE}→${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1"; exit 1; }
ask()  { echo -e "${BLUE}?${NC} $1"; }

# ─── cabeçalho ────────────────────────────────────────────────────────────────
echo ""
echo "  OmniNox Installer"
echo "  Sistema PARA + OmniNox para Claude Code"
echo "  ──────────────────────────────────────────"
echo ""

# ─── 1. onde criar o vault ────────────────────────────────────────────────────
ask "Onde criar o vault? (diretório pai)"
echo "  Padrão: $HOME/Documents"
read -r -p "  → " VAULT_PARENT
VAULT_PARENT="${VAULT_PARENT:-$HOME/Documents}"
VAULT_PARENT="${VAULT_PARENT/#\~/$HOME}"  # expande ~

if [ ! -d "$VAULT_PARENT" ]; then
  err "Diretório não encontrado: $VAULT_PARENT"
fi

echo ""
ask "Nome do vault (pasta que será criada dentro de $VAULT_PARENT)"
echo "  Padrão: meu-vault"
read -r -p "  → " VAULT_NAME
VAULT_NAME="${VAULT_NAME:-meu-vault}"

VAULT_PATH="$VAULT_PARENT/$VAULT_NAME"

if [ -d "$VAULT_PATH" ]; then
  warn "Pasta '$VAULT_PATH' já existe."
  read -r -p "  Continuar e instalar o OmniNox dentro dela? [s/N] " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
    echo "Instalação cancelada."
    exit 0
  fi
fi

# ─── 2. identidade ────────────────────────────────────────────────────────────
echo ""
ask "Qual é o seu nome?"
read -r -p "  → " USER_NAME
USER_NAME="${USER_NAME:-Usuário}"

echo ""
ask "Qual é a sua cidade/localização?"
read -r -p "  → " USER_LOCATION
USER_LOCATION="${USER_LOCATION:-}"

echo ""
ask "Idioma preferido?"
echo "  Padrão: Português brasileiro"
read -r -p "  → " USER_LANG
USER_LANG="${USER_LANG:-Português brasileiro}"

# ─── 3. wing inicial (opcional) ───────────────────────────────────────────────
echo ""
ask "Criar uma wing inicial agora? (deixe em branco para pular)"
echo "  Ex: trabalho, pessoal, projeto-x"
read -r -p "  → " FIRST_WING

# ─── 3b. capture (opcional) ───────────────────────────────────────────────────
INSTALL_CAPTURE="n"
if [ -d "$SCRIPT_DIR/capture" ]; then
  echo ""
  ask "Instalar OmniNox Capture também? (menubar app — Cmd+Shift+N para captura rápida)"
  echo "  Requer Node.js + npm. Default: S"
  read -r -p "  → [S/n] " CAP
  if [[ ! "$CAP" =~ ^[nN]$ ]]; then
    INSTALL_CAPTURE="y"
  fi
fi

# ─── resumo ───────────────────────────────────────────────────────────────────
echo ""
echo "  ─── Resumo da instalação ──────────────────"
echo "  Vault:     $VAULT_PATH"
echo "  OmniNox:   $VAULT_PATH/Areas/omninox"
echo "  Hook:      $HOME/.claude/hooks/session-start.sh"
echo "  Nome:      $USER_NAME"
[ -n "$USER_LOCATION" ] && echo "  Local:     $USER_LOCATION"
echo "  Idioma:    $USER_LANG"
[ -n "$FIRST_WING" ] && echo "  Wing:      $FIRST_WING"
[ "$INSTALL_CAPTURE" = "y" ] && echo "  Capture:   sim (build + /Applications)"
echo "  ────────────────────────────────────────────"
echo ""
read -r -p "  Confirmar instalação? [S/n] " GO
if [[ "$GO" =~ ^[nN]$ ]]; then
  echo "Instalação cancelada."
  exit 0
fi

echo ""
info "Instalando..."

# ─── 4. criar estrutura PARA ──────────────────────────────────────────────────
mkdir -p "$VAULT_PATH/10 Projetos"
mkdir -p "$VAULT_PATH/20 Áreas"
mkdir -p "$VAULT_PATH/30 Recursos"
mkdir -p "$VAULT_PATH/40 Arquivo"
mkdir -p "$VAULT_PATH/90 Templates"
mkdir -p "$VAULT_PATH/00 Inbox"
ok "Estrutura PARA criada"

# ─── 5. copiar omninox ───────────────────────────────────────────────────────
ON_DEST="$VAULT_PATH/Areas/omninox"
mkdir -p "$ON_DEST"
cp -r "$TEMPLATE_DIR/omninox/." "$ON_DEST/"
ok "OmniNox instalado em $ON_DEST"

# ─── 6. copiar CLAUDE.md ──────────────────────────────────────────────────────
CLAUDE_DEST="$VAULT_PATH/CLAUDE.md"
if [ -f "$CLAUDE_DEST" ]; then
  warn "CLAUDE.md já existe em $VAULT_PATH."
  read -r -p "  Sobrescrever? [s/N] " OW
  if [[ "$OW" =~ ^[sS]$ ]]; then
    cp "$TEMPLATE_DIR/CLAUDE.md" "$CLAUDE_DEST"
    ok "CLAUDE.md sobrescrito"
  else
    warn "CLAUDE.md mantido sem alteração"
  fi
else
  cp "$TEMPLATE_DIR/CLAUDE.md" "$CLAUDE_DEST"
  ok "CLAUDE.md criado"
fi

# ─── 7. preencher _identity.md ────────────────────────────────────────────────
TODAY=$(date +%Y-%m-%d)
IDENTITY_FILE="$ON_DEST/_identity.md"

sed -i '' \
  -e "s/__NOME__/$USER_NAME/g" \
  -e "s/__LOCALIZACAO__/${USER_LOCATION:-—}/g" \
  -e "s/__IDIOMA__/$USER_LANG/g" \
  -e "s/__VAULT_NAME__/$VAULT_NAME/g" \
  "$IDENTITY_FILE"
ok "_identity.md preenchido"

# ─── 8. preencher _wake-up.md ─────────────────────────────────────────────────
WAKE_FILE="$ON_DEST/_wake-up.md"
sed -i '' "s/__DATA__/$TODAY/g" "$WAKE_FILE"
ok "_wake-up.md inicializado"

# ─── 9. instalar hook global ──────────────────────────────────────────────────
HOOK_DIR="$HOME/.claude/hooks"
HOOK_DEST="$HOOK_DIR/session-start.sh"
mkdir -p "$HOOK_DIR"

# Substitui placeholder pelo path real
sed "s|__OMNINOX_PATH__|$ON_DEST|g" \
  "$TEMPLATE_DIR/hooks/session-start.sh" > "$HOOK_DEST"
chmod +x "$HOOK_DEST"
ok "Hook instalado em $HOOK_DEST"

# ─── 10. merge settings.json ──────────────────────────────────────────────────
SETTINGS_FILE="$HOME/.claude/settings.json"
SNIPPET="$SCRIPT_DIR/claude-config/settings-snippet.json"

if [ ! -f "$SETTINGS_FILE" ]; then
  cp "$SNIPPET" "$SETTINGS_FILE"
  ok "settings.json criado"
else
  # Verifica se o hook já está configurado
  if grep -q "session-start.sh" "$SETTINGS_FILE" 2>/dev/null; then
    warn "Hook já configurado em settings.json — sem alteração"
  else
    # Merge usando Python (disponível em qualquer macOS)
    python3 - "$SETTINGS_FILE" "$SNIPPET" << 'PYEOF'
import json, sys

existing_path = sys.argv[1]
snippet_path  = sys.argv[2]

with open(existing_path) as f:
    existing = json.load(f)
with open(snippet_path) as f:
    snippet = json.load(f)

# Merge hooks.SessionStart
hooks = existing.setdefault("hooks", {})
ss = hooks.setdefault("SessionStart", [])
snippet_ss = snippet.get("hooks", {}).get("SessionStart", [])
ss.extend(snippet_ss)

with open(existing_path, "w") as f:
    json.dump(existing, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
    ok "Hook adicionado ao settings.json existente"
  fi
fi

# ─── 11. tornar omninox.sh executável ─────────────────────────────────────────
chmod +x "$ON_DEST/.scripts/omninox.sh"
ok "omninox.sh marcado como executável"

# ─── 12. wing inicial (opcional) ──────────────────────────────────────────────
if [ -n "$FIRST_WING" ]; then
  bash "$ON_DEST/.scripts/omninox.sh" new-wing "$FIRST_WING" "Wing inicial" 2>/dev/null \
    && ok "Wing '$FIRST_WING' criada" \
    || warn "Não foi possível criar wing '$FIRST_WING' — crie depois com omninox.sh"
fi

# ─── 13. capture (opcional) ───────────────────────────────────────────────────
if [ "$INSTALL_CAPTURE" = "y" ]; then
  CAPTURE_DIR="$SCRIPT_DIR/capture"
  if ! command -v npm >/dev/null 2>&1; then
    warn "npm não encontrado — pulando Capture. Instale Node.js e rode 'cd capture && npm install && npm run build' depois."
  else
    info "Buildando OmniNox Capture..."
    (
      cd "$CAPTURE_DIR" && \
      npm install --silent && \
      npm run build > /tmp/omninox-capture-build.log 2>&1
    ) && {
      APP_BUILT="$CAPTURE_DIR/dist/mac-arm64/OmniNox Capture.app"
      if [ -d "$APP_BUILT" ]; then
        rm -rf "/Applications/OmniNox Capture.app" 2>/dev/null || true
        cp -R "$APP_BUILT" "/Applications/" && ok "Capture instalado em /Applications/OmniNox Capture.app"
      else
        warn "Build do Capture concluído mas .app não foi encontrado. Veja /tmp/omninox-capture-build.log"
      fi
    } || warn "Build do Capture falhou. Veja /tmp/omninox-capture-build.log"
  fi
fi

# ─── conclusão ────────────────────────────────────────────────────────────────
echo ""
echo "  ─── Instalação concluída! ──────────────────"
ok "OmniNox em:  $ON_DEST"
ok "Hook ativo: $HOOK_DEST"
[ "$INSTALL_CAPTURE" = "y" ] && [ -d "/Applications/OmniNox Capture.app" ] && ok "Capture:     /Applications/OmniNox Capture.app"
echo ""
echo "  Próximos passos:"
echo "  1. Abra o vault '$VAULT_NAME' no Obsidian"
echo "  2. Inicie uma nova sessão do Claude Code dentro do vault:"
echo "     cd \"$VAULT_PATH\" && claude"
echo "  3. O OmniNox já vai aparecer automaticamente no contexto."
[ "$INSTALL_CAPTURE" = "y" ] && [ -d "/Applications/OmniNox Capture.app" ] && \
  echo "  4. Abra o Capture (Cmd+Shift+N) e selecione o vault em 'Mudar vault...'"
echo ""
echo "  Para criar wings depois:"
echo "  bash Areas/omninox/.scripts/omninox.sh new-wing <nome> '<descrição>'"
echo ""
