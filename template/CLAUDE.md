# OmniNox Protocol — Instruções para Claude

> Este arquivo é lido automaticamente no início de toda sessão do Claude Code.
> O hook SessionStart já injeta _wake-up.md, _identity.md e _continue.md no contexto.
> Este CLAUDE.md define o COMPORTAMENTO, não o contexto.

## Quem é o usuário

Leia Areas/omninox/_identity.md para detalhes.

## External Content Reading

Quando solicitado a ler conteúdo externo (Notion, wikis, docs, sites), **sempre pergunte primeiro**: o usuário quer uma leitura profunda (todas as sub-páginas e links) ou superficial (apenas o nível raiz)? Se deep read for confirmado, leia recursivamente todos os sub-níveis antes de gerar qualquer arquivo.

## OmniNox — Sistema de Memória

Este projeto usa o sistema OmniNox. Wings são diretórios de arquivos Markdown no vault Obsidian. Ao criar uma nova wing, **sempre confirme com o usuário a descrição/propósito ANTES de gerar qualquer arquivo**.

### OmniNox vs PARA

O vault tem dois sistemas com propósitos distintos:

- **OmniNox** (`Areas/omninox/`) = memória compartilhada. Stream de tudo que pensamos e falamos. Cronológico, acumulativo, narrativo.
- **PARA** (`10 Projetos/`, `20 Áreas/`, `30 Recursos/`, `40 Arquivo/`) = sistema de trabalho. Onde artefatos consolidados vivem — MOCs, specs, docs, resources.

**O OmniNox alimenta o PARA.** Pensamos no OmniNox; quando algo cristaliza, sobe pro PARA. Na hora de salvar, escolher o lugar certo:
- Registro de sessão/pensamento → OmniNox (drawer + halls)
- Artefato de trabalho consolidado → PARA (MOC, nota, recurso)
- Quando vai nos dois: avaliar se o OmniNox precisa do conteúdo completo ou basta apontar pro PARA.

## Environment & Tooling

Antes de rodar comandos dependentes de ambiente (brew, gh, npm, pip, etc.), verifique primeiro se a ferramenta está instalada e no PATH. Se não estiver, instale e verifique o PATH antes de prosseguir. **Nunca assuma que ferramentas CLI estão pré-instaladas.**

## Estrutura do OmniNox

Sistema de memória persistente em Markdown dentro deste vault Obsidian.
Estrutura: Areas/omninox/ com wings (projetos/pessoas), halls (decisões, problemas, descobertas, propostas), e drawers (logs verbatim).

### Hierarquia de arquivos

```
Areas/omninox/
├── _wake-up.md          # Contexto de sessão (~200 tokens, injetado pelo hook)
├── _identity.md         # Quem é o usuário (injetado pelo hook)
├── _index.md            # Mapa navegável
├── tunnels.md           # Referências cruzadas entre wings
└── wings/
    ├── _template/       # Template para novas wings
    └── {nome}/          # Uma wing por projeto/pessoa
        ├── _wing.md     # Resumo da wing
        ├── _continue.md # Checkpoint da última sessão (injetado pelo hook)
        ├── decisoes.md  # Decisões tomadas
        ├── problemas.md # Bugs, bloqueios
        ├── descobertas.md # Insights, aprendizados
        ├── propostas.md # O que Claude propôs (com status)
        └── drawers/     # Logs verbatim das conversas
            └── YYYY-MM-DD_titulo.md
```

## Protocolo de sessão

### Início (automático)
O hook SessionStart injeta _wake-up.md, _identity.md e _continue.md das wings ativas. Você NÃO precisa lê-los manualmente.
Se a conversa for sobre um projeto/pessoa específico, navegue até a wing relevante e leia _wing.md.

### Durante a conversa
- Se o usuário menciona um projeto/pessoa que tem wing, leia a wing para contexto.
- Se Claude faz uma proposta, registre mentalmente para salvar depois.
- Se uma decisão é tomada, registre mentalmente.

### Final de conversa — Protocolo de Save

O save tem duas camadas com regras diferentes:

#### Drawers (AUTO-SAVE — sem pedir permissão)
Ao final de uma conversa **substantiva** (que gerou decisões, descobertas, ou trabalho concreto), salve automaticamente um drawer:

1. Crie o drawer: `wings/{nome}/drawers/YYYY-MM-DD_titulo.md`
2. Formato do drawer:
   ```
   # YYYY-MM-DD — Título descritivo

   ## Contexto
   [Por que essa conversa aconteceu]

   ## O Que Discutimos
   [Conteúdo completo e verbatim da sessão]

   ## Decisões Tomadas
   [Lista numerada]

   ## Artefatos Gerados
   [Arquivos criados/modificados com paths]
   ```

Conversas triviais (perguntas rápidas, erros, testes) NÃO precisam de drawer.

#### Halls (CURADO — pedir permissão)
Para atualizar halls (decisoes.md, problemas.md, descobertas.md, propostas.md), **pergunte antes**:
"Quer que eu atualize os halls com [lista do que seria adicionado]?"

#### Sempre ao salvar:
- Atualize `_continue.md` da wing com o checkpoint da sessão
- Se o estado do mundo mudou significativamente, atualize `_wake-up.md`
- Use o script quando possível: `bash Areas/omninox/.scripts/omninox.sh save-drawer <wing> <titulo>`

### Criar nova wing
Use o script: `bash Areas/omninox/.scripts/omninox.sh new-wing nome-da-wing "Descrição curta"`
Ou copie manualmente de wings/_template/.

### Buscar no OmniNox
Use o script: `bash Areas/omninox/.scripts/omninox.sh search "termo"`

## Context Budget — Gestão de Sessões Longas

Monitore o uso de contexto e ajuste o comportamento:

| Tier | Uso | Comportamento |
|------|-----|---------------|
| PEAK | 0-30% | Operação normal. Leia corpos completos, faça trabalho profundo. |
| GOOD | 30-50% | Normal. Prefira leituras seletivas, delegue a subagentes quando possível. |
| DEGRADING | 50-70% | Avise o usuário: "Sessão longa — quer que eu salve e continue em sessão nova?" |
| POOR | 70%+ | Salve drawer + _continue.md IMEDIATAMENTE. Ofereça continuar em sessão fresca. |

**Sinais de degradação:** respostas vagas, passos pulados, "padrão apropriado" em vez de código concreto. Se perceber isso em si mesmo, avise.

## Regras

1. **Drawers são verbatim.** Conteúdo original, completo. Nunca resuma drawers.
2. **Halls são acumulativos.** Adicione entradas, nunca apague as anteriores.
3. **_wake-up.md é enxuto.** Máximo ~200 tokens. Só estado atual.
4. **Drawers auto-save. Halls pedem permissão.** Duas camadas, duas regras.
5. **Propostas têm status.** Sempre registre: aceita, pendente, ou rejeitada.
6. **Datas absolutas.** Nunca "ontem" ou "semana passada" — sempre YYYY-MM-DD.
7. **_continue.md atualizado.** Sempre ao final de sessão substantiva.
