# Palace — Sistema PARA + MemPalace para Claude Code

Sistema de memória persistente em Markdown para uso com o Claude Code.
Combina organização PARA (Obsidian) com um MemPalace que injeta contexto automaticamente em toda sessão.

## Instalação

```bash
git clone https://github.com/<seu-usuario>/palace
cd palace
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
├── Areas/palace/          ← o MemPalace
│   ├── _identity.md       ← quem você é
│   ├── _wake-up.md        ← contexto da sessão (injetado automaticamente)
│   ├── _index.md          ← mapa do palace
│   ├── .scripts/palace.sh ← CLI helper
│   └── wings/             ← um diretório por projeto/pessoa
└── CLAUDE.md              ← instruções do palace para o Claude

~/.claude/hooks/session-start.sh   ← hook global (injeta palace em toda sessão)
~/.claude/settings.json            ← configura o hook no Claude Code
```

## Como usar

### Iniciar uma sessão
```bash
cd <vault>
claude
```
O palace é injetado automaticamente no contexto.

### Criar uma nova wing (projeto ou pessoa)
```bash
bash Areas/palace/.scripts/palace.sh new-wing nome-do-projeto "Descrição curta"
```

### Listar wings
```bash
bash Areas/palace/.scripts/palace.sh list-wings
```

### Atualizar wake-up
```bash
bash Areas/palace/.scripts/palace.sh update-wake-up
```

## Conceitos

- **Wing** = uma ala do palace para cada projeto ou pessoa
- **Halls** = corredores temáticos dentro de cada wing (decisões, problemas, descobertas, propostas)
- **Drawers** = logs verbatim das conversas — nunca resumidos
- **Wake-up** = contexto mínimo (~200 tokens) injetado em toda sessão

## Requisitos

- macOS ou Linux
- [Claude Code](https://claude.ai/code) instalado (`claude` no PATH)
- [Obsidian](https://obsidian.md) (opcional, mas recomendado para navegar o vault)
- Python 3 (pré-instalado no macOS)
