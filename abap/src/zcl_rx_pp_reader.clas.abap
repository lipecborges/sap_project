"! Leitor real das ordens de produção (PP-01, PP-03 e PP-04): SELECTs nas tabelas SAP.
"! Somente leitura. Tabelas (ECC e S/4): AUFK, AFKO, AFPO, AFVC, AFVV, CRHD, RESB, MARD, MAKT, AFRU,
"! VBEP, JEST, JSTO, TJ02T, TJ30T e a ZRX_PPSTAT_MAP.
"! O status de sistema é lido da JEST (INACT = espaço) e devolvido como abreviação EN da TJ02T
"! (REL, PCNF, MSPT…), porque o idioma do usuário muda o texto. (validar: códigos internos I0001…, V10)
"! Não há diferença ECC x S/4 nestas tabelas (AFKO, AFPO, AUFK, RESB, AFRU, JEST e MARD-LABST continuam
"! com os mesmos campos), por isso não há SQL dinâmico por release; só o FIELD da ZRX_PPSTAT_MAP é dinâmico.
CLASS zcl_rx_pp_reader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_rx_pp_reader.

  PRIVATE SECTION.
    " Teto de ordens lidas por consulta (a classificação e a paginação acontecem depois da leitura).
    CONSTANTS c_scan_limit TYPE i VALUE 5000.
    " Idioma dos textos de status de sistema (abreviações estáveis, independentes do usuário).
    CONSTANTS c_language_en TYPE c LENGTH 1 VALUE 'E'.
    CONSTANTS c_order_category TYPE c LENGTH 2 VALUE '10'.

    TYPES:
      BEGIN OF ty_range_c,
        sign   TYPE c LENGTH 1,
        option TYPE c LENGTH 2,
        low    TYPE c LENGTH 40,
        high   TYPE c LENGTH 40,
      END OF ty_range_c,
      ty_ranges_c TYPE STANDARD TABLE OF ty_range_c WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_range_d,
        sign   TYPE c LENGTH 1,
        option TYPE c LENGTH 2,
        low    TYPE d,
        high   TYPE d,
      END OF ty_range_d,
      ty_ranges_d TYPE STANDARD TABLE OF ty_range_d WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_header,
        aufnr TYPE aufk-aufnr,
        auart TYPE aufk-auart,
        werks TYPE aufk-werks,
        objnr TYPE aufk-objnr,
        dispo TYPE afko-dispo,
        fevor TYPE afko-fevor,
        gamng TYPE afko-gamng,
        igmng TYPE afko-igmng,
        iasmg TYPE afko-iasmg,
        gstrp TYPE afko-gstrp,
        gltrp TYPE afko-gltrp,
        gstrs TYPE afko-gstrs,
        gltrs TYPE afko-gltrs,
        gstri TYPE afko-gstri,
        getri TYPE afko-getri,
        gltri TYPE afko-gltri,
        posnr TYPE afpo-posnr,
        matnr TYPE afpo-matnr,
        meins TYPE afpo-meins,
        wemng TYPE afpo-wemng,
        kdauf TYPE afpo-kdauf,
        kdpos TYPE afpo-kdpos,
      END OF ty_header,
      ty_headers TYPE STANDARD TABLE OF ty_header WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_jest_row,
        objnr TYPE jest-objnr,
        stat  TYPE jest-stat,
      END OF ty_jest_row,
      ty_jest_rows TYPE STANDARD TABLE OF ty_jest_row WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_jsto_row,
        objnr TYPE jsto-objnr,
        stsma TYPE jsto-stsma,
      END OF ty_jsto_row,
      ty_jsto_rows TYPE STANDARD TABLE OF ty_jsto_row WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_tj02t_row,
        istat TYPE tj02t-istat,
        txt04 TYPE tj02t-txt04,
      END OF ty_tj02t_row,
      ty_tj02t_rows TYPE STANDARD TABLE OF ty_tj02t_row WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_tj30t_row,
        stsma TYPE tj30t-stsma,
        estat TYPE tj30t-estat,
        txt04 TYPE tj30t-txt04,
        txt30 TYPE tj30t-txt30,
      END OF ty_tj30t_row,
      ty_tj30t_rows TYPE STANDARD TABLE OF ty_tj30t_row WITH DEFAULT KEY.

    " Status ativo de um objeto (ordem ou operação): sistema (abreviação) ou usuário (perfil/código/texto).
    TYPES:
      BEGIN OF ty_status_row,
        objnr   TYPE jest-objnr,
        is_user TYPE abap_bool,
        system  TYPE zif_rx_pp_reader=>ty_status,
        profile TYPE c LENGTH 8,
        code    TYPE c LENGTH 5,
        text    TYPE c LENGTH 40,
      END OF ty_status_row,
      ty_status_rows TYPE SORTED TABLE OF ty_status_row WITH NON-UNIQUE KEY objnr.

    TYPES:
      BEGIN OF ty_makt_row,
        matnr TYPE makt-matnr,
        maktx TYPE makt-maktx,
      END OF ty_makt_row,
      ty_makt_rows TYPE SORTED TABLE OF ty_makt_row WITH UNIQUE KEY matnr.

    TYPES:
      BEGIN OF ty_afko_row,
        aufnr TYPE afko-aufnr,
        aufpl TYPE afko-aufpl,
      END OF ty_afko_row,
      ty_afko_rows TYPE STANDARD TABLE OF ty_afko_row WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_afvc_row,
        aufpl TYPE afvc-aufpl,
        aplzl TYPE afvc-aplzl,
        vornr TYPE afvc-vornr,
        arbid TYPE afvc-arbid,
        ltxa1 TYPE afvc-ltxa1,
        objnr TYPE afvc-objnr,
      END OF ty_afvc_row,
      ty_afvc_rows TYPE STANDARD TABLE OF ty_afvc_row WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_afvv_row,
        aufpl TYPE afvv-aufpl,
        aplzl TYPE afvv-aplzl,
        lmnga TYPE afvv-lmnga,
        xmnga TYPE afvv-xmnga,
        fsavd TYPE afvv-fsavd,
        fsedd TYPE afvv-fsedd,
        isdd  TYPE afvv-isdd,
        iedd  TYPE afvv-iedd,
      END OF ty_afvv_row,
      ty_afvv_rows TYPE STANDARD TABLE OF ty_afvv_row WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_crhd_row,
        objid TYPE crhd-objid,
        arbpl TYPE crhd-arbpl,
      END OF ty_crhd_row,
      ty_crhd_rows TYPE STANDARD TABLE OF ty_crhd_row WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_resb_row,
        aufnr TYPE resb-aufnr,
        rspos TYPE resb-rspos,
        matnr TYPE resb-matnr,
        werks TYPE resb-werks,
        lgort TYPE resb-lgort,
        bdmng TYPE resb-bdmng,
        enmng TYPE resb-enmng,
        meins TYPE resb-meins,
        xfehl TYPE resb-xfehl,
      END OF ty_resb_row,
      ty_resb_rows TYPE STANDARD TABLE OF ty_resb_row WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_mard_row,
        matnr TYPE mard-matnr,
        werks TYPE mard-werks,
        lgort TYPE mard-lgort,
        labst TYPE mard-labst,
      END OF ty_mard_row,
      ty_mard_rows TYPE STANDARD TABLE OF ty_mard_row WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_afru_row,
        aufnr TYPE afru-aufnr,
        budat TYPE afru-budat,
        vornr TYPE afru-vornr,
        lmnga TYPE afru-lmnga,
        xmnga TYPE afru-xmnga,
        ernam TYPE afru-ernam,
        stokz TYPE afru-stokz,
        stzhl TYPE afru-stzhl,
      END OF ty_afru_row,
      ty_afru_rows TYPE STANDARD TABLE OF ty_afru_row WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_vbep_row,
        vbeln TYPE vbep-vbeln,
        posnr TYPE vbep-posnr,
        edatu TYPE vbep-edatu,
      END OF ty_vbep_row,
      ty_vbep_rows TYPE STANDARD TABLE OF ty_vbep_row WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_pair_row,
        aufnr TYPE c LENGTH 12,
        value TYPE c LENGTH 60,
      END OF ty_pair_row,
      ty_pair_rows TYPE STANDARD TABLE OF ty_pair_row WITH DEFAULT KEY.

    METHODS read_orders
      IMPORTING is_filter        TYPE zif_rx_pp_reader=>ty_filter
                it_aufnr         TYPE zif_rx_pp_reader=>ty_aufnrs
                iv_limit         TYPE i
      RETURNING VALUE(rt_orders) TYPE zif_rx_pp_reader=>ty_orders.

    METHODS select_headers
      IMPORTING is_filter         TYPE zif_rx_pp_reader=>ty_filter
                it_aufnr          TYPE zif_rx_pp_reader=>ty_aufnrs
                iv_limit          TYPE i
      RETURNING VALUE(rt_headers) TYPE ty_headers.

    METHODS to_order
      IMPORTING is_header       TYPE ty_header
      RETURNING VALUE(rs_order) TYPE zif_rx_pp_reader=>ty_order.

    METHODS fill_descriptions
      CHANGING ct_orders TYPE zif_rx_pp_reader=>ty_orders.

    METHODS fill_statuses
      CHANGING ct_orders TYPE zif_rx_pp_reader=>ty_orders.

    METHODS fill_sales_dates
      CHANGING ct_orders TYPE zif_rx_pp_reader=>ty_orders.

    METHODS fill_field_marks
      CHANGING ct_orders TYPE zif_rx_pp_reader=>ty_orders.

    METHODS mark_field
      IMPORTING is_map    TYPE zif_rx_pp_reader=>ty_status_map
      CHANGING  ct_orders TYPE zif_rx_pp_reader=>ty_orders.

    METHODS read_statuses
      IMPORTING it_objnr         TYPE string_table
      RETURNING VALUE(rt_status) TYPE ty_status_rows.

    METHODS read_material_texts
      IMPORTING it_matnr        TYPE string_table
      RETURNING VALUE(rt_texts) TYPE ty_makt_rows.

    METHODS read_stock
      IMPORTING it_resb         TYPE ty_resb_rows
      RETURNING VALUE(rt_stock) TYPE ty_mard_rows.

    "! Valores únicos e não vazios como faixa de seleção (EQ).
    METHODS to_range
      IMPORTING it_values       TYPE string_table
      RETURNING VALUE(rt_range) TYPE ty_ranges_c.

    METHODS to_internal_material
      IMPORTING iv_material        TYPE csequence
      RETURNING VALUE(rv_material) TYPE string.

    METHODS add_range_c
      IMPORTING iv_value TYPE csequence
      CHANGING  ct_range TYPE ty_ranges_c.

    METHODS add_range_d
      IMPORTING iv_from  TYPE d
                iv_to    TYPE d
      CHANGING  ct_range TYPE ty_ranges_d.

    METHODS convert_system_value
      IMPORTING iv_value        TYPE csequence
      RETURNING VALUE(rv_value) TYPE string.

ENDCLASS.



CLASS zcl_rx_pp_reader IMPLEMENTATION.

  METHOD zif_rx_pp_reader~get_order.
    DATA lt_aufnr TYPE zif_rx_pp_reader=>ty_aufnrs.
    DATA ls_filter TYPE zif_rx_pp_reader=>ty_filter.
    DATA lt_orders TYPE zif_rx_pp_reader=>ty_orders.

    APPEND iv_aufnr TO lt_aufnr.
    lt_orders = read_orders( is_filter = ls_filter it_aufnr = lt_aufnr iv_limit = 1 ).
    READ TABLE lt_orders INDEX 1 INTO rs_order.
    IF sy-subrc <> 0.
      CLEAR rs_order.
    ENDIF.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~find_orders.
    DATA lt_aufnr TYPE zif_rx_pp_reader=>ty_aufnrs.

    rt_orders = read_orders( is_filter = is_filter it_aufnr = lt_aufnr iv_limit = c_scan_limit ).
  ENDMETHOD.


  METHOD zif_rx_pp_reader~has_orders.
    DATA lv_aufnr TYPE aufk-aufnr.

    SELECT SINGLE aufnr FROM aufk INTO lv_aufnr
      WHERE werks = iv_plant AND autyp = c_order_category.
    IF sy-subrc = 0.
      rv_exists = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~get_operations.
    DATA lt_values TYPE string_table.
    DATA lt_afko TYPE ty_afko_rows.
    DATA lt_afvc TYPE ty_afvc_rows.
    DATA lt_afvv TYPE ty_afvv_rows.
    DATA lt_crhd TYPE ty_crhd_rows.
    DATA lt_status TYPE ty_status_rows.
    DATA lr_aufnr TYPE ty_ranges_c.
    DATA lr_aufpl TYPE ty_ranges_c.
    DATA lr_arbid TYPE ty_ranges_c.
    DATA ls_operation TYPE zif_rx_pp_reader=>ty_operation.
    DATA lv_text TYPE string.
    FIELD-SYMBOLS <lv_aufnr> TYPE zif_rx_pp_reader=>ty_aufnr.
    FIELD-SYMBOLS <ls_afko> TYPE ty_afko_row.
    FIELD-SYMBOLS <ls_afvc> TYPE ty_afvc_row.
    FIELD-SYMBOLS <ls_afvv> TYPE ty_afvv_row.
    FIELD-SYMBOLS <ls_crhd> TYPE ty_crhd_row.
    FIELD-SYMBOLS <ls_status> TYPE ty_status_row.

    LOOP AT it_aufnr ASSIGNING <lv_aufnr>.
      lv_text = <lv_aufnr>.
      APPEND lv_text TO lt_values.
    ENDLOOP.
    lr_aufnr = to_range( lt_values ).
    IF lr_aufnr IS INITIAL.
      RETURN.
    ENDIF.
    SELECT aufnr aufpl FROM afko INTO TABLE lt_afko
      WHERE aufnr IN lr_aufnr
      ORDER BY aufnr.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    CLEAR lt_values.
    LOOP AT lt_afko ASSIGNING <ls_afko>.
      lv_text = <ls_afko>-aufpl.
      APPEND lv_text TO lt_values.
    ENDLOOP.
    lr_aufpl = to_range( lt_values ).
    SELECT aufpl aplzl vornr arbid ltxa1 objnr FROM afvc INTO TABLE lt_afvc
      WHERE aufpl IN lr_aufpl
      ORDER BY aufpl aplzl.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    SELECT aufpl aplzl lmnga xmnga fsavd fsedd isdd iedd FROM afvv INTO TABLE lt_afvv
      WHERE aufpl IN lr_aufpl
      ORDER BY aufpl aplzl.
    IF sy-subrc <> 0.
      CLEAR lt_afvv.
    ENDIF.

    CLEAR lt_values.
    LOOP AT lt_afvc ASSIGNING <ls_afvc>.
      lv_text = <ls_afvc>-arbid.
      APPEND lv_text TO lt_values.
    ENDLOOP.
    lr_arbid = to_range( lt_values ).
    SELECT objid arbpl FROM crhd INTO TABLE lt_crhd
      WHERE objty = 'A' AND objid IN lr_arbid
      ORDER BY objid.
    IF sy-subrc <> 0.
      CLEAR lt_crhd.
    ENDIF.

    CLEAR lt_values.
    LOOP AT lt_afvc ASSIGNING <ls_afvc>.
      lv_text = <ls_afvc>-objnr.
      APPEND lv_text TO lt_values.
    ENDLOOP.
    lt_status = read_statuses( lt_values ).

    LOOP AT lt_afko ASSIGNING <ls_afko>.
      LOOP AT lt_afvc ASSIGNING <ls_afvc> WHERE aufpl = <ls_afko>-aufpl.
        CLEAR ls_operation.
        ls_operation-aufnr = <ls_afko>-aufnr.
        ls_operation-vornr = <ls_afvc>-vornr.
        ls_operation-description = <ls_afvc>-ltxa1.
        READ TABLE lt_crhd ASSIGNING <ls_crhd> WITH KEY objid = <ls_afvc>-arbid.
        IF sy-subrc = 0.
          ls_operation-work_center = <ls_crhd>-arbpl.
        ENDIF.
        READ TABLE lt_afvv ASSIGNING <ls_afvv> WITH KEY aufpl = <ls_afvc>-aufpl aplzl = <ls_afvc>-aplzl.
        IF sy-subrc = 0.
          ls_operation-sched_start = <ls_afvv>-fsavd.
          ls_operation-sched_finish = <ls_afvv>-fsedd.
          ls_operation-actual_start = <ls_afvv>-isdd.
          ls_operation-actual_finish = <ls_afvv>-iedd.
          ls_operation-confirmed = <ls_afvv>-lmnga.
          ls_operation-scrap = <ls_afvv>-xmnga.
        ENDIF.
        LOOP AT lt_status ASSIGNING <ls_status> WHERE objnr = <ls_afvc>-objnr AND is_user = abap_false.
          APPEND <ls_status>-system TO ls_operation-status.
        ENDLOOP.
        APPEND ls_operation TO rt_operations.
      ENDLOOP.
    ENDLOOP.
    SORT rt_operations BY aufnr vornr.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~get_components.
    DATA lt_values TYPE string_table.
    DATA lt_resb TYPE ty_resb_rows.
    DATA lt_mard TYPE ty_mard_rows.
    DATA lt_texts TYPE ty_makt_rows.
    DATA lr_aufnr TYPE ty_ranges_c.
    DATA ls_component TYPE zif_rx_pp_reader=>ty_component.
    DATA lv_text TYPE string.
    FIELD-SYMBOLS <lv_aufnr> TYPE zif_rx_pp_reader=>ty_aufnr.
    FIELD-SYMBOLS <ls_resb> TYPE ty_resb_row.
    FIELD-SYMBOLS <ls_mard> TYPE ty_mard_row.
    FIELD-SYMBOLS <ls_text> TYPE ty_makt_row.

    LOOP AT it_aufnr ASSIGNING <lv_aufnr>.
      lv_text = <lv_aufnr>.
      APPEND lv_text TO lt_values.
    ENDLOOP.
    lr_aufnr = to_range( lt_values ).
    IF lr_aufnr IS INITIAL.
      RETURN.
    ENDIF.
    " Reservas ativas (XLOEK vazio) da ordem. RESB-XFEHL = falta de material (validar, V05).
    SELECT aufnr rspos matnr werks lgort bdmng enmng meins xfehl FROM resb INTO TABLE lt_resb
      WHERE aufnr IN lr_aufnr AND xloek = space
      ORDER BY aufnr rspos.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    lt_mard = read_stock( lt_resb ).
    CLEAR lt_values.
    LOOP AT lt_resb ASSIGNING <ls_resb>.
      lv_text = <ls_resb>-matnr.
      APPEND lv_text TO lt_values.
    ENDLOOP.
    lt_texts = read_material_texts( lt_values ).

    LOOP AT lt_resb ASSIGNING <ls_resb>.
      CLEAR ls_component.
      ls_component-aufnr = <ls_resb>-aufnr.
      ls_component-material = <ls_resb>-matnr.
      ls_component-unit = <ls_resb>-meins.
      ls_component-required = <ls_resb>-bdmng.
      ls_component-withdrawn = <ls_resb>-enmng.
      IF <ls_resb>-xfehl IS NOT INITIAL.
        ls_component-missing = abap_true.
      ENDIF.
      READ TABLE lt_texts ASSIGNING <ls_text> WITH TABLE KEY matnr = <ls_resb>-matnr.
      IF sy-subrc = 0.
        ls_component-description = <ls_text>-maktx.
      ENDIF.
      " Estoque livre: do depósito da reserva ou, sem depósito, de todo o centro.
      LOOP AT lt_mard ASSIGNING <ls_mard> WHERE matnr = <ls_resb>-matnr AND werks = <ls_resb>-werks.
        IF <ls_resb>-lgort IS NOT INITIAL AND <ls_mard>-lgort <> <ls_resb>-lgort.
          CONTINUE.
        ENDIF.
        ls_component-stock = ls_component-stock + <ls_mard>-labst.
      ENDLOOP.
      APPEND ls_component TO rt_components.
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~get_confirmations.
    DATA lt_values TYPE string_table.
    DATA lt_afru TYPE ty_afru_rows.
    DATA lr_aufnr TYPE ty_ranges_c.
    DATA ls_confirmation TYPE zif_rx_pp_reader=>ty_confirmation.
    DATA lv_text TYPE string.
    FIELD-SYMBOLS <lv_aufnr> TYPE zif_rx_pp_reader=>ty_aufnr.
    FIELD-SYMBOLS <ls_afru> TYPE ty_afru_row.

    LOOP AT it_aufnr ASSIGNING <lv_aufnr>.
      lv_text = <lv_aufnr>.
      APPEND lv_text TO lt_values.
    ENDLOOP.
    lr_aufnr = to_range( lt_values ).
    IF lr_aufnr IS INITIAL.
      RETURN.
    ENDIF.
    SELECT aufnr budat vornr lmnga xmnga ernam stokz stzhl FROM afru INTO TABLE lt_afru
      WHERE aufnr IN lr_aufnr AND budat >= iv_since
      ORDER BY aufnr budat.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    LOOP AT lt_afru ASSIGNING <ls_afru>.
      " O documento de estorno (STZHL preenchido) não entra: o apontamento original (STOKZ = X)
      " é que fica marcado como estornado. (validar)
      IF <ls_afru>-stzhl IS NOT INITIAL.
        CONTINUE.
      ENDIF.
      CLEAR ls_confirmation.
      ls_confirmation-aufnr = <ls_afru>-aufnr.
      ls_confirmation-date = <ls_afru>-budat.
      ls_confirmation-vornr = <ls_afru>-vornr.
      ls_confirmation-yield = <ls_afru>-lmnga.
      ls_confirmation-scrap = <ls_afru>-xmnga.
      ls_confirmation-user = <ls_afru>-ernam.
      IF <ls_afru>-stokz IS NOT INITIAL.
        ls_confirmation-reversed = abap_true.
      ENDIF.
      APPEND ls_confirmation TO rt_confirmations.
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~get_status_map.
    DATA lt_rows TYPE zif_rx_pp_reader=>ty_status_maps.
    DATA lv_value TYPE string.
    FIELD-SYMBOLS <ls_row> TYPE zif_rx_pp_reader=>ty_status_map.

    SELECT source_type source_value situation FROM zrx_ppstat_map INTO TABLE lt_rows
      ORDER BY source_type source_value.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    LOOP AT lt_rows ASSIGNING <ls_row> WHERE source_type = 'SYSTEM_STATUS'.
      " Aceita o código interno (I0002) ou a abreviação EN (REL); a lógica usa a abreviação.
      lv_value = convert_system_value( <ls_row>-source_value ).
      <ls_row>-source_value = lv_value.
    ENDLOOP.
    rt_map = lt_rows.
  ENDMETHOD.


  METHOD zif_rx_pp_reader~get_settings.
    rs_settings-tolerance_days = zcl_rx_config=>get_int( iv_key = 'PP_LATE_TOLERANCE_DAYS' iv_default = 0 ).
    rs_settings-max_rows = zcl_rx_config=>get_int( iv_key = 'MAX_ROWS' iv_default = 500 ).
  ENDMETHOD.


  METHOD zif_rx_pp_reader~is_authorized.
    DATA lv_plant TYPE c LENGTH 4.
    DATA lv_type TYPE c LENGTH 4.

    lv_plant = iv_plant.
    lv_type = iv_order_type.
    " Objeto C_AFKO_AWK e nomes dos campos AUFART/WERKS a conferir em SU21. (validar, V04)
    AUTHORITY-CHECK OBJECT 'C_AFKO_AWK'
      ID 'ACTVT' FIELD '03'
      ID 'AUFART' FIELD lv_type
      ID 'WERKS' FIELD lv_plant.
    IF sy-subrc = 0.
      rv_authorized = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD read_orders.
    DATA lt_headers TYPE ty_headers.
    DATA ls_order TYPE zif_rx_pp_reader=>ty_order.
    FIELD-SYMBOLS <ls_header> TYPE ty_header.

    lt_headers = select_headers( is_filter = is_filter it_aufnr = it_aufnr iv_limit = iv_limit ).
    LOOP AT lt_headers ASSIGNING <ls_header>.
      ls_order = to_order( <ls_header> ).
      APPEND ls_order TO rt_orders.
    ENDLOOP.
    IF rt_orders IS INITIAL.
      RETURN.
    ENDIF.
    fill_descriptions( CHANGING ct_orders = rt_orders ).
    fill_statuses( CHANGING ct_orders = rt_orders ).
    fill_sales_dates( CHANGING ct_orders = rt_orders ).
    fill_field_marks( CHANGING ct_orders = rt_orders ).
  ENDMETHOD.


  METHOD select_headers.
    DATA lr_aufnr TYPE ty_ranges_c.
    DATA lr_werks TYPE ty_ranges_c.
    DATA lr_auart TYPE ty_ranges_c.
    DATA lr_dispo TYPE ty_ranges_c.
    DATA lr_matnr TYPE ty_ranges_c.
    DATA lr_gltrs TYPE ty_ranges_d.
    DATA lv_aufnr TYPE zif_rx_pp_reader=>ty_aufnr.
    DATA lv_material TYPE string.

    LOOP AT it_aufnr INTO lv_aufnr.
      add_range_c( EXPORTING iv_value = lv_aufnr CHANGING ct_range = lr_aufnr ).
    ENDLOOP.
    add_range_c( EXPORTING iv_value = is_filter-plant CHANGING ct_range = lr_werks ).
    add_range_c( EXPORTING iv_value = is_filter-order_type CHANGING ct_range = lr_auart ).
    add_range_c( EXPORTING iv_value = is_filter-mrp_controller CHANGING ct_range = lr_dispo ).
    lv_material = to_internal_material( is_filter-material ).
    add_range_c( EXPORTING iv_value = lv_material CHANGING ct_range = lr_matnr ).
    " Período pelo fim programado (GLTRS). (validar: ordens ainda não escalonadas ficam de fora)
    add_range_d( EXPORTING iv_from = is_filter-date_from iv_to = is_filter-date_to CHANGING ct_range = lr_gltrs ).

    " AFPO pode ter vários itens (ordem coletiva): fica o primeiro (menor POSNR).
    SELECT a~aufnr a~auart a~werks a~objnr
           b~dispo b~fevor b~gamng b~igmng b~iasmg
           b~gstrp b~gltrp b~gstrs b~gltrs b~gstri b~getri b~gltri
           c~posnr c~matnr c~meins c~wemng c~kdauf c~kdpos
      FROM aufk AS a
      INNER JOIN afko AS b ON b~aufnr = a~aufnr
      INNER JOIN afpo AS c ON c~aufnr = a~aufnr
      INTO TABLE rt_headers
      UP TO iv_limit ROWS
      WHERE a~autyp = c_order_category
        AND a~aufnr IN lr_aufnr
        AND a~werks IN lr_werks
        AND a~auart IN lr_auart
        AND b~dispo IN lr_dispo
        AND c~matnr IN lr_matnr
        AND b~gltrs IN lr_gltrs
      ORDER BY a~aufnr c~posnr.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    DELETE ADJACENT DUPLICATES FROM rt_headers COMPARING aufnr.
  ENDMETHOD.


  METHOD to_order.
    rs_order-aufnr = is_header-aufnr.
    rs_order-objnr = is_header-objnr.
    rs_order-material = is_header-matnr.
    rs_order-plant = is_header-werks.
    rs_order-order_type = is_header-auart.
    rs_order-mrp_controller = is_header-dispo.
    rs_order-scheduler = is_header-fevor.
    rs_order-unit = is_header-meins.
    " Quantidades: planejada AFKO-GAMNG, confirmada AFKO-IGMNG e refugo AFKO-IASMG (validar, V08).
    rs_order-planned = is_header-gamng.
    rs_order-confirmed = is_header-igmng.
    rs_order-scrap = is_header-iasmg.
    rs_order-delivered = is_header-wemng.
    rs_order-basic_start = is_header-gstrp.
    rs_order-basic_finish = is_header-gltrp.
    rs_order-sched_start = is_header-gstrs.
    IF rs_order-sched_start IS INITIAL.
      rs_order-sched_start = is_header-gstrp.
    ENDIF.
    rs_order-sched_finish = is_header-gltrs.
    IF rs_order-sched_finish IS INITIAL.
      rs_order-sched_finish = is_header-gltrp.
    ENDIF.
    " Datas reais: início GSTRI; fim GLTRI (ou GETRI, fim confirmado). (validar, V09)
    rs_order-actual_start = is_header-gstri.
    rs_order-actual_finish = is_header-gltri.
    IF rs_order-actual_finish IS INITIAL.
      rs_order-actual_finish = is_header-getri.
    ENDIF.
    IF is_header-kdauf IS NOT INITIAL.
      rs_order-sales_order = is_header-kdauf.
      rs_order-sales_item = is_header-kdpos.
    ENDIF.
  ENDMETHOD.


  METHOD fill_descriptions.
    DATA lt_values TYPE string_table.
    DATA lt_texts TYPE ty_makt_rows.
    DATA lv_text TYPE string.
    DATA lv_matnr TYPE makt-matnr.
    FIELD-SYMBOLS <ls_order> TYPE zif_rx_pp_reader=>ty_order.
    FIELD-SYMBOLS <ls_text> TYPE ty_makt_row.

    LOOP AT ct_orders ASSIGNING <ls_order>.
      lv_text = <ls_order>-material.
      APPEND lv_text TO lt_values.
    ENDLOOP.
    lt_texts = read_material_texts( lt_values ).
    LOOP AT ct_orders ASSIGNING <ls_order>.
      lv_matnr = <ls_order>-material.
      READ TABLE lt_texts ASSIGNING <ls_text> WITH TABLE KEY matnr = lv_matnr.
      IF sy-subrc = 0.
        <ls_order>-description = <ls_text>-maktx.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD fill_statuses.
    DATA lt_values TYPE string_table.
    DATA lt_status TYPE ty_status_rows.
    DATA lv_text TYPE string.
    DATA ls_user TYPE zif_rx_pp_reader=>ty_user_status.
    FIELD-SYMBOLS <ls_order> TYPE zif_rx_pp_reader=>ty_order.
    FIELD-SYMBOLS <ls_status> TYPE ty_status_row.

    LOOP AT ct_orders ASSIGNING <ls_order>.
      lv_text = <ls_order>-objnr.
      APPEND lv_text TO lt_values.
    ENDLOOP.
    lt_status = read_statuses( lt_values ).
    LOOP AT ct_orders ASSIGNING <ls_order>.
      LOOP AT lt_status ASSIGNING <ls_status> WHERE objnr = <ls_order>-objnr.
        IF <ls_status>-is_user = abap_true.
          ls_user-profile = <ls_status>-profile.
          ls_user-code = <ls_status>-code.
          ls_user-text = <ls_status>-text.
          APPEND ls_user TO <ls_order>-user_status.
        ELSE.
          APPEND <ls_status>-system TO <ls_order>-system_status.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD fill_sales_dates.
    DATA lt_values TYPE string_table.
    DATA lt_vbep TYPE ty_vbep_rows.
    DATA lr_vbeln TYPE ty_ranges_c.
    DATA lv_text TYPE string.
    FIELD-SYMBOLS <ls_order> TYPE zif_rx_pp_reader=>ty_order.
    FIELD-SYMBOLS <ls_vbep> TYPE ty_vbep_row.

    LOOP AT ct_orders ASSIGNING <ls_order> WHERE sales_order IS NOT INITIAL.
      lv_text = <ls_order>-sales_order.
      APPEND lv_text TO lt_values.
    ENDLOOP.
    lr_vbeln = to_range( lt_values ).
    IF lr_vbeln IS INITIAL.
      RETURN.
    ENDIF.
    " Data pedida pelo cliente: a menor data de remessa (VBEP-EDATU) do item. (validar)
    SELECT vbeln posnr edatu FROM vbep INTO TABLE lt_vbep
      WHERE vbeln IN lr_vbeln
      ORDER BY vbeln posnr.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    LOOP AT ct_orders ASSIGNING <ls_order> WHERE sales_order IS NOT INITIAL.
      LOOP AT lt_vbep ASSIGNING <ls_vbep> WHERE vbeln = <ls_order>-sales_order AND posnr = <ls_order>-sales_item.
        IF <ls_order>-requested_date IS INITIAL OR <ls_vbep>-edatu < <ls_order>-requested_date.
          <ls_order>-requested_date = <ls_vbep>-edatu.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD fill_field_marks.
    DATA lt_map TYPE zif_rx_pp_reader=>ty_status_maps.
    FIELD-SYMBOLS <ls_map> TYPE zif_rx_pp_reader=>ty_status_map.

    lt_map = zif_rx_pp_reader~get_status_map( ).
    LOOP AT lt_map ASSIGNING <ls_map> WHERE source_type = 'FIELD'.
      mark_field( EXPORTING is_map = <ls_map> CHANGING ct_orders = ct_orders ).
    ENDLOOP.
  ENDMETHOD.


  METHOD mark_field.
    " SOURCE_VALUE no formato TABELA-CAMPO=VALOR (ex.: AUFK-USER4=APR). Só tabelas liberadas na
    " ZRX_CONFIG (PP_FIELD_TABLES, padrão AUFK,AFKO,AFPO), todas com chave AUFNR. (validar)
    DATA lv_left TYPE string.
    DATA lv_expected TYPE string.
    DATA lv_table TYPE string.
    DATA lv_field TYPE string.
    DATA lv_allowed TYPE string.
    DATA lt_allowed TYPE string_table.
    DATA lt_fields TYPE string_table.
    DATA lt_values TYPE string_table.
    DATA lt_pairs TYPE ty_pair_rows.
    DATA lr_aufnr TYPE ty_ranges_c.
    DATA lv_text TYPE string.
    DATA lv_value TYPE string.
    FIELD-SYMBOLS <ls_order> TYPE zif_rx_pp_reader=>ty_order.
    FIELD-SYMBOLS <ls_pair> TYPE ty_pair_row.

    SPLIT is_map-source_value AT '=' INTO lv_left lv_expected.
    SPLIT lv_left AT '-' INTO lv_table lv_field.
    TRANSLATE lv_table TO UPPER CASE.
    TRANSLATE lv_field TO UPPER CASE.
    IF lv_table IS INITIAL OR lv_field IS INITIAL
        OR lv_table CN 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'
        OR lv_field CN 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'.
      RETURN.
    ENDIF.

    lv_allowed = zcl_rx_config=>get( 'PP_FIELD_TABLES' ).
    IF lv_allowed IS INITIAL.
      lv_allowed = 'AUFK,AFKO,AFPO'.
    ENDIF.
    SPLIT lv_allowed AT ',' INTO TABLE lt_allowed.
    READ TABLE lt_allowed WITH KEY table_line = lv_table TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT ct_orders ASSIGNING <ls_order>.
      lv_text = <ls_order>-aufnr.
      APPEND lv_text TO lt_values.
    ENDLOOP.
    lr_aufnr = to_range( lt_values ).
    APPEND 'AUFNR' TO lt_fields.
    APPEND lv_field TO lt_fields.
    SELECT (lt_fields) FROM (lv_table) INTO TABLE lt_pairs
      WHERE aufnr IN lr_aufnr
      ORDER BY aufnr.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_pairs ASSIGNING <ls_pair>.
      lv_value = <ls_pair>-value.
      IF lv_value <> lv_expected.
        CONTINUE.
      ENDIF.
      READ TABLE ct_orders ASSIGNING <ls_order> WITH KEY aufnr = <ls_pair>-aufnr.
      IF sy-subrc = 0.
        APPEND is_map-source_value TO <ls_order>-field_marks.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD read_statuses.
    DATA lt_jest TYPE ty_jest_rows.
    DATA lt_jsto TYPE ty_jsto_rows.
    DATA lt_tj02t TYPE ty_tj02t_rows.
    DATA lt_tj30t TYPE ty_tj30t_rows.
    DATA lt_istat TYPE string_table.
    DATA lt_stsma TYPE string_table.
    DATA lt_estat TYPE string_table.
    DATA lr_objnr TYPE ty_ranges_c.
    DATA lr_istat TYPE ty_ranges_c.
    DATA lr_stsma TYPE ty_ranges_c.
    DATA lr_estat TYPE ty_ranges_c.
    DATA ls_row TYPE ty_status_row.
    DATA lv_text TYPE string.
    FIELD-SYMBOLS <ls_jest> TYPE ty_jest_row.
    FIELD-SYMBOLS <ls_jsto> TYPE ty_jsto_row.
    FIELD-SYMBOLS <ls_tj02t> TYPE ty_tj02t_row.
    FIELD-SYMBOLS <ls_tj30t> TYPE ty_tj30t_row.

    lr_objnr = to_range( it_objnr ).
    IF lr_objnr IS INITIAL.
      RETURN.
    ENDIF.
    " Status ativos (INACT vazio): I* = sistema, E* = usuário.
    SELECT objnr stat FROM jest INTO TABLE lt_jest
      WHERE objnr IN lr_objnr AND inact = space
      ORDER BY objnr stat.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    SELECT objnr stsma FROM jsto INTO TABLE lt_jsto
      WHERE objnr IN lr_objnr
      ORDER BY objnr.
    IF sy-subrc <> 0.
      CLEAR lt_jsto.
    ENDIF.

    LOOP AT lt_jest ASSIGNING <ls_jest>.
      lv_text = <ls_jest>-stat.
      CASE <ls_jest>-stat(1).
        WHEN 'I'.
          APPEND lv_text TO lt_istat.
        WHEN 'E'.
          APPEND lv_text TO lt_estat.
      ENDCASE.
    ENDLOOP.
    LOOP AT lt_jsto ASSIGNING <ls_jsto>.
      lv_text = <ls_jsto>-stsma.
      APPEND lv_text TO lt_stsma.
    ENDLOOP.

    lr_istat = to_range( lt_istat ).
    IF lr_istat IS NOT INITIAL.
      SELECT istat txt04 FROM tj02t INTO TABLE lt_tj02t
        WHERE istat IN lr_istat AND spras = c_language_en
        ORDER BY istat.
      IF sy-subrc <> 0.
        CLEAR lt_tj02t.
      ENDIF.
    ENDIF.
    lr_stsma = to_range( lt_stsma ).
    lr_estat = to_range( lt_estat ).
    IF lr_estat IS NOT INITIAL AND lr_stsma IS NOT INITIAL.
      SELECT stsma estat txt04 txt30 FROM tj30t INTO TABLE lt_tj30t
        WHERE stsma IN lr_stsma AND estat IN lr_estat AND spras = sy-langu
        ORDER BY stsma estat.
      IF sy-subrc <> 0.
        CLEAR lt_tj30t.
      ENDIF.
    ENDIF.

    LOOP AT lt_jest ASSIGNING <ls_jest>.
      CLEAR ls_row.
      ls_row-objnr = <ls_jest>-objnr.
      CASE <ls_jest>-stat(1).
        WHEN 'I'.
          READ TABLE lt_tj02t ASSIGNING <ls_tj02t> WITH KEY istat = <ls_jest>-stat.
          IF sy-subrc = 0.
            ls_row-system = <ls_tj02t>-txt04.
          ELSE.
            ls_row-system = <ls_jest>-stat.
          ENDIF.
          INSERT ls_row INTO TABLE rt_status.
        WHEN 'E'.
          READ TABLE lt_jsto ASSIGNING <ls_jsto> WITH KEY objnr = <ls_jest>-objnr.
          IF sy-subrc <> 0.
            CONTINUE.
          ENDIF.
          ls_row-is_user = abap_true.
          ls_row-profile = <ls_jsto>-stsma.
          ls_row-code = <ls_jest>-stat.
          READ TABLE lt_tj30t ASSIGNING <ls_tj30t> WITH KEY stsma = <ls_jsto>-stsma estat = <ls_jest>-stat.
          IF sy-subrc = 0.
            CONCATENATE <ls_tj30t>-txt04 '-' <ls_tj30t>-txt30 INTO ls_row-text SEPARATED BY space.
          ENDIF.
          INSERT ls_row INTO TABLE rt_status.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.


  METHOD read_material_texts.
    DATA lr_matnr TYPE ty_ranges_c.
    DATA lt_rows TYPE ty_makt_rows.

    lr_matnr = to_range( it_matnr ).
    IF lr_matnr IS INITIAL.
      RETURN.
    ENDIF.
    SELECT matnr maktx FROM makt INTO TABLE lt_rows
      WHERE matnr IN lr_matnr AND spras = sy-langu
      ORDER BY matnr.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    rt_texts = lt_rows.
  ENDMETHOD.


  METHOD read_stock.
    DATA lt_matnr TYPE string_table.
    DATA lt_werks TYPE string_table.
    DATA lr_matnr TYPE ty_ranges_c.
    DATA lr_werks TYPE ty_ranges_c.
    DATA lv_text TYPE string.
    FIELD-SYMBOLS <ls_resb> TYPE ty_resb_row.

    LOOP AT it_resb ASSIGNING <ls_resb>.
      lv_text = <ls_resb>-matnr.
      APPEND lv_text TO lt_matnr.
      lv_text = <ls_resb>-werks.
      APPEND lv_text TO lt_werks.
    ENDLOOP.
    lr_matnr = to_range( lt_matnr ).
    lr_werks = to_range( lt_werks ).
    IF lr_matnr IS INITIAL OR lr_werks IS INITIAL.
      RETURN.
    ENDIF.
    " Faixas de material e centro trazem um superconjunto; o par exato é filtrado na leitura.
    SELECT matnr werks lgort labst FROM mard INTO TABLE rt_stock
      WHERE matnr IN lr_matnr AND werks IN lr_werks
      ORDER BY matnr werks lgort.
    IF sy-subrc <> 0.
      CLEAR rt_stock.
    ENDIF.
  ENDMETHOD.


  METHOD to_range.
    DATA lt_values TYPE string_table.
    DATA lv_value TYPE string.
    DATA ls_range TYPE ty_range_c.

    lt_values = it_values.
    SORT lt_values.
    DELETE ADJACENT DUPLICATES FROM lt_values.
    LOOP AT lt_values INTO lv_value.
      IF lv_value IS INITIAL.
        CONTINUE.
      ENDIF.
      ls_range-sign = 'I'.
      ls_range-option = 'EQ'.
      ls_range-low = lv_value.
      APPEND ls_range TO rt_range.
    ENDLOOP.
  ENDMETHOD.


  METHOD to_internal_material.
    DATA lv_input TYPE c LENGTH 40.
    DATA lv_output TYPE c LENGTH 40.

    IF iv_material IS INITIAL.
      RETURN.
    ENDIF.
    lv_input = iv_material.
    " Material numérico: completa com zeros (ECC) ou usa o formato do sistema. (validar)
    CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
      EXPORTING
        input  = lv_input
      IMPORTING
        output = lv_output
      EXCEPTIONS
        OTHERS = 1.
    IF sy-subrc = 0.
      rv_material = lv_output.
    ELSE.
      rv_material = lv_input.
    ENDIF.
  ENDMETHOD.


  METHOD add_range_c.
    DATA ls_range TYPE ty_range_c.

    IF iv_value IS INITIAL.
      RETURN.
    ENDIF.
    ls_range-sign = 'I'.
    ls_range-option = 'EQ'.
    ls_range-low = iv_value.
    APPEND ls_range TO ct_range.
  ENDMETHOD.


  METHOD add_range_d.
    DATA ls_range TYPE ty_range_d.

    IF iv_from IS INITIAL AND iv_to IS INITIAL.
      RETURN.
    ENDIF.
    ls_range-sign = 'I'.
    IF iv_from IS NOT INITIAL AND iv_to IS NOT INITIAL.
      ls_range-option = 'BT'.
      ls_range-low = iv_from.
      ls_range-high = iv_to.
    ELSEIF iv_from IS NOT INITIAL.
      ls_range-option = 'GE'.
      ls_range-low = iv_from.
    ELSE.
      ls_range-option = 'LE'.
      ls_range-low = iv_to.
    ENDIF.
    APPEND ls_range TO ct_range.
  ENDMETHOD.


  METHOD convert_system_value.
    DATA lv_code TYPE tj02t-istat.
    DATA lv_text TYPE tj02t-txt04.

    rv_value = iv_value.
    IF strlen( rv_value ) <> 5 OR rv_value(1) <> 'I' OR rv_value+1(4) CN '0123456789'.
      RETURN.
    ENDIF.
    lv_code = rv_value.
    SELECT SINGLE txt04 FROM tj02t INTO lv_text WHERE istat = lv_code AND spras = c_language_en.
    IF sy-subrc = 0.
      rv_value = lv_text.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
