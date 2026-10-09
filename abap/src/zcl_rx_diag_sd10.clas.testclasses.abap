*"* Testes do SD-10 com dublê do leitor: reproduzem a lista do sap-mock
*"* (pedidos 4500001 a 4500007; o 4500004 já está faturado e fica de fora).
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
    DATA mt_denied_orgs TYPE string_table.
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
    DATA ls_header TYPE zif_rx_sd_reader=>ty_order_header.
    DATA lv_first_extra TYPE i.
    FIELD-SYMBOLS <ls_item> TYPE ty_item_row.
    FIELD-SYMBOLS <ls_followup> TYPE ty_followup_row.

    CLEAR et_orders.
    ev_truncated = abap_false.
    " Como o leitor real: só pedidos com faturamento pendente (A/B), da org. pedida,
    " com contagem de remessas e bloqueios de item já calculados.
    LOOP AT mt_headers INTO ls_header.
      IF iv_sales_org IS NOT INITIAL AND ls_header-vkorg <> iv_sales_org.
        CONTINUE.
      ENDIF.
      IF ls_header-state-billing_status <> 'A' AND ls_header-state-billing_status <> 'B'.
        CONTINUE.
      ENDIF.
      LOOP AT mt_items ASSIGNING <ls_item> WHERE vbeln = ls_header-vbeln.
        IF <ls_item>-item-schedule_block IS NOT INITIAL.
          ls_header-state-schedule_blocked = abap_true.
        ENDIF.
        IF <ls_item>-item-billing_block IS NOT INITIAL.
          ls_header-state-item_billing_blocked = abap_true.
        ENDIF.
      ENDLOOP.
      LOOP AT mt_followups ASSIGNING <ls_followup>
          WHERE vbeln = ls_header-vbeln AND followup-category = zif_rx_sd_reader=>c_followup-delivery.
        ls_header-state-delivery_count = ls_header-state-delivery_count + 1.
        IF ls_header-state-pending_delivery IS INITIAL
            AND ( <ls_followup>-followup-goods_issue_status = 'A'
               OR <ls_followup>-followup-goods_issue_status = 'B' ).
          ls_header-state-pending_delivery = <ls_followup>-followup-doc_number.
        ENDIF.
      ENDLOOP.
      APPEND ls_header TO et_orders.
    ENDLOOP.
    IF lines( et_orders ) > iv_max_rows.
      ev_truncated = abap_true.
      lv_first_extra = iv_max_rows + 1.
      DELETE et_orders FROM lv_first_extra.
    ENDIF.
  ENDMETHOD.

  METHOD zif_rx_sd_reader~is_authorized.
    DATA lv_vkorg TYPE string.

    rv_allowed = mv_authorized.
    lv_vkorg = iv_vkorg.
    READ TABLE mt_denied_orgs WITH KEY table_line = lv_vkorg TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      rv_allowed = abap_false.
    ENDIF.
  ENDMETHOD.
ENDCLASS.


CLASS ltc_sd10 DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_reader TYPE REF TO ltd_reader.
    DATA mo_cut TYPE REF TO zif_rx_diagnostic.

    METHODS setup.
    METHODS run
      IMPORTING iv_sales_org     TYPE string OPTIONAL
                iv_stage         TYPE string OPTIONAL
                iv_max_rows      TYPE string OPTIONAL
                iv_page          TYPE string OPTIONAL
      RETURNING VALUE(rs_result) TYPE zif_rx_types=>ty_result.
    METHODS add_param
      IMPORTING iv_name   TYPE string
                iv_value  TYPE string
      CHANGING  ct_params TYPE zif_rx_types=>ty_params.
    METHODS table
      IMPORTING is_result       TYPE zif_rx_types=>ty_result
      RETURNING VALUE(rs_table) TYPE zif_rx_types=>ty_table.
    METHODS orders
      IMPORTING is_result        TYPE zif_rx_types=>ty_result
      RETURNING VALUE(rv_orders) TYPE string.
    METHODS cell
      IMPORTING is_result       TYPE zif_rx_types=>ty_result
                iv_row          TYPE i
                iv_col          TYPE i
      RETURNING VALUE(rv_value) TYPE string.
    METHODS join
      IMPORTING it_texts       TYPE string_table
      RETURNING VALUE(rv_text) TYPE string.
    METHODS codes
      IMPORTING is_result       TYPE zif_rx_types=>ty_result
      RETURNING VALUE(rv_codes) TYPE string.
    METHODS fact
      IMPORTING is_result       TYPE zif_rx_types=>ty_result
                iv_id           TYPE string
      RETURNING VALUE(rv_value) TYPE string.
    METHODS has_fact
      IMPORTING is_result     TYPE zif_rx_types=>ty_result
                iv_id         TYPE string
      RETURNING VALUE(rv_has) TYPE abap_bool.

    METHODS metadata FOR TESTING.
    METHODS all_open_orders FOR TESTING.
    METHODS table_columns FOR TESTING.
    METHODS first_row FOR TESTING.
    METHODS reasons FOR TESTING.
    METHODS totals_and_stages FOR TESTING.
    METHODS past_requested_date FOR TESTING.
    METHODS several_late_orders FOR TESTING.
    METHODS filter_by_stage FOR TESTING.
    METHODS filter_by_delivery_stage FOR TESTING.
    METHODS filter_by_sales_org FOR TESTING.
    METHODS pagination FOR TESTING.
    METHODS default_page_size FOR TESTING.
    METHODS omits_rows_without_auth FOR TESTING.
    METHODS not_authorized_sales_org FOR TESTING.
    METHODS totals_per_currency FOR TESTING.
ENDCLASS.


CLASS ltc_sd10 IMPLEMENTATION.

  METHOD setup.
    DATA lv_today TYPE d VALUE '20261009'.

    CREATE OBJECT mo_reader.
    mo_reader->load_scenarios( lv_today ).
    CREATE OBJECT mo_cut TYPE zcl_rx_diag_sd10
      EXPORTING io_reader = mo_reader iv_today = lv_today.
  ENDMETHOD.

  METHOD add_param.
    DATA ls_param TYPE zif_rx_types=>ty_param.

    IF iv_value IS INITIAL.
      RETURN.
    ENDIF.
    ls_param-name = iv_name.
    ls_param-value = iv_value.
    APPEND ls_param TO ct_params.
  ENDMETHOD.

  METHOD run.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA lx_error TYPE REF TO zcx_rx_error.

    add_param( EXPORTING iv_name = 'salesOrg' iv_value = iv_sales_org CHANGING ct_params = lt_params ).
    add_param( EXPORTING iv_name = 'stage' iv_value = iv_stage CHANGING ct_params = lt_params ).
    add_param( EXPORTING iv_name = 'maxRows' iv_value = iv_max_rows CHANGING ct_params = lt_params ).
    add_param( EXPORTING iv_name = 'page' iv_value = iv_page CHANGING ct_params = lt_params ).
    TRY.
        rs_result = mo_cut->execute( lt_params ).
      CATCH zcx_rx_error INTO lx_error.
        cl_abap_unit_assert=>fail( msg = lx_error->mv_text ).
    ENDTRY.
  ENDMETHOD.

  METHOD table.
    READ TABLE is_result-tables INTO rs_table INDEX 1.
    IF sy-subrc <> 0.
      cl_abap_unit_assert=>fail( msg = 'Resultado sem tabela' ).
    ENDIF.
  ENDMETHOD.

  METHOD orders.
    DATA ls_table TYPE zif_rx_types=>ty_table.
    DATA lt_row TYPE string_table.
    DATA lv_order TYPE string.
    DATA lv_index TYPE i.

    ls_table = table( is_result ).
    LOOP AT ls_table-rows INTO lt_row.
      lv_index = sy-tabix.
      READ TABLE lt_row INTO lv_order INDEX 1.
      cl_abap_unit_assert=>assert_subrc( ).
      IF lv_index = 1.
        rv_orders = lv_order.
      ELSE.
        CONCATENATE rv_orders lv_order INTO rv_orders SEPARATED BY ','.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD cell.
    DATA ls_table TYPE zif_rx_types=>ty_table.
    DATA lt_row TYPE string_table.

    ls_table = table( is_result ).
    READ TABLE ls_table-rows INTO lt_row INDEX iv_row.
    IF sy-subrc <> 0.
      cl_abap_unit_assert=>fail( msg = 'Linha não encontrada' ).
    ENDIF.
    READ TABLE lt_row INTO rv_value INDEX iv_col.
    IF sy-subrc <> 0.
      cl_abap_unit_assert=>fail( msg = 'Coluna não encontrada' ).
    ENDIF.
  ENDMETHOD.

  METHOD join.
    DATA lv_text TYPE string.

    LOOP AT it_texts INTO lv_text.
      IF sy-tabix = 1.
        rv_text = lv_text.
      ELSE.
        CONCATENATE rv_text lv_text INTO rv_text SEPARATED BY ','.
      ENDIF.
    ENDLOOP.
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

  METHOD fact.
    DATA ls_fact TYPE zif_rx_types=>ty_fact.

    READ TABLE is_result-facts INTO ls_fact WITH KEY id = iv_id.
    IF sy-subrc <> 0.
      cl_abap_unit_assert=>fail( msg = 'Fato não encontrado' detail = iv_id ).
    ENDIF.
    rv_value = ls_fact-value.
  ENDMETHOD.

  METHOD has_fact.
    READ TABLE is_result-facts WITH KEY id = iv_id TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      rv_has = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD metadata.
    DATA ls_meta TYPE zif_rx_types=>ty_diag_meta.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.
    DATA lv_names TYPE string.

    ls_meta = mo_cut->get_metadata( ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-id exp = 'SD-10' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-version exp = '1.0' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-module exp = 'SD' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-kind exp = 'LIST' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-title
                                        exp = 'Pedidos de venda travados antes do faturamento' ).
    LOOP AT ls_meta-params INTO ls_param.
      IF sy-tabix = 1.
        lv_names = ls_param-name.
      ELSE.
        CONCATENATE lv_names ls_param-name INTO lv_names SEPARATED BY ','.
      ENDIF.
      cl_abap_unit_assert=>assert_equals( act = ls_param-required exp = abap_false ).
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals( act = lv_names exp = 'salesOrg,stage,maxRows,page' ).

    READ TABLE ls_meta-params INTO ls_param INDEX 1.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Organização de vendas' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'STRING' ).
    READ TABLE ls_meta-params INTO ls_param INDEX 2.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Etapa' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'ENUM' ).
    cl_abap_unit_assert=>assert_equals( act = join( ls_param-options ) exp = 'CREDIT,DELIVERY,GOODS_ISSUE,BILLING' ).
    READ TABLE ls_meta-params INTO ls_param INDEX 3.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Linhas por página' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'INTEGER' ).
    READ TABLE ls_meta-params INTO ls_param INDEX 4.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Página' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'INTEGER' ).
  ENDMETHOD.

  METHOD all_open_orders.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    " Mais antigo primeiro; o 4500004 (faturado) não entra.
    ls_result = run( ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-kind exp = 'SALES_ORG' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '*' ).
    cl_abap_unit_assert=>assert_equals( act = orders( ls_result )
                                        exp = '4500003,4500001,4500002,4500005,4500006,4500007' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD10.PAST_REQUESTED_DATE' ).
  ENDMETHOD.

  METHOD table_columns.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_table TYPE zif_rx_types=>ty_table.
    DATA lv_keys TYPE string.
    DATA lv_columns TYPE string.

    ls_result = run( ).
    ls_table = table( ls_result ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-id exp = 'salesOrders' ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-title exp = 'Pedidos de venda' ).
    lv_keys = 'salesOrder,customer,netValue,createdOn,requestedDate,'.
    CONCATENATE lv_keys 'stage,stageCode,reason,daysOpen' INTO lv_keys.
    cl_abap_unit_assert=>assert_equals( act = join( ls_table-keys ) exp = lv_keys ).
    lv_columns = 'Pedido,Cliente,Valor líquido,Criado em,Data desejada,'.
    CONCATENATE lv_columns 'Etapa,Código da etapa,Motivo,Dias em aberto' INTO lv_columns.
    cl_abap_unit_assert=>assert_equals( act = join( ls_table-columns ) exp = lv_columns ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_false ).
  ENDMETHOD.

  METHOD first_row.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    " 4500003: criado há 9 dias, desejado há 2 dias, remessa 80000123 sem saída de mercadoria.
    ls_result = run( ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 1 iv_col = 1 ) exp = '4500003' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 1 iv_col = 2 )
                                        exp = '100777 · Saneamento Litoral S.A.' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 1 iv_col = 3 )
                                        exp = 'R$ 96.300,00' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 1 iv_col = 4 )
                                        exp = '2026-09-30' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 1 iv_col = 5 )
                                        exp = '2026-10-07' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 1 iv_col = 6 )
                                        exp = 'Saída de mercadoria' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 1 iv_col = 7 )
                                        exp = 'GOODS_ISSUE' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 1 iv_col = 8 )
                                        exp = 'Remessa 80000123 sem saída de mercadoria' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 1 iv_col = 9 ) exp = '9' ).
  ENDMETHOD.

  METHOD reasons.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( ).
    " Linha 2 = 4500001 (crédito), 3 = 4500002 (remessa), 4 = 4500005 (faturamento), 6 = 4500007.
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 2 iv_col = 7 ) exp = 'CREDIT' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 2 iv_col = 8 )
                                        exp = 'Bloqueio de crédito' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 3 iv_col = 7 ) exp = 'DELIVERY' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 3 iv_col = 8 )
                                        exp = 'Bloqueio de remessa + pedido incompleto' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 4 iv_col = 7 ) exp = 'BILLING' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 4 iv_col = 8 )
                                        exp = 'Bloqueio de faturamento (verificar preço)' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 6 iv_col = 7 ) exp = 'DELIVERY' ).
    cl_abap_unit_assert=>assert_equals( act = cell( is_result = ls_result iv_row = 6 iv_col = 8 )
                                        exp = 'Pedido incompleto' ).
  ENDMETHOD.

  METHOD totals_and_stages.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_fact TYPE zif_rx_types=>ty_fact.
    DATA lv_ids TYPE string.
    DATA lv_exp TYPE string.

    ls_result = run( ).
    LOOP AT ls_result-facts INTO ls_fact.
      IF sy-tabix = 1.
        lv_ids = ls_fact-id.
      ELSE.
        CONCATENATE lv_ids ls_fact-id INTO lv_ids SEPARATED BY ','.
      ENDIF.
    ENDLOOP.
    lv_exp = 'total,totalValue,stage:CREDIT,stage:DELIVERY,'.
    CONCATENATE lv_exp 'stage:GOODS_ISSUE,stage:BILLING' INTO lv_exp.
    cl_abap_unit_assert=>assert_equals( act = lv_ids exp = lv_exp ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '6' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'totalValue' )
                                        exp = 'R$ 348.860,50' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'stage:CREDIT' ) exp = '2' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'stage:DELIVERY' ) exp = '2' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'stage:GOODS_ISSUE' ) exp = '1' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'stage:BILLING' ) exp = '1' ).
  ENDMETHOD.

  METHOD past_requested_date.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.

    ls_result = run( ).
    READ TABLE ls_result-findings INTO ls_finding INDEX 1.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-code exp = 'SD10.PAST_REQUESTED_DATE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'WARNING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title
                                        exp = '1 pedido(s) já passaram da data desejada pelo cliente' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-detail
                                        exp = 'Pedidos: 4500003. Use o SD-01 para ver a causa de cada um.' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'VA05' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-description
                                        exp = 'Lista de pedidos de venda' ).
    cl_abap_unit_assert=>assert_initial( ls_finding-evidence ).
  ENDMETHOD.

  METHOD several_late_orders.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    FIELD-SYMBOLS <ls_header> TYPE zif_rx_sd_reader=>ty_order_header.

    " O 4500001 também passa da data desejada: os pedidos saem na ordem da lista.
    READ TABLE mo_reader->mt_headers ASSIGNING <ls_header> WITH KEY vbeln = '0004500001'.
    cl_abap_unit_assert=>assert_subrc( ).
    <ls_header>-vdatu = '20261001'.

    ls_result = run( ).
    READ TABLE ls_result-findings INTO ls_finding INDEX 1.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title
                                        exp = '2 pedido(s) já passaram da data desejada pelo cliente' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-detail
                                        exp = 'Pedidos: 4500003, 4500001. Use o SD-01 para ver a causa de cada um.' ).
  ENDMETHOD.

  METHOD filter_by_stage.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_stage = 'CREDIT' ).
    cl_abap_unit_assert=>assert_equals( act = orders( ls_result ) exp = '4500001,4500006' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '2' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'totalValue' )
                                        exp = 'R$ 202.650,00' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'stage:CREDIT' ) exp = '2' ).
    cl_abap_unit_assert=>assert_equals( act = has_fact( is_result = ls_result iv_id = 'stage:BILLING' )
                                        exp = abap_false ).
    " Nenhum dos dois passou da data desejada: sem achado e status OK.
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'OK' ).
    cl_abap_unit_assert=>assert_initial( ls_result-findings ).
  ENDMETHOD.

  METHOD filter_by_delivery_stage.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_stage = 'DELIVERY' ).
    cl_abap_unit_assert=>assert_equals( act = orders( ls_result ) exp = '4500002,4500007' ).

    ls_result = run( iv_stage = 'GOODS_ISSUE' ).
    cl_abap_unit_assert=>assert_equals( act = orders( ls_result ) exp = '4500003' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).

    ls_result = run( iv_stage = 'BILLING' ).
    cl_abap_unit_assert=>assert_equals( act = orders( ls_result ) exp = '4500005' ).
  ENDMETHOD.

  METHOD filter_by_sales_org.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_sales_org = '1000' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '1000' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '6' ).

    " Outra organização: lista vazia, sem erro.
    ls_result = run( iv_sales_org = '2000' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '2000' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'OK' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '0' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'totalValue' ) exp = 'R$ 0,00' ).
    cl_abap_unit_assert=>assert_initial( table( ls_result )-rows ).
  ENDMETHOD.

  METHOD pagination.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_max_rows = '2' iv_page = '1' ).
    cl_abap_unit_assert=>assert_equals( act = orders( ls_result ) exp = '4500003,4500001' ).
    cl_abap_unit_assert=>assert_equals( act = table( ls_result )-truncated exp = abap_true ).
    " Os totais são do conjunto todo, não da página.
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '6' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'totalValue' )
                                        exp = 'R$ 348.860,50' ).

    ls_result = run( iv_max_rows = '2' iv_page = '2' ).
    cl_abap_unit_assert=>assert_equals( act = orders( ls_result ) exp = '4500002,4500005' ).
    cl_abap_unit_assert=>assert_equals( act = table( ls_result )-truncated exp = abap_true ).

    ls_result = run( iv_max_rows = '2' iv_page = '3' ).
    cl_abap_unit_assert=>assert_equals( act = orders( ls_result ) exp = '4500006,4500007' ).
    cl_abap_unit_assert=>assert_equals( act = table( ls_result )-truncated exp = abap_false ).

    " Página além do fim: tabela vazia, e o achado continua valendo para o conjunto.
    ls_result = run( iv_max_rows = '2' iv_page = '4' ).
    cl_abap_unit_assert=>assert_initial( table( ls_result )-rows ).
    cl_abap_unit_assert=>assert_equals( act = table( ls_result )-truncated exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'SD10.PAST_REQUESTED_DATE' ).
  ENDMETHOD.

  METHOD default_page_size.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    " maxRows 0 ou página 0 voltam ao padrão (100 linhas, página 1), como no sap-mock.
    ls_result = run( iv_max_rows = '0' iv_page = '0' ).
    cl_abap_unit_assert=>assert_equals( act = lines( table( ls_result )-rows ) exp = 6 ).
    cl_abap_unit_assert=>assert_equals( act = table( ls_result )-truncated exp = abap_false ).
  ENDMETHOD.

  METHOD omits_rows_without_auth.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    FIELD-SYMBOLS <ls_header> TYPE zif_rx_sd_reader=>ty_order_header.

    " O 4500005 é de outra organização de vendas, sem autorização: a linha some e os totais refletem isso.
    READ TABLE mo_reader->mt_headers ASSIGNING <ls_header> WITH KEY vbeln = '0004500005'.
    cl_abap_unit_assert=>assert_subrc( ).
    <ls_header>-vkorg = '2000'.
    APPEND '2000' TO mo_reader->mt_denied_orgs.

    ls_result = run( ).
    cl_abap_unit_assert=>assert_equals( act = orders( ls_result ) exp = '4500003,4500001,4500002,4500006,4500007' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '5' ).
    cl_abap_unit_assert=>assert_equals( act = has_fact( is_result = ls_result iv_id = 'stage:BILLING' )
                                        exp = abap_false ).
  ENDMETHOD.

  METHOD not_authorized_sales_org.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA lx_error TYPE REF TO zcx_rx_error.

    " Org. de vendas informada e sem V_VBAK_VKO: erro 403.
    add_param( EXPORTING iv_name = 'salesOrg' iv_value = '1000' CHANGING ct_params = lt_params ).
    APPEND '1000' TO mo_reader->mt_denied_orgs.
    TRY.
        mo_cut->execute( lt_params ).
        cl_abap_unit_assert=>fail( 'Deveria negar o acesso' ).
      CATCH zcx_rx_error INTO lx_error.
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_http_status exp = 403 ).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'NOT_AUTHORIZED' ).
    ENDTRY.
  ENDMETHOD.

  METHOD totals_per_currency.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA lv_exp TYPE string.
    FIELD-SYMBOLS <ls_header> TYPE zif_rx_sd_reader=>ty_order_header.

    " Valores em moedas diferentes não se somam.
    READ TABLE mo_reader->mt_headers ASSIGNING <ls_header> WITH KEY vbeln = '0004500006'.
    cl_abap_unit_assert=>assert_subrc( ).
    <ls_header>-waerk = 'USD'.

    ls_result = run( ).
    lv_exp = 'R$ 194.660,50;'.
    CONCATENATE lv_exp '154.200,00 USD' INTO lv_exp SEPARATED BY space.
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'totalValue' ) exp = lv_exp ).
  ENDMETHOD.

ENDCLASS.
