#!/bin/bash
# ============================================================================
#  OmniNox v2 — Instalador
#
#  Uso (uma linha no Terminal):
#    curl -fsSL https://raw.githubusercontent.com/jota-nox/omninox/main/install.sh | bash
#
#  Modos: novo vault (template em branco) · restaurar de backup · atualizar.
#  Backup no GitHub é opcional (sem backup = tudo fica só nesta máquina).
#
#  Variáveis de teste/automação (não interativo):
#    ONX_MODE=novo|restaurar|atualizar  ONX_VAULT_DIR=<path>
#    ONX_BACKUP=s|n  ONX_REPO_URL=<url>  ONX_SKIP_APPS=1  ONX_LOCAL_SRC=<dir>
# ============================================================================
set -uo pipefail

REPO="jota-nox/omninox"
CONFIG_DIR="$HOME/.config/omninox"
CONFIG="$CONFIG_DIR/config.json"
DEFAULT_VAULT="$HOME/Documents/omninox"
TMP="$(mktemp -d /tmp/omninox-install.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- aparência
Y=$'\033[1;33m'; G=$'\033[0;32m'; R=$'\033[0;31m'; D=$'\033[0;90m'; N=$'\033[0m'
say()  { printf "%s\n" "$1"; }
ok()   { printf "  ${G}✓${N} %s\n" "$1"; }
warn() { printf "  ${Y}!${N} %s\n" "$1"; }
die()  { printf "  ${R}✗ %s${N}\n" "$1"; exit 1; }

# pergunta SEMPRE pelo /dev/tty (stdin é o próprio script no curl|bash)
ask() { # ask "pergunta" "default" -> $REPLY_ANS
  local q="$1" def="${2:-}"
  if [ -n "${ONX_NONINTERACTIVE:-}" ]; then REPLY_ANS="$def"; return; fi
  printf "  ${Y}?${N} %s " "$q" > /dev/tty
  read -r REPLY_ANS < /dev/tty || REPLY_ANS=""
  [ -z "$REPLY_ANS" ] && REPLY_ANS="$def"
}

json_get() { python3 -c "import json,sys;print(json.load(open('$1')).get('$2',''))" 2>/dev/null; }

# ---------------------------------------------------------------- boas-vindas
say ""
say "  ${Y}◆ OmniNox v2${N} — memória persistente pro Claude Code"
say "  ${D}vault Obsidian · captura automática · backup opcional${N}"
say ""

[ "$(uname)" = "Darwin" ] || die "Este instalador é só pra macOS."

# ---------------------------------------------------------------- fonte dos arquivos
# ONX_LOCAL_SRC permite instalar de um checkout local (dev/testes);
# padrão: baixa o tarball do GitHub.
if [ -n "${ONX_LOCAL_SRC:-}" ]; then
  SRC="$ONX_LOCAL_SRC"
  ok "fonte local: $SRC"
else
  say "  ${D}baixando arquivos do OmniNox...${N}"
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" -o "$TMP/src.tgz" \
    || die "não consegui baixar o OmniNox (sem internet?)"
  tar -xzf "$TMP/src.tgz" -C "$TMP"
  SRC="$(echo "$TMP"/omninox-*)"
  ok "arquivos baixados"
fi
[ -d "$SRC/template/vault" ] || die "fonte inválida (template/vault ausente)"

# ---------------------------------------------------------------- dependências
say ""
say "  ${Y}1/6${N} Dependências"

# Command Line Tools (traz git e python3)
if ! xcode-select -p >/dev/null 2>&1; then
  warn "As ferramentas de linha de comando da Apple são necessárias."
  say  "      Vai abrir uma janela de instalação — clique em Instalar e aguarde."
  xcode-select --install >/dev/null 2>&1
  until xcode-select -p >/dev/null 2>&1; do sleep 10; done
fi
ok "git e python3 presentes"

# Claude Code (obrigatório — é ele que roda a captura automática)
if [ -z "${ONX_SKIP_APPS:-}" ]; then
  if ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
    warn "Claude Code não encontrado — instalando..."
    curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 \
      || die "instalação do Claude Code falhou — instale manualmente (claude.com/claude-code) e rode de novo"
  fi
  ok "Claude Code instalado"

  # Obsidian
  if [ ! -d "/Applications/Obsidian.app" ]; then
    warn "Obsidian não encontrado — baixando..."
    OBS_URL=$(curl -fsSL "https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest" \
      | python3 -c "import json,sys;a=json.load(sys.stdin)['assets'];print(next(x['browser_download_url'] for x in a if x['name'].endswith('.dmg') and 'arm64' not in x['name']))" 2>/dev/null)
    if [ -n "$OBS_URL" ] && curl -fsSL "$OBS_URL" -o "$TMP/obsidian.dmg"; then
      MNT=$(hdiutil attach -nobrowse -readonly "$TMP/obsidian.dmg" | tail -1 | awk -F'\t' '{print $NF}')
      cp -R "$MNT/Obsidian.app" /Applications/ 2>/dev/null
      hdiutil detach "$MNT" >/dev/null 2>&1
    fi
    [ -d "/Applications/Obsidian.app" ] || warn "não consegui instalar o Obsidian — baixe em obsidian.md (o resto segue normal)"
  fi
  [ -d "/Applications/Obsidian.app" ] && ok "Obsidian instalado"

  # OmniNox Capture (binário pré-compilado do release)
  CAP_ZIP_URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | python3 -c "import json,sys;a=json.load(sys.stdin).get('assets',[]);print(next((x['browser_download_url'] for x in a if x['name'].endswith('.zip')),''))" 2>/dev/null)
  if [ -n "$CAP_ZIP_URL" ]; then
    curl -fsSL "$CAP_ZIP_URL" -o "$TMP/capture.zip" \
      && ditto -x -k "$TMP/capture.zip" "$TMP/capture-app" \
      && rm -rf "/Applications/OmniNox Capture.app" \
      && cp -R "$TMP/capture-app/OmniNox Capture.app" /Applications/ \
      && xattr -dr com.apple.quarantine "/Applications/OmniNox Capture.app" 2>/dev/null
    [ -d "/Applications/OmniNox Capture.app" ] && ok "OmniNox Capture instalado" || warn "Capture não instalou — siga sem ele por ora"
  else
    warn "release do Capture não encontrado — pulando o app (o sistema funciona sem ele)"
  fi
else
  ok "apps pulados (ONX_SKIP_APPS)"
fi

# ---------------------------------------------------------------- modo
say ""
say "  ${Y}2/6${N} O que você quer fazer?"

MODE="${ONX_MODE:-}"
EXISTING_VAULT="$(json_get "$CONFIG" vaultPath)"
if [ -z "$MODE" ]; then
  if [ -n "$EXISTING_VAULT" ] && [ -f "$EXISTING_VAULT/.omninox-vault" ]; then
    say "      Já existe um OmniNox nesta máquina: $EXISTING_VAULT"
    ask "Atualizar ele? (s = atualizar / n = outra instalação)" "s"
    [ "$REPLY_ANS" = "s" ] && MODE="atualizar"
  fi
fi
if [ -z "$MODE" ]; then
  say "      1) Começar um OmniNox NOVO (vault em branco)"
  say "      2) RESTAURAR meu OmniNox de um backup (máquina nova/formatada)"
  ask "Escolha [1/2]:" "1"
  [ "$REPLY_ANS" = "2" ] && MODE="restaurar" || MODE="novo"
fi
ok "modo: $MODE"

# ---------------------------------------------------------------- vault
say ""
say "  ${Y}3/6${N} Vault"

VAULT="${ONX_VAULT_DIR:-}"
case "$MODE" in
  atualizar)
    VAULT="${VAULT:-$EXISTING_VAULT}"
    [ -f "$VAULT/.omninox-vault" ] || die "vault em $VAULT sem marker .omninox-vault"
    # atualiza só a máquina: scripts novos + hooks; conteúdo do vault não é tocado
    cp "$SRC/template/vault/Areas/omninox/.scripts/"* "$VAULT/Areas/omninox/.scripts/" 2>/dev/null
    chmod +x "$VAULT/Areas/omninox/.scripts/"*.sh "$VAULT/Areas/omninox/.scripts/"*.py 2>/dev/null
    [ -f "$VAULT/.gitattributes" ] || cp "$SRC/template/vault/.gitattributes" "$VAULT/"
    ok "scripts atualizados em $VAULT"
    ;;
  novo)
    if [ -z "$VAULT" ]; then
      ask "Onde criar o vault? [enter = $DEFAULT_VAULT]" "$DEFAULT_VAULT"
      VAULT="$REPLY_ANS"
    fi
    VAULT="${VAULT/#\~/$HOME}"
    if [ -f "$VAULT/.omninox-vault" ]; then
      ok "vault já existe em $VAULT (mantendo conteúdo)"
    else
      mkdir -p "$(dirname "$VAULT")"
      cp -R "$SRC/template/vault" "$VAULT"
      ok "vault criado em $VAULT"
    fi
    if [ ! -d "$VAULT/.git" ]; then
      git -C "$VAULT" init -q -b master
      git -C "$VAULT" add -A
      git -C "$VAULT" commit -q -m "OmniNox v2 — vault inicial" 2>/dev/null \
        || { git -C "$VAULT" -c user.email=omninox@local -c user.name=OmniNox commit -q -m "OmniNox v2 — vault inicial"; }
      ok "git iniciado (histórico local ativo)"
    fi
    ;;
  restaurar)
    REPO_URL="${ONX_REPO_URL:-}"
    if [ -z "$REPO_URL" ]; then
      say "      Preciso do endereço do seu backup (ex.: https://github.com/voce/omni-vault)"
      ask "URL do repositório:" ""
      REPO_URL="$REPLY_ANS"
    fi
    [ -n "$REPO_URL" ] || die "sem URL não dá pra restaurar"
    if [ -z "$VAULT" ]; then
      ask "Onde colocar o vault restaurado? [enter = $DEFAULT_VAULT]" "$DEFAULT_VAULT"
      VAULT="$REPLY_ANS"
    fi
    VAULT="${VAULT/#\~/$HOME}"
    if [ -f "$VAULT/.omninox-vault" ]; then
      ok "vault já existe em $VAULT — pulando clone"
    else
      [ -e "$VAULT" ] && die "$VAULT já existe e não é um vault OmniNox — escolha outro caminho"
      # repo privado: tenta gh primeiro (auth), cai pro git puro
      if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh repo clone "$REPO_URL" "$VAULT" -- -q || die "clone falhou"
      else
        git clone -q "$REPO_URL" "$VAULT" || die "clone falhou (repo privado? rode: gh auth login)"
      fi
      ok "vault restaurado de $REPO_URL"
    fi
    [ -f "$VAULT/.omninox-vault" ] || die "o repo clonado não tem o marker .omninox-vault — não é um vault OmniNox"
    ;;
esac

# config canônica da máquina
mkdir -p "$CONFIG_DIR"
python3 - "$CONFIG" "$VAULT" <<'EOF'
import json, os, sys
cfg_path, vault = sys.argv[1], sys.argv[2]
cfg = {}
if os.path.isfile(cfg_path):
    try: cfg = json.load(open(cfg_path))
    except Exception: cfg = {}
cfg["vaultPath"] = vault
json.dump(cfg, open(cfg_path, "w"), indent=2, sort_keys=True)
EOF
ok "config gravada (~/.config/omninox/config.json)"

# ---------------------------------------------------------------- backup
say ""
say "  ${Y}4/6${N} Backup na nuvem (GitHub)"

if git -C "$VAULT" remote 2>/dev/null | grep -q origin; then
  ok "backup já configurado: $(git -C "$VAULT" remote get-url origin)"
elif [ "$MODE" = "restaurar" ]; then
  ok "backup herdado do clone"
else
  BK="${ONX_BACKUP:-}"
  if [ -z "$BK" ]; then
    say "      Com backup, suas notas ficam salvas num repositório PRIVADO no GitHub"
    say "      e você pode trabalhar de qualquer máquina. Sem backup, tudo fica só aqui."
    ask "Ativar backup? [s/n]" "s"
    BK="$REPLY_ANS"
  fi
  if [ "$BK" = "s" ]; then
    # garante gh
    if ! command -v gh >/dev/null 2>&1; then
      warn "instalando GitHub CLI..."
      GH_URL=$(curl -fsSL "https://api.github.com/repos/cli/cli/releases/latest" \
        | python3 -c "import json,sys;a=json.load(sys.stdin)['assets'];print(next(x['browser_download_url'] for x in a if 'macOS_arm64' in x['name'] and x['name'].endswith('.zip')))" 2>/dev/null)
      if [ -n "$GH_URL" ] && curl -fsSL "$GH_URL" -o "$TMP/gh.zip"; then
        ditto -x -k "$TMP/gh.zip" "$TMP/gh"
        mkdir -p "$HOME/.local/bin"
        cp "$TMP"/gh/gh_*/bin/gh "$HOME/.local/bin/gh" && chmod +x "$HOME/.local/bin/gh"
        export PATH="$HOME/.local/bin:$PATH"
      fi
    fi
    if command -v gh >/dev/null 2>&1; then
      if ! gh auth status >/dev/null 2>&1; then
        say "      Vou abrir o login do GitHub no navegador — siga os passos lá."
        gh auth login --web --git-protocol https < /dev/tty || warn "login não concluído"
      fi
      if gh auth status >/dev/null 2>&1; then
        RNAME="omninox-vault"
        ask "Nome do repositório privado [enter = $RNAME]:" "$RNAME"
        RNAME="$REPLY_ANS"
        if gh repo create "$RNAME" --private --source "$VAULT" --push >/dev/null 2>&1; then
          ok "backup ativo: repositório privado $RNAME"
        else
          # repo pode já existir — tenta ligar e pushar
          OWNER=$(gh api user --jq .login 2>/dev/null)
          git -C "$VAULT" remote add origin "https://github.com/$OWNER/$RNAME.git" 2>/dev/null
          git -C "$VAULT" push -q -u origin master 2>/dev/null \
            && ok "backup ativo: $OWNER/$RNAME" \
            || warn "não consegui criar/ligar o repositório — backup fica pra depois (rode o instalador de novo)"
        fi
      else
        warn "sem login no GitHub — backup fica pra depois (rode o instalador de novo quando quiser)"
      fi
    else
      warn "GitHub CLI indisponível — backup fica pra depois"
    fi
  else
    warn "sem backup: suas notas existem SÓ nesta máquina (você pode ativar depois rodando o instalador de novo)"
  fi
fi

# ---------------------------------------------------------------- claude code: hooks + skill + memória
say ""
say "  ${Y}5/6${N} Ligações com o Claude Code"

mkdir -p "$HOME/.claude/skills"
# hooks (merge preservando o settings existente)
python3 - "$SRC/claude-config/settings-snippet.json" "$HOME/.claude/settings.json" "$VAULT" <<'EOF'
import json, os, sys
snip_p, settings_p, vault = sys.argv[1], sys.argv[2], sys.argv[3]
snip = json.load(open(snip_p))
snip.pop("_comment", None)
def sub(o):
    if isinstance(o, dict): return {k: sub(v) for k, v in o.items()}
    if isinstance(o, list): return [sub(v) for v in o]
    if isinstance(o, str): return o.replace("__VAULT__", vault)
    return o
snip = sub(snip)
cur = {}
if os.path.isfile(settings_p):
    try: cur = json.load(open(settings_p))
    except Exception: cur = {}
cur.setdefault("hooks", {})
for event, entries in snip["hooks"].items():
    cur["hooks"][event] = entries          # OmniNox é dono desses 4 eventos
cur["cleanupPeriodDays"] = max(cur.get("cleanupPeriodDays", 0), snip["cleanupPeriodDays"])
os.makedirs(os.path.dirname(settings_p), exist_ok=True)
json.dump(cur, open(settings_p, "w"), indent=2)
EOF
ok "hooks de captura registrados (~/.claude/settings.json)"

# skill /omni-compile
cp -R "$SRC/claude-config/skills/omni-compile" "$HOME/.claude/skills/" 2>/dev/null
ok "skill /omni-compile instalada"

# memória do Claude dentro do vault (viaja no backup/restauração)
PROJ_ENC=$(printf "%s" "$HOME/Documents" | tr '/' '-')
MEM_DIR="$HOME/.claude/projects/$PROJ_ENC/memory"
mkdir -p "$VAULT/.claude-memory" "$(dirname "$MEM_DIR")"
if [ -L "$MEM_DIR" ]; then
  ok "memória do Claude já linkada ao vault"
else
  if [ -d "$MEM_DIR" ] && [ -n "$(ls -A "$MEM_DIR" 2>/dev/null)" ]; then
    cp -an "$MEM_DIR/." "$VAULT/.claude-memory/" 2>/dev/null
    mv "$MEM_DIR" "$MEM_DIR.pre-omninox-backup"
  fi
  ln -sfn "$VAULT/.claude-memory" "$MEM_DIR"
  ok "memória do Claude linkada ao vault (segue você entre máquinas)"
fi

# ---------------------------------------------------------------- permissões e fechamento
say ""
say "  ${Y}6/6${N} Últimos passos (coisas que só você pode clicar)"
say ""
say "   1. Abra o ${Y}Obsidian${N} → \"Open folder as vault\" → escolha:"
say "      $VAULT"
say "   2. Aperte ${Y}⌘⇧N${N} pra abrir o OmniNox Capture, escreva algo e salve"
say "      com ${Y}⌘Enter${N} — o macOS vai pedir permissão de acesso a Documentos:"
say "      clique em ${Y}Permitir${N} (acontece só uma vez)."
say "   3. Abra o Terminal, rode ${Y}claude${N} e faça login se pedir."
say ""
ok "OmniNox v2 instalado. A partir de agora, toda sessão do Claude Code é capturada sozinha."
say "  ${D}dica: de tempos em tempos, rode /omni-compile numa sessão do Claude pra destilar a memória.${N}"
say ""
