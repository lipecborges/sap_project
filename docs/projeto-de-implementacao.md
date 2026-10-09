# Projeto de Implementação — Raio-X (codinome provisório)

> Assistente de diagnóstico de processos SAP (SD, MM, PP) com IA, para web, Windows, Android e iOS.

| | |
|---|---|
| **Versão** | 0.1 (rascunho para discussão) |
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
| D14 | **Multi-tenant desde o início**, empacotável para **self-hosted** (Docker) | Atende SaaS e clientes que não aceitam nuvem |
| D15 | **Web primeiro.** Desktop e mobile depois, com o mesmo código | Entrega valor mais cedo, sem retrabalho |
| D16 | `RFC_READ_TABLE` **apenas para exploração**, nunca no produto | Limitações técnicas, não é liberada para clientes e enfrenta resistência da segurança |

### 3.2 Propostas novas (precisam do seu OK)

| ID | Proposta | Motivo |
|---|---|---|
| P01 | **Desenvolvimento orientado a contrato + simulador SAP** (`services/sap-mock`) | Front, backend e IA evoluem sem depender de um sistema SAP. Também serve para demos e testes automatizados |
| P02 | **Formato padrão de resultado** (*Finding*) compartilhado entre ABAP e TypeScript (seção 5.3) | A IA, a UI e os testes passam a falar a mesma língua. Adicionar um diagnóstico novo não exige mudar o front |
| P03 | **Objeto de autorização próprio `ZRX_DIAG`** + role PFCG modelo | O cliente controla, no próprio SAP, quem pode usar cada diagnóstico |
| P04 | **Release mínimo: SAP NetWeaver 7.40** (sintaxe ABAP 7.40) | Produtividade (declarações inline, expressões) e `/UI2/CL_JSON` disponível. Ver pendência Q4 |
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
| P16 | **Ambiente SAP de desenvolvimento:** framework técnico no *ABAP Platform Trial* e diagnósticos em um **S/4 Fully-Activated Appliance (SAP CAL)** ou no **sandbox de um parceiro piloto**, com autorização formal | O ABAP Platform Trial **não traz os módulos SD/MM/PP** (ver risco R01) |
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
│                                                    ├── direct    (dev / Trial)      │
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

### 4.4 Modos de implantação

| Modo | Para quem | Observação |
|---|---|---|
| **SaaS** (padrão) | Empresas médias e consultorias | Backend na nuvem do Raio-X (região Brasil) + conector no cliente |
| **SaaS + IA do cliente** | Empresas com política de IA própria | O LLM roda na nuvem do cliente (Azure, AWS Bedrock, Google Vertex), com credenciais dele |
| **Self-hosted** | Grandes empresas e setores regulados | Backend inteiro em Docker/Kubernetes no cliente, com licença por arquivo assinado |

### 4.5 Compatibilidade com sistemas SAP

| Sistema | Suporte | Como |
|---|---|---|
| ECC 6.0 (EHP7+/NW 7.40+) | ✅ MVP | Add-on ABAP + conector |
| S/4HANA on-premise / Private Cloud | ✅ MVP | Add-on ABAP + conector (camada de compatibilidade) |
| ECC em NW < 7.40 | ⚠️ Avaliar | Exigiria *downport* da sintaxe (ver Q4) |
| S/4HANA Public Cloud | 🔜 Fase 6 | Somente APIs liberadas (OData) ou extensão ABAP Cloud |

---

## 5. Add-on ABAP

### 5.1 Estrutura de objetos (pacote `ZRX`)

| Subpacote | Objetos principais | Papel |
|---|---|---|
| `ZRX_CORE` | `ZCL_RX_HTTP_HANDLER` (implementa `IF_HTTP_EXTENSION`), `ZCL_RX_ROUTER`, `ZCL_RX_JSON` | Recebe a requisição, roteia, (de)serializa JSON e trata erros |
| `ZRX_CORE` | `ZIF_RX_DIAGNOSTIC`, `ZCL_RX_DIAGNOSTIC_REGISTRY` | Interface comum dos diagnósticos e registro dos disponíveis |
| `ZRX_CORE` | `ZCL_RX_RELEASE_INFO` | Detecta ECC ou S/4 (por exemplo, componente `S4CORE` na `CVERS`) e a versão |
| `ZRX_SEC` | Objeto de autorização `ZRX_DIAG` (campos `ZRX_DIAGID`, `ACTVT`), `ZCL_RX_AUTH`, role modelo `ZRX_USER` | Quem pode usar qual diagnóstico + verificações de autorização standard |
| `ZRX_LOG` | Tabela `ZRX_LOG`, `ZCL_RX_LOGGER` | Registro de cada execução: usuário, diagnóstico, parâmetros e duração |
| `ZRX_CFG` | Tabela `ZRX_CONFIG` + visão de manutenção | Diagnósticos habilitados, limites e mascaramento |
| `ZRX_COMPAT` | `ZIF_RX_SD_STATUS`, `ZCL_RX_SD_STATUS_ECC`, `ZCL_RX_SD_STATUS_S4`… | Isola as diferenças de modelo de dados entre ECC e S/4 |
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
| POST | `/v1/diagnostics/{id}` | Executa um diagnóstico. Corpo: parâmetros. Resposta: resultado padrão |

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
| `sap-transport` | Interface `SapTransport` com implementações `direct`, `connector` e `mock` |
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
| Web | PWA (instalável) | Web Push, cookie seguro | URL própria |
| Windows | Tauri 2 | Notificações do Windows, cofre de credenciais, auto-update | Instalador MSI/EXE assinado e Microsoft Store (opcional) |
| Android | Capacitor | Push (FCM), biometria, Keystore | Google Play e MDM corporativo (Intune etc.) |
| iOS | Capacitor | Push (APNs), Face ID/Touch ID, Keychain | App Store e distribuição privada (Apple Business Manager / MDM) |

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
├── infra/                   # Docker, compose, deploy
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
| ABAP | **abaplint** (CI) | Sintaxe, padrões, regra de somente leitura e compatibilidade com 7.40 |
| Contratos | Zod + testes de contrato | ABAP, mock e backend falam o mesmo JSON |
| Backend | Vitest + banco de teste | Regras de licença, isolamento de tenant, laço do agente |
| Front | Vitest + Testing Library | Componentes e cartões de diagnóstico |
| Ponta a ponta | Playwright, contra o `sap-mock` | Login → pergunta → resposta |
| IA | `evals/` | Qualidade das respostas (seção 7.6) |

**CI (GitHub Actions):** lint, typecheck, testes, abaplint, evals (quando prompt ou ferramentas mudarem) e build das imagens Docker.

**Ambientes:** `local` (mock ou SAP Trial) → `staging` (com SAP de teste) → `produção`.

---

## 14. Plano de implementação

> As estimativas consideram **1 pessoa em dedicação integral**. Com cerca de 20 h/semana, multiplique por ~2.

### Fase 0: Fundação e validação (1 a 2 semanas)
**Objetivo:** ambiente pronto e hipótese de mercado testada.
- Monorepo (pnpm + Turborepo), CI básico, abapGit, abaplint
- `packages/contracts` com o esquema do Finding
- `services/sap-mock` com os cenários dos 3 primeiros diagnósticos
- SAP ABAP Platform Trial rodando (framework técnico)
- Definir o acesso a um sistema com SD/MM/PP (P16)
- **Trilha de negócio:** 5 conversas com gestores de AMS e key users. Buscar 1 cliente piloto (P17)

**Pronto quando:** `pnpm dev` sobe a web e o mock, e há pelo menos 1 piloto interessado ou um aprendizado claro das entrevistas.

### Fase 1: Núcleo ABAP (3 a 4 semanas)
- Handler REST, roteador, JSON, tratamento de erros (`ZRX_CORE`)
- `health`, `me` e `diagnostics`
- Objeto de autorização `ZRX_DIAG`, log `ZRX_LOG` e configuração `ZRX_CONFIG`
- Camada de compatibilidade ECC/S/4 (status SD)
- **Diagnósticos do MVP:** `SD-01` Pedido não faturado, `MM-02` Fatura bloqueada, `PP-01` Ordem não liberada / falta de componentes
- ABAP Unit para os três

**Pronto quando:** os 3 diagnósticos retornam Findings corretos em pelo menos 5 cenários reais cada, via Postman/curl.

### Fase 2: Backend + IA (3 a 4 semanas)
- API (Fastify), PostgreSQL (Drizzle), auth `sap-basic`, sessão
- `SapTransport` (`direct` + `mock`)
- `packages/sap-tools` + laço do agente + streaming SSE
- Auditoria, mascaramento básico e contadores de uso
- Avaliação de 2 provedores de IA com os primeiros evals

**Pronto quando:** uma pergunta em linguagem natural gera a resposta correta, com fonte, nos cenários de referência (≥ 90% nos evals).

### Fase 3: Web MVP (2 a 3 semanas)
- Login, chat com streaming, cartões de Findings, modo sem IA, histórico, 👍/👎
- Admin mínimo: usuários e licenças, sistemas SAP, uso
- i18n (pt-BR), tema claro e escuro, layout responsivo

**Pronto quando:** demo completa no navegador e no celular (PWA). **Esta é a versão para mostrar a clientes.**

> **Marco:** MVP demonstrável em cerca de **9 a 13 semanas** de dedicação integral.

### Fase 4: Piloto (4 a 6 semanas)
- `services/connector` (Docker + serviço Windows), gateway de conectores
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
- Pacote self-hosted e licença por arquivo assinado
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
| R01 | **Sem acesso a um SAP com SD/MM/PP.** O ABAP Platform Trial só traz a plataforma técnica | Alto | S/4 Fully-Activated Appliance via SAP CAL (trial, com custo de nuvem), sandbox do cliente piloto (com autorização formal) e `sap-mock` para todo o restante |
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

---

## 16. Pendências e perguntas em aberto

| ID | Pergunta | Sugestão atual |
|---|---|---|
| Q1 | **Nome comercial** do produto | Codinome "Raio-X" até definir |
| Q2 | **Nuvem de hospedagem**: AWS ou Azure? | Azure: muitos clientes SAP usam o ecossistema Microsoft (Entra ID). AWS também é viável. Ambas têm região Brasil |
| Q3 | **Provedor de IA padrão** | Comparar 2 provedores nos evals (seção 7.4) |
| Q4 | **Release mínimo** do SAP: NW 7.40 é aceitável? Seus clientes têm ECC em 7.31 ou 7.0x? | 7.40 (P04) |
| Q5 | **Dedicação e equipe:** só você? Quantas horas por semana? | Estimativas feitas para 1 pessoa em tempo integral |
| Q6 | **Ambiente SAP com SD/MM/PP:** tem acesso a algum de forma legítima? | P16 / R01 |
| Q7 | **Os 3 diagnósticos do MVP** (SD-01, MM-02, PP-01) são as maiores dores que você vê no dia a dia? | Validar nas entrevistas |
| Q8 | **Preço inicial** | Definir depois das entrevistas, com valor de referência por usuário/ano e desconto para o piloto |
| Q9 | Namespace reservado `/XXX/` agora ou depois do piloto? | Depois do piloto (P14) |

---

## 17. Próximos passos

1. Revisar este documento e responder às pendências (seção 16).
2. Revisar o [catálogo de diagnósticos](./catalogo-de-diagnosticos.md): é ali que o seu conhecimento funcional faz a maior diferença.
3. Criar o esqueleto do monorepo (Fase 0): `contracts`, `sap-mock`, `api` e `web` mínimos, mais `abap/` com o handler REST.
4. Marcar as primeiras 5 conversas de validação.
