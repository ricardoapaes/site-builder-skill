---
name: business-biolink-seo
description: Cria páginas estáticas de bio links para empresas locais, rápidas e mobile-first, no estilo Linktree, com foco em conversão (WhatsApp, ligações e mapas), JSON-LD Schema.org LocalBusiness, metatags Open Graph e publicação no Cloudflare Pages sem etapa de build. Use para criar links na bio, microsites, cartões de visita digitais ou sites estáticos com SEO local.
---

# Gerador de bio links comerciais e SEO local

Fluxo para gerar páginas estáticas de bio links de alta conversão, em página única e no estilo Linktree, com foco na presença digital de empresas locais, conversões em dispositivos móveis e SEO técnico.

## Quando usar

- Criar uma página mobile-first de agregação de links ou micro landing page para uma empresa ou profissional local.
- Otimizar um microsite estático para o Local Pack do Google e a indexação do Google Maps.
- Criar páginas estáticas sem dependências, prontas para publicação imediata no Cloudflare Pages.
- Substituir configurações pesadas de Linktree/WordPress por um recurso estático personalizado e leve.

---

## Entregáveis por execução

O agente deve gerar uma estrutura de projeto organizada e pronta para produção:
1. `index.html`: HTML5 independente com CSS interno mínimo (sem CDNs externos nem dependências de runtime).
2. `robots.txt`: instruções adequadas de rastreamento que referenciem o sitemap.
3. `sitemap.xml`: sitemap XML apontando para o domínio canônico.
4. `_headers`: cabeçalhos de segurança e cache para o Cloudflare Pages.

---

## Instruções passo a passo

### 1. Colete/confirme os dados da empresa
Confirme os seguintes dados:
- **Nome da marca** e **nicho/categoria** (por exemplo, oficina mecânica, consultório odontológico, advocacia).
- **Cidade e estado** (por exemplo, São Paulo - SP).
- **WhatsApp** (formato: `55` + DDD + número), com texto de saudação pré-preenchido.
- **Telefone** (link `tel:`).
- **Endereço físico** e **URL direta ou incorporada do Google Maps**.
- **Horário de funcionamento** (para o schema JSON-LD).

### 2. Requisitos de SEO técnico e metadados (`<head>`)
Todo `index.html` deve incluir:
- **Title tag**: padrão obrigatório `[Nome da Empresa] | [Nicho / Palavra-chave] em [Cidade - UF]` (menos de 60 caracteres).
- **Meta description**: texto persuasivo com nome da cidade, principais serviços e CTA (140–155 caracteres).
- **Canonical**: `<link rel="canonical" href="https://[dominio]/">`.
- **Open Graph e Twitter**: `og:title`, `og:description`, `og:url`, `og:image`, `og:type="website"` e `twitter:card="summary_large_image"`.
- **JSON-LD LocalBusiness**: `<script type="application/ld+json">` inline declarando `LocalBusiness` (ou um subtipo específico, como `AutoRepair`, `MedicalClinic` ou `ProfessionalService`) com:
  - `name`, `image`, `telephone`, `url`, `address` (`PostalAddress` com `addressLocality` e `addressRegion`), `openingHoursSpecification` e `sameAs`.

### 3. Orientações de layout e UI (arquitetura Linktree)
- **Contêiner**: mobile-first, centralizado, `max-width: 520px`, espaçamento interno `1.5rem 1rem`.
- **Tipografia e tema**: pilha moderna e simples de fontes do sistema (`system-ui, -apple-system, sans-serif`). Paleta escura ou neutra e discreta, com cores de destaque de alto contraste.
- **Cabeçalho**:
  - Avatar/logo centralizado com `width`, `height` explícitos e `alt` descritivo.
  - Uma única tag `<h1>` contendo o nome da empresa.
  - Subtítulo `<p>` definindo a proposta de valor e a localização.
- **CTAs principais (alta conversão)**:
  - **WhatsApp**: botão destacado e distinto (fundo verde `#25D366` ou cor de destaque da marca), ícone e texto: *“Falar no WhatsApp”*. Link: `https://wa.me/55[DDD][NUMERO]?text=[MENSAGEM]`.
  - **Ligar agora**: CTA secundário para telefone (`tel:+55...`).
- **Lista de links secundários (`<nav>`)**:
  - Cards clicáveis de largura total (altura mínima de 48px, `border-radius` de 10–12px e transição sutil de borda/hover).
  - Use **SVGs inline** para ícones (WhatsApp, Instagram, Maps, catálogo). Nunca carregue Font Awesome nem conjuntos externos de ícones.
  - Todos os links externos devem incluir `target="_blank" rel="noopener noreferrer"`.
- **Card de contexto local**:
  - Card com endereço e link direto para o Google Maps (“Como chegar”).
  - Lista ou tabela clara de horários de funcionamento.
- **Rodapé**:
  - Copyright, CNPJ (se aplicável) e referência à cidade.

### 4. Otimização para Cloudflare Pages
Gere `_headers` na raiz:
```http
/*
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: geolocation=(), camera=(), microphone=()

/assets/*
  Cache-Control: public, max-age=31536000, immutable
```
