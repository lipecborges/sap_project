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


CLASS ltc_status_map DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    CONSTANTS c_today TYPE d VALUE '20261009'.

    DATA mo_reader TYPE REF TO ltd_reader.

    METHODS setup.
    "! Classifica a ordem do dublê com a tolerância e o mapeamento informados.
    METHODS classify
      IMPORTING iv_order                 TYPE string
                iv_tolerance             TYPE i DEFAULT 0
                it_mapping               TYPE zif_rx_pp_reader=>ty_status_maps OPTIONAL
                iv_use_double_mapping    TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(rs_classification) TYPE zcl_rx_pp_status_map=>ty_classification.
    METHODS situation_of
      IMPORTING iv_order            TYPE string
      RETURNING VALUE(rv_situation) TYPE string.
    METHODS has_flag
      IMPORTING iv_order      TYPE string
                iv_flag       TYPE string
      RETURNING VALUE(rv_has) TYPE abap_bool.
    METHODS flags_of
      IMPORTING iv_order        TYPE string
                iv_tolerance    TYPE i DEFAULT 0
      RETURNING VALUE(rv_flags) TYPE string.
    METHODS order_of
      IMPORTING iv_order        TYPE string
      RETURNING VALUE(rs_order) TYPE zif_rx_pp_reader=>ty_order.
    METHODS map_row
      IMPORTING iv_type      TYPE csequence
                iv_value     TYPE csequence
                iv_situation TYPE csequence
      CHANGING  ct_mapping   TYPE zif_rx_pp_reader=>ty_status_maps.

    METHODS situations FOR TESTING.
    METHODS flags_of_every_order FOR TESTING.
    METHODS delay_days FOR TESTING.
    METHODS tolerance FOR TESTING.
    METHODS tolerance_does_not_hide_other FOR TESTING.
    METHODS finished_orders_not_late FOR TESTING.
    METHODS partial_confirmation FOR TESTING.
    METHODS full_confirmation_no_receipt FOR TESTING.
    METHODS mapping_user_status FOR TESTING.
    METHODS mapping_system_status FOR TESTING.
    METHODS mapping_field FOR TESTING.
    METHODS mapping_empty FOR TESTING.
    METHODS blocking_user_statuses FOR TESTING.
    METHODS status_precedence FOR TESTING.
    METHODS component_shortage FOR TESTING.
    METHODS reversal_window FOR TESTING.
    METHODS sales_order_risk FOR TESTING.
    METHODS no_dates_no_delay FOR TESTING.
    METHODS labels_and_codes FOR TESTING.
ENDCLASS.


CLASS ltc_status_map IMPLEMENTATION.

  METHOD setup.
    CREATE OBJECT mo_reader.
  ENDMETHOD.

  METHOD order_of.
    DATA lv_aufnr TYPE zif_rx_pp_reader=>ty_aufnr.

    lv_aufnr = zcl_rx_format=>alpha_in( iv_value = iv_order iv_length = 12 ).
    rs_order = mo_reader->zif_rx_pp_reader~get_order( lv_aufnr ).
    cl_abap_unit_assert=>assert_not_initial( rs_order-aufnr ).
  ENDMETHOD.

  METHOD classify.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.
    DATA lt_aufnr TYPE zif_rx_pp_reader=>ty_aufnrs.
    DATA lt_mapping TYPE zif_rx_pp_reader=>ty_status_maps.
    DATA lt_operations TYPE zif_rx_pp_reader=>ty_operations.
    DATA lt_components TYPE zif_rx_pp_reader=>ty_components.
    DATA lt_confirmations TYPE zif_rx_pp_reader=>ty_confirmations.
    DATA lo_cut TYPE REF TO zcl_rx_pp_status_map.

    ls_order = order_of( iv_order ).
    APPEND ls_order-aufnr TO lt_aufnr.
    IF iv_use_double_mapping = abap_true.
      lt_mapping = mo_reader->zif_rx_pp_reader~get_status_map( ).
    ELSE.
      lt_mapping = it_mapping.
    ENDIF.
    CREATE OBJECT lo_cut
      EXPORTING
        iv_today          = c_today
        iv_tolerance_days = iv_tolerance
        it_mapping        = lt_mapping.
    lt_operations = mo_reader->zif_rx_pp_reader~get_operations( lt_aufnr ).
    lt_components = mo_reader->zif_rx_pp_reader~get_components( lt_aufnr ).
    lt_confirmations = mo_reader->zif_rx_pp_reader~get_confirmations( lt_aufnr ).
    rs_classification = lo_cut->classify( is_order         = ls_order
                                          it_operations    = lt_operations
                                          it_components    = lt_components
                                          it_confirmations = lt_confirmations ).
  ENDMETHOD.

  METHOD situation_of.
    DATA ls_classification TYPE zcl_rx_pp_status_map=>ty_classification.

    ls_classification = classify( iv_order ).
    rv_situation = ls_classification-situation.
  ENDMETHOD.

  METHOD has_flag.
    DATA lv_flags TYPE string.

    lv_flags = flags_of( iv_order ).
    IF lv_flags CS iv_flag.
      rv_has = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD flags_of.
    DATA ls_classification TYPE zcl_rx_pp_status_map=>ty_classification.

    ls_classification = classify( iv_order = iv_order iv_tolerance = iv_tolerance ).
    rv_flags = zcl_rx_pp_view=>join( it_values = ls_classification-flags iv_separator = ',' iv_space = abap_false ).
  ENDMETHOD.

  METHOD map_row.
    DATA ls_map TYPE zif_rx_pp_reader=>ty_status_map.

    ls_map-source_type = iv_type.
    ls_map-source_value = iv_value.
    ls_map-situation = iv_situation.
    APPEND ls_map TO ct_mapping.
  ENDMETHOD.

  METHOD situations.
    cl_abap_unit_assert=>assert_equals( act = situation_of( '1000001' ) exp = 'CREATED' ).
    cl_abap_unit_assert=>assert_equals( act = situation_of( '1000002' ) exp = 'CREATED' ).
    cl_abap_unit_assert=>assert_equals( act = situation_of( '1000003' ) exp = 'RELEASED' ).
    cl_abap_unit_assert=>assert_equals( act = situation_of( '1000004' ) exp = 'RELEASED' ).
    cl_abap_unit_assert=>assert_equals( act = situation_of( '1000005' ) exp = 'TECHNICALLY_COMPLETED' ).
    cl_abap_unit_assert=>assert_equals( act = situation_of( '1000006' ) exp = 'APPROVED' ).
    cl_abap_unit_assert=>assert_equals( act = situation_of( '1000010' ) exp = 'IN_PRODUCTION' ).
    cl_abap_unit_assert=>assert_equals( act = situation_of( '1000011' ) exp = 'DELIVERED' ).
    cl_abap_unit_assert=>assert_equals( act = situation_of( '1000012' ) exp = 'CONFIRMED' ).
    cl_abap_unit_assert=>assert_equals( act = situation_of( '1000013' ) exp = 'IN_PRODUCTION' ).
    cl_abap_unit_assert=>assert_equals( act = situation_of( '1000014' ) exp = 'RELEASED' ).
    cl_abap_unit_assert=>assert_equals( act = situation_of( '2000001' ) exp = 'RELEASED' ).
  ENDMETHOD.

  METHOD flags_of_every_order.
    cl_abap_unit_assert=>assert_equals( act = flags_of( '1000001' ) exp = 'LATE_START,MISSING_PARTS' ).
    cl_abap_unit_assert=>assert_equals( act = flags_of( '1000002' ) exp = '' ).
    cl_abap_unit_assert=>assert_equals( act = flags_of( '1000003' ) exp = '' ).
    cl_abap_unit_assert=>assert_equals( act = flags_of( '1000004' ) exp = 'LOCKED' ).
    cl_abap_unit_assert=>assert_equals( act = flags_of( '1000005' ) exp = '' ).
    cl_abap_unit_assert=>assert_equals( act = flags_of( '1000006' ) exp = '' ).
    cl_abap_unit_assert=>assert_equals(
      act = flags_of( '1000010' )
      exp = 'LATE_FINISH,OPERATION_LATE,MISSING_PARTS,SALES_ORDER_AT_RISK' ).
    cl_abap_unit_assert=>assert_equals( act = flags_of( '1000011' ) exp = '' ).
    cl_abap_unit_assert=>assert_equals( act = flags_of( '1000012' ) exp = 'LATE_FINISH,CONFIRMED_NOT_RECEIVED' ).
    cl_abap_unit_assert=>assert_equals( act = flags_of( '1000013' ) exp = 'REVERSED_CONFIRMATION' ).
    cl_abap_unit_assert=>assert_equals( act = flags_of( '1000014' ) exp = '' ).
    cl_abap_unit_assert=>assert_equals( act = flags_of( '2000001' ) exp = 'LATE_START' ).
  ENDMETHOD.

  METHOD delay_days.
    DATA ls_classification TYPE zcl_rx_pp_status_map=>ty_classification.

    " 1000010: fim programado há 3 dias, já começou.
    ls_classification = classify( '1000010' ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-finish_delay_days exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-start_delay_days exp = 0 ).
    " 1000001: início programado há 2 dias e ainda sem início real; o fim ainda está no prazo.
    ls_classification = classify( '1000001' ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-start_delay_days exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-finish_delay_days exp = 0 ).
    " 1000012: confirmada, mas sem entrada: o fim continua atrasado (1 dia).
    ls_classification = classify( '1000012' ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-finish_delay_days exp = 1 ).
    " Ordem no prazo.
    ls_classification = classify( '1000003' ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-finish_delay_days exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-start_delay_days exp = 0 ).
  ENDMETHOD.

  METHOD tolerance.
    DATA ls_classification TYPE zcl_rx_pp_status_map=>ty_classification.

    " Atraso de 3 dias com tolerância de 5: não é atraso; com tolerância de 2, é.
    cl_abap_unit_assert=>assert_equals(
      act = flags_of( iv_order = '1000010' iv_tolerance = 5 )
      exp = 'MISSING_PARTS,SALES_ORDER_AT_RISK' ).
    cl_abap_unit_assert=>assert_equals(
      act = flags_of( iv_order = '1000010' iv_tolerance = 2 )
      exp = 'LATE_FINISH,OPERATION_LATE,MISSING_PARTS,SALES_ORDER_AT_RISK' ).
    " Tolerância igual ao atraso: ainda não passou do limite (o atraso de 3 dias com tolerância 3 não conta).
    ls_classification = classify( iv_order = '1000010' iv_tolerance = 3 ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-finish_delay_days exp = 0 ).
    ls_classification = classify( iv_order = '1000001' iv_tolerance = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-start_delay_days exp = 0 ).
    ls_classification = classify( iv_order = '1000001' iv_tolerance = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-start_delay_days exp = 2 ).
  ENDMETHOD.

  METHOD tolerance_does_not_hide_other.
    " A tolerância vale só para atrasos; falta de material e risco ao cliente continuam.
    cl_abap_unit_assert=>assert_equals(
      act = flags_of( iv_order = '1000001' iv_tolerance = 30 )
      exp = 'MISSING_PARTS' ).
  ENDMETHOD.

  METHOD finished_orders_not_late.
    DATA ls_classification TYPE zcl_rx_pp_status_map=>ty_classification.

    cl_abap_unit_assert=>assert_equals( act = flags_of( '1000005' ) exp = '' ).
    cl_abap_unit_assert=>assert_equals( act = flags_of( '1000011' ) exp = '' ).
    ls_classification = classify( '1000005' ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-finish_delay_days exp = 0 ).
  ENDMETHOD.

  METHOD partial_confirmation.
    " Em PCNF (1000010) é normal a entrada vir só no fim: não sinaliza.
    cl_abap_unit_assert=>assert_false( has_flag( iv_order = '1000010' iv_flag = 'CONFIRMED_NOT_RECEIVED' ) ).
  ENDMETHOD.

  METHOD full_confirmation_no_receipt.
    cl_abap_unit_assert=>assert_true( has_flag( iv_order = '1000012' iv_flag = 'CONFIRMED_NOT_RECEIVED' ) ).
  ENDMETHOD.

  METHOD mapping_user_status.
    DATA lt_mapping TYPE zif_rx_pp_reader=>ty_status_maps.
    DATA ls_classification TYPE zcl_rx_pp_status_map=>ty_classification.

    " Sem mapeamento, o status de usuário "Aprovada" não muda a situação.
    ls_classification = classify( iv_order = '1000006' iv_use_double_mapping = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-situation exp = 'CREATED' ).
    " Outro status de usuário mapeado como Aprovada.
    map_row( EXPORTING iv_type = 'USER_STATUS' iv_value = 'ZPP00001/E0003' iv_situation = 'APPROVED'
             CHANGING  ct_mapping = lt_mapping ).
    ls_classification = classify( iv_order = '1000002' iv_use_double_mapping = abap_false it_mapping = lt_mapping ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-situation exp = 'APPROVED' ).
  ENDMETHOD.

  METHOD mapping_system_status.
    DATA lt_mapping TYPE zif_rx_pp_reader=>ty_status_maps.
    DATA ls_classification TYPE zcl_rx_pp_status_map=>ty_classification.

    " Status de sistema (abreviação EN) mapeado como Aprovada: vale para a ordem criada (CRTD + PRC).
    map_row( EXPORTING iv_type = 'SYSTEM_STATUS' iv_value = 'PRC' iv_situation = 'APPROVED'
             CHANGING  ct_mapping = lt_mapping ).
    ls_classification = classify( iv_order = '1000002' iv_use_double_mapping = abap_false it_mapping = lt_mapping ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-situation exp = 'APPROVED' ).
    " Liberada tem prioridade sobre Aprovada.
    ls_classification = classify( iv_order = '1000003' iv_use_double_mapping = abap_false it_mapping = lt_mapping ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-situation exp = 'RELEASED' ).
  ENDMETHOD.

  METHOD mapping_field.
    DATA lt_mapping TYPE zif_rx_pp_reader=>ty_status_maps.
    DATA ls_classification TYPE zcl_rx_pp_status_map=>ty_classification.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.
    DATA lt_empty_ops TYPE zif_rx_pp_reader=>ty_operations.
    DATA lt_empty_comps TYPE zif_rx_pp_reader=>ty_components.
    DATA lt_empty_confs TYPE zif_rx_pp_reader=>ty_confirmations.
    DATA lo_cut TYPE REF TO zcl_rx_pp_status_map.

    " Fonte FIELD: o leitor marca na ordem os valores da ZRX_PPSTAT_MAP que ela satisfaz.
    map_row( EXPORTING iv_type = 'FIELD' iv_value = 'AUFK-USER4=APR' iv_situation = 'APPROVED'
             CHANGING  ct_mapping = lt_mapping ).
    ls_order = order_of( '1000002' ).
    CREATE OBJECT lo_cut
      EXPORTING
        iv_today   = c_today
        it_mapping = lt_mapping.
    ls_classification = lo_cut->classify( is_order         = ls_order
                                          it_operations    = lt_empty_ops
                                          it_components    = lt_empty_comps
                                          it_confirmations = lt_empty_confs ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-situation exp = 'CREATED' ).
    APPEND 'AUFK-USER4=APR' TO ls_order-field_marks.
    ls_classification = lo_cut->classify( is_order         = ls_order
                                          it_operations    = lt_empty_ops
                                          it_components    = lt_empty_comps
                                          it_confirmations = lt_empty_confs ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-situation exp = 'APPROVED' ).
  ENDMETHOD.

  METHOD mapping_empty.
    DATA ls_classification TYPE zcl_rx_pp_status_map=>ty_classification.

    ls_classification = classify( iv_order = '1000001' iv_use_double_mapping = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-situation exp = 'CREATED' ).
  ENDMETHOD.

  METHOD blocking_user_statuses.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.
    DATA lt_mapping TYPE zif_rx_pp_reader=>ty_status_maps.
    DATA lt_blocking TYPE zif_rx_pp_reader=>ty_user_statuses.
    DATA ls_blocking TYPE zif_rx_pp_reader=>ty_user_status.
    DATA lo_cut TYPE REF TO zcl_rx_pp_status_map.

    lt_mapping = mo_reader->zif_rx_pp_reader~get_status_map( ).
    CREATE OBJECT lo_cut
      EXPORTING
        iv_today   = c_today
        it_mapping = lt_mapping.
    " 1000002 tem E0003 (bloqueia); 1000006 tem E0002 (aprova, não bloqueia).
    ls_order = order_of( '1000002' ).
    lt_blocking = lo_cut->blocking_user_statuses( ls_order ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_blocking ) exp = 1 ).
    READ TABLE lt_blocking INDEX 1 INTO ls_blocking.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_blocking-code exp = 'E0003' ).
    cl_abap_unit_assert=>assert_equals( act = ls_blocking-profile exp = 'ZPP00001' ).
    ls_order = order_of( '1000006' ).
    lt_blocking = lo_cut->blocking_user_statuses( ls_order ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_blocking ) exp = 0 ).
  ENDMETHOD.

  METHOD status_precedence.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.
    DATA lo_cut TYPE REF TO zcl_rx_pp_status_map.

    CREATE OBJECT lo_cut
      EXPORTING
        iv_today = c_today.
    " Cada status acrescentado passa na frente do anterior, até a eliminação.
    APPEND 'REL' TO ls_order-system_status.
    APPEND 'PCNF' TO ls_order-system_status.
    cl_abap_unit_assert=>assert_equals( act = lo_cut->situation_of( ls_order ) exp = 'IN_PRODUCTION' ).
    APPEND 'CNF' TO ls_order-system_status.
    cl_abap_unit_assert=>assert_equals( act = lo_cut->situation_of( ls_order ) exp = 'CONFIRMED' ).
    APPEND 'PDLV' TO ls_order-system_status.
    cl_abap_unit_assert=>assert_equals( act = lo_cut->situation_of( ls_order ) exp = 'PARTIALLY_DELIVERED' ).
    APPEND 'DLV' TO ls_order-system_status.
    cl_abap_unit_assert=>assert_equals( act = lo_cut->situation_of( ls_order ) exp = 'DELIVERED' ).
    APPEND 'TECO' TO ls_order-system_status.
    cl_abap_unit_assert=>assert_equals( act = lo_cut->situation_of( ls_order ) exp = 'TECHNICALLY_COMPLETED' ).
    APPEND 'CLSD' TO ls_order-system_status.
    cl_abap_unit_assert=>assert_equals( act = lo_cut->situation_of( ls_order ) exp = 'CLOSED' ).
    APPEND 'DLFL' TO ls_order-system_status.
    cl_abap_unit_assert=>assert_equals( act = lo_cut->situation_of( ls_order ) exp = 'DELETED' ).
    " Parcialmente liberada conta como liberada.
    CLEAR ls_order-system_status.
    APPEND 'PREL' TO ls_order-system_status.
    cl_abap_unit_assert=>assert_equals( act = lo_cut->situation_of( ls_order ) exp = 'RELEASED' ).
    CLEAR ls_order-system_status.
    cl_abap_unit_assert=>assert_equals( act = lo_cut->situation_of( ls_order ) exp = 'CREATED' ).
  ENDMETHOD.

  METHOD component_shortage.
    DATA ls_component TYPE zif_rx_pp_reader=>ty_component.

    " Estoque 100 para pendente 100 (necessário 120, retirado 20): sem falta.
    ls_component-required = 120.
    ls_component-withdrawn = 20.
    ls_component-stock = 100.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_pp_status_map=>is_short( ls_component ) exp = abap_false ).
    " Estoque menor que o pendente: falta.
    ls_component-stock = 99.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_pp_status_map=>is_short( ls_component ) exp = abap_true ).
    " Indicador de falta da reserva, mesmo com estoque.
    ls_component-stock = 500.
    ls_component-missing = abap_true.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_pp_status_map=>is_short( ls_component ) exp = abap_true ).
  ENDMETHOD.

  METHOD reversal_window.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.
    DATA lt_confirmations TYPE zif_rx_pp_reader=>ty_confirmations.
    DATA ls_confirmation TYPE zif_rx_pp_reader=>ty_confirmation.
    DATA lt_empty_ops TYPE zif_rx_pp_reader=>ty_operations.
    DATA lt_empty_comps TYPE zif_rx_pp_reader=>ty_components.
    DATA ls_classification TYPE zcl_rx_pp_status_map=>ty_classification.
    DATA lo_cut TYPE REF TO zcl_rx_pp_status_map.

    CREATE OBJECT lo_cut
      EXPORTING
        iv_today = c_today.
    ls_order-aufnr = '000009999999'.
    APPEND 'REL' TO ls_order-system_status.
    ls_confirmation-aufnr = ls_order-aufnr.
    ls_confirmation-reversed = abap_true.
    " Estorno de 7 dias atrás (limite da janela): conta. De 8 dias atrás: não conta.
    ls_confirmation-date = '20261002'.
    APPEND ls_confirmation TO lt_confirmations.
    ls_classification = lo_cut->classify( is_order         = ls_order
                                          it_operations    = lt_empty_ops
                                          it_components    = lt_empty_comps
                                          it_confirmations = lt_confirmations ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_classification-flags ) exp = 1 ).
    CLEAR lt_confirmations.
    ls_confirmation-date = '20261001'.
    APPEND ls_confirmation TO lt_confirmations.
    ls_classification = lo_cut->classify( is_order         = ls_order
                                          it_operations    = lt_empty_ops
                                          it_components    = lt_empty_comps
                                          it_confirmations = lt_confirmations ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_classification-flags ) exp = 0 ).
    " Apontamento recente que não foi estornado não sinaliza.
    CLEAR lt_confirmations.
    ls_confirmation-date = '20261008'.
    ls_confirmation-reversed = abap_false.
    APPEND ls_confirmation TO lt_confirmations.
    ls_classification = lo_cut->classify( is_order         = ls_order
                                          it_operations    = lt_empty_ops
                                          it_components    = lt_empty_comps
                                          it_confirmations = lt_confirmations ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_classification-flags ) exp = 0 ).
  ENDMETHOD.

  METHOD sales_order_risk.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.
    DATA lt_empty_ops TYPE zif_rx_pp_reader=>ty_operations.
    DATA lt_empty_comps TYPE zif_rx_pp_reader=>ty_components.
    DATA lt_empty_confs TYPE zif_rx_pp_reader=>ty_confirmations.
    DATA ls_classification TYPE zcl_rx_pp_status_map=>ty_classification.
    DATA lo_cut TYPE REF TO zcl_rx_pp_status_map.

    CREATE OBJECT lo_cut
      EXPORTING
        iv_today = c_today.
    APPEND 'REL' TO ls_order-system_status.
    ls_order-actual_start = '20261001'.
    ls_order-sched_start = '20261001'.
    ls_order-sales_order = '4500020'.
    " Fim programado no futuro, depois da data pedida: risco.
    ls_order-sched_finish = '20261020'.
    ls_order-requested_date = '20261015'.
    ls_classification = lo_cut->classify( is_order         = ls_order
                                          it_operations    = lt_empty_ops
                                          it_components    = lt_empty_comps
                                          it_confirmations = lt_empty_confs ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_classification-flags ) exp = 1 ).
    " Data pedida igual ao fim programado: sem risco.
    ls_order-requested_date = '20261020'.
    ls_classification = lo_cut->classify( is_order         = ls_order
                                          it_operations    = lt_empty_ops
                                          it_components    = lt_empty_comps
                                          it_confirmations = lt_empty_confs ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_classification-flags ) exp = 0 ).
    " Fim programado no passado: a ordem só termina hoje, então o pedido pedido para ontem está em risco.
    ls_order-sched_finish = '20261005'.
    ls_order-requested_date = '20261008'.
    ls_classification = lo_cut->classify( is_order         = ls_order
                                          it_operations    = lt_empty_ops
                                          it_components    = lt_empty_comps
                                          it_confirmations = lt_empty_confs ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_classification-flags ) exp = 2 ).
  ENDMETHOD.

  METHOD no_dates_no_delay.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.
    DATA lt_empty_ops TYPE zif_rx_pp_reader=>ty_operations.
    DATA lt_empty_comps TYPE zif_rx_pp_reader=>ty_components.
    DATA lt_empty_confs TYPE zif_rx_pp_reader=>ty_confirmations.
    DATA ls_classification TYPE zcl_rx_pp_status_map=>ty_classification.
    DATA lo_cut TYPE REF TO zcl_rx_pp_status_map.

    " Ordem sem datas programadas não é tratada como atrasada.
    CREATE OBJECT lo_cut
      EXPORTING
        iv_today = c_today.
    APPEND 'CRTD' TO ls_order-system_status.
    ls_classification = lo_cut->classify( is_order         = ls_order
                                          it_operations    = lt_empty_ops
                                          it_components    = lt_empty_comps
                                          it_confirmations = lt_empty_confs ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-start_delay_days exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = ls_classification-finish_delay_days exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_classification-flags ) exp = 0 ).
  ENDMETHOD.

  METHOD labels_and_codes.
    DATA lt_codes TYPE string_table.

    cl_abap_unit_assert=>assert_equals( act = zcl_rx_pp_status_map=>situation_label( 'CONFIRMED' )
                                        exp = 'Produzida (confirmada)' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_pp_status_map=>situation_label( 'IN_PRODUCTION' )
                                        exp = 'Em produção' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_pp_status_map=>flag_label( 'LATE_FINISH' )
                                        exp = 'Atrasada no fim' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_pp_status_map=>flag_label( 'SALES_ORDER_AT_RISK' )
                                        exp = 'Risco para o pedido do cliente' ).
    lt_codes = zcl_rx_pp_status_map=>all_situations( ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_codes ) exp = 10 ).
    lt_codes = zcl_rx_pp_status_map=>all_flags( ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_codes ) exp = 8 ).
    cl_abap_unit_assert=>assert_true( zcl_rx_pp_status_map=>is_finished( 'DELIVERED' ) ).
    cl_abap_unit_assert=>assert_false( zcl_rx_pp_status_map=>is_finished( 'CONFIRMED' ) ).
  ENDMETHOD.

ENDCLASS.
