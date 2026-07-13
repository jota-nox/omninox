#!/bin/bash
# OmniNox SessionStart Hook (GLOBAL — registrado em ~/.claude/settings.json)
# Injeta _wake-up.md + wings + checkpoints em TODA sessão do Claude Code,
# independente do cwd. Stdout vira contexto da sessão.
# À prova de falha: qualquer erro sai silencioso (exit 0) — nunca quebra a sessão.

CONFIG="$HOME/.config/omninox/config.json"
VAULT=$(python3 -c "import json;print(json.load(open('$CONFIG')).get('vaultPath',''))" 2>/dev/null)
[ -z "$VAULT" ] && VAULT="$HOME/Documents/omninox"

[ -f "$VAULT/.omninox-vault" ] || exit 0   # vault canônico ausente: silêncio

# sync multi-máquina: integra o que outras máquinas pusharam, sem bloquear
# o início da sessão (background; conflito real é tratado no omni-capture).
if git -C "$VAULT" remote 2>/dev/null | grep -q origin; then
  (git -C "$VAULT" pull --rebase --autostash -q origin master >/dev/null 2>&1 \
    || git -C "$VAULT" rebase --abort >/dev/null 2>&1) &
fi

OMNI="$VAULT/Areas/omninox"

echo "=== OMNINOX: Wake-Up ==="
cat "$OMNI/_wake-up.md" 2>/dev/null || echo "(wake-up indisponível)"

echo ""
echo "=== OMNINOX: Wings ==="
for wing_dir in "$OMNI/wings"/*/; do
  wing_name=$(basename "$wing_dir")
  [ "$wing_name" = "_template" ] && continue
  desc=$(grep -m1 '^>' "$wing_dir/_wing.md" 2>/dev/null | sed 's/^> //')
  echo "- $wing_name: $desc"
done

echo ""
echo "=== OMNINOX: Contrato de memória ==="
echo "Captura verbatim é AUTOMÁTICA (hooks mineram o transcript pra Areas/omninox/raw/)."
echo "Você NÃO precisa salvar verbatim. Sua responsabilidade é curadoria:"
echo "- Sessão substantiva -> drawer CURADO (resumo denso + link pro raw) na wing certa."
echo "- Escreva SEMPRE no vault canônico: $VAULT (marker .omninox-vault). Nunca em cópias."
echo "- Síntese pesada (halls, wiki, _wake-up) pertence ao /omni-compile, não ao fim de sessão."

exit 0
