# Raio-X (codinome provisório)

Assistente de diagnóstico de processos SAP (SD, MM, PP) com IA, para **web, Windows, Android e iOS**.

Pergunte *"por que o pedido 4500123 não faturou?"* e receba a causa, as evidências e a ação sugerida, com a fonte citada. A lógica de diagnóstico roda em ABAP, dentro do SAP (ECC ou S/4HANA), em modo somente leitura e respeitando as autorizações do usuário. A IA interpreta a pergunta e explica o resultado.

## Versões

- **Cloud:** hospedada no nosso servidor, conectando ao SAP do cliente por um conector instalado na rede dele (conexão de saída, sem abrir firewall).
- **Self-hosted:** a ferramenta inteira roda no servidor do cliente (VM Linux + Docker) e acessa o SAP direto pela rede interna.

As duas versões usam o mesmo código e as mesmas imagens Docker; muda só a configuração.

## Documentação

- [Projeto de implementação](docs/projeto-de-implementacao.md): visão, decisões, arquitetura, plano por fases, riscos e pendências
- [Catálogo de diagnósticos](docs/catalogo-de-diagnosticos.md): o que cada diagnóstico verifica, onde e o que sugere
- [Add-on ABAP](abap/README.md): objetos e testes; [instalação no SAP](abap/INSTALACAO.md) passo a passo
- [Guia de desenvolvimento ABAP](docs/abap-guia-desenvolvimento.md): regras de sintaxe 7.00 e padrão dos diagnósticos
- [Pendências de teste](docs/pendencias-de-teste.md): o que ainda precisa ser testado com SAP real, chave do Claude e clientes

## Rodando localmente

Pré-requisitos: Node 22 e pnpm 10 (`corepack enable`).

```bash
pnpm install
pnpm dev
```

Abra http://localhost:5173 e entre com **DEMO / demo** (acesso completo) ou **VENDAS / vendas** (só vendas, para ver a autorização em ação).

| Tela | O que mostra |
|---|---|
| **Início** | Indicadores do dia, lista "Precisa de atenção agora", gráficos e pergunta rápida para a IA |
| **Assistente** | Chat com IA que consulta o SAP (os diagnósticos são as ferramentas dela) e explica causa e transação |
| **Produção** | Ordens com filtros (atrasadas, falta de material…) e página da ordem: diagnóstico, operações, componentes, apontamentos |
| **Vendas** | Pedidos travados e página do pedido com o fluxo (crédito → remessa → saída → faturamento) |
| **Compras** | Faturas bloqueadas/estacionadas e página da fatura |
| **Diagnósticos** | Execução direta de qualquer diagnóstico |
| **Ctrl+K** | Busca global: digite o nº da ordem, pedido ou fatura, ou uma pergunta |

O `pnpm dev` sobe a interface (5173), a API (3000) e o simulador SAP (8000).

### Assistente de IA

Por padrão roda em **modo demonstração** (regras locais, sem modelo, funciona offline). Para usar o Claude:

```bash
# services/api/.env
AI_PROVIDER=anthropic
ANTHROPIC_API_KEY=sk-ant-...
```

## Self-hosted com Docker

```bash
cd infra/selfhosted
cp .env.example .env                # aponte SAP_BASE_URL para o SAP (ou use o perfil demo)
docker compose --profile demo up -d --build
```

A interface fica em http://localhost:8080, servida pela própria API.

## Verificações

| Comando | O que faz |
|---|---|
| `pnpm lint` | Biome (lint + formatação) |
| `pnpm typecheck` | TypeScript em todos os pacotes |
| `pnpm test` | Testes de contratos, simulador, API e web |
| `pnpm abaplint` | ABAP com sintaxe NetWeaver 7.00 |
| `pnpm test:abap` | ABAP Unit fora do SAP (open-abap) |
| `pnpm test:selfhosted` | Pacote self-hosted ponta a ponta **sem internet** (D23, requer Docker) |

## Estrutura

```
apps/web/            Interface React + Vite + Tailwind (PWA; base de Tauri e Capacitor)
services/api/        Backend Fastify: mesma imagem para Cloud e Self-hosted
services/sap-mock/   Simulador da API ABAP (cenários do MVP)
packages/contracts/  Contratos Zod compartilhados (resultado, diagnósticos, erros)
abap/src/            Add-on ABAP (formato abapGit)
tools/abap-unit/     Executor de ABAP Unit fora do SAP
infra/               Dockerfiles e pacote self-hosted
docs/                Projeto e catálogo
```

## Status

✅ Fase 0 (fundação) e boa parte das Fases 2 e 3: app web completo, assistente de IA (Claude + modo demonstração), sessão por cookie, painel e páginas por documento, tudo sobre o simulador SAP.
✅ Fase 1a no código: os 7 diagnósticos em ABAP (SD-01, SD-10, MM-02, MM-10, PP-01, PP-03, PP-04) com 169 testes ABAP Unit fora do SAP.
⏳ Testes pendentes (SAP real, chave do Claude, mercado): [docs/pendencias-de-teste.md](docs/pendencias-de-teste.md).
Próximo: persistência (PostgreSQL) para conversas e sessões, e o conector da versão Cloud (Fase 4).
