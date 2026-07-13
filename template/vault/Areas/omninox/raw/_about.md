# raw/ — camada verbatim (imutável)

> **Para agentes:** esta pasta é gerada por máquina (`.scripts/omni-capture.py`,
> disparado por hooks globais Stop/PreCompact/SessionEnd). NUNCA edite, renomeie
> ou apague arquivos aqui. Ela é a fonte de verdade do pensamento do dono do vault.

## O que é

Cada arquivo `YYYY-MM-DD_<sessionid8>_<cwd>.md` é o verbatim minerado do
transcript real (`~/.claude/projects/**/*.jsonl`): toda mensagem do usuário e
toda resposta em texto do Claude, com timestamps BRT. Front-matter traz
session_id, cwd, janela temporal e arquivos tocados.

- Cobertura: 100% das sessões ≥ 50 KB de transcript (as menores ficam
  registradas só no `ledger.tsv`).
- `ledger.tsv` é o índice: uma linha por sessão vista pelos hooks.
- `.capture-errors.log` registra falhas de captura — se crescer, algo está errado.

## Relação com os drawers

Drawer (em `wings/*/drawers/`) é **curadoria**: resumo denso escrito por um
agente, com link pro raw correspondente. O raw garante que nada se perde;
o drawer torna útil. Se um drawer faltar, o `/omni-compile` o gera a partir daqui.
