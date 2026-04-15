#!/bin/bash
# OmniNox CLI — Helper para o sistema de memória OmniNox
# Uso: bash omninox.sh <comando> [args...]

OMNINOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WINGS_DIR="$OMNINOX_DIR/wings"
TEMPLATE_DIR="$WINGS_DIR/_template"

usage() {
  echo "OmniNox CLI — Sistema de memória persistente"
  echo ""
  echo "Comandos:"
  echo "  new-wing <nome> <descricao>         Cria nova wing a partir do template"
  echo "  list-wings                           Lista wings ativas"
  echo "  read-wing <nome>                    Lê o contexto completo de uma wing"
  echo "  save-drawer <wing> <titulo>         Cria drawer (conteúdo via stdin)"
  echo "  search <termo>                       Busca full-text em drawers e halls"
  echo "  update-wake-up                       Regenera _wake-up.md a partir do estado atual"
  echo ""
  echo "Exemplos:"
  echo "  bash omninox.sh new-wing projeto-x 'Redesign do dashboard principal'"
  echo "  bash omninox.sh save-drawer jota 'pricing-v07' < conteudo.md"
  echo "  echo 'conteudo' | bash omninox.sh save-drawer jota 'pricing-v07'"
  echo "  bash omninox.sh search 'onboarding'"
}

cmd_new_wing() {
  local name="$1"
  local desc="$2"

  if [ -z "$name" ] || [ -z "$desc" ]; then
    echo "Erro: uso: omninox.sh new-wing <nome> <descricao>"
    exit 1
  fi

  local wing_dir="$WINGS_DIR/$name"

  if [ -d "$wing_dir" ]; then
    echo "Erro: wing '$name' já existe em $wing_dir"
    exit 1
  fi

  cp -r "$TEMPLATE_DIR" "$wing_dir"
  mkdir -p "$wing_dir/drawers"

  sed -i '' "s/\[NOME\]/$name/g" "$wing_dir"/*.md

  cat > "$wing_dir/_wing.md" << EOF
# Wing: $name
> $desc

## Tipo
> projeto

## Status
> ativo

## Pessoas Envolvidas
> -

## Resumo
> Wing criada em $(date +%Y-%m-%d).
EOF

  local index_file="$OMNINOX_DIR/_index.md"
  local new_row="| [[$name]] | projeto | ativo | $(date +%Y-%m-%d) |"

  sed -i '' "/^## Como Funciona/i\\
$new_row" "$index_file"

  cmd_update_wake_up

  echo "Wing '$name' criada com sucesso em $wing_dir"
  echo "Halls: decisoes.md, problemas.md, descobertas.md, propostas.md"
  echo "Drawers: $wing_dir/drawers/"
}

cmd_list_wings() {
  echo "Wings ativas:"
  for wing_dir in "$WINGS_DIR"/*/; do
    local wing_name=$(basename "$wing_dir")
    if [ "$wing_name" != "_template" ] && [ -f "$wing_dir/_wing.md" ]; then
      local desc=$(grep -m1 '^>' "$wing_dir/_wing.md" | sed 's/^> //')
      local drawer_count=$(ls -1 "$wing_dir/drawers/" 2>/dev/null | wc -l | tr -d ' ')
      echo "  - $wing_name: $desc ($drawer_count drawers)"
    fi
  done
}

cmd_read_wing() {
  local name="$1"
  local wing_dir="$WINGS_DIR/$name"

  if [ ! -d "$wing_dir" ]; then
    echo "Erro: wing '$name' não encontrada"
    exit 1
  fi

  echo "=== Wing: $name ==="
  cat "$wing_dir/_wing.md"
  echo ""

  for hall in decisoes problemas descobertas propostas; do
    if [ -f "$wing_dir/$hall.md" ]; then
      echo "=== $hall ==="
      cat "$wing_dir/$hall.md"
      echo ""
    fi
  done

  if [ -f "$wing_dir/_continue.md" ]; then
    echo "=== Continue ==="
    cat "$wing_dir/_continue.md"
    echo ""
  fi

  echo "=== Drawers ==="
  if [ -d "$wing_dir/drawers" ]; then
    ls -1t "$wing_dir/drawers/" 2>/dev/null || echo "(nenhum drawer)"
  fi
}

cmd_save_drawer() {
  local wing="$1"
  local titulo="$2"

  if [ -z "$wing" ] || [ -z "$titulo" ]; then
    echo "Erro: uso: omninox.sh save-drawer <wing> <titulo>"
    echo "  Conteúdo via stdin (pipe ou redirect)"
    exit 1
  fi

  local wing_dir="$WINGS_DIR/$wing"

  if [ ! -d "$wing_dir" ]; then
    echo "Erro: wing '$wing' não encontrada"
    exit 1
  fi

  mkdir -p "$wing_dir/drawers"

  local today=$(date +%Y-%m-%d)
  local filename="${today}_${titulo}.md"
  local filepath="$wing_dir/drawers/$filename"

  if [ -f "$filepath" ]; then
    # Adiciona sufixo se já existe drawer com mesmo nome hoje
    local counter=2
    while [ -f "$wing_dir/drawers/${today}_${titulo}-${counter}.md" ]; do
      counter=$((counter + 1))
    done
    filename="${today}_${titulo}-${counter}.md"
    filepath="$wing_dir/drawers/$filename"
  fi

  if [ -t 0 ]; then
    # Sem stdin — cria drawer vazio com header
    cat > "$filepath" << EOF
# Drawer: ${titulo}

> **Data:** ${today}
> **Wing:** ${wing}

---

EOF
    echo "Drawer criado (vazio): $filepath"
    echo "Edite o arquivo para adicionar conteúdo."
  else
    # Com stdin — escreve conteúdo recebido
    cat > "$filepath"
    echo "Drawer salvo: $filepath"
  fi
}

cmd_search() {
  local term="$1"

  if [ -z "$term" ]; then
    echo "Erro: uso: omninox.sh search <termo>"
    exit 1
  fi

  local found=0

  echo "=== Buscando '$term' no OmniNox ==="
  echo ""

  # Busca nos halls
  for wing_dir in "$WINGS_DIR"/*/; do
    local wing_name=$(basename "$wing_dir")
    [ "$wing_name" = "_template" ] && continue

    for hall in decisoes problemas descobertas propostas; do
      if [ -f "$wing_dir/$hall.md" ]; then
        local results=$(grep -in "$term" "$wing_dir/$hall.md" 2>/dev/null)
        if [ -n "$results" ]; then
          echo "--- $wing_name/$hall.md ---"
          echo "$results"
          echo ""
          found=1
        fi
      fi
    done
  done

  # Busca nos drawers
  for wing_dir in "$WINGS_DIR"/*/; do
    local wing_name=$(basename "$wing_dir")
    [ "$wing_name" = "_template" ] && continue

    if [ -d "$wing_dir/drawers" ]; then
      for drawer in "$wing_dir/drawers"/*.md; do
        [ -f "$drawer" ] || continue
        local results=$(grep -in "$term" "$drawer" 2>/dev/null)
        if [ -n "$results" ]; then
          local drawer_name=$(basename "$drawer")
          echo "--- $wing_name/drawers/$drawer_name ---"
          echo "$results" | head -5
          local total=$(echo "$results" | wc -l | tr -d ' ')
          if [ "$total" -gt 5 ]; then
            echo "  ... (+$((total - 5)) linhas)"
          fi
          echo ""
          found=1
        fi
      done
    fi
  done

  # Busca nos core files
  for core in _wake-up.md _index.md tunnels.md; do
    if [ -f "$OMNINOX_DIR/$core" ]; then
      local results=$(grep -in "$term" "$OMNINOX_DIR/$core" 2>/dev/null)
      if [ -n "$results" ]; then
        echo "--- $core ---"
        echo "$results"
        echo ""
        found=1
      fi
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "Nenhum resultado para '$term'."
  fi
}

cmd_update_wake_up() {
  local wake_file="$OMNINOX_DIR/_wake-up.md"
  local today=$(date +%Y-%m-%d)

  # Coleta projetos ativos
  local projects=""
  for wing_dir in "$WINGS_DIR"/*/; do
    local wing_name=$(basename "$wing_dir")
    if [ "$wing_name" != "_template" ] && [ -f "$wing_dir/_wing.md" ]; then
      local desc=$(grep -m1 '^>' "$wing_dir/_wing.md" | sed 's/^> //')
      projects="$projects\n- **$wing_name** — $desc"
    fi
  done

  if [ -z "$projects" ]; then
    projects="\n> Nenhum projeto registrado ainda."
  fi

  # Coleta decisões recentes — suporta ambos os formatos:
  #   - **[DATE]** Decisão...
  #   ## [DATE] Decisão...
  local decisions=""
  for wing_dir in "$WINGS_DIR"/*/; do
    local wing_name=$(basename "$wing_dir")
    if [ "$wing_name" != "_template" ] && [ -f "$wing_dir/decisoes.md" ]; then
      local recent=$(grep -E "^(- \*\*\[|## \[)" "$wing_dir/decisoes.md" | head -3)
      if [ -n "$recent" ]; then
        decisions="$decisions\n### $wing_name\n$recent"
      fi
    fi
  done

  if [ -z "$decisions" ]; then
    decisions="\n> Nenhuma decisão registrada recentemente."
  fi

  # Coleta propostas pendentes — match mais preciso
  local proposals=""
  for wing_dir in "$WINGS_DIR"/*/; do
    local wing_name=$(basename "$wing_dir")
    if [ "$wing_name" != "_template" ] && [ -f "$wing_dir/propostas.md" ]; then
      local pending=$(grep -E '\*\*pendente\*\*|— pendente|status:.*pendente' "$wing_dir/propostas.md")
      if [ -n "$pending" ]; then
        proposals="$proposals\n### $wing_name\n$pending"
      fi
    fi
  done

  if [ -z "$proposals" ]; then
    proposals="\n> Nenhuma proposta pendente."
  fi

  cat > "$wake_file" << EOF
# Wake-Up — Contexto de Sessão
> ~200 tokens. Claude lê isso ao iniciar qualquer sessão.

## Projetos Ativos
$(echo -e "$projects")

## Decisões Recentes
$(echo -e "$decisions")

## Propostas Pendentes
$(echo -e "$proposals")

## Última Atualização
> $today
EOF

  echo "_wake-up.md atualizado em $today"
}

# Router
case "$1" in
  new-wing)
    cmd_new_wing "$2" "$3"
    ;;
  list-wings)
    cmd_list_wings
    ;;
  read-wing)
    cmd_read_wing "$2"
    ;;
  save-drawer)
    cmd_save_drawer "$2" "$3"
    ;;
  search)
    cmd_search "$2"
    ;;
  update-wake-up)
    cmd_update_wake_up
    ;;
  *)
    usage
    ;;
esac
