*"* Testes com dublê local do leitor (ltd_reader): ordens do simulador (sap-mock), com datas
*"* relativas a "hoje" = 2026-10-09 convertidas para datas absolutas.
CLASS ltd_reader DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_rx_pp_reader.

    DATA mt_orders TYPE zif_rx_pp_reader=>ty_orders.
    DATA mt_operations TYPE zif_rx_pp_reader=>ty_operations.
    DATA mt_components TYPE zif_rx_pp_reader=>ty_components.
    DATA mt_confirmations TYPE zif_rx_pp_reader=>ty_confirmations.
    DATA mt_map TYPE zif_rx_pp_reader=>ty_status_maps.
    DATA ms_settings TYPE zif_rx_pp_reader=>ty_settings.
    DATA ms_last_filter TYPE zif_rx_pp_reader=>ty_filter.
    " Sem autorização: todos os tipos de ordem ou só o tipo informado.
    DATA mv_deny_all TYPE abap_bool.
    DATA mv_denied_type TYPE c LENGTH 4.

    METHODS constructor.

  PRIVATE SECTION.
    METHODS order_1000001.
    METHODS order_1000002.
    METHODS order_1000003.
    METHODS order_1000004.
    METHODS order_1000005.
    METHODS order_1000006.
    METHODS new_order
      IMPORTING iv_aufnr        TYPE zif_rx_pp_reader=>ty_aufnr
                iv_material     TYPE csequence
                iv_description  TYPE csequence
                iv_plant        TYPE csequence
                iv_order_type   TYPE csequence
                iv_mrp          TYPE csequence
                iv_scheduler    TYPE csequence
      RETURNING VALUE(rs_order) TYPE zif_rx_pp_reader=>ty_order.
    METHODS add_user_status
      IMPORTING iv_profile TYPE csequence
                iv_code    TYPE csequence
                iv_text    TYPE csequence
      CHANGING  cs_order   TYPE zif_rx_pp_reader=>ty_order.
    METHODS add_operation
      IMPORTING iv_aufnr         TYPE zif_rx_pp_reader=>ty_aufnr
                iv_vornr         TYPE csequence
                iv_work_center   TYPE csequence
                iv_text          TYPE csequence
                iv_status        TYPE csequence
                iv_sched_start   TYPE d
                iv_sched_finish  TYPE d
                iv_actual_start  TYPE d OPTIONAL
                iv_actual_finish TYPE d OPTIONAL
                iv_confirmed     TYPE zif_rx_pp_reader=>ty_qty DEFAULT 0
                iv_scrap         TYPE zif_rx_pp_reader=>ty_qty DEFAULT 0.
    METHODS add_component
      IMPORTING iv_aufnr     TYPE zif_rx_pp_reader=>ty_aufnr
                iv_material  TYPE csequence
                iv_text      TYPE csequence
                iv_required  TYPE zif_rx_pp_reader=>ty_qty
                iv_withdrawn TYPE zif_rx_pp_reader=>ty_qty
                iv_stock     TYPE zif_rx_pp_reader=>ty_qty
                iv_missing   TYPE abap_bool DEFAULT abap_false.
ENDCLASS.


CLASS ltd_reader IMPLEMENTATION.

  METHOD constructor.
    DATA ls_map TYPE zif_rx_pp_reader=>ty_status_map.

    order_1000001( ).
    order_1000002( ).
    order_1000003( ).
    order_1000004( ).
    order_1000005( ).
    order_1000006( ).
    " Mapeamento da ZRX_PPSTAT_MAP (equivalente ao USER_STATUS_MAP do simulador).
    ls_map-source_type = 'USER_STATUS'.
    ls_map-source_value = 'ZPP00001/E0002'.
    ls_map-situation = 'APPROVED'.
    APPEND ls_map TO mt_map.
    ls_map-source_type = 'USER_STATUS'.
    ls_map-source_value = 'ZPP00001/E0003'.
    ls_map-situation = 'BLOCKS_RELEASE'.
    APPEND ls_map TO mt_map.
    ms_settings-tolerance_days = 0.
    ms_settings-max_rows = 500.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~get_order.
    FIELD-SYMBOLS <ls_order> TYPE zif_rx_pp_reader=>ty_order.

    READ TABLE mt_orders ASSIGNING <ls_order> WITH KEY aufnr = iv_aufnr.
    IF sy-subrc = 0.
      rs_order = <ls_order>.
    ENDIF.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~find_orders.
    FIELD-SYMBOLS <ls_order> TYPE zif_rx_pp_reader=>ty_order.

    ms_last_filter = is_filter.
    LOOP AT mt_orders ASSIGNING <ls_order> WHERE plant = is_filter-plant.
      IF is_filter-mrp_controller IS NOT INITIAL AND <ls_order>-mrp_controller <> is_filter-mrp_controller.
        CONTINUE.
      ENDIF.
      IF is_filter-order_type IS NOT INITIAL AND <ls_order>-order_type <> is_filter-order_type.
        CONTINUE.
      ENDIF.
      IF is_filter-material IS NOT INITIAL AND <ls_order>-material <> is_filter-material.
        CONTINUE.
      ENDIF.
      IF is_filter-date_from IS NOT INITIAL AND <ls_order>-sched_finish < is_filter-date_from.
        CONTINUE.
      ENDIF.
      IF is_filter-date_to IS NOT INITIAL AND <ls_order>-sched_finish > is_filter-date_to.
        CONTINUE.
      ENDIF.
      APPEND <ls_order> TO rt_orders.
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~has_orders.
    READ TABLE mt_orders TRANSPORTING NO FIELDS WITH KEY plant = iv_plant.
    IF sy-subrc = 0.
      rv_exists = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~get_operations.
    FIELD-SYMBOLS <ls_operation> TYPE zif_rx_pp_reader=>ty_operation.

    LOOP AT mt_operations ASSIGNING <ls_operation>.
      READ TABLE it_aufnr TRANSPORTING NO FIELDS WITH KEY table_line = <ls_operation>-aufnr.
      IF sy-subrc = 0.
        APPEND <ls_operation> TO rt_operations.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~get_components.
    FIELD-SYMBOLS <ls_component> TYPE zif_rx_pp_reader=>ty_component.

    LOOP AT mt_components ASSIGNING <ls_component>.
      READ TABLE it_aufnr TRANSPORTING NO FIELDS WITH KEY table_line = <ls_component>-aufnr.
      IF sy-subrc = 0.
        APPEND <ls_component> TO rt_components.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~get_confirmations.
    FIELD-SYMBOLS <ls_confirmation> TYPE zif_rx_pp_reader=>ty_confirmation.

    LOOP AT mt_confirmations ASSIGNING <ls_confirmation> WHERE date >= iv_since.
      READ TABLE it_aufnr TRANSPORTING NO FIELDS WITH KEY table_line = <ls_confirmation>-aufnr.
      IF sy-subrc = 0.
        APPEND <ls_confirmation> TO rt_confirmations.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~get_status_map.
    rt_map = mt_map.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~get_settings.
    rs_settings = ms_settings.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~is_authorized.
    rv_authorized = abap_true.
    IF mv_deny_all = abap_true.
      rv_authorized = abap_false.
    ELSEIF mv_denied_type IS NOT INITIAL AND iv_order_type = mv_denied_type.
      rv_authorized = abap_false.
    ENDIF.
  ENDMETHOD.


  METHOD new_order.
    rs_order-aufnr = iv_aufnr.
    rs_order-material = iv_material.
    rs_order-description = iv_description.
    rs_order-plant = iv_plant.
    rs_order-order_type = iv_order_type.
    rs_order-mrp_controller = iv_mrp.
    rs_order-scheduler = iv_scheduler.
    rs_order-unit = 'PC'.
  ENDMETHOD.


  METHOD add_user_status.
    DATA ls_user TYPE zif_rx_pp_reader=>ty_user_status.

    ls_user-profile = iv_profile.
    ls_user-code = iv_code.
    ls_user-text = iv_text.
    APPEND ls_user TO cs_order-user_status.
  ENDMETHOD.


  METHOD add_operation.
    DATA ls_operation TYPE zif_rx_pp_reader=>ty_operation.

    ls_operation-aufnr = iv_aufnr.
    ls_operation-vornr = iv_vornr.
    ls_operation-work_center = iv_work_center.
    ls_operation-description = iv_text.
    APPEND iv_status TO ls_operation-status.
    ls_operation-sched_start = iv_sched_start.
    ls_operation-sched_finish = iv_sched_finish.
    ls_operation-actual_start = iv_actual_start.
    ls_operation-actual_finish = iv_actual_finish.
    ls_operation-confirmed = iv_confirmed.
    ls_operation-scrap = iv_scrap.
    APPEND ls_operation TO mt_operations.
  ENDMETHOD.


  METHOD add_component.
    DATA ls_component TYPE zif_rx_pp_reader=>ty_component.

    ls_component-aufnr = iv_aufnr.
    ls_component-material = iv_material.
    ls_component-description = iv_text.
    ls_component-unit = 'PC'.
    ls_component-required = iv_required.
    ls_component-withdrawn = iv_withdrawn.
    ls_component-stock = iv_stock.
    ls_component-missing = iv_missing.
    APPEND ls_component TO mt_components.
  ENDMETHOD.


  METHOD order_1000001.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.

    ls_order = new_order( iv_aufnr       = '000001000001'
                          iv_material    = 'FG-1001'
                          iv_description = 'Bomba centrífuga BC-200'
                          iv_plant       = '1000'
                          iv_order_type  = 'PP01'
                          iv_mrp         = '001'
                          iv_scheduler   = '101' ).
    APPEND 'CRTD' TO ls_order-system_status.
    APPEND 'MSPT' TO ls_order-system_status.
    APPEND 'PRC' TO ls_order-system_status.
    ls_order-planned = 500.
    ls_order-confirmed = 0.
    ls_order-scrap = 0.
    ls_order-delivered = 0.
    ls_order-basic_start = '20261007'.
    ls_order-basic_finish = '20261014'.
    ls_order-sched_start = '20261007'.
    ls_order-sched_finish = '20261014'.
    APPEND ls_order TO mt_orders.

    add_operation( iv_aufnr        = '000001000001'
                   iv_vornr        = '0010'
                   iv_work_center  = 'MONT01'
                   iv_text         = 'Montagem do conjunto'
                   iv_status       = 'CRTD'
                   iv_sched_start  = '20261007'
                   iv_sched_finish = '20261011' ).
    add_operation( iv_aufnr        = '000001000001'
                   iv_vornr        = '0020'
                   iv_work_center  = 'TEST01'
                   iv_text         = 'Teste hidrostático'
                   iv_status       = 'CRTD'
                   iv_sched_start  = '20261011'
                   iv_sched_finish = '20261014' ).
    add_component( iv_aufnr     = '000001000001'
                   iv_material  = 'RM-2001'
                   iv_text      = 'Carcaça fundida BC-200'
                   iv_required  = 500
                   iv_withdrawn = 0
                   iv_stock     = 120
                   iv_missing   = abap_true ).
    add_component( iv_aufnr     = '000001000001'
                   iv_material  = 'RM-2002'
                   iv_text      = 'Rotor inox 200 mm'
                   iv_required  = 500
                   iv_withdrawn = 0
                   iv_stock     = 600 ).
    add_component( iv_aufnr     = '000001000001'
                   iv_material  = 'RM-2003'
                   iv_text      = 'Selo mecânico 1 1/2"'
                   iv_required  = 500
                   iv_withdrawn = 0
                   iv_stock     = 0
                   iv_missing   = abap_true ).
  ENDMETHOD.


  METHOD order_1000002.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.

    ls_order = new_order( iv_aufnr       = '000001000002'
                          iv_material    = 'FG-1002'
                          iv_description = 'Bomba centrífuga BC-300'
                          iv_plant       = '1000'
                          iv_order_type  = 'PP01'
                          iv_mrp         = '001'
                          iv_scheduler   = '101' ).
    APPEND 'CRTD' TO ls_order-system_status.
    APPEND 'PRC' TO ls_order-system_status.
    add_user_status( EXPORTING iv_profile = 'ZPP00001' iv_code = 'E0003' iv_text = 'BLQQ - Bloqueio da qualidade'
                     CHANGING  cs_order = ls_order ).
    ls_order-planned = 200.
    ls_order-confirmed = 0.
    ls_order-scrap = 0.
    ls_order-delivered = 0.
    ls_order-basic_start = '20261010'.
    ls_order-basic_finish = '20261015'.
    ls_order-sched_start = '20261010'.
    ls_order-sched_finish = '20261015'.
    APPEND ls_order TO mt_orders.

    add_operation( iv_aufnr        = '000001000002'
                   iv_vornr        = '0010'
                   iv_work_center  = 'MONT01'
                   iv_text         = 'Montagem do conjunto'
                   iv_status       = 'CRTD'
                   iv_sched_start  = '20261010'
                   iv_sched_finish = '20261015' ).
    add_component( iv_aufnr     = '000001000002'
                   iv_material  = 'RM-2101'
                   iv_text      = 'Carcaça fundida BC-300'
                   iv_required  = 200
                   iv_withdrawn = 0
                   iv_stock     = 400 ).
  ENDMETHOD.


  METHOD order_1000003.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.

    ls_order = new_order( iv_aufnr       = '000001000003'
                          iv_material    = 'FG-1003'
                          iv_description = 'Válvula gaveta VG-50'
                          iv_plant       = '1000'
                          iv_order_type  = 'PP01'
                          iv_mrp         = '001'
                          iv_scheduler   = '101' ).
    APPEND 'REL' TO ls_order-system_status.
    APPEND 'PRC' TO ls_order-system_status.
    APPEND 'MACM' TO ls_order-system_status.
    ls_order-planned = 1000.
    ls_order-confirmed = 0.
    ls_order-scrap = 0.
    ls_order-delivered = 0.
    ls_order-basic_start = '20261010'.
    ls_order-basic_finish = '20261017'.
    ls_order-sched_start = '20261010'.
    ls_order-sched_finish = '20261017'.
    APPEND ls_order TO mt_orders.

    add_operation( iv_aufnr        = '000001000003'
                   iv_vornr        = '0010'
                   iv_work_center  = 'USIN01'
                   iv_text         = 'Usinagem do corpo'
                   iv_status       = 'REL'
                   iv_sched_start  = '20261010'
                   iv_sched_finish = '20261017' ).
    add_component( iv_aufnr     = '000001000003'
                   iv_material  = 'RM-2201'
                   iv_text      = 'Corpo forjado VG-50'
                   iv_required  = 1000
                   iv_withdrawn = 0
                   iv_stock     = 2500 ).
  ENDMETHOD.


  METHOD order_1000004.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.

    ls_order = new_order( iv_aufnr       = '000001000004'
                          iv_material    = 'FG-1004'
                          iv_description = 'Válvula esfera VE-25'
                          iv_plant       = '1000'
                          iv_order_type  = 'PP01'
                          iv_mrp         = '001'
                          iv_scheduler   = '101' ).
    APPEND 'REL' TO ls_order-system_status.
    APPEND 'LKD' TO ls_order-system_status.
    APPEND 'PRC' TO ls_order-system_status.
    ls_order-planned = 300.
    ls_order-confirmed = 0.
    ls_order-scrap = 0.
    ls_order-delivered = 0.
    ls_order-basic_start = '20261009'.
    ls_order-basic_finish = '20261013'.
    ls_order-sched_start = '20261009'.
    ls_order-sched_finish = '20261013'.
    APPEND ls_order TO mt_orders.

    add_operation( iv_aufnr        = '000001000004'
                   iv_vornr        = '0010'
                   iv_work_center  = 'USIN01'
                   iv_text         = 'Usinagem da esfera'
                   iv_status       = 'REL'
                   iv_sched_start  = '20261009'
                   iv_sched_finish = '20261013' ).
    add_component( iv_aufnr     = '000001000004'
                   iv_material  = 'RM-2301'
                   iv_text      = 'Esfera inox 25 mm'
                   iv_required  = 300
                   iv_withdrawn = 0
                   iv_stock     = 900 ).
  ENDMETHOD.


  METHOD order_1000005.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.

    ls_order = new_order( iv_aufnr       = '000001000005'
                          iv_material    = 'FG-1005'
                          iv_description = 'Filtro Y FY-80'
                          iv_plant       = '1000'
                          iv_order_type  = 'PP01'
                          iv_mrp         = '001'
                          iv_scheduler   = '101' ).
    APPEND 'TECO' TO ls_order-system_status.
    APPEND 'PCNF' TO ls_order-system_status.
    APPEND 'PDLV' TO ls_order-system_status.
    APPEND 'PRC' TO ls_order-system_status.
    ls_order-planned = 400.
    ls_order-confirmed = 380.
    ls_order-scrap = 0.
    ls_order-delivered = 380.
    ls_order-basic_start = '20260909'.
    ls_order-basic_finish = '20260919'.
    ls_order-sched_start = '20260909'.
    ls_order-sched_finish = '20260919'.
    ls_order-actual_start = '20260909'.
    ls_order-actual_finish = '20260920'.
    APPEND ls_order TO mt_orders.

    add_operation( iv_aufnr         = '000001000005'
                   iv_vornr         = '0010'
                   iv_work_center   = 'MONT02'
                   iv_text          = 'Montagem do filtro'
                   iv_status        = 'CNF'
                   iv_sched_start   = '20260909'
                   iv_sched_finish  = '20260919'
                   iv_actual_start  = '20260909'
                   iv_actual_finish = '20260920'
                   iv_confirmed     = 380 ).
    add_component( iv_aufnr     = '000001000005'
                   iv_material  = 'RM-2401'
                   iv_text      = 'Corpo fundido FY-80'
                   iv_required  = 400
                   iv_withdrawn = 380
                   iv_stock     = 50 ).
  ENDMETHOD.


  METHOD order_1000006.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.

    ls_order = new_order( iv_aufnr       = '000001000006'
                          iv_material    = 'FG-1006'
                          iv_description = 'Bomba submersa BS-10'
                          iv_plant       = '1000'
                          iv_order_type  = 'PP01'
                          iv_mrp         = '001'
                          iv_scheduler   = '101' ).
    APPEND 'CRTD' TO ls_order-system_status.
    APPEND 'PRC' TO ls_order-system_status.
    add_user_status( EXPORTING iv_profile = 'ZPP00001' iv_code = 'E0002' iv_text = 'APRV - Aprovada'
                     CHANGING  cs_order = ls_order ).
    ls_order-planned = 150.
    ls_order-confirmed = 0.
    ls_order-scrap = 0.
    ls_order-delivered = 0.
    ls_order-basic_start = '20261012'.
    ls_order-basic_finish = '20261019'.
    ls_order-sched_start = '20261012'.
    ls_order-sched_finish = '20261019'.
    APPEND ls_order TO mt_orders.

    add_operation( iv_aufnr        = '000001000006'
                   iv_vornr        = '0010'
                   iv_work_center  = 'MONT01'
                   iv_text         = 'Montagem da bomba'
                   iv_status       = 'CRTD'
                   iv_sched_start  = '20261012'
                   iv_sched_finish = '20261019' ).
    add_component( iv_aufnr     = '000001000006'
                   iv_material  = 'RM-2501'
                   iv_text      = 'Motor 1 cv blindado'
                   iv_required  = 150
                   iv_withdrawn = 0
                   iv_stock     = 300 ).
  ENDMETHOD.

ENDCLASS.


CLASS ltc_pp01 DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    CONSTANTS c_today TYPE d VALUE '20261009'.

    DATA mo_reader TYPE REF TO ltd_reader.
    DATA mo_cut TYPE REF TO zcl_rx_diag_pp01.

    METHODS setup.
    METHODS run
      IMPORTING iv_order         TYPE string
      RETURNING VALUE(rs_result) TYPE zif_rx_types=>ty_result
      RAISING   zcx_rx_error.
    METHODS codes
      IMPORTING is_result       TYPE zif_rx_types=>ty_result
      RETURNING VALUE(rv_codes) TYPE string.
    METHODS check
      IMPORTING iv_order  TYPE string
                iv_status TYPE string
                iv_codes  TYPE string
      RAISING   zcx_rx_error.
    METHODS finding
      IMPORTING is_result         TYPE zif_rx_types=>ty_result
                iv_code           TYPE string
      RETURNING VALUE(rs_finding) TYPE zif_rx_types=>ty_finding.

    METHODS scenario_not_released FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_user_status_block FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_released_ok FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_locked FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_teco FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_manual_release FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_not_found FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_deleted FOR TESTING RAISING zcx_rx_error.
    METHODS missing_parts_detail FOR TESTING RAISING zcx_rx_error.
    METHODS user_status_block_detail FOR TESTING RAISING zcx_rx_error.
    METHODS components_table FOR TESTING RAISING zcx_rx_error.
    METHODS object_without_leading_zeros FOR TESTING RAISING zcx_rx_error.
    METHODS mapping_is_configurable FOR TESTING RAISING zcx_rx_error.
    METHODS not_authorized FOR TESTING RAISING zcx_rx_error.
    METHODS metadata FOR TESTING.
ENDCLASS.


CLASS ltc_pp01 IMPLEMENTATION.

  METHOD setup.
    CREATE OBJECT mo_reader.
    CREATE OBJECT mo_cut
      EXPORTING
        io_reader = mo_reader
        iv_today  = c_today.
  ENDMETHOD.

  METHOD run.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_param TYPE zif_rx_types=>ty_param.

    ls_param-name = 'productionOrder'.
    ls_param-value = iv_order.
    APPEND ls_param TO lt_params.
    rs_result = mo_cut->zif_rx_diagnostic~execute( lt_params ).
  ENDMETHOD.

  METHOD codes.
    FIELD-SYMBOLS <ls_finding> TYPE zif_rx_types=>ty_finding.

    LOOP AT is_result-findings ASSIGNING <ls_finding>.
      IF rv_codes IS INITIAL.
        rv_codes = <ls_finding>-code.
      ELSE.
        CONCATENATE rv_codes <ls_finding>-code INTO rv_codes SEPARATED BY ','.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD check.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_order ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = iv_status ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = iv_codes ).
  ENDMETHOD.

  METHOD finding.
    FIELD-SYMBOLS <ls_finding> TYPE zif_rx_types=>ty_finding.

    LOOP AT is_result-findings ASSIGNING <ls_finding> WHERE code = iv_code.
      rs_finding = <ls_finding>.
      RETURN.
    ENDLOOP.
    cl_abap_unit_assert=>fail( 'Achado não encontrado' ).
  ENDMETHOD.

  METHOD scenario_not_released.
    check( iv_order = '1000001' iv_status = 'PROBLEM_FOUND' iv_codes = 'PP01.NOT_RELEASED,PP01.MISSING_PARTS' ).
  ENDMETHOD.

  METHOD scenario_user_status_block.
    check( iv_order = '1000002' iv_status = 'PROBLEM_FOUND' iv_codes = 'PP01.NOT_RELEASED,PP01.USER_STATUS_BLOCK' ).
  ENDMETHOD.

  METHOD scenario_released_ok.
    check( iv_order = '1000003' iv_status = 'OK' iv_codes = 'PP01.RELEASED' ).
  ENDMETHOD.

  METHOD scenario_locked.
    check( iv_order = '1000004' iv_status = 'PROBLEM_FOUND' iv_codes = 'PP01.LOCKED' ).
  ENDMETHOD.

  METHOD scenario_teco.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    check( iv_order = '1000005' iv_status = 'OK' iv_codes = 'PP01.TECO' ).
    " Ordem encerrada: não há tabela de componentes a mostrar.
    ls_result = run( '1000005' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-tables ) exp = 0 ).
  ENDMETHOD.

  METHOD scenario_manual_release.
    check( iv_order = '1000006' iv_status = 'PROBLEM_FOUND' iv_codes = 'PP01.NOT_RELEASED,PP01.MANUAL_RELEASE' ).
  ENDMETHOD.

  METHOD scenario_not_found.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    check( iv_order = '1' iv_status = 'NOT_FOUND' iv_codes = 'PP01.NOT_FOUND' ).
    ls_result = run( '1' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-kind exp = 'PRODUCTION_ORDER' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '1' ).
  ENDMETHOD.

  METHOD scenario_deleted.
    " Ordem marcada para eliminação (DLFL): só informa, sem tabela.
    FIELD-SYMBOLS <ls_order> TYPE zif_rx_pp_reader=>ty_order.

    READ TABLE mo_reader->mt_orders ASSIGNING <ls_order> WITH KEY aufnr = '000001000001'.
    cl_abap_unit_assert=>assert_subrc( ).
    APPEND 'DLFL' TO <ls_order>-system_status.
    check( iv_order = '1000001' iv_status = 'OK' iv_codes = 'PP01.DELETED' ).
  ENDMETHOD.

  METHOD missing_parts_detail.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    ls_result = run( '1000001' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP01.MISSING_PARTS' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title exp = 'Falta de material em 2 componente(s)' ).
    " RM-2001 (estoque menor que o pendente) e RM-2003 (indicador de falta); RM-2002 está coberto.
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = 'RM-2001 (Carcaça fundida BC-200): precisa 500 PC, estoque 120 PC; RM-2003 (Selo mecânico 1 1/2"):' &
            ' precisa 500 PC, estoque 0 PC' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'CO24' ).
    " Evidências: status de sistema + uma reserva (RESB) por componente em falta.
    cl_abap_unit_assert=>assert_equals( act = lines( ls_finding-evidence ) exp = 3 ).
    READ TABLE ls_finding-evidence INDEX 1 INTO ls_evidence.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'JEST' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = 'CRTD MSPT PRC' ).
    READ TABLE ls_finding-evidence INDEX 2 INTO ls_evidence.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'RESB' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-label exp = 'Necessidade de RM-2001' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '500' ).
  ENDMETHOD.

  METHOD user_status_block_detail.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    ls_result = run( '1000002' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP01.USER_STATUS_BLOCK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = 'O status de usuário "BLQQ - Bloqueio da qualidade" (perfil ZPP00001) proíbe a liberação.' ).
    READ TABLE ls_finding-evidence INDEX 1 INTO ls_evidence.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = 'E0003' ).
  ENDMETHOD.

  METHOD components_table.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_table TYPE zif_rx_types=>ty_table.
    DATA lt_row TYPE string_table.
    DATA lv_keys TYPE string.

    ls_result = run( '1000001' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-tables ) exp = 1 ).
    READ TABLE ls_result-tables INDEX 1 INTO ls_table.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-id exp = 'components' ).
    lv_keys = zcl_rx_pp_view=>join( it_values = ls_table-keys iv_separator = ',' iv_space = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = lv_keys
                                        exp = 'material,description,required,withdrawn,pending,stock,short' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-columns ) exp = lines( ls_table-keys ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-rows ) exp = 3 ).
    " RM-2001: necessário 500, retirado 0, pendente 500, estoque 120 -> em falta.
    READ TABLE ls_table-rows INDEX 1 INTO lt_row.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_row ) exp = 7 ).
    lv_keys = zcl_rx_pp_view=>join( it_values = lt_row iv_separator = '|' iv_space = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = lv_keys
                                        exp = 'RM-2001|Carcaça fundida BC-200|500 PC|0 PC|500 PC|120 PC|Sim' ).
    " RM-2002: estoque 600 cobre os 500 pendentes.
    READ TABLE ls_table-rows INDEX 2 INTO lt_row.
    cl_abap_unit_assert=>assert_subrc( ).
    READ TABLE lt_row INDEX 7 INTO lv_keys.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = lv_keys exp = 'Não' ).
  ENDMETHOD.

  METHOD object_without_leading_zeros.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( '0001000003' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-kind exp = 'PRODUCTION_ORDER' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '1000003' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'PP01.RELEASED' ).
  ENDMETHOD.

  METHOD mapping_is_configurable.
    " Com E0002 (Aprovada) mapeado como bloqueio de liberação, a ordem 1000006 passa a ser bloqueada.
    FIELD-SYMBOLS <ls_map> TYPE zif_rx_pp_reader=>ty_status_map.

    READ TABLE mo_reader->mt_map ASSIGNING <ls_map> WITH KEY source_value = 'ZPP00001/E0002'.
    cl_abap_unit_assert=>assert_subrc( ).
    <ls_map>-situation = 'BLOCKS_RELEASE'.
    check( iv_order = '1000006' iv_status = 'PROBLEM_FOUND' iv_codes = 'PP01.NOT_RELEASED,PP01.USER_STATUS_BLOCK' ).
  ENDMETHOD.

  METHOD not_authorized.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA lx_error TYPE REF TO zcx_rx_error.

    mo_reader->mv_deny_all = abap_true.
    TRY.
        ls_result = run( '1000001' ).
        cl_abap_unit_assert=>fail( 'Esperava ZCX_RX_ERROR com HTTP 403' ).
      CATCH zcx_rx_error INTO lx_error.
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_http_status exp = 403 ).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'NOT_AUTHORIZED' ).
    ENDTRY.
  ENDMETHOD.

  METHOD metadata.
    DATA ls_meta TYPE zif_rx_types=>ty_diag_meta.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.

    ls_meta = mo_cut->zif_rx_diagnostic~get_metadata( ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-id exp = 'PP-01' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-version exp = '1.0' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-module exp = 'PP' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-kind exp = 'OBJECT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-title
                                        exp = 'Ordem de produção não liberada / falta de componentes' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_meta-params ) exp = 1 ).
    READ TABLE ls_meta-params INDEX 1 INTO ls_param.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-name exp = 'productionOrder' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Ordem de produção' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'DOCUMENT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-required exp = abap_true ).
  ENDMETHOD.

ENDCLASS.
