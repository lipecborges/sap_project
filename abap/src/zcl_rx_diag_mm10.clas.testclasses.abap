*"* Testes do MM-10 com dublê do leitor (cenários do sap-mock, 2026-10-09 como "hoje")
CLASS ltd_reader DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_rx_mm_reader.

    DATA mt_pending TYPE zif_rx_mm_reader=>ty_pendings.
    DATA mt_denied TYPE STANDARD TABLE OF zif_rx_mm_reader=>ty_bukrs WITH DEFAULT KEY.
ENDCLASS.

CLASS ltd_reader IMPLEMENTATION.

  METHOD zif_rx_mm_reader~read_header.
    CLEAR rs_header.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~read_items.
    CLEAR rt_items.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~read_history.
    CLEAR rt_history.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~read_po_item.
    CLEAR rs_po_item.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~read_tolerance.
    CLEAR rs_tolerance.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~read_vendor_item.
    CLEAR rs_vendor_item.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~read_pending.
    DATA ls_pending TYPE zif_rx_mm_reader=>ty_pending.

    " Imita a seleção do leitor real: filtro por empresa e por situação.
    LOOP AT mt_pending INTO ls_pending.
      IF iv_bukrs IS NOT INITIAL AND ls_pending-bukrs <> iv_bukrs.
        CONTINUE.
      ENDIF.
      IF iv_state = 'PARKED' AND ls_pending-parked = abap_false.
        CONTINUE.
      ENDIF.
      IF iv_state = 'BLOCKED' AND ls_pending-parked = abap_true.
        CONTINUE.
      ENDIF.
      APPEND ls_pending TO rt_pending.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_rx_mm_reader~is_authorized.
    READ TABLE mt_denied WITH KEY table_line = iv_bukrs TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      rv_allowed = abap_true.
    ENDIF.
  ENDMETHOD.

ENDCLASS.


CLASS ltc_mm10 DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_reader TYPE REF TO ltd_reader.
    DATA mo_cut TYPE REF TO zif_rx_diagnostic.

    METHODS setup.
    METHODS pending
      IMPORTING iv_belnr          TYPE zif_rx_mm_reader=>ty_belnr
                iv_lifnr          TYPE zif_rx_mm_reader=>ty_lifnr
                iv_name           TYPE string
                iv_amount         TYPE i
                iv_due            TYPE d
                iv_ebeln          TYPE zif_rx_mm_reader=>ty_ebeln
      RETURNING VALUE(rs_pending) TYPE zif_rx_mm_reader=>ty_pending.
    METHODS add
      IMPORTING is_pending TYPE zif_rx_mm_reader=>ty_pending.
    METHODS param
      IMPORTING iv_name   TYPE string
                iv_value  TYPE string
      CHANGING  ct_params TYPE zif_rx_types=>ty_params.
    METHODS run
      IMPORTING it_params        TYPE zif_rx_types=>ty_params
      RETURNING VALUE(rs_result) TYPE zif_rx_types=>ty_result
      RAISING   zcx_rx_error.
    METHODS codes
      IMPORTING is_result       TYPE zif_rx_types=>ty_result
      RETURNING VALUE(rv_codes) TYPE string.
    METHODS invoices
      IMPORTING is_result        TYPE zif_rx_types=>ty_result
      RETURNING VALUE(rv_values) TYPE string.
    METHODS fact
      IMPORTING is_result       TYPE zif_rx_types=>ty_result
                iv_id           TYPE string
      RETURNING VALUE(rv_value) TYPE string.
    METHODS has_fact
      IMPORTING is_result     TYPE zif_rx_types=>ty_result
                iv_id         TYPE string
      RETURNING VALUE(rv_has) TYPE abap_bool.
    METHODS row
      IMPORTING is_result     TYPE zif_rx_types=>ty_result
                iv_index      TYPE i
      RETURNING VALUE(rt_row) TYPE string_table.
    METHODS cell
      IMPORTING it_row         TYPE string_table
                iv_index       TYPE i
      RETURNING VALUE(rv_text) TYPE string.

    METHODS metadata FOR TESTING.
    METHODS full_list FOR TESTING RAISING zcx_rx_error.
    METHODS facts_and_states FOR TESTING RAISING zcx_rx_error.
    METHODS table_keys_and_row FOR TESTING RAISING zcx_rx_error.
    METHODS overdue_finding FOR TESTING RAISING zcx_rx_error.
    METHODS filter_parked FOR TESTING RAISING zcx_rx_error.
    METHODS filter_blocked FOR TESTING RAISING zcx_rx_error.
    METHODS filter_company FOR TESTING RAISING zcx_rx_error.
    METHODS paging FOR TESTING RAISING zcx_rx_error.
    METHODS empty_list FOR TESTING RAISING zcx_rx_error.
    METHODS several_currencies FOR TESTING RAISING zcx_rx_error.
    METHODS reason_texts FOR TESTING RAISING zcx_rx_error.
    METHODS skips_unauthorized_companies FOR TESTING RAISING zcx_rx_error.
    METHODS not_authorized_company FOR TESTING.
ENDCLASS.


CLASS ltc_mm10 IMPLEMENTATION.

  METHOD setup.
    DATA lo_diag TYPE REF TO zcl_rx_diag_mm10.
    DATA ls_pending TYPE zif_rx_mm_reader=>ty_pending.

    CREATE OBJECT mo_reader.

    " 5105600001: bloqueada por preço, vence em 2026-10-11.
    ls_pending = pending( iv_belnr  = '5105600001'
                          iv_lifnr  = '0000200310'
                          iv_name   = 'Metalúrgica Silva S.A.'
                          iv_amount = 1150
                          iv_due    = '20261011'
                          iv_ebeln  = '4500017788' ).
    ls_pending-zlspr = 'R'.
    ls_pending-blocks-spgrp = 'X'.
    add( ls_pending ).

    " 5105600002: bloqueada por quantidade, vencida em 2026-10-08.
    ls_pending = pending( iv_belnr  = '5105600002'
                          iv_lifnr  = '0000200455'
                          iv_name   = 'Plásticos Vale Ltda.'
                          iv_amount = 8400
                          iv_due    = '20261008'
                          iv_ebeln  = '4500017790' ).
    ls_pending-blocks-spgrm = 'X'.
    add( ls_pending ).

    " 5105600004: estacionada, vence em 2026-10-22.
    ls_pending = pending( iv_belnr  = '5105600004'
                          iv_lifnr  = '0000200612'
                          iv_name   = 'Transportes Rápido Sul'
                          iv_amount = 3980
                          iv_due    = '20261022'
                          iv_ebeln  = '4500017812' ).
    ls_pending-parked = abap_true.
    add( ls_pending ).

    " 5105600005: bloqueada por data, vence em 2026-10-13.
    ls_pending = pending( iv_belnr  = '5105600005'
                          iv_lifnr  = '0000200455'
                          iv_name   = 'Plásticos Vale Ltda.'
                          iv_amount = 15720
                          iv_due    = '20261013'
                          iv_ebeln  = '4500017795' ).
    ls_pending-zlspr = 'R'.
    ls_pending-blocks-spgrt = 'X'.
    add( ls_pending ).

    CREATE OBJECT lo_diag EXPORTING io_reader = mo_reader iv_today = '20261009'.
    mo_cut = lo_diag.
  ENDMETHOD.

  METHOD pending.
    rs_pending-belnr = iv_belnr.
    rs_pending-gjahr = '2026'.
    rs_pending-bukrs = '1000'.
    rs_pending-lifnr = iv_lifnr.
    rs_pending-vendor_name = iv_name.
    rs_pending-rmwwr = iv_amount.
    rs_pending-waers = 'BRL'.
    rs_pending-due_date = iv_due.
    rs_pending-ebeln = iv_ebeln.
  ENDMETHOD.

  METHOD add.
    APPEND is_pending TO mo_reader->mt_pending.
  ENDMETHOD.

  METHOD param.
    DATA ls_param TYPE zif_rx_types=>ty_param.

    ls_param-name = iv_name.
    ls_param-value = iv_value.
    APPEND ls_param TO ct_params.
  ENDMETHOD.

  METHOD run.
    rs_result = mo_cut->execute( it_params ).
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

  METHOD invoices.
    DATA lt_row TYPE string_table.
    DATA lv_belnr TYPE string.
    DATA ls_table TYPE zif_rx_types=>ty_table.

    READ TABLE is_result-tables INDEX 1 INTO ls_table.    "#EC CI_SUBRC
    LOOP AT ls_table-rows INTO lt_row.
      lv_belnr = cell( it_row = lt_row iv_index = 1 ).
      IF rv_values IS INITIAL.
        rv_values = lv_belnr.
      ELSE.
        CONCATENATE rv_values ',' lv_belnr INTO rv_values.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD fact.
    DATA ls_fact TYPE zif_rx_types=>ty_fact.

    LOOP AT is_result-facts INTO ls_fact WHERE id = iv_id.
      rv_value = ls_fact-value.
      RETURN.
    ENDLOOP.
    cl_abap_unit_assert=>fail( msg = 'Fato não encontrado' detail = iv_id ).
  ENDMETHOD.

  METHOD has_fact.
    DATA ls_fact TYPE zif_rx_types=>ty_fact.

    LOOP AT is_result-facts INTO ls_fact WHERE id = iv_id.
      rv_has = abap_true.
      RETURN.
    ENDLOOP.
  ENDMETHOD.

  METHOD row.
    DATA ls_table TYPE zif_rx_types=>ty_table.

    READ TABLE is_result-tables INDEX 1 INTO ls_table.    "#EC CI_SUBRC
    READ TABLE ls_table-rows INDEX iv_index INTO rt_row.  "#EC CI_SUBRC
  ENDMETHOD.

  METHOD cell.
    READ TABLE it_row INDEX iv_index INTO rv_text.        "#EC CI_SUBRC
  ENDMETHOD.

  METHOD metadata.
    DATA ls_meta TYPE zif_rx_types=>ty_diag_meta.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.
    DATA lv_option TYPE string.

    ls_meta = mo_cut->get_metadata( ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-id exp = 'MM-10' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-version exp = '1.0' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-module exp = 'MM' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-kind exp = 'LIST' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-title exp = 'Faturas de fornecedor bloqueadas ou pendentes' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_meta-params ) exp = 4 ).

    READ TABLE ls_meta-params INTO ls_param INDEX 1.      "#EC CI_SUBRC
    cl_abap_unit_assert=>assert_equals( act = ls_param-name exp = 'companyCode' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Empresa' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'STRING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-required exp = abap_false ).

    READ TABLE ls_meta-params INTO ls_param INDEX 2.      "#EC CI_SUBRC
    cl_abap_unit_assert=>assert_equals( act = ls_param-name exp = 'state' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Situação' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'ENUM' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-required exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_param-options ) exp = 2 ).
    READ TABLE ls_param-options INTO lv_option INDEX 1.   "#EC CI_SUBRC
    cl_abap_unit_assert=>assert_equals( act = lv_option exp = 'BLOCKED' ).
    READ TABLE ls_param-options INTO lv_option INDEX 2.   "#EC CI_SUBRC
    cl_abap_unit_assert=>assert_equals( act = lv_option exp = 'PARKED' ).

    READ TABLE ls_meta-params INTO ls_param INDEX 3.      "#EC CI_SUBRC
    cl_abap_unit_assert=>assert_equals( act = ls_param-name exp = 'maxRows' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Linhas por página' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'INTEGER' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-required exp = abap_false ).

    READ TABLE ls_meta-params INTO ls_param INDEX 4.      "#EC CI_SUBRC
    cl_abap_unit_assert=>assert_equals( act = ls_param-name exp = 'page' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Página' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'INTEGER' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-required exp = abap_false ).
  ENDMETHOD.

  METHOD full_list.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( lt_params ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-kind exp = 'COMPANY_CODE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '*' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
    " Ordenação por vencimento.
    cl_abap_unit_assert=>assert_equals( act = invoices( ls_result )
                                        exp = '5105600002,5105600001,5105600005,5105600004' ).
  ENDMETHOD.

  METHOD facts_and_states.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_fact TYPE zif_rx_types=>ty_fact.
    DATA lv_ids TYPE string.

    ls_result = run( lt_params ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '4' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'totalAmount' )
                                        exp = 'R$ 29.250,00' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'state:BLOCKED' ) exp = '3' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'state:PARKED' ) exp = '1' ).
    LOOP AT ls_result-facts INTO ls_fact.
      IF lv_ids IS INITIAL.
        lv_ids = ls_fact-id.
      ELSE.
        CONCATENATE lv_ids ',' ls_fact-id INTO lv_ids.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals( act = lv_ids exp = 'total,totalAmount,state:BLOCKED,state:PARKED' ).
  ENDMETHOD.

  METHOD table_keys_and_row.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_table TYPE zif_rx_types=>ty_table.
    DATA lv_keys TYPE string.
    DATA lv_key TYPE string.
    DATA lt_row TYPE string_table.

    ls_result = run( lt_params ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-tables ) exp = 1 ).
    READ TABLE ls_result-tables INTO ls_table INDEX 1.    "#EC CI_SUBRC
    cl_abap_unit_assert=>assert_equals( act = ls_table-id exp = 'invoices' ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-title exp = 'Faturas de fornecedor' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-columns ) exp = 10 ).
    LOOP AT ls_table-keys INTO lv_key.
      IF lv_keys IS INITIAL.
        lv_keys = lv_key.
      ELSE.
        CONCATENATE lv_keys ',' lv_key INTO lv_keys.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals(
      act = lv_keys
      exp = 'invoice,fiscalYear,vendor,grossAmount,dueDate,daysToDue,state,stateCode,reason,purchaseOrder' ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_false ).

    " Primeira linha (5105600002): vencida há 1 dia.
    lt_row = row( is_result = ls_result iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_row ) exp = 10 ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 1 ) exp = '5105600002' ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 2 ) exp = '2026' ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 3 )
                                        exp = '200455 · Plásticos Vale Ltda.' ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 4 ) exp = 'R$ 8.400,00' ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 5 ) exp = '2026-10-08' ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 6 ) exp = '-1' ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 7 ) exp = 'Bloqueada' ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 8 ) exp = 'BLOCKED' ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 9 ) exp = 'Bloqueio por quantidade' ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 10 ) exp = '4500017790' ).

    " Última linha (5105600004): estacionada, vence em 13 dias.
    lt_row = row( is_result = ls_result iv_index = 4 ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 1 ) exp = '5105600004' ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 6 ) exp = '13' ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 7 ) exp = 'Estacionada' ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 8 ) exp = 'PARKED' ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 9 ) exp = 'Estacionada, não lançada' ).
  ENDMETHOD.

  METHOD overdue_finding.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.

    ls_result = run( lt_params ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'MM10.OVERDUE' ).
    READ TABLE ls_result-findings INTO ls_finding INDEX 1. "#EC CI_SUBRC
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title
                                        exp = '1 fatura(s) bloqueada(s) ou estacionada(s) já vencida(s)' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = 'Faturas: 5105600002. O fornecedor pode cobrar juros. Use o MM-02 para a causa.' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'MRBR' ).
    cl_abap_unit_assert=>assert_initial( ls_finding-evidence ).
  ENDMETHOD.

  METHOD filter_parked.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    param( EXPORTING iv_name = 'state' iv_value = 'PARKED' CHANGING ct_params = lt_params ).
    ls_result = run( lt_params ).
    cl_abap_unit_assert=>assert_equals( act = invoices( ls_result ) exp = '5105600004' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '1' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'totalAmount' )
                                        exp = 'R$ 3.980,00' ).
    cl_abap_unit_assert=>assert_equals( act = has_fact( is_result = ls_result iv_id = 'state:BLOCKED' )
                                        exp = abap_false ).
    " Estacionada com vencimento futuro: sem fatura vencida, sem achado.
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'OK' ).
    cl_abap_unit_assert=>assert_initial( ls_result-findings ).
  ENDMETHOD.

  METHOD filter_blocked.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    param( EXPORTING iv_name = 'state' iv_value = 'BLOCKED' CHANGING ct_params = lt_params ).
    ls_result = run( lt_params ).
    cl_abap_unit_assert=>assert_equals( act = invoices( ls_result ) exp = '5105600002,5105600001,5105600005' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'totalAmount' )
                                        exp = 'R$ 25.270,00' ).
    cl_abap_unit_assert=>assert_equals( act = has_fact( is_result = ls_result iv_id = 'state:PARKED' )
                                        exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'MM10.OVERDUE' ).
  ENDMETHOD.

  METHOD filter_company.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_pending TYPE zif_rx_mm_reader=>ty_pending.

    ls_pending = pending( iv_belnr  = '5105600099'
                          iv_lifnr  = '0000200310'
                          iv_name   = 'Metalúrgica Silva S.A.'
                          iv_amount = 500
                          iv_due    = '20261201'
                          iv_ebeln  = '4500019999' ).
    ls_pending-bukrs = '2000'.
    ls_pending-zlspr = 'R'.
    add( ls_pending ).

    param( EXPORTING iv_name = 'companyCode' iv_value = '2000' CHANGING ct_params = lt_params ).
    ls_result = run( lt_params ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '2000' ).
    cl_abap_unit_assert=>assert_equals( act = invoices( ls_result ) exp = '5105600099' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'OK' ).

    CLEAR lt_params.
    param( EXPORTING iv_name = 'companyCode' iv_value = '1000' CHANGING ct_params = lt_params ).
    ls_result = run( lt_params ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '1000' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '4' ).
  ENDMETHOD.

  METHOD paging.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_table TYPE zif_rx_types=>ty_table.

    param( EXPORTING iv_name = 'maxRows' iv_value = '3' CHANGING ct_params = lt_params ).
    ls_result = run( lt_params ).
    READ TABLE ls_result-tables INTO ls_table INDEX 1.    "#EC CI_SUBRC
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-rows ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_true ).
    " Os totais valem para a lista inteira, não só para a página.
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '4' ).

    param( EXPORTING iv_name = 'page' iv_value = '2' CHANGING ct_params = lt_params ).
    ls_result = run( lt_params ).
    READ TABLE ls_result-tables INTO ls_table INDEX 1.    "#EC CI_SUBRC
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-rows ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = invoices( ls_result ) exp = '5105600004' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '4' ).
  ENDMETHOD.

  METHOD empty_list.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    CLEAR mo_reader->mt_pending.
    ls_result = run( lt_params ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'OK' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '0' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'totalAmount' )
                                        exp = 'R$ 0,00' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-tables ) exp = 1 ).
    cl_abap_unit_assert=>assert_initial( ls_result-findings ).
  ENDMETHOD.

  METHOD several_currencies.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_pending TYPE zif_rx_mm_reader=>ty_pending.

    ls_pending = pending( iv_belnr  = '5105600098'
                          iv_lifnr  = '0000200310'
                          iv_name   = 'Metalúrgica Silva S.A.'
                          iv_amount = 1000
                          iv_due    = '20261201'
                          iv_ebeln  = '4500019998' ).
    ls_pending-waers = 'USD'.
    ls_pending-zlspr = 'R'.
    add( ls_pending ).

    ls_result = run( lt_params ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'totalAmount' )
                                        exp = 'R$ 29.250,00; 1.000,00 USD' ).
  ENDMETHOD.

  METHOD reason_texts.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_pending TYPE zif_rx_mm_reader=>ty_pending.
    DATA lt_row TYPE string_table.

    CLEAR mo_reader->mt_pending.
    ls_pending = pending( iv_belnr  = '5105600090'
                          iv_lifnr  = '0000200310'
                          iv_name   = ''
                          iv_amount = 100
                          iv_due    = '20261101'
                          iv_ebeln  = '4500019990' ).
    ls_pending-zlspr = 'R'.
    ls_pending-blocks-spgrp = 'X'.
    ls_pending-blocks-spgrm = 'X'.
    add( ls_pending ).
    ls_pending-belnr = '5105600091'.
    CLEAR ls_pending-blocks.
    ls_pending-zlspr = 'A'.
    add( ls_pending ).

    ls_result = run( lt_params ).
    lt_row = row( is_result = ls_result iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 9 )
                                        exp = 'Bloqueio por preço, quantidade' ).
    " Sem nome do fornecedor, só o número.
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 3 ) exp = '200310' ).
    lt_row = row( is_result = ls_result iv_index = 2 ).
    cl_abap_unit_assert=>assert_equals( act = cell( it_row = lt_row iv_index = 9 )
                                        exp = 'Bloqueio de pagamento (chave A)' ).
  ENDMETHOD.

  METHOD skips_unauthorized_companies.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_pending TYPE zif_rx_mm_reader=>ty_pending.
    DATA lv_company TYPE zif_rx_mm_reader=>ty_bukrs.

    ls_pending = pending( iv_belnr  = '5105600097'
                          iv_lifnr  = '0000200310'
                          iv_name   = 'Metalúrgica Silva S.A.'
                          iv_amount = 700
                          iv_due    = '20260901'
                          iv_ebeln  = '4500019997' ).
    ls_pending-bukrs = '3000'.
    ls_pending-zlspr = 'R'.
    add( ls_pending ).
    lv_company = '3000'.
    APPEND lv_company TO mo_reader->mt_denied.

    " Sem filtro de empresa, as faturas da empresa sem autorização ficam fora da lista e dos totais.
    ls_result = run( lt_params ).
    cl_abap_unit_assert=>assert_equals( act = invoices( ls_result )
                                        exp = '5105600002,5105600001,5105600005,5105600004' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '4' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'totalAmount' )
                                        exp = 'R$ 29.250,00' ).
  ENDMETHOD.

  METHOD not_authorized_company.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA lx_error TYPE REF TO zcx_rx_error.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA lv_company TYPE zif_rx_mm_reader=>ty_bukrs.

    lv_company = '1000'.
    APPEND lv_company TO mo_reader->mt_denied.
    param( EXPORTING iv_name = 'companyCode' iv_value = '1000' CHANGING ct_params = lt_params ).
    TRY.
        ls_result = run( lt_params ).
        cl_abap_unit_assert=>fail( msg = 'Esperava erro 403' ).
      CATCH zcx_rx_error INTO lx_error.
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_http_status exp = 403 ).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'NOT_AUTHORIZED' ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
