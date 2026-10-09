"! Leitor real dos dados de compras (MM) para MM-02 e MM-10.
"! Somente leitura. RBKP, RSEG, EKBE, EKPO, EKET, T169G e BSIK têm a mesma estrutura
"! no ECC e no S/4 (no S/4, BSIK é visão de compatibilidade), por isso não há SQL dinâmico.
"! Os tipos das estruturas locais são ABAP embutidos: só os nomes de tabela e campo
"! dependem do dicionário. Pontos a confirmar num sistema real estão marcados com (validar).
CLASS zcl_rx_mm_reader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_rx_mm_reader.

  PRIVATE SECTION.
    TYPES ty_status TYPE c LENGTH 1.
    TYPES ty_status_range TYPE RANGE OF ty_status.
    TYPES ty_bukrs_range TYPE RANGE OF zif_rx_mm_reader=>ty_bukrs.

    TYPES:
      "! Campos lidos de RBKP (tipos ABAP embutidos; só os nomes dos campos vêm do dicionário).
      BEGIN OF ty_rbkp,
        belnr  TYPE c LENGTH 10,
        gjahr  TYPE n LENGTH 4,
        bukrs  TYPE c LENGTH 4,
        lifnr  TYPE c LENGTH 10,
        rmwwr  TYPE p LENGTH 13 DECIMALS 2,
        waers  TYPE c LENGTH 5,
        budat  TYPE d,
        bldat  TYPE d,
        zfbdt  TYPE d,
        zbd1t  TYPE p LENGTH 3 DECIMALS 0,
        zbd2t  TYPE p LENGTH 3 DECIMALS 0,
        zbd3t  TYPE p LENGTH 3 DECIMALS 0,
        rbstat TYPE c LENGTH 1,
        zlspr  TYPE c LENGTH 1,
      END OF ty_rbkp.
    TYPES ty_rbkp_tab TYPE STANDARD TABLE OF ty_rbkp WITH DEFAULT KEY.

    TYPES:
      "! Campos lidos de RSEG.
      BEGIN OF ty_rseg,
        belnr TYPE c LENGTH 10,
        gjahr TYPE n LENGTH 4,
        buzei TYPE n LENGTH 6,
        ebeln TYPE c LENGTH 10,
        ebelp TYPE n LENGTH 5,
        werks TYPE c LENGTH 4,
        menge TYPE p LENGTH 13 DECIMALS 3,
        meins TYPE c LENGTH 3,
        wrbtr TYPE p LENGTH 13 DECIMALS 2,
        spgrp TYPE c LENGTH 1,
        spgrm TYPE c LENGTH 1,
        spgrt TYPE c LENGTH 1,
        spgrg TYPE c LENGTH 1,
        spgrq TYPE c LENGTH 1,
        spgrs TYPE c LENGTH 1,
        spgrc TYPE c LENGTH 1,
        spgrv TYPE c LENGTH 1,
      END OF ty_rseg.
    TYPES ty_rseg_tab TYPE STANDARD TABLE OF ty_rseg WITH DEFAULT KEY.

    "! RBKP das faturas pendentes (bloqueadas e/ou estacionadas, não estornadas).
    CLASS-METHODS select_rbkp
      IMPORTING iv_bukrs       TYPE csequence
                iv_state       TYPE csequence
                iv_limit       TYPE i
      RETURNING VALUE(rt_rbkp) TYPE ty_rbkp_tab.

    "! Itens (RSEG) de uma fatura, só os campos de bloqueio e do pedido.
    CLASS-METHODS select_rseg
      IMPORTING iv_belnr       TYPE csequence
                iv_gjahr       TYPE csequence
      RETURNING VALUE(rt_rseg) TYPE ty_rseg_tab.

    "! Marca 'X' em CS_BLOCKS para cada motivo de bloqueio do item.
    CLASS-METHODS merge_blocks
      IMPORTING is_rseg   TYPE ty_rseg
      CHANGING  cs_blocks TYPE zif_rx_mm_reader=>ty_blocks.

    "! Vencimento de uma linha de RBKP.
    CLASS-METHODS rbkp_due_date
      IMPORTING is_rbkp        TYPE ty_rbkp
      RETURNING VALUE(rv_date) TYPE d.

    CLASS-METHODS unit_out
      IMPORTING iv_unit        TYPE csequence
      RETURNING VALUE(rv_unit) TYPE string.

    "! Vencimento = data-base + dias de prazo (ZBD3T, senão ZBD2T, senão ZBD1T).
    "! Sem data-base (ZFBDT), usa a data do documento. (validar)
    CLASS-METHODS due_date
      IMPORTING iv_base        TYPE d
                iv_fallback    TYPE d
                iv_days1       TYPE i
                iv_days2       TYPE i
                iv_days3       TYPE i
      RETURNING VALUE(rv_date) TYPE d.

    "! Situações de fatura estacionada em RBKP-RBSTAT. (validar: A, B e C; lançada = 5)
    CLASS-METHODS parked_statuses
      RETURNING VALUE(rt_range) TYPE ty_status_range.

    CLASS-METHODS vendor_name
      IMPORTING iv_lifnr       TYPE zif_rx_mm_reader=>ty_lifnr
      RETURNING VALUE(rv_name) TYPE string.

ENDCLASS.



CLASS zcl_rx_mm_reader IMPLEMENTATION.

  METHOD unit_out.
    DATA lv_output TYPE c LENGTH 3.

    rv_unit = iv_unit.
    CONDENSE rv_unit.
    IF rv_unit IS INITIAL.
      RETURN.
    ENDIF.
    " Unidade interna (ST) para a externa do idioma do usuário (PC). (validar)
    CALL FUNCTION 'CONVERSION_EXIT_CUNIT_OUTPUT'
      EXPORTING
        input    = iv_unit
        language = sy-langu
      IMPORTING
        output   = lv_output
      EXCEPTIONS
        OTHERS   = 1.
    IF sy-subrc = 0 AND lv_output IS NOT INITIAL.
      rv_unit = lv_output.
    ENDIF.
  ENDMETHOD.


  METHOD due_date.
    DATA lv_days TYPE i.
    DATA lv_base TYPE d.

    lv_base = iv_base.
    IF lv_base IS INITIAL.
      lv_base = iv_fallback.
    ENDIF.
    IF lv_base IS INITIAL.
      RETURN.
    ENDIF.
    IF iv_days3 > 0.
      lv_days = iv_days3.
    ELSEIF iv_days2 > 0.
      lv_days = iv_days2.
    ELSE.
      lv_days = iv_days1.
    ENDIF.
    rv_date = lv_base + lv_days.
  ENDMETHOD.


  METHOD parked_statuses.
    DATA ls_range LIKE LINE OF rt_range.

    ls_range-sign = 'I'.
    ls_range-option = 'EQ'.
    ls_range-low = 'A'.
    APPEND ls_range TO rt_range.
    ls_range-low = 'B'.
    APPEND ls_range TO rt_range.
    ls_range-low = 'C'.
    APPEND ls_range TO rt_range.
  ENDMETHOD.


  METHOD vendor_name.
    DATA lv_lifnr TYPE c LENGTH 10.
    DATA lv_name TYPE c LENGTH 35.

    lv_lifnr = iv_lifnr.
    SELECT SINGLE name1 FROM lfa1 INTO lv_name WHERE lifnr = lv_lifnr.
    IF sy-subrc = 0.
      rv_name = lv_name.
    ENDIF.
  ENDMETHOD.


  METHOD zif_rx_mm_reader~read_header.
    DATA ls_rbkp TYPE ty_rbkp.
    DATA lv_belnr TYPE c LENGTH 10.
    DATA lv_gjahr TYPE n LENGTH 4.
    DATA lt_parked TYPE ty_status_range.
    DATA lv_text TYPE c LENGTH 20.

    lv_belnr = iv_belnr.
    lv_gjahr = iv_gjahr.
    SELECT SINGLE bukrs lifnr rmwwr waers budat bldat zfbdt zbd1t zbd2t zbd3t rbstat zlspr
      FROM rbkp
      INTO CORRESPONDING FIELDS OF ls_rbkp
      WHERE belnr = lv_belnr
        AND gjahr = lv_gjahr.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    rs_header-found = abap_true.
    rs_header-belnr = iv_belnr.
    rs_header-gjahr = iv_gjahr.
    rs_header-bukrs = ls_rbkp-bukrs.
    rs_header-lifnr = ls_rbkp-lifnr.
    rs_header-vendor_name = vendor_name( rs_header-lifnr ).
    rs_header-rmwwr = ls_rbkp-rmwwr.
    rs_header-waers = ls_rbkp-waers.
    rs_header-budat = ls_rbkp-budat.
    rs_header-rbstat = ls_rbkp-rbstat.
    rs_header-zlspr = ls_rbkp-zlspr.

    lt_parked = parked_statuses( ).
    IF ls_rbkp-rbstat IN lt_parked.
      rs_header-parked = abap_true.
    ENDIF.

    rs_header-due_date = rbkp_due_date( ls_rbkp ).

    IF ls_rbkp-zlspr IS NOT INITIAL.
      " Texto do motivo de bloqueio de pagamento. (validar: T008T-TEXTM)
      SELECT SINGLE textm FROM t008t INTO lv_text
        WHERE spras = sy-langu
          AND zahls = ls_rbkp-zlspr.
      IF sy-subrc = 0.
        rs_header-zlspr_text = lv_text.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD zif_rx_mm_reader~read_items.
    DATA lt_rseg TYPE ty_rseg_tab.
    DATA lv_belnr TYPE c LENGTH 10.
    DATA lv_gjahr TYPE n LENGTH 4.
    DATA ls_item TYPE zif_rx_mm_reader=>ty_item.
    FIELD-SYMBOLS <ls_rseg> TYPE ty_rseg.

    lv_belnr = iv_belnr.
    lv_gjahr = iv_gjahr.
    SELECT buzei ebeln ebelp werks menge meins wrbtr spgrp spgrm spgrt spgrg spgrq spgrs spgrc spgrv
      FROM rseg
      INTO CORRESPONDING FIELDS OF TABLE lt_rseg
      WHERE belnr = lv_belnr
        AND gjahr = lv_gjahr
      ORDER BY buzei.                                     "#EC CI_SUBRC

    LOOP AT lt_rseg ASSIGNING <ls_rseg>.
      CLEAR ls_item.
      ls_item-buzei = <ls_rseg>-buzei.
      ls_item-ebeln = <ls_rseg>-ebeln.
      ls_item-ebelp = <ls_rseg>-ebelp.
      ls_item-werks = <ls_rseg>-werks.
      ls_item-menge = <ls_rseg>-menge.
      ls_item-meins = unit_out( <ls_rseg>-meins ).
      ls_item-wrbtr = <ls_rseg>-wrbtr.
      merge_blocks( EXPORTING is_rseg = <ls_rseg> CHANGING cs_blocks = ls_item-blocks ).
      APPEND ls_item TO rt_items.
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_rx_mm_reader~read_history.
    TYPES:
      BEGIN OF ty_ekbe,
        vgabe TYPE c LENGTH 1,
        shkzg TYPE c LENGTH 1,
        belnr TYPE c LENGTH 10,
        menge TYPE p LENGTH 13 DECIMALS 3,
        meins TYPE c LENGTH 3,
        budat TYPE d,
      END OF ty_ekbe.
    DATA lt_ekbe TYPE STANDARD TABLE OF ty_ekbe WITH DEFAULT KEY.
    DATA lv_ebeln TYPE c LENGTH 10.
    DATA lv_ebelp TYPE n LENGTH 5.
    DATA ls_line TYPE zif_rx_mm_reader=>ty_history_line.
    FIELD-SYMBOLS <ls_ekbe> TYPE ty_ekbe.

    lv_ebeln = iv_ebeln.
    lv_ebelp = iv_ebelp.
    " Só entradas de mercadoria (VGABE 1) e faturas (VGABE 2).
    SELECT vgabe shkzg belnr menge meins budat
      FROM ekbe
      INTO CORRESPONDING FIELDS OF TABLE lt_ekbe
      WHERE ebeln = lv_ebeln
        AND ebelp = lv_ebelp
        AND ( vgabe = '1' OR vgabe = '2' )
      ORDER BY budat belnr.                               "#EC CI_SUBRC

    LOOP AT lt_ekbe ASSIGNING <ls_ekbe>.
      CLEAR ls_line.
      ls_line-vgabe = <ls_ekbe>-vgabe.
      ls_line-shkzg = <ls_ekbe>-shkzg.
      ls_line-belnr = <ls_ekbe>-belnr.
      ls_line-menge = <ls_ekbe>-menge.
      ls_line-meins = unit_out( <ls_ekbe>-meins ).
      ls_line-budat = <ls_ekbe>-budat.
      APPEND ls_line TO rt_history.
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_rx_mm_reader~read_po_item.
    TYPES:
      BEGIN OF ty_ekpo,
        netpr TYPE p LENGTH 13 DECIMALS 2,
        peinh TYPE p LENGTH 5 DECIMALS 0,
        bprme TYPE c LENGTH 3,
      END OF ty_ekpo.
    DATA ls_ekpo TYPE ty_ekpo.
    DATA lv_ebeln TYPE c LENGTH 10.
    DATA lv_ebelp TYPE n LENGTH 5.
    DATA lv_waers TYPE c LENGTH 5.
    DATA lv_eindt TYPE d.
    DATA lt_eindt TYPE STANDARD TABLE OF d WITH DEFAULT KEY.

    lv_ebeln = iv_ebeln.
    lv_ebelp = iv_ebelp.
    SELECT SINGLE netpr peinh bprme
      FROM ekpo
      INTO CORRESPONDING FIELDS OF ls_ekpo
      WHERE ebeln = lv_ebeln
        AND ebelp = lv_ebelp.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    rs_po_item-found = abap_true.
    rs_po_item-ebeln = iv_ebeln.
    rs_po_item-ebelp = iv_ebelp.
    rs_po_item-netpr = ls_ekpo-netpr.
    rs_po_item-peinh = ls_ekpo-peinh.
    rs_po_item-bprme = unit_out( ls_ekpo-bprme ).

    " Moeda do pedido: cabeçalho EKKO.
    SELECT SINGLE waers FROM ekko INTO lv_waers WHERE ebeln = lv_ebeln.
    IF sy-subrc = 0.
      rs_po_item-waers = lv_waers.
    ENDIF.

    " Primeira data de remessa do item (EKET). Ordenada para pegar a mais antiga.
    SELECT eindt FROM eket INTO TABLE lt_eindt UP TO 1 ROWS
      WHERE ebeln = lv_ebeln
        AND ebelp = lv_ebelp
      ORDER BY eindt.                                     "#EC CI_SUBRC
    READ TABLE lt_eindt INDEX 1 INTO lv_eindt.
    IF sy-subrc = 0.
      rs_po_item-eindt = lv_eindt.
    ENDIF.
  ENDMETHOD.


  METHOD zif_rx_mm_reader~read_tolerance.
    DATA lv_bukrs TYPE c LENGTH 4.
    DATA lv_tolsl TYPE c LENGTH 2.
    DATA lv_proz1 TYPE p LENGTH 5 DECIMALS 2.

    lv_bukrs = iv_bukrs.
    lv_tolsl = iv_tolsl.
    " Tolerância por empresa e chave (PP = variação de preço). (validar: campos TOLSL e PROZ1 da T169G)
    SELECT SINGLE proz1 FROM t169g INTO lv_proz1
      WHERE bukrs = lv_bukrs
        AND tolsl = lv_tolsl.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    rs_tolerance-found = abap_true.
    rs_tolerance-bukrs = iv_bukrs.
    rs_tolerance-tolsl = iv_tolsl.
    rs_tolerance-proz1 = lv_proz1.
  ENDMETHOD.


  METHOD zif_rx_mm_reader~read_vendor_item.
    TYPES:
      BEGIN OF ty_bsik,
        zlspr TYPE c LENGTH 1,
        zfbdt TYPE d,
        zbd1t TYPE p LENGTH 3 DECIMALS 0,
        zbd2t TYPE p LENGTH 3 DECIMALS 0,
        zbd3t TYPE p LENGTH 3 DECIMALS 0,
      END OF ty_bsik.
    DATA ls_bsik TYPE ty_bsik.
    DATA lv_awkey TYPE c LENGTH 20.
    DATA lv_bukrs TYPE c LENGTH 4.
    DATA lv_lifnr TYPE c LENGTH 10.
    DATA lv_fi_belnr TYPE c LENGTH 10.
    DATA lv_fi_gjahr TYPE n LENGTH 4.
    DATA lv_days1 TYPE i.
    DATA lv_days2 TYPE i.
    DATA lv_days3 TYPE i.
    DATA lv_no_date TYPE d.

    lv_bukrs = iv_bukrs.
    lv_lifnr = iv_lifnr.
    " Documento FI da fatura: referência RMRP, chave = documento MM (10) + exercício (4). (validar)
    CONCATENATE iv_belnr iv_gjahr INTO lv_awkey.
    SELECT SINGLE belnr gjahr FROM bkpf INTO (lv_fi_belnr, lv_fi_gjahr)
      WHERE bukrs = lv_bukrs
        AND awtyp = 'RMRP'
        AND awkey = lv_awkey.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " Partida em aberto do fornecedor (a fatura já paga não está na BSIK).
    SELECT SINGLE zlspr zfbdt zbd1t zbd2t zbd3t
      FROM bsik
      INTO CORRESPONDING FIELDS OF ls_bsik
      WHERE bukrs = lv_bukrs
        AND lifnr = lv_lifnr
        AND belnr = lv_fi_belnr
        AND gjahr = lv_fi_gjahr.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    rs_vendor_item-found = abap_true.
    rs_vendor_item-zlspr = ls_bsik-zlspr.
    lv_days1 = ls_bsik-zbd1t.
    lv_days2 = ls_bsik-zbd2t.
    lv_days3 = ls_bsik-zbd3t.
    rs_vendor_item-due_date = due_date( iv_base     = ls_bsik-zfbdt
                                        iv_fallback = lv_no_date
                                        iv_days1    = lv_days1
                                        iv_days2    = lv_days2
                                        iv_days3    = lv_days3 ).
  ENDMETHOD.


  METHOD zif_rx_mm_reader~read_pending.
    TYPES:
      BEGIN OF ty_vendor,
        lifnr TYPE c LENGTH 10,
        name1 TYPE string,
      END OF ty_vendor.
    DATA lt_rbkp TYPE ty_rbkp_tab.
    DATA lt_rseg TYPE ty_rseg_tab.
    DATA lt_vendors TYPE STANDARD TABLE OF ty_vendor WITH DEFAULT KEY.
    DATA ls_vendor TYPE ty_vendor.
    DATA lt_parked TYPE ty_status_range.
    DATA ls_pending TYPE zif_rx_mm_reader=>ty_pending.
    FIELD-SYMBOLS <ls_rbkp> TYPE ty_rbkp.
    FIELD-SYMBOLS <ls_rseg> TYPE ty_rseg.
    FIELD-SYMBOLS <ls_vendor> TYPE ty_vendor.

    lt_rbkp = select_rbkp( iv_bukrs = iv_bukrs iv_state = iv_state iv_limit = iv_limit ).
    lt_parked = parked_statuses( ).

    LOOP AT lt_rbkp ASSIGNING <ls_rbkp>.
      CLEAR ls_pending.
      ls_pending-belnr = <ls_rbkp>-belnr.
      ls_pending-gjahr = <ls_rbkp>-gjahr.
      ls_pending-bukrs = <ls_rbkp>-bukrs.
      ls_pending-lifnr = <ls_rbkp>-lifnr.
      ls_pending-rmwwr = <ls_rbkp>-rmwwr.
      ls_pending-waers = <ls_rbkp>-waers.
      ls_pending-budat = <ls_rbkp>-budat.
      ls_pending-zlspr = <ls_rbkp>-zlspr.
      ls_pending-due_date = rbkp_due_date( <ls_rbkp> ).
      IF <ls_rbkp>-rbstat IN lt_parked.
        ls_pending-parked = abap_true.
      ENDIF.

      " Nome do fornecedor, lido uma vez por fornecedor.
      READ TABLE lt_vendors ASSIGNING <ls_vendor> WITH KEY lifnr = <ls_rbkp>-lifnr.
      IF sy-subrc <> 0.
        ls_vendor-lifnr = <ls_rbkp>-lifnr.
        ls_vendor-name1 = vendor_name( ls_vendor-lifnr ).
        APPEND ls_vendor TO lt_vendors.
        ls_pending-vendor_name = ls_vendor-name1.
      ELSE.
        ls_pending-vendor_name = <ls_vendor>-name1.
      ENDIF.

      " Itens da fatura pela chave (BELNR, GJAHR), uma leitura por fatura (no máximo IV_LIMIT).
      " Evita FOR ALL ENTRIES com lista grande. (validar desempenho)
      lt_rseg = select_rseg( iv_belnr = <ls_rbkp>-belnr iv_gjahr = <ls_rbkp>-gjahr ).

      " Motivos: um 'X' em qualquer item vale para a fatura; o pedido é o do primeiro item.
      LOOP AT lt_rseg ASSIGNING <ls_rseg>.
        IF ls_pending-ebeln IS INITIAL.
          ls_pending-ebeln = <ls_rseg>-ebeln.
        ENDIF.
        merge_blocks( EXPORTING is_rseg = <ls_rseg> CHANGING cs_blocks = ls_pending-blocks ).
      ENDLOOP.
      APPEND ls_pending TO rt_pending.
    ENDLOOP.
  ENDMETHOD.


  METHOD select_rbkp.
    DATA lt_parked TYPE ty_status_range.
    DATA lt_bukrs TYPE ty_bukrs_range.
    DATA ls_bukrs LIKE LINE OF lt_bukrs.
    DATA lv_limit TYPE i.

    lt_parked = parked_statuses( ).
    IF iv_bukrs IS NOT INITIAL.
      ls_bukrs-sign = 'I'.
      ls_bukrs-option = 'EQ'.
      ls_bukrs-low = iv_bukrs.
      APPEND ls_bukrs TO lt_bukrs.
    ENDIF.
    lv_limit = iv_limit.
    IF lv_limit <= 0.
      lv_limit = 5000.
    ENDIF.

    " Faturas não estornadas (STBLG vazio). Bloqueada = lançada com bloqueio de pagamento
    " (ZLSPR; o bloqueio por item também preenche o do cabeçalho, 'R'). (validar)
    CASE iv_state.
      WHEN 'PARKED'.
        SELECT belnr gjahr bukrs lifnr rmwwr waers budat bldat zfbdt zbd1t zbd2t zbd3t rbstat zlspr
          FROM rbkp UP TO lv_limit ROWS
          INTO CORRESPONDING FIELDS OF TABLE rt_rbkp
          WHERE bukrs IN lt_bukrs
            AND stblg = space
            AND rbstat IN lt_parked
          ORDER BY PRIMARY KEY.                           "#EC CI_SUBRC
      WHEN 'BLOCKED'.
        SELECT belnr gjahr bukrs lifnr rmwwr waers budat bldat zfbdt zbd1t zbd2t zbd3t rbstat zlspr
          FROM rbkp UP TO lv_limit ROWS
          INTO CORRESPONDING FIELDS OF TABLE rt_rbkp
          WHERE bukrs IN lt_bukrs
            AND stblg = space
            AND rbstat NOT IN lt_parked
            AND zlspr <> space
          ORDER BY PRIMARY KEY.                           "#EC CI_SUBRC
      WHEN OTHERS.
        SELECT belnr gjahr bukrs lifnr rmwwr waers budat bldat zfbdt zbd1t zbd2t zbd3t rbstat zlspr
          FROM rbkp UP TO lv_limit ROWS
          INTO CORRESPONDING FIELDS OF TABLE rt_rbkp
          WHERE bukrs IN lt_bukrs
            AND stblg = space
            AND ( rbstat IN lt_parked OR zlspr <> space )
          ORDER BY PRIMARY KEY.                           "#EC CI_SUBRC
    ENDCASE.
  ENDMETHOD.


  METHOD select_rseg.
    DATA lv_belnr TYPE c LENGTH 10.
    DATA lv_gjahr TYPE n LENGTH 4.

    lv_belnr = iv_belnr.
    lv_gjahr = iv_gjahr.
    SELECT belnr gjahr buzei ebeln spgrp spgrm spgrt spgrg spgrq spgrs spgrc spgrv
      FROM rseg INTO CORRESPONDING FIELDS OF TABLE rt_rseg
      WHERE belnr = lv_belnr
        AND gjahr = lv_gjahr
      ORDER BY buzei.                                     "#EC CI_SUBRC
  ENDMETHOD.


  METHOD merge_blocks.
    IF is_rseg-spgrp IS NOT INITIAL.
      cs_blocks-spgrp = 'X'.
    ENDIF.
    IF is_rseg-spgrm IS NOT INITIAL.
      cs_blocks-spgrm = 'X'.
    ENDIF.
    IF is_rseg-spgrt IS NOT INITIAL.
      cs_blocks-spgrt = 'X'.
    ENDIF.
    IF is_rseg-spgrg IS NOT INITIAL.
      cs_blocks-spgrg = 'X'.
    ENDIF.
    IF is_rseg-spgrq IS NOT INITIAL.
      cs_blocks-spgrq = 'X'.
    ENDIF.
    IF is_rseg-spgrs IS NOT INITIAL.
      cs_blocks-spgrs = 'X'.
    ENDIF.
    IF is_rseg-spgrc IS NOT INITIAL.
      cs_blocks-spgrc = 'X'.
    ENDIF.
    IF is_rseg-spgrv IS NOT INITIAL.
      cs_blocks-spgrv = 'X'.
    ENDIF.
  ENDMETHOD.


  METHOD rbkp_due_date.
    DATA lv_days1 TYPE i.
    DATA lv_days2 TYPE i.
    DATA lv_days3 TYPE i.

    lv_days1 = is_rbkp-zbd1t.
    lv_days2 = is_rbkp-zbd2t.
    lv_days3 = is_rbkp-zbd3t.
    rv_date = due_date( iv_base     = is_rbkp-zfbdt
                        iv_fallback = is_rbkp-bldat
                        iv_days1    = lv_days1
                        iv_days2    = lv_days2
                        iv_days3    = lv_days3 ).
  ENDMETHOD.


  METHOD zif_rx_mm_reader~is_authorized.
    DATA lv_bukrs TYPE c LENGTH 4.
    DATA lv_werks TYPE c LENGTH 4.

    lv_bukrs = iv_bukrs.
    AUTHORITY-CHECK OBJECT 'F_BKPF_BUK'
      ID 'BUKRS' FIELD lv_bukrs
      ID 'ACTVT' FIELD '03'.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    IF iv_werks IS NOT INITIAL.
      " Objeto e campos da verificação de faturas por centro. (validar: M_RECH_WRK, WERKS e ACTVT)
      lv_werks = iv_werks.
      AUTHORITY-CHECK OBJECT 'M_RECH_WRK'
        ID 'WERKS' FIELD lv_werks
        ID 'ACTVT' FIELD '03'.
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.
    ENDIF.
    rv_allowed = abap_true.
  ENDMETHOD.

ENDCLASS.
