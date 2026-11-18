# Site Builder Skill

Conjunto de **agent** e **skill** para o OpenCode focado na criação de páginas estáticas de bio-links (estilo Linktree), cartões de visita digitais e microsites para negócios locais, com otimização de conversão mobile, SEO técnico (`Schema.org LocalBusiness`, Open Graph, Twitter Cards) e deploy direto no Cloudflare Pages sem etapa de build.

## Estrutura do repositório

```text
site-builder-skill/
├── agents/
│   └── site-builder.md              # Agent especialista em UI/UX, Design Tokens e SEO local
├── skills/
│   └── business-biolink-seo/
│       └── SKILL.md                 # Skill com fluxo passo a passo para bio-links e SEO local
├── install.sh                       # Script para vincular agents e skills no OpenCode global
└── README.md
```

## O que está incluído

### Agent: `site-builder`
Definido em [`agents/site-builder.md`](agents/site-builder.md), atua como engenheiro de frontend estático e especialista em SEO local:
- **Identidade da marca primeiro:** verifica se o projeto possui uma skill de identidade (`*-identidade`, `brand-*`, `design-tokens`) e a prioriza como fonte da verdade.
- **Zero dependências externas:** gera HTML5 + CSS interno em um único `index.html` com SVGs inline (sem Tailwind CDN, Bootstrap, FontAwesome ou jQuery).
- **Design System & a11y:** usa variáveis CSS semânticas, contraste WCAG AA e alvos de toque mínimos de `48px` para mobile.
- **Entregáveis completos:** gera `index.html`, `robots.txt`, `sitemap.xml` e `_headers` para Cloudflare Pages.

### Skill: `business-biolink-seo`
Definida em [`skills/business-biolink-seo/SKILL.md`](skills/business-biolink-seo/SKILL.md), orienta o fluxo de geração da página:
- Coleta de dados do negócio (marca, nicho, cidade/UF, WhatsApp com mensagem pré-preenchida, telefone, endereço, Google Maps e horários).
- Metatags de SEO técnico (`title`, `description`, `canonical`, Open Graph, Twitter Cards e JSON-LD `LocalBusiness`).
- Arquitetura mobile-first (`max-width: 520px`) com CTAs de alta conversão (WhatsApp e ligação) e card de contexto local.
- Arquivo `_headers` configurado com cabeçalhos de segurança e cache estático para o Cloudflare Pages.

## Instalação

### Instalação automática (recomendada)

O script [`install.sh`](install.sh) localiza automaticamente a pasta global do OpenCode e cria links simbólicos (`symlinks`) para os itens em `skills/` e `agents/`. Como usa links simbólicos, atualizações via `git pull` refletem imediatamente no OpenCode.

```bash
git clone <url-do-repositorio> site-builder-skill
cd site-builder-skill
chmod +x install.sh
./install.sh
```

#### Ordem de busca da pasta global do OpenCode
O script procura automaticamente nos seguintes locais:
1. Variável de ambiente `$OPENCODE_CONFIG_DIR` (se definida)
2. `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`
3. `$HOME/.config/opencode`
4. `$HOME/.opencode`

#### Opções do `install.sh`

| Opção | Descrição |
| --- | --- |
| `-t, --target DIR` | Informa manualmente o diretório global do OpenCode |
| `-c, --create` | Cria `~/.config/opencode` caso ainda não exista |
| `-f, --force` | Substitui symlinks divergentes ou arquivos/pastas existentes (fazendo backup) |
| `-n, --dry-run` | Simula a execução sem criar ou alterar arquivos |
| `-u, --uninstall` | Remove apenas os symlinks que apontam para este repositório |
| `-h, --help` | Exibe a ajuda do script |

Exemplos:

```bash
# Simular antes de instalar
./install.sh --dry-run

# Instalar em um diretório customizado
./install.sh --target ~/.config/opencode

# Desinstalar os symlinks criados
./install.sh --uninstall
```

### Instalação manual

Se preferir criar os links simbólicos manualmente (considerando `~/.config/opencode` como pasta global):

```bash
mkdir -p ~/.config/opencode/agents ~/.config/opencode/skills
ln -s "$(pwd)/agents/site-builder.md" ~/.config/opencode/agents/site-builder.md
ln -s "$(pwd)/skills/business-biolink-seo" ~/.config/opencode/skills/business-biolink-seo
```

### Uso por projeto (opcional)

Caso queira usar apenas em um repositório específico, copie ou vincule os arquivos dentro da pasta `.opencode/` do projeto:

```bash
mkdir -p .opencode/agents .opencode/skills
ln -s /caminho/para/site-builder-skill/agents/site-builder.md .opencode/agents/site-builder.md
ln -s /caminho/para/site-builder-skill/skills/business-biolink-seo .opencode/skills/business-biolink-seo
```

## Como usar no OpenCode

1. Abra o OpenCode na pasta onde deseja gerar o site estático.
2. Selecione ou mencione o agent **`site-builder`** (ou peça uma tarefa que acione a skill **`business-biolink-seo`**).
3. Informe os dados da empresa (nome, nicho, cidade/UF, WhatsApp, telefone, endereço, link do Google Maps e horário de funcionamento).
4. O agent apresentará a direção visual/tokens e criará os arquivos prontos para publicação:
   - `index.html`
   - `robots.txt`
   - `sitemap.xml`
   - `_headers`
5. Publique a pasta diretamente no **Cloudflare Pages** (sem comando de build; diretório de saída `.`).

