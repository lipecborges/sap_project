"! Leitura de dados de vendas (SD) para os diagnósticos SD-01 e SD-10.
"! Os tipos já vêm harmonizados entre ECC e S/4HANA: quem usa a interface não
"! precisa saber se o status SD vem da VBUK/VBUP (ECC) ou da VBAK/VBAP/LIKP (S/4).
"! Interface separada para permitir dublês com dados em memória nos testes unitários.
INTERFACE zif_rx_sd_reader PUBLIC.

  " Situação do pedido na cadeia crédito → remessa → saída de mercadoria → faturamento.
  " Os campos de status são os do SAP (valores: ' ' não relevante, A não processado,
  " B parcial, C concluído). Os indicadores no fim são calculados por quem consome.
  TYPES:
    BEGIN OF ty_order_state,
      "! CMGST: B/C = crédito não aprovado (validar valores, pendência V01)
      credit_status        TYPE c LENGTH 1,
      "! LIFSK: bloqueio de remessa do cabeçalho
      delivery_block       TYPE c LENGTH 2,
      "! UVALL: A/B = pedido incompleto
      incompletion_status  TYPE c LENGTH 1,
      "! LFSTK: status de remessa do pedido
      delivery_status      TYPE c LENGTH 1,
      "! FAKSK: bloqueio de faturamento do cabeçalho
      billing_block        TYPE c LENGTH 2,
      "! Texto do bloqueio de faturamento (TVFST)
      billing_block_text   TYPE c LENGTH 20,
      "! FKSTK: status de faturamento do pedido
      billing_status       TYPE c LENGTH 1,
      "! Há bloqueio de remessa em alguma divisão (VBEP-LIFSP)
      schedule_blocked     TYPE abap_bool,
      "! Há bloqueio de faturamento em algum item (VBAP-FAKSP)
      item_billing_blocked TYPE abap_bool,
      "! Quantidade de remessas criadas para o pedido
      delivery_count       TYPE i,
      "! Primeira remessa com saída de mercadoria pendente (vazio = nenhuma)
      pending_delivery     TYPE c LENGTH 10,
    END OF ty_order_state.

  " Cabeçalho do pedido (VBAK) com os status já lidos da tabela certa do release.
  TYPES:
    BEGIN OF ty_order_header,
      "! Falso quando o pedido não existe no mandante
      exists              TYPE abap_bool,
      vbeln               TYPE c LENGTH 10,
      "! Categoria do documento (C = pedido)
      vbtyp               TYPE c LENGTH 1,
      auart               TYPE c LENGTH 4,
      vkorg               TYPE c LENGTH 4,
      vtweg               TYPE c LENGTH 2,
      spart               TYPE c LENGTH 2,
      kunnr               TYPE c LENGTH 10,
      customer_name       TYPE c LENGTH 35,
      netwr               TYPE p LENGTH 15 DECIMALS 2,
      waerk               TYPE c LENGTH 5,
      "! Data de criação
      erdat               TYPE d,
      "! Data de remessa desejada pelo cliente
      vdatu               TYPE d,
      "! Quantidade de itens
      item_count          TYPE i,
      "! Texto do bloqueio de remessa (TVLST)
      delivery_block_text TYPE c LENGTH 20,
      state               TYPE ty_order_state,
    END OF ty_order_header,
    ty_order_headers TYPE STANDARD TABLE OF ty_order_header WITH DEFAULT KEY.

  " Item do pedido (VBAP) com recusa, bloqueios e relevância de faturamento.
  TYPES:
    BEGIN OF ty_item,
      posnr               TYPE c LENGTH 6,
      "! ABGRU: motivo de recusa
      rejection_reason    TYPE c LENGTH 2,
      "! Texto do motivo de recusa (TVAGT)
      rejection_text      TYPE c LENGTH 40,
      "! PSTYV: categoria do item
      item_category       TYPE c LENGTH 4,
      "! TVAP-FKREL preenchido: o item é relevante para faturamento
      billing_relevant    TYPE abap_bool,
      "! VBEP-LIFSP: bloqueio de remessa da divisão
      schedule_block      TYPE c LENGTH 2,
      schedule_block_text TYPE c LENGTH 20,
      "! VBAP-FAKSP: bloqueio de faturamento do item
      billing_block       TYPE c LENGTH 2,
      billing_block_text  TYPE c LENGTH 20,
    END OF ty_item,
    ty_items TYPE STANDARD TABLE OF ty_item WITH DEFAULT KEY.

  " Campo obrigatório faltante (VBUV).
  TYPES:
    BEGIN OF ty_missing_field,
      "! 000000 = cabeçalho
      posnr      TYPE c LENGTH 6,
      table_name TYPE c LENGTH 30,
      field_name TYPE c LENGTH 30,
      "! Descrição do campo no dicionário, no idioma do usuário
      field_text TYPE c LENGTH 60,
    END OF ty_missing_field,
    ty_missing_fields TYPE STANDARD TABLE OF ty_missing_field WITH DEFAULT KEY.

  " Documento subsequente (VBFA): remessa (J) ou fatura (M).
  TYPES:
    BEGIN OF ty_followup,
      category           TYPE c LENGTH 1,
      doc_number         TYPE c LENGTH 10,
      "! Documento anterior (o pedido ou, na fatura, a remessa)
      predecessor        TYPE c LENGTH 10,
      "! WBSTK da remessa (vazio na fatura)
      goods_issue_status TYPE c LENGTH 1,
    END OF ty_followup,
    ty_followups TYPE STANDARD TABLE OF ty_followup WITH DEFAULT KEY.

  CONSTANTS:
    BEGIN OF c_followup,
      delivery TYPE c LENGTH 1 VALUE 'J',
      invoice  TYPE c LENGTH 1 VALUE 'M',
    END OF c_followup.

  "! True quando o sistema é S/4HANA (status SD em VBAK/VBAP/LIKP em vez de VBUK/VBUP).
  METHODS is_s4
    RETURNING VALUE(rv_s4) TYPE abap_bool.

  "! Cabeçalho do pedido. EXISTS = falso quando o pedido não existe.
  METHODS get_header
    IMPORTING iv_vbeln         TYPE csequence
    RETURNING VALUE(rs_header) TYPE ty_order_header.

  METHODS get_items
    IMPORTING iv_vbeln        TYPE csequence
    RETURNING VALUE(rt_items) TYPE ty_items.

  "! Campos faltantes do log de incompletude (VBUV).
  METHODS get_missing_fields
    IMPORTING iv_vbeln          TYPE csequence
    RETURNING VALUE(rt_missing) TYPE ty_missing_fields.

  "! Remessas e faturas subsequentes (VBFA) com o status de saída de mercadoria.
  METHODS get_followups
    IMPORTING iv_vbeln            TYPE csequence
    RETURNING VALUE(rt_followups) TYPE ty_followups.

  "! O pedido (ou uma remessa dele) está na lista de faturamento (VKDFS).
  METHODS is_billing_due
    IMPORTING iv_vbeln      TYPE csequence
              it_followups  TYPE ty_followups
    RETURNING VALUE(rv_due) TYPE abap_bool.

  "! Pedidos abertos (faturamento pendente), do mais antigo para o mais novo,
  "! já com os status e indicadores de bloqueio. EV_TRUNCATED = atingiu IV_MAX_ROWS.
  METHODS get_open_orders
    IMPORTING iv_sales_org TYPE csequence OPTIONAL
              iv_max_rows  TYPE i
    EXPORTING et_orders    TYPE ty_order_headers
              ev_truncated TYPE abap_bool.

  "! Autorização standard de leitura (ACTVT 03): V_VBAK_VKO (org. de vendas, canal,
  "! setor) e, se IV_AUART vier preenchido, V_VBAK_AAT (tipo de documento).
  "! Canal e setor vazios não são verificados.
  METHODS is_authorized
    IMPORTING iv_vkorg          TYPE csequence
              iv_vtweg          TYPE csequence OPTIONAL
              iv_spart          TYPE csequence OPTIONAL
              iv_auart          TYPE csequence OPTIONAL
    RETURNING VALUE(rv_allowed) TYPE abap_bool.

ENDINTERFACE.
