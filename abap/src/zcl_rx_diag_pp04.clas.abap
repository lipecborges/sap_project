"! PP-04: lista de ordens de produção por situação (atrasadas, liberadas, apontadas…), paginada.
"! Cada ordem é classificada com a mesma regra do PP-03 (ZCL_RX_PP_STATUS_MAP). Ordens sem
"! autorização (C_AFKO_AWK) são omitidas e o total omitido é informado em um fato.
"! Mesmos totais (situation:<CÓDIGO> / flag:<CÓDIGO>), tabela "orders" e achados do simulador.
CLASS zcl_rx_diag_pp04 DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_rx_diagnostic.

    "! Sem IO_READER usa o leitor real; sem IV_TODAY usa SY-DATUM.
    METHODS constructor
      IMPORTING io_reader TYPE REF TO zif_rx_pp_reader OPTIONAL
                iv_today  TYPE d OPTIONAL.

  PRIVATE SECTION.
    CONSTANTS c_default_rows TYPE i VALUE 100.
    " Período padrão pelo fim programado: últimos 90 dias até hoje + 30 (catálogo).
    CONSTANTS c_default_days_back TYPE i VALUE 90.
    CONSTANTS c_default_days_ahead TYPE i VALUE 30.

    TYPES:
      BEGIN OF ty_item,
        seq               TYPE i,
        finish_delay_days TYPE i,
        start_delay_days  TYPE i,
        order             TYPE zif_rx_pp_reader=>ty_order,
        classification    TYPE zcl_rx_pp_status_map=>ty_classification,
      END OF ty_item,
      ty_items TYPE STANDARD TABLE OF ty_item WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_count,
        id    TYPE string,
        label TYPE string,
        count TYPE i,
      END OF ty_count,
      ty_counts TYPE STANDARD TABLE OF ty_count WITH DEFAULT KEY.

    DATA mo_reader TYPE REF TO zif_rx_pp_reader.
    DATA mv_today TYPE d.

    METHODS read_filter
      IMPORTING it_params        TYPE zif_rx_types=>ty_params
      RETURNING VALUE(rs_filter) TYPE zif_rx_pp_reader=>ty_filter.

    "! Remove as ordens sem autorização; levanta 403 se nenhuma restar.
    METHODS authorize
      IMPORTING iv_plant   TYPE csequence
      CHANGING  ct_orders  TYPE zif_rx_pp_reader=>ty_orders
                cv_omitted TYPE i
      RAISING   zcx_rx_error.

    METHODS classify_all
      IMPORTING it_orders       TYPE zif_rx_pp_reader=>ty_orders
      RETURNING VALUE(rt_items) TYPE ty_items.

    METHODS keep_situation
      IMPORTING iv_situation TYPE string
      CHANGING  ct_items     TYPE ty_items.

    METHODS add_count_facts
      IMPORTING it_items   TYPE ty_items
                iv_omitted TYPE i
      CHANGING  cs_result  TYPE zif_rx_types=>ty_result.

    METHODS add_orders_table
      IMPORTING it_items    TYPE ty_items
                iv_max_rows TYPE i
                iv_page     TYPE i
      CHANGING  cs_result   TYPE zif_rx_types=>ty_result.

    METHODS add_order_row
      IMPORTING is_item TYPE ty_item
      CHANGING  ct_rows TYPE zif_rx_types=>ty_rows.

    METHODS add_summary_findings
      IMPORTING it_items  TYPE ty_items
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_list_finding
      IMPORTING iv_code   TYPE csequence
                iv_title  TYPE csequence
                iv_intro  TYPE csequence
                iv_hint   TYPE csequence
                iv_tcode  TYPE csequence
                iv_action TYPE csequence
                it_orders TYPE string_table
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    CLASS-METHODS bump
      IMPORTING iv_id     TYPE csequence
                iv_label  TYPE csequence
      CHANGING  ct_counts TYPE ty_counts.

    CLASS-METHODS add_param
      IMPORTING iv_name     TYPE csequence
                iv_label    TYPE csequence
                iv_type     TYPE csequence
                iv_required TYPE abap_bool DEFAULT abap_false
                it_options  TYPE string_table OPTIONAL
      CHANGING  ct_params   TYPE zif_rx_types=>ty_param_metas.

    CLASS-METHODS to_int
      IMPORTING iv_text       TYPE csequence
      RETURNING VALUE(rv_int) TYPE i.

ENDCLASS.



CLASS zcl_rx_diag_pp04 IMPLEMENTATION.

  METHOD constructor.
    IF io_reader IS BOUND.
      mo_reader = io_reader.
    ELSE.
      CREATE OBJECT mo_reader TYPE zcl_rx_pp_reader.
    ENDIF.
    IF iv_today IS INITIAL.
      mv_today = sy-datum.
    ELSE.
      mv_today = iv_today.
    ENDIF.
  ENDMETHOD.


  METHOD zif_rx_diagnostic~get_metadata.
    DATA lt_options TYPE string_table.
    DATA lt_flags TYPE string_table.

    rs_meta-id = 'PP-04'.
    rs_meta-version = '1.0'.
    rs_meta-module = 'PP'.
    rs_meta-kind = 'LIST'.
    rs_meta-title = 'Ordens de produção por situação'.

    " Opções do filtro: as situações seguidas dos sinalizadores (mesma ordem do contrato).
    lt_options = zcl_rx_pp_status_map=>all_situations( ).
    lt_flags = zcl_rx_pp_status_map=>all_flags( ).
    APPEND LINES OF lt_flags TO lt_options.

    add_param( EXPORTING iv_name = 'plant' iv_label = 'Centro' iv_type = zif_rx_types=>c_data_type-string
                         iv_required = abap_true
               CHANGING  ct_params = rs_meta-params ).
    add_param( EXPORTING iv_name = 'situation' iv_label = 'Situação' iv_type = zif_rx_types=>c_data_type-enum
                         it_options = lt_options
               CHANGING  ct_params = rs_meta-params ).
    add_param( EXPORTING iv_name = 'mrpController' iv_label = 'Planejador MRP'
                         iv_type = zif_rx_types=>c_data_type-string
               CHANGING  ct_params = rs_meta-params ).
    add_param( EXPORTING iv_name = 'orderType' iv_label = 'Tipo de ordem' iv_type = zif_rx_types=>c_data_type-string
               CHANGING  ct_params = rs_meta-params ).
    add_param( EXPORTING iv_name = 'material' iv_label = 'Material' iv_type = zif_rx_types=>c_data_type-string
               CHANGING  ct_params = rs_meta-params ).
    add_param( EXPORTING iv_name = 'dateFrom' iv_label = 'Fim programado de' iv_type = zif_rx_types=>c_data_type-date
               CHANGING  ct_params = rs_meta-params ).
    add_param( EXPORTING iv_name = 'dateTo' iv_label = 'Fim programado até' iv_type = zif_rx_types=>c_data_type-date
               CHANGING  ct_params = rs_meta-params ).
    add_param( EXPORTING iv_name = 'maxRows' iv_label = 'Linhas por página'
                         iv_type = zif_rx_types=>c_data_type-integer
               CHANGING  ct_params = rs_meta-params ).
    add_param( EXPORTING iv_name = 'page' iv_label = 'Página' iv_type = zif_rx_types=>c_data_type-integer
               CHANGING  ct_params = rs_meta-params ).
  ENDMETHOD.


  METHOD zif_rx_diagnostic~execute.
    DATA ls_filter TYPE zif_rx_pp_reader=>ty_filter.
    DATA ls_settings TYPE zif_rx_pp_reader=>ty_settings.
    DATA lt_orders TYPE zif_rx_pp_reader=>ty_orders.
    DATA lt_items TYPE ty_items.
    DATA lv_omitted TYPE i.
    DATA lv_situation TYPE string.
    DATA lv_max_rows TYPE i.
    DATA lv_page TYPE i.
    DATA lv_detail TYPE string.
    DATA lv_plant TYPE string.

    ls_filter = read_filter( it_params ).
    lv_plant = ls_filter-plant.
    rs_result = zcl_rx_result=>create( iv_kind = 'PLANT' iv_id = lv_plant ).

    lt_orders = mo_reader->find_orders( ls_filter ).
    IF lt_orders IS INITIAL AND mo_reader->has_orders( ls_filter-plant ) = abap_false.
      CONCATENATE lv_plant '.' INTO lv_detail.
      CONCATENATE 'Não há ordens de produção no centro' lv_detail INTO lv_detail SEPARATED BY space.
      rs_result-status = zif_rx_types=>c_status-not_found.
      zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP04.NO_ORDERS'
                                            iv_severity = zif_rx_types=>c_severity-info
                                            iv_title    = 'Nenhuma ordem no centro'
                                            iv_detail   = lv_detail
                                  CHANGING  cs_result   = rs_result ).
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'AUFK'
                                             iv_field  = 'WERKS'
                                             iv_value  = lv_plant
                                             iv_label  = 'Centro'
                                   CHANGING  cs_result = rs_result ).
      RETURN.
    ENDIF.

    authorize( EXPORTING iv_plant = ls_filter-plant
               CHANGING  ct_orders = lt_orders cv_omitted = lv_omitted ).
    lt_items = classify_all( lt_orders ).
    lv_situation = zcl_rx_params=>get( it_params = it_params iv_name = 'situation' ).
    keep_situation( EXPORTING iv_situation = lv_situation CHANGING ct_items = lt_items ).
    SORT lt_items BY finish_delay_days DESCENDING start_delay_days DESCENDING seq ASCENDING.

    ls_settings = mo_reader->get_settings( ).
    lv_max_rows = to_int( zcl_rx_params=>get( it_params = it_params iv_name = 'maxRows' ) ).
    IF lv_max_rows <= 0.
      lv_max_rows = c_default_rows.
    ENDIF.
    IF ls_settings-max_rows > 0 AND lv_max_rows > ls_settings-max_rows.
      lv_max_rows = ls_settings-max_rows.
    ENDIF.
    lv_page = to_int( zcl_rx_params=>get( it_params = it_params iv_name = 'page' ) ).
    IF lv_page < 1.
      lv_page = 1.
    ENDIF.

    add_count_facts( EXPORTING it_items = lt_items iv_omitted = lv_omitted CHANGING cs_result = rs_result ).
    add_orders_table( EXPORTING it_items = lt_items iv_max_rows = lv_max_rows iv_page = lv_page
                      CHANGING  cs_result = rs_result ).
    add_summary_findings( EXPORTING it_items = lt_items CHANGING cs_result = rs_result ).
    zcl_rx_result=>settle_status( CHANGING cs_result = rs_result ).
  ENDMETHOD.


  METHOD read_filter.
    DATA lv_date TYPE string.

    rs_filter-plant = zcl_rx_params=>get( it_params = it_params iv_name = 'plant' ).
    TRANSLATE rs_filter-plant TO UPPER CASE.
    rs_filter-mrp_controller = zcl_rx_params=>get( it_params = it_params iv_name = 'mrpController' ).
    TRANSLATE rs_filter-mrp_controller TO UPPER CASE.
    rs_filter-order_type = zcl_rx_params=>get( it_params = it_params iv_name = 'orderType' ).
    TRANSLATE rs_filter-order_type TO UPPER CASE.
    rs_filter-material = zcl_rx_params=>get( it_params = it_params iv_name = 'material' ).
    TRANSLATE rs_filter-material TO UPPER CASE.

    lv_date = zcl_rx_params=>get( it_params = it_params iv_name = 'dateFrom' ).
    rs_filter-date_from = zcl_rx_format=>date_from_iso( lv_date ).
    lv_date = zcl_rx_params=>get( it_params = it_params iv_name = 'dateTo' ).
    rs_filter-date_to = zcl_rx_format=>date_from_iso( lv_date ).
    IF rs_filter-date_from IS INITIAL AND rs_filter-date_to IS INITIAL.
      rs_filter-date_from = mv_today - c_default_days_back.
      rs_filter-date_to = mv_today + c_default_days_ahead.
    ENDIF.
  ENDMETHOD.


  METHOD authorize.
    DATA lt_allowed TYPE zif_rx_pp_reader=>ty_orders.
    DATA lt_types TYPE string_table.
    DATA lt_denied TYPE string_table.
    DATA lv_type TYPE string.
    DATA lv_message TYPE string.
    FIELD-SYMBOLS <ls_order> TYPE zif_rx_pp_reader=>ty_order.

    " Uma checagem por tipo de ordem (o centro é único na consulta).
    LOOP AT ct_orders ASSIGNING <ls_order>.
      lv_type = <ls_order>-order_type.
      READ TABLE lt_types WITH KEY table_line = lv_type TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND lv_type TO lt_types.
        IF mo_reader->is_authorized( iv_plant = iv_plant iv_order_type = lv_type ) = abap_false.
          APPEND lv_type TO lt_denied.
        ENDIF.
      ENDIF.
      READ TABLE lt_denied WITH KEY table_line = lv_type TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        cv_omitted = cv_omitted + 1.
      ELSE.
        APPEND <ls_order> TO lt_allowed.
      ENDIF.
    ENDLOOP.

    IF lt_allowed IS INITIAL AND cv_omitted > 0.
      CONCATENATE 'Sem autorização (objeto C_AFKO_AWK) para as ordens do centro' iv_plant
        INTO lv_message SEPARATED BY space.
      RAISE EXCEPTION TYPE zcx_rx_error
        EXPORTING iv_http_status = 403 iv_code = 'NOT_AUTHORIZED' iv_text = lv_message.
    ENDIF.
    ct_orders = lt_allowed.
  ENDMETHOD.


  METHOD classify_all.
    DATA ls_settings TYPE zif_rx_pp_reader=>ty_settings.
    DATA lt_map TYPE zif_rx_pp_reader=>ty_status_maps.
    DATA lt_aufnr TYPE zif_rx_pp_reader=>ty_aufnrs.
    DATA lt_operations TYPE zif_rx_pp_reader=>ty_operations.
    DATA lt_components TYPE zif_rx_pp_reader=>ty_components.
    DATA lt_confirmations TYPE zif_rx_pp_reader=>ty_confirmations.
    DATA lo_map TYPE REF TO zcl_rx_pp_status_map.
    DATA lv_since TYPE d.
    DATA ls_item TYPE ty_item.
    FIELD-SYMBOLS <ls_order> TYPE zif_rx_pp_reader=>ty_order.

    IF it_orders IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT it_orders ASSIGNING <ls_order>.
      APPEND <ls_order>-aufnr TO lt_aufnr.
    ENDLOOP.
    " Só os estornos da janela recente interessam à classificação.
    lv_since = mv_today - zcl_rx_pp_status_map=>c_reversal_window_days.
    lt_operations = mo_reader->get_operations( lt_aufnr ).
    lt_components = mo_reader->get_components( lt_aufnr ).
    lt_confirmations = mo_reader->get_confirmations( it_aufnr = lt_aufnr iv_since = lv_since ).
    ls_settings = mo_reader->get_settings( ).
    lt_map = mo_reader->get_status_map( ).
    CREATE OBJECT lo_map
      EXPORTING
        iv_today          = mv_today
        iv_tolerance_days = ls_settings-tolerance_days
        it_mapping        = lt_map.

    LOOP AT it_orders ASSIGNING <ls_order>.
      CLEAR ls_item.
      ls_item-seq = sy-tabix.
      ls_item-order = <ls_order>.
      ls_item-classification = lo_map->classify( is_order         = <ls_order>
                                                 it_operations    = lt_operations
                                                 it_components    = lt_components
                                                 it_confirmations = lt_confirmations ).
      ls_item-finish_delay_days = ls_item-classification-finish_delay_days.
      ls_item-start_delay_days = ls_item-classification-start_delay_days.
      APPEND ls_item TO rt_items.
    ENDLOOP.
  ENDMETHOD.


  METHOD keep_situation.
    FIELD-SYMBOLS <ls_item> TYPE ty_item.

    IF iv_situation IS INITIAL.
      RETURN.
    ENDIF.
    " O filtro aceita uma situação principal ou um sinalizador.
    LOOP AT ct_items ASSIGNING <ls_item>.
      IF <ls_item>-classification-situation = iv_situation.
        CONTINUE.
      ENDIF.
      READ TABLE <ls_item>-classification-flags WITH KEY table_line = iv_situation TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        DELETE ct_items.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_count_facts.
    DATA lt_counts TYPE ty_counts.
    DATA lv_id TYPE string.
    DATA lv_label TYPE string.
    DATA lv_flag TYPE string.
    DATA lv_value TYPE string.
    DATA lv_total TYPE i.
    FIELD-SYMBOLS <ls_item> TYPE ty_item.
    FIELD-SYMBOLS <ls_count> TYPE ty_count.

    lv_total = lines( it_items ).
    lv_value = zcl_rx_format=>int( lv_total ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'total' iv_label = 'Ordens encontradas' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).
    IF iv_omitted > 0.
      lv_value = zcl_rx_format=>int( iv_omitted ).
      zcl_rx_result=>add_fact( EXPORTING iv_id = 'omitted' iv_label = 'Ordens omitidas (sem autorização)'
                                         iv_value = lv_value
                               CHANGING  cs_result = cs_result ).
    ENDIF.

    " Totais com id estável (situation:<código> / flag:<código>), na ordem em que aparecem.
    LOOP AT it_items ASSIGNING <ls_item>.
      CONCATENATE 'situation:' <ls_item>-classification-situation INTO lv_id.
      lv_label = zcl_rx_pp_status_map=>situation_label( <ls_item>-classification-situation ).
      bump( EXPORTING iv_id = lv_id iv_label = lv_label CHANGING ct_counts = lt_counts ).
      LOOP AT <ls_item>-classification-flags INTO lv_flag.
        CONCATENATE 'flag:' lv_flag INTO lv_id.
        lv_label = zcl_rx_pp_status_map=>flag_label( lv_flag ).
        bump( EXPORTING iv_id = lv_id iv_label = lv_label CHANGING ct_counts = lt_counts ).
      ENDLOOP.
    ENDLOOP.
    LOOP AT lt_counts ASSIGNING <ls_count>.
      lv_value = zcl_rx_format=>int( <ls_count>-count ).
      zcl_rx_result=>add_fact( EXPORTING iv_id = <ls_count>-id iv_label = <ls_count>-label iv_value = lv_value
                               CHANGING  cs_result = cs_result ).
    ENDLOOP.
  ENDMETHOD.


  METHOD add_orders_table.
    DATA ls_table TYPE zif_rx_types=>ty_table.
    DATA lv_total TYPE i.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    DATA lv_index TYPE i.
    FIELD-SYMBOLS <ls_item> TYPE ty_item.

    ls_table-id = 'orders'.
    ls_table-title = 'Ordens de produção'.
    zcl_rx_result=>add_column( EXPORTING iv_key = 'order' iv_label = 'Ordem' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'material' iv_label = 'Material' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'description' iv_label = 'Descrição' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'planned' iv_label = 'Planejada' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'confirmed' iv_label = 'Confirmada' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'progress' iv_label = '% confirmado' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'delivered' iv_label = 'Entregue' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'situation' iv_label = 'Situação' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'situationCode' iv_label = 'Código da situação'
                               CHANGING  cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'flags' iv_label = 'Sinalizadores' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'flagCodes' iv_label = 'Códigos dos sinalizadores'
                               CHANGING  cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'scheduledFinish' iv_label = 'Fim programado'
                               CHANGING  cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'delayDays' iv_label = 'Dias de atraso'
                               CHANGING  cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'salesOrder' iv_label = 'Pedido de venda'
                               CHANGING  cs_table = ls_table ).

    lv_total = lines( it_items ).
    lv_from = ( iv_page - 1 ) * iv_max_rows.
    lv_to = iv_page * iv_max_rows.
    LOOP AT it_items ASSIGNING <ls_item>.
      lv_index = sy-tabix.
      IF lv_index > lv_from AND lv_index <= lv_to.
        add_order_row( EXPORTING is_item = <ls_item> CHANGING ct_rows = ls_table-rows ).
      ENDIF.
    ENDLOOP.
    IF lv_to < lv_total.
      ls_table-truncated = abap_true.
    ENDIF.
    APPEND ls_table TO cs_result-tables.
  ENDMETHOD.


  METHOD add_order_row.
    DATA lt_row TYPE string_table.
    DATA lt_labels TYPE string_table.
    DATA lv_text TYPE string.
    DATA lv_flag TYPE string.
    DATA lv_vbeln TYPE string.
    DATA lv_posnr TYPE string.
    DATA lv_pct TYPE i.
    FIELD-SYMBOLS <ls_order> TYPE zif_rx_pp_reader=>ty_order.

    ASSIGN is_item-order TO <ls_order>.
    lv_text = zcl_rx_format=>alpha_out( <ls_order>-aufnr ).
    APPEND lv_text TO lt_row.
    lv_text = zcl_rx_format=>alpha_out( <ls_order>-material ).
    APPEND lv_text TO lt_row.
    lv_text = <ls_order>-description.
    APPEND lv_text TO lt_row.
    lv_text = zcl_rx_format=>quantity( iv_value = <ls_order>-planned iv_unit = <ls_order>-unit ).
    APPEND lv_text TO lt_row.
    lv_text = zcl_rx_format=>quantity( iv_value = <ls_order>-confirmed iv_unit = <ls_order>-unit ).
    APPEND lv_text TO lt_row.
    lv_pct = zcl_rx_pp_view=>percent( iv_part = <ls_order>-confirmed iv_total = <ls_order>-planned ).
    lv_text = zcl_rx_format=>int( lv_pct ).
    APPEND lv_text TO lt_row.
    lv_text = zcl_rx_format=>quantity( iv_value = <ls_order>-delivered iv_unit = <ls_order>-unit ).
    APPEND lv_text TO lt_row.
    lv_text = zcl_rx_pp_status_map=>situation_label( is_item-classification-situation ).
    APPEND lv_text TO lt_row.
    lv_text = is_item-classification-situation.
    APPEND lv_text TO lt_row.

    LOOP AT is_item-classification-flags INTO lv_flag.
      lv_text = zcl_rx_pp_status_map=>flag_label( lv_flag ).
      APPEND lv_text TO lt_labels.
    ENDLOOP.
    lv_text = zcl_rx_pp_view=>join( it_values = lt_labels iv_separator = ',' ).
    APPEND lv_text TO lt_row.
    lv_text = zcl_rx_pp_view=>join( it_values = is_item-classification-flags iv_separator = ',' iv_space = abap_false ).
    APPEND lv_text TO lt_row.
    lv_text = zcl_rx_format=>date_iso( <ls_order>-sched_finish ).
    APPEND lv_text TO lt_row.
    lv_text = zcl_rx_format=>int( is_item-classification-finish_delay_days ).
    APPEND lv_text TO lt_row.

    CLEAR lv_text.
    IF <ls_order>-sales_order IS NOT INITIAL.
      lv_vbeln = zcl_rx_format=>alpha_out( <ls_order>-sales_order ).
      lv_posnr = zcl_rx_format=>alpha_out( <ls_order>-sales_item ).
      CONCATENATE lv_vbeln '/' lv_posnr INTO lv_text.
    ENDIF.
    APPEND lv_text TO lt_row.
    APPEND lt_row TO ct_rows.
  ENDMETHOD.


  METHOD add_summary_findings.
    DATA lt_late TYPE string_table.
    DATA lt_missing TYPE string_table.
    DATA lv_order TYPE string.
    FIELD-SYMBOLS <ls_item> TYPE ty_item.

    LOOP AT it_items ASSIGNING <ls_item>.
      lv_order = zcl_rx_format=>alpha_out( <ls_item>-order-aufnr ).
      READ TABLE <ls_item>-classification-flags WITH KEY table_line = zcl_rx_pp_status_map=>c_flag-late_start
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        APPEND lv_order TO lt_late.
      ELSE.
        READ TABLE <ls_item>-classification-flags WITH KEY table_line = zcl_rx_pp_status_map=>c_flag-late_finish
          TRANSPORTING NO FIELDS.
        IF sy-subrc = 0.
          APPEND lv_order TO lt_late.
        ENDIF.
      ENDIF.
      READ TABLE <ls_item>-classification-flags WITH KEY table_line = zcl_rx_pp_status_map=>c_flag-missing_parts
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        APPEND lv_order TO lt_missing.
      ENDIF.
    ENDLOOP.

    add_list_finding( EXPORTING iv_code   = 'PP04.LATE_ORDERS'
                                iv_title  = 'ordem(ns) atrasada(s)'
                                iv_intro  = 'Ordens atrasadas:'
                                iv_hint   = 'Use o PP-03 para ver cada uma.'
                                iv_tcode  = 'COOIS'
                                iv_action = 'Sistema de informação de ordens'
                                it_orders = lt_late
                      CHANGING  cs_result = cs_result ).
    add_list_finding( EXPORTING iv_code   = 'PP04.MISSING_PARTS'
                                iv_title  = 'ordem(ns) com falta de material'
                                iv_intro  = 'Ordens:'
                                iv_hint   = 'Use o PP-01 para o detalhe.'
                                iv_tcode  = 'CO24'
                                iv_action = 'Lista de faltas'
                                it_orders = lt_missing
                      CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_list_finding.
    DATA lv_count TYPE i.
    DATA lv_count_text TYPE string.
    DATA lv_title TYPE string.
    DATA lv_list TYPE string.
    DATA lv_detail TYPE string.

    lv_count = lines( it_orders ).
    IF lv_count = 0.
      RETURN.
    ENDIF.
    lv_count_text = zcl_rx_format=>int( lv_count ).
    CONCATENATE lv_count_text iv_title INTO lv_title SEPARATED BY space.
    lv_list = zcl_rx_pp_view=>join( it_values = it_orders iv_separator = ',' ).
    CONCATENATE lv_list '.' INTO lv_list.
    CONCATENATE iv_intro lv_list iv_hint INTO lv_detail SEPARATED BY space.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = iv_code
                                          iv_severity = zif_rx_types=>c_severity-warning
                                          iv_title    = lv_title
                                          iv_detail   = lv_detail
                                          iv_tcode    = iv_tcode
                                          iv_action   = iv_action
                                CHANGING  cs_result   = cs_result ).
  ENDMETHOD.


  METHOD bump.
    FIELD-SYMBOLS <ls_count> TYPE ty_count.
    DATA ls_count TYPE ty_count.

    READ TABLE ct_counts ASSIGNING <ls_count> WITH KEY id = iv_id.
    IF sy-subrc = 0.
      <ls_count>-count = <ls_count>-count + 1.
    ELSE.
      ls_count-id = iv_id.
      ls_count-label = iv_label.
      ls_count-count = 1.
      APPEND ls_count TO ct_counts.
    ENDIF.
  ENDMETHOD.


  METHOD add_param.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.

    ls_param-name = iv_name.
    ls_param-label = iv_label.
    ls_param-data_type = iv_type.
    ls_param-required = iv_required.
    ls_param-options = it_options.
    APPEND ls_param TO ct_params.
  ENDMETHOD.


  METHOD to_int.
    DATA lv_text TYPE string.

    lv_text = iv_text.
    IF lv_text IS NOT INITIAL AND lv_text CO '0123456789'.
      rv_int = lv_text.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
