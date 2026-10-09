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
- [Add-on ABAP](abap/README.md): objetos, instalação via abapGit e testes

## Rodando localmente

Pré-requisitos: Node 22 e pnpm 10 (`corepack enable`).

```bash
pnpm install
pnpm dev
```

Abra http://localhost:5173 e entre com **DEMO / demo** (todos os diagnósticos) ou **VENDAS / vendas** (só SD-01). O `pnpm dev` sobe:

| Serviço | Porta | O que é |
|---|---|---|
| `apps/web` | 5173 | Interface (Vite, com proxy de `/api` para a API) |
| `services/api` | 3000 | Backend, no modo self-hosted com transporte direto |
| `services/sap-mock` | 8000 | Simulador do add-on ABAP, com cenários fixos (`/sap/bc/zrx/api/v1`) |

Os exemplos clicáveis na tela (pedidos 4500001…, ordens 1000001…) são os cenários do simulador.

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

✅ Fase 0 (fundação): monorepo, contratos, simulador, API, web em modo sem IA, framework ABAP, Docker e CI.
Próximo: Fase 1a (framework ABAP no Trial, objeto `ZRX_DIAG`, log) e Fase 2 (sessão, IA).
