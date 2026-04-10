#!/bin/bash
# Claudiknows SessionStart Hook (GLOBAL)
# Injeta _wake-up.md e _identity.md no contexto do Claude automaticamente.
# Roda de qualquer diretório — usa caminho absoluto pro Claudiknows.

CK_DIR="__CK_PATH__"

# Se o Claudiknows não existir, sai silenciosamente
if [ ! -d "$CK_DIR" ]; then
  exit 0
fi

echo "=== CLAUDIKNOWS: Wake-Up ==="
[ -f "$CK_DIR/_wake-up.md" ] && cat "$CK_DIR/_wake-up.md"

echo ""
echo "=== CLAUDIKNOWS: Identity ==="
[ -f "$CK_DIR/_identity.md" ] && cat "$CK_DIR/_identity.md"

echo ""
echo "=== CLAUDIKNOWS: Wings Ativas ==="
if [ -d "$CK_DIR/wings" ]; then
  for wing_dir in "$CK_DIR/wings"/*/; do
    wing_name=$(basename "$wing_dir")
    if [ "$wing_name" != "_template" ] && [ -f "$wing_dir/_wing.md" ]; then
      desc=$(grep -m1 '^>' "$wing_dir/_wing.md" 2>/dev/null | sed 's/^> //' || echo "")
      echo "- $wing_name: $desc"
    fi
  done
fi

echo ""
echo "=== CLAUDIKNOWS: Diretório de trabalho ==="
echo "Sessão rodando em: $(pwd)"
echo "Claudiknows em: $CK_DIR"

exit 0
