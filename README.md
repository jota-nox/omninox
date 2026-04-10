# Claudiknows — Sistema PARA + Claudiknows para Claude Code

Sistema de memória persistente em Markdown para uso com o Claude Code.
Combina organização PARA (Obsidian) com um Claudiknows que injeta contexto automaticamente em toda sessão.

## Instalação

```bash
git clone https://github.com/<seu-usuario>/palace
cd claudiknows
bash install.sh
```

O installer vai perguntar:
- Onde criar o vault (pasta pai)
- Nome do vault
- Seu nome, localização e idioma
- Se quer criar uma wing inicial

Tempo estimado: ~2 minutos.

## O que é instalado

```
<vault>/
├── 10 Projetos/
├── 20 Áreas/
├── 30 Recursos/
├── 40 Arquivo/
├── 90 Templates/
├── 00 Inbox/
├── Areas/claudiknows/          ← o Claudiknows
│   ├── _identity.md       ← quem você é
│   ├── _wake-up.md        ← contexto da sessão (injetado automaticamente)
│   ├── _index.md          ← mapa do Claudiknows
│   ├── .scripts/claudiknows.sh ← CLI helper
│   └── wings/             ← um diretório por projeto/pessoa
└── CLAUDE.md              ← instruções do Claudiknows para o Claude

~/.claude/hooks/session-start.sh   ← hook global (injeta Claudiknows em toda sessão)
~/.claude/settings.json            ← configura o hook no Claude Code
```

## Como usar

### Iniciar uma sessão
```bash
cd <vault>
claude
```
O Claudiknows é injetado automaticamente no contexto.

### Criar uma nova wing (projeto ou pessoa)
```bash
bash Areas/claudiknows/.scripts/claudiknows.sh new-wing nome-do-projeto "Descrição curta"
```

### Listar wings
```bash
bash Areas/claudiknows/.scripts/claudiknows.sh list-wings
```

### Atualizar wake-up
```bash
bash Areas/claudiknows/.scripts/claudiknows.sh update-wake-up
```

## Conceitos

- **Wing** = uma ala do Claudiknows para cada projeto ou pessoa
- **Halls** = corredores temáticos dentro de cada wing (decisões, problemas, descobertas, propostas)
- **Drawers** = logs verbatim das conversas — nunca resumidos
- **Wake-up** = contexto mínimo (~200 tokens) injetado em toda sessão

## Requisitos

- macOS ou Linux
- [Claude Code](https://claude.ai/code) instalado (`claude` no PATH)
- [Obsidian](https://obsidian.md) (opcional, mas recomendado para navegar o vault)
- Python 3 (pré-instalado no macOS)
