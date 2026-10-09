*"* Testes do MM-02 com dublê do leitor (cenários do sap-mock, 2026-10-09 como "hoje")
CLASS ltd_reader DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_rx_mm_reader.

    TYPES:
      BEGIN OF ty_item_row,
        belnr TYPE zif_rx_mm_reader=>ty_belnr,
        gjahr TYPE zif_rx_mm_reader=>ty_gjahr,
        item  TYPE zif_rx_mm_reader=>ty_item,
      END OF ty_item_row.
    TYPES:
      BEGIN OF ty_history_row,
        ebeln TYPE zif_rx_mm_reader=>ty_ebeln,
        ebelp TYPE zif_rx_mm_reader=>ty_ebelp,
        line  TYPE zif_rx_mm_reader=>ty_history_line,
      END OF ty_history_row.
    TYPES:
      BEGIN OF ty_vendor_row,
        belnr TYPE zif_rx_mm_reader=>ty_belnr,
        gjahr TYPE zif_rx_mm_reader=>ty_gjahr,
        item  TYPE zif_rx_mm_reader=>ty_vendor_item,
      END OF ty_vendor_row.

    DATA mt_headers TYPE STANDARD TABLE OF zif_rx_mm_reader=>ty_header WITH DEFAULT KEY.
    DATA mt_items TYPE STANDARD TABLE OF ty_item_row WITH DEFAULT KEY.
    DATA mt_history TYPE STANDARD TABLE OF ty_history_row WITH DEFAULT KEY.
    DATA mt_po_items TYPE STANDARD TABLE OF zif_rx_mm_reader=>ty_po_item WITH DEFAULT KEY.
    DATA mt_tolerances TYPE STANDARD TABLE OF zif_rx_mm_reader=>ty_tolerance WITH DEFAULT KEY.
    DATA mt_vendor_items TYPE STANDARD TABLE OF ty_vendor_row WITH DEFAULT KEY.
    DATA mv_company_allowed TYPE abap_bool VALUE abap_true.
    DATA mv_denied_plant TYPE zif_rx_mm_reader=>ty_werks.

    METHODS add_invoice
      IMPORTING is_header TYPE zif_rx_mm_reader=>ty_header.
    METHODS add_item
      IMPORTING iv_belnr TYPE zif_rx_mm_reader=>ty_belnr
                is_item  TYPE zif_rx_mm_reader=>ty_item.
    METHODS add_history
      IMPORTING iv_ebeln TYPE zif_rx_mm_reader=>ty_ebeln
                iv_vgabe TYPE c
                iv_menge TYPE i
                iv_budat TYPE d OPTIONAL
                iv_shkzg TYPE c DEFAULT 'S'.
ENDCLASS.

CLASS ltd_reader IMPLEMENTATION.

  METHOD add_invoice.
    APPEND is_header TO mt_headers.
  ENDMETHOD.

  METHOD add_item.
    DATA ls_row TYPE ty_item_row.

    ls_row-belnr = iv_belnr.
    ls_row-gjahr = '2026'.
    ls_row-item = is_item.
    APPEND ls_row TO mt_items.
  ENDMETHOD.

  METHOD add_history.
    DATA ls_row TYPE ty_history_row.

    ls_row-ebeln = iv_ebeln.
    ls_row-ebelp = '00010'.
    ls_row-line-vgabe = iv_vgabe.
    ls_row-line-shkzg = iv_shkzg.
    ls_row-line-menge = iv_menge.
    ls_row-line-meins = 'PC'.
    ls_row-line-budat = iv_budat.
    APPEND ls_row TO mt_history.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~read_header.
    READ TABLE mt_headers INTO rs_header WITH KEY belnr = iv_belnr gjahr = iv_gjahr.
    IF sy-subrc <> 0.
      CLEAR rs_header.
    ENDIF.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~read_items.
    DATA ls_row TYPE ty_item_row.

    LOOP AT mt_items INTO ls_row WHERE belnr = iv_belnr AND gjahr = iv_gjahr.
      APPEND ls_row-item TO rt_items.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~read_history.
    DATA ls_row TYPE ty_history_row.

    LOOP AT mt_history INTO ls_row WHERE ebeln = iv_ebeln AND ebelp = iv_ebelp.
      APPEND ls_row-line TO rt_history.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~read_po_item.
    READ TABLE mt_po_items INTO rs_po_item WITH KEY ebeln = iv_ebeln ebelp = iv_ebelp.
    IF sy-subrc <> 0.
      CLEAR rs_po_item.
    ENDIF.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~read_tolerance.
    READ TABLE mt_tolerances INTO rs_tolerance WITH KEY bukrs = iv_bukrs tolsl = iv_tolsl.
    IF sy-subrc <> 0.
      CLEAR rs_tolerance.
    ENDIF.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~read_vendor_item.
    DATA ls_row TYPE ty_vendor_row.

    READ TABLE mt_vendor_items INTO ls_row WITH KEY belnr = iv_belnr gjahr = iv_gjahr.
    IF sy-subrc = 0.
      rs_vendor_item = ls_row-item.
    ENDIF.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~read_pending.
    CLEAR rt_pending.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~is_authorized.
    IF mv_company_allowed = abap_false.
      RETURN.
    ENDIF.
    IF iv_werks IS NOT INITIAL AND iv_werks = mv_denied_plant.
      RETURN.
    ENDIF.
    rv_allowed = abap_true.
  ENDMETHOD.

ENDCLASS.


CLASS ltc_mm02 DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_reader TYPE REF TO ltd_reader.
    DATA mo_cut TYPE REF TO zif_rx_diagnostic.

    METHODS setup.
    METHODS add_scenario_price.
    METHODS add_scenario_quantity.
    METHODS add_scenario_released.
    METHODS add_scenario_parked.
    METHODS add_scenario_date.
    METHODS header
      IMPORTING iv_belnr         TYPE zif_rx_mm_reader=>ty_belnr
                iv_lifnr         TYPE zif_rx_mm_reader=>ty_lifnr
                iv_name          TYPE string
                iv_amount        TYPE i
                iv_budat         TYPE d
                iv_due           TYPE d
                iv_zlspr         TYPE c OPTIONAL
      RETURNING VALUE(rs_header) TYPE zif_rx_mm_reader=>ty_header.
    METHODS item
      IMPORTING iv_ebeln       TYPE zif_rx_mm_reader=>ty_ebeln
                iv_amount      TYPE i
      RETURNING VALUE(rs_item) TYPE zif_rx_mm_reader=>ty_item.
    METHODS params
      IMPORTING iv_document      TYPE string
                iv_year          TYPE string DEFAULT '2026'
      RETURNING VALUE(rt_params) TYPE zif_rx_types=>ty_params.
    METHODS run
      IMPORTING iv_document      TYPE string
      RETURNING VALUE(rs_result) TYPE zif_rx_types=>ty_result
      RAISING   zcx_rx_error.
    METHODS codes
      IMPORTING is_result       TYPE zif_rx_types=>ty_result
      RETURNING VALUE(rv_codes) TYPE string.
    METHODS finding
      IMPORTING is_result         TYPE zif_rx_types=>ty_result
                iv_code           TYPE string
      RETURNING VALUE(rs_finding) TYPE zif_rx_types=>ty_finding.
    METHODS fact
      IMPORTING is_result       TYPE zif_rx_types=>ty_result
                iv_id           TYPE string
      RETURNING VALUE(rv_value) TYPE string.
    METHODS evidence
      IMPORTING is_finding         TYPE zif_rx_types=>ty_finding
                iv_index           TYPE i
      RETURNING VALUE(rs_evidence) TYPE zif_rx_types=>ty_evidence.
    METHODS param_meta
      IMPORTING is_meta         TYPE zif_rx_types=>ty_diag_meta
                iv_index        TYPE i
      RETURNING VALUE(rs_param) TYPE zif_rx_types=>ty_param_meta.
    METHODS related
      IMPORTING is_result         TYPE zif_rx_types=>ty_result
                iv_index          TYPE i
      RETURNING VALUE(rs_related) TYPE zif_rx_types=>ty_object_ref.
    METHODS assert_codes
      IMPORTING iv_document TYPE string
                iv_status   TYPE string
                iv_codes    TYPE string
      RAISING   zcx_rx_error.

    METHODS metadata FOR TESTING.
    METHODS price_block FOR TESTING RAISING zcx_rx_error.
    METHODS price_block_details FOR TESTING RAISING zcx_rx_error.
    METHODS quantity_block FOR TESTING RAISING zcx_rx_error.
    METHODS quantity_block_details FOR TESTING RAISING zcx_rx_error.
    METHODS not_blocked FOR TESTING RAISING zcx_rx_error.
    METHODS parked FOR TESTING RAISING zcx_rx_error.
    METHODS date_block FOR TESTING RAISING zcx_rx_error.
    METHODS not_found FOR TESTING RAISING zcx_rx_error.
    METHODS leading_zeros FOR TESTING RAISING zcx_rx_error.
    METHODS facts FOR TESTING RAISING zcx_rx_error.
    METHODS related_order FOR TESTING RAISING zcx_rx_error.
    METHODS fi_block_other_key FOR TESTING RAISING zcx_rx_error.
    METHODS fi_block_same_key FOR TESTING RAISING zcx_rx_error.
    METHODS quantity_covered FOR TESTING RAISING zcx_rx_error.
    METHODS other_reasons_in_order FOR TESTING RAISING zcx_rx_error.
    METHODS not_authorized_company FOR TESTING.
    METHODS not_authorized_plant FOR TESTING.
ENDCLASS.


CLASS ltc_mm02 IMPLEMENTATION.

  METHOD setup.
    DATA lo_diag TYPE REF TO zcl_rx_diag_mm02.

    CREATE OBJECT mo_reader.
    add_scenario_price( ).
    add_scenario_quantity( ).
    add_scenario_released( ).
    add_scenario_parked( ).
    add_scenario_date( ).
    CREATE OBJECT lo_diag EXPORTING io_reader = mo_reader iv_today = '20261009'.
    mo_cut = lo_diag.
  ENDMETHOD.

  METHOD header.
    rs_header-found = abap_true.
    rs_header-belnr = iv_belnr.
    rs_header-gjahr = '2026'.
    rs_header-bukrs = '1000'.
    rs_header-lifnr = iv_lifnr.
    rs_header-vendor_name = iv_name.
    rs_header-rmwwr = iv_amount.
    rs_header-waers = 'BRL'.
    rs_header-budat = iv_budat.
    rs_header-due_date = iv_due.
    rs_header-rbstat = '5'.
    rs_header-zlspr = iv_zlspr.
  ENDMETHOD.

  METHOD item.
    rs_item-buzei = '000001'.
    rs_item-ebeln = iv_ebeln.
    rs_item-ebelp = '00010'.
    rs_item-werks = '1000'.
    rs_item-menge = 100.
    rs_item-meins = 'PC'.
    rs_item-wrbtr = iv_amount.
  ENDMETHOD.

  METHOD add_scenario_price.
    DATA ls_header TYPE zif_rx_mm_reader=>ty_header.
    DATA ls_item TYPE zif_rx_mm_reader=>ty_item.
    DATA ls_po TYPE zif_rx_mm_reader=>ty_po_item.
    DATA ls_tolerance TYPE zif_rx_mm_reader=>ty_tolerance.

    ls_header = header( iv_belnr  = '5105600001'
                        iv_lifnr  = '0000200310'
                        iv_name   = 'Metalúrgica Silva S.A.'
                        iv_amount = 1150
                        iv_budat  = '20261004'
                        iv_due    = '20261011'
                        iv_zlspr  = 'R' ).
    mo_reader->add_invoice( ls_header ).
    ls_item = item( iv_ebeln = '4500017788' iv_amount = 1150 ).
    ls_item-blocks-spgrp = 'X'.
    mo_reader->add_item( iv_belnr = '5105600001' is_item = ls_item ).

    ls_po-found = abap_true.
    ls_po-ebeln = '4500017788'.
    ls_po-ebelp = '00010'.
    ls_po-netpr = 10.
    ls_po-peinh = 1.
    ls_po-bprme = 'PC'.
    ls_po-waers = 'BRL'.
    APPEND ls_po TO mo_reader->mt_po_items.
    mo_reader->add_history( iv_ebeln = '4500017788' iv_vgabe = '1' iv_menge = 100 iv_budat = '20260930' ).
    mo_reader->add_history( iv_ebeln = '4500017788' iv_vgabe = '2' iv_menge = 100 iv_budat = '20261004' ).

    ls_tolerance-found = abap_true.
    ls_tolerance-bukrs = '1000'.
    ls_tolerance-tolsl = 'PP'.
    ls_tolerance-proz1 = 5.
    APPEND ls_tolerance TO mo_reader->mt_tolerances.
  ENDMETHOD.

  METHOD add_scenario_quantity.
    DATA ls_header TYPE zif_rx_mm_reader=>ty_header.
    DATA ls_item TYPE zif_rx_mm_reader=>ty_item.

    ls_header = header( iv_belnr  = '5105600002'
                        iv_lifnr  = '0000200455'
                        iv_name   = 'Plásticos Vale Ltda.'
                        iv_amount = 8400
                        iv_budat  = '20261001'
                        iv_due    = '20261008' ).
    mo_reader->add_invoice( ls_header ).
    ls_item = item( iv_ebeln = '4500017790' iv_amount = 8400 ).
    ls_item-blocks-spgrm = 'X'.
    mo_reader->add_item( iv_belnr = '5105600002' is_item = ls_item ).
    mo_reader->add_history( iv_ebeln = '4500017790' iv_vgabe = '1' iv_menge = 80 iv_budat = '20260928' ).
    mo_reader->add_history( iv_ebeln = '4500017790' iv_vgabe = '2' iv_menge = 100 iv_budat = '20261001' ).
  ENDMETHOD.

  METHOD add_scenario_released.
    DATA ls_header TYPE zif_rx_mm_reader=>ty_header.
    DATA ls_item TYPE zif_rx_mm_reader=>ty_item.

    ls_header = header( iv_belnr  = '5105600003'
                        iv_lifnr  = '0000200310'
                        iv_name   = 'Metalúrgica Silva S.A.'
                        iv_amount = 22350
                        iv_budat  = '20260929'
                        iv_due    = '20261029' ).
    mo_reader->add_invoice( ls_header ).
    ls_item = item( iv_ebeln = '4500017701' iv_amount = 22350 ).
    mo_reader->add_item( iv_belnr = '5105600003' is_item = ls_item ).
  ENDMETHOD.

  METHOD add_scenario_parked.
    DATA ls_header TYPE zif_rx_mm_reader=>ty_header.
    DATA ls_item TYPE zif_rx_mm_reader=>ty_item.

    ls_header = header( iv_belnr  = '5105600004'
                        iv_lifnr  = '0000200612'
                        iv_name   = 'Transportes Rápido Sul'
                        iv_amount = 3980
                        iv_budat  = '20261007'
                        iv_due    = '20261022' ).
    ls_header-rbstat = 'A'.
    ls_header-parked = abap_true.
    mo_reader->add_invoice( ls_header ).
    ls_item = item( iv_ebeln = '4500017812' iv_amount = 3980 ).
    mo_reader->add_item( iv_belnr = '5105600004' is_item = ls_item ).
  ENDMETHOD.

  METHOD add_scenario_date.
    DATA ls_header TYPE zif_rx_mm_reader=>ty_header.
    DATA ls_item TYPE zif_rx_mm_reader=>ty_item.
    DATA ls_po TYPE zif_rx_mm_reader=>ty_po_item.

    ls_header = header( iv_belnr  = '5105600005'
                        iv_lifnr  = '0000200455'
                        iv_name   = 'Plásticos Vale Ltda.'
                        iv_amount = 15720
                        iv_budat  = '20261006'
                        iv_due    = '20261013'
                        iv_zlspr  = 'R' ).
    mo_reader->add_invoice( ls_header ).
    ls_item = item( iv_ebeln = '4500017795' iv_amount = 15720 ).
    ls_item-blocks-spgrt = 'X'.
    mo_reader->add_item( iv_belnr = '5105600005' is_item = ls_item ).

    ls_po-found = abap_true.
    ls_po-ebeln = '4500017795'.
    ls_po-ebelp = '00010'.
    ls_po-netpr = '157.20'.
    ls_po-peinh = 1.
    ls_po-bprme = 'PC'.
    ls_po-waers = 'BRL'.
    ls_po-eindt = '20261018'.
    APPEND ls_po TO mo_reader->mt_po_items.
    " Entrada em 2026-10-06, 12 dias antes da remessa prevista (2026-10-18).
    mo_reader->add_history( iv_ebeln = '4500017795' iv_vgabe = '1' iv_menge = 100 iv_budat = '20261006' ).
    mo_reader->add_history( iv_ebeln = '4500017795' iv_vgabe = '2' iv_menge = 100 iv_budat = '20261006' ).
  ENDMETHOD.

  METHOD params.
    DATA ls_param TYPE zif_rx_types=>ty_param.

    ls_param-name = 'invoiceDocument'.
    ls_param-value = iv_document.
    APPEND ls_param TO rt_params.
    ls_param-name = 'fiscalYear'.
    ls_param-value = iv_year.
    APPEND ls_param TO rt_params.
  ENDMETHOD.

  METHOD run.
    rs_result = mo_cut->execute( params( iv_document ) ).
  ENDMETHOD.

  METHOD codes.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.

    LOOP AT is_result-findings INTO ls_finding.
      IF rv_codes IS INITIAL.
        rv_codes = ls_finding-code.
      ELSE.
        CONCATENATE rv_codes ',' ls_finding-code INTO rv_codes.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD finding.
    LOOP AT is_result-findings INTO rs_finding WHERE code = iv_code.
      RETURN.
    ENDLOOP.
    cl_abap_unit_assert=>fail( msg = 'Achado não encontrado' detail = iv_code ).
  ENDMETHOD.

  METHOD fact.
    DATA ls_fact TYPE zif_rx_types=>ty_fact.

    LOOP AT is_result-facts INTO ls_fact WHERE id = iv_id.
      rv_value = ls_fact-value.
      RETURN.
    ENDLOOP.
    cl_abap_unit_assert=>fail( msg = 'Fato não encontrado' detail = iv_id ).
  ENDMETHOD.

  METHOD evidence.
    READ TABLE is_finding-evidence INDEX iv_index INTO rs_evidence. "#EC CI_SUBRC
  ENDMETHOD.

  METHOD param_meta.
    READ TABLE is_meta-params INDEX iv_index INTO rs_param. "#EC CI_SUBRC
  ENDMETHOD.

  METHOD related.
    READ TABLE is_result-related INDEX iv_index INTO rs_related. "#EC CI_SUBRC
  ENDMETHOD.

  METHOD assert_codes.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_document ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = iv_status ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = iv_codes ).
  ENDMETHOD.

  METHOD metadata.
    DATA ls_meta TYPE zif_rx_types=>ty_diag_meta.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.

    ls_meta = mo_cut->get_metadata( ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-id exp = 'MM-02' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-version exp = '1.0' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-module exp = 'MM' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-kind exp = 'OBJECT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-title exp = 'Fatura de fornecedor bloqueada para pagamento' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_meta-params ) exp = 2 ).
    ls_param = param_meta( is_meta = ls_meta iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-name exp = 'invoiceDocument' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Documento de faturamento (MIRO)' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'DOCUMENT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-required exp = abap_true ).
    ls_param = param_meta( is_meta = ls_meta iv_index = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-name exp = 'fiscalYear' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Exercício' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'INTEGER' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-required exp = abap_true ).
    cl_abap_unit_assert=>assert_initial( ls_param-options ).
  ENDMETHOD.

  METHOD price_block.
    assert_codes( iv_document = '5105600001'
                  iv_status   = 'PROBLEM_FOUND'
                  iv_codes    = 'MM02.PAYMENT_BLOCK,MM02.BLOCK_PRICE,MM02.PRICE_DIFF,MM02.TOLERANCE_INFO' ).
  ENDMETHOD.

  METHOD price_block_details.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    ls_result = run( '5105600001' ).

    ls_finding = finding( is_result = ls_result iv_code = 'MM02.PAYMENT_BLOCK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'MRBR' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'RBKP' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'ZLSPR' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = 'R' ).

    ls_finding = finding( is_result = ls_result iv_code = 'MM02.BLOCK_PRICE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title exp = 'Item 1 bloqueado por preço' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'RSEG' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'SPGRP' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = 'X' ).

    ls_finding = finding( is_result = ls_result iv_code = 'MM02.PRICE_DIFF' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title exp = 'Divergência de preço de 15%' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-detail
                                        exp = 'Pedido: R$ 10,00/PC. Fatura: R$ 11,50/PC (+15%), para 100 PC.' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'ME23N' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_finding-evidence ) exp = 2 ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'EKPO' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'NETPR' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '10,00' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-label exp = 'Preço do pedido 4500017788/10' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'RSEG' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'WRBTR' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '1.150,00' ).

    ls_finding = finding( is_result = ls_result iv_code = 'MM02.TOLERANCE_INFO' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'INFO' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title exp = 'Tolerância de preço excedida' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = 'A chave de tolerância PP da empresa 1000 permite até 5% acima do preço do pedido.' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'T169G' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'PROZ1' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '5,00' ).
  ENDMETHOD.

  METHOD quantity_block.
    assert_codes( iv_document = '5105600002'
                  iv_status   = 'PROBLEM_FOUND'
                  iv_codes    = 'MM02.BLOCK_QUANTITY,MM02.GR_MISSING' ).
  ENDMETHOD.

  METHOD quantity_block_details.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    ls_result = run( '5105600002' ).
    ls_finding = finding( is_result = ls_result iv_code = 'MM02.GR_MISSING' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = 'Recebido: 80 PC. Faturado: 100 PC. Faltam 20 PC de entrada de mercadoria no pedido 4500017790/10.' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'MIGO' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-description
                                        exp = 'Lançar a entrada de mercadoria dos 20 PC restantes' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_finding-evidence ) exp = 2 ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'EKBE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '80' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '100' ).
    ls_finding = finding( is_result = ls_result iv_code = 'MM02.BLOCK_QUANTITY' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'MRBR' ).
  ENDMETHOD.

  METHOD not_blocked.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.

    assert_codes( iv_document = '5105600003' iv_status = 'OK' iv_codes = 'MM02.NOT_BLOCKED' ).
    ls_result = run( '5105600003' ).
    ls_finding = finding( is_result = ls_result iv_code = 'MM02.NOT_BLOCKED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'INFO' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'FBL1N' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'state' ) exp = 'Liberada' ).
  ENDMETHOD.

  METHOD parked.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    assert_codes( iv_document = '5105600004' iv_status = 'PROBLEM_FOUND' iv_codes = 'MM02.PARKED' ).
    ls_result = run( '5105600004' ).
    ls_finding = finding( is_result = ls_result iv_code = 'MM02.PARKED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'WARNING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'MIR4' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'RBSTAT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = 'A' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'state' ) exp = 'Estacionada' ).
  ENDMETHOD.

  METHOD date_block.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    assert_codes( iv_document = '5105600005'
                  iv_status   = 'PROBLEM_FOUND'
                  iv_codes    = 'MM02.PAYMENT_BLOCK,MM02.BLOCK_DATE' ).
    ls_result = run( '5105600005' ).
    ls_finding = finding( is_result = ls_result iv_code = 'MM02.BLOCK_DATE' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = 'A mercadoria foi entregue 12 dias antes da data prevista no pedido 4500017795, acima da tolerância.' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'SPGRT' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'EKET' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'EINDT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '2026-10-18' ).
  ENDMETHOD.

  METHOD not_found.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    assert_codes( iv_document = '5199999999' iv_status = 'NOT_FOUND' iv_codes = 'MM02.NOT_FOUND' ).
    ls_result = run( '5199999999' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-kind exp = 'SUPPLIER_INVOICE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '5199999999/2026' ).
    ls_finding = finding( is_result = ls_result iv_code = 'MM02.NOT_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'INFO' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = 'O documento 5199999999 do exercício 2026 não existe na verificação de faturas (RBKP).' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'RBKP' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'BELNR' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '5199999999' ).
    cl_abap_unit_assert=>assert_initial( ls_result-facts ).
  ENDMETHOD.

  METHOD leading_zeros.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    " Documento com zeros à esquerda e exercício informado: mesmo resultado.
    ls_result = run( '00005105600001' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '5105600001/2026' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
  ENDMETHOD.

  METHOD facts.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_fact TYPE zif_rx_types=>ty_fact.
    DATA lv_ids TYPE string.

    ls_result = run( '5105600001' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-kind exp = 'SUPPLIER_INVOICE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '5105600001/2026' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'vendor' )
                                        exp = '200310 · Metalúrgica Silva S.A.' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'grossAmount' )
                                        exp = 'R$ 1.150,00' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'state' ) exp = 'Bloqueada' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'purchaseOrder' )
                                        exp = '4500017788' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'postingDate' )
                                        exp = '2026-10-04' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'dueDate' ) exp = '2026-10-11' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'companyCode' ) exp = '1000' ).
    " Ordem dos fatos igual à do simulador.
    LOOP AT ls_result-facts INTO ls_fact.
      IF lv_ids IS INITIAL.
        lv_ids = ls_fact-id.
      ELSE.
        CONCATENATE lv_ids ',' ls_fact-id INTO lv_ids.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals(
      act = lv_ids
      exp = 'vendor,grossAmount,state,purchaseOrder,postingDate,dueDate,companyCode' ).
  ENDMETHOD.

  METHOD related_order.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_related TYPE zif_rx_types=>ty_object_ref.

    ls_result = run( '5105600001' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-related ) exp = 1 ).
    ls_related = related( is_result = ls_result iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_related-kind exp = 'PURCHASE_ORDER' ).
    cl_abap_unit_assert=>assert_equals( act = ls_related-id exp = '4500017788' ).
    " Sem bloqueio nos itens, não há pedido relacionado.
    ls_result = run( '5105600003' ).
    cl_abap_unit_assert=>assert_initial( ls_result-related ).
  ENDMETHOD.

  METHOD fi_block_other_key.
    DATA ls_row TYPE ltd_reader=>ty_vendor_row.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    " Fatura sem bloqueio no cabeçalho, mas com a partida bloqueada na FI (chave A).
    ls_row-belnr = '5105600003'.
    ls_row-gjahr = '2026'.
    ls_row-item-found = abap_true.
    ls_row-item-zlspr = 'A'.
    ls_row-item-due_date = '20261105'.
    APPEND ls_row TO mo_reader->mt_vendor_items.

    ls_result = run( '5105600003' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'MM02.FI_PAYMENT_BLOCK' ).
    ls_finding = finding( is_result = ls_result iv_code = 'MM02.FI_PAYMENT_BLOCK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'BSIK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'ZLSPR' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = 'A' ).
    " O vencimento vem da partida do fornecedor.
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'dueDate' ) exp = '2026-11-05' ).
  ENDMETHOD.

  METHOD fi_block_same_key.
    DATA ls_row TYPE ltd_reader=>ty_vendor_row.

    " Mesma chave do cabeçalho: o MM02.PAYMENT_BLOCK já cobre, sem achado duplicado.
    ls_row-belnr = '5105600005'.
    ls_row-gjahr = '2026'.
    ls_row-item-found = abap_true.
    ls_row-item-zlspr = 'R'.
    APPEND ls_row TO mo_reader->mt_vendor_items.
    assert_codes( iv_document = '5105600005'
                  iv_status   = 'PROBLEM_FOUND'
                  iv_codes    = 'MM02.PAYMENT_BLOCK,MM02.BLOCK_DATE' ).
  ENDMETHOD.

  METHOD quantity_covered.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.

    " Entrada de 20 PC lançada depois: as entradas (100) cobrem as faturas (100).
    mo_reader->add_history( iv_ebeln = '4500017790' iv_vgabe = '1' iv_menge = 20 iv_budat = '20261005' ).
    ls_result = run( '5105600002' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'MM02.BLOCK_QUANTITY,MM02.QTY_DIFF' ).
    ls_finding = finding( is_result = ls_result iv_code = 'MM02.QTY_DIFF' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'MRBR' ).
  ENDMETHOD.

  METHOD other_reasons_in_order.
    DATA ls_item TYPE zif_rx_mm_reader=>ty_item.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    " Vários motivos no mesmo item saem na ordem do catálogo (SPGRP ... SPGRV).
    CLEAR mo_reader->mt_items.
    ls_item = item( iv_ebeln = '4500017701' iv_amount = 22350 ).
    ls_item-blocks-spgrv = 'X'.
    ls_item-blocks-spgrc = 'X'.
    ls_item-blocks-spgrs = 'X'.
    ls_item-blocks-spgrq = 'X'.
    ls_item-blocks-spgrg = 'X'.
    mo_reader->add_item( iv_belnr = '5105600003' is_item = ls_item ).
    ls_result = run( '5105600003' ).
    cl_abap_unit_assert=>assert_equals(
      act = codes( ls_result )
      exp = 'MM02.BLOCK_PRICE_QTY,MM02.BLOCK_MANUAL,MM02.BLOCK_AMOUNT,MM02.BLOCK_QUALITY,MM02.BLOCK_PROJECT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
  ENDMETHOD.

  METHOD not_authorized_company.
    DATA lx_error TYPE REF TO zcx_rx_error.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    mo_reader->mv_company_allowed = abap_false.
    TRY.
        ls_result = run( '5105600001' ).
        cl_abap_unit_assert=>fail( msg = 'Esperava erro 403' ).
      CATCH zcx_rx_error INTO lx_error.
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_http_status exp = 403 ).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'NOT_AUTHORIZED' ).
    ENDTRY.
  ENDMETHOD.

  METHOD not_authorized_plant.
    DATA lx_error TYPE REF TO zcx_rx_error.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    mo_reader->mv_denied_plant = '1000'.
    TRY.
        ls_result = run( '5105600001' ).
        cl_abap_unit_assert=>fail( msg = 'Esperava erro 403' ).
      CATCH zcx_rx_error INTO lx_error.
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_http_status exp = 403 ).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'NOT_AUTHORIZED' ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
