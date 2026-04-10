#!/bin/bash
# Palace SessionStart Hook (GLOBAL)
# Injeta _wake-up.md e _identity.md no contexto do Claude automaticamente.
# Roda de qualquer diretório — usa caminho absoluto pro palace.

PALACE_DIR="__PALACE_PATH__"

# Se o palace não existir, sai silenciosamente
if [ ! -d "$PALACE_DIR" ]; then
  exit 0
fi

echo "=== PALACE: Wake-Up ==="
[ -f "$PALACE_DIR/_wake-up.md" ] && cat "$PALACE_DIR/_wake-up.md"

echo ""
echo "=== PALACE: Identity ==="
[ -f "$PALACE_DIR/_identity.md" ] && cat "$PALACE_DIR/_identity.md"

echo ""
echo "=== PALACE: Wings Ativas ==="
if [ -d "$PALACE_DIR/wings" ]; then
  for wing_dir in "$PALACE_DIR/wings"/*/; do
    wing_name=$(basename "$wing_dir")
    if [ "$wing_name" != "_template" ] && [ -f "$wing_dir/_wing.md" ]; then
      desc=$(grep -m1 '^>' "$wing_dir/_wing.md" 2>/dev/null | sed 's/^> //' || echo "")
      echo "- $wing_name: $desc"
    fi
  done
fi

echo ""
echo "=== PALACE: Diretório de trabalho ==="
echo "Sessão rodando em: $(pwd)"
echo "Palace em: $PALACE_DIR"

exit 0
