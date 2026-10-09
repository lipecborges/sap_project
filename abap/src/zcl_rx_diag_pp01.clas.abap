"! PP-01: ordem de produção não liberada / falta de componentes.
"! Só lógica: os dados vêm do leitor (ZIF_RX_PP_READER). Mesmos achados, severidades e ordem do
"! simulador (services/sap-mock/src/fixtures/pp.ts). Entrada: productionOrder (AUFNR).
CLASS zcl_rx_diag_pp01 DEFINITION
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
    DATA mo_reader TYPE REF TO zif_rx_pp_reader.
    DATA mv_today TYPE d.

    METHODS check_authorization
      IMPORTING is_order TYPE zif_rx_pp_reader=>ty_order
      RAISING   zcx_rx_error.

    "! Ordem eliminada (DLFL) ou encerrada tecnicamente (TECO): não há liberação pendente.
    CLASS-METHODS is_final
      IMPORTING is_order        TYPE zif_rx_pp_reader=>ty_order
      RETURNING VALUE(rv_final) TYPE abap_bool.

    METHODS add_final_status
      IMPORTING is_order  TYPE zif_rx_pp_reader=>ty_order
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_not_released
      IMPORTING is_order  TYPE zif_rx_pp_reader=>ty_order
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_user_status_blocks
      IMPORTING is_order  TYPE zif_rx_pp_reader=>ty_order
                io_map    TYPE REF TO zcl_rx_pp_status_map
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_locked
      IMPORTING is_order  TYPE zif_rx_pp_reader=>ty_order
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_missing_parts
      IMPORTING is_order      TYPE zif_rx_pp_reader=>ty_order
                it_components TYPE zif_rx_pp_reader=>ty_components
      CHANGING  cs_result     TYPE zif_rx_types=>ty_result.

    METHODS add_status_evidence
      IMPORTING is_order  TYPE zif_rx_pp_reader=>ty_order
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    CLASS-METHODS is_released
      IMPORTING is_order           TYPE zif_rx_pp_reader=>ty_order
      RETURNING VALUE(rv_released) TYPE abap_bool.

ENDCLASS.



CLASS zcl_rx_diag_pp01 IMPLEMENTATION.

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

    rs_meta-id = 'PP-01'.
    rs_meta-version = '1.0'.
    rs_meta-module = 'PP'.
    rs_meta-kind = 'OBJECT'.
    rs_meta-title = 'Ordem de produção não liberada / falta de componentes'.
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
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.
    DATA lt_aufnr TYPE zif_rx_pp_reader=>ty_aufnrs.
    DATA lt_components TYPE zif_rx_pp_reader=>ty_components.
    DATA lt_map TYPE zif_rx_pp_reader=>ty_status_maps.
    DATA lo_map TYPE REF TO zcl_rx_pp_status_map.
    DATA lv_released TYPE abap_bool.

    lv_input = zcl_rx_params=>get( it_params = it_params iv_name = 'productionOrder' ).
    lv_aufnr = zcl_rx_format=>alpha_in( iv_value = lv_input iv_length = 12 ).
    lv_display = zcl_rx_format=>alpha_out( lv_aufnr ).
    rs_result = zcl_rx_result=>create( iv_kind = 'PRODUCTION_ORDER' iv_id = lv_display ).

    ls_order = mo_reader->get_order( lv_aufnr ).
    IF ls_order-aufnr IS INITIAL.
      CONCATENATE 'A ordem de produção' lv_display 'não existe neste sistema/mandante.'
        INTO lv_detail SEPARATED BY space.
      zcl_rx_result=>set_not_found( EXPORTING iv_prefix = 'PP01'
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

    IF is_final( ls_order ) = abap_true.
      add_final_status( EXPORTING is_order = ls_order CHANGING cs_result = rs_result ).
      zcl_rx_result=>settle_status( CHANGING cs_result = rs_result ).
      RETURN.
    ENDIF.

    APPEND ls_order-aufnr TO lt_aufnr.
    lt_components = mo_reader->get_components( lt_aufnr ).
    lt_map = mo_reader->get_status_map( ).
    CREATE OBJECT lo_map
      EXPORTING
        iv_today   = mv_today
        it_mapping = lt_map.

    lv_released = is_released( ls_order ).
    IF lv_released = abap_false.
      add_not_released( EXPORTING is_order = ls_order CHANGING cs_result = rs_result ).
    ENDIF.
    add_user_status_blocks( EXPORTING is_order = ls_order io_map = lo_map CHANGING cs_result = rs_result ).
    add_locked( EXPORTING is_order = ls_order CHANGING cs_result = rs_result ).
    add_missing_parts( EXPORTING is_order = ls_order it_components = lt_components CHANGING cs_result = rs_result ).

    IF lv_released = abap_false AND lines( rs_result-findings ) = 1.
      zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP01.MANUAL_RELEASE'
                                            iv_severity = zif_rx_types=>c_severity-info
                                            iv_title    = 'Nada impede a liberação'
                                            iv_detail   = 'Não há falta de material nem bloqueios.' &
                                                        ' A ordem só aguarda a liberação manual.'
                                            iv_tcode    = 'COHV'
                                            iv_action   = 'Liberar em massa, se houver várias ordens'
                                  CHANGING  cs_result   = rs_result ).
    ENDIF.
    IF lv_released = abap_true AND rs_result-findings IS INITIAL.
      zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP01.RELEASED'
                                            iv_severity = zif_rx_types=>c_severity-info
                                            iv_title    = 'Ordem liberada e sem faltas'
                                            iv_detail   = 'A ordem está liberada e todos os componentes' &
                                                        ' estão disponíveis.'
                                  CHANGING  cs_result   = rs_result ).
      add_status_evidence( EXPORTING is_order = ls_order CHANGING cs_result = rs_result ).
    ENDIF.

    APPEND zcl_rx_pp_view=>components_table( iv_aufnr = ls_order-aufnr it_components = lt_components )
      TO rs_result-tables.
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


  METHOD is_final.
    IF zcl_rx_pp_status_map=>has_status( it_status = is_order-system_status
                                         iv_status = zcl_rx_pp_status_map=>c_status-dlfl ) = abap_true
        OR zcl_rx_pp_status_map=>has_status( it_status = is_order-system_status
                                             iv_status = zcl_rx_pp_status_map=>c_status-teco ) = abap_true.
      rv_final = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD add_final_status.
    IF zcl_rx_pp_status_map=>has_status( it_status = is_order-system_status
                                         iv_status = zcl_rx_pp_status_map=>c_status-dlfl ) = abap_true.
      zcl_rx_result=>add_finding(
        EXPORTING iv_code     = 'PP01.DELETED'
                  iv_severity = zif_rx_types=>c_severity-info
                  iv_title    = 'Ordem marcada para eliminação'
                  iv_detail   = 'A ordem está marcada para eliminação (DLFL) e não pode ser liberada.'
        CHANGING  cs_result   = cs_result ).
    ELSE.
      zcl_rx_result=>add_finding(
        EXPORTING iv_code     = 'PP01.TECO'
                  iv_severity = zif_rx_types=>c_severity-info
                  iv_title    = 'Ordem encerrada tecnicamente'
                  iv_detail   = 'A ordem já foi encerrada tecnicamente (TECO). Não há liberação pendente.'
                  iv_tcode    = 'CO03'
                  iv_action   = 'Exibir a ordem'
        CHANGING  cs_result   = cs_result ).
    ENDIF.
    add_status_evidence( EXPORTING is_order = is_order CHANGING cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_not_released.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP01.NOT_RELEASED'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = 'Ordem não liberada'
                                          iv_detail   = 'A ordem está apenas criada (CRTD). Sem liberação' &
                                                      ' não é possível apontar nem retirar material.'
                                          iv_tcode    = 'CO02'
                                          iv_action   = 'Liberar a ordem (Funções → Liberar)'
                                CHANGING  cs_result   = cs_result ).
    add_status_evidence( EXPORTING is_order = is_order CHANGING cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_user_status_blocks.
    DATA lt_blocking TYPE zif_rx_pp_reader=>ty_user_statuses.
    DATA lv_detail TYPE string.
    DATA lv_label TYPE string.
    DATA lv_code TYPE string.
    DATA lv_text TYPE string.
    DATA lv_profile TYPE string.
    DATA lv_quoted TYPE string.
    FIELD-SYMBOLS <ls_user> TYPE zif_rx_pp_reader=>ty_user_status.

    lt_blocking = io_map->blocking_user_statuses( is_order ).
    LOOP AT lt_blocking ASSIGNING <ls_user>.
      lv_text = <ls_user>-text.
      lv_profile = <ls_user>-profile.
      lv_code = <ls_user>-code.
      CONCATENATE '"' lv_text '"' INTO lv_quoted.
      CONCATENATE lv_profile ')' INTO lv_profile.
      CONCATENATE 'O status de usuário' lv_quoted '(perfil' lv_profile 'proíbe a liberação.'
        INTO lv_detail SEPARATED BY space.
      CONCATENATE 'Status de usuário:' lv_text INTO lv_label SEPARATED BY space.
      zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP01.USER_STATUS_BLOCK'
                                            iv_severity = zif_rx_types=>c_severity-blocking
                                            iv_title    = 'Status de usuário impede a liberação'
                                            iv_detail   = lv_detail
                                            iv_tcode    = 'CO02'
                                            iv_action   = 'Alterar o status de usuário (área responsável)'
                                  CHANGING  cs_result   = cs_result ).
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'JEST'
                                             iv_field  = 'STAT'
                                             iv_value  = lv_code
                                             iv_label  = lv_label
                                   CHANGING  cs_result = cs_result ).
    ENDLOOP.
  ENDMETHOD.


  METHOD add_locked.
    IF zcl_rx_pp_status_map=>has_status( it_status = is_order-system_status
                                         iv_status = zcl_rx_pp_status_map=>c_status-lkd ) = abap_false.
      RETURN.
    ENDIF.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP01.LOCKED'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = 'Ordem bloqueada'
                                          iv_detail   = 'A ordem está bloqueada (LKD). Nenhuma operação' &
                                                      ' de negócio é permitida até o desbloqueio.'
                                          iv_tcode    = 'CO02'
                                          iv_action   = 'Desbloquear a ordem (Funções → Bloquear → Desbloquear)'
                                CHANGING  cs_result   = cs_result ).
    add_status_evidence( EXPORTING is_order = is_order CHANGING cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_missing_parts.
    DATA lt_missing TYPE zif_rx_pp_reader=>ty_components.
    DATA lv_count TYPE i.
    DATA lv_count_text TYPE string.
    DATA lv_title TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_item TYPE string.
    DATA lv_material TYPE string.
    DATA lv_required TYPE string.
    DATA lv_pending TYPE string.
    DATA lv_stock TYPE string.
    DATA lv_qty TYPE zif_rx_pp_reader=>ty_qty.
    DATA lv_label TYPE string.
    FIELD-SYMBOLS <ls_component> TYPE zif_rx_pp_reader=>ty_component.

    LOOP AT it_components ASSIGNING <ls_component> WHERE aufnr = is_order-aufnr.
      IF zcl_rx_pp_status_map=>is_short( <ls_component> ) = abap_true.
        APPEND <ls_component> TO lt_missing.
      ENDIF.
    ENDLOOP.
    lv_count = lines( lt_missing ).
    IF lv_count = 0
        AND zcl_rx_pp_status_map=>has_status( it_status = is_order-system_status
                                              iv_status = zcl_rx_pp_status_map=>c_status-mspt ) = abap_false.
      RETURN.
    ENDIF.

    lv_count_text = zcl_rx_format=>int( lv_count ).
    CONCATENATE 'Falta de material em' lv_count_text 'componente(s)' INTO lv_title SEPARATED BY space.
    LOOP AT lt_missing ASSIGNING <ls_component>.
      lv_material = zcl_rx_format=>alpha_out( <ls_component>-material ).
      lv_qty = <ls_component>-required - <ls_component>-withdrawn.
      lv_pending = zcl_rx_format=>quantity( iv_value = lv_qty iv_unit = <ls_component>-unit ).
      lv_stock = zcl_rx_format=>quantity( iv_value = <ls_component>-stock iv_unit = <ls_component>-unit ).
      lv_item = <ls_component>-description.
      CONCATENATE '(' lv_item '):' INTO lv_item.
      CONCATENATE lv_pending ',' INTO lv_pending.
      CONCATENATE lv_material lv_item 'precisa' lv_pending 'estoque' lv_stock INTO lv_item SEPARATED BY space.
      IF lv_detail IS NOT INITIAL.
        CONCATENATE lv_detail ';' INTO lv_detail.
        CONCATENATE lv_detail lv_item INTO lv_item SEPARATED BY space.
      ENDIF.
      lv_detail = lv_item.
    ENDLOOP.

    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'PP01.MISSING_PARTS'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = lv_title
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'CO24'
                                          iv_action   = 'Analisar a lista de faltas e o MD04 de cada componente'
                                CHANGING  cs_result   = cs_result ).
    add_status_evidence( EXPORTING is_order = is_order CHANGING cs_result = cs_result ).
    LOOP AT lt_missing ASSIGNING <ls_component>.
      lv_material = zcl_rx_format=>alpha_out( <ls_component>-material ).
      lv_required = zcl_rx_format=>number_br( <ls_component>-required ).
      CONCATENATE 'Necessidade de' lv_material INTO lv_label SEPARATED BY space.
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'RESB'
                                             iv_field  = 'BDMNG'
                                             iv_value  = lv_required
                                             iv_label  = lv_label
                                   CHANGING  cs_result = cs_result ).
    ENDLOOP.
  ENDMETHOD.


  METHOD add_status_evidence.
    DATA lv_text TYPE string.

    lv_text = zcl_rx_pp_view=>status_text( is_order-system_status ).
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'JEST'
                                           iv_field  = 'STAT'
                                           iv_value  = lv_text
                                           iv_label  = 'Status de sistema ativos'
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD is_released.
    IF zcl_rx_pp_status_map=>has_status( it_status = is_order-system_status
                                         iv_status = zcl_rx_pp_status_map=>c_status-rel ) = abap_true
        OR zcl_rx_pp_status_map=>has_status( it_status = is_order-system_status
                                             iv_status = zcl_rx_pp_status_map=>c_status-prel ) = abap_true.
      rv_released = abap_true.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
