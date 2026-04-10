# Claudiknows Protocol — Instruções para Claude

> Este arquivo é lido automaticamente no início de toda sessão do Claude Code.
> O hook SessionStart já injeta _wake-up.md e _identity.md no contexto.
> Este CLAUDE.md define o COMPORTAMENTO, não o contexto.

## Quem é o usuário

Leia Areas/claudiknows/_identity.md para detalhes.
Tom: direto, informal, sem enrolação. Prefere soluções que funcionem.

## O que é o Claudiknows

O Claudiknows é um sistema de memória persistente em Markdown dentro deste vault Obsidian.
Estrutura: Areas/claudiknows/ com wings (projetos/pessoas), halls (decisões, problemas, descobertas, propostas), e drawers (logs verbatim).

### Hierarquia de arquivos

```
Areas/claudiknows/
├── _wake-up.md          # Contexto de sessão (~200 tokens, injetado pelo hook)
├── _identity.md         # Quem é o usuário (injetado pelo hook)
├── _index.md            # Mapa navegável
├── tunnels.md           # Referências cruzadas entre wings
└── wings/
    ├── _template/       # Template para novas wings
    └── {nome}/          # Uma wing por projeto/pessoa
        ├── _wing.md     # Resumo da wing
        ├── decisoes.md  # Decisões tomadas
        ├── problemas.md # Bugs, bloqueios
        ├── descobertas.md # Insights, aprendizados
        ├── propostas.md # O que Claude propôs (com status)
        └── drawers/     # Logs verbatim das conversas
            └── YYYY-MM-DD_titulo.md
```

## Protocolo de sessão

### Início (automático)
O hook SessionStart injeta _wake-up.md e _identity.md. Você NÃO precisa lê-los manualmente.
Se a conversa for sobre um projeto/pessoa específico, navegue até a wing relevante e leia _wing.md.

### Durante a conversa
- Se o usuário menciona um projeto/pessoa que tem wing, leia a wing para contexto.
- Se Claude faz uma proposta, registre mentalmente para salvar depois.
- Se uma decisão é tomada, registre mentalmente.

### Final de conversa substantiva
Ao final de uma conversa que gerou valor (decisões, descobertas, propostas), execute o protocolo de salvamento:

1. **Pergunte antes de salvar.** Sempre. ("Quer que eu salve essa sessão no Claudiknows?")
2. Se sim, use o script helper: `bash Areas/claudiknows/.scripts/claudiknows.sh save-session`
3. Ou faça manualmente:
   a. Crie o drawer em `wings/{nome}/drawers/YYYY-MM-DD_titulo.md`
   b. Atualize os halls relevantes (decisoes, problemas, descobertas, propostas)
   c. Atualize `_wake-up.md` se o estado do mundo mudou
   d. Atualize `_index.md` se uma nova wing foi criada

### Criar nova wing
Use o script: `bash Areas/claudiknows/.scripts/claudiknows.sh new-wing nome-da-wing "Descrição curta"`
Ou copie manualmente de wings/_template/.

## Regras

1. **Nunca resuma drawers.** Drawers são verbatim — o conteúdo original, completo.
2. **Halls são acumulativos.** Adicione entradas, nunca apague as anteriores.
3. **_wake-up.md é enxuto.** Máximo ~200 tokens. Só estado atual.
4. **Pergunte antes de salvar.** O usuário decide o que vale registrar.
5. **Propostas têm status.** Sempre registre: aceita, pendente, ou rejeitada.
6. **Datas absolutas.** Nunca "ontem" ou "semana passada" — sempre YYYY-MM-DD.
