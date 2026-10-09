*"* Testes do SD-01 com dublê do leitor: reproduzem os cenários do sap-mock
*"* (pedidos 4500001 a 4500007 e um inexistente), como em services/sap-mock/test/server.test.ts.
*"* "Hoje" é sempre 2026-10-09.
CLASS ltd_reader DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_rx_sd_reader.

    TYPES:
      BEGIN OF ty_item_row,
        vbeln TYPE c LENGTH 10,
        item  TYPE zif_rx_sd_reader=>ty_item,
      END OF ty_item_row,
      ty_item_rows TYPE STANDARD TABLE OF ty_item_row WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_missing_row,
        vbeln   TYPE c LENGTH 10,
        missing TYPE zif_rx_sd_reader=>ty_missing_field,
      END OF ty_missing_row,
      ty_missing_rows TYPE STANDARD TABLE OF ty_missing_row WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_followup_row,
        vbeln    TYPE c LENGTH 10,
        followup TYPE zif_rx_sd_reader=>ty_followup,
      END OF ty_followup_row,
      ty_followup_rows TYPE STANDARD TABLE OF ty_followup_row WITH DEFAULT KEY.

    DATA mt_headers TYPE zif_rx_sd_reader=>ty_order_headers.
    DATA mt_items TYPE ty_item_rows.
    DATA mt_missing TYPE ty_missing_rows.
    DATA mt_followups TYPE ty_followup_rows.
    DATA mt_due TYPE string_table.
    DATA mv_s4 TYPE abap_bool.
    DATA mv_authorized TYPE abap_bool.

    METHODS constructor.

    "! Os sete cenários do sap-mock, com datas relativas a IV_TODAY.
    METHODS load_scenarios
      IMPORTING iv_today TYPE d.

    METHODS add_order
      IMPORTING iv_vbeln TYPE string
                iv_kunnr TYPE string
                iv_name  TYPE string
                iv_netwr TYPE string
                iv_erdat TYPE d
                iv_vdatu TYPE d
                iv_items TYPE i.

    METHODS set_status
      IMPORTING iv_vbeln      TYPE string
                iv_credit     TYPE csequence DEFAULT 'A'
                iv_incomplete TYPE csequence DEFAULT 'C'
                iv_delivery   TYPE csequence DEFAULT 'C'
                iv_billing    TYPE csequence DEFAULT 'A'.

    METHODS set_delivery_block
      IMPORTING iv_vbeln TYPE string
                iv_code  TYPE csequence
                iv_text  TYPE csequence.

    METHODS set_billing_block
      IMPORTING iv_vbeln TYPE string
                iv_code  TYPE csequence
                iv_text  TYPE csequence.

    METHODS add_item
      IMPORTING iv_vbeln     TYPE string
                iv_posnr     TYPE csequence
                iv_rejection TYPE csequence OPTIONAL
                iv_reason    TYPE csequence OPTIONAL
                iv_relevant  TYPE abap_bool DEFAULT abap_true
                iv_schedule  TYPE csequence OPTIONAL
                iv_billing   TYPE csequence OPTIONAL.

    METHODS add_missing
      IMPORTING iv_vbeln TYPE string
                iv_posnr TYPE csequence
                iv_table TYPE csequence
                iv_field TYPE csequence
                iv_text  TYPE csequence.

    METHODS add_followup
      IMPORTING iv_vbeln    TYPE string
                iv_category TYPE csequence
                iv_doc      TYPE csequence
                iv_pred     TYPE csequence
                iv_wbstk    TYPE csequence OPTIONAL.

  PRIVATE SECTION.
    METHODS pad
      IMPORTING iv_vbeln        TYPE string
      RETURNING VALUE(rv_vbeln) TYPE string.
ENDCLASS.


CLASS ltd_reader IMPLEMENTATION.

  METHOD constructor.
    mv_authorized = abap_true.
  ENDMETHOD.

  METHOD pad.
    rv_vbeln = zcl_rx_format=>alpha_in( iv_value = iv_vbeln iv_length = 10 ).
  ENDMETHOD.

  METHOD load_scenarios.
    DATA lv_erdat TYPE d.
    DATA lv_vdatu TYPE d.

    " 4500001: bloqueio de crédito.
    lv_erdat = iv_today - 6.
    lv_vdatu = iv_today + 2.
    add_order( iv_vbeln = '4500001' iv_kunnr = '100234' iv_name = 'Comercial Andrade Ltda.'
               iv_netwr = '48450' iv_erdat = lv_erdat iv_vdatu = lv_vdatu iv_items = 3 ).
    set_status( iv_vbeln = '4500001' iv_credit = 'B' iv_delivery = 'A' ).

    " 4500002: bloqueio de remessa + incompletude.
    lv_erdat = iv_today - 4.
    lv_vdatu = iv_today + 5.
    add_order( iv_vbeln = '4500002' iv_kunnr = '100518' iv_name = 'Distribuidora Paraná S.A.'
               iv_netwr = '12890.50' iv_erdat = lv_erdat iv_vdatu = lv_vdatu iv_items = 2 ).
    set_status( iv_vbeln = '4500002' iv_incomplete = 'A' iv_delivery = 'A' ).
    set_delivery_block( iv_vbeln = '4500002' iv_code = '01' iv_text = 'Bloqueio geral' ).
    add_missing( iv_vbeln = '4500002' iv_posnr = '000000' iv_table = 'VBKD' iv_field = 'ZTERM'
                 iv_text = 'Condições de pagamento' ).
    add_missing( iv_vbeln = '4500002' iv_posnr = '000000' iv_table = 'VBKD' iv_field = 'INCO1'
                 iv_text = 'Incoterms' ).

    " 4500003: remessa criada, sem saída de mercadoria.
    lv_erdat = iv_today - 9.
    lv_vdatu = iv_today - 2.
    add_order( iv_vbeln = '4500003' iv_kunnr = '100777' iv_name = 'Saneamento Litoral S.A.'
               iv_netwr = '96300' iv_erdat = lv_erdat iv_vdatu = lv_vdatu iv_items = 5 ).
    set_status( '4500003' ).
    add_followup( iv_vbeln = '4500003' iv_category = 'J' iv_doc = '0080000123' iv_pred = '0004500003'
                  iv_wbstk = 'A' ).

    " 4500004: já faturado (remessa 80000124, fatura 90000456).
    lv_erdat = iv_today - 15.
    lv_vdatu = iv_today - 8.
    add_order( iv_vbeln = '4500004' iv_kunnr = '100234' iv_name = 'Comercial Andrade Ltda.'
               iv_netwr = '7420' iv_erdat = lv_erdat iv_vdatu = lv_vdatu iv_items = 1 ).
    set_status( iv_vbeln = '4500004' iv_billing = 'C' ).
    add_followup( iv_vbeln = '4500004' iv_category = 'J' iv_doc = '0080000124' iv_pred = '0004500004'
                  iv_wbstk = 'C' ).
    add_followup( iv_vbeln = '4500004' iv_category = 'M' iv_doc = '0090000456' iv_pred = '0080000124' ).

    " 4500005: bloqueio de faturamento + item 20 recusado.
    lv_erdat = iv_today - 3.
    lv_vdatu = iv_today + 1.
    add_order( iv_vbeln = '4500005' iv_kunnr = '100901' iv_name = 'Agro Serra Verde Ltda.'
               iv_netwr = '31780' iv_erdat = lv_erdat iv_vdatu = lv_vdatu iv_items = 2 ).
    set_status( '4500005' ).
    set_billing_block( iv_vbeln = '4500005' iv_code = '02' iv_text = 'Verificar preço' ).
    add_item( iv_vbeln = '4500005' iv_posnr = '000010' ).
    add_item( iv_vbeln = '4500005' iv_posnr = '000020' iv_rejection = '01'
              iv_reason = 'Prazo de entrega inaceitável' iv_relevant = abap_false ).
    add_followup( iv_vbeln = '4500005' iv_category = 'J' iv_doc = '0080000125' iv_pred = '0004500005'
                  iv_wbstk = 'C' ).

    " 4500006: bloqueio de crédito (pedido grande).
    lv_erdat = iv_today - 2.
    lv_vdatu = iv_today + 7.
    add_order( iv_vbeln = '4500006' iv_kunnr = '100345' iv_name = 'Hidráulica Central Eireli'
               iv_netwr = '154200' iv_erdat = lv_erdat iv_vdatu = lv_vdatu iv_items = 8 ).
    set_status( iv_vbeln = '4500006' iv_credit = 'B' iv_delivery = 'A' ).

    " 4500007: incompleto (falta o recebedor da mercadoria no item 10).
    lv_erdat = iv_today - 1.
    lv_vdatu = iv_today + 4.
    add_order( iv_vbeln = '4500007' iv_kunnr = '100518' iv_name = 'Distribuidora Paraná S.A.'
               iv_netwr = '5240' iv_erdat = lv_erdat iv_vdatu = lv_vdatu iv_items = 1 ).
    set_status( iv_vbeln = '4500007' iv_incomplete = 'A' iv_delivery = 'A' ).
    add_missing( iv_vbeln = '4500007' iv_posnr = '000010' iv_table = 'VBPA' iv_field = 'KUNWE'
                 iv_text = 'Recebedor da mercadoria' ).
  ENDMETHOD.

  METHOD add_order.
    DATA ls_header TYPE zif_rx_sd_reader=>ty_order_header.

    ls_header-exists = abap_true.
    ls_header-vbeln = pad( iv_vbeln ).
    ls_header-vbtyp = 'C'.
    ls_header-auart = 'OR'.
    ls_header-vkorg = '1000'.
    ls_header-vtweg = '10'.
    ls_header-spart = '00'.
    ls_header-kunnr = zcl_rx_format=>alpha_in( iv_value = iv_kunnr iv_length = 10 ).
    ls_header-customer_name = iv_name.
    ls_header-netwr = iv_netwr.
    ls_header-waerk = 'BRL'.
    ls_header-erdat = iv_erdat.
    ls_header-vdatu = iv_vdatu.
    ls_header-item_count = iv_items.
    APPEND ls_header TO mt_headers.
  ENDMETHOD.

  METHOD set_status.
    FIELD-SYMBOLS <ls_header> TYPE zif_rx_sd_reader=>ty_order_header.

    READ TABLE mt_headers ASSIGNING <ls_header> WITH KEY vbeln = pad( iv_vbeln ).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    <ls_header>-state-credit_status = iv_credit.
    <ls_header>-state-incompletion_status = iv_incomplete.
    <ls_header>-state-delivery_status = iv_delivery.
    <ls_header>-state-billing_status = iv_billing.
  ENDMETHOD.

  METHOD set_delivery_block.
    FIELD-SYMBOLS <ls_header> TYPE zif_rx_sd_reader=>ty_order_header.

    READ TABLE mt_headers ASSIGNING <ls_header> WITH KEY vbeln = pad( iv_vbeln ).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    <ls_header>-state-delivery_block = iv_code.
    <ls_header>-delivery_block_text = iv_text.
  ENDMETHOD.

  METHOD set_billing_block.
    FIELD-SYMBOLS <ls_header> TYPE zif_rx_sd_reader=>ty_order_header.

    READ TABLE mt_headers ASSIGNING <ls_header> WITH KEY vbeln = pad( iv_vbeln ).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    <ls_header>-state-billing_block = iv_code.
    <ls_header>-state-billing_block_text = iv_text.
  ENDMETHOD.

  METHOD add_item.
    DATA ls_row TYPE ty_item_row.

    ls_row-vbeln = pad( iv_vbeln ).
    ls_row-item-posnr = iv_posnr.
    ls_row-item-rejection_reason = iv_rejection.
    ls_row-item-rejection_text = iv_reason.
    ls_row-item-item_category = 'TAN'.
    ls_row-item-billing_relevant = iv_relevant.
    ls_row-item-schedule_block = iv_schedule.
    IF iv_schedule IS NOT INITIAL.
      ls_row-item-schedule_block_text = 'Bloqueio de crédito'.
    ENDIF.
    ls_row-item-billing_block = iv_billing.
    IF iv_billing IS NOT INITIAL.
      ls_row-item-billing_block_text = 'Verificar preço'.
    ENDIF.
    APPEND ls_row TO mt_items.
  ENDMETHOD.

  METHOD add_missing.
    DATA ls_row TYPE ty_missing_row.

    ls_row-vbeln = pad( iv_vbeln ).
    ls_row-missing-posnr = iv_posnr.
    ls_row-missing-table_name = iv_table.
    ls_row-missing-field_name = iv_field.
    ls_row-missing-field_text = iv_text.
    APPEND ls_row TO mt_missing.
  ENDMETHOD.

  METHOD add_followup.
    DATA ls_row TYPE ty_followup_row.

    ls_row-vbeln = pad( iv_vbeln ).
    ls_row-followup-category = iv_category.
    ls_row-followup-doc_number = iv_doc.
    ls_row-followup-predecessor = iv_pred.
    ls_row-followup-goods_issue_status = iv_wbstk.
    APPEND ls_row TO mt_followups.
  ENDMETHOD.

  METHOD zif_rx_sd_reader~is_s4.
    rv_s4 = mv_s4.
  ENDMETHOD.

  METHOD zif_rx_sd_reader~get_header.
    READ TABLE mt_headers INTO rs_header WITH KEY vbeln = iv_vbeln.
    IF sy-subrc <> 0.
      CLEAR rs_header.
    ENDIF.
  ENDMETHOD.

  METHOD zif_rx_sd_reader~get_items.
    FIELD-SYMBOLS <ls_row> TYPE ty_item_row.

    LOOP AT mt_items ASSIGNING <ls_row> WHERE vbeln = iv_vbeln.
      APPEND <ls_row>-item TO rt_items.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_rx_sd_reader~get_missing_fields.
    FIELD-SYMBOLS <ls_row> TYPE ty_missing_row.

    LOOP AT mt_missing ASSIGNING <ls_row> WHERE vbeln = iv_vbeln.
      APPEND <ls_row>-missing TO rt_missing.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_rx_sd_reader~get_followups.
    FIELD-SYMBOLS <ls_row> TYPE ty_followup_row.

    LOOP AT mt_followups ASSIGNING <ls_row> WHERE vbeln = iv_vbeln.
      APPEND <ls_row>-followup TO rt_followups.
    ENDLOOP.
  ENDMETHOD.

  METHOD zif_rx_sd_reader~is_billing_due.
    DATA lv_vbeln TYPE string.

    lv_vbeln = iv_vbeln.
    READ TABLE mt_due WITH KEY table_line = lv_vbeln TRANSPORTING NO FIELDS.
    IF sy-subrc = 0 AND it_followups IS NOT INITIAL.
      rv_due = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD zif_rx_sd_reader~get_open_orders.
    CLEAR et_orders.
    ev_truncated = abap_false.
  ENDMETHOD.

  METHOD zif_rx_sd_reader~is_authorized.
    rv_allowed = mv_authorized.
  ENDMETHOD.
ENDCLASS.


CLASS ltc_sd01 DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_reader TYPE REF TO ltd_reader.
    DATA mo_cut TYPE REF TO zif_rx_diagnostic.

    METHODS setup.
    METHODS run
      IMPORTING iv_order         TYPE string
      RETURNING VALUE(rs_result) TYPE zif_rx_types=>ty_result.
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
    METHODS related
      IMPORTING is_result     TYPE zif_rx_types=>ty_result
                iv_index      TYPE i
      RETURNING VALUE(rs_ref) TYPE zif_rx_types=>ty_object_ref.
    METHODS assert_contains
      IMPORTING iv_text TYPE string
                iv_part TYPE string.

    METHODS metadata FOR TESTING.
    METHODS credit_block FOR TESTING.
    METHODS credit_block_s4 FOR TESTING.
    METHODS delivery_block_and_incomplete FOR TESTING.
    METHODS goods_issue_pending FOR TESTING.
    METHODS already_billed FOR TESTING.
    METHODS billing_block_rejected_item FOR TESTING.
    METHODS credit_block_large_order FOR TESTING.
    METHODS incomplete_item FOR TESTING.
    METHODS not_found FOR TESTING.
    METHODS leading_zeros FOR TESTING.
    METHODS main_facts FOR TESTING.
    METHODS related_documents FOR TESTING.
    METHODS not_authorized FOR TESTING.
    METHODS schedule_and_item_block FOR TESTING.
    METHODS not_delivered_without_blocks FOR TESTING.
    METHODS billing_due FOR TESTING.
    METHODS not_billing_relevant FOR TESTING.
    METHODS several_invoices FOR TESTING.
ENDCLASS.


CLASS ltc_sd01 IMPLEMENTATION.

  METHOD setup.
    DATA lv_today TYPE d VALUE '20261009'.

    CREATE OBJECT mo_reader.
    mo_reader->load_scenarios( lv_today ).
    CREATE OBJECT mo_cut TYPE zcl_rx_diag_sd01
      EXPORTING io_reader = mo_reader iv_today = lv_today.
  ENDMETHOD.

  METHOD run.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_param TYPE zif_rx_types=>ty_param.
    DATA lx_error TYPE REF TO zcx_rx_error.

    ls_param-name = 'salesOrder'.
    ls_param-value = iv_order.
    APPEND ls_param TO lt_params.
    TRY.
        rs_result = mo_cut->execute( lt_params ).
      CATCH zcx_rx_error INTO lx_error.
        cl_abap_unit_assert=>fail( msg = lx_error->mv_text ).
    ENDTRY.
  ENDMETHOD.

  METHOD codes.
    FIELD-SYMBOLS <ls_finding> TYPE zif_rx_types=>ty_finding.

    LOOP AT is_result-findings ASSIGNING <ls_finding>.
      IF sy-tabix = 1.
        rv_codes = <ls_finding>-code.
      ELSE.
        CONCATENATE rv_codes <ls_finding>-code INTO rv_codes SEPARATED BY ','.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD finding.
    READ TABLE is_result-findings INTO rs_finding WITH KEY code = iv_code.
    IF sy-subrc <> 0.
      cl_abap_unit_assert=>fail( msg = 'Achado não encontrado' detail = iv_code ).
    ENDIF.
  ENDMETHOD.

  METHOD fact.
    DATA ls_fact TYPE zif_rx_types=>ty_fact.

    READ TABLE is_result-facts INTO ls_fact WITH KEY id = iv_id.
    IF sy-subrc <> 0.
      cl_abap_unit_assert=>fail( msg = 'Fato não encontrado' detail = iv_id ).
    ENDIF.
    rv_value = ls_fact-value.
  ENDMETHOD.

  METHOD evidence.
    READ TABLE is_finding-evidence INTO rs_evidence INDEX iv_index.
    IF sy-subrc <> 0.
      cl_abap_unit_assert=>fail( msg = 'Evidência não encontrada' ).
    ENDIF.
  ENDMETHOD.

  METHOD related.
    READ TABLE is_result-related INTO rs_ref INDEX iv_index.
    IF sy-subrc <> 0.
      cl_abap_unit_assert=>fail( msg = 'Relacionado não encontrado' ).
    ENDIF.
  ENDMETHOD.

  METHOD assert_contains.
    IF iv_text NS iv_part.
      cl_abap_unit_assert=>fail( msg = iv_part detail = iv_text ).
    ENDIF.
  ENDMETHOD.

  METHOD metadata.
    DATA ls_meta TYPE zif_rx_types=>ty_diag_meta.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.

    ls_meta = mo_cut->get_metadata( ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-id exp = 'SD-01' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-version exp = '1.0' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-module exp = 'SD' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-kind exp = 'OBJECT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-title exp = 'Pedido de venda não faturado' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_meta-params ) exp = 1 ).
    READ TABLE ls_meta-params INTO ls_param INDEX 1.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-name exp = 'salesOrder' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Pedido de venda' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'DOCUMENT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-required exp = abap_true ).
    cl_abap_unit_assert=>assert_initial( ls_param-options ).
  ENDMETHOD.

  METHOD credit_block.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    ls_result = run( '4500001' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD01.CREDIT_BLOCK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-kind exp = 'SALES_ORDER' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '4500001' ).

    ls_finding = finding( is_result = ls_result iv_code = 'SD01.CREDIT_BLOCK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title exp = 'Pedido bloqueado por crédito' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'VKM3' ).
    assert_contains( iv_text = ls_finding-detail iv_part = 'R$ 48.450,00' ).
    assert_contains( iv_text = ls_finding-detail iv_part = 'cliente 100234' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_finding-evidence ) exp = 1 ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'VBUK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'CMGST' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = 'B' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-label exp = 'Status de crédito: não aprovado' ).
  ENDMETHOD.

  METHOD credit_block_s4.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    " No S/4 o status sai da VBAK e a ação é a decisão de crédito do FSCM.
    mo_reader->mv_s4 = abap_true.
    ls_result = run( '4500001' ).
    ls_finding = finding( is_result = ls_result iv_code = 'SD01.CREDIT_BLOCK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'UKM_MY_DCDS' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'VBAK' ).
  ENDMETHOD.

  METHOD delivery_block_and_incomplete.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    ls_result = run( '4500002' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result )
                                        exp = 'SD01.DELIVERY_BLOCK_HEADER,SD01.INCOMPLETE' ).

    ls_finding = finding( is_result = ls_result iv_code = 'SD01.DELIVERY_BLOCK_HEADER' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-detail
                                        exp = 'O pedido está com o bloqueio de remessa 01 (Bloqueio geral).' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'VBAK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'LIFSK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '01' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-label exp = 'Bloqueio de remessa: Bloqueio geral' ).

    ls_finding = finding( is_result = ls_result iv_code = 'SD01.INCOMPLETE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    assert_contains( iv_text = ls_finding-detail iv_part = 'condições de pagamento e incoterms' ).
    " Dois campos faltantes + o status de incompletude (UVALL), como no sap-mock.
    cl_abap_unit_assert=>assert_equals( act = lines( ls_finding-evidence ) exp = 3 ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'VBUV' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'FDNAM' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = 'ZTERM' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-label exp = 'Campo faltante: condições de pagamento' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 3 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'VBUK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'UVALL' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = 'A' ).
  ENDMETHOD.

  METHOD goods_issue_pending.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    ls_result = run( '4500003' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD01.GOODS_ISSUE_PENDING' ).

    ls_finding = finding( is_result = ls_result iv_code = 'SD01.GOODS_ISSUE_PENDING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'VL02N' ).
    assert_contains( iv_text = ls_finding-detail iv_part = 'A remessa 80000123 foi criada' ).
    assert_contains( iv_text = ls_finding-detail iv_part = 'SD-02' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_finding-evidence ) exp = 2 ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'VBFA' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'VBTYP_N' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = 'J' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-label exp = 'Documento subsequente: remessa 80000123' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'VBUK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'WBSTK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-label
                                        exp = 'Status de saída de mercadoria: não processado' ).
  ENDMETHOD.

  METHOD already_billed.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA lv_exp TYPE string.

    ls_result = run( '4500004' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'OK' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD01.ALREADY_BILLED' ).

    ls_finding = finding( is_result = ls_result iv_code = 'SD01.ALREADY_BILLED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'INFO' ).
    lv_exp = 'O pedido foi faturado pela fatura 90000456,'.
    CONCATENATE lv_exp 'a partir da remessa 80000124.' INTO lv_exp SEPARATED BY space.
    cl_abap_unit_assert=>assert_equals( act = ls_finding-detail exp = lv_exp ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'VF03' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-description
                                        exp = 'Exibir a fatura 90000456' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'stage' ) exp = 'Concluído' ).
  ENDMETHOD.

  METHOD billing_block_rejected_item.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.
    DATA lv_exp TYPE string.

    ls_result = run( '4500005' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD01.BILLING_BLOCK,SD01.ITEM_REJECTED' ).

    ls_finding = finding( is_result = ls_result iv_code = 'SD01.BILLING_BLOCK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-detail
                                        exp = 'O pedido está com o bloqueio de faturamento 02 (Verificar preço).' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'VBAK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'FAKSK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '02' ).

    ls_finding = finding( is_result = ls_result iv_code = 'SD01.ITEM_REJECTED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'INFO' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title exp = 'Item 20 recusado' ).
    lv_exp = 'O item 20 foi recusado (motivo 01: Prazo de entrega inaceitável)'.
    CONCATENATE lv_exp 'e não será faturado.' INTO lv_exp SEPARATED BY space.
    cl_abap_unit_assert=>assert_equals( act = ls_finding-detail exp = lv_exp ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'VBAP' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'ABGRU' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '01' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-label exp = 'Motivo de recusa do item 20' ).
  ENDMETHOD.

  METHOD credit_block_large_order.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.

    ls_result = run( '4500006' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD01.CREDIT_BLOCK' ).
    ls_finding = finding( is_result = ls_result iv_code = 'SD01.CREDIT_BLOCK' ).
    assert_contains( iv_text = ls_finding-detail iv_part = 'R$ 154.200,00' ).
    assert_contains( iv_text = ls_finding-detail iv_part = 'cliente 100345' ).
  ENDMETHOD.

  METHOD incomplete_item.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    ls_result = run( '4500007' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD01.INCOMPLETE' ).
    ls_finding = finding( is_result = ls_result iv_code = 'SD01.INCOMPLETE' ).
    assert_contains( iv_text = ls_finding-detail iv_part = 'recebedor da mercadoria (item 10)' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_finding-evidence ) exp = 2 ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = 'KUNWE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-label
                                        exp = 'Campo faltante: recebedor da mercadoria (item 10)' ).
  ENDMETHOD.

  METHOD not_found.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    ls_result = run( '9999999' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'NOT_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD01.NOT_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '9999999' ).
    cl_abap_unit_assert=>assert_initial( ls_result-facts ).
    ls_finding = finding( is_result = ls_result iv_code = 'SD01.NOT_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'INFO' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'VBAK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'VBELN' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '9999999' ).
  ENDMETHOD.

  METHOD leading_zeros.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    " Com zeros à esquerda é o mesmo pedido; o id sai sem zeros.
    ls_result = run( '0004500001' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '4500001' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD01.CREDIT_BLOCK' ).
  ENDMETHOD.

  METHOD main_facts.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_fact TYPE zif_rx_types=>ty_fact.
    DATA lv_ids TYPE string.

    ls_result = run( '4500001' ).
    LOOP AT ls_result-facts INTO ls_fact.
      IF sy-tabix = 1.
        lv_ids = ls_fact-id.
      ELSE.
        CONCATENATE lv_ids ls_fact-id INTO lv_ids SEPARATED BY ','.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals( act = lv_ids
                                        exp = 'customer,netValue,stage,salesOrg,createdOn,requestedDate,items' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'customer' )
                                        exp = '100234 · Comercial Andrade Ltda.' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'netValue' )
                                        exp = 'R$ 48.450,00' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'stage' ) exp = 'Crédito' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'salesOrg' ) exp = '1000' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'createdOn' )
                                        exp = '2026-10-03' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'requestedDate' )
                                        exp = '2026-10-11' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'items' ) exp = '3' ).

    " Etapa de cada cenário (mesma classificação do SD-10).
    ls_result = run( '4500002' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'stage' ) exp = 'Remessa' ).
    ls_result = run( '4500003' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'stage' )
                                        exp = 'Saída de mercadoria' ).
    ls_result = run( '4500005' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'stage' )
                                        exp = 'Faturamento' ).
  ENDMETHOD.

  METHOD related_documents.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_ref TYPE zif_rx_types=>ty_object_ref.

    ls_result = run( '4500004' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-related ) exp = 2 ).
    ls_ref = related( is_result = ls_result iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_ref-kind exp = 'DELIVERY' ).
    cl_abap_unit_assert=>assert_equals( act = ls_ref-id exp = '80000124' ).
    ls_ref = related( is_result = ls_result iv_index = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_ref-kind exp = 'BILLING_DOCUMENT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_ref-id exp = '90000456' ).

    ls_result = run( '4500003' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-related ) exp = 1 ).
    ls_ref = related( is_result = ls_result iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_ref-id exp = '80000123' ).

    ls_result = run( '4500001' ).
    cl_abap_unit_assert=>assert_initial( ls_result-related ).
  ENDMETHOD.

  METHOD not_authorized.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_param TYPE zif_rx_types=>ty_param.
    DATA lx_error TYPE REF TO zcx_rx_error.

    " Sem V_VBAK_VKO/V_VBAK_AAT: erro 403 e nenhum dado do pedido.
    mo_reader->mv_authorized = abap_false.
    ls_param-name = 'salesOrder'.
    ls_param-value = '4500001'.
    APPEND ls_param TO lt_params.
    TRY.
        mo_cut->execute( lt_params ).
        cl_abap_unit_assert=>fail( 'Deveria negar o acesso' ).
      CATCH zcx_rx_error INTO lx_error.
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_http_status exp = 403 ).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'NOT_AUTHORIZED' ).
    ENDTRY.
  ENDMETHOD.

  METHOD schedule_and_item_block.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.
    DATA lv_today TYPE d VALUE '20261009'.

    " Pedido novo: divisão do item 10 com bloqueio de remessa e item 20 com bloqueio de faturamento.
    mo_reader->add_order( iv_vbeln = '4500010' iv_kunnr = '100234' iv_name = 'Comercial Andrade Ltda.'
                          iv_netwr = '1000' iv_erdat = lv_today iv_vdatu = lv_today iv_items = 2 ).
    mo_reader->set_status( iv_vbeln = '4500010' iv_delivery = 'A' ).
    mo_reader->add_item( iv_vbeln = '4500010' iv_posnr = '000010' iv_schedule = '03' ).
    mo_reader->add_item( iv_vbeln = '4500010' iv_posnr = '000020' iv_billing = '02' ).

    ls_result = run( '4500010' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result )
                                        exp = 'SD01.DELIVERY_BLOCK_SCHEDULE,SD01.BILLING_BLOCK' ).
    ls_finding = finding( is_result = ls_result iv_code = 'SD01.DELIVERY_BLOCK_SCHEDULE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'VBEP' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'LIFSP' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '03' ).
    ls_finding = finding( is_result = ls_result iv_code = 'SD01.BILLING_BLOCK' ).
    ls_evidence = evidence( is_finding = ls_finding iv_index = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'VBAP' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'FAKSP' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-label
                                        exp = 'Bloqueio de faturamento do item 20: Verificar preço' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'stage' ) exp = 'Remessa' ).
  ENDMETHOD.

  METHOD not_delivered_without_blocks.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA lv_today TYPE d VALUE '20261009'.

    " Nada bloqueia, mas a remessa ainda não existe: aviso (e não bloqueio).
    mo_reader->add_order( iv_vbeln = '4500011' iv_kunnr = '100234' iv_name = 'Comercial Andrade Ltda.'
                          iv_netwr = '1000' iv_erdat = lv_today iv_vdatu = lv_today iv_items = 1 ).
    mo_reader->set_status( iv_vbeln = '4500011' iv_delivery = 'A' ).

    ls_result = run( '4500011' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD01.NOT_DELIVERED' ).
    ls_finding = finding( is_result = ls_result iv_code = 'SD01.NOT_DELIVERED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'WARNING' ).
  ENDMETHOD.

  METHOD billing_due.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA lv_today TYPE d VALUE '20261009'.

    " Remessa com saída lançada e pedido na lista de faturamento: só informação.
    mo_reader->add_order( iv_vbeln = '4500012' iv_kunnr = '100234' iv_name = 'Comercial Andrade Ltda.'
                          iv_netwr = '1000' iv_erdat = lv_today iv_vdatu = lv_today iv_items = 1 ).
    mo_reader->set_status( '4500012' ).
    mo_reader->add_followup( iv_vbeln = '4500012' iv_category = 'J' iv_doc = '0080000200'
                             iv_pred = '0004500012' iv_wbstk = 'C' ).
    APPEND '0004500012' TO mo_reader->mt_due.

    ls_result = run( '4500012' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'OK' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD01.BILLING_DUE' ).
    ls_finding = finding( is_result = ls_result iv_code = 'SD01.BILLING_DUE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'INFO' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'VF04' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'stage' ) exp = 'Faturamento' ).
  ENDMETHOD.

  METHOD not_billing_relevant.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA lv_today TYPE d VALUE '20261009'.

    mo_reader->add_order( iv_vbeln = '4500013' iv_kunnr = '100234' iv_name = 'Comercial Andrade Ltda.'
                          iv_netwr = '1000' iv_erdat = lv_today iv_vdatu = lv_today iv_items = 2 ).
    mo_reader->set_status( iv_vbeln = '4500013' iv_billing = ' ' ).
    mo_reader->add_item( iv_vbeln = '4500013' iv_posnr = '000010' iv_relevant = abap_false ).
    mo_reader->add_item( iv_vbeln = '4500013' iv_posnr = '000020' iv_relevant = abap_false ).

    ls_result = run( '4500013' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'OK' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD01.NOT_BILLING_RELEVANT' ).
    ls_finding = finding( is_result = ls_result iv_code = 'SD01.NOT_BILLING_RELEVANT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'INFO' ).
    assert_contains( iv_text = ls_finding-detail iv_part = 'Os itens 10 e 20' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_finding-evidence ) exp = 2 ).
  ENDMETHOD.

  METHOD several_invoices.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA lv_exp TYPE string.
    DATA lv_today TYPE d VALUE '20261009'.

    mo_reader->add_order( iv_vbeln = '4500014' iv_kunnr = '100234' iv_name = 'Comercial Andrade Ltda.'
                          iv_netwr = '1000' iv_erdat = lv_today iv_vdatu = lv_today iv_items = 2 ).
    mo_reader->set_status( iv_vbeln = '4500014' iv_billing = 'C' ).
    mo_reader->add_followup( iv_vbeln = '4500014' iv_category = 'J' iv_doc = '0080000301'
                             iv_pred = '0004500014' iv_wbstk = 'C' ).
    mo_reader->add_followup( iv_vbeln = '4500014' iv_category = 'J' iv_doc = '0080000302'
                             iv_pred = '0004500014' iv_wbstk = 'C' ).
    mo_reader->add_followup( iv_vbeln = '4500014' iv_category = 'M' iv_doc = '0090000501'
                             iv_pred = '0080000301' ).
    mo_reader->add_followup( iv_vbeln = '4500014' iv_category = 'M' iv_doc = '0090000502'
                             iv_pred = '0080000302' ).

    ls_result = run( '4500014' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD01.ALREADY_BILLED' ).
    ls_finding = finding( is_result = ls_result iv_code = 'SD01.ALREADY_BILLED' ).
    lv_exp = 'O pedido foi faturado pelas faturas 90000501 e 90000502,'.
    CONCATENATE lv_exp 'a partir das remessas 80000301 e 80000302.' INTO lv_exp SEPARATED BY space.
    cl_abap_unit_assert=>assert_equals( act = ls_finding-detail exp = lv_exp ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_finding-evidence ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-related ) exp = 4 ).
  ENDMETHOD.

ENDCLASS.
