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
    METHODS order_1000010.
    METHODS order_1000011.
    METHODS order_1000012.
    METHODS order_1000013.
    METHODS order_1000014.
    METHODS order_2000001.
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
    METHODS add_confirmation
      IMPORTING iv_aufnr    TYPE zif_rx_pp_reader=>ty_aufnr
                iv_date     TYPE d
                iv_vornr    TYPE csequence
                iv_yield    TYPE zif_rx_pp_reader=>ty_qty
                iv_scrap    TYPE zif_rx_pp_reader=>ty_qty
                iv_user     TYPE csequence
                iv_reversed TYPE abap_bool.
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
    order_1000010( ).
    order_1000011( ).
    order_1000012( ).
    order_1000013( ).
    order_1000014( ).
    order_2000001( ).
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


  METHOD add_confirmation.
    DATA ls_confirmation TYPE zif_rx_pp_reader=>ty_confirmation.

    ls_confirmation-aufnr = iv_aufnr.
    ls_confirmation-date = iv_date.
    ls_confirmation-vornr = iv_vornr.
    ls_confirmation-yield = iv_yield.
    ls_confirmation-scrap = iv_scrap.
    ls_confirmation-user = iv_user.
    ls_confirmation-reversed = iv_reversed.
    APPEND ls_confirmation TO mt_confirmations.
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


  METHOD order_1000010.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.

    ls_order = new_order( iv_aufnr       = '000001000010'
                          iv_material    = 'FG-1010'
                          iv_description = 'Conjunto motobomba MB-500'
                          iv_plant       = '1000'
                          iv_order_type  = 'PP02'
                          iv_mrp         = '001'
                          iv_scheduler   = '101' ).
    APPEND 'REL' TO ls_order-system_status.
    APPEND 'PCNF' TO ls_order-system_status.
    APPEND 'PRC' TO ls_order-system_status.
    APPEND 'GMPS' TO ls_order-system_status.
    ls_order-planned = 1000.
    ls_order-confirmed = 600.
    ls_order-scrap = 12.
    ls_order-delivered = 0.
    ls_order-basic_start = '20260927'.
    ls_order-basic_finish = '20261006'.
    ls_order-sched_start = '20260927'.
    ls_order-sched_finish = '20261006'.
    ls_order-actual_start = '20260927'.
    ls_order-sales_order = '0004500020'.
    ls_order-sales_item = '000010'.
    ls_order-requested_date = '20261008'.
    APPEND ls_order TO mt_orders.

    add_operation( iv_aufnr         = '000001000010'
                   iv_vornr         = '0010'
                   iv_work_center   = 'MONT01'
                   iv_text          = 'Montagem do conjunto'
                   iv_status        = 'CNF'
                   iv_sched_start   = '20260927'
                   iv_sched_finish  = '20261002'
                   iv_actual_start  = '20260927'
                   iv_actual_finish = '20261003'
                   iv_confirmed     = 1000 ).
    add_operation( iv_aufnr        = '000001000010'
                   iv_vornr        = '0020'
                   iv_work_center  = 'PINT02'
                   iv_text         = 'Pintura eletrostática'
                   iv_status       = 'PCNF'
                   iv_sched_start  = '20261002'
                   iv_sched_finish = '20261005'
                   iv_actual_start = '20261003'
                   iv_confirmed    = 600
                   iv_scrap        = 12 ).
    add_operation( iv_aufnr        = '000001000010'
                   iv_vornr        = '0030'
                   iv_work_center  = 'TEST01'
                   iv_text         = 'Teste de desempenho'
                   iv_status       = 'REL'
                   iv_sched_start  = '20261005'
                   iv_sched_finish = '20261006' ).
    add_component( iv_aufnr     = '000001000010'
                   iv_material  = 'RM-3001'
                   iv_text      = 'Motor 5 cv'
                   iv_required  = 1000
                   iv_withdrawn = 1000
                   iv_stock     = 40 ).
    add_component( iv_aufnr     = '000001000010'
                   iv_material  = 'RM-3002'
                   iv_text      = 'Bomba BC-500'
                   iv_required  = 1000
                   iv_withdrawn = 1000
                   iv_stock     = 15 ).
    add_component( iv_aufnr     = '000001000010'
                   iv_material  = 'RM-3003'
                   iv_text      = 'Tinta epóxi azul (L)'
                   iv_required  = 250
                   iv_withdrawn = 160
                   iv_stock     = 30 ).
    add_confirmation( iv_aufnr    = '000001000010'
                      iv_date     = '20261003'
                      iv_vornr    = '0010'
                      iv_yield    = 1000
                      iv_scrap    = 0
                      iv_user     = 'OPERADOR1'
                      iv_reversed = abap_false ).
    add_confirmation( iv_aufnr    = '000001000010'
                      iv_date     = '20261006'
                      iv_vornr    = '0020'
                      iv_yield    = 350
                      iv_scrap    = 12
                      iv_user     = 'OPERADOR2'
                      iv_reversed = abap_false ).
    add_confirmation( iv_aufnr    = '000001000010'
                      iv_date     = '20261008'
                      iv_vornr    = '0020'
                      iv_yield    = 250
                      iv_scrap    = 0
                      iv_user     = 'OPERADOR2'
                      iv_reversed = abap_false ).
  ENDMETHOD.


  METHOD order_1000011.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.

    ls_order = new_order( iv_aufnr       = '000001000011'
                          iv_material    = 'FG-1011'
                          iv_description = 'Bomba centrífuga BC-200'
                          iv_plant       = '1000'
                          iv_order_type  = 'PP01'
                          iv_mrp         = '001'
                          iv_scheduler   = '101' ).
    APPEND 'REL' TO ls_order-system_status.
    APPEND 'CNF' TO ls_order-system_status.
    APPEND 'DLV' TO ls_order-system_status.
    APPEND 'PRC' TO ls_order-system_status.
    APPEND 'GMPS' TO ls_order-system_status.
    ls_order-planned = 300.
    ls_order-confirmed = 300.
    ls_order-scrap = 0.
    ls_order-delivered = 300.
    ls_order-basic_start = '20260924'.
    ls_order-basic_finish = '20261001'.
    ls_order-sched_start = '20260924'.
    ls_order-sched_finish = '20261001'.
    ls_order-actual_start = '20260924'.
    ls_order-actual_finish = '20260930'.
    APPEND ls_order TO mt_orders.

    add_operation( iv_aufnr         = '000001000011'
                   iv_vornr         = '0010'
                   iv_work_center   = 'MONT01'
                   iv_text          = 'Montagem do conjunto'
                   iv_status        = 'CNF'
                   iv_sched_start   = '20260924'
                   iv_sched_finish  = '20261001'
                   iv_actual_start  = '20260924'
                   iv_actual_finish = '20260930'
                   iv_confirmed     = 300 ).
    add_component( iv_aufnr     = '000001000011'
                   iv_material  = 'RM-2001'
                   iv_text      = 'Carcaça fundida BC-200'
                   iv_required  = 300
                   iv_withdrawn = 300
                   iv_stock     = 120 ).
    add_confirmation( iv_aufnr    = '000001000011'
                      iv_date     = '20260930'
                      iv_vornr    = '0010'
                      iv_yield    = 300
                      iv_scrap    = 0
                      iv_user     = 'OPERADOR1'
                      iv_reversed = abap_false ).
  ENDMETHOD.


  METHOD order_1000012.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.

    ls_order = new_order( iv_aufnr       = '000001000012'
                          iv_material    = 'FG-1012'
                          iv_description = 'Válvula gaveta VG-80'
                          iv_plant       = '1000'
                          iv_order_type  = 'PP01'
                          iv_mrp         = '001'
                          iv_scheduler   = '101' ).
    APPEND 'REL' TO ls_order-system_status.
    APPEND 'CNF' TO ls_order-system_status.
    APPEND 'PRC' TO ls_order-system_status.
    ls_order-planned = 250.
    ls_order-confirmed = 250.
    ls_order-scrap = 0.
    ls_order-delivered = 0.
    ls_order-basic_start = '20261003'.
    ls_order-basic_finish = '20261008'.
    ls_order-sched_start = '20261003'.
    ls_order-sched_finish = '20261008'.
    ls_order-actual_start = '20261003'.
    APPEND ls_order TO mt_orders.

    add_operation( iv_aufnr         = '000001000012'
                   iv_vornr         = '0010'
                   iv_work_center   = 'USIN01'
                   iv_text          = 'Usinagem do corpo'
                   iv_status        = 'CNF'
                   iv_sched_start   = '20261003'
                   iv_sched_finish  = '20261008'
                   iv_actual_start  = '20261003'
                   iv_actual_finish = '20261008'
                   iv_confirmed     = 250 ).
    add_component( iv_aufnr     = '000001000012'
                   iv_material  = 'RM-2202'
                   iv_text      = 'Corpo forjado VG-80'
                   iv_required  = 250
                   iv_withdrawn = 250
                   iv_stock     = 10 ).
    add_confirmation( iv_aufnr    = '000001000012'
                      iv_date     = '20261008'
                      iv_vornr    = '0010'
                      iv_yield    = 250
                      iv_scrap    = 0
                      iv_user     = 'OPERADOR3'
                      iv_reversed = abap_false ).
  ENDMETHOD.


  METHOD order_1000013.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.

    ls_order = new_order( iv_aufnr       = '000001000013'
                          iv_material    = 'FG-1013'
                          iv_description = 'Filtro cesto FC-100'
                          iv_plant       = '1000'
                          iv_order_type  = 'PP01'
                          iv_mrp         = '002'
                          iv_scheduler   = '101' ).
    APPEND 'REL' TO ls_order-system_status.
    APPEND 'PCNF' TO ls_order-system_status.
    APPEND 'PRC' TO ls_order-system_status.
    ls_order-planned = 120.
    ls_order-confirmed = 40.
    ls_order-scrap = 0.
    ls_order-delivered = 0.
    ls_order-basic_start = '20261005'.
    ls_order-basic_finish = '20261012'.
    ls_order-sched_start = '20261005'.
    ls_order-sched_finish = '20261012'.
    ls_order-actual_start = '20261005'.
    APPEND ls_order TO mt_orders.

    add_operation( iv_aufnr        = '000001000013'
                   iv_vornr        = '0010'
                   iv_work_center  = 'MONT02'
                   iv_text         = 'Montagem do filtro'
                   iv_status       = 'PCNF'
                   iv_sched_start  = '20261005'
                   iv_sched_finish = '20261012'
                   iv_actual_start = '20261005'
                   iv_confirmed    = 40 ).
    add_component( iv_aufnr     = '000001000013'
                   iv_material  = 'RM-2402'
                   iv_text      = 'Cesto inox FC-100'
                   iv_required  = 120
                   iv_withdrawn = 40
                   iv_stock     = 200 ).
    add_confirmation( iv_aufnr    = '000001000013'
                      iv_date     = '20261006'
                      iv_vornr    = '0010'
                      iv_yield    = 60
                      iv_scrap    = 0
                      iv_user     = 'OPERADOR4'
                      iv_reversed = abap_true ).
    add_confirmation( iv_aufnr    = '000001000013'
                      iv_date     = '20261007'
                      iv_vornr    = '0010'
                      iv_yield    = 40
                      iv_scrap    = 0
                      iv_user     = 'OPERADOR4'
                      iv_reversed = abap_false ).
  ENDMETHOD.


  METHOD order_1000014.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.

    ls_order = new_order( iv_aufnr       = '000001000014'
                          iv_material    = 'FG-1003'
                          iv_description = 'Válvula gaveta VG-50'
                          iv_plant       = '1000'
                          iv_order_type  = 'PP01'
                          iv_mrp         = '002'
                          iv_scheduler   = '101' ).
    APPEND 'REL' TO ls_order-system_status.
    APPEND 'PRC' TO ls_order-system_status.
    APPEND 'MACM' TO ls_order-system_status.
    ls_order-planned = 800.
    ls_order-confirmed = 0.
    ls_order-scrap = 0.
    ls_order-delivered = 0.
    ls_order-basic_start = '20261014'.
    ls_order-basic_finish = '20261021'.
    ls_order-sched_start = '20261014'.
    ls_order-sched_finish = '20261021'.
    APPEND ls_order TO mt_orders.

    add_operation( iv_aufnr        = '000001000014'
                   iv_vornr        = '0010'
                   iv_work_center  = 'USIN01'
                   iv_text         = 'Usinagem do corpo'
                   iv_status       = 'REL'
                   iv_sched_start  = '20261014'
                   iv_sched_finish = '20261021' ).
    add_component( iv_aufnr     = '000001000014'
                   iv_material  = 'RM-2201'
                   iv_text      = 'Corpo forjado VG-50'
                   iv_required  = 800
                   iv_withdrawn = 0
                   iv_stock     = 2500 ).
  ENDMETHOD.


  METHOD order_2000001.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.

    ls_order = new_order( iv_aufnr       = '000002000001'
                          iv_material    = 'FG-2001'
                          iv_description = 'Redutor RD-40'
                          iv_plant       = '2000'
                          iv_order_type  = 'PP01'
                          iv_mrp         = '010'
                          iv_scheduler   = '201' ).
    APPEND 'REL' TO ls_order-system_status.
    APPEND 'PRC' TO ls_order-system_status.
    ls_order-planned = 60.
    ls_order-confirmed = 0.
    ls_order-scrap = 0.
    ls_order-delivered = 0.
    ls_order-basic_start = '20261008'.
    ls_order-basic_finish = '20261015'.
    ls_order-sched_start = '20261008'.
    ls_order-sched_finish = '20261015'.
    APPEND ls_order TO mt_orders.

    add_operation( iv_aufnr        = '000002000001'
                   iv_vornr        = '0010'
                   iv_work_center  = 'MONT10'
                   iv_text         = 'Montagem do redutor'
                   iv_status       = 'REL'
                   iv_sched_start  = '20261008'
                   iv_sched_finish = '20261015' ).
    add_component( iv_aufnr     = '000002000001'
                   iv_material  = 'RM-4001'
                   iv_text      = 'Engrenagem helicoidal'
                   iv_required  = 120
                   iv_withdrawn = 0
                   iv_stock     = 500 ).
  ENDMETHOD.

ENDCLASS.


CLASS ltc_pp04 DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    CONSTANTS c_today TYPE d VALUE '20261009'.
    CONSTANTS c_all_sorted TYPE string VALUE
      '1000010,1000012,1000001,1000002,1000003,1000004,1000005,1000006,1000011,1000013,1000014'.

    DATA mo_reader TYPE REF TO ltd_reader.
    DATA mo_cut TYPE REF TO zcl_rx_diag_pp04.

    METHODS setup.
    METHODS run
      IMPORTING iv_plant         TYPE string
                iv_situation     TYPE string OPTIONAL
                iv_mrp           TYPE string OPTIONAL
                iv_order_type    TYPE string OPTIONAL
                iv_material      TYPE string OPTIONAL
                iv_from          TYPE string OPTIONAL
                iv_to            TYPE string OPTIONAL
                iv_max_rows      TYPE string OPTIONAL
                iv_page          TYPE string OPTIONAL
      RETURNING VALUE(rs_result) TYPE zif_rx_types=>ty_result
      RAISING   zcx_rx_error.
    METHODS add_param
      IMPORTING iv_name   TYPE string
                iv_value  TYPE string
      CHANGING  ct_params TYPE zif_rx_types=>ty_params.
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
    METHODS fact_ids
      IMPORTING is_result     TYPE zif_rx_types=>ty_result
      RETURNING VALUE(rv_ids) TYPE string.
    METHODS orders_table
      IMPORTING is_result       TYPE zif_rx_types=>ty_result
      RETURNING VALUE(rs_table) TYPE zif_rx_types=>ty_table.
    METHODS order_numbers
      IMPORTING is_result         TYPE zif_rx_types=>ty_result
      RETURNING VALUE(rv_numbers) TYPE string.
    METHODS row_text
      IMPORTING is_table       TYPE zif_rx_types=>ty_table
                iv_index       TYPE i
      RETURNING VALUE(rv_text) TYPE string.
    METHODS finding
      IMPORTING is_result         TYPE zif_rx_types=>ty_result
                iv_code           TYPE string
      RETURNING VALUE(rs_finding) TYPE zif_rx_types=>ty_finding.

    METHODS scenario_plant_1000 FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_no_orders FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_plant_2000 FOR TESTING RAISING zcx_rx_error.
    METHODS totals_by_situation_and_flag FOR TESTING RAISING zcx_rx_error.
    METHODS table_keys FOR TESTING RAISING zcx_rx_error.
    METHODS table_rows FOR TESTING RAISING zcx_rx_error.
    METHODS sorted_by_delay FOR TESTING RAISING zcx_rx_error.
    METHODS filter_late_finish FOR TESTING RAISING zcx_rx_error.
    METHODS filter_late_start FOR TESTING RAISING zcx_rx_error.
    METHODS filter_approved FOR TESTING RAISING zcx_rx_error.
    METHODS filter_released FOR TESTING RAISING zcx_rx_error.
    METHODS filter_locked FOR TESTING RAISING zcx_rx_error.
    METHODS filter_missing_parts FOR TESTING RAISING zcx_rx_error.
    METHODS filter_confirmed_no_receipt FOR TESTING RAISING zcx_rx_error.
    METHODS filter_mrp_controller FOR TESTING RAISING zcx_rx_error.
    METHODS filter_order_type FOR TESTING RAISING zcx_rx_error.
    METHODS filter_material FOR TESTING RAISING zcx_rx_error.
    METHODS filter_dates FOR TESTING RAISING zcx_rx_error.
    METHODS default_date_range FOR TESTING RAISING zcx_rx_error.
    METHODS filter_without_match FOR TESTING RAISING zcx_rx_error.
    METHODS pagination FOR TESTING RAISING zcx_rx_error.
    METHODS max_rows_from_settings FOR TESTING RAISING zcx_rx_error.
    METHODS summary_findings FOR TESTING RAISING zcx_rx_error.
    METHODS tolerance_from_settings FOR TESTING RAISING zcx_rx_error.
    METHODS omits_unauthorized_rows FOR TESTING RAISING zcx_rx_error.
    METHODS not_authorized FOR TESTING RAISING zcx_rx_error.
    METHODS metadata FOR TESTING.
ENDCLASS.


CLASS ltc_pp04 IMPLEMENTATION.

  METHOD setup.
    CREATE OBJECT mo_reader.
    CREATE OBJECT mo_cut
      EXPORTING
        io_reader = mo_reader
        iv_today  = c_today.
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

    add_param( EXPORTING iv_name = 'plant' iv_value = iv_plant CHANGING ct_params = lt_params ).
    add_param( EXPORTING iv_name = 'situation' iv_value = iv_situation CHANGING ct_params = lt_params ).
    add_param( EXPORTING iv_name = 'mrpController' iv_value = iv_mrp CHANGING ct_params = lt_params ).
    add_param( EXPORTING iv_name = 'orderType' iv_value = iv_order_type CHANGING ct_params = lt_params ).
    add_param( EXPORTING iv_name = 'material' iv_value = iv_material CHANGING ct_params = lt_params ).
    add_param( EXPORTING iv_name = 'dateFrom' iv_value = iv_from CHANGING ct_params = lt_params ).
    add_param( EXPORTING iv_name = 'dateTo' iv_value = iv_to CHANGING ct_params = lt_params ).
    add_param( EXPORTING iv_name = 'maxRows' iv_value = iv_max_rows CHANGING ct_params = lt_params ).
    add_param( EXPORTING iv_name = 'page' iv_value = iv_page CHANGING ct_params = lt_params ).
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

  METHOD fact.
    FIELD-SYMBOLS <ls_fact> TYPE zif_rx_types=>ty_fact.

    LOOP AT is_result-facts ASSIGNING <ls_fact> WHERE id = iv_id.
      rv_value = <ls_fact>-value.
      RETURN.
    ENDLOOP.
    cl_abap_unit_assert=>fail( 'Fato não encontrado' ).
  ENDMETHOD.

  METHOD has_fact.
    FIELD-SYMBOLS <ls_fact> TYPE zif_rx_types=>ty_fact.

    LOOP AT is_result-facts ASSIGNING <ls_fact> WHERE id = iv_id.
      rv_has = abap_true.
      RETURN.
    ENDLOOP.
  ENDMETHOD.

  METHOD fact_ids.
    FIELD-SYMBOLS <ls_fact> TYPE zif_rx_types=>ty_fact.

    LOOP AT is_result-facts ASSIGNING <ls_fact>.
      IF rv_ids IS INITIAL.
        rv_ids = <ls_fact>-id.
      ELSE.
        CONCATENATE rv_ids <ls_fact>-id INTO rv_ids SEPARATED BY ','.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD orders_table.
    FIELD-SYMBOLS <ls_table> TYPE zif_rx_types=>ty_table.

    LOOP AT is_result-tables ASSIGNING <ls_table> WHERE id = 'orders'.
      rs_table = <ls_table>.
      RETURN.
    ENDLOOP.
    cl_abap_unit_assert=>fail( 'Tabela orders não encontrada' ).
  ENDMETHOD.

  METHOD order_numbers.
    DATA ls_table TYPE zif_rx_types=>ty_table.
    DATA lt_numbers TYPE string_table.
    DATA lt_row TYPE string_table.
    DATA lv_number TYPE string.

    ls_table = orders_table( is_result ).
    LOOP AT ls_table-rows INTO lt_row.
      READ TABLE lt_row INDEX 1 INTO lv_number.
      cl_abap_unit_assert=>assert_subrc( ).
      APPEND lv_number TO lt_numbers.
    ENDLOOP.
    rv_numbers = zcl_rx_pp_view=>join( it_values = lt_numbers iv_separator = ',' iv_space = abap_false ).
  ENDMETHOD.

  METHOD row_text.
    DATA lt_row TYPE string_table.

    READ TABLE is_table-rows INDEX iv_index INTO lt_row.
    cl_abap_unit_assert=>assert_subrc( ).
    rv_text = zcl_rx_pp_view=>join( it_values = lt_row iv_separator = '|' iv_space = abap_false ).
  ENDMETHOD.

  METHOD finding.
    FIELD-SYMBOLS <ls_finding> TYPE zif_rx_types=>ty_finding.

    LOOP AT is_result-findings ASSIGNING <ls_finding> WHERE code = iv_code.
      rs_finding = <ls_finding>.
      RETURN.
    ENDLOOP.
    cl_abap_unit_assert=>fail( 'Achado não encontrado' ).
  ENDMETHOD.

  METHOD scenario_plant_1000.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( '1000' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'PP04.LATE_ORDERS,PP04.MISSING_PARTS' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-kind exp = 'PLANT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '1000' ).
  ENDMETHOD.

  METHOD scenario_no_orders.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    ls_result = run( '9999' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'NOT_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'PP04.NO_ORDERS' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-tables ) exp = 0 ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP04.NO_ORDERS' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'INFO' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title exp = 'Nenhuma ordem no centro' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-detail exp = 'Não há ordens de produção no centro 9999.' ).
    READ TABLE ls_finding-evidence INDEX 1 INTO ls_evidence.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'AUFK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'WERKS' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '9999' ).
  ENDMETHOD.

  METHOD scenario_plant_2000.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( '2000' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'PP04.LATE_ORDERS' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '2000001' ).
    cl_abap_unit_assert=>assert_equals( act = fact_ids( ls_result ) exp = 'total,situation:RELEASED,flag:LATE_START' ).
  ENDMETHOD.

  METHOD totals_by_situation_and_flag.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( '1000' ).
    cl_abap_unit_assert=>assert_equals(
      act = fact_ids( ls_result )
      exp = 'total,situation:IN_PRODUCTION,flag:LATE_FINISH,flag:OPERATION_LATE,flag:MISSING_PARTS,' &
            'flag:SALES_ORDER_AT_RISK,situation:CONFIRMED,flag:CONFIRMED_NOT_RECEIVED,situation:CREATED,' &
            'flag:LATE_START,situation:RELEASED,flag:LOCKED,situation:TECHNICALLY_COMPLETED,situation:APPROVED,' &
            'situation:DELIVERED,flag:REVERSED_CONFIRMATION' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '11' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'situation:IN_PRODUCTION' )
                                        exp = '2' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'situation:CREATED' ) exp = '2' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'situation:RELEASED' ) exp = '3' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'situation:DELIVERED' ) exp = '1' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'flag:LATE_FINISH' ) exp = '2' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'flag:MISSING_PARTS' ) exp = '2' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'flag:LOCKED' ) exp = '1' ).
    cl_abap_unit_assert=>assert_equals( act = has_fact( is_result = ls_result iv_id = 'omitted' ) exp = abap_false ).
  ENDMETHOD.

  METHOD table_keys.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_table TYPE zif_rx_types=>ty_table.
    DATA lv_keys TYPE string.
    DATA lv_columns TYPE string.

    ls_result = run( '1000' ).
    ls_table = orders_table( ls_result ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-title exp = 'Ordens de produção' ).
    lv_keys = zcl_rx_pp_view=>join( it_values = ls_table-keys iv_separator = ',' iv_space = abap_false ).
    cl_abap_unit_assert=>assert_equals(
      act = lv_keys
      exp = 'order,material,description,planned,confirmed,progress,delivered,situation,situationCode,flags,' &
            'flagCodes,scheduledFinish,delayDays,salesOrder' ).
    lv_columns = zcl_rx_pp_view=>join( it_values = ls_table-columns iv_separator = '|' iv_space = abap_false ).
    cl_abap_unit_assert=>assert_equals(
      act = lv_columns
      exp = 'Ordem|Material|Descrição|Planejada|Confirmada|% confirmado|Entregue|Situação|Código da situação|' &
            'Sinalizadores|Códigos dos sinalizadores|Fim programado|Dias de atraso|Pedido de venda' ).
  ENDMETHOD.

  METHOD table_rows.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_table TYPE zif_rx_types=>ty_table.

    ls_result = run( '1000' ).
    ls_table = orders_table( ls_result ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-rows ) exp = 11 ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_false ).
    cl_abap_unit_assert=>assert_equals(
      act = row_text( is_table = ls_table iv_index = 1 )
      exp = '1000010|FG-1010|Conjunto motobomba MB-500|1.000 PC|600 PC|60|0 PC|Em produção|IN_PRODUCTION|' &
            'Atrasada no fim, Operação atrasada, Falta de material, Risco para o pedido do cliente|' &
            'LATE_FINISH,OPERATION_LATE,MISSING_PARTS,SALES_ORDER_AT_RISK|2026-10-06|3|4500020/10' ).
    cl_abap_unit_assert=>assert_equals(
      act = row_text( is_table = ls_table iv_index = 2 )
      exp = '1000012|FG-1012|Válvula gaveta VG-80|250 PC|250 PC|100|0 PC|Produzida (confirmada)|CONFIRMED|' &
            'Atrasada no fim, Confirmada sem entrada|LATE_FINISH,CONFIRMED_NOT_RECEIVED|2026-10-08|1|' ).
    cl_abap_unit_assert=>assert_equals(
      act = row_text( is_table = ls_table iv_index = 3 )
      exp = '1000001|FG-1001|Bomba centrífuga BC-200|500 PC|0 PC|0|0 PC|Criada|CREATED|' &
            'Atrasada no início, Falta de material|LATE_START,MISSING_PARTS|2026-10-14|0|' ).
    " Sem sinalizadores: colunas de texto e de códigos vazias.
    cl_abap_unit_assert=>assert_equals(
      act = row_text( is_table = ls_table iv_index = 4 )
      exp = '1000002|FG-1002|Bomba centrífuga BC-300|200 PC|0 PC|0|0 PC|Criada|CREATED|||2026-10-15|0|' ).
    cl_abap_unit_assert=>assert_equals(
      act = row_text( is_table = ls_table iv_index = 7 )
      exp = '1000005|FG-1005|Filtro Y FY-80|400 PC|380 PC|95|380 PC|Encerrada tecnicamente|' &
            'TECHNICALLY_COMPLETED|||2026-09-19|0|' ).
    cl_abap_unit_assert=>assert_equals(
      act = row_text( is_table = ls_table iv_index = 10 )
      exp = '1000013|FG-1013|Filtro cesto FC-100|120 PC|40 PC|33|0 PC|Em produção|IN_PRODUCTION|' &
            'Apontamento estornado|REVERSED_CONFIRMATION|2026-10-12|0|' ).
  ENDMETHOD.

  METHOD sorted_by_delay.
    " Dias de atraso no fim (decrescente), depois no início; empates na ordem do leitor.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( '1000' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = c_all_sorted ).
  ENDMETHOD.

  METHOD filter_late_finish.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_plant = '1000' iv_situation = 'LATE_FINISH' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000010,1000012' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '2' ).
    " Os totais refletem só as ordens filtradas.
    cl_abap_unit_assert=>assert_equals( act = has_fact( is_result = ls_result iv_id = 'situation:CREATED' )
                                        exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'flag:LATE_FINISH' ) exp = '2' ).
  ENDMETHOD.

  METHOD filter_late_start.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_plant = '1000' iv_situation = 'LATE_START' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000001' ).
  ENDMETHOD.

  METHOD filter_approved.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_plant = '1000' iv_situation = 'APPROVED' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000006' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'OK' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-findings ) exp = 0 ).
  ENDMETHOD.

  METHOD filter_released.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_plant = '1000' iv_situation = 'RELEASED' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000003,1000004,1000014' ).
    ls_result = run( iv_plant = '1000' iv_situation = 'IN_PRODUCTION' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000010,1000013' ).
    ls_result = run( iv_plant = '1000' iv_situation = 'CREATED' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000001,1000002' ).
    ls_result = run( iv_plant = '1000' iv_situation = 'DELIVERED' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000011' ).
    ls_result = run( iv_plant = '1000' iv_situation = 'CONFIRMED' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000012' ).
    ls_result = run( iv_plant = '1000' iv_situation = 'TECHNICALLY_COMPLETED' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000005' ).
  ENDMETHOD.

  METHOD filter_locked.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_plant = '1000' iv_situation = 'LOCKED' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000004' ).
  ENDMETHOD.

  METHOD filter_missing_parts.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_plant = '1000' iv_situation = 'MISSING_PARTS' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000010,1000001' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'PP04.LATE_ORDERS,PP04.MISSING_PARTS' ).
  ENDMETHOD.

  METHOD filter_confirmed_no_receipt.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_plant = '1000' iv_situation = 'CONFIRMED_NOT_RECEIVED' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000012' ).
    ls_result = run( iv_plant = '1000' iv_situation = 'REVERSED_CONFIRMATION' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000013' ).
    ls_result = run( iv_plant = '1000' iv_situation = 'SALES_ORDER_AT_RISK' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000010' ).
    ls_result = run( iv_plant = '1000' iv_situation = 'OPERATION_LATE' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000010' ).
  ENDMETHOD.

  METHOD filter_mrp_controller.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_plant = '1000' iv_mrp = '002' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000013,1000014' ).
  ENDMETHOD.

  METHOD filter_order_type.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_plant = '1000' iv_order_type = 'PP02' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000010' ).
  ENDMETHOD.

  METHOD filter_material.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( iv_plant = '1000' iv_material = 'FG-1003' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000003,1000014' ).
  ENDMETHOD.

  METHOD filter_dates.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    " Período pelo fim programado.
    ls_result = run( iv_plant = '1000' iv_from = '2026-10-12' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result )
                                        exp = '1000001,1000002,1000003,1000004,1000006,1000013,1000014' ).
    ls_result = run( iv_plant = '1000' iv_to = '2026-10-01' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000005,1000011' ).
    ls_result = run( iv_plant = '1000' iv_from = '2026-10-05' iv_to = '2026-10-13' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000010,1000012,1000004,1000013' ).
  ENDMETHOD.

  METHOD default_date_range.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    " Sem datas: últimos 90 dias até hoje + 30 (catálogo).
    ls_result = run( '1000' ).
    cl_abap_unit_assert=>assert_equals( act = mo_reader->ms_last_filter-date_from exp = '20260711' ).
    cl_abap_unit_assert=>assert_equals( act = mo_reader->ms_last_filter-date_to exp = '20261108' ).
    " Com alguma data informada, o padrão não se aplica.
    ls_result = run( iv_plant = '1000' iv_from = '2026-10-01' ).
    cl_abap_unit_assert=>assert_equals( act = mo_reader->ms_last_filter-date_from exp = '20261001' ).
    cl_abap_unit_assert=>assert_initial( mo_reader->ms_last_filter-date_to ).
    " Nos filtros de atraso não há limite inicial: a ordem mais antiga é a mais atrasada.
    ls_result = run( iv_plant = '1000' iv_situation = 'LATE_FINISH' ).
    cl_abap_unit_assert=>assert_initial( mo_reader->ms_last_filter-date_from ).
    cl_abap_unit_assert=>assert_equals( act = mo_reader->ms_last_filter-date_to exp = '20261108' ).
    ls_result = run( iv_plant = '1000' iv_situation = 'OPERATION_LATE' ).
    cl_abap_unit_assert=>assert_initial( mo_reader->ms_last_filter-date_from ).
    " Os demais filtros chegam ao leitor.
    ls_result = run( iv_plant = '1000' iv_mrp = '002' iv_order_type = 'PP01' iv_material = 'FG-1003' ).
    cl_abap_unit_assert=>assert_equals( act = mo_reader->ms_last_filter-plant exp = '1000' ).
    cl_abap_unit_assert=>assert_equals( act = mo_reader->ms_last_filter-mrp_controller exp = '002' ).
    cl_abap_unit_assert=>assert_equals( act = mo_reader->ms_last_filter-order_type exp = 'PP01' ).
    cl_abap_unit_assert=>assert_equals( act = mo_reader->ms_last_filter-material exp = 'FG-1003' ).
  ENDMETHOD.

  METHOD filter_without_match.
    " O centro tem ordens, mas nenhuma passa pelos filtros: resultado vazio, não "centro sem ordens".
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_table TYPE zif_rx_types=>ty_table.

    ls_result = run( iv_plant = '1000' iv_mrp = '999' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'OK' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-findings ) exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = fact_ids( ls_result ) exp = 'total' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '0' ).
    ls_table = orders_table( ls_result ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-rows ) exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_false ).
  ENDMETHOD.

  METHOD pagination.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_table TYPE zif_rx_types=>ty_table.

    ls_result = run( iv_plant = '1000' iv_max_rows = '3' ).
    ls_table = orders_table( ls_result ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-rows ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000010,1000012,1000001' ).
    " O total e os achados continuam sobre todas as ordens, não só sobre a página.
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '11' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'PP04.LATE_ORDERS,PP04.MISSING_PARTS' ).

    ls_result = run( iv_plant = '1000' iv_max_rows = '3' iv_page = '2' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000002,1000003,1000004' ).
    ls_table = orders_table( ls_result ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_true ).

    ls_result = run( iv_plant = '1000' iv_max_rows = '3' iv_page = '3' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000005,1000006,1000011' ).
    ls_table = orders_table( ls_result ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_true ).

    ls_result = run( iv_plant = '1000' iv_max_rows = '3' iv_page = '4' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '1000013,1000014' ).
    ls_table = orders_table( ls_result ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_false ).

    " Página além do fim: vazia.
    ls_result = run( iv_plant = '1000' iv_max_rows = '3' iv_page = '9' ).
    cl_abap_unit_assert=>assert_equals( act = order_numbers( ls_result ) exp = '' ).
    ls_table = orders_table( ls_result ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_false ).

    " Tamanho exato da lista: não trunca.
    ls_result = run( iv_plant = '1000' iv_max_rows = '11' ).
    ls_table = orders_table( ls_result ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-rows ) exp = 11 ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_false ).
  ENDMETHOD.

  METHOD max_rows_from_settings.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_table TYPE zif_rx_types=>ty_table.

    " O limite de linhas da ZRX_CONFIG (MAX_ROWS) vale mesmo se o usuário pedir mais.
    mo_reader->ms_settings-max_rows = 2.
    ls_result = run( iv_plant = '1000' iv_max_rows = '100' ).
    ls_table = orders_table( ls_result ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-rows ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_true ).
    " Padrão de 100 linhas quando nada é pedido.
    mo_reader->ms_settings-max_rows = 500.
    ls_result = run( '1000' ).
    ls_table = orders_table( ls_result ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-rows ) exp = 11 ).
  ENDMETHOD.

  METHOD summary_findings.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.

    ls_result = run( '1000' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP04.LATE_ORDERS' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'WARNING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title exp = '3 ordem(ns) atrasada(s)' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = 'Ordens atrasadas: 1000010, 1000012, 1000001. Use o PP-03 para ver cada uma.' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'COOIS' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_finding-evidence ) exp = 0 ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP04.MISSING_PARTS' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'WARNING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title exp = '2 ordem(ns) com falta de material' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-detail
                                        exp = 'Ordens: 1000010, 1000001. Use o PP-01 para o detalhe.' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'CO24' ).
  ENDMETHOD.

  METHOD tolerance_from_settings.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    " Tolerância de 5 dias: nenhuma ordem passa a contar como atrasada; só a falta de material fica.
    mo_reader->ms_settings-tolerance_days = 5.
    ls_result = run( '1000' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'PP04.MISSING_PARTS' ).
    cl_abap_unit_assert=>assert_equals( act = has_fact( is_result = ls_result iv_id = 'flag:LATE_FINISH' )
                                        exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = has_fact( is_result = ls_result iv_id = 'flag:LATE_START' )
                                        exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'PROBLEM_FOUND' ).
  ENDMETHOD.

  METHOD omits_unauthorized_rows.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.

    " Sem autorização para o tipo PP02 (só a 1000010): a linha é omitida e o total omitido é informado.
    mo_reader->mv_denied_type = 'PP02'.
    ls_result = run( '1000' ).
    cl_abap_unit_assert=>assert_equals(
      act = order_numbers( ls_result )
      exp = '1000012,1000001,1000002,1000003,1000004,1000005,1000006,1000011,1000013,1000014' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'total' ) exp = '10' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'omitted' ) exp = '1' ).
    " Os achados também não citam a ordem omitida.
    ls_finding = finding( is_result = ls_result iv_code = 'PP04.LATE_ORDERS' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title exp = '2 ordem(ns) atrasada(s)' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = 'Ordens atrasadas: 1000012, 1000001. Use o PP-03 para ver cada uma.' ).
  ENDMETHOD.

  METHOD not_authorized.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA lx_error TYPE REF TO zcx_rx_error.

    " Sem autorização para nenhuma ordem do centro: 403.
    mo_reader->mv_deny_all = abap_true.
    TRY.
        ls_result = run( '1000' ).
        cl_abap_unit_assert=>fail( 'Esperava ZCX_RX_ERROR com HTTP 403' ).
      CATCH zcx_rx_error INTO lx_error.
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_http_status exp = 403 ).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'NOT_AUTHORIZED' ).
    ENDTRY.
  ENDMETHOD.

  METHOD metadata.
    DATA ls_meta TYPE zif_rx_types=>ty_diag_meta.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.
    DATA lv_names TYPE string.
    DATA lv_options TYPE string.
    DATA lt_names TYPE string_table.
    DATA lv_name TYPE string.

    ls_meta = mo_cut->zif_rx_diagnostic~get_metadata( ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-id exp = 'PP-04' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-version exp = '1.0' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-module exp = 'PP' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-kind exp = 'LIST' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-title exp = 'Ordens de produção por situação' ).
    LOOP AT ls_meta-params INTO ls_param.
      lv_name = ls_param-name.
      APPEND lv_name TO lt_names.
    ENDLOOP.
    lv_names = zcl_rx_pp_view=>join( it_values = lt_names iv_separator = ',' iv_space = abap_false ).
    cl_abap_unit_assert=>assert_equals(
      act = lv_names
      exp = 'plant,situation,mrpController,orderType,material,dateFrom,dateTo,maxRows,page' ).

    READ TABLE ls_meta-params INDEX 1 INTO ls_param.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Centro' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'STRING' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-required exp = abap_true ).

    " As opções do filtro: as situações seguidas dos sinalizadores (ordem do contrato).
    READ TABLE ls_meta-params INDEX 2 INTO ls_param.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Situação' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'ENUM' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-required exp = abap_false ).
    lv_options = zcl_rx_pp_view=>join( it_values = ls_param-options iv_separator = ',' iv_space = abap_false ).
    cl_abap_unit_assert=>assert_equals(
      act = lv_options
      exp = 'DELETED,CLOSED,TECHNICALLY_COMPLETED,DELIVERED,PARTIALLY_DELIVERED,CONFIRMED,IN_PRODUCTION,RELEASED,' &
            'APPROVED,CREATED,LATE_START,LATE_FINISH,OPERATION_LATE,MISSING_PARTS,LOCKED,CONFIRMED_NOT_RECEIVED,' &
            'SALES_ORDER_AT_RISK,REVERSED_CONFIRMATION' ).

    READ TABLE ls_meta-params INDEX 6 INTO ls_param.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Fim programado de' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'DATE' ).
    READ TABLE ls_meta-params INDEX 8 INTO ls_param.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-name exp = 'maxRows' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'INTEGER' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_param-options ) exp = 0 ).
  ENDMETHOD.

ENDCLASS.
