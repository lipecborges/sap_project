"! SD-10: Pedidos de venda travados antes do faturamento (lista).
"! Cada pedido aberto é classificado pela primeira etapa travada (crédito → remessa →
"! saída de mercadoria → faturamento), com a mesma regra do SD-01 (ZCL_RX_SD_STAGE).
"! Só lógica: os dados vêm do leitor (ZIF_RX_SD_READER). Paridade com o sap-mock
"! (services/sap-mock/src/fixtures/lists.ts, função sd10).
CLASS zcl_rx_diag_sd10 DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_rx_diagnostic.

    "! IO_READER: sem ele, usa o leitor real (ZCL_RX_SD_READER).
    "! IV_TODAY: sem ele, usa a data do sistema.
    METHODS constructor
      IMPORTING io_reader TYPE REF TO zif_rx_sd_reader OPTIONAL
                iv_today  TYPE d OPTIONAL.

  PRIVATE SECTION.
    " Pedido classificado, pronto para a tabela.
    TYPES:
      BEGIN OF ty_row,
        vbeln     TYPE c LENGTH 10,
        erdat     TYPE d,
        stage     TYPE string,
        reason    TYPE string,
        days_open TYPE i,
        header    TYPE zif_rx_sd_reader=>ty_order_header,
      END OF ty_row,
      ty_rows TYPE STANDARD TABLE OF ty_row WITH DEFAULT KEY.

    " Valor parado por moeda.
    TYPES:
      BEGIN OF ty_total,
        waerk  TYPE c LENGTH 5,
        amount TYPE p LENGTH 15 DECIMALS 2,
      END OF ty_total,
      ty_totals TYPE STANDARD TABLE OF ty_total WITH DEFAULT KEY.

    CONSTANTS:
      c_default_rows  TYPE i VALUE 100,
      c_max_rows      TYPE i VALUE 500,
      " Quantos pedidos abertos o leitor devolve no máximo para classificar.
      c_read_limit    TYPE i VALUE 2000,
      " Quantos números de pedido entram no texto do achado.
      c_listed_orders TYPE i VALUE 20.

    DATA mo_reader TYPE REF TO zif_rx_sd_reader.
    DATA mv_today TYPE d.

    METHODS classify_rows
      IMPORTING iv_sales_org TYPE csequence
                iv_stage     TYPE csequence
      EXPORTING et_rows      TYPE ty_rows
                ev_capped    TYPE abap_bool.

    METHODS add_facts
      IMPORTING it_rows   TYPE ty_rows
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_table
      IMPORTING it_rows   TYPE ty_rows
                iv_rows   TYPE i
                iv_page   TYPE i
                iv_capped TYPE abap_bool
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_past_requested_date
      IMPORTING it_rows   TYPE ty_rows
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS total_value
      IMPORTING it_rows        TYPE ty_rows
      RETURNING VALUE(rv_text) TYPE string.

    METHODS to_int
      IMPORTING iv_text       TYPE csequence
      RETURNING VALUE(rv_int) TYPE i.

    METHODS customer_text
      IMPORTING is_header      TYPE zif_rx_sd_reader=>ty_order_header
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.



CLASS zcl_rx_diag_sd10 IMPLEMENTATION.

  METHOD constructor.
    IF io_reader IS BOUND.
      mo_reader = io_reader.
    ELSE.
      CREATE OBJECT mo_reader TYPE zcl_rx_sd_reader.
    ENDIF.
    IF iv_today IS INITIAL.
      mv_today = sy-datum.
    ELSE.
      mv_today = iv_today.
    ENDIF.
  ENDMETHOD.


  METHOD zif_rx_diagnostic~get_metadata.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.

    rs_meta-id = 'SD-10'.
    rs_meta-version = '1.0'.
    rs_meta-module = 'SD'.
    rs_meta-kind = 'LIST'.
    rs_meta-title = 'Pedidos de venda travados antes do faturamento'.

    ls_param-name = 'salesOrg'.
    ls_param-label = 'Organização de vendas'.
    ls_param-data_type = zif_rx_types=>c_data_type-string.
    ls_param-required = abap_false.
    APPEND ls_param TO rs_meta-params.

    CLEAR ls_param.
    ls_param-name = 'stage'.
    ls_param-label = 'Etapa'.
    ls_param-data_type = zif_rx_types=>c_data_type-enum.
    ls_param-required = abap_false.
    APPEND 'CREDIT' TO ls_param-options.
    APPEND 'DELIVERY' TO ls_param-options.
    APPEND 'GOODS_ISSUE' TO ls_param-options.
    APPEND 'BILLING' TO ls_param-options.
    APPEND ls_param TO rs_meta-params.

    CLEAR ls_param.
    ls_param-name = 'maxRows'.
    ls_param-label = 'Linhas por página'.
    ls_param-data_type = zif_rx_types=>c_data_type-integer.
    ls_param-required = abap_false.
    APPEND ls_param TO rs_meta-params.

    CLEAR ls_param.
    ls_param-name = 'page'.
    ls_param-label = 'Página'.
    ls_param-data_type = zif_rx_types=>c_data_type-integer.
    ls_param-required = abap_false.
    APPEND ls_param TO rs_meta-params.
  ENDMETHOD.


  METHOD zif_rx_diagnostic~execute.
    DATA lv_sales_org TYPE string.
    DATA lv_stage TYPE string.
    DATA lv_object_id TYPE string.
    DATA lv_message TYPE string.
    DATA lv_rows TYPE i.
    DATA lv_page TYPE i.
    DATA lv_capped TYPE abap_bool.
    DATA lt_rows TYPE ty_rows.

    lv_sales_org = zcl_rx_params=>get( it_params = it_params iv_name = 'salesOrg' ).
    lv_stage = zcl_rx_params=>get( it_params = it_params iv_name = 'stage' ).
    lv_rows = to_int( zcl_rx_params=>get( it_params = it_params iv_name = 'maxRows' ) ).
    IF lv_rows <= 0.
      lv_rows = c_default_rows.
    ENDIF.
    IF lv_rows > c_max_rows.
      lv_rows = c_max_rows.
    ENDIF.
    lv_page = to_int( zcl_rx_params=>get( it_params = it_params iv_name = 'page' ) ).
    IF lv_page < 1.
      lv_page = 1.
    ENDIF.

    lv_object_id = lv_sales_org.
    IF lv_object_id IS INITIAL.
      lv_object_id = '*'.
    ENDIF.
    rs_result = zcl_rx_result=>create( iv_kind = 'SALES_ORG' iv_id = lv_object_id ).

    " Organização informada sem autorização: erro. Sem filtro, as linhas sem autorização são omitidas.
    IF lv_sales_org IS NOT INITIAL AND mo_reader->is_authorized( lv_sales_org ) = abap_false.
      CONCATENATE 'Sem autorização para a organização de vendas' lv_sales_org '(objeto V_VBAK_VKO)'
        INTO lv_message SEPARATED BY space.
      RAISE EXCEPTION TYPE zcx_rx_error
        EXPORTING iv_http_status = 403 iv_code = 'NOT_AUTHORIZED' iv_text = lv_message.
    ENDIF.

    classify_rows( EXPORTING iv_sales_org = lv_sales_org
                             iv_stage     = lv_stage
                   IMPORTING et_rows      = lt_rows
                             ev_capped    = lv_capped ).
    add_facts( EXPORTING it_rows = lt_rows CHANGING cs_result = rs_result ).
    add_table( EXPORTING it_rows   = lt_rows
                         iv_rows   = lv_rows
                         iv_page   = lv_page
                         iv_capped = lv_capped
               CHANGING  cs_result = rs_result ).
    add_past_requested_date( EXPORTING it_rows = lt_rows CHANGING cs_result = rs_result ).
    zcl_rx_result=>settle_status( CHANGING cs_result = rs_result ).
  ENDMETHOD.


  METHOD classify_rows.
    DATA lt_orders TYPE zif_rx_sd_reader=>ty_order_headers.
    DATA ls_row TYPE ty_row.
    FIELD-SYMBOLS <ls_order> TYPE zif_rx_sd_reader=>ty_order_header.

    CLEAR et_rows.
    mo_reader->get_open_orders( EXPORTING iv_sales_org = iv_sales_org
                                          iv_max_rows  = c_read_limit
                                IMPORTING et_orders    = lt_orders
                                          ev_truncated = ev_capped ).
    LOOP AT lt_orders ASSIGNING <ls_order>.
      CLEAR ls_row.
      ls_row-stage = zcl_rx_sd_stage=>classify( <ls_order>-state ).
      IF ls_row-stage IS INITIAL OR ls_row-stage = zcl_rx_sd_stage=>c_stage-completed.
        CONTINUE.
      ENDIF.
      IF iv_stage IS NOT INITIAL AND ls_row-stage <> iv_stage.
        CONTINUE.
      ENDIF.
      " Linhas de organizações/tipos sem autorização são omitidas.
      IF mo_reader->is_authorized( iv_vkorg = <ls_order>-vkorg
                                   iv_vtweg = <ls_order>-vtweg
                                   iv_spart = <ls_order>-spart
                                   iv_auart = <ls_order>-auart ) = abap_false.
        CONTINUE.
      ENDIF.
      ls_row-vbeln = <ls_order>-vbeln.
      ls_row-erdat = <ls_order>-erdat.
      ls_row-reason = zcl_rx_sd_stage=>reason( is_state = <ls_order>-state iv_stage = ls_row-stage ).
      IF <ls_order>-erdat IS NOT INITIAL.
        ls_row-days_open = mv_today - <ls_order>-erdat.
      ENDIF.
      ls_row-header = <ls_order>.
      APPEND ls_row TO et_rows.
    ENDLOOP.
    " Mais antigo primeiro.
    SORT et_rows STABLE BY erdat vbeln.
  ENDMETHOD.


  METHOD add_facts.
    DATA lv_value TYPE string.
    DATA lv_count TYPE i.
    DATA lv_stage TYPE string.
    DATA lv_id TYPE string.
    DATA lv_label TYPE string.
    DATA lt_stages TYPE string_table.
    FIELD-SYMBOLS <ls_row> TYPE ty_row.

    lv_value = zcl_rx_format=>int( lines( it_rows ) ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'total' iv_label = 'Pedidos travados' iv_value = lv_value
                             CHANGING cs_result = cs_result ).
    lv_value = total_value( it_rows ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'totalValue' iv_label = 'Valor parado' iv_value = lv_value
                             CHANGING cs_result = cs_result ).

    " Uma contagem por etapa, só das que têm pedidos, na ordem da cadeia.
    APPEND zcl_rx_sd_stage=>c_stage-credit TO lt_stages.
    APPEND zcl_rx_sd_stage=>c_stage-delivery TO lt_stages.
    APPEND zcl_rx_sd_stage=>c_stage-goods_issue TO lt_stages.
    APPEND zcl_rx_sd_stage=>c_stage-billing TO lt_stages.
    LOOP AT lt_stages INTO lv_stage.
      lv_count = 0.
      LOOP AT it_rows ASSIGNING <ls_row> WHERE stage = lv_stage.
        lv_count = lv_count + 1.
      ENDLOOP.
      IF lv_count > 0.
        CONCATENATE 'stage:' lv_stage INTO lv_id.
        lv_value = zcl_rx_format=>int( lv_count ).
        lv_label = zcl_rx_sd_stage=>label( lv_stage ).
        zcl_rx_result=>add_fact( EXPORTING iv_id = lv_id iv_label = lv_label iv_value = lv_value
                                 CHANGING cs_result = cs_result ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_table.
    DATA ls_table TYPE zif_rx_types=>ty_table.
    DATA lt_cells TYPE string_table.
    DATA lv_cell TYPE string.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    DATA lv_index TYPE i.
    FIELD-SYMBOLS <ls_row> TYPE ty_row.

    ls_table-id = 'salesOrders'.
    ls_table-title = 'Pedidos de venda'.
    zcl_rx_result=>add_column( EXPORTING iv_key = 'salesOrder' iv_label = 'Pedido' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'customer' iv_label = 'Cliente' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'netValue' iv_label = 'Valor líquido' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'createdOn' iv_label = 'Criado em' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'requestedDate' iv_label = 'Data desejada'
                               CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'stage' iv_label = 'Etapa' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'stageCode' iv_label = 'Código da etapa'
                               CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'reason' iv_label = 'Motivo' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'daysOpen' iv_label = 'Dias em aberto'
                               CHANGING cs_table = ls_table ).

    " Página IV_PAGE de IV_ROWS linhas.
    lv_from = ( iv_page - 1 ) * iv_rows + 1.
    lv_to = iv_page * iv_rows.
    LOOP AT it_rows ASSIGNING <ls_row>.
      lv_index = sy-tabix.
      IF lv_index < lv_from.
        CONTINUE.
      ENDIF.
      IF lv_index > lv_to.
        EXIT.
      ENDIF.
      CLEAR lt_cells.
      lv_cell = zcl_rx_format=>alpha_out( <ls_row>-vbeln ).
      APPEND lv_cell TO lt_cells.
      lv_cell = customer_text( <ls_row>-header ).
      APPEND lv_cell TO lt_cells.
      lv_cell = zcl_rx_format=>money( iv_amount   = <ls_row>-header-netwr
                                      iv_currency = <ls_row>-header-waerk ).
      APPEND lv_cell TO lt_cells.
      lv_cell = zcl_rx_format=>date_iso( <ls_row>-header-erdat ).
      APPEND lv_cell TO lt_cells.
      lv_cell = zcl_rx_format=>date_iso( <ls_row>-header-vdatu ).
      APPEND lv_cell TO lt_cells.
      lv_cell = zcl_rx_sd_stage=>label( <ls_row>-stage ).
      APPEND lv_cell TO lt_cells.
      APPEND <ls_row>-stage TO lt_cells.
      APPEND <ls_row>-reason TO lt_cells.
      lv_cell = zcl_rx_format=>int( <ls_row>-days_open ).
      APPEND lv_cell TO lt_cells.
      APPEND lt_cells TO ls_table-rows.
    ENDLOOP.

    IF lines( it_rows ) > lv_to OR iv_capped = abap_true.
      ls_table-truncated = abap_true.
    ENDIF.
    APPEND ls_table TO cs_result-tables.
  ENDMETHOD.


  METHOD add_past_requested_date.
    DATA lt_orders TYPE string_table.
    DATA lv_order TYPE string.
    DATA lv_list TYPE string.
    DATA lv_more TYPE i.
    DATA lv_count TYPE i.
    DATA lv_title TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_number TYPE string.
    FIELD-SYMBOLS <ls_row> TYPE ty_row.

    LOOP AT it_rows ASSIGNING <ls_row>.
      IF <ls_row>-header-vdatu IS NOT INITIAL AND mv_today > <ls_row>-header-vdatu.
        lv_order = zcl_rx_format=>alpha_out( <ls_row>-vbeln ).
        APPEND lv_order TO lt_orders.
      ENDIF.
    ENDLOOP.
    lv_count = lines( lt_orders ).
    IF lv_count = 0.
      RETURN.
    ENDIF.

    " Lista só os primeiros pedidos; o resto vira "e mais N".
    IF lv_count > c_listed_orders.
      lv_more = lv_count - c_listed_orders.
      DELETE lt_orders FROM c_listed_orders + 1.
    ENDIF.
    LOOP AT lt_orders INTO lv_order.
      IF sy-tabix = 1.
        lv_list = lv_order.
      ELSE.
        CONCATENATE lv_list ',' INTO lv_list.
        CONCATENATE lv_list lv_order INTO lv_list SEPARATED BY space.
      ENDIF.
    ENDLOOP.
    IF lv_more > 0.
      lv_number = zcl_rx_format=>int( lv_more ).
      CONCATENATE lv_list 'e mais' lv_number INTO lv_list SEPARATED BY space.
    ENDIF.

    lv_number = zcl_rx_format=>int( lv_count ).
    CONCATENATE lv_number 'pedido(s) já passaram da data desejada pelo cliente'
      INTO lv_title SEPARATED BY space.
    CONCATENATE 'Pedidos:' lv_list INTO lv_detail SEPARATED BY space.
    CONCATENATE lv_detail '.' INTO lv_detail.
    CONCATENATE lv_detail 'Use o SD-01 para ver a causa de cada um.' INTO lv_detail SEPARATED BY space.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'SD10.PAST_REQUESTED_DATE'
                                          iv_severity = zif_rx_types=>c_severity-warning
                                          iv_title    = lv_title
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'VA05'
                                          iv_action   = 'Lista de pedidos de venda'
                                CHANGING  cs_result   = cs_result ).
  ENDMETHOD.


  METHOD total_value.
    DATA lt_totals TYPE ty_totals.
    DATA ls_total TYPE ty_total.
    DATA lv_text TYPE string.
    FIELD-SYMBOLS <ls_row> TYPE ty_row.
    FIELD-SYMBOLS <ls_total> TYPE ty_total.

    " Soma por moeda: valores em moedas diferentes não se somam.
    LOOP AT it_rows ASSIGNING <ls_row>.
      READ TABLE lt_totals ASSIGNING <ls_total> WITH KEY waerk = <ls_row>-header-waerk.
      IF sy-subrc <> 0.
        CLEAR ls_total.
        ls_total-waerk = <ls_row>-header-waerk.
        APPEND ls_total TO lt_totals ASSIGNING <ls_total>.
      ENDIF.
      <ls_total>-amount = <ls_total>-amount + <ls_row>-header-netwr.
    ENDLOOP.

    IF lt_totals IS INITIAL.
      ls_total-waerk = 'BRL'.
      ls_total-amount = 0.
      APPEND ls_total TO lt_totals.
    ENDIF.
    LOOP AT lt_totals INTO ls_total.
      lv_text = zcl_rx_format=>money( iv_amount = ls_total-amount iv_currency = ls_total-waerk ).
      IF sy-tabix = 1.
        rv_text = lv_text.
      ELSE.
        CONCATENATE rv_text ';' INTO rv_text.
        CONCATENATE rv_text lv_text INTO rv_text SEPARATED BY space.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD to_int.
    DATA lv_text TYPE string.

    lv_text = iv_text.
    CONDENSE lv_text.
    IF lv_text IS INITIAL OR lv_text CN '0123456789'.
      RETURN.
    ENDIF.
    " Acima de 9 dígitos não cabe no inteiro: vale o maior valor, que o chamador limita.
    IF strlen( lv_text ) > 9.
      rv_int = 999999999.
    ELSE.
      rv_int = lv_text.
    ENDIF.
  ENDMETHOD.


  METHOD customer_text.
    DATA lv_code TYPE string.
    DATA lv_name TYPE string.

    lv_code = zcl_rx_format=>alpha_out( is_header-kunnr ).
    lv_name = is_header-customer_name.
    IF lv_name IS INITIAL.
      rv_text = lv_code.
    ELSE.
      CONCATENATE lv_code '·' lv_name INTO rv_text SEPARATED BY space.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
