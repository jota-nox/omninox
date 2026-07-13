# OmniNox v2 — Protocolo do Vault

> Vault canônico desta máquina: o caminho registrado em `~/.config/omninox/config.json`
> (marker `.omninox-vault` na raiz — se o marker não estiver presente, você está
> na árvore errada: PARE). Nunca escrever em cópias, backups ou paths derivados de cwd.

## Arquitetura em camadas

```
TRANSCRIPT (~/.claude/projects/**/*.jsonl)     fonte de verdade, 100% automático
   └─> raw/ (Areas/omninox/raw/)               verbatim minerado por HOOKS (imutável)
         └─> drawers (wings/*/drawers/)         curadoria por sessão, link pro raw
               └─> halls + _continue + _wake-up  estado destilado por wing
                     └─> wiki/ (Areas/omninox/wiki/)  padrões da mente (compilados)
                           └─> PARA (10/20/30/40)     artefatos de trabalho cristalizados
```

**Captura é automática.** Hooks globais (`~/.claude/settings.json`) rodam
`Areas/omninox/.scripts/omni-capture.py` em Stop/PreCompact/SessionEnd: mineram o
transcript pra `raw/`, atualizam `raw/ledger.tsv` e commitam no git. Você NUNCA é
responsável por salvar verbatim (essa responsabilidade foi removida do modelo por design).

**Síntese é assíncrona.** Drawers curados, halls, `_wake-up.md` e wiki são
atualizados pelo skill `/omni-compile` (sessão dedicada, contexto fresco).
No fim de uma sessão substantiva você PODE salvar um drawer curado na hora
(via `omninox.sh save-drawer`), mas se não salvar, nada se perde: o próximo
compile gera a partir do raw.

**Sync multi-máquina (quando há backup remoto).** Cada máquina tem um clone
canônico; o hub é um repo git privado. Pull `--rebase` acontece no início de
sessão e antes de todo push; halls e ledger fundem sozinhos (`merge=union`).
Conflito real aborta e alerta — nunca resolver em silêncio.

## OmniNox vs PARA

- **OmniNox** (`Areas/omninox/`) = memória do pensamento. raw → drawers → halls → wiki.
- **PARA** (`10 Projetos/ 20 Áreas/ 30 Recursos/ 40 Arquivo/`) = artefatos de
  trabalho cristalizados. Cada pasta tem `_index.md` escrito pra você (leia antes
  de navegar). Promoção OmniNox→PARA passa pelo `/omni-compile` com ok do usuário.

## Regras

1. **raw/ é imutável.** Nunca editar, renomear ou apagar.
2. **Drawer sem link pro raw é bug.**
3. **Halls são append-only**, entradas `**[YYYY-MM-DD]**`, datas absolutas sempre.
4. **Toda escrita no vault termina em git commit** (os scripts já fazem; se
   escrever manualmente, commite).
5. **Escrita não verificada não aconteceu**: confira existência+tamanho após Write.
6. **Nova wing**: `bash Areas/omninox/.scripts/omninox.sh new-wing <nome> "<desc>"`,
   confirmando propósito com o usuário antes.
7. **Busca**: `bash Areas/omninox/.scripts/omninox.sh search "<termo>"` (halls+drawers)
   e grep em `raw/` pro verbatim.
8. **Sinal de corrupção/divergência** (arquivo sumido, cópia nova do vault,
   `.capture-errors.log` crescendo): alertar o usuário IMEDIATAMENTE, nunca
   "consertar" em silêncio.

## Sessões longas

Contexto degradando (respostas vagas, passos pulados): avise e ofereça sessão
fresca. A captura automática garante que nada da sessão atual se perde no corte.
