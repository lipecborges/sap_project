"! Leitura dos dados de compras (MM) usados pelos diagnósticos MM-02 e MM-10:
"! fatura do fornecedor (RBKP/RSEG), histórico do pedido (EKBE), preço do pedido (EKPO),
"! tolerâncias (T169G) e partida do fornecedor (BSIK). Só tipos e métodos de leitura,
"! sem lógica de negócio. A implementação real é ZCL_RX_MM_READER.
INTERFACE zif_rx_mm_reader PUBLIC.

  TYPES ty_belnr TYPE c LENGTH 10.
  TYPES ty_gjahr TYPE n LENGTH 4.
  TYPES ty_bukrs TYPE c LENGTH 4.
  TYPES ty_werks TYPE c LENGTH 4.
  TYPES ty_lifnr TYPE c LENGTH 10.
  TYPES ty_ebeln TYPE c LENGTH 10.
  TYPES ty_ebelp TYPE n LENGTH 5.
  TYPES ty_tolsl TYPE c LENGTH 2.

  TYPES:
    "! Motivos de bloqueio do item (RSEG-SPGR*): 'X' = bloqueado.
    BEGIN OF ty_blocks,
      spgrp TYPE c LENGTH 1,
      spgrm TYPE c LENGTH 1,
      spgrt TYPE c LENGTH 1,
      spgrg TYPE c LENGTH 1,
      spgrq TYPE c LENGTH 1,
      spgrs TYPE c LENGTH 1,
      spgrc TYPE c LENGTH 1,
      spgrv TYPE c LENGTH 1,
    END OF ty_blocks.

  TYPES:
    "! Cabeçalho da fatura (RBKP). FOUND = abap_false quando o documento não existe.
    BEGIN OF ty_header,
      found       TYPE abap_bool,
      belnr       TYPE ty_belnr,
      gjahr       TYPE ty_gjahr,
      bukrs       TYPE ty_bukrs,
      lifnr       TYPE ty_lifnr,
      vendor_name TYPE string,
      rmwwr       TYPE p LENGTH 13 DECIMALS 2,
      waers       TYPE c LENGTH 5,
      budat       TYPE d,
      due_date    TYPE d,
      rbstat      TYPE c LENGTH 1,
      parked      TYPE abap_bool,
      zlspr       TYPE c LENGTH 1,
      zlspr_text  TYPE string,
    END OF ty_header.

  TYPES:
    "! Item da fatura (RSEG). MEINS já na unidade externa (ex.: PC).
    BEGIN OF ty_item,
      buzei  TYPE n LENGTH 6,
      ebeln  TYPE ty_ebeln,
      ebelp  TYPE ty_ebelp,
      werks  TYPE ty_werks,
      menge  TYPE p LENGTH 13 DECIMALS 3,
      meins  TYPE c LENGTH 3,
      wrbtr  TYPE p LENGTH 13 DECIMALS 2,
      blocks TYPE ty_blocks,
    END OF ty_item,
    ty_items TYPE STANDARD TABLE OF ty_item WITH DEFAULT KEY.

  TYPES:
    "! Histórico do item do pedido (EKBE): VGABE '1' = entrada de mercadoria, '2' = fatura.
    "! SHKZG 'S' = débito, 'H' = crédito (estorno/devolução/nota de crédito).
    BEGIN OF ty_history_line,
      vgabe TYPE c LENGTH 1,
      shkzg TYPE c LENGTH 1,
      belnr TYPE ty_belnr,
      menge TYPE p LENGTH 13 DECIMALS 3,
      meins TYPE c LENGTH 3,
      budat TYPE d,
    END OF ty_history_line,
    ty_history TYPE STANDARD TABLE OF ty_history_line WITH DEFAULT KEY.

  TYPES:
    "! Item do pedido (EKPO): preço líquido NETPR por PEINH unidades de BPRME;
    "! EINDT = primeira data de remessa (EKET).
    BEGIN OF ty_po_item,
      found TYPE abap_bool,
      ebeln TYPE ty_ebeln,
      ebelp TYPE ty_ebelp,
      netpr TYPE p LENGTH 13 DECIMALS 2,
      peinh TYPE p LENGTH 5 DECIMALS 0,
      bprme TYPE c LENGTH 3,
      waers TYPE c LENGTH 5,
      eindt TYPE d,
    END OF ty_po_item.

  TYPES:
    "! Tolerância de verificação de faturas (T169G): PROZ1 = limite superior em %.
    BEGIN OF ty_tolerance,
      found TYPE abap_bool,
      bukrs TYPE ty_bukrs,
      tolsl TYPE ty_tolsl,
      proz1 TYPE p LENGTH 5 DECIMALS 2,
    END OF ty_tolerance.

  TYPES:
    "! Partida do fornecedor na FI (BSIK). FOUND = abap_false se não há partida em aberto.
    BEGIN OF ty_vendor_item,
      found    TYPE abap_bool,
      zlspr    TYPE c LENGTH 1,
      due_date TYPE d,
    END OF ty_vendor_item.

  TYPES:
    "! Fatura pendente (bloqueada ou estacionada) para a lista do MM-10.
    "! BLOCKS = motivos de bloqueio de todos os itens; EBELN = pedido do primeiro item.
    BEGIN OF ty_pending,
      belnr       TYPE ty_belnr,
      gjahr       TYPE ty_gjahr,
      bukrs       TYPE ty_bukrs,
      lifnr       TYPE ty_lifnr,
      vendor_name TYPE string,
      rmwwr       TYPE p LENGTH 13 DECIMALS 2,
      waers       TYPE c LENGTH 5,
      budat       TYPE d,
      due_date    TYPE d,
      parked      TYPE abap_bool,
      zlspr       TYPE c LENGTH 1,
      ebeln       TYPE ty_ebeln,
      blocks      TYPE ty_blocks,
    END OF ty_pending,
    ty_pendings TYPE STANDARD TABLE OF ty_pending WITH DEFAULT KEY.

  "! Cabeçalho da fatura (RBKP) com fornecedor, texto do bloqueio e vencimento.
  METHODS read_header
    IMPORTING iv_belnr         TYPE ty_belnr
              iv_gjahr         TYPE ty_gjahr
    RETURNING VALUE(rs_header) TYPE ty_header.

  "! Itens da fatura (RSEG) com os motivos de bloqueio, em ordem de item.
  METHODS read_items
    IMPORTING iv_belnr        TYPE ty_belnr
              iv_gjahr        TYPE ty_gjahr
    RETURNING VALUE(rt_items) TYPE ty_items.

  "! Entradas de mercadoria e faturas de um item do pedido (EKBE, VGABE 1 e 2).
  METHODS read_history
    IMPORTING iv_ebeln          TYPE ty_ebeln
              iv_ebelp          TYPE ty_ebelp
    RETURNING VALUE(rt_history) TYPE ty_history.

  "! Preço e data de remessa do item do pedido (EKPO, EKET).
  METHODS read_po_item
    IMPORTING iv_ebeln          TYPE ty_ebeln
              iv_ebelp          TYPE ty_ebelp
    RETURNING VALUE(rs_po_item) TYPE ty_po_item.

  "! Tolerância da empresa para uma chave (ex.: PP = variação de preço).
  METHODS read_tolerance
    IMPORTING iv_bukrs            TYPE ty_bukrs
              iv_tolsl            TYPE ty_tolsl
    RETURNING VALUE(rs_tolerance) TYPE ty_tolerance.

  "! Partida do fornecedor da fatura lançada (BSIK): bloqueio na FI e vencimento.
  METHODS read_vendor_item
    IMPORTING iv_belnr              TYPE ty_belnr
              iv_gjahr              TYPE ty_gjahr
              iv_bukrs              TYPE ty_bukrs
              iv_lifnr              TYPE ty_lifnr
    RETURNING VALUE(rs_vendor_item) TYPE ty_vendor_item.

  "! Faturas bloqueadas e/ou estacionadas (não estornadas). IV_STATE: 'BLOCKED', 'PARKED'
  "! ou vazio (ambas). IV_LIMIT limita a leitura; a ordenação e a paginação são do diagnóstico.
  METHODS read_pending
    IMPORTING iv_bukrs          TYPE ty_bukrs OPTIONAL
              iv_state          TYPE string OPTIONAL
              iv_limit          TYPE i DEFAULT 5000
    RETURNING VALUE(rt_pending) TYPE ty_pendings.

  "! Autorização de leitura: F_BKPF_BUK (empresa) e, se IV_WERKS vier preenchido,
  "! M_RECH_WRK (centro).
  METHODS is_authorized
    IMPORTING iv_bukrs          TYPE ty_bukrs
              iv_werks          TYPE ty_werks OPTIONAL
    RETURNING VALUE(rv_allowed) TYPE abap_bool.

ENDINTERFACE.
