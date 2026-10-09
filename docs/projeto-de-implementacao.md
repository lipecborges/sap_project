# Projeto de Implementação — Raio-X (codinome provisório)

> Assistente de diagnóstico de processos SAP (SD, MM, PP) com IA, para web, Windows, Android e iOS.

| | |
|---|---|
| **Versão** | 0.4: VM Linux como pré-requisito do self-hosted (D22) e piloto Cloud sem dependência de nuvem (D23) |
| **Data** | 09/10/2026 |
| **Status** | Em definição. As decisões marcadas como *Proposta* aguardam aprovação |
| **Documentos relacionados** | [Catálogo de diagnósticos](./catalogo-de-diagnosticos.md) |

> "Raio-X" é só um codinome de trabalho. O nome comercial não pode conter "SAP" (ver P13).

---

## Sumário

1. [Resumo executivo](#1-resumo-executivo)
2. [Problema, proposta de valor e público](#2-problema-proposta-de-valor-e-público)
3. [Decisões](#3-decisões)
4. [Arquitetura](#4-arquitetura)
5. [Add-on ABAP](#5-add-on-abap)
6. [Backend](#6-backend)
7. [Inteligência artificial](#7-inteligência-artificial)
8. [Autenticação e identidade](#8-autenticação-e-identidade)
9. [Licenciamento e cobrança](#9-licenciamento-e-cobrança)
10. [Segurança, privacidade e compliance](#10-segurança-privacidade-e-compliance)
11. [Multiplataforma](#11-multiplataforma)
12. [Estrutura do repositório](#12-estrutura-do-repositório)
13. [Qualidade, testes e CI/CD](#13-qualidade-testes-e-cicd)
14. [Plano de implementação](#14-plano-de-implementação)
15. [Riscos e mitigações](#15-riscos-e-mitigações)
16. [Pendências e perguntas em aberto](#16-pendências-e-perguntas-em-aberto)
17. [Próximos passos](#17-próximos-passos)

---

## 1. Resumo executivo

O Raio-X responde, em linguagem natural, perguntas do tipo **"por que este processo travou?"** no SAP ECC e no S/4HANA:

- *"Por que o pedido de venda 4500123 não faturou?"*
- *"Por que a fatura deste fornecedor está bloqueada?"*
- *"Por que a ordem de produção 1000456 não liberou?"*

**Como funciona:**

1. A lógica de cada diagnóstico roda em **ABAP, dentro do SAP do cliente**, em modo somente leitura e respeitando as autorizações do usuário.
2. O resultado é estruturado: causa, evidências e ação sugerida.
3. A **IA interpreta a pergunta**, escolhe e executa os diagnósticos e **explica o resultado** em linguagem simples, citando a fonte.
4. Uma única interface **React + TypeScript** atende web (PWA), Windows (Tauri) e Android/iOS (Capacitor).

**Principal diferencial:** o conhecimento funcional de SD, MM e PP vira código. A IA não "adivinha" SQL; ela usa diagnósticos escritos por quem conhece o processo.

---

## 2. Problema, proposta de valor e público

### Problema
- Chamados do tipo "X não aconteceu" (pedido não faturou, fatura bloqueada, ordem não liberou) são uma parte grande do volume de suporte SAP.
- Investigar exige navegar por várias transações e tabelas (fluxo de documentos, status, bloqueios, logs) e depende de poucos especialistas.
- O SAP Joule e a IA nativa da SAP focam em S/4 Cloud/RISE. **Clientes ECC estão praticamente sem opção.**

### Proposta de valor
> De 30 a 60 minutos de investigação para segundos: causa, evidência e próxima ação, com a fonte citada.

### Público-alvo, em ordem de prioridade
1. **Consultorias de AMS (suporte SAP):** ganham produtividade e margem por chamado e já têm acesso aos sistemas dos clientes.
2. **Key users e suporte interno** de empresas médias e grandes com ECC ou S/4 on-premise.
3. **Gestores:** consultas rápidas no celular ("o pedido do cliente X já saiu?").

### Diferenciais
- Diagnósticos escritos por especialista (ABAP + funcional), não SQL gerado por IA.
- Funciona em **ECC e S/4** com o mesmo produto.
- **Funciona sem IA** (modo diagnóstico direto), útil para clientes que ainda não liberaram IA.
- Respeita as autorizações SAP do usuário e mostra a fonte de cada resposta.

### Fora do escopo inicial
- Qualquer **escrita** no SAP (criar, alterar ou liberar documentos).
- FI aprofundado, fiscal Brasil e reforma tributária (possível módulo futuro, com especialista).
- S/4HANA Public Cloud (entra na Fase 6, via APIs liberadas).
- Dados de RH/HCM (sensíveis).

---

## 3. Decisões

### 3.1 Decisões tomadas na conversa

| ID | Decisão | Motivo |
|---|---|---|
| D01 | **Nicho:** diagnóstico de processos logísticos **SD, MM e PP** (mais IDoc e fatura de fornecedor) | Combina com o perfil ABAP + funcional. Dor clara e cara. Difícil de copiar |
| D02 | **Somente leitura** no SAP, garantido no ABAP (não só no prompt) | Facilita a aprovação pela segurança do cliente e elimina o risco de a IA alterar dados |
| D03 | **Lógica de diagnóstico em ABAP**, dentro do SAP. A IA só interpreta e explica o resultado | Precisão, uma chamada por diagnóstico e menos dados expostos ao LLM |
| D04 | **Exposição via REST no ICF** (`IF_HTTP_EXTENSION`) com JSON, **um serviço por diagnóstico** (não por consulta) e versão na URL | HTTP puro, sem SDK RFC. Funciona em ECC e S/4 on-premise |
| D05 | **Front único em React + Vite + TypeScript**: PWA (web), **Tauri 2** (Windows) e **Capacitor** (Android/iOS) | Cerca de 95% do código compartilhado entre as quatro plataformas |
| D06 | **Backend em TypeScript (Node)** | Uma linguagem só fora do SAP. Tipos compartilhados com o front |
| D07 | **Monorepo** com pnpm + Turborepo. ABAP versionado com **abapGit** no mesmo repositório | Tudo versionado junto, com contratos compartilhados |
| D08 | **Conector on-premise** com conexão **de saída** (WebSocket/TLS). Alternativa: SAP Cloud Connector | Sem abrir porta de entrada no firewall do cliente |
| D09 | **Autenticação com os usuários SAP**, em camada plugável e por fases (ver seção 8) | Mesmas autorizações e auditoria. Simplifica a conversa sobre licenciamento SAP |
| D10 | **Licenciamento por usuário nomeado + franquia de uso de IA**, controlado no backend (nunca no ABAP). Arquivo de licença assinado para self-hosted | Modelo conhecido no mercado SAP. A franquia protege a margem contra o custo variável da IA |
| D11 | **Provedor de IA plugável.** O cliente pode usar um modelo na própria nuvem | Exigência comum de clientes enterprise |
| D12 | **O produto funciona sem IA** (modo diagnóstico direto) | Remove a principal objeção de clientes conservadores |
| D13 | **Requisitos de confiança desde o MVP:** auditoria, mascaramento, citação da fonte e respeito às autorizações | Viram argumento de venda em vez de obstáculo |
| D14 | **Multi-tenant desde o início** na versão Cloud. A mesma base roda com um único tenant no Self-hosted (D21) | Um código só para os dois modos |
| D15 | **Web primeiro.** Desktop e mobile depois, com o mesmo código | Entrega valor mais cedo, sem retrabalho |
| D16 | `RFC_READ_TABLE` **apenas para exploração**, nunca no produto | Limitações técnicas, não é liberada para clientes e enfrenta resistência da segurança |
| D17 | **Release mínimo: SAP NetWeaver 7.00** (ECC 6.0 em qualquer EHP). Código ABAP com **sintaxe 7.00**, verificada pelo abaplint (ver seção 5.5) | Atinge toda a base ECC. O custo é abrir mão da sintaxe 7.40 e escrever um serializador JSON próprio |
| D18 | **Escopo do MVP:** `SD-01`, `MM-02`, `PP-01`, mais `PP-03` (situação da ordem de produção) e `PP-04` (ordens atrasadas / lista por situação) | As três maiores dores, mais a visão de acompanhamento da produção pedida |
| D19 | **Ambiente SAP em etapas:** `sap-mock` + ABAP Platform Trial agora (grátis); **sprint concentrado de 30 dias** num S/4 trial (SAP CAL) para os diagnósticos; **sandbox ECC de um cliente piloto** para validar o ECC (ver seção 14.1) | Sem acesso a SAP hoje. Minimiza custo e usa o tempo de sistema real só quando tudo já está preparado |
| D21 | **Requisito: duas versões do produto.** **Cloud** (no nosso servidor, conectando ao SAP do cliente via conector) e **Self-hosted** (a ferramenta inteira hospedada no servidor do cliente). **Um único código e as mesmas imagens Docker**; a diferença é só configuração (seção 4.4) | Atende tanto quem aceita SaaS quanto quem exige que nada saia da rede (grandes empresas, setores regulados) |
| D22 | **Pré-requisito do Self-hosted: VM Linux** fornecida pelo cliente, com Docker Engine. Distribuições suportadas: **Ubuntu Server LTS, RHEL 8/9 (e compatíveis) e SUSE SLES 15**. Windows Server **não é suportado** | Uma plataforma só para testar e suportar. RHEL e SLES já são comuns em ambientes SAP |
| D23 | **Primeiro piloto em Cloud, sem criar dependência de nuvem.** O self-hosted é construído e testado em paralelo desde a Fase 2, com um **teste automático de independência da nuvem** no CI (seção 13) | Entrega mais rápida no piloto sem comprometer a versão self-hosted |
| D20 | **Desenvolvedor solo:** escopo enxuto, serviços gerenciados e nada que não seja essencial antes do piloto (ver seção 14.2) | Uma pessoa só precisa proteger o próprio tempo |

### 3.2 Propostas novas (precisam do seu OK)

| ID | Proposta | Motivo |
|---|---|---|
| P01 | **Desenvolvimento orientado a contrato + simulador SAP** (`services/sap-mock`) | Front, backend e IA evoluem sem depender de um sistema SAP. Também serve para demos e testes automatizados |
| P02 | **Formato padrão de resultado** (*Finding*) compartilhado entre ABAP e TypeScript (seção 5.3) | A IA, a UI e os testes passam a falar a mesma língua. Adicionar um diagnóstico novo não exige mudar o front |
| P03 | **Objeto de autorização próprio `ZRX_DIAG`** + role PFCG modelo | O cliente controla, no próprio SAP, quem pode usar cada diagnóstico |
| ~~P04~~ | *Substituída pela D17 (release mínimo NW 7.00)* | |
| P05 | **Camada de compatibilidade ECC/S/4** no ABAP (leitores de status por release) | As diferenças de modelo de dados (VBUK/VBUP, KONV, MATDOC…) ficam isoladas num só lugar |
| P06 | Backend com **Fastify + Zod**, **Drizzle ORM** (sintaxe próxima ao Open SQL), **PostgreSQL** e **pg-boss** para filas | Stack enxuta. Sem Redis no início |
| P07 | Front com **TanStack Router/Query**, **Tailwind + shadcn/ui** e **i18next** (pt-BR primeiro, inglês depois) | Componentes acessíveis e responsivos. Internacionalização pronta desde o início |
| P08 | **Avaliação contínua da IA (evals)** com um conjunto de cenários de referência | Mede a qualidade objetivamente e permite trocar de modelo ou prompt com segurança |
| P09 | **Proteção contra prompt injection:** dados do SAP sempre tratados como dados, texto livre delimitado e ferramentas somente leitura | Textos de pedidos e notas podem conter instruções maliciosas |
| P10 | **Observabilidade:** OpenTelemetry + Sentry e logs estruturados | Diagnosticar problemas em ambientes de clientes |
| P11 | **Hospedagem em região Brasil**, com tudo em contêineres | Residência de dados (LGPD) e portabilidade para self-hosted |
| P12 | **abaplint no CI** para o código ABAP | Qualidade e padronização do ABAP, verificadas a cada commit |
| P13 | **Nome comercial sem "SAP"**, no formato "Produto *para* SAP" | As diretrizes de marca da SAP restringem o uso da marca em nomes de produtos de terceiros |
| P14 | **Namespace ABAP:** prefixo `ZRX` no MVP. Antes de vender, avaliar um **namespace reservado** (`/XXX/`) junto à SAP | Evita colisão com objetos Z do cliente e transmite profissionalismo |
| P15 | **Feedback 👍/👎** em cada resposta, com comentário opcional | Alimenta melhorias dos diagnósticos e o conjunto de evals |
| ~~P16~~ | *Aceita e detalhada na D19 (ambiente SAP em etapas)* | |
| P17 | **Cliente piloto ("design partner")** desde a Fase 0: uma consultoria AMS com desconto em troca de feedback e acesso a um sandbox ECC | Validação real de mercado e de compatibilidade com ECC |

---

## 4. Arquitetura

### 4.1 Visão geral

```
┌──────────────────── Clientes (mesmo código React + TypeScript) ────────────────────┐
│     Web (PWA)          Windows (Tauri 2)          Android / iOS (Capacitor)          │
└─────────────────────────────────────┬──────────────────────────────────────────────┘
                                      │ HTTPS (REST) + SSE (respostas em streaming)
┌─────────────────────────────────────▼──────────────────────────────────────────────┐
│ Backend Raio-X (SaaS, região Brasil; ou self-hosted)                                │
│  ┌──────────┐ ┌────────────┐ ┌─────────────┐ ┌───────────┐ ┌──────────┐ ┌────────┐ │
│  │ Auth     │ │ Licenças & │ │ Orquestrador│ │ Catálogo  │ │ Auditoria│ │ Admin  │ │
│  │ plugável │ │ uso        │ │ de IA       │ │ ferramentas│ │ & logs   │ │        │ │
│  └──────────┘ └────────────┘ └──────┬──────┘ └─────┬─────┘ └──────────┘ └────────┘ │
│                                     │              │        PostgreSQL · pg-boss    │
│                       Provedor de IA (plugável)    │ SapTransport                   │
│                                                    ├── direct    (self-hosted/dev)  │
│                                                    ├── connector (produção)         │
│                                                    └── mock      (testes / demo)    │
└────────────────────────────────────────────────────┼───────────────────────────────┘
                                                     │ WebSocket TLS de saída,
                                                     │ iniciado pelo conector
┌──────────────────────── Rede do cliente ────────────▼──────────────────────────────┐
│  Conector Raio-X (Docker ou serviço Windows)                                        │
│                       │ HTTPS interno, só caminhos /zrx/api/* liberados              │
│  ┌────────────────────▼───────────────────────────────────────────────────────────┐ │
│  │ SAP ECC / S/4HANA: add-on ABAP ZRX                                              │ │
│  │  Handler REST (ICF) → Roteador → Diagnósticos → Camada de compatibilidade ECC/S4 │ │
│  │  AUTHORITY-CHECK · somente SELECT · log ZRX_LOG · objeto de autorização ZRX_DIAG │ │
│  └────────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Componentes

| Componente | Responsabilidade | Tecnologia |
|---|---|---|
| **apps/web** | Interface única: login, chat, cartões de diagnóstico, histórico e admin | React, Vite, TS, TanStack, Tailwind/shadcn, i18next |
| **apps/desktop** | Empacota `apps/web` para Windows, com auto-update e notificações | Tauri 2 |
| **apps/mobile** | Empacota `apps/web` para Android e iOS, com push, biometria e armazenamento seguro | Capacitor |
| **services/api** | Autenticação, tenants, licenças, orquestração de IA, auditoria, admin e API para os apps | Node, Fastify, Zod, Drizzle, PostgreSQL |
| **services/connector** | Túnel de saída até o backend. Executa chamadas permitidas ao SAP do cliente | Node + TS, Docker / serviço Windows |
| **services/sap-mock** | Simula a API ABAP com cenários fixos (fixtures) | Node + TS |
| **packages/contracts** | Esquemas e tipos compartilhados: Finding, diagnósticos, API | Zod → tipos TS + JSON Schema |
| **packages/sap-tools** | Definição das ferramentas que a IA pode usar, mapeadas para os diagnósticos | TS + Zod |
| **packages/platform** | Abstração de recursos nativos (token, push, biometria) | TS |
| **packages/ui** | Componentes visuais compartilhados | React |
| **abap/** | Add-on ZRX: handler REST, diagnósticos, autorização e logs | ABAP 7.40+, abapGit |

### 4.3 Fluxo de uma pergunta

```
Usuário: "Por que o pedido 4500123 não faturou?"
 1. App → API (POST /chat, SSE)        token de sessão: tenant, usuário, sistema SAP
 2. API verifica licença e franquia de uso
 3. Orquestrador → LLM (pergunta + catálogo de ferramentas)
 4. LLM decide: sd_order_billing_diagnosis({ salesOrder: "4500123" })
 5. API → SapTransport → Conector → SAP (POST /zrx/api/v1/diagnostics/SD-01)
 6. ABAP: AUTHORITY-CHECK (usuário real) → SELECTs → Findings estruturados → log ZRX_LOG
 7. Resultado volta. A API mascara dados pessoais, se configurado, e registra a auditoria
 8. LLM recebe os Findings e redige a resposta: causa, evidências, ação e transação
 9. Resposta em streaming para o app, com cartões clicáveis (documento, transação)
10. Usuário avalia 👍/👎 → feedback registrado
```

**Modo sem IA:** a pessoa escolhe o diagnóstico, informa o número do documento e vê os mesmos cartões. Os passos 3, 4 e 8 não acontecem.

### 4.4 Modos de implantação: Cloud e Self-hosted (requisito, D21)

**Princípio: um único código, dois modos.** As mesmas imagens Docker, na mesma versão, rodam nos dois. A diferença está só na configuração (`DEPLOYMENT_MODE=cloud|selfhosted`).

```
          CLOUD (nosso servidor)                         SELF-HOSTED (servidor do cliente)

 ┌─ Nuvem Raio-X (região Brasil) ─────┐       ┌─ Rede do cliente ──────────────────────────┐
 │ web + api + PostgreSQL             │       │ VM Linux + Docker                           │
 │ gateway de conectores · IA         │       │   web + api + PostgreSQL                    │
 └───────────────▲────────────────────┘       │          │ HTTP(S) interno (sem conector)   │
                 │ WebSocket TLS                │          ▼                                  │
                 │ (conexão de saída)           │   SAP ECC / S/4 (add-on ZRX)                │
 ┌─ Rede do cliente ┴──────────────────┐       └──────────┬──────────────────────────────────┘
 │ Conector ──► SAP ECC/S4 (add-on ZRX) │                  │ saídas opcionais: provedor de IA,
 └─────────────────────────────────────┘                  ▼ licença, push, atualizações
```

#### 4.4.1 Comparação

| Aspecto | Cloud | Self-hosted |
|---|---|---|
| Onde roda | Nossa nuvem (região Brasil) | VM ou servidor do cliente |
| Acesso ao SAP | **Conector** no cliente (conexão de saída) | **Direto** pela rede interna (`SapTransport: direct`), sem conector |
| Tenants | Multi-tenant | Um tenant, criado na instalação |
| Banco de dados | PostgreSQL gerenciado por nós | PostgreSQL incluído no pacote ou do próprio cliente |
| Licença | Assinatura registrada no nosso banco | **Arquivo de licença assinado**, com verificação online opcional (seção 9.4) |
| IA | Nosso provedor, ou a nuvem de IA do cliente | IA na conta do cliente (Azure, AWS, Google), **nosso proxy de IA** (opcional) ou **modelo local** (open source, menor qualidade) |
| Login / SSO | Usuário SAP / OIDC | Igual, com o provedor de identidade do cliente |
| Atualizações | Contínuas, aplicadas por nós | **Versões estáveis** (ex.: trimestrais) aplicadas pelo cliente, com migração automática do banco |
| Backup, TLS e certificados | Nós | Cliente (certificado da empresa) |
| Monitoramento e suporte | Nós (OpenTelemetry/Sentry) | **Pacote de suporte** exportável pelo admin + telemetria opcional (opt-in) |
| Apps desktop e mobile | Apontam para a nossa URL | Apontam para a URL do cliente (código da empresa, QR code ou MDM). Acesso de fora da rede depende de VPN ou proxy do cliente |
| Notificações push | Diretas | Via **relay** nosso (só "você tem uma notificação", sem dados de negócio) ou desligadas |
| Comercial | Assinatura | Licença + manutenção anual (normalmente mais cara), instalação como serviço |

#### 4.4.2 Regras de engenharia para manter os dois modos

1. **Nenhum recurso depende só da nossa nuvem.** Tudo que usa um serviço nosso (relay de push, verificação de licença, descoberta de servidor, proxy de IA) é opcional e tem alternativa.
2. **Configuração única** por variáveis de ambiente ou arquivo, validada na inicialização (Zod).
3. **Sem serviços proprietários de nuvem no núcleo** (filas, storage ou bancos específicos). Fila no PostgreSQL (pg-boss). O que precisar ser específico fica atrás de uma interface.
4. **Mesma imagem Docker nos dois modos.** O ambiente local de desenvolvimento usa o **mesmo docker-compose** do self-hosted, então ele é testado todo dia.
5. **CI roda os testes ponta a ponta nos dois modos.**
6. **Compatibilidade de versões:** o backend aceita o add-on ABAP da versão atual e da anterior (N-1). O `health` informa a versão, e a matriz de compatibilidade é publicada.
7. **Migrações de banco** automáticas, só para frente, testadas a partir da versão anterior.
8. **Logs sem dados de negócio** por padrão, o que facilita o suporte e a LGPD.

#### 4.4.3 Pacote Self-hosted

- **Pré-requisito (D22): VM Linux fornecida pelo cliente.** Sem ela, a opção é a versão Cloud. Isso deve constar na proposta comercial.
  - Sistema operacional: Ubuntu Server LTS, RHEL 8/9 (ou compatíveis) ou SUSE SLES 15
  - Dimensionamento inicial *(validar no piloto)*: 4 vCPU, 8 GB de RAM, 50 GB de disco
  - Docker Engine + Docker Compose (Podman: melhor esforço, avaliar depois)
  - Rede: acesso HTTP(S) da VM ao SAP (porta do ICF) e dos usuários à VM (porta 443). Saída para a internet **opcional** (IA, licença, atualizações)
- **Checklist de pré-instalação** para a TI do cliente: VM, sistema operacional, Docker, DNS interno, certificado TLS, regras de firewall, usuário SAP técnico ou configuração de SSO e o add-on ABAP importado.
- **Conteúdo:** imagens (`api` com a `web` embutida, `postgres` opcional), `docker-compose.yml`, `.env` modelo, script de instalação e atualização, guia de instalação, checklist de rede e firewall, arquivo de licença.
- **Assistente de primeira instalação** no navegador: licença → banco → sistema SAP → IA → SSO → primeiro administrador.
- **Distribuição das imagens:** registry privado nosso, com credencial vinculada à licença. Para ambientes **sem internet**, um pacote offline assinado (`docker save`).
- **Depois:** Helm chart (Kubernetes) e, se pedirem, appliance (OVA). Windows Server não é suportado (D22).

#### 4.4.4 Variante: Cloud com IA do cliente

Na versão Cloud, o cliente pode exigir que o LLM rode na conta dele (Azure, AWS Bedrock, Google Vertex). O backend usa as credenciais do cliente para aquele tenant.

### 4.5 Compatibilidade com sistemas SAP

| Sistema | Suporte | Como |
|---|---|---|
| ECC 6.0, qualquer EHP (NW 7.00 a 7.50) | ✅ MVP | Add-on ABAP com sintaxe 7.00 + conector (seção 5.5) |
| S/4HANA on-premise / Private Cloud | ✅ MVP | O mesmo add-on (código 7.00 roda em releases superiores) + camada de compatibilidade |
| S/4HANA Public Cloud | 🔜 Fase 6 | Somente APIs liberadas (OData) ou extensão ABAP Cloud |

---

## 5. Add-on ABAP

### 5.1 Estrutura de objetos (pacote `ZRX`)

| Subpacote | Objetos principais | Papel |
|---|---|---|
| `ZRX_CORE` | `ZCL_RX_HTTP_HANDLER` (implementa `IF_HTTP_EXTENSION`), `ZCL_RX_ROUTER`, `ZCL_RX_JSON` (serializador próprio via RTTI, compatível com 7.00) | Recebe a requisição, roteia, gera o JSON da resposta e trata erros |
| `ZRX_CORE` | `ZIF_RX_DIAGNOSTIC`, `ZCL_RX_DIAGNOSTIC_REGISTRY` | Interface comum dos diagnósticos e registro dos disponíveis |
| `ZRX_CORE` | `ZCL_RX_RELEASE_INFO` | Detecta ECC ou S/4 (por exemplo, componente `S4CORE` na `CVERS`) e a versão |
| `ZRX_SEC` | Objeto de autorização `ZRX_DIAG` (campos `ZRX_DIAGID`, `ACTVT`), `ZCL_RX_AUTH`, role modelo `ZRX_USER` | Quem pode usar qual diagnóstico + verificações de autorização standard |
| `ZRX_LOG` | Tabela `ZRX_LOG`, `ZCL_RX_LOGGER` | Registro de cada execução: usuário, diagnóstico, parâmetros e duração |
| `ZRX_CFG` | Tabelas `ZRX_CONFIG` e `ZRX_PP_STATUS_MAP` + visões de manutenção | Diagnósticos habilitados, limites, mascaramento, tolerância de atraso e mapeamento de status de usuário (ex.: "Aprovada") |
| `ZRX_COMPAT` | `ZIF_RX_SD_STATUS`, `ZCL_RX_SD_STATUS_ECC`, `ZCL_RX_SD_STATUS_S4`… | Isola as diferenças de modelo de dados entre ECC e S/4 |
| `ZRX_PP_CORE` | `ZCL_RX_PP_ORDER_READER` (status, datas, quantidades, operações, componentes), `ZCL_RX_PP_STATUS_MAP` | Base compartilhada por PP-01, PP-03 e PP-04 |
| `ZRX_DIAG_SD` | `ZCL_RX_DIAG_SD01` … | Diagnósticos de SD |
| `ZRX_DIAG_MM` | `ZCL_RX_DIAG_MM01` … | Diagnósticos de MM |
| `ZRX_DIAG_PP` | `ZCL_RX_DIAG_PP01` … | Diagnósticos de PP |
| `ZRX_DIAG_GE` | `ZCL_RX_DIAG_GE01` | IDoc e outros diagnósticos gerais |

```abap
INTERFACE zif_rx_diagnostic PUBLIC.
  METHODS get_metadata
    RETURNING VALUE(rs_meta) TYPE zrx_s_diag_meta.     " id, versão, parâmetros
  METHODS execute
    IMPORTING it_params        TYPE zrx_t_param
    RETURNING VALUE(rs_result) TYPE zrx_s_diag_result " status + findings
    RAISING   zcx_rx_error.
ENDINTERFACE.
```

### 5.2 Endpoints REST (nó ICF `/sap/bc/zrx/api`)

| Método | Caminho | Descrição |
|---|---|---|
| GET | `/v1/health` | Versão do add-on, release SAP (ECC/S4), diagnósticos habilitados |
| GET | `/v1/me` | Valida a credencial e devolve o usuário SAP, o idioma e os diagnósticos permitidos |
| GET | `/v1/diagnostics` | Catálogo de diagnósticos (metadados e parâmetros) |
| POST | `/v1/diagnostics/{id}` | Executa um diagnóstico ou consulta. Parâmetros planos (form ou query string). Resposta: resultado padrão |

Dois tipos de serviço usam o mesmo endpoint:
- **Diagnóstico de objeto:** um documento ("por que a ordem X não liberou?"). Ex.: SD-01, PP-01, PP-03.
- **Consulta de lista:** vários objetos com filtros ("ordens atrasadas do centro 1000"). Ex.: PP-04. Sempre paginada, com limite máximo de linhas.

Regras: somente `SELECT`, nenhum `COMMIT WORK`, limite de linhas por consulta, timeout, `AUTHORITY-CHECK` antes de qualquer leitura e log de cada execução.

### 5.3 Contrato do resultado (Finding)

```json
{
  "diagnosticId": "SD-01",
  "version": "1.0",
  "object": { "type": "SALES_ORDER", "id": "0004500123" },
  "system": { "sid": "PRD", "client": "300", "release": "ECC" },
  "status": "PROBLEM_FOUND",
  "findings": [
    {
      "code": "SD01.CREDIT_BLOCK",
      "severity": "BLOCKING",
      "title": "Pedido bloqueado por crédito",
      "detail": "Verificação de crédito não aprovada para o cliente 100234.",
      "evidence": [
        { "source": "VBUK", "field": "CMGST", "value": "B", "label": "Status de crédito" }
      ],
      "suggestedAction": {
        "tcode": "VKM3",
        "description": "Solicitar a liberação ao responsável de crédito"
      }
    }
  ],
  "related": [{ "type": "DELIVERY", "id": "0080001234" }],
  "executedAt": "2026-10-09T14:32:10Z",
  "durationMs": 184
}
```

Para consultas (PP-03, PP-04), o mesmo contrato ganha dois blocos opcionais:

```json
{
  "facts": [
    { "key": "progress", "label": "Quantidade confirmada", "value": "600 de 1.000 PC (60%)" },
    { "key": "delay",    "label": "Atraso no fim",         "value": "3 dias" }
  ],
  "tables": [
    {
      "id": "operations",
      "title": "Operações",
      "columns": ["Operação", "Centro de trabalho", "Status", "Fim programado", "Confirmado"],
      "rows": [["0010", "MONT01", "CONF", "2026-10-06", "1000"],
               ["0020", "PINT02", "CONF.P", "2026-10-08", "600"]],
      "truncated": false
    }
  ]
}
```

- `status`: `OK` | `PROBLEM_FOUND` | `NOT_FOUND` | `NOT_AUTHORIZED` | `ERROR`
- `severity`: `BLOCKING` | `WARNING` | `INFO`
- A UI desenha os cartões a partir desse contrato, e a IA recebe exatamente esse JSON.

### 5.4 Diferenças ECC × S/4 isoladas na camada de compatibilidade

| Tema | ECC | S/4HANA |
|---|---|---|
| Status de documentos SD | `VBUK` / `VBUP` | Campos de status em `VBAK`/`VBAP`, `LIKP`/`LIPS`, `VBRK` (VBUK/VBUP não são mais preenchidas) |
| Condições de preço | `KONV` | `PRCD_ELEMENTS` |
| Documentos de material | `MKPF` / `MSEG` | `MATDOC` (MKPF/MSEG como visões de compatibilidade) |
| Gestão de crédito | SD clássico (`VKM1`/`VKM3`) | SAP Credit Management / FSCM (`UKM_*`) |
| Cliente e fornecedor | `KNA1` / `LFA1` | Business Partner (KNA1/LFA1 continuam existindo) |
| Material | `MATNR` com 18 posições | `MATNR` com até 40 posições |
| MRP | Lista MRP persistida (`MDKP`/`MDTB`) | MRP Live (lista nem sempre persistida). Usar `BAPI_MATERIAL_STOCK_REQ_LIST` |

### 5.5 Compatibilidade com NetWeaver 7.00 (D17)

**Qual release de NetWeaver cada ECC usa:**

| ECC 6.0 | EHP0–3 | EHP4 | EHP5 | EHP6 | EHP7 | EHP8 |
|---|---|---|---|---|---|---|
| NetWeaver | 7.00 | 7.01 | 7.02 | 7.03 / 7.31 | 7.40 | 7.50 |

**Regras de código:**

| ❌ Proibido (7.02+ / 7.40+) | ✅ Usar no lugar |
|---|---|
| Declaração inline `DATA(...)`, `FIELD-SYMBOL(...)` | `DATA` / `FIELD-SYMBOLS` declarados no início |
| `VALUE #( )`, `NEW #( )`, `CONV`, `COND`, `SWITCH`, `REDUCE`, `FOR` | `CREATE OBJECT`, `APPEND`, `IF`/`CASE` clássicos |
| Expressões de tabela `itab[ ... ]` | `READ TABLE ... INTO / ASSIGNING` |
| String templates `\|...\|` e `boolc( )` | `CONCATENATE`, `WRITE ... TO` |
| Open SQL novo (`@var`, campos separados por vírgula, `CASE` em SELECT) | `SELECT` clássico, `FOR ALL ENTRIES` |
| CDS, AMDP, RAP | Classes ABAP e SELECTs |
| `/UI2/CL_JSON` e JSON nativo (sXML) *(depende do release/SP)* | `ZCL_RX_JSON` próprio (RTTI) |

**Garantia automática:** o abaplint com `"version": "v700"` reprova no CI qualquer sintaxe mais nova. Assim dá para desenvolver num sistema de release superior (o Trial é 7.5x) sem quebrar a compatibilidade.

**Outros pontos:**
- **Entrada simples:** os parâmetros chegam como form ou query string (`server->request->get_form_field`), sem precisar de um parser JSON no ABAP. JSON só na saída.
- **Unicode:** ECCs antigos podem ser **não-Unicode**. É preciso testar acentuação e garantir a resposta em UTF-8.
- **TLS:** kernels antigos podem não suportar TLS 1.2. Dentro da rede do cliente, o conector pode falar HTTP com o SAP, se a política permitir. O trecho externo (conector ↔ nuvem) é sempre TLS.
- **abapGit** exige 7.02 ou superior *(validar)*. No desenvolvimento e na entrega para 7.02+, usar abapGit. Para 7.00/7.01, entregar por **ordem de transporte**, tratando caso a caso.
- **Dicionário (DDIC):** tabelas e tipos Z simples, sem recursos novos, para que o transporte funcione em releases antigos.
- **Testes:** ABAP Unit existe desde a 6.40, mas o *test double* de SQL só existe a partir da 7.51. Por isso os leitores de dados são **interfaces injetáveis**, com dublês manuais nos testes.
- **Funções standard:** confirmar que cada BAPI ou módulo usado existe na 7.00 (ex.: `STATUS_READ`, `BAPI_MATERIAL_AVAILABILITY`, `AUTHORITY_CHECK`).

---

## 6. Backend

### 6.1 Módulos (`services/api`)

| Módulo | Responsabilidade |
|---|---|
| `auth` | Provedores plugáveis (`sap-basic`, `oidc`, depois `principal-propagation`), sessão e refresh |
| `tenants` | Clientes, sistemas SAP (SID/mandante) e conectores |
| `licensing` | Licenças, atribuição, franquias, verificação no login e por requisição |
| `chat` | Conversas, mensagens e streaming (SSE) |
| `agent` | Laço de orquestração da IA (seção 7) |
| `tools` | Registro das ferramentas (`packages/sap-tools`) e validação de parâmetros |
| `sap-transport` | Interface `SapTransport` com implementações `direct` (self-hosted e dev), `connector` (cloud) e `mock` (testes e demo) |
| `deployment` | Leitura e validação da configuração por modo (`cloud` / `selfhosted`), assistente de instalação e pacote de suporte |
| `connector-gateway` | WebSocket dos conectores: autenticação, heartbeat e versão |
| `privacy` | Mascaramento de dados pessoais e política de retenção |
| `audit` | Trilha de auditoria (quem, o quê, quando, quais dados) |
| `usage` | Contadores de uso e tokens por tenant e por usuário |
| `admin` | API do painel do administrador do cliente |

### 6.2 Modelo de dados principal

```
tenants            (id, nome, plano, status, configuracoes_ia, retencao_dias)
subscriptions      (tenant_id, licencas_contratadas, franquia_ia_mensal, inicio, fim)
sap_systems        (id, tenant_id, sid, mandante, tipo[PRD|QAS|DEV], release, connector_id)
connectors         (id, tenant_id, nome, versao, ultimo_heartbeat, chave_publica)
users              (id, tenant_id, email, nome, papel[USER|ADMIN])
sap_user_links     (user_id, sap_system_id, sap_username)
seats              (tenant_id, user_id, status, atribuida_em, liberavel_em)
sessions           (id, user_id, sap_system_id, dispositivo, expira_em)
conversations      (id, user_id, sap_system_id, criada_em)
messages           (id, conversation_id, papel, conteudo, tokens_in, tokens_out)
tool_calls         (id, message_id, diagnostico, parametros, status, duracao_ms)
feedback           (message_id, nota, comentario)
usage_monthly      (tenant_id, user_id, mes, perguntas, diagnosticos, tokens)
audit_log          (id, tenant_id, user_id, acao, objeto, detalhes, ip, criado_em)
```

---

## 7. Inteligência artificial

### 7.1 Papel da IA
- **Entender** a pergunta: qual objeto, qual documento, qual dúvida.
- **Escolher e executar** um ou mais diagnósticos (tool calling).
- **Explicar** o resultado em linguagem simples, no idioma do usuário.
- **Não** decide a causa sozinha: a causa vem dos Findings do ABAP.

### 7.2 Laço do agente
1. Monta o contexto: prompt de sistema, catálogo de ferramentas permitidas ao usuário e histórico curto.
2. O LLM pede ferramentas. O backend valida os parâmetros (Zod) e executa via `SapTransport`.
3. Limites: **no máximo 6 chamadas de ferramenta por pergunta**, timeout total e orçamento de tokens.
4. A resposta final segue o formato: **Resumo → Causa → Evidências → O que fazer (transação)**.

### 7.3 Guardrails
- Responder **somente com base nas evidências** das ferramentas. Sem evidência, a resposta é "não encontrei".
- Sempre citar o documento e a fonte (tabela/campo ou transação).
- Dados do SAP vão como **dados delimitados**, nunca como instruções (proteção contra prompt injection, P09).
- Nenhuma ferramenta escreve no SAP, por construção.
- Mascaramento configurável de dados pessoais (CPF/CNPJ de pessoa física, nomes, endereços, e-mails) antes do envio ao LLM.

### 7.4 Escolha do provedor (pendência Q3)
Interface `LlmProvider` única. Critérios para escolher o padrão:
1. Qualidade de *tool calling* e de português, medida pelos **evals** (7.6).
2. Disponibilidade nas nuvens dos clientes (Azure, AWS Bedrock, Google Vertex) e em região Brasil.
3. Termos de dados: sem treino com dados do cliente e retenção mínima.
4. Custo por pergunta.

Sugestão: comparar **dois provedores** com o mesmo conjunto de evals antes de fixar o padrão.

### 7.5 Controle de custos
- Franquia mensal por usuário e tenant, com alertas em 80% e 100%.
- Cache de prompt (prompt de sistema e catálogo de ferramentas).
- Roteamento por complexidade: modelo menor para perguntas simples, quando os evals permitirem.
- Painel de custo por tenant no admin interno.

### 7.6 Evals (qualidade mensurável)
- Conjunto de **cenários de referência**: pergunta + Findings simulados + o que a resposta deve conter.
- Métricas: causa correta, transação correta, ausência de invenção (alucinação) e idioma.
- Rodam no CI (contra o `sap-mock`) a cada mudança de prompt, modelo ou ferramenta.
- Cresce com os casos reais marcados com 👎 (depois de anonimizados).

---

## 8. Autenticação e identidade

### 8.1 Fases

| Fase | Mecanismo | Identidade no SAP |
|---|---|---|
| MVP / Trial | **Usuário e senha SAP** (Basic Auth no ICF via `GET /v1/me`), sem armazenar a senha. Reaproveita a sessão SAP (cookie de sessão / `MYSAPSSO2`, se o sistema estiver configurado) | Usuário real |
| Primeiros clientes | **SSO corporativo (OIDC: Entra ID etc.)** + **usuário técnico** no conector. O ABAP verifica as autorizações do usuário final (`AUTHORITY_CHECK` com parâmetro `USER`) | Usuário técnico nos logs SAP + usuário real no `ZRX_LOG` |
| Produto maduro | **SSO + principal propagation** (certificado X.509 de curta duração mapeado no SAP) | Usuário real |
| S/4 Public Cloud | **SAP IAS** (OIDC/OAuth) | Usuário real |
| Alternativa | **OAuth 2.0 do AS ABAP** (`SOAUTH2`) | Usuário real |

### 8.2 Tela de login (MVP)
`Empresa (código do tenant)` → `Sistema SAP (ex.: PRD/300)` → `Usuário SAP` → `Senha`

### 8.3 Sessão
- O backend emite um **token de acesso curto** (15 min) e um **refresh token**: cookie httpOnly na web, armazenamento seguro do sistema no mobile e no desktop.
- O token carrega `tenant`, `user`, `sapSystem`, `plano` e `recursos`.
- Limite de **dispositivos ativos por licença** (ex.: 3), visível e revogável pelo usuário e pelo admin.

---

## 9. Licenciamento e cobrança

### 9.1 Modelo
- **Usuário nomeado** com **franquia mensal de IA** por usuário, mais pacotes adicionais.
- A licença é da **pessoa**, não do sistema. Os usuários SAP de DEV, QAS e PRD são ligados pelo e-mail.
- **Sistemas não produtivos não consomem licença** (política sugerida).
- Planos alternativos para avaliar: **por sistema SAP** (empresas médias) e **por consultor** (consultorias AMS).

### 9.2 Verificação no login
```
SAP valida a credencial ─► backend identifica o tenant e o sistema ─► usuário tem licença?
   ├─ Sim ............................................. libera
   ├─ Não, há licenças livres ......................... atribui (automático ou com aprovação do admin)
   └─ Não, cota esgotada .............................. bloqueia com mensagem clara
```

### 9.3 Regras
- Uma licença só pode trocar de pessoa a cada **30 dias** (evita rodízio).
- Franquia de IA esgotada: o modo diagnóstico direto continua funcionando, só a conversa com IA é bloqueada.
- Relatório mensal de uso para o cliente e para o faturamento.

### 9.4 Self-hosted
- **Arquivo de licença assinado** (Ed25519): tenant, licenças, validade, recursos e franquia.
- Verificação online opcional, com **tolerância offline** (ex.: 15 dias).
- Contrato com **cláusula de auditoria** e envio de relatório de uso.

### 9.5 Cobrança
- Início: **contrato anual**, nota fiscal de serviço (NFS-e) e boleto ou transferência.
- Cobrança automática (Stripe, Asaas, Iugu…) só se surgirem planos de autoatendimento.

---

## 10. Segurança, privacidade e compliance

**No SAP**
- [ ] Somente leitura (sem `COMMIT`, `UPDATE`, `INSERT`, `MODIFY` ou `DELETE` em tabelas de negócio). Verificado por abaplint e revisão
- [ ] `AUTHORITY-CHECK` standard por diagnóstico + objeto `ZRX_DIAG`
- [ ] Log de execução em `ZRX_LOG`
- [ ] Limite de linhas e timeout por diagnóstico

**No conector**
- [ ] Apenas conexão de saída (WebSocket TLS)
- [ ] Lista branca de caminhos (`/sap/bc/zrx/api/*`)
- [ ] Registro com token de uso único → par de chaves por conector
- [ ] Atualização assinada

**No backend**
- [ ] Isolamento por tenant em todas as consultas (testado)
- [ ] Criptografia em trânsito (TLS) e em repouso (banco e backups)
- [ ] Segredos em cofre (nunca no repositório)
- [ ] Auditoria completa e exportável
- [ ] Rate limiting por usuário e por tenant
- [ ] Mascaramento de dados pessoais configurável
- [ ] Retenção de conversas configurável (padrão sugerido: 90 dias) e exclusão a pedido (LGPD)

**Documentação comercial (antes do primeiro contrato)**
- [ ] Termos de uso e contrato SaaS
- [ ] DPA (acordo de tratamento de dados, LGPD)
- [ ] Política de privacidade e de segurança
- [ ] Respostas-padrão para questionário de segurança
- [ ] Futuro: ISO 27001 / SOC 2, quando os clientes grandes exigirem

---

## 11. Multiplataforma

| Plataforma | Empacotamento | Recursos nativos | Distribuição |
|---|---|---|---|
| Web | PWA (instalável) | Web Push, cookie seguro | Nossa URL (cloud) ou a URL interna do cliente (self-hosted) |
| Windows | Tauri 2 | Notificações do Windows, cofre de credenciais, auto-update | Instalador MSI/EXE assinado e Microsoft Store (opcional) |
| Android | Capacitor | Push (FCM), biometria, Keystore | Google Play e MDM corporativo (Intune etc.) |
| iOS | Capacitor | Push (APNs), Face ID/Touch ID, Keychain | App Store e distribuição privada (Apple Business Manager / MDM) |

- **Endereço do servidor:** no primeiro acesso, o app pede o código da empresa (resolvido para a URL certa), lê um QR code ou recebe a configuração via MDM. Assim, o mesmo app das lojas atende Cloud e Self-hosted.
- `packages/platform` expõe uma API única (`saveToken`, `notify`, `authenticateBiometric`…) com uma implementação por plataforma.
- **Atenção à App Store (diretriz 4.2):** o app precisa ter recursos nativos reais (push, biometria) para não ser rejeitado como "site empacotado".
- **Build iOS** exige macOS: Mac próprio ou CI com runners macOS. É preciso conta Apple Developer (anual) e conta Google Play (taxa única).
- **Assinatura de código no Windows** (certificado) evita alertas do SmartScreen.

---

## 12. Estrutura do repositório

```
sap_project/
├── apps/
│   ├── web/                 # React + Vite (PWA): a UI única
│   ├── desktop/             # Tauri 2: empacota apps/web para Windows
│   └── mobile/              # Capacitor: empacota apps/web para Android/iOS
├── services/
│   ├── api/                 # Backend: auth, licenças, IA, auditoria, admin
│   ├── connector/           # Agente on-premise: túnel de saída até o SAP
│   └── sap-mock/            # Simulador da API ABAP (fixtures por cenário)
├── packages/
│   ├── contracts/           # Esquemas Zod: Finding, diagnósticos, API
│   ├── sap-tools/           # Ferramentas da IA ↔ diagnósticos
│   ├── platform/            # Abstração de recursos nativos
│   └── ui/                  # Componentes compartilhados
├── abap/
│   └── src/                 # Add-on ZRX (formato abapGit)
├── evals/                   # Cenários de referência e runner de avaliação da IA
├── infra/
│   ├── docker/              # Dockerfiles (as mesmas imagens nos dois modos)
│   ├── selfhosted/          # docker-compose, .env modelo, install/update, guia
│   └── cloud/               # Infra da nossa nuvem (IaC)
├── docs/                    # Este documento, catálogo, decisões
├── .github/workflows/       # CI
├── pnpm-workspace.yaml
└── turbo.json
```

---

## 13. Qualidade, testes e CI/CD

| Camada | Ferramenta | O que testa |
|---|---|---|
| ABAP | **ABAP Unit** com injeção de dependência (leitores de dados simulados) | Lógica de cada diagnóstico, sem depender de dados reais |
| ABAP | **abaplint** (CI, `version: v700`) | Sintaxe, padrões, regra de somente leitura e compatibilidade com NW 7.00 |
| Contratos | Zod + testes de contrato | ABAP, mock e backend falam o mesmo JSON |
| Backend | Vitest + banco de teste | Regras de licença, isolamento de tenant, laço do agente |
| Front | Vitest + Testing Library | Componentes e cartões de diagnóstico |
| Ponta a ponta | Playwright, contra o `sap-mock`, **nos dois modos** (cloud + conector, self-hosted direto) | Login → pergunta → resposta |
| Instalação | Script de teste do pacote self-hosted (instalação limpa + atualização da versão anterior) nas distribuições suportadas (Ubuntu, RHEL, SLES) | O pacote instala, migra e sobe |
| **Independência da nuvem** (D23) | Sobe o pacote self-hosted **com a saída para a internet bloqueada** (só o `sap-mock` e um provedor de IA simulado na rede) e roda o fluxo ponta a ponta | Nenhum recurso depende da nossa nuvem. Se este teste quebrar, o PR não entra |
| IA | `evals/` | Qualidade das respostas (seção 7.6) |

**CI (GitHub Actions):** lint, typecheck, testes, abaplint, evals (quando prompt ou ferramentas mudarem) e build das imagens Docker.

**Ambientes:** `local` (mock ou SAP Trial) → `staging` (com SAP de teste) → `produção`.

---

## 14. Plano de implementação

> As estimativas consideram **1 pessoa em dedicação integral** (D20). Com cerca de 20 h/semana, multiplique por ~2.

### 14.1 Estratégia de ambiente SAP (D19)

Hoje não há um SAP com SD, MM e PP disponível. O plano é usar cada tipo de ambiente no momento certo:

| Etapa | Ambiente | Custo | Para quê |
|---|---|---|---|
| **1. Agora** | **`sap-mock`** (simulador próprio) | Grátis | Front, backend, IA, evals e demos. Cerca de 70% do produto não depende do SAP |
| **1. Agora** | **SAP ABAP Platform Trial** (imagem Docker) | Grátis (precisa de uma máquina com bastante RAM e disco) | Framework ABAP: handler REST, JSON, autorização, log, ABAP Unit com dublês. **Não tem SD/MM/PP** |
| **2. Sprint de 30 dias** | **S/4HANA Fully-Activated Appliance** via **SAP Cloud Appliance Library (CAL)**, com licença de avaliação | Licença trial sem custo + **custo da nuvem** (AWS, Azure ou GCP) por hora ligada | Implementar e validar os leitores reais de SD/MM/PP com dados de exemplo. **Desligar quando não estiver usando** |
| **3. Piloto** | **Sandbox ECC do cliente piloto**, com autorização formal (contrato/NDA) | Licença do produto como contrapartida | Validar o ECC real, releases antigos e customizações |
| **4. Com receita** | **Programa de parceiros SAP** (pacotes de licença de teste e demo) | Anuidade | Ambiente próprio permanente para desenvolvimento e demos |

**Como aproveitar bem os 30 dias do CAL:**
1. Antes de ligar: catálogo de diagnósticos fechado, framework ABAP pronto no Trial, dublês e testes escritos, cenários definidos.
2. Primeira semana: criar os documentos de teste de cada cenário (pedido bloqueado por crédito, fatura com divergência de preço, ordem com falta de material, ordem atrasada…).
3. Semanas 2 a 4: implementar os leitores reais, comparar com o `sap-mock` e **gravar os resultados reais como fixtures** do mock e dos evals.
4. Usar o abaplint (v700) o tempo todo, porque o CAL roda um release bem mais novo que o ECC antigo.

**Evitar:** "acessos SAP para estudo" vendidos na internet sem licença comprovada, e o sistema do empregador ou dos clientes dele sem autorização formal. Isso traz risco jurídico e de propriedade intelectual para o produto.

> Confira as condições atuais do CAL (duração do trial, appliances disponíveis, tamanho e custo das máquinas) antes de iniciar. Elas mudam com frequência.

### 14.2 Trabalhando sozinho (D20)

- **Fazer agora:** contratos, mock, framework ABAP, backend + IA e web. É o caminho até a demo.
- **Adiar até ter piloto:** conector on-premise (no início, `direct` via VPN ou rede do piloto), SSO, multi-tenant completo e apps de lojas.
- **Infra gerenciada:** banco PostgreSQL gerenciado e contêineres em PaaS. Nada de Kubernetes antes de clientes self-hosted.
- **Ritmo:** entregas pequenas com demo ao fim de cada fase. As fases que dependem de SAP real (2, no CAL) ficam agrupadas para não pagar nuvem à toa.
- **Assistentes de código com IA** aceleram bastante o front e o backend. O ABAP com conhecimento funcional continua sendo o seu diferencial.

### Fase 0: Fundação e validação (1 a 2 semanas)
**Objetivo:** ambiente pronto e hipótese de mercado testada.
- Monorepo (pnpm + Turborepo), CI básico, abapGit, abaplint
- `packages/contracts` com o esquema do Finding
- `services/sap-mock` com os cenários dos diagnósticos do MVP (SD-01, MM-02, PP-01, PP-03, PP-04)
- SAP ABAP Platform Trial rodando (framework técnico)
- Orçar o sprint no CAL e escolher a nuvem (14.1)
- **Trilha de negócio:** 5 conversas com gestores de AMS e key users. Buscar 1 cliente piloto (P17)

**Pronto quando:** `pnpm dev` sobe a web e o mock, e há pelo menos 1 piloto interessado ou um aprendizado claro das entrevistas.

### Fase 1a: Framework ABAP no Trial (2 a 3 semanas)
- Handler REST, roteador, `ZCL_RX_JSON` (sintaxe 7.00), tratamento de erros (`ZRX_CORE`)
- `health`, `me` e `diagnostics`
- Objeto de autorização `ZRX_DIAG`, log `ZRX_LOG` e configuração `ZRX_CONFIG`
- Interfaces dos leitores de dados (SD, MM, PP) e lógica dos diagnósticos **contra dublês**, com ABAP Unit
- abaplint v700 no CI

**Pronto quando:** os diagnósticos rodam no Trial com dados simulados, devolvendo o mesmo JSON do `sap-mock`.

### Fase 1b: Sprint no S/4 (CAL) (3 a 4 semanas, dentro dos 30 dias)
- Leitores reais (ECC e S/4 na camada de compatibilidade; o lado ECC é validado depois, no piloto)
- **Diagnósticos do MVP (D18):** `SD-01` Pedido não faturado, `MM-02` Fatura bloqueada, `PP-01` Ordem não liberada / falta de componentes, `PP-03` Situação da ordem, `PP-04` Ordens atrasadas / lista por situação
- Cenários reais criados no sistema e gravados como fixtures

**Pronto quando:** cada diagnóstico retorna o resultado correto em pelo menos 5 cenários reais, via Postman/curl.

### Fase 2: Backend + IA (3 a 4 semanas)
- API (Fastify), PostgreSQL (Drizzle), auth `sap-basic`, sessão
- `SapTransport` (`direct` + `mock`)
- Configuração por modo (`DEPLOYMENT_MODE`) e **docker-compose** usado no desenvolvimento, que já é a base do self-hosted
- `packages/sap-tools` + laço do agente + streaming SSE
- Auditoria, mascaramento básico e contadores de uso
- Avaliação de 2 provedores de IA com os primeiros evals

**Pronto quando:** uma pergunta em linguagem natural gera a resposta correta, com fonte, nos cenários de referência (≥ 90% nos evals).

### Fase 3: Web MVP (2 a 3 semanas)
- Login, chat com streaming, cartões de Findings, modo sem IA, histórico, 👍/👎
- Admin mínimo: usuários e licenças, sistemas SAP, uso
- i18n (pt-BR), tema claro e escuro, layout responsivo

**Pronto quando:** demo completa no navegador e no celular (PWA). **Esta é a versão para mostrar a clientes.**

> **Marco:** MVP demonstrável em cerca de **12 a 17 semanas** de dedicação integral (de 6 a 8 meses com 20 h/semana). As Fases 2 e 3 podem andar antes da 1b, usando o `sap-mock`.

### Fase 4: Piloto (5 a 7 semanas)
- **Cloud (piloto, D23):** `services/connector` (Docker + serviço Windows), gateway de conectores, implantação na nossa nuvem
- **Self-hosted v1 (em paralelo):** pacote (compose, instalador/atualizador, assistente de instalação), licença por arquivo assinado, pacote de suporte, testado nas 3 distribuições. Ao fim da fase, o self-hosted fica pronto para o segundo cliente, mesmo que o piloto rode em Cloud
- Multi-tenant completo, licenciamento (atribuição, franquias, bloqueios)
- SSO (OIDC) + usuário técnico. Observabilidade (OpenTelemetry/Sentry)
- Novos diagnósticos: `SD-02`, `MM-01`, `GE-01`
- Documentação comercial (seção 10), instalação no piloto e acompanhamento semanal

**Pronto quando:** o piloto usa o produto em produção por 30 dias, com métricas de uso e de tempo economizado.

### Fase 5: Multiplataforma (3 a 4 semanas)
- Tauri (Windows): instalador assinado, auto-update e notificações
- Capacitor (Android/iOS): push, biometria, armazenamento seguro
- Publicação nas lojas e/ou distribuição via MDM

### Fase 6: Escala (contínua)
- Principal propagation (X.509), OAuth `SOAUTH2`
- S/4HANA Public Cloud via APIs liberadas + SAP IAS
- Diagnósticos `SD-03` (preço) e `PP-02` (MRP), e novos a partir do feedback
- Servidor **MCP** com as ferramentas (integração com assistentes de mercado)
- Self-hosted avançado: Helm chart (Kubernetes), pacote offline assinado, appliance (OVA) se pedirem
- Relay de push e proxy de IA opcionais para clientes self-hosted
- Leitura genérica controlada (lista branca de tabelas e campos)
- Namespace reservado e avaliação do programa de parceiros SAP

### Trilha de negócio (em paralelo)
| Quando | Ação |
|---|---|
| Fase 0 | Entrevistas de validação. Cliente piloto |
| Fase 0–1 | Verificar o contrato de trabalho atual (propriedade intelectual, exclusividade) |
| Fase 2 | Definir o nome comercial (sem "SAP") e registrar domínio e marca |
| Fase 3 | Abrir empresa (CNPJ), se ainda não tiver. Tabela de preços inicial |
| Fase 4 | Contratos (termos, DPA) revisados por advogado |
| Fase 5–6 | Avaliar o programa de parceiros SAP e a certificação de integração |

---

## 15. Riscos e mitigações

| ID | Risco | Impacto | Mitigação |
|---|---|---|---|
| R01 | **Sem acesso a um SAP com SD/MM/PP.** O ABAP Platform Trial só traz a plataforma técnica | Alto | Estratégia em etapas (14.1): mock + Trial, sprint de 30 dias no CAL, sandbox do piloto e, depois, programa de parceiros |
| R02 | SAP lança um recurso equivalente (Joule) para ECC/on-premise | Médio | Foco em ECC, profundidade de diagnóstico, funcionamento sem IA e independência de licença de IA da SAP |
| R03 | Questões de licenciamento SAP (acesso indireto) | Médio | Usuários SAP reais, somente leitura. Orientar o cliente a validar com o contrato SAP dele |
| R04 | Ciclo de venda longo no enterprise | Alto | Começar por consultorias AMS e empresas médias. Piloto com desconto |
| R05 | Resistência da segurança e do jurídico do cliente à IA | Médio | Modo sem IA, IA na nuvem do cliente, mascaramento, auditoria e DPA |
| R06 | Custo de IA acima do previsto | Médio | Franquias, cache, roteamento de modelos, monitoramento por tenant |
| R07 | Alucinação ou resposta errada | Alto | Causa vinda do ABAP, evals no CI, citação obrigatória da fonte, feedback 👎 |
| R08 | Diversidade de releases e customizações SAP | Médio | Camada de compatibilidade, `health` informando o release, testes no ambiente do piloto |
| R09 | Conflito com o empregador atual (propriedade intelectual) | Alto | Desenvolver fora do horário e em equipamento próprio, sem usar sistemas ou dados do empregador. Revisar o contrato |
| R10 | Rejeição na App Store | Baixo | Recursos nativos reais e opção de distribuição via MDM |
| R11 | Uso da marca "SAP" | Baixo | Nome sem "SAP" e uso de "para SAP" conforme as diretrizes |
| R12 | **Releases antigos (NW 7.00/7.01):** sintaxe limitada, sistemas não-Unicode, TLS antigo, sem abapGit | Médio | Sintaxe 7.00 verificada pelo abaplint, JSON próprio, testes de acentuação, HTTP interno via conector, entrega por transporte (seção 5.5) |
| R13 | **Validação do ECC só no piloto.** O CAL é S/4, então o lado ECC é testado mais tarde | Médio | Camada de compatibilidade bem isolada, fixtures de ECC montadas pelo seu conhecimento das tabelas e prioridade de conseguir o sandbox do piloto |
| R14 | **Desenvolvedor solo:** sobrecarga, dependência de uma pessoa, escopo crescendo | Alto | Escopo enxuto (14.2), demos por fase, documentação viva e serviços gerenciados |
| R15 | **Versões fragmentadas no self-hosted:** cada cliente numa versão, suporte mais difícil | Médio | Versões estáveis com janela de suporte definida (ex.: últimas 2), atualização simples por script, compatibilidade N-1 e pacote de suporte |
| R16 | **Código no servidor do cliente** (self-hosted) pode ser copiado ou estudado | Baixo | Build minificado, licença assinada e, principalmente, contrato com cláusula de auditoria. O ABAP já fica visível no SAP de qualquer forma |
| R17 | **Cliente sem VM Linux ou sem internet** | Baixo | VM Linux é pré-requisito contratual (D22). Sem ela, oferecer a versão Cloud. Pacote offline para quem não tem internet |
| R18 | **Dependência da nuvem surgindo aos poucos**, já que o piloto roda em Cloud | Médio | Teste de independência da nuvem no CI (D23) e a regra 4.4.2-1 na revisão de cada PR |

---

## 16. Pendências e perguntas em aberto

| ID | Pergunta | Sugestão atual |
|---|---|---|
| Q1 | **Nome comercial** do produto | Codinome "Raio-X" até definir |
| Q2 | **Nuvem de hospedagem**: AWS ou Azure? | Azure: muitos clientes SAP usam o ecossistema Microsoft (Entra ID). AWS também é viável. Ambas têm região Brasil |
| Q3 | **Provedor de IA padrão** | Comparar 2 provedores nos evals (seção 7.4) |
| ~~Q4~~ | ✅ Respondida: release mínimo NW 7.00 | D17 |
| ~~Q5~~ | ✅ Respondida: trabalho solo no início | D20 |
| Q5b | **Quantas horas por semana** você consegue dedicar? | Recalcular o cronograma |
| ~~Q6~~ | ✅ Respondida: sem ambiente SAP hoje | D19 / 14.1 |
| ~~Q7~~ | ✅ Respondida: MVP com SD-01, MM-02, PP-01, mais PP-03 e PP-04 | D18 |
| Q10 | **Orçamento** para o sprint no CAL (custo de nuvem por hora ligada) | Estimar antes da Fase 1b |
| Q11 | Em PP, o que **"aprovada"** significa nos clientes que você conhece? Status de usuário, workflow, outra coisa? | Configurável por cliente (catálogo, PP-03) |
| ~~Q12~~ | ✅ Respondida: VM Linux é pré-requisito do self-hosted | D22 |
| ~~Q13~~ | ✅ Respondida: piloto em Cloud, self-hosted em paralelo e sem dependência de nuvem | D23 |
| Q8 | **Preço inicial** | Definir depois das entrevistas, com valor de referência por usuário/ano e desconto para o piloto |
| Q9 | Namespace reservado `/XXX/` agora ou depois do piloto? | Depois do piloto (P14) |

---

## 17. Próximos passos

1. Revisar este documento e responder às pendências (seção 16).
2. Revisar o [catálogo de diagnósticos](./catalogo-de-diagnosticos.md): é ali que o seu conhecimento funcional faz a maior diferença.
3. Criar o esqueleto do monorepo (Fase 0): `contracts`, `sap-mock`, `api` e `web` mínimos, mais `abap/` com o handler REST em sintaxe 7.00.
4. Instalar o SAP ABAP Platform Trial (Docker) e orçar o sprint no CAL.
5. Marcar as primeiras 5 conversas de validação.
