#!/bin/bash
# Claudiknows CLI — Helper para o Claudiknows
# Uso: bash claudiknows.sh <comando> [args...]

CK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WINGS_DIR="$CK_DIR/wings"
TEMPLATE_DIR="$WINGS_DIR/_template"

usage() {
  echo "Claudiknows CLI — Helper para o Claudiknows"
  echo ""
  echo "Comandos:"
  echo "  new-wing <nome> <descricao>    Cria nova wing a partir do template"
  echo "  list-wings                      Lista wings ativas"
  echo "  read-wing <nome>               Lê o contexto completo de uma wing"
  echo "  update-wake-up                  Regenera _wake-up.md a partir do estado atual"
  echo ""
  echo "Exemplo:"
  echo "  bash claudiknows.sh new-wing projeto-x 'Redesign do dashboard principal'"
}

cmd_new_wing() {
  local name="$1"
  local desc="$2"

  if [ -z "$name" ] || [ -z "$desc" ]; then
    echo "Erro: uso: claudiknows.sh new-wing <nome> <descricao>"
    exit 1
  fi

  local wing_dir="$WINGS_DIR/$name"

  if [ -d "$wing_dir" ]; then
    echo "Erro: wing '$name' já existe em $wing_dir"
    exit 1
  fi

  # Cria a wing a partir do template
  cp -r "$TEMPLATE_DIR" "$wing_dir"
  mkdir -p "$wing_dir/drawers"

  # Substitui placeholders
  sed -i '' "s/\[NOME\]/$name/g" "$wing_dir"/*.md

  # Preenche _wing.md
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

  # Adiciona à tabela do _index.md
  local index_file="$CK_DIR/_index.md"
  local new_row="| [[$name]] | projeto | ativo | $(date +%Y-%m-%d) |"

  # Insere antes da linha '## Como Funciona'
  sed -i '' "/^## Como Funciona/i\\
$new_row" "$index_file"

  # Atualiza _wake-up.md
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
      local status=$(grep -m1 '^>' "$wing_dir/_wing.md" | sed 's/^> //')
      echo "  - $wing_name: $status"
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

  # Lista drawers
  echo "=== Drawers ==="
  if [ -d "$wing_dir/drawers" ]; then
    ls -1 "$wing_dir/drawers/" 2>/dev/null || echo "(nenhum drawer)"
  fi
}

cmd_update_wake_up() {
  local wake_file="$CK_DIR/_wake-up.md"
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

  # Coleta decisões recentes (últimas 3 por wing)
  local decisions=""
  for wing_dir in "$WINGS_DIR"/*/; do
    local wing_name=$(basename "$wing_dir")
    if [ "$wing_name" != "_template" ] && [ -f "$wing_dir/decisoes.md" ]; then
      local recent=$(grep -E "^- \*\*\[" "$wing_dir/decisoes.md" | head -3)
      if [ -n "$recent" ]; then
        decisions="$decisions\n### $wing_name\n$recent"
      fi
    fi
  done

  if [ -z "$decisions" ]; then
    decisions="\n> Nenhuma decisão registrada recentemente."
  fi

  # Coleta propostas pendentes
  local proposals=""
  for wing_dir in "$WINGS_DIR"/*/; do
    local wing_name=$(basename "$wing_dir")
    if [ "$wing_name" != "_template" ] && [ -f "$wing_dir/propostas.md" ]; then
      local pending=$(grep -i 'pendente' "$wing_dir/propostas.md")
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
  update-wake-up)
    cmd_update_wake_up
    ;;
  *)
    usage
    ;;
esac
