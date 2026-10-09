"! MM-10: Faturas de fornecedor bloqueadas ou estacionadas (lista), por vencimento.
"! Só lógica: filtra por autorização, ordena, pagina e totaliza os dados do leitor
"! (ZIF_RX_MM_READER). Mesmo formato do simulador: facts total, totalAmount e state:<SITUAÇÃO>,
"! tabela "invoices" e o achado MM10.OVERDUE.
CLASS zcl_rx_diag_mm10 DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_rx_diagnostic.

    "! IO_READER: leitor de dados (sem ele, cria ZCL_RX_MM_READER).
    "! IV_TODAY: data de hoje (sem ela, SY-DATUM).
    METHODS constructor
      IMPORTING io_reader TYPE REF TO zif_rx_mm_reader OPTIONAL
                iv_today  TYPE d OPTIONAL.

  PRIVATE SECTION.
    CONSTANTS c_blocked TYPE string VALUE 'BLOCKED'.
    CONSTANTS c_parked TYPE string VALUE 'PARKED'.
    CONSTANTS c_default_rows TYPE i VALUE 100.
    CONSTANTS c_max_rows TYPE i VALUE 500.
    CONSTANTS c_select_limit TYPE i VALUE 2000.

    TYPES:
      BEGIN OF ty_total,
        waers  TYPE c LENGTH 5,
        amount TYPE p LENGTH 15 DECIMALS 2,
      END OF ty_total,
      ty_totals TYPE STANDARD TABLE OF ty_total WITH DEFAULT KEY.

    DATA mo_reader TYPE REF TO zif_rx_mm_reader.
    DATA mv_today TYPE d.

    "! Mantém só as faturas de empresas em que o usuário tem F_BKPF_BUK.
    METHODS keep_authorized
      CHANGING ct_pending TYPE zif_rx_mm_reader=>ty_pendings.

    METHODS state_code
      IMPORTING is_pending     TYPE zif_rx_mm_reader=>ty_pending
      RETURNING VALUE(rv_code) TYPE string.

    METHODS state_label
      IMPORTING iv_code         TYPE csequence
      RETURNING VALUE(rv_label) TYPE string.

    METHODS reason_text
      IMPORTING is_pending     TYPE zif_rx_mm_reader=>ty_pending
      RETURNING VALUE(rv_text) TYPE string.

    "! Valor retido: soma por moeda ("R$ 29.250,00"; várias moedas separadas por ponto e vírgula).
    METHODS total_amount
      IMPORTING it_pending     TYPE zif_rx_mm_reader=>ty_pendings
      RETURNING VALUE(rv_text) TYPE string.

    METHODS add_state_facts
      IMPORTING it_pending TYPE zif_rx_mm_reader=>ty_pendings
      CHANGING  cs_result  TYPE zif_rx_types=>ty_result.

    METHODS build_table
      IMPORTING it_pending      TYPE zif_rx_mm_reader=>ty_pendings
                iv_max_rows     TYPE i
                iv_page         TYPE i
      RETURNING VALUE(rs_table) TYPE zif_rx_types=>ty_table.

    METHODS add_overdue
      IMPORTING it_pending TYPE zif_rx_mm_reader=>ty_pendings
      CHANGING  cs_result  TYPE zif_rx_types=>ty_result.

    "! Inteiro positivo do parâmetro, ou o padrão quando vazio/inválido.
    METHODS int_param
      IMPORTING it_params       TYPE zif_rx_types=>ty_params
                iv_name         TYPE csequence
                iv_default      TYPE i
      RETURNING VALUE(rv_value) TYPE i.

ENDCLASS.



CLASS zcl_rx_diag_mm10 IMPLEMENTATION.

  METHOD constructor.
    IF io_reader IS BOUND.
      mo_reader = io_reader.
    ELSE.
      CREATE OBJECT mo_reader TYPE zcl_rx_mm_reader.
    ENDIF.
    IF iv_today IS INITIAL.
      mv_today = sy-datum.
    ELSE.
      mv_today = iv_today.
    ENDIF.
  ENDMETHOD.


  METHOD zif_rx_diagnostic~get_metadata.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.

    rs_meta-id = 'MM-10'.
    rs_meta-version = '1.0'.
    rs_meta-module = 'MM'.
    rs_meta-kind = 'LIST'.
    rs_meta-title = 'Faturas de fornecedor bloqueadas ou pendentes'.

    ls_param-name = 'companyCode'.
    ls_param-label = 'Empresa'.
    ls_param-data_type = zif_rx_types=>c_data_type-string.
    APPEND ls_param TO rs_meta-params.

    CLEAR ls_param.
    ls_param-name = 'state'.
    ls_param-label = 'Situação'.
    ls_param-data_type = zif_rx_types=>c_data_type-enum.
    APPEND c_blocked TO ls_param-options.
    APPEND c_parked TO ls_param-options.
    APPEND ls_param TO rs_meta-params.

    CLEAR ls_param.
    ls_param-name = 'maxRows'.
    ls_param-label = 'Linhas por página'.
    ls_param-data_type = zif_rx_types=>c_data_type-integer.
    APPEND ls_param TO rs_meta-params.

    CLEAR ls_param.
    ls_param-name = 'page'.
    ls_param-label = 'Página'.
    ls_param-data_type = zif_rx_types=>c_data_type-integer.
    APPEND ls_param TO rs_meta-params.
  ENDMETHOD.


  METHOD zif_rx_diagnostic~execute.
    DATA lv_company TYPE string.
    DATA lv_state TYPE string.
    DATA lv_id TYPE string.
    DATA lv_message TYPE string.
    DATA lv_value TYPE string.
    DATA lv_bukrs TYPE zif_rx_mm_reader=>ty_bukrs.
    DATA lv_max_rows TYPE i.
    DATA lv_page TYPE i.
    DATA lt_pending TYPE zif_rx_mm_reader=>ty_pendings.
    DATA ls_table TYPE zif_rx_types=>ty_table.

    lv_company = zcl_rx_params=>get( it_params = it_params iv_name = 'companyCode' ).
    TRANSLATE lv_company TO UPPER CASE.
    lv_state = zcl_rx_params=>get( it_params = it_params iv_name = 'state' ).
    lv_max_rows = int_param( it_params = it_params iv_name = 'maxRows' iv_default = c_default_rows ).
    IF lv_max_rows > c_max_rows.
      lv_max_rows = c_max_rows.
    ENDIF.
    lv_page = int_param( it_params = it_params iv_name = 'page' iv_default = 1 ).

    IF lv_company IS INITIAL.
      lv_id = '*'.
    ELSE.
      lv_id = lv_company.
    ENDIF.
    rs_result = zcl_rx_result=>create( iv_kind = 'COMPANY_CODE' iv_id = lv_id ).

    " Empresa informada sem autorização: erro. Sem filtro de empresa, só as autorizadas entram.
    IF lv_company IS NOT INITIAL.
      lv_bukrs = lv_company.
      IF mo_reader->is_authorized( lv_bukrs ) = abap_false.
        CONCATENATE `Sem autorização para a empresa ` lv_company ` (objeto F_BKPF_BUK).` INTO lv_message.
        RAISE EXCEPTION TYPE zcx_rx_error
          EXPORTING iv_http_status = 403 iv_code = 'NOT_AUTHORIZED' iv_text = lv_message.
      ENDIF.
    ENDIF.

    lt_pending = mo_reader->read_pending( iv_bukrs = lv_bukrs iv_state = lv_state iv_limit = c_select_limit ).
    keep_authorized( CHANGING ct_pending = lt_pending ).
    SORT lt_pending BY due_date ASCENDING belnr ASCENDING gjahr ASCENDING.

    lv_value = zcl_rx_format=>int( lines( lt_pending ) ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'total' iv_label = 'Faturas pendentes' iv_value = lv_value
                             CHANGING  cs_result = rs_result ).
    lv_value = total_amount( lt_pending ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'totalAmount' iv_label = 'Valor retido' iv_value = lv_value
                             CHANGING  cs_result = rs_result ).
    add_state_facts( EXPORTING it_pending = lt_pending CHANGING cs_result = rs_result ).

    ls_table = build_table( it_pending  = lt_pending
                            iv_max_rows = lv_max_rows
                            iv_page     = lv_page ).
    APPEND ls_table TO rs_result-tables.

    add_overdue( EXPORTING it_pending = lt_pending CHANGING cs_result = rs_result ).
    zcl_rx_result=>settle_status( CHANGING cs_result = rs_result ).
  ENDMETHOD.


  METHOD keep_authorized.
    TYPES:
      BEGIN OF ty_auth,
        bukrs   TYPE zif_rx_mm_reader=>ty_bukrs,
        allowed TYPE abap_bool,
      END OF ty_auth.
    DATA lt_auth TYPE STANDARD TABLE OF ty_auth WITH DEFAULT KEY.
    DATA ls_auth TYPE ty_auth.
    FIELD-SYMBOLS <ls_pending> TYPE zif_rx_mm_reader=>ty_pending.
    FIELD-SYMBOLS <ls_auth> TYPE ty_auth.

    " Uma verificação por empresa (F_BKPF_BUK).
    LOOP AT ct_pending ASSIGNING <ls_pending>.
      READ TABLE lt_auth ASSIGNING <ls_auth> WITH KEY bukrs = <ls_pending>-bukrs.
      IF sy-subrc <> 0.
        ls_auth-bukrs = <ls_pending>-bukrs.
        ls_auth-allowed = mo_reader->is_authorized( ls_auth-bukrs ).
        APPEND ls_auth TO lt_auth.
      ENDIF.
    ENDLOOP.
    LOOP AT lt_auth INTO ls_auth WHERE allowed = abap_false.
      DELETE ct_pending WHERE bukrs = ls_auth-bukrs.
    ENDLOOP.
  ENDMETHOD.


  METHOD state_code.
    IF is_pending-parked = abap_true.
      rv_code = c_parked.
    ELSE.
      rv_code = c_blocked.
    ENDIF.
  ENDMETHOD.


  METHOD state_label.
    CASE iv_code.
      WHEN c_blocked.
        rv_label = 'Bloqueada'.
      WHEN c_parked.
        rv_label = 'Estacionada'.
    ENDCASE.
  ENDMETHOD.


  METHOD reason_text.
    DATA lt_reasons TYPE string_table.
    DATA lv_reason TYPE string.

    IF is_pending-parked = abap_true.
      rv_text = 'Estacionada, não lançada'.
      RETURN.
    ENDIF.

    IF is_pending-blocks-spgrp IS NOT INITIAL.
      APPEND `preço` TO lt_reasons.
    ENDIF.
    IF is_pending-blocks-spgrm IS NOT INITIAL.
      APPEND `quantidade` TO lt_reasons.
    ENDIF.
    IF is_pending-blocks-spgrt IS NOT INITIAL.
      APPEND `data` TO lt_reasons.
    ENDIF.
    IF is_pending-blocks-spgrg IS NOT INITIAL.
      APPEND `quantidade do preço do pedido` TO lt_reasons.
    ENDIF.
    IF is_pending-blocks-spgrq IS NOT INITIAL.
      APPEND `manual` TO lt_reasons.
    ENDIF.
    IF is_pending-blocks-spgrs IS NOT INITIAL.
      APPEND `montante` TO lt_reasons.
    ENDIF.
    IF is_pending-blocks-spgrc IS NOT INITIAL.
      APPEND `qualidade` TO lt_reasons.
    ENDIF.
    IF is_pending-blocks-spgrv IS NOT INITIAL.
      APPEND `projeto` TO lt_reasons.
    ENDIF.

    IF lt_reasons IS INITIAL.
      CONCATENATE `Bloqueio de pagamento (chave ` is_pending-zlspr `)` INTO rv_text.
      RETURN.
    ENDIF.
    rv_text = 'Bloqueio por'.
    LOOP AT lt_reasons INTO lv_reason.
      IF sy-tabix > 1.
        CONCATENATE rv_text `,` INTO rv_text.
      ENDIF.
      CONCATENATE rv_text lv_reason INTO rv_text SEPARATED BY space.
    ENDLOOP.
  ENDMETHOD.


  METHOD total_amount.
    DATA lt_totals TYPE ty_totals.
    DATA ls_total TYPE ty_total.
    DATA lv_money TYPE string.
    FIELD-SYMBOLS <ls_pending> TYPE zif_rx_mm_reader=>ty_pending.
    FIELD-SYMBOLS <ls_total> TYPE ty_total.

    LOOP AT it_pending ASSIGNING <ls_pending>.
      READ TABLE lt_totals ASSIGNING <ls_total> WITH KEY waers = <ls_pending>-waers.
      IF sy-subrc = 0.
        <ls_total>-amount = <ls_total>-amount + <ls_pending>-rmwwr.
      ELSE.
        ls_total-waers = <ls_pending>-waers.
        ls_total-amount = <ls_pending>-rmwwr.
        APPEND ls_total TO lt_totals.
      ENDIF.
    ENDLOOP.

    IF lt_totals IS INITIAL.
      ls_total-amount = 0.
      rv_text = zcl_rx_format=>money( iv_amount = ls_total-amount iv_currency = 'BRL' ).
      RETURN.
    ENDIF.
    LOOP AT lt_totals INTO ls_total.
      lv_money = zcl_rx_format=>money( iv_amount = ls_total-amount iv_currency = ls_total-waers ).
      IF sy-tabix = 1.
        rv_text = lv_money.
      ELSE.
        CONCATENATE rv_text `; ` lv_money INTO rv_text.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_state_facts.
    DATA lt_codes TYPE string_table.
    DATA lv_code TYPE string.
    DATA lv_id TYPE string.
    DATA lv_count TYPE i.
    DATA lv_value TYPE string.
    DATA lv_label TYPE string.
    FIELD-SYMBOLS <ls_pending> TYPE zif_rx_mm_reader=>ty_pending.

    APPEND c_blocked TO lt_codes.
    APPEND c_parked TO lt_codes.
    LOOP AT lt_codes INTO lv_code.
      lv_count = 0.
      LOOP AT it_pending ASSIGNING <ls_pending>.
        IF state_code( <ls_pending> ) = lv_code.
          lv_count = lv_count + 1.
        ENDIF.
      ENDLOOP.
      IF lv_count > 0.
        CONCATENATE `state:` lv_code INTO lv_id.
        lv_label = state_label( lv_code ).
        lv_value = zcl_rx_format=>int( lv_count ).
        zcl_rx_result=>add_fact( EXPORTING iv_id = lv_id iv_label = lv_label iv_value = lv_value
                                 CHANGING  cs_result = cs_result ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD build_table.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    DATA lv_total TYPE i.
    DATA lv_index TYPE i.
    DATA lv_code TYPE string.
    DATA lv_days TYPE i.
    DATA lt_row TYPE string_table.
    DATA lv_text TYPE string.
    FIELD-SYMBOLS <ls_pending> TYPE zif_rx_mm_reader=>ty_pending.

    rs_table-id = 'invoices'.
    rs_table-title = 'Faturas de fornecedor'.
    zcl_rx_result=>add_column( EXPORTING iv_key = 'invoice' iv_label = 'Fatura' CHANGING cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'fiscalYear' iv_label = 'Exercício' CHANGING cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'vendor' iv_label = 'Fornecedor' CHANGING cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'grossAmount' iv_label = 'Valor bruto'
                               CHANGING  cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'dueDate' iv_label = 'Vencimento' CHANGING cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'daysToDue' iv_label = 'Dias para vencer'
                               CHANGING  cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'state' iv_label = 'Situação' CHANGING cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'stateCode' iv_label = 'Código da situação'
                               CHANGING  cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'reason' iv_label = 'Motivo' CHANGING cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'purchaseOrder' iv_label = 'Pedido de compra'
                               CHANGING  cs_table = rs_table ).

    lv_total = lines( it_pending ).
    lv_from = ( iv_page - 1 ) * iv_max_rows + 1.
    lv_to = iv_page * iv_max_rows.
    IF lv_to < lv_total.
      rs_table-truncated = abap_true.
    ELSE.
      rs_table-truncated = abap_false.
    ENDIF.

    LOOP AT it_pending ASSIGNING <ls_pending>.
      lv_index = sy-tabix.
      IF lv_index < lv_from OR lv_index > lv_to.
        CONTINUE.
      ENDIF.
      CLEAR lt_row.
      lv_text = zcl_rx_format=>alpha_out( <ls_pending>-belnr ).
      APPEND lv_text TO lt_row.
      lv_text = <ls_pending>-gjahr.
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_format=>alpha_out( <ls_pending>-lifnr ).
      IF <ls_pending>-vendor_name IS NOT INITIAL.
        CONCATENATE lv_text '·' <ls_pending>-vendor_name INTO lv_text SEPARATED BY space.
      ENDIF.
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_format=>money( iv_amount = <ls_pending>-rmwwr iv_currency = <ls_pending>-waers ).
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_format=>date_iso( <ls_pending>-due_date ).
      APPEND lv_text TO lt_row.
      IF <ls_pending>-due_date IS INITIAL.
        lv_text = ''.
      ELSE.
        lv_days = <ls_pending>-due_date - mv_today.
        lv_text = zcl_rx_format=>int( lv_days ).
      ENDIF.
      APPEND lv_text TO lt_row.
      lv_code = state_code( <ls_pending> ).
      lv_text = state_label( lv_code ).
      APPEND lv_text TO lt_row.
      APPEND lv_code TO lt_row.
      lv_text = reason_text( <ls_pending> ).
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_format=>alpha_out( <ls_pending>-ebeln ).
      APPEND lv_text TO lt_row.
      APPEND lt_row TO rs_table-rows.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_overdue.
    DATA lv_count TYPE i.
    DATA lv_list TYPE string.
    DATA lv_invoice TYPE string.
    DATA lv_count_text TYPE string.
    DATA lv_title TYPE string.
    DATA lv_detail TYPE string.
    FIELD-SYMBOLS <ls_pending> TYPE zif_rx_mm_reader=>ty_pending.

    " Vencida = vencimento anterior a hoje (no simulador, vale para bloqueadas e estacionadas).
    LOOP AT it_pending ASSIGNING <ls_pending> WHERE due_date IS NOT INITIAL AND due_date < mv_today.
      lv_count = lv_count + 1.
      lv_invoice = zcl_rx_format=>alpha_out( <ls_pending>-belnr ).
      IF lv_list IS INITIAL.
        lv_list = lv_invoice.
      ELSE.
        CONCATENATE lv_list `, ` lv_invoice INTO lv_list.
      ENDIF.
    ENDLOOP.
    IF lv_count = 0.
      RETURN.
    ENDIF.

    lv_count_text = zcl_rx_format=>int( lv_count ).
    CONCATENATE lv_count_text ` fatura(s) bloqueada(s) ou estacionada(s) já vencida(s)` INTO lv_title.
    CONCATENATE `Faturas: ` lv_list `. O fornecedor pode cobrar juros. Use o MM-02 para a causa.` INTO lv_detail.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'MM10.OVERDUE'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = lv_title
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'MRBR'
                                          iv_action   = 'Liberar faturas bloqueadas'
                                CHANGING  cs_result   = cs_result ).
  ENDMETHOD.


  METHOD int_param.
    DATA lv_text TYPE string.

    rv_value = iv_default.
    lv_text = zcl_rx_params=>get( it_params = it_params iv_name = iv_name ).
    IF lv_text IS INITIAL OR lv_text CN '0123456789'.
      RETURN.
    ENDIF.
    rv_value = lv_text.
    IF rv_value < 1.
      rv_value = iv_default.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
