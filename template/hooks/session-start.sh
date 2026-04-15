#!/bin/bash
# OmniNox SessionStart Hook (GLOBAL)
# Injeta _wake-up.md, _identity.md e _continue.md no contexto do Claude.
# Roda de qualquer diretório — usa caminho absoluto pro OmniNox.

OMNINOX_DIR="__OMNINOX_PATH__"

# Se o OmniNox não existir, sai silenciosamente
if [ ! -d "$OMNINOX_DIR" ]; then
  exit 0
fi

echo "=== OMNINOX: Wake-Up ==="
[ -f "$OMNINOX_DIR/_wake-up.md" ] && cat "$OMNINOX_DIR/_wake-up.md"

echo ""
echo "=== OMNINOX: Identity ==="
[ -f "$OMNINOX_DIR/_identity.md" ] && cat "$OMNINOX_DIR/_identity.md"

echo ""
echo "=== OMNINOX: Wings Ativas ==="
if [ -d "$OMNINOX_DIR/wings" ]; then
  for wing_dir in "$OMNINOX_DIR/wings"/*/; do
    wing_name=$(basename "$wing_dir")
    if [ "$wing_name" != "_template" ] && [ -f "$wing_dir/_wing.md" ]; then
      desc=$(grep -m1 '^>' "$wing_dir/_wing.md" 2>/dev/null | sed 's/^> //' || echo "")
      echo "- $wing_name: $desc"
    fi
  done
fi

# Injeta _continue.md de wings com checkpoint ativo
echo ""
has_continue=0
for wing_dir in "$OMNINOX_DIR/wings"/*/; do
  wing_name=$(basename "$wing_dir")
  if [ "$wing_name" != "_template" ] && [ -f "$wing_dir/_continue.md" ]; then
    content_lines=$(grep -cv '^\s*$\|^#\|^>\|^---' "$wing_dir/_continue.md" 2>/dev/null || echo "0")
    if [ "$content_lines" -gt 0 ]; then
      if [ "$has_continue" -eq 0 ]; then
        echo "=== OMNINOX: Checkpoints Ativos ==="
        has_continue=1
      fi
      echo "--- $wing_name ---"
      cat "$wing_dir/_continue.md"
      echo ""
    fi
  fi
done

exit 0
