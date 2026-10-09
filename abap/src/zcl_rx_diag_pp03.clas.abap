"! PP-03: situação da ordem de produção (visão completa): situação resumida, sinalizadores,
"! quantidades, datas, atraso e as tabelas de operações, componentes e apontamentos.
"! Só lógica: os dados vêm do leitor (ZIF_RX_PP_READER) e a classificação de ZCL_RX_PP_STATUS_MAP.
"! Mesmos achados, severidades, ordem e ids de fatos do simulador (sap-mock). Entrada: productionOrder.
CLASS zcl_rx_diag_pp03 DEFINITION
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
    " Quantidade de apontamentos mostrados na tabela (os mais recentes).
    CONSTANTS c_max_confirmations TYPE i VALUE 20.

    DATA mo_reader TYPE REF TO zif_rx_pp_reader.
    DATA mv_today TYPE d.
    DATA mo_map TYPE REF TO zcl_rx_pp_status_map.

    METHODS check_authorization
      IMPORTING is_order TYPE zif_rx_pp_reader=>ty_order
      RAISING   zcx_rx_error.

    METHODS add_identity_facts
      IMPORTING is_order          TYPE zif_rx_pp_reader=>ty_order
                is_classification TYPE zcl_rx_pp_status_map=>ty_classification
      CHANGING  cs_result         TYPE zif_rx_types=>ty_result.

    METHODS add_quantity_facts
      IMPORTING is_order  TYPE zif_rx_pp_reader=>ty_order
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_date_facts
      IMPORTING is_order          TYPE zif_rx_pp_reader=>ty_order
                is_classification TYPE zcl_rx_pp_status_map=>ty_classification
      CHANGING  cs_result         TYPE zif_rx_types=>ty_result.

    METHODS add_operations_table
      IMPORTING is_order      TYPE zif_rx_pp_reader=>ty_order
                it_operations TYPE zif_rx_pp_reader=>ty_operations
      CHANGING  cs_result     TYPE zif_rx_types=>ty_result.

    METHODS add_confirmations_table
      IMPORTING is_order         TYPE zif_rx_pp_reader=>ty_order
                it_confirmations TYPE zif_rx_pp_reader=>ty_confirmations
      CHANGING  cs_result        TYPE zif_rx_types=>ty_result.

    METHODS add_flag_finding
      IMPORTING iv_flag           TYPE string
                is_order          TYPE zif_rx_pp_reader=>ty_order
                is_classification TYPE zcl_rx_pp_status_map=>ty_classification
                it_operations     TYPE zif_rx_pp_reader=>ty_operations
      CHANGING  cs_result         TYPE zif_rx_types=>ty_result.

    METHODS add_late_start
      IMPORTING is_order          TYPE zif_rx_pp_reader=>ty_order
                is_classification TYPE zcl_rx_pp_status_map=>ty_classification
      CHANGING  cs_result         TYPE zif_rx_types=>ty_result.

    METHODS add_late_finish
      IMPORTING is_order          TYPE zif_rx_pp_reader=>ty_order
                is_classification TYPE zcl_rx_pp_status_map=>ty_classification
      CHANGING  cs_result         TYPE zif_rx_types=>ty_result.

    METHODS add_operation_late
      IMPORTING is_order      TYPE zif_rx_pp_reader=>ty_order
                it_operations TYPE zif_rx_pp_reader=>ty_operations
      CHANGING  cs_result     TYPE zif_rx_types=>ty_result.

    METHODS add_confirmed_not_received
      IMPORTING is_order  TYPE zif_rx_pp_reader=>ty_order
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_sales_order_at_risk
      IMPORTING is_order  TYPE zif_rx_pp_reader=>ty_order
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_simple_finding
      IMPORTING iv_flag   TYPE string
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    "! Texto "quantidade (NN%)" em relação ao planejado.
    CLASS-METHODS quantity_with_percent
      IMPORTING iv_value       TYPE zif_rx_pp_reader=>ty_qty
                iv_total       TYPE zif_rx_pp_reader=>ty_qty
                iv_unit        TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

    "! "AAAA-MM-DD → AAAA-MM-DD" (datas vazias aparecem como —).
    CLASS-METHODS date_range
      IMPORTING iv_from        TYPE d
                iv_to          TYPE d
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.



CLASS zcl_rx_diag_pp03 IMPLEMENTATION.

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
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.

    rs_meta-id = 'PP-03'.
    rs_meta-version = '1.0'.
    rs_meta-module = 'PP'.
    rs_meta-kind = 'OBJECT'.
    rs_meta-title = 'Situação da ordem de produção'.
    ls_param-name = 'productionOrder'.
    ls_param-label = 'Ordem de produção'.
    ls_param-data_type = zif_rx_types=>c_data_type-document.
    ls_param-required = abap_true.
    APPEND ls_param TO rs_meta-params.
  ENDMETHOD.


  METHOD zif_rx_diagnostic~execute.
    DATA lv_input TYPE string.
    DATA lv_aufnr TYPE zif_rx_pp_reader=>ty_aufnr.
    DATA lv_display TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_sales_order TYPE string.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.
    DATA ls_settings TYPE zif_rx_pp_reader=>ty_settings.
    DATA ls_classification TYPE zcl_rx_pp_status_map=>ty_classification.
    DATA lt_aufnr TYPE zif_rx_pp_reader=>ty_aufnrs.
    DATA lt_map TYPE zif_rx_pp_reader=>ty_status_maps.
    DATA lt_operations TYPE zif_rx_pp_reader=>ty_operations.
    DATA lt_components TYPE zif_rx_pp_reader=>ty_components.
    DATA lt_confirmations TYPE zif_rx_pp_reader=>ty_confirmations.
    DATA lv_flag TYPE string.

    lv_input = zcl_rx_params=>get( it_params = it_params iv_name = 'productionOrder' ).
    lv_aufnr = zcl_rx_format=>alpha_in( iv_value = lv_input iv_length = 12 ).
    lv_display = zcl_rx_format=>alpha_out( lv_aufnr ).
    rs_result = zcl_rx_result=>create( iv_kind = 'PRODUCTION_ORDER' iv_id = lv_display ).

    ls_order = mo_reader->get_order( lv_aufnr ).
    IF ls_order-aufnr IS INITIAL.
      CONCATENATE 'A ordem de produção' lv_display 'não existe neste sistema/mandante.'
        INTO lv_detail SEPARATED BY space.
      zcl_rx_result=>set_not_found( EXPORTING iv_prefix = 'PP03'
                                              iv_title  = 'Ordem não encontrada'
                                              iv_detail = lv_detail
                                              iv_source = 'AUFK'
                                              iv_field  = 'AUFNR'
                                              iv_value  = lv_display
                                              iv_label  = 'Ordem de produção'
                                    CHANGING  cs_result = rs_result ).
      RETURN.
    ENDIF.
    check_authorization( ls_order ).

    APPEND ls_order-aufnr TO lt_aufnr.
    lt_operations = mo_reader->get_operations( lt_aufnr ).
    lt_components = mo_reader->get_components( lt_aufnr ).
    lt_confirmations = mo_reader->get_confirmations( lt_aufnr ).
    lt_map = mo_reader->get_status_map( ).
    ls_settings = mo_reader->get_settings( ).
    CREATE OBJECT mo_map
      EXPORTING
        iv_today          = mv_today
        iv_tolerance_days = ls_settings-tolerance_days
        it_mapping        = lt_map.
    ls_classification = mo_map->classify( is_order         = ls_order
                                          it_operations    = lt_operations
                                          it_components    = lt_components
                                          it_confirmations = lt_confirmations ).

    add_identity_facts( EXPORTING is_order = ls_order is_classification = ls_classification
                        CHANGING  cs_result = rs_result ).
    add_quantity_facts( EXPORTING is_order = ls_order CHANGING cs_result = rs_result ).
    add_date_facts( EXPORTING is_order = ls_order is_classification = ls_classification
                    CHANGING  cs_result = rs_result ).
    IF ls_order-sales_order IS NOT INITIAL.
      lv_sales_order = zcl_rx_format=>alpha_out( ls_order-sales_order ).
      zcl_rx_result=>add_related( EXPORTING iv_kind = 'SALES_ORDER' iv_id = lv_sales_order
                                  CHANGING  cs_result = rs_result ).
    ENDIF.

    add_operations_table( EXPORTING is_order = ls_order it_operations = lt_operations
                          CHANGING  cs_result = rs_result ).
    APPEND zcl_rx_pp_view=>components_table( iv_aufnr = ls_order-aufnr it_components = lt_components )
      TO rs_result-tables.
    add_confirmations_table( EXPORTING is_order = ls_order it_confirmations = lt_confirmations
                             CHANGING  cs_result = rs_result ).

    LOOP AT ls_classification-flags INTO lv_flag.
      add_flag_finding( EXPORTING iv_flag           = lv_flag
                                  is_order          = ls_order
                                  is_classification = ls_classification
                                  it_operations     = lt_operations
                        CHANGING  cs_result         = rs_result ).
    ENDLOOP.
    zcl_rx_result=>settle_status( CHANGING cs_result = rs_result ).
  ENDMETHOD.


  METHOD check_authorization.
    DATA lv_message TYPE string.

    IF mo_reader->is_authorized( iv_plant = is_order-plant iv_order_type = is_order-order_type ) = abap_true.
      RETURN.
    ENDIF.
    CONCATENATE 'Sem autorização (objeto C_AFKO_AWK) para o centro' is_order-plant
                'e o tipo de ordem' is_order-order_type
      INTO lv_message SEPARATED BY space.
    RAISE EXCEPTION TYPE zcx_rx_error
      EXPORTING iv_http_status = 403 iv_code = 'NOT_AUTHORIZED' iv_text = lv_message.
  ENDMETHOD.


  METHOD add_identity_facts.
    DATA lv_value TYPE string.
    DATA lv_a TYPE string.
    DATA lv_b TYPE string.
    DATA lv_label TYPE string.
    DATA lt_labels TYPE string_table.
    DATA lt_texts TYPE string_table.
    DATA lv_flag TYPE string.
    FIELD-SYMBOLS <ls_user> TYPE zif_rx_pp_reader=>ty_user_status.

    lv_a = zcl_rx_format=>alpha_out( is_order-material ).
    lv_b = is_order-description.
    CONCATENATE lv_a '·' lv_b INTO lv_value SEPARATED BY space.
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'material' iv_label = 'Material' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).

    lv_a = is_order-plant.
    lv_b = is_order-order_type.
    CONCATENATE lv_a '/' lv_b INTO lv_value SEPARATED BY space.
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'plant' iv_label = 'Centro / tipo' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).

    lv_a = is_order-mrp_controller.
    lv_b = is_order-scheduler.
    CONCATENATE lv_a '/' lv_b INTO lv_value SEPARATED BY space.
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'mrpController' iv_label = 'Planejador MRP / responsável'
                                       iv_value = lv_value
                             CHANGING  cs_result = cs_result ).

    lv_value = zcl_rx_pp_status_map=>situation_label( is_classification-situation ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'situation' iv_label = 'Situação' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).

    LOOP AT is_classification-flags INTO lv_flag.
      lv_label = zcl_rx_pp_status_map=>flag_label( lv_flag ).
      APPEND lv_label TO lt_labels.
    ENDLOOP.
    lv_value = zcl_rx_pp_view=>join( it_values = lt_labels iv_separator = ',' ).
    IF lv_value IS INITIAL.
      lv_value = 'Nenhum'.
    ENDIF.
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'flags' iv_label = 'Sinalizadores' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).

    lv_value = zcl_rx_pp_view=>status_text( is_order-system_status ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'systemStatus' iv_label = 'Status de sistema' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).

    LOOP AT is_order-user_status ASSIGNING <ls_user>.
      lv_a = <ls_user>-text.
      APPEND lv_a TO lt_texts.
    ENDLOOP.
    lv_value = zcl_rx_pp_view=>join( it_values = lt_texts iv_separator = ',' ).
    IF lv_value IS INITIAL.
      lv_value = '—'.
    ENDIF.
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'userStatus' iv_label = 'Status de usuário' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_quantity_facts.
    DATA lv_value TYPE string.

    lv_value = zcl_rx_format=>quantity( iv_value = is_order-planned iv_unit = is_order-unit ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'planned' iv_label = 'Quantidade planejada' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).

    lv_value = quantity_with_percent( iv_value = is_order-confirmed
                                      iv_total = is_order-planned
                                      iv_unit  = is_order-unit ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'confirmed' iv_label = 'Confirmada (apontada)' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).

    lv_value = zcl_rx_format=>quantity( iv_value = is_order-scrap iv_unit = is_order-unit ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'scrap' iv_label = 'Refugo' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).

    lv_value = quantity_with_percent( iv_value = is_order-delivered
                                      iv_total = is_order-planned
                                      iv_unit  = is_order-unit ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'delivered' iv_label = 'Entregue no estoque' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_date_facts.
    DATA lv_value TYPE string.
    DATA lv_start TYPE string.
    DATA lv_finish TYPE string.
    DATA lv_vbeln TYPE string.
    DATA lv_posnr TYPE string.
    DATA lv_item TYPE string.
    DATA lv_requested TYPE string.

    lv_value = date_range( iv_from = is_order-basic_start iv_to = is_order-basic_finish ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'basicDates' iv_label = 'Datas base' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).
    lv_value = date_range( iv_from = is_order-sched_start iv_to = is_order-sched_finish ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'scheduledDates' iv_label = 'Datas programadas' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).
    lv_value = date_range( iv_from = is_order-actual_start iv_to = is_order-actual_finish ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'actualDates' iv_label = 'Datas reais' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).

    IF is_classification-start_delay_days = 0 AND is_classification-finish_delay_days = 0.
      lv_value = 'No prazo'.
    ELSE.
      lv_start = zcl_rx_format=>int( is_classification-start_delay_days ).
      lv_finish = zcl_rx_format=>int( is_classification-finish_delay_days ).
      CONCATENATE 'Início:' lv_start 'dia(s) · Fim:' lv_finish 'dia(s)' INTO lv_value SEPARATED BY space.
    ENDIF.
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'delay' iv_label = 'Atraso' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).

    IF is_order-sales_order IS NOT INITIAL.
      lv_vbeln = zcl_rx_format=>alpha_out( is_order-sales_order ).
      lv_posnr = zcl_rx_format=>alpha_out( is_order-sales_item ).
      CONCATENATE lv_vbeln '/' lv_posnr INTO lv_item.
      lv_value = lv_item.
      IF is_order-requested_date IS NOT INITIAL.
        lv_requested = zcl_rx_format=>date_iso( is_order-requested_date ).
        CONCATENATE lv_item '· pedido para' lv_requested INTO lv_value SEPARATED BY space.
      ENDIF.
      zcl_rx_result=>add_fact( EXPORTING iv_id = 'salesOrder' iv_label = 'Pedido de venda' iv_value = lv_value
                               CHANGING  cs_result = cs_result ).
    ENDIF.
  ENDMETHOD.


  METHOD add_operations_table.
    DATA ls_table TYPE zif_rx_types=>ty_table.
    DATA lt_row TYPE string_table.
    DATA lv_text TYPE string.
    FIELD-SYMBOLS <ls_operation> TYPE zif_rx_pp_reader=>ty_operation.

    ls_table-id = 'operations'.
    ls_table-title = 'Operações'.
    zcl_rx_result=>add_column( EXPORTING iv_key = 'operation' iv_label = 'Operação' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'workCenter' iv_label = 'Centro de trabalho'
                               CHANGING  cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'description' iv_label = 'Descrição' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'status' iv_label = 'Status' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'scheduledFinish' iv_label = 'Fim programado'
                               CHANGING  cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'actualFinish' iv_label = 'Fim real' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'confirmed' iv_label = 'Confirmado' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'scrap' iv_label = 'Refugo' CHANGING cs_table = ls_table ).

    LOOP AT it_operations ASSIGNING <ls_operation> WHERE aufnr = is_order-aufnr.
      CLEAR lt_row.
      lv_text = <ls_operation>-vornr.
      APPEND lv_text TO lt_row.
      lv_text = <ls_operation>-work_center.
      APPEND lv_text TO lt_row.
      lv_text = <ls_operation>-description.
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_pp_view=>status_text( <ls_operation>-status ).
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_pp_view=>date_or_dash( <ls_operation>-sched_finish ).
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_pp_view=>date_or_dash( <ls_operation>-actual_finish ).
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_format=>quantity( iv_value = <ls_operation>-confirmed iv_unit = is_order-unit ).
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_format=>quantity( iv_value = <ls_operation>-scrap iv_unit = is_order-unit ).
      APPEND lv_text TO lt_row.
      APPEND lt_row TO ls_table-rows.
    ENDLOOP.
    APPEND ls_table TO cs_result-tables.
  ENDMETHOD.


  METHOD add_confirmations_table.
    DATA ls_table TYPE zif_rx_types=>ty_table.
    DATA lt_mine TYPE zif_rx_pp_reader=>ty_confirmations.
    DATA lt_row TYPE string_table.
    DATA lv_text TYPE string.
    DATA lv_skip TYPE i.
    DATA lv_index TYPE i.
    FIELD-SYMBOLS <ls_confirmation> TYPE zif_rx_pp_reader=>ty_confirmation.

    ls_table-id = 'confirmations'.
    ls_table-title = 'Últimos apontamentos'.
    zcl_rx_result=>add_column( EXPORTING iv_key = 'date' iv_label = 'Data' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'operation' iv_label = 'Operação' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'yield' iv_label = 'Qtd. boa' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'scrap' iv_label = 'Refugo' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'user' iv_label = 'Usuário' CHANGING cs_table = ls_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'reversed' iv_label = 'Estornado?' CHANGING cs_table = ls_table ).

    LOOP AT it_confirmations ASSIGNING <ls_confirmation> WHERE aufnr = is_order-aufnr.
      APPEND <ls_confirmation> TO lt_mine.
    ENDLOOP.
    " Só os mais recentes (o leitor entrega em ordem cronológica).
    lv_skip = lines( lt_mine ) - c_max_confirmations.
    LOOP AT lt_mine ASSIGNING <ls_confirmation>.
      lv_index = sy-tabix.
      IF lv_index <= lv_skip.
        CONTINUE.
      ENDIF.
      CLEAR lt_row.
      lv_text = zcl_rx_format=>date_iso( <ls_confirmation>-date ).
      APPEND lv_text TO lt_row.
      lv_text = <ls_confirmation>-vornr.
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_format=>quantity( iv_value = <ls_confirmation>-yield iv_unit = is_order-unit ).
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_format=>quantity( iv_value = <ls_confirmation>-scrap iv_unit = is_order-unit ).
      APPEND lv_text TO lt_row.
      lv_text = <ls_confirmation>-user.
      APPEND lv_text TO lt_row.
      IF <ls_confirmation>-reversed = abap_true.
        lv_text = 'Sim'.
      ELSE.
        lv_text = 'Não'.
      ENDIF.
      APPEND lv_text TO lt_row.
      APPEND lt_row TO ls_table-rows.
    ENDLOOP.
    APPEND ls_table TO cs_result-tables.
  ENDMETHOD.


  METHOD add_flag_finding.
    CASE iv_flag.
      WHEN zcl_rx_pp_status_map=>c_flag-late_start.
        add_late_start( EXPORTING is_order = is_order is_classification = is_classification
                        CHANGING  cs_result = cs_result ).
      WHEN zcl_rx_pp_status_map=>c_flag-late_finish.
        add_late_finish( EXPORTING is_order = is_order is_classification = is_classification
                         CHANGING  cs_result = cs_result ).
      WHEN zcl_rx_pp_status_map=>c_flag-operation_late.
        add_operation_late( EXPORTING is_order = is_order it_operations = it_operations
                            CHANGING  cs_result = cs_result ).
      WHEN zcl_rx_pp_status_map=>c_flag-confirmed_not_received.
        add_confirmed_not_received( EXPORTING is_order = is_order CHANGING cs_result = cs_result ).
      WHEN zcl_rx_pp_status_map=>c_flag-sales_order_at_risk.
        add_sales_order_at_risk( EXPORTING is_order = is_order CHANGING cs_result = cs_result ).
      WHEN OTHERS.
        add_simple_finding( EXPORTING iv_flag = iv_flag CHANGING cs_result = cs_result ).
    ENDCASE.
  ENDMETHOD.


  METHOD add_late_start.
    DATA lv_days TYPE string.
    DATA lv_title TYPE string.
    DATA lv_date TYPE string.
    DATA lv_detail TYPE string.

    lv_days = zcl_rx_format=>int( is_classification-start_delay_days ).
    CONCATENATE 'Início atrasado em' lv_days 'dia(s)' INTO lv_title SEPARATED BY space.
    lv_date = zcl_rx_format=>date_iso( is_order-sched_start ).
    CONCATENATE 'O início programado era' lv_date 'e a ordem ainda não começou.' INTO lv_detail SEPARATED BY space.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP03.LATE_START'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = lv_title
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'CO02'
                                          iv_action   = 'Liberar ou reprogramar a ordem com o PCP'
                                CHANGING  cs_result   = cs_result ).
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'AFKO'
                                           iv_field  = 'GSTRS'
                                           iv_value  = lv_date
                                           iv_label  = 'Início programado'
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_late_finish.
    DATA lv_days TYPE string.
    DATA lv_title TYPE string.
    DATA lv_date TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_done TYPE string.
    DATA lv_planned TYPE string.
    DATA lv_when TYPE string.

    lv_days = zcl_rx_format=>int( is_classification-finish_delay_days ).
    CONCATENATE 'Fim atrasado em' lv_days 'dia(s)' INTO lv_title SEPARATED BY space.
    lv_date = zcl_rx_format=>date_iso( is_order-sched_finish ).
    lv_done = zcl_rx_format=>quantity( iv_value = is_order-confirmed iv_unit = is_order-unit ).
    lv_planned = zcl_rx_format=>quantity( iv_value = is_order-planned iv_unit = is_order-unit ).
    CONCATENATE lv_date '.' INTO lv_when.
    CONCATENATE lv_planned '.' INTO lv_planned.
    CONCATENATE 'O fim programado era' lv_when 'Confirmado até agora:' lv_done 'de' lv_planned
      INTO lv_detail SEPARATED BY space.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP03.LATE_FINISH'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = lv_title
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'COOIS'
                                          iv_action   = 'Ver as operações pendentes e o gargalo'
                                CHANGING  cs_result   = cs_result ).
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'AFKO'
                                           iv_field  = 'GLTRS'
                                           iv_value  = lv_date
                                           iv_label  = 'Fim programado'
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_operation_late.
    DATA lv_count TYPE i.
    DATA lv_count_text TYPE string.
    DATA lv_title TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_item TYPE string.
    DATA lv_vornr TYPE string.
    DATA lv_text TYPE string.
    DATA lv_center TYPE string.
    DATA lv_date TYPE string.
    DATA lv_label TYPE string.
    DATA lt_late TYPE zif_rx_pp_reader=>ty_operations.
    DATA lt_items TYPE string_table.
    FIELD-SYMBOLS <ls_operation> TYPE zif_rx_pp_reader=>ty_operation.

    LOOP AT it_operations ASSIGNING <ls_operation> WHERE aufnr = is_order-aufnr.
      IF mo_map->is_operation_late( <ls_operation> ) = abap_true.
        APPEND <ls_operation> TO lt_late.
      ENDIF.
    ENDLOOP.
    lv_count = lines( lt_late ).
    lv_count_text = zcl_rx_format=>int( lv_count ).
    CONCATENATE lv_count_text 'operação(ões) atrasada(s)' INTO lv_title SEPARATED BY space.
    LOOP AT lt_late ASSIGNING <ls_operation>.
      lv_vornr = <ls_operation>-vornr.
      lv_text = <ls_operation>-description.
      lv_center = <ls_operation>-work_center.
      CONCATENATE '(' lv_center '),' INTO lv_center.
      lv_date = zcl_rx_format=>date_iso( <ls_operation>-sched_finish ).
      CONCATENATE lv_vornr lv_text lv_center 'fim programado' lv_date INTO lv_item SEPARATED BY space.
      APPEND lv_item TO lt_items.
    ENDLOOP.
    lv_detail = zcl_rx_pp_view=>join( it_values = lt_items iv_separator = ';' ).

    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP03.OPERATION_LATE'
                                          iv_severity = zif_rx_types=>c_severity-warning
                                          iv_title    = lv_title
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'CM01'
                                          iv_action   = 'Verificar a carga do centro de trabalho'
                                CHANGING  cs_result   = cs_result ).
    LOOP AT lt_late ASSIGNING <ls_operation>.
      lv_vornr = <ls_operation>-vornr.
      lv_date = zcl_rx_format=>date_iso( <ls_operation>-sched_finish ).
      CONCATENATE 'Fim programado da operação' lv_vornr INTO lv_label SEPARATED BY space.
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'AFVV'
                                             iv_field  = 'FSEDD'
                                             iv_value  = lv_date
                                             iv_label  = lv_label
                                   CHANGING  cs_result = cs_result ).
    ENDLOOP.
  ENDMETHOD.


  METHOD add_confirmed_not_received.
    DATA lv_confirmed TYPE string.
    DATA lv_delivered TYPE string.
    DATA lv_value TYPE string.
    DATA lv_detail TYPE string.

    lv_confirmed = zcl_rx_format=>quantity( iv_value = is_order-confirmed iv_unit = is_order-unit ).
    lv_delivered = zcl_rx_format=>quantity( iv_value = is_order-delivered iv_unit = is_order-unit ).
    CONCATENATE lv_confirmed ',' INTO lv_confirmed.
    CONCATENATE 'Foram confirmados' lv_confirmed 'mas só' lv_delivered 'deram entrada no estoque.'
      INTO lv_detail SEPARATED BY space.
    lv_value = zcl_rx_format=>number_br( is_order-delivered ).
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP03.CONFIRMED_NOT_RECEIVED'
                                          iv_severity = zif_rx_types=>c_severity-warning
                                          iv_title    = 'Confirmada sem entrada de mercadoria'
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'MIGO'
                                          iv_action   = 'Lançar a entrada de mercadoria da ordem (movimento 101)'
                                CHANGING  cs_result   = cs_result ).
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'AFPO'
                                           iv_field  = 'WEMNG'
                                           iv_value  = lv_value
                                           iv_label  = 'Quantidade entregue'
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_sales_order_at_risk.
    DATA lv_vbeln TYPE string.
    DATA lv_posnr TYPE string.
    DATA lv_item TYPE string.
    DATA lv_date TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_when TYPE string.

    lv_vbeln = zcl_rx_format=>alpha_out( is_order-sales_order ).
    lv_posnr = zcl_rx_format=>alpha_out( is_order-sales_item ).
    CONCATENATE lv_vbeln '/' lv_posnr INTO lv_item.
    lv_date = zcl_rx_format=>date_iso( is_order-requested_date ).
    CONCATENATE lv_item ',' INTO lv_item.
    CONCATENATE lv_date '.' INTO lv_when.
    CONCATENATE 'A ordem atende o pedido' lv_item 'com data pedida' lv_when
      INTO lv_detail SEPARATED BY space.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP03.SALES_ORDER_AT_RISK'
                                          iv_severity = zif_rx_types=>c_severity-warning
                                          iv_title    = 'Risco para o pedido do cliente'
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'VA03'
                                          iv_action   = 'Avisar a área comercial sobre o novo prazo'
                                CHANGING  cs_result   = cs_result ).
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'VBEP'
                                           iv_field  = 'EDATU'
                                           iv_value  = lv_date
                                           iv_label  = 'Data pedida pelo cliente'
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_simple_finding.
    CASE iv_flag.
      WHEN zcl_rx_pp_status_map=>c_flag-missing_parts.
        zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP03.MISSING_PARTS'
                                              iv_severity = zif_rx_types=>c_severity-warning
                                              iv_title    = 'Falta de material'
                                              iv_detail   = 'Há componentes com falta.' &
                                                          ' Rode o diagnóstico PP-01 para o detalhe.'
                                              iv_tcode    = 'CO24'
                                              iv_action   = 'Lista de faltas'
                                    CHANGING  cs_result   = cs_result ).
        zcl_rx_result=>add_evidence( EXPORTING iv_source = 'JEST'
                                               iv_field  = 'STAT'
                                               iv_value  = 'MSPT'
                                               iv_label  = 'Status: falta de material'
                                     CHANGING  cs_result = cs_result ).
      WHEN zcl_rx_pp_status_map=>c_flag-locked.
        zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP03.LOCKED'
                                              iv_severity = zif_rx_types=>c_severity-blocking
                                              iv_title    = 'Ordem bloqueada'
                                              iv_detail   = 'A ordem está bloqueada (LKD).'
                                              iv_tcode    = 'CO02'
                                              iv_action   = 'Desbloquear a ordem'
                                    CHANGING  cs_result   = cs_result ).
        zcl_rx_result=>add_evidence( EXPORTING iv_source = 'JEST'
                                               iv_field  = 'STAT'
                                               iv_value  = 'LKD'
                                               iv_label  = 'Status: bloqueada'
                                     CHANGING  cs_result = cs_result ).
      WHEN zcl_rx_pp_status_map=>c_flag-reversed_confirmation.
        zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP03.REVERSED_CONFIRMATION'
                                              iv_severity = zif_rx_types=>c_severity-info
                                              iv_title    = 'Apontamento estornado recentemente'
                                              iv_detail   = 'Houve estorno de apontamento nos últimos 7 dias.'
                                              iv_tcode    = 'CO14'
                                              iv_action   = 'Exibir os apontamentos da ordem'
                                    CHANGING  cs_result   = cs_result ).
        zcl_rx_result=>add_evidence( EXPORTING iv_source = 'AFRU'
                                               iv_field  = 'STOKZ'
                                               iv_value  = 'X'
                                               iv_label  = 'Apontamento estornado'
                                     CHANGING  cs_result = cs_result ).
    ENDCASE.
  ENDMETHOD.


  METHOD quantity_with_percent.
    DATA lv_pct TYPE i.
    DATA lv_pct_text TYPE string.
    DATA lv_quantity TYPE string.
    DATA lv_paren TYPE string.

    lv_pct = zcl_rx_pp_view=>percent( iv_part = iv_value iv_total = iv_total ).
    lv_pct_text = zcl_rx_format=>int( lv_pct ).
    lv_quantity = zcl_rx_format=>quantity( iv_value = iv_value iv_unit = iv_unit ).
    CONCATENATE '(' lv_pct_text '%)' INTO lv_paren.
    CONCATENATE lv_quantity lv_paren INTO rv_text SEPARATED BY space.
  ENDMETHOD.


  METHOD date_range.
    DATA lv_from TYPE string.
    DATA lv_to TYPE string.

    lv_from = zcl_rx_pp_view=>date_or_dash( iv_from ).
    lv_to = zcl_rx_pp_view=>date_or_dash( iv_to ).
    CONCATENATE lv_from '→' lv_to INTO rv_text SEPARATED BY space.
  ENDMETHOD.

ENDCLASS.
