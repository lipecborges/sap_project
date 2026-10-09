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
    METHODS order_1000005.
    METHODS order_1000006.
    METHODS order_1000010.
    METHODS order_1000011.
    METHODS order_1000012.
    METHODS order_1000013.
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
    order_1000005( ).
    order_1000006( ).
    order_1000010( ).
    order_1000011( ).
    order_1000012( ).
    order_1000013( ).
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

ENDCLASS.


CLASS ltc_pp03 DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    CONSTANTS c_today TYPE d VALUE '20261009'.

    DATA mo_reader TYPE REF TO ltd_reader.
    DATA mo_cut TYPE REF TO zcl_rx_diag_pp03.

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
    METHODS fact
      IMPORTING is_result       TYPE zif_rx_types=>ty_result
                iv_id           TYPE string
      RETURNING VALUE(rv_value) TYPE string.
    METHODS fact_ids
      IMPORTING is_result     TYPE zif_rx_types=>ty_result
      RETURNING VALUE(rv_ids) TYPE string.
    METHODS table_of
      IMPORTING is_result       TYPE zif_rx_types=>ty_result
                iv_id           TYPE string
      RETURNING VALUE(rs_table) TYPE zif_rx_types=>ty_table.
    METHODS keys_of
      IMPORTING is_table       TYPE zif_rx_types=>ty_table
      RETURNING VALUE(rv_keys) TYPE string.
    METHODS row_text
      IMPORTING is_table       TYPE zif_rx_types=>ty_table
                iv_index       TYPE i
      RETURNING VALUE(rv_text) TYPE string.
    METHODS finding
      IMPORTING is_result         TYPE zif_rx_types=>ty_result
                iv_code           TYPE string
      RETURNING VALUE(rs_finding) TYPE zif_rx_types=>ty_finding.

    METHODS scenario_late_finish FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_delivered_ok FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_confirmed_no_receipt FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_reversed FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_late_start FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_not_found FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_teco FOR TESTING RAISING zcx_rx_error.
    METHODS scenario_approved FOR TESTING RAISING zcx_rx_error.
    METHODS facts_of_late_order FOR TESTING RAISING zcx_rx_error.
    METHODS facts_of_ontime_order FOR TESTING RAISING zcx_rx_error.
    METHODS finding_details FOR TESTING RAISING zcx_rx_error.
    METHODS finding_severities FOR TESTING RAISING zcx_rx_error.
    METHODS operations_table FOR TESTING RAISING zcx_rx_error.
    METHODS components_table FOR TESTING RAISING zcx_rx_error.
    METHODS confirmations_table FOR TESTING RAISING zcx_rx_error.
    METHODS related_sales_order FOR TESTING RAISING zcx_rx_error.
    METHODS tolerance_from_settings FOR TESTING RAISING zcx_rx_error.
    METHODS not_authorized FOR TESTING RAISING zcx_rx_error.
    METHODS object_without_zeros FOR TESTING RAISING zcx_rx_error.
    METHODS metadata FOR TESTING.
ENDCLASS.


CLASS ltc_pp03 IMPLEMENTATION.

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

  METHOD fact.
    FIELD-SYMBOLS <ls_fact> TYPE zif_rx_types=>ty_fact.

    LOOP AT is_result-facts ASSIGNING <ls_fact> WHERE id = iv_id.
      rv_value = <ls_fact>-value.
      RETURN.
    ENDLOOP.
    cl_abap_unit_assert=>fail( 'Fato não encontrado' ).
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

  METHOD table_of.
    FIELD-SYMBOLS <ls_table> TYPE zif_rx_types=>ty_table.

    LOOP AT is_result-tables ASSIGNING <ls_table> WHERE id = iv_id.
      rs_table = <ls_table>.
      RETURN.
    ENDLOOP.
    cl_abap_unit_assert=>fail( 'Tabela não encontrada' ).
  ENDMETHOD.

  METHOD keys_of.
    rv_keys = zcl_rx_pp_view=>join( it_values = is_table-keys iv_separator = ',' iv_space = abap_false ).
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

  METHOD scenario_late_finish.
    check( iv_order  = '1000010'
           iv_status = 'PROBLEM_FOUND'
           iv_codes  = 'PP03.LATE_FINISH,PP03.OPERATION_LATE,PP03.MISSING_PARTS,PP03.SALES_ORDER_AT_RISK' ).
  ENDMETHOD.

  METHOD scenario_delivered_ok.
    check( iv_order = '1000011' iv_status = 'OK' iv_codes = '' ).
  ENDMETHOD.

  METHOD scenario_confirmed_no_receipt.
    check( iv_order  = '1000012'
           iv_status = 'PROBLEM_FOUND'
           iv_codes  = 'PP03.LATE_FINISH,PP03.CONFIRMED_NOT_RECEIVED' ).
  ENDMETHOD.

  METHOD scenario_reversed.
    check( iv_order = '1000013' iv_status = 'OK' iv_codes = 'PP03.REVERSED_CONFIRMATION' ).
  ENDMETHOD.

  METHOD scenario_late_start.
    check( iv_order = '1000001' iv_status = 'PROBLEM_FOUND' iv_codes = 'PP03.LATE_START,PP03.MISSING_PARTS' ).
  ENDMETHOD.

  METHOD scenario_not_found.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    check( iv_order = '1' iv_status = 'NOT_FOUND' iv_codes = 'PP03.NOT_FOUND' ).
    ls_result = run( '1' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-kind exp = 'PRODUCTION_ORDER' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '1' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-facts ) exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-tables ) exp = 0 ).
  ENDMETHOD.

  METHOD scenario_teco.
    " Encerrada tecnicamente: não é tratada como atrasada.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    check( iv_order = '1000005' iv_status = 'OK' iv_codes = '' ).
    ls_result = run( '1000005' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'situation' )
                                        exp = 'Encerrada tecnicamente' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'delay' ) exp = 'No prazo' ).
  ENDMETHOD.

  METHOD scenario_approved.
    " "Aprovada" vem do mapeamento do status de usuário (ZRX_PPSTAT_MAP).
    DATA ls_result TYPE zif_rx_types=>ty_result.

    check( iv_order = '1000006' iv_status = 'OK' iv_codes = '' ).
    ls_result = run( '1000006' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'situation' ) exp = 'Aprovada' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'userStatus' )
                                        exp = 'APRV - Aprovada' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'systemStatus' ) exp = 'CRTD PRC' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'actualDates' ) exp = '— → —' ).
  ENDMETHOD.

  METHOD facts_of_late_order.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( '1000010' ).
    cl_abap_unit_assert=>assert_equals(
      act = fact_ids( ls_result )
      exp = 'material,plant,mrpController,situation,flags,systemStatus,userStatus,planned,confirmed,scrap,delivered,' &
            'basicDates,scheduledDates,actualDates,delay,salesOrder' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'material' )
                                        exp = 'FG-1010 · Conjunto motobomba MB-500' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'plant' ) exp = '1000 / PP02' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'mrpController' ) exp = '001 / 101' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'situation' ) exp = 'Em produção' ).
    cl_abap_unit_assert=>assert_equals(
      act = fact( is_result = ls_result iv_id = 'flags' )
      exp = 'Atrasada no fim, Operação atrasada, Falta de material, Risco para o pedido do cliente' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'systemStatus' )
                                        exp = 'REL PCNF PRC GMPS' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'userStatus' ) exp = '—' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'planned' ) exp = '1.000 PC' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'confirmed' ) exp = '600 PC (60%)' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'scrap' ) exp = '12 PC' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'delivered' ) exp = '0 PC (0%)' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'basicDates' )
                                        exp = '2026-09-27 → 2026-10-06' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'scheduledDates' )
                                        exp = '2026-09-27 → 2026-10-06' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'actualDates' )
                                        exp = '2026-09-27 → —' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'delay' )
                                        exp = 'Início: 0 dia(s) · Fim: 3 dia(s)' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'salesOrder' )
                                        exp = '4500020/10 · pedido para 2026-10-08' ).
  ENDMETHOD.

  METHOD facts_of_ontime_order.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( '1000011' ).
    " Sem pedido de venda vinculado, não há o fato salesOrder.
    cl_abap_unit_assert=>assert_equals(
      act = fact_ids( ls_result )
      exp = 'material,plant,mrpController,situation,flags,systemStatus,userStatus,planned,confirmed,scrap,delivered,' &
            'basicDates,scheduledDates,actualDates,delay' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'situation' ) exp = 'Entregue' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'flags' ) exp = 'Nenhum' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'delay' ) exp = 'No prazo' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'delivered' )
                                        exp = '300 PC (100%)' ).
    cl_abap_unit_assert=>assert_equals( act = fact( is_result = ls_result iv_id = 'actualDates' )
                                        exp = '2026-09-24 → 2026-09-30' ).
  ENDMETHOD.

  METHOD finding_details.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.

    ls_result = run( '1000010' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP03.LATE_FINISH' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title exp = 'Fim atrasado em 3 dia(s)' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = 'O fim programado era 2026-10-06. Confirmado até agora: 600 PC de 1.000 PC.' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'COOIS' ).
    READ TABLE ls_finding-evidence INDEX 1 INTO ls_evidence.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-source exp = 'AFKO' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'GLTRS' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = '2026-10-06' ).

    ls_finding = finding( is_result = ls_result iv_code = 'PP03.OPERATION_LATE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title exp = '2 operação(ões) atrasada(s)' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = '0020 Pintura eletrostática (PINT02), fim programado 2026-10-05;' &
            ' 0030 Teste de desempenho (TEST01), fim programado 2026-10-06' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_finding-evidence ) exp = 2 ).
    READ TABLE ls_finding-evidence INDEX 2 INTO ls_evidence.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-label exp = 'Fim programado da operação 0030' ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-field exp = 'FSEDD' ).

    ls_finding = finding( is_result = ls_result iv_code = 'PP03.SALES_ORDER_AT_RISK' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = 'A ordem atende o pedido 4500020/10, com data pedida 2026-10-08.' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'VA03' ).

    ls_result = run( '1000001' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP03.LATE_START' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-title exp = 'Início atrasado em 2 dia(s)' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = 'O início programado era 2026-10-07 e a ordem ainda não começou.' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP03.MISSING_PARTS' ).
    READ TABLE ls_finding-evidence INDEX 1 INTO ls_evidence.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_evidence-value exp = 'MSPT' ).

    ls_result = run( '1000012' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP03.CONFIRMED_NOT_RECEIVED' ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-detail
      exp = 'Foram confirmados 250 PC, mas só 0 PC deram entrada no estoque.' ).
  ENDMETHOD.

  METHOD finding_severities.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.

    ls_result = run( '1000010' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP03.LATE_FINISH' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP03.OPERATION_LATE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'WARNING' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP03.MISSING_PARTS' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'WARNING' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP03.SALES_ORDER_AT_RISK' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'WARNING' ).
    ls_result = run( '1000001' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP03.LATE_START' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'BLOCKING' ).
    ls_result = run( '1000012' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP03.CONFIRMED_NOT_RECEIVED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'WARNING' ).
    ls_result = run( '1000013' ).
    ls_finding = finding( is_result = ls_result iv_code = 'PP03.REVERSED_CONFIRMATION' ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-severity exp = 'INFO' ).
  ENDMETHOD.

  METHOD operations_table.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_table TYPE zif_rx_types=>ty_table.

    ls_result = run( '1000010' ).
    ls_table = table_of( is_result = ls_result iv_id = 'operations' ).
    cl_abap_unit_assert=>assert_equals(
      act = keys_of( ls_table )
      exp = 'operation,workCenter,description,status,scheduledFinish,actualFinish,confirmed,scrap' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-columns ) exp = lines( ls_table-keys ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_table-truncated exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-rows ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals(
      act = row_text( is_table = ls_table iv_index = 1 )
      exp = '0010|MONT01|Montagem do conjunto|CNF|2026-10-02|2026-10-03|1.000 PC|0 PC' ).
    cl_abap_unit_assert=>assert_equals(
      act = row_text( is_table = ls_table iv_index = 2 )
      exp = '0020|PINT02|Pintura eletrostática|PCNF|2026-10-05|—|600 PC|12 PC' ).
    cl_abap_unit_assert=>assert_equals(
      act = row_text( is_table = ls_table iv_index = 3 )
      exp = '0030|TEST01|Teste de desempenho|REL|2026-10-06|—|0 PC|0 PC' ).
  ENDMETHOD.

  METHOD components_table.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_table TYPE zif_rx_types=>ty_table.

    ls_result = run( '1000010' ).
    ls_table = table_of( is_result = ls_result iv_id = 'components' ).
    cl_abap_unit_assert=>assert_equals( act = keys_of( ls_table )
                                        exp = 'material,description,required,withdrawn,pending,stock,short' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-rows ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals(
      act = row_text( is_table = ls_table iv_index = 1 )
      exp = 'RM-3001|Motor 5 cv|1.000 PC|1.000 PC|0 PC|40 PC|Não' ).
    " Tinta: pendente 90, estoque 30 -> em falta.
    cl_abap_unit_assert=>assert_equals(
      act = row_text( is_table = ls_table iv_index = 3 )
      exp = 'RM-3003|Tinta epóxi azul (L)|250 PC|160 PC|90 PC|30 PC|Sim' ).
  ENDMETHOD.

  METHOD confirmations_table.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_table TYPE zif_rx_types=>ty_table.

    ls_result = run( '1000010' ).
    ls_table = table_of( is_result = ls_result iv_id = 'confirmations' ).
    cl_abap_unit_assert=>assert_equals( act = keys_of( ls_table ) exp = 'date,operation,yield,scrap,user,reversed' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-rows ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = row_text( is_table = ls_table iv_index = 2 )
                                        exp = '2026-10-06|0020|350 PC|12 PC|OPERADOR2|Não' ).
    " Apontamento estornado aparece com "Sim".
    ls_result = run( '1000013' ).
    ls_table = table_of( is_result = ls_result iv_id = 'confirmations' ).
    cl_abap_unit_assert=>assert_equals( act = row_text( is_table = ls_table iv_index = 1 )
                                        exp = '2026-10-06|0010|60 PC|0 PC|OPERADOR4|Sim' ).
    cl_abap_unit_assert=>assert_equals( act = row_text( is_table = ls_table iv_index = 2 )
                                        exp = '2026-10-07|0010|40 PC|0 PC|OPERADOR4|Não' ).
    " Ordem sem apontamentos: tabela presente e vazia.
    ls_result = run( '1000001' ).
    ls_table = table_of( is_result = ls_result iv_id = 'confirmations' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_table-rows ) exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-tables ) exp = 3 ).
  ENDMETHOD.

  METHOD related_sales_order.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_related TYPE zif_rx_types=>ty_object_ref.

    ls_result = run( '1000010' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-related ) exp = 1 ).
    READ TABLE ls_result-related INDEX 1 INTO ls_related.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_related-kind exp = 'SALES_ORDER' ).
    cl_abap_unit_assert=>assert_equals( act = ls_related-id exp = '4500020' ).
    ls_result = run( '1000011' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_result-related ) exp = 0 ).
  ENDMETHOD.

  METHOD tolerance_from_settings.
    " Tolerância de 5 dias (PP_LATE_TOLERANCE_DAYS): o atraso de 3 dias deixa de contar.
    mo_reader->ms_settings-tolerance_days = 5.
    check( iv_order  = '1000010'
           iv_status = 'PROBLEM_FOUND'
           iv_codes  = 'PP03.MISSING_PARTS,PP03.SALES_ORDER_AT_RISK' ).
    mo_reader->ms_settings-tolerance_days = 0.
    check( iv_order  = '1000012'
           iv_status = 'PROBLEM_FOUND'
           iv_codes  = 'PP03.LATE_FINISH,PP03.CONFIRMED_NOT_RECEIVED' ).
    mo_reader->ms_settings-tolerance_days = 1.
    check( iv_order = '1000012' iv_status = 'PROBLEM_FOUND' iv_codes = 'PP03.CONFIRMED_NOT_RECEIVED' ).
  ENDMETHOD.

  METHOD not_authorized.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA lx_error TYPE REF TO zcx_rx_error.

    mo_reader->mv_denied_type = 'PP02'.
    " 1000010 é do tipo PP02: negado. 1000011 é PP01: liberado.
    TRY.
        ls_result = run( '1000010' ).
        cl_abap_unit_assert=>fail( 'Esperava ZCX_RX_ERROR com HTTP 403' ).
      CATCH zcx_rx_error INTO lx_error.
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_http_status exp = 403 ).
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_code exp = 'NOT_AUTHORIZED' ).
    ENDTRY.
    ls_result = run( '1000011' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = 'OK' ).
  ENDMETHOD.

  METHOD object_without_zeros.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = run( '0001000012' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-object-id exp = '1000012' ).
    cl_abap_unit_assert=>assert_equals( act = codes( ls_result ) exp = 'PP03.LATE_FINISH,PP03.CONFIRMED_NOT_RECEIVED' ).
  ENDMETHOD.

  METHOD metadata.
    DATA ls_meta TYPE zif_rx_types=>ty_diag_meta.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.

    ls_meta = mo_cut->zif_rx_diagnostic~get_metadata( ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-id exp = 'PP-03' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-version exp = '1.0' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-module exp = 'PP' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-kind exp = 'OBJECT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_meta-title exp = 'Situação da ordem de produção' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_meta-params ) exp = 1 ).
    READ TABLE ls_meta-params INDEX 1 INTO ls_param.
    cl_abap_unit_assert=>assert_subrc( ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-name exp = 'productionOrder' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-label exp = 'Ordem de produção' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-data_type exp = 'DOCUMENT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_param-required exp = abap_true ).
  ENDMETHOD.

ENDCLASS.
