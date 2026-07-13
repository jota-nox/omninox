# OmniNox v2

Memória persistente pro Claude Code: um vault Obsidian onde toda sessão de
trabalho é capturada automaticamente, destilada em conhecimento curado e
(se você quiser) sincronizada entre máquinas por um repositório privado.

## Instalar

Cole uma linha no Terminal e siga o assistente (em português):

```
curl -fsSL https://raw.githubusercontent.com/jota-nox/omninox/main/install.sh | bash
```

O assistente cuida de tudo: ferramentas da Apple, Claude Code, Obsidian,
o app OmniNox Capture, a estrutura do vault, os hooks de captura e as
permissões. Três caminhos possíveis:

1. **Novo** (vault em branco pra começar do zero)
2. **Restaurar** (máquina nova ou formatada: clona seu backup e tudo volta,
   inclusive a memória do Claude)
3. **Atualizar** (detecta uma instalação existente e só atualiza scripts e apps)

### Backup e multi-máquina

Durante a instalação você escolhe se quer backup num repositório **privado**
do GitHub. Com backup ativo, cada máquina onde você instalar o OmniNox vira
uma estação de trabalho do mesmo cérebro: o vault sincroniza sozinho (pull no
início de sessão, push no fim), e appends paralelos em máquinas diferentes se
fundem sem conflito. Sem backup, tudo funciona igual, só que existe apenas na
sua máquina (você pode ativar depois rodando o instalador de novo).

## Como funciona

```
TRANSCRIPT (Claude Code)      tudo que você conversa, 100% automático
   └─> raw/                   verbatim minerado por hooks (imutável)
         └─> drawers          resumo curado por sessão
               └─> halls      decisões, descobertas, propostas por projeto
                     └─> wiki padrões compilados da sua forma de pensar
                           └─> PARA  artefatos de trabalho (10/20/30/40)
```

- **Captura é automática.** Hooks do Claude Code mineram o transcript de cada
  sessão pro vault. Você nunca precisa pedir "salva isso".
- **Síntese é assíncrona.** De tempos em tempos, rode `/omni-compile` numa
  sessão do Claude: os verbatims viram drawers curados, halls e wiki.
- **Capture rápido.** `⌘⇧N` de qualquer lugar abre o OmniNox Capture
  (app nativo de 532 KB): texto, imagens com OCR automático, arquivos.
  Tudo cai no `00 Inbox` do vault, já com git.

## O que tem neste repositório

| Pasta | O quê |
|---|---|
| `install.sh` | O instalador/assistente |
| `template/vault/` | O vault em branco (estrutura PARA + OmniNox) |
| `capture/` | Código do OmniNox Capture (Swift/AppKit, arquivo único) |
| `claude-config/` | Hooks e skill `/omni-compile` pro Claude Code |

O binário do Capture vem pré-compilado nos
[releases](https://github.com/jota-nox/omninox/releases) (o instalador baixa
sozinho; ninguém precisa de Xcode).

## Requisitos

macOS Apple Silicon. Conta no Claude (o Claude Code é instalado pelo
assistente se faltar). Conta no GitHub apenas se quiser backup.
