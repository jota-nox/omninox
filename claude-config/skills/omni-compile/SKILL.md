---
name: omni-compile
description: Consolidação assíncrona do OmniNox — transforma verbatims raw/ em drawers curados, atualiza halls/_continue/_wake-up, mantém a wiki/ e roda lint de integridade. Use quando o usuário disser '/omni-compile', 'compila o omni', 'consolida as sessões', ou ao final de um dia de trabalho pesado. NÃO é a captura (essa é automática por hooks) — é a curadoria.
---

# omni-compile — síntese assíncrona do OmniNox

## Arquitetura (contexto obrigatório)

O OmniNox v2 separa **captura** de **síntese**:

- **Captura (automática, hooks)**: `omni-capture.py` minera todo transcript pra
  `Areas/omninox/raw/` (verbatim imutável, 100% de cobertura). Você nunca faz captura.
- **Síntese (este skill)**: transforma raw em conhecimento curado. Roda em sessão
  dedicada, com contexto fresco — nunca no fim de sessão degradado.

Vault canônico: o caminho em `~/.config/omninox/config.json` (chave `vaultPath`).
Valide o marker `.omninox-vault` antes de qualquer escrita; se ausente, PARE e avise.

## Fluxo

### 1. Descobrir o que há pra compilar
```bash
V="$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.config/omninox/config.json')))['vaultPath'])")/Areas/omninox"
# raws ainda não referenciados por nenhum drawer:
for r in "$V"/raw/2*.md; do
  grep -rlq "$(basename "$r")" "$V"/wings/*/drawers/ 2>/dev/null || echo "PENDENTE: $(basename "$r")"
done
```
Considere também `raw/ledger.tsv` (sessões triviais <50KB não têm raw — ok ignorar).

### 2. Pra cada raw pendente substantivo
1. Leia o raw (front-matter: cwd, janela, files_touched; corpo: verbatim).
2. Classifique a wing (jota, jota-ux-review, jorgex, geral, carreira, biblioteca,
   resonance...). Sessões de trabalho no jota-site → wing jota. Na dúvida, geral.
3. Escreva o drawer curado em `wings/{wing}/drawers/YYYY-MM-DD_titulo.md`:

```markdown
# YYYY-MM-DD — Título descritivo

> **Raw:** [[../../../raw/ARQUIVO_RAW.md]] (verbatim completo)
> **Sessão:** <session_id8> · <cwd> · <hh:mm início–fim>

## Contexto
[por que a sessão aconteceu]

## O que aconteceu
[resumo DENSO: decisões com racional, descobertas, mudanças de direção,
 reações do usuário — o COMO ele pensou, não só o resultado]

## Decisões
[numeradas, com data]

## Artefatos
[paths criados/modificados — use files_touched do raw]
```

O drawer é curadoria: denso mas seletivo. O verbatim já está garantido no raw —
não copie a conversa, destile o raciocínio.

4. Aglutine: várias sessões pequenas do mesmo dia/tema podem virar UM drawer
   (liste todos os raws no cabeçalho).

### 3. Atualizar as camadas derivadas
- **Halls** (`decisoes.md`, `descobertas.md`, `problemas.md`, `propostas.md`):
  append das entradas novas, formato `**[YYYY-MM-DD]** texto`. Nunca apagar.
- **`_continue.md`** da wing: sobrescrever com o checkpoint mais atual.
- **`_wake-up.md`**: regenerar via
  `bash $V/.scripts/omninox.sh update-wake-up` e depois revisar manualmente a
  seção de decisões (o script pega as 3 primeiras linhas — garanta que são as
  mais recentes).
- **wiki/** (`Areas/omninox/wiki/`): se a rodada revelou um conceito, padrão de
  pensamento ou tese que atravessa sessões, crie/atualize a página (ver
  `wiki/_about.md`). Atualização cirúrgica: só as páginas afetadas.

### 4. Promoções pro PARA
Se algo cristalizou (spec fechada, decisão de produto, recurso permanente),
proponha ao usuário a promoção pra `10 Projetos/` ou `30 Recursos/` — liste as
candidatas no relatório final, não mova sem ok.

### 5. Lint de integridade (sempre, mesmo sem raws pendentes)
- `raw/.capture-errors.log` tem entradas novas? → reportar.
- `git -C <vault> status` sujo? → commit.
- Sessões no ledger dos últimos 7 dias sem `extracted_to` e com transcript
  > 50KB? → capture falhou, rodar `omni-capture.py --backfill`.
- Wings com `_continue.md` mais velho que o drawer mais recente da wing? → atualizar.
- `mdfind -name "omni-nox" | grep -v Documents/obsidian-omni-nox` retorna algo?
  → CÓPIA FANTASMA NOVA, alertar o usuário imediatamente.

### 6. Fechar
- `git -C <vault> add -A && git commit` com mensagem `omni-compile: <resumo>`.
- Relatório final pro usuário: N raws compilados → N drawers, halls tocados,
  páginas wiki atualizadas, candidatas a promoção PARA, achados do lint.

## Regras
1. Raw é imutável — NUNCA edite `raw/`.
2. Drawer sem link pro raw é bug.
3. Halls são append-only.
4. Escreva só no vault canônico (marker!).
5. Compile grande (>10 raws)? Delegue lotes a subagentes por wing e revise.
