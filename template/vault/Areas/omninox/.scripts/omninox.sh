#!/bin/bash
# OmniNox CLI — Helper para o sistema de memória OmniNox
# Uso: bash omninox.sh <comando> [args...]

# PATH CANÔNICO da config (~/.config/omninox/config.json) — nunca derivar
# de $0: foi assim que sessões escreveram em cópias do vault (split-brain
# descoberto em 2026-07-13). O marker abaixo é a segunda trava.
VAULT=$(python3 -c "import json;print(json.load(open('$HOME/.config/omninox/config.json')).get('vaultPath',''))" 2>/dev/null)
[ -z "$VAULT" ] && VAULT="$HOME/Documents/omninox"
OMNINOX_DIR="$VAULT/Areas/omninox"
WINGS_DIR="$OMNINOX_DIR/wings"
TEMPLATE_DIR="$WINGS_DIR/_template"

if [ ! -f "$VAULT/.omninox-vault" ]; then
  echo "ERRO: marker .omninox-vault ausente em $VAULT — vault canônico não encontrado. Nada foi escrito." >&2
  exit 1
fi

# commit automático pós-escrita: git é a testemunha de toda mutação
omninox_commit() {
  git -C "$VAULT" add -A >/dev/null 2>&1
  git -C "$VAULT" diff --cached --quiet 2>/dev/null || \
    git -C "$VAULT" commit -q -m "omninox.sh: $1" >/dev/null 2>&1
}

usage() {
  echo "OmniNox CLI — Sistema de memória persistente"
  echo ""
  echo "Comandos:"
  echo "  new-wing <nome> <descricao>         Cria nova wing a partir do template"
  echo "  list-wings                           Lista wings ativas"
  echo "  read-wing <nome>                    Lê o contexto completo de uma wing"
  echo "  list-drawers <wing> [N]             Lista drawers de uma wing (N mais recentes)"
  echo "  save-drawer <wing> <titulo>         Cria drawer (conteúdo via stdin)"
  echo "  search <termo>                       Busca full-text, ordenado por frequência"
  echo "  update-wake-up                       Regenera _wake-up.md a partir do estado atual"
  echo ""
  echo "Exemplos:"
  echo "  bash omninox.sh new-wing projeto-x 'Redesign do dashboard principal'"
  echo "  bash omninox.sh list-drawers jota 5"
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

  # não usar $wing_dir aqui: cmd_update_wake_up itera "for wing_dir in ..." sem
  # local e, pelo dynamic scoping do bash, sobrescreve o local do caller
  echo "Wing '$name' criada com sucesso em $WINGS_DIR/$name"
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

cmd_list_drawers() {
  local wing="$1"
  local recent="${2:-0}"

  if [ -z "$wing" ]; then
    echo "Erro: uso: omninox.sh list-drawers <wing> [N]"
    exit 1
  fi

  local wing_dir="$WINGS_DIR/$wing"
  if [ ! -d "$wing_dir" ]; then
    echo "Erro: wing '$wing' não encontrada"
    exit 1
  fi

  local drawers_dir="$wing_dir/drawers"
  if [ ! -d "$drawers_dir" ] || [ -z "$(ls -A "$drawers_dir" 2>/dev/null)" ]; then
    echo "Nenhum drawer em '$wing'."
    exit 0
  fi

  local total=$(ls -1 "$drawers_dir"/*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "Drawers — $wing ($total total):"
  echo ""

  if [ "$recent" -gt 0 ]; then
    ls -1t "$drawers_dir"/*.md 2>/dev/null | head -"$recent" | while read -r f; do
      echo "  $(basename "$f")"
    done
  else
    ls -1t "$drawers_dir"/*.md 2>/dev/null | while read -r f; do
      echo "  $(basename "$f")"
    done
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
    cat > "$filepath" << EOF
# Drawer: ${titulo}

> **Data:** ${today}
> **Wing:** ${wing}

---

EOF
    echo "Drawer criado (vazio): $filepath"
    echo "Edite o arquivo para adicionar conteúdo."
  else
    cat > "$filepath"
    # verificação: escrita sem verificação não aconteceu
    if [ -s "$filepath" ]; then
      echo "Drawer salvo e verificado: $filepath ($(wc -c < "$filepath" | tr -d ' ') bytes)"
    else
      echo "ERRO: drawer vazio ou não escrito em $filepath" >&2
      exit 1
    fi
  fi

  cmd_update_wake_up > /dev/null 2>&1
  omninox_commit "save-drawer $wing/$filename"
}

cmd_search() {
  local term="$1"

  if [ -z "$term" ]; then
    echo "Erro: uso: omninox.sh search <termo>"
    exit 1
  fi

  echo "=== Buscando '$term' no OmniNox ==="
  echo ""

  local tmp_results
  tmp_results=$(mktemp)

  # Halls
  for wing_dir in "$WINGS_DIR"/*/; do
    local wing_name
    wing_name=$(basename "$wing_dir")
    [ "$wing_name" = "_template" ] && continue

    for hall in decisoes problemas descobertas propostas; do
      local hall_file="$wing_dir/$hall.md"
      if [ -f "$hall_file" ]; then
        local count
        count=$(grep -ci "$term" "$hall_file" 2>/dev/null || echo 0)
        [ "$count" -gt 0 ] && echo "${count}|$wing_name/$hall.md|$hall_file" >> "$tmp_results"
      fi
    done
  done

  # Drawers
  for wing_dir in "$WINGS_DIR"/*/; do
    local wing_name
    wing_name=$(basename "$wing_dir")
    [ "$wing_name" = "_template" ] && continue

    if [ -d "$wing_dir/drawers" ]; then
      for drawer in "$wing_dir/drawers"/*.md; do
        [ -f "$drawer" ] || continue
        local count
        count=$(grep -ci "$term" "$drawer" 2>/dev/null || echo 0)
        if [ "$count" -gt 0 ]; then
          local drawer_name
          drawer_name=$(basename "$drawer")
          echo "${count}|$wing_name/drawers/$drawer_name|$drawer" >> "$tmp_results"
        fi
      done
    fi
  done

  # Core files
  for core in _wake-up.md _index.md tunnels.md; do
    local core_file="$OMNINOX_DIR/$core"
    if [ -f "$core_file" ]; then
      local count
      count=$(grep -ci "$term" "$core_file" 2>/dev/null || echo 0)
      [ "$count" -gt 0 ] && echo "${count}|$core|$core_file" >> "$tmp_results"
    fi
  done

  if [ ! -s "$tmp_results" ]; then
    echo "Nenhum resultado para '$term'."
    rm -f "$tmp_results"
    return
  fi

  # Ordenar por contagem decrescente e exibir
  sort -t'|' -k1 -rn "$tmp_results" | while IFS='|' read -r count label filepath; do
    echo "--- $label (${count}x) ---"
    grep -in "$term" "$filepath" | head -5
    if [ "$count" -gt 5 ]; then
      echo "  ... (+$((count - 5)) linhas)"
    fi
    echo ""
  done

  rm -f "$tmp_results"
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
      # halls são append-only: as entradas mais RECENTES estão no fim (tail, não head)
      local recent=$(grep -E "^(- \*\*\[|## \[|\*\*\[)" "$wing_dir/decisoes.md" | tail -3)
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
  list-drawers)
    cmd_list_drawers "$2" "$3"
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
