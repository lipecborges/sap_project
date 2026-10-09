# Catálogo de Diagnósticos

> Documento vivo. Define **o que cada diagnóstico verifica, onde e o que sugere**.
> Ele é a especificação da lógica ABAP (`ZCL_RX_DIAG_*`), dos cenários do `sap-mock` e dos evals.

**Convenções**
- **Fonte ECC / Fonte S/4:** tabela e campo usados em cada release. Quando os dois forem iguais, aparece só uma vez.
- **Achado:** código do Finding (`<ID>.<CÓDIGO>`) e severidade (`BLOCKING`, `WARNING`, `INFO`).
- Itens marcados com *(validar)* precisam ser conferidos em sistema real antes da implementação.
- Todas as verificações são **somente leitura**.
- Todo o código segue a **sintaxe ABAP 7.00** (ver o projeto de implementação, seção 5.5).

## Visão geral

| ID | Pergunta típica | Fase | Prioridade |
|---|---|---|---|
| **SD-01** | Por que o pedido de venda não faturou? | MVP | ⭐ |
| **MM-02** | Por que a fatura do fornecedor está bloqueada para pagamento? | MVP | ⭐ |
| **PP-01** | Por que a ordem de produção não liberou ou está com falta de componentes? | MVP | ⭐ |
| **PP-03** | Qual a situação desta ordem de produção? (criada, aprovada, liberada, apontada, entregue, atrasada…) | MVP | ⭐ |
| **PP-04** | Quais ordens estão atrasadas / liberadas / sem entrada de mercadoria no centro X? (lista) | MVP | ⭐ |
| SD-02 | Por que a remessa não teve saída de mercadoria? | Piloto | |
| MM-01 | Por que o pedido de compra não teve entrada de mercadoria? | Piloto | |
| GE-01 | Por que o IDoc deu erro e como reprocessar? | Piloto | |
| SD-03 | Por que o preço ou a condição do item está errado ou incompleto? | Escala | |
| PP-02 | O que significam as mensagens de exceção do MRP deste material? | Escala | |

---

## SD-01: Pedido de venda não faturado

**Entrada:** `salesOrder` (VBELN). Opcional: `item` (POSNR).
**Autorização:** `V_VBAK_VKO` (org. vendas, canal, setor, ACTVT 03), `V_VBAK_AAT` (tipo de documento) e `ZRX_DIAG` (SD-01).

**Ordem de verificação:** segue a cadeia do processo (pedido → crédito → remessa → saída de mercadoria → faturamento). O resultado mostra **todos** os achados, com o primeiro bloqueio em destaque.

| # | Verificação | Fonte ECC | Fonte S/4 | Achado | Ação sugerida |
|---|---|---|---|---|---|
| 1 | Pedido existe | `VBAK` | `VBAK` | `SD01.NOT_FOUND` (status NOT_FOUND) | Conferir o número do documento |
| 2 | Itens recusados | `VBAP-ABGRU` | `VBAP-ABGRU` | `SD01.ITEM_REJECTED` (INFO) | VA02 se a recusa foi indevida |
| 3 | Item relevante para faturamento | `VBAP-PSTYV` → `TVAP-FKREL` | idem | `SD01.NOT_BILLING_RELEVANT` (INFO) | Rever a categoria de item (consultor) |
| 4 | Bloqueio de remessa no cabeçalho | `VBAK-LIFSK` (texto `TVLST`) | idem | `SD01.DELIVERY_BLOCK_HEADER` (BLOCKING) | VA02: remover o bloqueio |
| 5 | Bloqueio de remessa na divisão | `VBEP-LIFSP` | idem | `SD01.DELIVERY_BLOCK_SCHEDULE` (BLOCKING) | VA02: remover o bloqueio |
| 6 | Bloqueio de faturamento | `VBAK-FAKSK` / `VBAP-FAKSP` (texto `TVFST`) | idem | `SD01.BILLING_BLOCK` (BLOCKING) | VA02: remover o bloqueio |
| 7 | Bloqueio por crédito | `VBUK-CMGST` | `VBAK-CMGST` | `SD01.CREDIT_BLOCK` (BLOCKING) quando `B`/`C` *(validar valores)* | ECC: VKM1/VKM3. S/4 (FSCM): UKM_MY_DCDS *(validar)* |
| 8 | Incompletude | `VBUV` + `VBUK-UVALL/UVVLK/UVFAK` | `VBUV` + `VBAK-UVALL/UVVLK/UVFAK` | `SD01.INCOMPLETE` (BLOCKING), listando os campos faltantes | VA02 (log de incompletude) ou V.02 |
| 9 | Status de remessa | `VBUK-LFSTK` / `VBUP-LFSTA` | `VBAK-LFSTK` / `VBAP-LFSTA` | `SD01.NOT_DELIVERED` (WARNING) | VL01N / VL10* |
| 10 | Remessa sem saída de mercadoria | `VBFA` (remessa `VBTYP_N = 'J'`) → `VBUK-WBSTK` | `VBFA` → `LIKP-WBSTK` | `SD01.GOODS_ISSUE_PENDING` (BLOCKING) → sugere rodar **SD-02** | VL02N: dar saída de mercadoria |
| 11 | Faturamento pendente | `VBUK-FKSTK/FKSAK`, `VBUP-FKSTA/FKSAA`, `VKDFS` | `VBAK`/`VBAP` (mesmos campos), `VKDFS` | `SD01.BILLING_DUE` (INFO): está na lista de faturamento | VF01 / VF04 |
| 12 | Já faturado | `VBFA` (fatura `VBTYP_N = 'M'`) | idem | `SD01.ALREADY_BILLED` (status OK) com o número da fatura | VF03 |

**Relacionados:** remessas e faturas (do `VBFA`).

---

## MM-02: Fatura de fornecedor bloqueada para pagamento

**Entrada:** `invoiceDocument` (RBKP-BELNR) + `fiscalYear` (GJAHR). Opcional: `purchaseOrder`.
**Autorização:** `F_BKPF_BUK` (empresa, ACTVT 03), `M_RECH_WRK` (centro) *(validar)* e `ZRX_DIAG` (MM-02).

| # | Verificação | Fonte (ECC e S/4) | Achado | Ação sugerida |
|---|---|---|---|---|
| 1 | Documento existe e situação | `RBKP` (`RBSTAT`) | `MM02.NOT_FOUND` / `MM02.PARKED` (INFO, fatura estacionada) | MIR4 / MIR7 |
| 2 | Bloqueio de pagamento no cabeçalho | `RBKP-ZLSPR` (texto `T008T`) | `MM02.PAYMENT_BLOCK` (BLOCKING). `R` = bloqueio automático da verificação de faturas | MRBR (liberar) |
| 3 | Motivos de bloqueio por item | `RSEG-SPGRP` (preço), `SPGRM` (quantidade), `SPGRT` (data), `SPGRG` (qtd. preço do pedido), `SPGRQ` (manual), `SPGRS` (montante), `SPGRC` (qualidade), `SPGRV` (projeto) | `MM02.BLOCK_PRICE`, `MM02.BLOCK_QUANTITY`, `MM02.BLOCK_DATE`… (BLOCKING), um achado por motivo | MRBR. Corrigir a origem (ver 4 e 5) |
| 4 | Divergência de quantidade (entrada × fatura) | `EKBE` (`VGABE = '1'` entrada, `'2'` fatura) por item do pedido | `MM02.GR_MISSING` / `MM02.QTY_DIFF` (BLOCKING), com as quantidades | MIGO (entrada pendente) |
| 5 | Divergência de preço (pedido × fatura) | `EKPO-NETPR/PEINH` × `RSEG-WRBTR/MENGE` | `MM02.PRICE_DIFF` (BLOCKING), com o percentual | ME23N / contato com o comprador |
| 6 | Tolerâncias aplicáveis | `T169G` (chave de tolerância por empresa) | `MM02.TOLERANCE_INFO` (INFO): limites que dispararam o bloqueio | Consultor MM (OMR6) |
| 7 | Bloqueio na partida do fornecedor (FI) | `BSIK-ZLSPR` (em S/4, `BSIK` é visão de compatibilidade) | `MM02.FI_PAYMENT_BLOCK` (BLOCKING) | FB02 / FBL1N |

---

## PP-01: Ordem de produção não liberada / falta de componentes

**Entrada:** `productionOrder` (AUFNR).
**Autorização:** `C_AFKO_AWK` (centro e tipo de ordem) *(validar)* e `ZRX_DIAG` (PP-01).

| # | Verificação | Fonte (ECC e S/4) | Achado | Ação sugerida |
|---|---|---|---|---|
| 1 | Ordem existe | `AUFK`, `AFKO`, `AFPO` | `PP01.NOT_FOUND` | Conferir o número |
| 2 | Status do sistema (ver a [referência de status](#referência-status-da-ordem-de-produção)) | `JEST` (`OBJNR`, `INACT = ' '`) + `TJ02T` | `PP01.NOT_RELEASED` (BLOCKING) se não houver `REL`/`PREL`. `PP01.DELETED` se tiver `DLFL`. `PP01.TECO` se tiver `TECO`. `PP01.LOCKED` se tiver `LKD` | CO02: liberar / desbloquear |
| 3 | Status de usuário bloqueando a liberação | `JEST` (status `E*`) + `TJ30T`, perfil de status (BS02) | `PP01.USER_STATUS_BLOCK` (BLOCKING) | Ajustar o status de usuário (CO02) / consultor |
| 4 | Falta de material | Status `MSPT` em `JEST` + `RESB-XFEHL` *(validar)* | `PP01.MISSING_PARTS` (BLOCKING), listando os componentes | CO24 (lista de faltas) / MD04 |
| 5 | Componentes: necessidade × estoque | `RESB` (`BDMNG`, `ENMNG`, `XLOEK`) × `MARD-LABST` / `MCHB-CLABS` (S/4: visões sobre `MATDOC`) | `PP01.COMPONENT_SHORTAGE` (BLOCKING/WARNING), com as quantidades | MD04 / MIGO / transferência |
| 6 | Disponibilidade (ATP) na liberação | `BAPI_MATERIAL_AVAILABILITY` por componente; regra de verificação do tipo de ordem (OPJK) | `PP01.ATP_FAILED` (BLOCKING) quando a configuração impede a liberação com falta | Consultor PP (OPJK) / CO02 |
| 7 | Liberação automática não configurada | Parâmetros do tipo de ordem (OPL8) *(validar tabela)* | `PP01.MANUAL_RELEASE` (INFO) | CO02 / COHV (em massa) |

---

## PP-03: Situação da ordem de produção (visão completa)

**Pergunta típica:** *"Como está a ordem 1000456?"*, *"Essa ordem já foi apontada?"*, *"Vai atrasar o pedido do cliente?"*
**Entrada:** `productionOrder` (AUFNR).
**Autorização:** `C_AFKO_AWK` (centro e tipo de ordem) *(validar)* e `ZRX_DIAG` (PP-03).
**Base compartilhada:** `ZCL_RX_PP_ORDER_READER` (também usada por PP-01 e PP-04).

### O que a consulta devolve

**Fatos (`facts`)**

| Fato | Fonte (ECC e S/4) |
|---|---|
| Material, descrição, centro, tipo de ordem | `AFPO-MATNR`, `MAKT`, `AUFK-WERKS`, `AUFK-AUART` |
| Planejador MRP / responsável pela produção | `AFKO-DISPO`, `AFKO-FEVOR` |
| **Situação resumida** (ver a tabela abaixo) e status traduzidos | `JEST` + `TJ02T` (sistema) / `TJ30T` (usuário), no idioma do usuário |
| Quantidade planejada | `AFKO-GAMNG` / `AFPO-PSMNG` |
| Quantidade confirmada (apontada) boa | `AFKO-IGMNG` *(validar)* ou soma de `AFRU-LMNGA` (sem estornos) |
| Refugo confirmado | Soma de `AFRU-XMNGA` (sem estornos) |
| Quantidade entregue (entrada de mercadoria no estoque) | `AFPO-WEMNG` |
| Progresso | Confirmado ÷ planejado e entregue ÷ planejado (%) |
| Datas base (início/fim) | `AFKO-GSTRP` / `AFKO-GLTRP` |
| Datas programadas (início/fim) | `AFKO-GSTRS` / `AFKO-GLTRS` |
| Datas reais (início / fim confirmado / fim de entrega) | `AFKO-GSTRI` / `AFKO-GETRI` / `AFKO-GLTRI` |
| **Atraso** (dias de início e de fim) | Regras abaixo |
| Pedido de venda vinculado (MTO) e data pedida pelo cliente | `AFPO-KDAUF`/`KDPOS` → `VBEP-EDATU` |

**Tabelas (`tables`)**

| Tabela | Colunas | Fonte |
|---|---|---|
| Operações | Operação, centro de trabalho, descrição, status, início/fim programado, início/fim real, qtd. confirmada, refugo | `AFKO-AUFPL` → `AFVC` (`VORNR`, `ARBID` → `CRHD-ARBPL`, `LTXA1`, `OBJNR`) + `AFVV` (`MGVRG`, `LMNGA`, `XMNGA`, `FSAVD`/`FSEDD`, `ISDD`/`IEDD`) |
| Componentes | Material, necessário, retirado, pendente, falta? | `RESB` (`BDMNG`, `ENMNG`, `XFEHL` *(validar)*, `XLOEK`) |
| Últimos apontamentos | Data, operação, qtd. boa, refugo, usuário, estornado? | `AFRU` (`BUDAT`, `VORNR`, `LMNGA`, `XMNGA`, `ERNAM`, `STOKZ`/`STZHL`) |

### Situação resumida (vocabulário do Raio-X)

A ordem recebe **uma** situação principal (avaliada de cima para baixo) e **sinalizadores** adicionais.

| Situação principal | Regra (status de sistema ativos) |
|---|---|
| Eliminada | `DLFL` |
| Fechada | `CLSD` |
| Encerrada tecnicamente | `TECO` |
| Entregue | `DLV` |
| Entregue parcialmente | `PDLV` |
| Produzida (confirmada) | `CNF` |
| Em produção (apontada parcialmente) | `PCNF` |
| Liberada | `REL` ou `PREL` |
| **Aprovada** | Fonte a definir: status ou campo configurado como "aprovação" (ver abaixo) |
| Criada / aberta | `CRTD` |

| Sinalizador | Regra |
|---|---|
| 🔴 Atrasada no início | Sem início real (`GSTRI` vazio) e início programado (`GSTRS`, ou `GSTRP`) < hoje − tolerância |
| 🔴 Atrasada no fim | Sem `DLV`/`TECO`/`CLSD` e fim programado (`GLTRS`, ou `GLTRP`) < hoje − tolerância |
| 🟠 Operação atrasada | Operação sem `CNF` e fim programado da operação (`AFVV-FSEDD`) < hoje − tolerância |
| 🟠 Falta de material | `MSPT` ativo ou componente com falta |
| 🟠 Bloqueada | `LKD` |
| 🟡 Confirmada sem entrada | `CNF`/`PCNF` com quantidade confirmada > `AFPO-WEMNG` (entrada de mercadoria pendente) |
| 🟡 Risco para o pedido do cliente | Ordem MTO com fim programado posterior à data pedida no pedido de venda |
| ⚪ Apontamento estornado | Existe `AFRU` estornado nos últimos N dias |

**"Aprovada": fonte a definir (ver V07).** Existe o status "aprovada" na ordem de produção, mas **de qual campo ou status ele será lido** ainda vai ser definido. Para não travar a implementação, a tabela `ZRX_PP_STATUS_MAP` aceita qualquer uma destas fontes:

| Tipo de fonte | Exemplo | Como é lido |
|---|---|---|
| `SYSTEM_STATUS` | Código interno de status de sistema | `JEST` (`STAT = 'I....'`, `INACT = ' '`) |
| `USER_STATUS` | Perfil de status + status de usuário (ex.: `ZPP00001` / `E0002`) | `JEST` + `TJ30` |
| `FIELD` | Tabela + campo + valor (ex.: um campo da `AUFK`/`AFKO` ou de uma tabela Z do cliente) | `SELECT` dinâmico restrito às tabelas permitidas na configuração |

Cada linha liga *tipo de fonte + valor* a uma situação do Raio-X (ex.: → **Aprovada**). Status sem mapeamento aparecem com o texto original.

**Tolerância de atraso:** configurável por centro em `ZRX_CONFIG` (padrão: 0 dias). Os dias são corridos no MVP. O calendário de fábrica (`T001W-FABKL`) fica para depois.

### Achados (`findings`)

| Código | Severidade | Ação sugerida |
|---|---|---|
| `PP03.LATE_START` | BLOCKING | CO02 (liberar/reprogramar) / falar com o PCP |
| `PP03.LATE_FINISH` | BLOCKING | CO02 / COOIS (ver o gargalo) |
| `PP03.OPERATION_LATE` | WARNING | CO11N / CM01 (capacidade) |
| `PP03.MISSING_PARTS` | WARNING | Rodar **PP-01** / CO24 |
| `PP03.CONFIRMED_NOT_RECEIVED` | WARNING | MIGO (entrada de mercadoria da ordem, 101) |
| `PP03.SALES_ORDER_AT_RISK` | WARNING | Avisar a área comercial (VA03 do pedido) |
| `PP03.LOCKED` | BLOCKING | CO02 (desbloquear) |
| `PP03.REVERSED_CONFIRMATION` | INFO | CO14 (ver apontamentos) |

---

## PP-04: Lista de ordens por situação (atrasadas, liberadas, apontadas…)

**Pergunta típica:** *"Quais ordens estão atrasadas no centro 1000?"*, *"Quais ordens do planejador 001 foram liberadas e ainda não foram apontadas?"*, *"Tem ordem confirmada sem entrada de mercadoria?"*
**Tipo:** consulta de lista (paginada).
**Autorização:** `C_AFKO_AWK` por centro e tipo de ordem. Linhas sem autorização são **omitidas**, e o total omitido é informado.

**Entrada**

| Parâmetro | Obrigatório | Observação |
|---|---|---|
| `plant` (WERKS) | ✅ | Evita varrer todas as ordens |
| `situation` | — | `LATE_START`, `LATE_FINISH`, `RELEASED`, `IN_PRODUCTION`, `CONFIRMED_NOT_RECEIVED`, `MISSING_PARTS`, `CREATED`, `APPROVED`… (vocabulário do PP-03) |
| `mrpController` (DISPO) / `productionScheduler` (FEVOR) | — | |
| `orderType` (AUART) | — | |
| `dateFrom` / `dateTo` | — | Período pelas datas programadas. Padrão: últimos 90 dias até hoje + 30 |
| `material` | — | |
| `maxRows` / `page` | — | Padrão 100, máximo 500 |

**Seleção (ECC e S/4)**
1. `AUFK` (`AUTYP = '10'`, ordem de produção; opcional `'40'`, ordem de processo PP-PI) + `AFKO` + `AFPO`, filtrando centro, tipo, planejador e datas.
2. Status em bloco via `JEST` (`FOR ALL ENTRIES` nos `OBJNR`, `INACT = ' '`).
3. Classificação de cada ordem com a **mesma regra do PP-03** (`ZCL_RX_PP_STATUS_MAP`).
4. Filtro pela situação pedida, ordenação por dias de atraso (decrescente) e paginação.

**Saída**
- `facts`: totais por situação (ex.: "12 atrasadas no fim, 5 com falta de material, 3 confirmadas sem entrada").
- `tables` → `orders`: Ordem, Material, Descrição, Qtd. planejada, Confirmada, Entregue, Situação, Sinalizadores, Fim programado, Dias de atraso, Pedido de venda.
- `findings`: um resumo por sinalizador relevante (ex.: `PP04.LATE_ORDERS` com a contagem).

**Uso futuro:** é a base para **alertas push** no celular (ex.: resumo diário das ordens atrasadas para o gestor) na Fase 5.

---

## SD-02: Remessa sem saída de mercadoria

**Entrada:** `delivery` (LIKP-VBELN).
**Autorização:** `V_LIKP_VST` (ponto de expedição) e `ZRX_DIAG` (SD-02).

| # | Verificação | Fonte ECC | Fonte S/4 | Achado | Ação sugerida |
|---|---|---|---|---|---|
| 1 | Status de saída de mercadoria | `VBUK-WBSTK` | `LIKP-WBSTK` | `SD02.ALREADY_ISSUED` (OK) | VL03N |
| 2 | Bloqueio de remessa | `LIKP-LIFSK` | idem | `SD02.DELIVERY_BLOCK` (BLOCKING) | VL02N |
| 3 | Crédito | `VBUK-CMGST` | `LIKP-CMGST` | `SD02.CREDIT_BLOCK` (BLOCKING) | VKM1/VKM3 ou FSCM |
| 4 | Incompletude | `VBUV` | `VBUV` | `SD02.INCOMPLETE` (BLOCKING) | VL02N |
| 5 | Picking | `VBUK-KOSTK` / `VBUP-KOSTA` | `LIKP-KOSTK` / `LIPS-KOSTA` | `SD02.PICKING_PENDING` (BLOCKING) | VL02N / LT03 (WM) |
| 6 | Ordem de transferência WM aberta | `LTAK`/`LTAP` (quando `LIPS-LGNUM` está preenchido) | idem (EWM descentralizado fora do escopo) | `SD02.WM_TO_OPEN` (BLOCKING) | LT12 |
| 7 | Lote obrigatório não informado | `MARC-XCHPF = 'X'` e `LIPS-CHARG` vazio | idem | `SD02.BATCH_MISSING` (BLOCKING) | VL02N |
| 8 | Estoque insuficiente | `MARD-LABST` / `MCHB-CLABS` | idem (visões sobre `MATDOC`) | `SD02.NO_STOCK` (BLOCKING), com as quantidades | MMBE / MIGO |
| 9 | Período MM fechado | `MARV` (período atual da empresa) × data de saída | idem | `SD02.PERIOD_CLOSED` (BLOCKING) | Key user / MMPV |

---

## MM-01: Pedido de compra sem entrada de mercadoria

**Entrada:** `purchaseOrder` (EBELN). Opcional: `item`.
**Autorização:** `M_BEST_EKO` (org. compras), `M_BEST_WRK` (centro), `M_BEST_BSA` (tipo de pedido) e `ZRX_DIAG` (MM-01).

| # | Verificação | Fonte (ECC e S/4) | Achado | Ação sugerida |
|---|---|---|---|---|
| 1 | Estratégia de liberação pendente | `EKKO-FRGKE`, `FRGZU`, `FRGGR/FRGSX` | `MM01.NOT_RELEASED` (BLOCKING), indicando o próximo liberador | ME29N / ME28 |
| 2 | Item eliminado ou bloqueado | `EKPO-LOEKZ` (`L` eliminado, `S` bloqueado) | `MM01.ITEM_DELETED` / `MM01.ITEM_BLOCKED` (BLOCKING) | ME22N |
| 3 | Entrada não prevista | `EKPO-WEPOS` vazio | `MM01.NO_GR_EXPECTED` (INFO) | Rever o item (comprador) |
| 4 | Remessa final marcada | `EKPO-ELIKZ` | `MM01.DELIVERY_COMPLETED` (INFO) | ME22N, se for indevido |
| 5 | Entrada exige aviso de recebimento | `EKPO-BSTAE` (controle de confirmação) + `EKES` | `MM01.INBOUND_DELIVERY_REQUIRED` (BLOCKING) | VL31N → MIGO |
| 6 | Histórico de entradas | `EKBE` (`VGABE = '1'`) × `EKET` (`MENGE`, `WEMNG`, `EINDT`) | `MM01.PARTIAL_GR` / `MM01.OVERDUE` (WARNING), com os dias de atraso | MIGO / follow-up com o fornecedor |
| 7 | Fornecedor bloqueado | `LFA1-SPERM` / `LFM1-SPERM` | `MM01.VENDOR_BLOCKED` (BLOCKING) | XK05 / BP (S/4) |

---

## GE-01: IDoc com erro

**Entrada:** `idoc` (DOCNUM).
**Autorização:** `S_IDOCMONI` *(validar)* e `ZRX_DIAG` (GE-01).

| # | Verificação | Fonte (ECC e S/4) | Achado | Ação sugerida |
|---|---|---|---|---|
| 1 | Cabeçalho e status atual | `EDIDC` (`STATUS`, `MESTYP`, `IDOCTP`, `DIRECT`, parceiros) | `GE01.STATUS_<nn>` com o significado (ex.: 51 = documento de aplicação não lançado) | WE02 |
| 2 | Mensagens de erro | `EDIDS` (`STATUS`, `STAMID`, `STAMNO`, `STAPA1–4`) + texto `T100` | `GE01.APP_ERROR` (BLOCKING), com a mensagem completa | Corrigir a causa (cadastro, configuração) |
| 3 | Parceiro / perfil | `EDP13` / `EDP21` (saída / entrada) | `GE01.PARTNER_PROFILE_MISSING` (BLOCKING) | WE20 (Basis/consultor) |
| 4 | Reprocessamento | Status atual + histórico em `EDIDS` | `GE01.REPROCESS_HINT` (INFO) | BD87, depois de corrigir a causa |

---

## SD-03 e PP-02 (fase de escala: especificar depois)

- **SD-03 Preço / condições:** esquema de cálculo (`VBAK-KALSM`), condições do item (`KONV` no ECC, `PRCD_ELEMENTS` no S/4), condições inativas (`KINAK`), condições obrigatórias ausentes (`T683S-KOBLI`) e incompletude de preço.
- **PP-02 Exceções do MRP:** `BAPI_MATERIAL_STOCK_REQ_LIST` (funciona com a lista persistida do ECC e com o MRP Live do S/4), mensagens de exceção e respectivos textos *(validar tabela de textos)* e ações sugeridas por exceção.

---

## Referência: status da ordem de produção

Status de sistema mais usados em ordens de produção. **A lógica usa o código interno** (`JEST-STAT`, ex.: `I0002`), nunca o texto, que muda com o idioma: em português, `TJ02T` mostra abreviações traduzidas. Os códigos internos de cada status serão confirmados em `TJ02T` na Fase 1b e fixados como constantes em `ZCL_RX_PP_STATUS_MAP`.

| Status (EN) | Significado | Uso no Raio-X |
|---|---|---|
| `CRTD` | Criada / aberta | Situação "Criada" |
| `PREL` | Parcialmente liberada | Situação "Liberada" |
| `REL` | Liberada | Situação "Liberada" |
| `PCNF` | Parcialmente confirmada (apontada) | Situação "Em produção" |
| `CNF` | Confirmada | Situação "Produzida" |
| `PDLV` | Parcialmente fornecida (entrada parcial no estoque) | Situação "Entregue parcialmente" |
| `DLV` | Fornecida (entrada total no estoque) | Situação "Entregue" |
| `TECO` | Encerrada tecnicamente | Situação "Encerrada tecnicamente" |
| `CLSD` | Fechada (encerramento comercial) | Situação "Fechada" |
| `DLFL` | Marcada para eliminação | Situação "Eliminada" |
| `LKD` | Bloqueada | Sinalizador "Bloqueada" |
| `MSPT` | Falta de material | Sinalizador "Falta de material" |
| `MACM` | Material comprometido (disponibilidade confirmada) | Informativo |
| `PRC` | Pré-calculada (custos) | Informativo |
| `CSER` | Erro no cálculo de custos | Achado informativo (pode impedir a liberação, conforme a configuração) |
| `GMPS` | Movimento de mercadoria lançado | Informativo |
| `SETC` | Regra de liquidação criada | Informativo |

**Status de usuário** (`JEST` com `STAT` começando por `E`, textos em `TJ30T` por perfil de status) dependem de cada cliente. Eles aparecem sempre com o texto original e podem ser mapeados para situações do Raio-X em `ZRX_PP_STATUS_MAP` (ex.: "Aprovada").

---

## Checklist de validação

Pontos que escrevi com base no meu conhecimento de SAP, mas que **precisam ser conferidos por você** (SE11/SE16, SU21, transações) antes de virar código. Marque ✅ quando confirmar, ou corrija na tabela do diagnóstico.

| ID | Diagnóstico | O que conferir | Onde conferir |
|---|---|---|---|
| V01 | SD-01 | Valores do status de crédito `CMGST` que significam "bloqueado" (`B`? `C`?) | SE11 → domínio do `CMGST` |
| V02 | SD-01 | Transação de liberação de crédito no S/4 com FSCM (`UKM_MY_DCDS`?) | Sistema S/4 |
| V03 | MM-02 | Objeto de autorização por centro na verificação de faturas (`M_RECH_WRK`?) | SU21 |
| V04 | PP-01, PP-03, PP-04 | Objeto de autorização de ordem por centro e tipo (`C_AFKO_AWK`?) | SU21 |
| V05 | PP-01, PP-03 | Campo de "falta de material" na reserva (`RESB-XFEHL`?) | SE11 → `RESB` |
| V06 | PP-01 | Onde ficam os parâmetros do tipo de ordem para liberação automática (OPL8) | SE11 / OPL8 |
| V07 | PP-03, PP-04 | **De qual campo ou status vem o "Aprovada"** | A definir por você |
| V08 | PP-03 | Quantidade confirmada no cabeçalho (`AFKO-IGMNG`?) ou soma de `AFRU-LMNGA` | SE11 → `AFKO` |
| V09 | PP-03 | Datas reais do cabeçalho: `GSTRI` (início), `GETRI` (fim confirmado), `GLTRI` (fim real) | SE11 → `AFKO` |
| V10 | PP-03 / referência | Códigos internos (`I0001`…) de cada status: CRTD, REL, PCNF, CNF, DLV, TECO, LKD, MSPT… | SE16 → `TJ02T` (idioma EN) |
| V11 | GE-01 | Objeto de autorização de monitoramento de IDoc (`S_IDOCMONI`?) | SU21 |
| V12 | PP-02 | Tabela de textos das mensagens de exceção do MRP | SE11 / configuração do MRP |
| V13 | Todos | Funções e BAPIs usadas existem em NW 7.00 (`STATUS_READ`, `BAPI_MATERIAL_AVAILABILITY`, `AUTHORITY_CHECK`…) | SE37 em um sistema 7.00 (quando houver) |
| V14 | Plataforma | abapGit exige 7.02 ou superior? | Documentação do abapGit |

V01 a V12 podem ser conferidos em qualquer sistema ECC ou S/4 a que você tenha acesso legítimo, ou durante o sprint no SAP CAL.

---

## Como adicionar um diagnóstico

1. Especificar aqui: entrada, autorização e tabela de verificações.
2. Criar os cenários no `services/sap-mock` (um por achado).
3. Definir o esquema de parâmetros em `packages/contracts` e a ferramenta em `packages/sap-tools`.
4. Implementar `ZCL_RX_DIAG_<ID>` (`ZIF_RX_DIAGNOSTIC`) com ABAP Unit.
5. Adicionar casos ao `evals/`.
6. Habilitar em `ZRX_CONFIG` e incluir o ID na role modelo `ZRX_USER`.
