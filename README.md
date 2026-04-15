# OmniNox — Sistema de Memória Persistente para Claude Code

Sistema de memória em Markdown para uso com Claude Code + Obsidian.
Injeta contexto automaticamente em toda sessão. Drawers auto-save, halls curados, busca full-text.

## Instalação

```bash
git clone https://github.com/jota-nox/omninox
cd omninox
bash install.sh
```

O installer pergunta:
- Onde criar o vault (pasta pai)
- Nome do vault
- Seu nome, localização e idioma
- Se quer criar uma wing inicial

## O que é instalado

```
<vault>/
├── 10 Projetos/
├── 20 Áreas/
├── 30 Recursos/
├── 40 Arquivo/
├── 90 Templates/
├── 00 Inbox/
├── Areas/omninox/              ← o OmniNox
│   ├── _identity.md            ← quem você é
│   ├── _wake-up.md             ← contexto da sessão (injetado automaticamente)
│   ├── _index.md               ← mapa do OmniNox
│   ├── tunnels.md              ← referências cruzadas entre wings
│   ├── .scripts/omninox.sh     ← CLI helper
│   └── wings/                  ← um diretório por projeto/pessoa
│       └── _template/          ← template para novas wings
│           ├── _wing.md
│           ├── _continue.md    ← checkpoint de sessão
│           ├── decisoes.md
│           ├── problemas.md
│           ├── descobertas.md
│           ├── propostas.md
│           └── drawers/
└── CLAUDE.md                   ← protocolo de comportamento do Claude

~/.claude/hooks/session-start.sh   ← hook global (injeta OmniNox em toda sessão)
~/.claude/settings.json            ← configura o hook no Claude Code
```

## Como usar

### Iniciar uma sessão
```bash
cd <vault>
claude
```
O OmniNox é injetado automaticamente no contexto.

### Criar uma nova wing
```bash
bash Areas/omninox/.scripts/omninox.sh new-wing projeto-x "Descrição curta"
```

### Salvar um drawer
```bash
echo "conteúdo" | bash Areas/omninox/.scripts/omninox.sh save-drawer projeto-x "titulo-sessao"
```

### Buscar no OmniNox
```bash
bash Areas/omninox/.scripts/omninox.sh search "termo"
```

### Listar wings
```bash
bash Areas/omninox/.scripts/omninox.sh list-wings
```

### Atualizar wake-up
```bash
bash Areas/omninox/.scripts/omninox.sh update-wake-up
```

## Conceitos

- **Wing** = uma ala do OmniNox para cada projeto ou pessoa
- **Halls** = corredores temáticos dentro de cada wing (decisões, problemas, descobertas, propostas)
- **Drawers** = logs verbatim das conversas — nunca resumidos
- **Tunnels** = referências cruzadas entre wings
- **Wake-up** = contexto mínimo (~200 tokens) injetado em toda sessão
- **Continue** = checkpoint da última sessão por wing (injetado automaticamente)

## Protocolo de save

O OmniNox usa duas camadas de save:

| Camada | Permissão | O que salva |
|--------|-----------|-------------|
| **Drawers** | Auto-save | Log verbatim da sessão. Sem pedir permissão. |
| **Halls** | Curado | Decisões, problemas, descobertas, propostas. Claude pede permissão. |

## Context Budget

O CLAUDE.md inclui regras de gestão de contexto para sessões longas:

| Tier | Uso | Comportamento |
|------|-----|---------------|
| PEAK | 0-30% | Operação normal |
| GOOD | 30-50% | Leituras seletivas |
| DEGRADING | 50-70% | Avisa o usuário |
| POOR | 70%+ | Salva e oferece sessão nova |

## Requisitos

- macOS ou Linux
- [Claude Code](https://claude.ai/code) instalado (`claude` no PATH)
- [Obsidian](https://obsidian.md) (opcional, mas recomendado para navegar o vault)
- Python 3 (pré-instalado no macOS)
