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

## Stack (resumo)

| Camada | Tecnologia |
|---|---|
| Interface | React + Vite + TypeScript: PWA (web), Tauri 2 (Windows), Capacitor (Android/iOS) |
| Backend | Node + TypeScript (Fastify, Zod, Drizzle, PostgreSQL) |
| Conector on-premise | Node + TypeScript (WebSocket de saída) |
| SAP | Add-on ABAP (REST via ICF, abapGit) |
| Monorepo | pnpm + Turborepo |

## Status

📐 Fase de definição. O código começa na Fase 0 (ver o plano de implementação).
