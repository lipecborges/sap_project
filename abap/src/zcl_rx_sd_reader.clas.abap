"! Leitor real de vendas (SD): SELECTs nas tabelas SAP, somente leitura.
"! Isola as diferenças ECC × S/4HANA: os status do documento SD ficam na VBUK/VBUP
"! no ECC e na VBAK/VBAP/LIKP no S/4. Onde o campo ou a tabela muda por release, usa
"! SQL dinâmico, para a classe compilar nos dois sistemas.
"! Itens marcados com (validar) dependem de conferência num sistema real (V-SAP).
CLASS zcl_rx_sd_reader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_rx_sd_reader.

  PRIVATE SECTION.
    TYPES ty_line TYPE c LENGTH 72.
    TYPES ty_lines TYPE STANDARD TABLE OF ty_line WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_vbak,
        vbeln TYPE c LENGTH 10,
        vbtyp TYPE c LENGTH 1,
        auart TYPE c LENGTH 4,
        vkorg TYPE c LENGTH 4,
        vtweg TYPE c LENGTH 2,
        spart TYPE c LENGTH 2,
        kunnr TYPE c LENGTH 10,
        netwr TYPE p LENGTH 15 DECIMALS 2,
        waerk TYPE c LENGTH 5,
        erdat TYPE d,
        vdatu TYPE d,
        lifsk TYPE c LENGTH 2,
        faksk TYPE c LENGTH 2,
      END OF ty_vbak.

    " Linha da consulta de pedidos abertos: VBAK + status (VBUK no ECC, VBAK no S/4).
    TYPES:
      BEGIN OF ty_open,
        vbeln TYPE c LENGTH 10,
        vbtyp TYPE c LENGTH 1,
        auart TYPE c LENGTH 4,
        vkorg TYPE c LENGTH 4,
        vtweg TYPE c LENGTH 2,
        spart TYPE c LENGTH 2,
        kunnr TYPE c LENGTH 10,
        netwr TYPE p LENGTH 15 DECIMALS 2,
        waerk TYPE c LENGTH 5,
        erdat TYPE d,
        vdatu TYPE d,
        lifsk TYPE c LENGTH 2,
        faksk TYPE c LENGTH 2,
        cmgst TYPE c LENGTH 1,
        uvall TYPE c LENGTH 1,
        lfstk TYPE c LENGTH 1,
        fkstk TYPE c LENGTH 1,
      END OF ty_open,
      ty_opens TYPE STANDARD TABLE OF ty_open WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_status,
        cmgst TYPE c LENGTH 1,
        uvall TYPE c LENGTH 1,
        lfstk TYPE c LENGTH 1,
        fkstk TYPE c LENGTH 1,
      END OF ty_status.

    TYPES:
      BEGIN OF ty_doc,
        vbeln TYPE c LENGTH 10,
      END OF ty_doc,
      ty_docs TYPE STANDARD TABLE OF ty_doc WITH DEFAULT KEY.

    " Elo do fluxo de documentos (VBFA): anterior → subsequente.
    TYPES:
      BEGIN OF ty_link,
        vbelv TYPE c LENGTH 10,
        vbeln TYPE c LENGTH 10,
      END OF ty_link,
      ty_links TYPE STANDARD TABLE OF ty_link WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_goods_issue,
        vbeln TYPE c LENGTH 10,
        wbstk TYPE c LENGTH 1,
      END OF ty_goods_issue,
      ty_goods_issues TYPE STANDARD TABLE OF ty_goods_issue WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_customer,
        kunnr TYPE c LENGTH 10,
        name1 TYPE c LENGTH 35,
      END OF ty_customer,
      ty_customers TYPE STANDARD TABLE OF ty_customer WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_vbap,
        posnr TYPE c LENGTH 6,
        abgru TYPE c LENGTH 2,
        pstyv TYPE c LENGTH 4,
        faksp TYPE c LENGTH 2,
      END OF ty_vbap,
      ty_vbaps TYPE STANDARD TABLE OF ty_vbap WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_tvap,
        pstyv TYPE c LENGTH 4,
        fkrel TYPE c LENGTH 1,
      END OF ty_tvap,
      ty_tvaps TYPE STANDARD TABLE OF ty_tvap WITH DEFAULT KEY.

    TYPES:
      BEGIN OF ty_vbep,
        posnr TYPE c LENGTH 6,
        etenr TYPE c LENGTH 4,
        lifsp TYPE c LENGTH 2,
      END OF ty_vbep,
      ty_vbeps TYPE STANDARD TABLE OF ty_vbep WITH DEFAULT KEY.

    " Texto já lido (TVLST, TVFST, TVAGT), para não repetir o SELECT.
    TYPES:
      BEGIN OF ty_text,
        source TYPE c LENGTH 5,
        code   TYPE c LENGTH 2,
        text   TYPE c LENGTH 40,
      END OF ty_text,
      ty_texts TYPE STANDARD TABLE OF ty_text WITH DEFAULT KEY.

    " Faixa de valores para o WHERE ... IN. Usada no lugar de FOR ALL ENTRIES (o abaplint
    " do projeto reprova FAE); valores repetidos saem em CLOSE_RANGE.
    TYPES:
      BEGIN OF ty_range,
        sign   TYPE c LENGTH 1,
        option TYPE c LENGTH 2,
        low    TYPE c LENGTH 10,
        high   TYPE c LENGTH 10,
      END OF ty_range,
      ty_ranges TYPE STANDARD TABLE OF ty_range WITH DEFAULT KEY.

    CONSTANTS c_text_delivery_block TYPE c LENGTH 5 VALUE 'TVLST'.
    CONSTANTS c_text_billing_block TYPE c LENGTH 5 VALUE 'TVFST'.
    CONSTANTS c_text_rejection TYPE c LENGTH 5 VALUE 'TVAGT'.

    DATA mv_release_known TYPE abap_bool.
    DATA mv_s4 TYPE abap_bool.
    DATA mt_texts TYPE ty_texts.

    METHODS is_sales_org_allowed
      IMPORTING iv_vkorg          TYPE csequence
      RETURNING VALUE(rv_allowed) TYPE abap_bool.

    METHODS is_sales_area_allowed
      IMPORTING iv_vkorg          TYPE csequence
                iv_vtweg          TYPE csequence
                iv_spart          TYPE csequence
      RETURNING VALUE(rv_allowed) TYPE abap_bool.

    METHODS add_range
      IMPORTING iv_value TYPE csequence
      CHANGING  ct_range TYPE ty_ranges.

    "! Tira os valores repetidos da faixa.
    METHODS close_range
      CHANGING ct_range TYPE ty_ranges.

    METHODS read_text
      IMPORTING iv_source      TYPE csequence
                iv_code        TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

    METHODS read_status
      IMPORTING iv_vbeln         TYPE csequence
      RETURNING VALUE(rs_status) TYPE ty_status.

    METHODS read_customer_name
      IMPORTING iv_kunnr       TYPE csequence
      RETURNING VALUE(rv_name) TYPE string.

    "! Remessas (VBFA, categoria J) do pedido, sem repetição.
    METHODS read_delivery_links
      IMPORTING iv_vbeln        TYPE csequence
      RETURNING VALUE(rt_links) TYPE ty_links.

    "! WBSTK de cada remessa: VBUK no ECC, LIKP no S/4 (validar).
    METHODS read_goods_issue
      IMPORTING it_links              TYPE ty_links
      RETURNING VALUE(rt_goods_issue) TYPE ty_goods_issues.

    "! Faturas (VBFA, categoria M) do pedido ou das remessas, sem as estornadas.
    METHODS read_invoice_links
      IMPORTING iv_vbeln        TYPE csequence
                it_deliveries   TYPE ty_links
      RETURNING VALUE(rt_links) TYPE ty_links.

    METHODS read_field_text
      IMPORTING iv_table       TYPE csequence
                iv_field       TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

    METHODS open_orders_select
      IMPORTING iv_sales_org   TYPE csequence
                iv_max_rows    TYPE i
      RETURNING VALUE(rt_open) TYPE ty_opens.

    "! Converte as linhas lidas em cabeçalhos (com o nome dos clientes).
    METHODS open_orders_map
      IMPORTING it_open          TYPE ty_opens
      RETURNING VALUE(rt_orders) TYPE zif_rx_sd_reader=>ty_order_headers.

    "! Quantidade de remessas e primeira remessa sem saída de mercadoria.
    METHODS open_orders_delivery
      CHANGING ct_orders TYPE zif_rx_sd_reader=>ty_order_headers.

    "! Bloqueios de divisão (VBEP) e de item (VBAP).
    METHODS open_orders_blocks
      CHANGING ct_orders TYPE zif_rx_sd_reader=>ty_order_headers.

ENDCLASS.



CLASS zcl_rx_sd_reader IMPLEMENTATION.

  METHOD zif_rx_sd_reader~is_s4.
    IF mv_release_known = abap_false.
      mv_s4 = zcl_rx_system_info=>is_s4( ).
      mv_release_known = abap_true.
    ENDIF.
    rv_s4 = mv_s4.
  ENDMETHOD.


  METHOD zif_rx_sd_reader~get_header.
    DATA lv_vbeln TYPE c LENGTH 10.
    DATA ls_vbak TYPE ty_vbak.
    DATA ls_status TYPE ty_status.

    lv_vbeln = iv_vbeln.
    SELECT SINGLE vbeln vbtyp auart vkorg vtweg spart kunnr netwr waerk erdat vdatu lifsk faksk
      FROM vbak INTO CORRESPONDING FIELDS OF ls_vbak
      WHERE vbeln = lv_vbeln.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    rs_header-exists = abap_true.
    rs_header-vbeln = ls_vbak-vbeln.
    rs_header-vbtyp = ls_vbak-vbtyp.
    rs_header-auart = ls_vbak-auart.
    rs_header-vkorg = ls_vbak-vkorg.
    rs_header-vtweg = ls_vbak-vtweg.
    rs_header-spart = ls_vbak-spart.
    rs_header-kunnr = ls_vbak-kunnr.
    rs_header-customer_name = read_customer_name( ls_vbak-kunnr ).
    rs_header-netwr = ls_vbak-netwr.
    rs_header-waerk = ls_vbak-waerk.
    rs_header-erdat = ls_vbak-erdat.
    rs_header-vdatu = ls_vbak-vdatu.
    rs_header-delivery_block_text = read_text( iv_source = c_text_delivery_block iv_code = ls_vbak-lifsk ).

    SELECT COUNT(*) FROM vbap INTO rs_header-item_count WHERE vbeln = lv_vbeln.
    IF sy-subrc <> 0.
      rs_header-item_count = 0.
    ENDIF.

    ls_status = read_status( lv_vbeln ).
    rs_header-state-credit_status = ls_status-cmgst.
    rs_header-state-incompletion_status = ls_status-uvall.
    rs_header-state-delivery_status = ls_status-lfstk.
    rs_header-state-billing_status = ls_status-fkstk.
    rs_header-state-delivery_block = ls_vbak-lifsk.
    rs_header-state-billing_block = ls_vbak-faksk.
    rs_header-state-billing_block_text = read_text( iv_source = c_text_billing_block iv_code = ls_vbak-faksk ).
  ENDMETHOD.


  METHOD zif_rx_sd_reader~get_items.
    DATA lv_vbeln TYPE c LENGTH 10.
    DATA lt_vbap TYPE ty_vbaps.
    DATA lt_tvap TYPE ty_tvaps.
    DATA lt_vbep TYPE ty_vbeps.
    DATA lt_categories TYPE ty_ranges.
    DATA ls_item TYPE zif_rx_sd_reader=>ty_item.
    DATA ls_tvap TYPE ty_tvap.
    DATA ls_vbep TYPE ty_vbep.
    FIELD-SYMBOLS <ls_vbap> TYPE ty_vbap.

    lv_vbeln = iv_vbeln.
    SELECT posnr abgru pstyv faksp FROM vbap
      INTO CORRESPONDING FIELDS OF TABLE lt_vbap UP TO 1000 ROWS
      WHERE vbeln = lv_vbeln
      ORDER BY posnr.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " Relevância de faturamento por categoria de item (TVAP-FKREL). Itens de texto também
    " aparecem sem FKREL; se virar ruído, filtrar por categoria (validar).
    LOOP AT lt_vbap ASSIGNING <ls_vbap>.
      add_range( EXPORTING iv_value = <ls_vbap>-pstyv CHANGING ct_range = lt_categories ).
    ENDLOOP.
    " Faixa vazia selecionaria a tabela inteira: só lê se houver categoria.
    IF lt_categories IS NOT INITIAL.
      close_range( CHANGING ct_range = lt_categories ).
      SELECT pstyv fkrel FROM tvap
        INTO CORRESPONDING FIELDS OF TABLE lt_tvap
        WHERE pstyv IN lt_categories
        ORDER BY PRIMARY KEY.
      IF sy-subrc <> 0.
        CLEAR lt_tvap.
      ENDIF.
    ENDIF.

    " Só as divisões bloqueadas interessam; a primeira de cada item basta.
    SELECT posnr etenr lifsp FROM vbep
      INTO CORRESPONDING FIELDS OF TABLE lt_vbep UP TO 5000 ROWS
      WHERE vbeln = lv_vbeln AND lifsp <> ' '
      ORDER BY posnr etenr.
    IF sy-subrc <> 0.
      CLEAR lt_vbep.
    ENDIF.

    LOOP AT lt_vbap ASSIGNING <ls_vbap>.
      CLEAR ls_item.
      ls_item-posnr = <ls_vbap>-posnr.
      ls_item-rejection_reason = <ls_vbap>-abgru.
      IF <ls_vbap>-abgru IS NOT INITIAL.
        ls_item-rejection_text = read_text( iv_source = c_text_rejection iv_code = <ls_vbap>-abgru ).
      ENDIF.
      ls_item-item_category = <ls_vbap>-pstyv.
      READ TABLE lt_tvap INTO ls_tvap WITH KEY pstyv = <ls_vbap>-pstyv.
      IF sy-subrc = 0 AND ls_tvap-fkrel IS NOT INITIAL.
        ls_item-billing_relevant = abap_true.
      ENDIF.
      READ TABLE lt_vbep INTO ls_vbep WITH KEY posnr = <ls_vbap>-posnr.
      IF sy-subrc = 0.
        ls_item-schedule_block = ls_vbep-lifsp.
        ls_item-schedule_block_text = read_text( iv_source = c_text_delivery_block iv_code = ls_vbep-lifsp ).
      ENDIF.
      ls_item-billing_block = <ls_vbap>-faksp.
      IF <ls_vbap>-faksp IS NOT INITIAL.
        ls_item-billing_block_text = read_text( iv_source = c_text_billing_block iv_code = <ls_vbap>-faksp ).
      ENDIF.
      APPEND ls_item TO rt_items.
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_rx_sd_reader~get_missing_fields.
    DATA lv_vbeln TYPE c LENGTH 10.
    FIELD-SYMBOLS <ls_missing> TYPE zif_rx_sd_reader=>ty_missing_field.

    lv_vbeln = iv_vbeln.
    SELECT posnr tbnam fdnam FROM vbuv
      INTO CORRESPONDING FIELDS OF TABLE rt_missing UP TO 200 ROWS
      WHERE vbeln = lv_vbeln
      ORDER BY posnr tbnam fdnam.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    LOOP AT rt_missing ASSIGNING <ls_missing>.
      <ls_missing>-field_text = read_field_text( iv_table = <ls_missing>-table_name
                                                 iv_field = <ls_missing>-field_name ).
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_rx_sd_reader~get_followups.
    DATA lt_deliveries TYPE ty_links.
    DATA lt_invoices TYPE ty_links.
    DATA lt_goods_issue TYPE ty_goods_issues.
    DATA ls_followup TYPE zif_rx_sd_reader=>ty_followup.
    DATA ls_goods_issue TYPE ty_goods_issue.
    FIELD-SYMBOLS <ls_link> TYPE ty_link.

    lt_deliveries = read_delivery_links( iv_vbeln ).
    lt_goods_issue = read_goods_issue( lt_deliveries ).
    LOOP AT lt_deliveries ASSIGNING <ls_link>.
      CLEAR ls_followup.
      ls_followup-category = zif_rx_sd_reader=>c_followup-delivery.
      ls_followup-doc_number = <ls_link>-vbeln.
      ls_followup-predecessor = <ls_link>-vbelv.
      READ TABLE lt_goods_issue INTO ls_goods_issue WITH KEY vbeln = <ls_link>-vbeln.
      IF sy-subrc = 0.
        ls_followup-goods_issue_status = ls_goods_issue-wbstk.
      ENDIF.
      APPEND ls_followup TO rt_followups.
    ENDLOOP.

    lt_invoices = read_invoice_links( iv_vbeln = iv_vbeln it_deliveries = lt_deliveries ).
    LOOP AT lt_invoices ASSIGNING <ls_link>.
      CLEAR ls_followup.
      ls_followup-category = zif_rx_sd_reader=>c_followup-invoice.
      ls_followup-doc_number = <ls_link>-vbeln.
      ls_followup-predecessor = <ls_link>-vbelv.
      APPEND ls_followup TO rt_followups.
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_rx_sd_reader~is_billing_due.
    DATA lt_docs TYPE ty_ranges.
    DATA lt_found TYPE ty_docs.
    FIELD-SYMBOLS <ls_followup> TYPE zif_rx_sd_reader=>ty_followup.

    " A lista de faturamento (VKDFS) é indexada pelo pedido ou pela remessa (validar no S/4).
    add_range( EXPORTING iv_value = iv_vbeln CHANGING ct_range = lt_docs ).
    LOOP AT it_followups ASSIGNING <ls_followup>
        WHERE category = zif_rx_sd_reader=>c_followup-delivery.
      add_range( EXPORTING iv_value = <ls_followup>-doc_number CHANGING ct_range = lt_docs ).
    ENDLOOP.
    close_range( CHANGING ct_range = lt_docs ).

    SELECT vbeln FROM vkdfs INTO CORRESPONDING FIELDS OF TABLE lt_found UP TO 1 ROWS
      WHERE vbeln IN lt_docs
      ORDER BY PRIMARY KEY.
    IF sy-subrc = 0.
      rv_due = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD zif_rx_sd_reader~get_open_orders.
    DATA lt_open TYPE ty_opens.
    DATA lv_first_extra TYPE i.

    CLEAR et_orders.
    ev_truncated = abap_false.

    " Lê um a mais para saber se a lista foi cortada.
    lt_open = open_orders_select( iv_sales_org = iv_sales_org iv_max_rows = iv_max_rows ).
    IF lines( lt_open ) > iv_max_rows.
      ev_truncated = abap_true.
      lv_first_extra = iv_max_rows + 1.
      DELETE lt_open FROM lv_first_extra.
    ENDIF.
    IF lt_open IS INITIAL.
      RETURN.
    ENDIF.

    et_orders = open_orders_map( lt_open ).
    open_orders_delivery( CHANGING ct_orders = et_orders ).
    open_orders_blocks( CHANGING ct_orders = et_orders ).
  ENDMETHOD.


  METHOD zif_rx_sd_reader~is_authorized.
    DATA lv_vkorg TYPE c LENGTH 4.
    DATA lv_vtweg TYPE c LENGTH 2.
    DATA lv_spart TYPE c LENGTH 2.
    DATA lv_auart TYPE c LENGTH 4.

    lv_vkorg = iv_vkorg.
    lv_vtweg = iv_vtweg.
    lv_spart = iv_spart.
    lv_auart = iv_auart.

    " Canal e setor vazios: só a organização de vendas é verificada.
    IF lv_vtweg IS INITIAL OR lv_spart IS INITIAL.
      rv_allowed = is_sales_org_allowed( lv_vkorg ).
    ELSE.
      rv_allowed = is_sales_area_allowed( iv_vkorg = lv_vkorg iv_vtweg = lv_vtweg iv_spart = lv_spart ).
    ENDIF.
    IF rv_allowed = abap_false OR lv_auart IS INITIAL.
      RETURN.
    ENDIF.

    " Tipo de documento. Campos do V_VBAK_AAT: AUART e ACTVT (validar).
    rv_allowed = abap_false.
    AUTHORITY-CHECK OBJECT 'V_VBAK_AAT'
      ID 'AUART' FIELD lv_auart
      ID 'ACTVT' FIELD '03'.
    IF sy-subrc = 0.
      rv_allowed = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD is_sales_org_allowed.
    DATA lv_vkorg TYPE c LENGTH 4.

    lv_vkorg = iv_vkorg.
    AUTHORITY-CHECK OBJECT 'V_VBAK_VKO'
      ID 'VKORG' FIELD lv_vkorg
      ID 'VTWEG' DUMMY
      ID 'SPART' DUMMY
      ID 'ACTVT' FIELD '03'.
    IF sy-subrc = 0.
      rv_allowed = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD is_sales_area_allowed.
    DATA lv_vkorg TYPE c LENGTH 4.
    DATA lv_vtweg TYPE c LENGTH 2.
    DATA lv_spart TYPE c LENGTH 2.

    lv_vkorg = iv_vkorg.
    lv_vtweg = iv_vtweg.
    lv_spart = iv_spart.
    AUTHORITY-CHECK OBJECT 'V_VBAK_VKO'
      ID 'VKORG' FIELD lv_vkorg
      ID 'VTWEG' FIELD lv_vtweg
      ID 'SPART' FIELD lv_spart
      ID 'ACTVT' FIELD '03'.
    IF sy-subrc = 0.
      rv_allowed = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD add_range.
    DATA ls_range TYPE ty_range.

    IF iv_value IS INITIAL.
      RETURN.
    ENDIF.
    ls_range-sign = 'I'.
    ls_range-option = 'EQ'.
    ls_range-low = iv_value.
    APPEND ls_range TO ct_range.
  ENDMETHOD.


  METHOD close_range.
    SORT ct_range BY low.
    DELETE ADJACENT DUPLICATES FROM ct_range COMPARING low.
  ENDMETHOD.


  METHOD read_text.
    DATA ls_text TYPE ty_text.
    DATA lv_source TYPE c LENGTH 5.
    DATA lv_code TYPE c LENGTH 2.
    DATA lv_vtext TYPE c LENGTH 20.
    DATA lv_bezei TYPE c LENGTH 40.

    lv_source = iv_source.
    lv_code = iv_code.
    IF lv_code IS INITIAL.
      RETURN.
    ENDIF.
    READ TABLE mt_texts INTO ls_text WITH KEY source = lv_source code = lv_code.
    IF sy-subrc = 0.
      rv_text = ls_text-text.
      RETURN.
    ENDIF.

    " Textos no idioma do usuário (sem texto no idioma, fica vazio).
    CASE lv_source.
      WHEN c_text_delivery_block.
        SELECT SINGLE vtext FROM tvlst INTO lv_vtext WHERE spras = sy-langu AND lifsp = lv_code.
        IF sy-subrc = 0.
          ls_text-text = lv_vtext.
        ENDIF.
      WHEN c_text_billing_block.
        SELECT SINGLE vtext FROM tvfst INTO lv_vtext WHERE spras = sy-langu AND faksp = lv_code.
        IF sy-subrc = 0.
          ls_text-text = lv_vtext.
        ENDIF.
      WHEN c_text_rejection.
        SELECT SINGLE bezei FROM tvagt INTO lv_bezei WHERE spras = sy-langu AND abgru = lv_code.
        IF sy-subrc = 0.
          ls_text-text = lv_bezei.
        ENDIF.
    ENDCASE.
    ls_text-source = lv_source.
    ls_text-code = lv_code.
    APPEND ls_text TO mt_texts.
    rv_text = ls_text-text.
  ENDMETHOD.


  METHOD read_status.
    DATA lt_fields TYPE ty_lines.
    DATA lt_where TYPE ty_lines.
    DATA lv_table TYPE c LENGTH 5.
    DATA lv_vbeln TYPE c LENGTH 10.
    DATA lv_field TYPE ty_line.

    lv_vbeln = iv_vbeln.
    " ECC: status na VBUK. S/4: os mesmos campos foram para a VBAK (validar).
    IF zif_rx_sd_reader~is_s4( ) = abap_true.
      lv_table = 'VBAK'.
    ELSE.
      lv_table = 'VBUK'.
    ENDIF.
    lv_field = 'CMGST'.
    APPEND lv_field TO lt_fields.
    lv_field = 'UVALL'.
    APPEND lv_field TO lt_fields.
    lv_field = 'LFSTK'.
    APPEND lv_field TO lt_fields.
    lv_field = 'FKSTK'.
    APPEND lv_field TO lt_fields.
    lv_field = 'VBELN = LV_VBELN'.
    APPEND lv_field TO lt_where.

    SELECT SINGLE (lt_fields) FROM (lv_table) INTO CORRESPONDING FIELDS OF rs_status
      WHERE (lt_where).
    IF sy-subrc <> 0.
      CLEAR rs_status.
    ENDIF.
  ENDMETHOD.


  METHOD read_customer_name.
    DATA lv_kunnr TYPE c LENGTH 10.
    DATA lv_name TYPE c LENGTH 35.

    lv_kunnr = iv_kunnr.
    SELECT SINGLE name1 FROM kna1 INTO lv_name WHERE kunnr = lv_kunnr.
    IF sy-subrc = 0.
      rv_name = lv_name.
    ENDIF.
  ENDMETHOD.


  METHOD read_delivery_links.
    DATA lv_vbeln TYPE c LENGTH 10.

    lv_vbeln = iv_vbeln.
    SELECT vbelv vbeln FROM vbfa
      INTO CORRESPONDING FIELDS OF TABLE rt_links UP TO 1000 ROWS
      WHERE vbelv = lv_vbeln AND vbtyp_n = zif_rx_sd_reader=>c_followup-delivery
      ORDER BY vbeln.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    " O VBFA tem uma linha por item: uma remessa aparece várias vezes.
    DELETE ADJACENT DUPLICATES FROM rt_links COMPARING vbeln.
  ENDMETHOD.


  METHOD read_goods_issue.
    DATA lv_table TYPE c LENGTH 5.
    DATA lt_fields TYPE ty_lines.
    DATA lv_field TYPE ty_line.
    DATA lt_docs TYPE ty_ranges.
    FIELD-SYMBOLS <ls_link> TYPE ty_link.

    LOOP AT it_links ASSIGNING <ls_link>.
      add_range( EXPORTING iv_value = <ls_link>-vbeln CHANGING ct_range = lt_docs ).
    ENDLOOP.
    IF lt_docs IS INITIAL.
      RETURN.
    ENDIF.
    close_range( CHANGING ct_range = lt_docs ).

    " ECC: WBSTK na VBUK. S/4: WBSTK na LIKP (validar).
    IF zif_rx_sd_reader~is_s4( ) = abap_true.
      lv_table = 'LIKP'.
    ELSE.
      lv_table = 'VBUK'.
    ENDIF.
    lv_field = 'VBELN'.
    APPEND lv_field TO lt_fields.
    lv_field = 'WBSTK'.
    APPEND lv_field TO lt_fields.

    SELECT (lt_fields) FROM (lv_table) INTO CORRESPONDING FIELDS OF TABLE rt_goods_issue
      WHERE vbeln IN lt_docs
      ORDER BY PRIMARY KEY.
    IF sy-subrc <> 0.
      CLEAR rt_goods_issue.
    ENDIF.
  ENDMETHOD.


  METHOD read_invoice_links.
    DATA lv_vbeln TYPE c LENGTH 10.
    DATA lt_direct TYPE ty_links.
    DATA lt_deliveries TYPE ty_ranges.
    DATA lt_candidates TYPE ty_ranges.
    DATA lt_cancelled TYPE ty_docs.
    DATA ls_doc TYPE ty_doc.
    FIELD-SYMBOLS <ls_link> TYPE ty_link.

    lv_vbeln = iv_vbeln.
    " Faturas das remessas do pedido (têm preferência: o anterior é a remessa)…
    LOOP AT it_deliveries ASSIGNING <ls_link>.
      add_range( EXPORTING iv_value = <ls_link>-vbeln CHANGING ct_range = lt_deliveries ).
    ENDLOOP.
    IF lt_deliveries IS NOT INITIAL.
      close_range( CHANGING ct_range = lt_deliveries ).
      SELECT vbelv vbeln FROM vbfa
        INTO CORRESPONDING FIELDS OF TABLE rt_links
        WHERE vbelv IN lt_deliveries AND vbtyp_n = zif_rx_sd_reader=>c_followup-invoice
        ORDER BY PRIMARY KEY.
      IF sy-subrc <> 0.
        CLEAR rt_links.
      ENDIF.
    ENDIF.
    " …e as geradas direto do pedido.
    SELECT vbelv vbeln FROM vbfa
      INTO CORRESPONDING FIELDS OF TABLE lt_direct UP TO 1000 ROWS
      WHERE vbelv = lv_vbeln AND vbtyp_n = zif_rx_sd_reader=>c_followup-invoice
      ORDER BY vbeln.
    IF sy-subrc = 0.
      APPEND LINES OF lt_direct TO rt_links.
    ENDIF.
    " O VBFA tem uma linha por item: a mesma fatura aparece várias vezes.
    SORT rt_links STABLE BY vbeln.
    DELETE ADJACENT DUPLICATES FROM rt_links COMPARING vbeln.

    " Faturas estornadas (VBRK-FKSTO = X) não contam como faturamento (validar o campo).
    LOOP AT rt_links ASSIGNING <ls_link>.
      add_range( EXPORTING iv_value = <ls_link>-vbeln CHANGING ct_range = lt_candidates ).
    ENDLOOP.
    IF lt_candidates IS NOT INITIAL.
      close_range( CHANGING ct_range = lt_candidates ).
      SELECT vbeln FROM vbrk INTO CORRESPONDING FIELDS OF TABLE lt_cancelled
        WHERE vbeln IN lt_candidates AND fksto = 'X'
        ORDER BY PRIMARY KEY.
      IF sy-subrc <> 0.
        CLEAR lt_cancelled.
      ENDIF.
    ENDIF.
    LOOP AT lt_cancelled INTO ls_doc.
      DELETE rt_links WHERE vbeln = ls_doc-vbeln.
    ENDLOOP.
  ENDMETHOD.


  METHOD read_field_text.
    DATA lo_struct TYPE REF TO cl_abap_structdescr.
    DATA lt_fields TYPE ddfields.
    DATA lv_table TYPE string.
    FIELD-SYMBOLS <ls_field> TYPE dfies.

    " Descrição do campo no dicionário (VBUV-TBNAM/FDNAM), no idioma do usuário. Sem ela,
    " vale o nome do campo. Tabelas de partner (VBPA) podem vir com outro nome (validar).
    rv_text = iv_field.
    lv_table = iv_table.
    TRY.
        lo_struct ?= cl_abap_typedescr=>describe_by_name( lv_table ).
        lt_fields = lo_struct->get_ddic_field_list( ).
      CATCH cx_root.
        RETURN.
    ENDTRY.
    LOOP AT lt_fields ASSIGNING <ls_field> WHERE fieldname = iv_field.
      IF <ls_field>-fieldtext IS NOT INITIAL.
        rv_text = <ls_field>-fieldtext.
      ENDIF.
      RETURN.
    ENDLOOP.
  ENDMETHOD.


  METHOD open_orders_select.
    DATA lv_from TYPE string.
    DATA lv_alias TYPE c LENGTH 1.
    DATA lv_vkorg TYPE c LENGTH 4.
    DATA lv_limit TYPE i.
    DATA lt_fields TYPE ty_lines.
    DATA lt_where TYPE ty_lines.
    DATA lt_order TYPE ty_lines.
    DATA lv_line TYPE ty_line.
    DATA lv_fkstk TYPE ty_line.

    " ECC: VBAK + VBUK (status). S/4: os status estão na própria VBAK (validar).
    " Join dinâmico no FROM e ORDER BY dinâmico: conferir no ECC 7.00 (validar).
    " Pedido aberto = categoria C com FKSTK A/B; pedidos 100% recusados têm FKSTK vazio (validar).
    IF zif_rx_sd_reader~is_s4( ) = abap_true.
      lv_from = 'VBAK AS a'.
      lv_alias = 'a'.
    ELSE.
      lv_from = 'VBAK AS a INNER JOIN VBUK AS b ON b~vbeln = a~vbeln'.
      lv_alias = 'b'.
    ENDIF.

    lv_line = 'a~vbeln a~vbtyp a~auart a~vkorg a~vtweg a~spart a~kunnr'.
    APPEND lv_line TO lt_fields.
    lv_line = 'a~netwr a~waerk a~erdat a~vdatu a~lifsk a~faksk'.
    APPEND lv_line TO lt_fields.
    " Os quatro campos de status saem do alias certo (b = VBUK no ECC, a = VBAK no S/4).
    CONCATENATE lv_alias '~cmgst' INTO lv_line.
    APPEND lv_line TO lt_fields.
    CONCATENATE lv_alias '~uvall' INTO lv_line.
    APPEND lv_line TO lt_fields.
    CONCATENATE lv_alias '~lfstk' INTO lv_line.
    APPEND lv_line TO lt_fields.
    CONCATENATE lv_alias '~fkstk' INTO lv_fkstk.
    APPEND lv_fkstk TO lt_fields.

    " Pedidos (categoria C) com faturamento pendente (A ou B).
    lv_line = 'a~vbtyp = ''C'' AND'.
    APPEND lv_line TO lt_where.
    CONCATENATE '(' lv_fkstk '= ''A'' OR' lv_fkstk '= ''B'' )'
      INTO lv_line SEPARATED BY space.
    APPEND lv_line TO lt_where.
    lv_vkorg = iv_sales_org.
    IF lv_vkorg IS NOT INITIAL.
      lv_line = 'AND a~vkorg = lv_vkorg'.
      APPEND lv_line TO lt_where.
    ENDIF.

    lv_line = 'a~erdat'.
    APPEND lv_line TO lt_order.
    lv_line = 'a~vbeln'.
    APPEND lv_line TO lt_order.

    lv_limit = iv_max_rows + 1.
    SELECT (lt_fields) FROM (lv_from) INTO CORRESPONDING FIELDS OF TABLE rt_open UP TO lv_limit ROWS
      WHERE (lt_where)
      ORDER BY (lt_order).
    IF sy-subrc <> 0.
      CLEAR rt_open.
    ENDIF.
  ENDMETHOD.


  METHOD open_orders_map.
    DATA lt_customers TYPE ty_customers.
    DATA ls_customer TYPE ty_customer.
    DATA ls_header TYPE zif_rx_sd_reader=>ty_order_header.
    DATA lt_kunnr TYPE ty_ranges.
    FIELD-SYMBOLS <ls_open> TYPE ty_open.

    " Nomes dos clientes de uma vez só.
    LOOP AT it_open ASSIGNING <ls_open>.
      add_range( EXPORTING iv_value = <ls_open>-kunnr CHANGING ct_range = lt_kunnr ).
    ENDLOOP.
    " Faixa vazia selecionaria a tabela inteira: só lê se houver cliente.
    IF lt_kunnr IS NOT INITIAL.
      close_range( CHANGING ct_range = lt_kunnr ).
      SELECT kunnr name1 FROM kna1 INTO CORRESPONDING FIELDS OF TABLE lt_customers
        WHERE kunnr IN lt_kunnr
        ORDER BY PRIMARY KEY.
      IF sy-subrc <> 0.
        CLEAR lt_customers.
      ENDIF.
    ENDIF.

    LOOP AT it_open ASSIGNING <ls_open>.
      CLEAR ls_header.
      ls_header-exists = abap_true.
      ls_header-vbeln = <ls_open>-vbeln.
      ls_header-vbtyp = <ls_open>-vbtyp.
      ls_header-auart = <ls_open>-auart.
      ls_header-vkorg = <ls_open>-vkorg.
      ls_header-vtweg = <ls_open>-vtweg.
      ls_header-spart = <ls_open>-spart.
      ls_header-kunnr = <ls_open>-kunnr.
      READ TABLE lt_customers INTO ls_customer WITH KEY kunnr = <ls_open>-kunnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_header-customer_name = ls_customer-name1.
      ENDIF.
      ls_header-netwr = <ls_open>-netwr.
      ls_header-waerk = <ls_open>-waerk.
      ls_header-erdat = <ls_open>-erdat.
      ls_header-vdatu = <ls_open>-vdatu.
      ls_header-state-credit_status = <ls_open>-cmgst.
      ls_header-state-incompletion_status = <ls_open>-uvall.
      ls_header-state-delivery_status = <ls_open>-lfstk.
      ls_header-state-billing_status = <ls_open>-fkstk.
      ls_header-state-delivery_block = <ls_open>-lifsk.
      ls_header-state-billing_block = <ls_open>-faksk.
      ls_header-state-billing_block_text = read_text( iv_source = c_text_billing_block
                                                      iv_code   = <ls_open>-faksk ).
      APPEND ls_header TO rt_orders.
    ENDLOOP.
  ENDMETHOD.


  METHOD open_orders_delivery.
    DATA lt_links TYPE ty_links.
    DATA lt_goods_issue TYPE ty_goods_issues.
    DATA ls_goods_issue TYPE ty_goods_issue.
    DATA lv_index TYPE i.
    DATA lt_orders TYPE ty_ranges.
    FIELD-SYMBOLS <ls_order> TYPE zif_rx_sd_reader=>ty_order_header.
    FIELD-SYMBOLS <ls_link> TYPE ty_link.

    LOOP AT ct_orders ASSIGNING <ls_order>.
      add_range( EXPORTING iv_value = <ls_order>-vbeln CHANGING ct_range = lt_orders ).
    ENDLOOP.
    IF lt_orders IS INITIAL.
      RETURN.
    ENDIF.
    close_range( CHANGING ct_range = lt_orders ).
    " Remessas de todos os pedidos de uma vez (VBFA categoria J) e o WBSTK delas.
    SELECT vbelv vbeln FROM vbfa INTO CORRESPONDING FIELDS OF TABLE lt_links
      WHERE vbelv IN lt_orders AND vbtyp_n = zif_rx_sd_reader=>c_followup-delivery
      ORDER BY PRIMARY KEY.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    SORT lt_links BY vbelv vbeln.
    DELETE ADJACENT DUPLICATES FROM lt_links COMPARING vbelv vbeln.
    lt_goods_issue = read_goods_issue( lt_links ).
    SORT lt_goods_issue BY vbeln.

    LOOP AT ct_orders ASSIGNING <ls_order>.
      READ TABLE lt_links TRANSPORTING NO FIELDS WITH KEY vbelv = <ls_order>-vbeln BINARY SEARCH.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      lv_index = sy-tabix.
      LOOP AT lt_links ASSIGNING <ls_link> FROM lv_index.
        IF <ls_link>-vbelv <> <ls_order>-vbeln.
          EXIT.
        ENDIF.
        <ls_order>-state-delivery_count = <ls_order>-state-delivery_count + 1.
        IF <ls_order>-state-pending_delivery IS NOT INITIAL.
          CONTINUE.
        ENDIF.
        READ TABLE lt_goods_issue INTO ls_goods_issue WITH KEY vbeln = <ls_link>-vbeln BINARY SEARCH.
        IF sy-subrc = 0 AND ( ls_goods_issue-wbstk = 'A' OR ls_goods_issue-wbstk = 'B' ).
          <ls_order>-state-pending_delivery = <ls_link>-vbeln.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD open_orders_blocks.
    DATA lt_schedule TYPE ty_docs.
    DATA lt_items TYPE ty_docs.
    DATA lt_orders TYPE ty_ranges.
    FIELD-SYMBOLS <ls_order> TYPE zif_rx_sd_reader=>ty_order_header.

    LOOP AT ct_orders ASSIGNING <ls_order>.
      add_range( EXPORTING iv_value = <ls_order>-vbeln CHANGING ct_range = lt_orders ).
    ENDLOOP.
    IF lt_orders IS INITIAL.
      RETURN.
    ENDIF.
    close_range( CHANGING ct_range = lt_orders ).
    " Bloqueio de remessa em alguma divisão (VBEP-LIFSP)…
    SELECT vbeln FROM vbep INTO CORRESPONDING FIELDS OF TABLE lt_schedule
      WHERE vbeln IN lt_orders AND lifsp <> ' '
      ORDER BY vbeln.
    IF sy-subrc <> 0.
      CLEAR lt_schedule.
    ENDIF.
    " …e bloqueio de faturamento em algum item (VBAP-FAKSP).
    SELECT vbeln FROM vbap INTO CORRESPONDING FIELDS OF TABLE lt_items
      WHERE vbeln IN lt_orders AND faksp <> ' '
      ORDER BY vbeln.
    IF sy-subrc <> 0.
      CLEAR lt_items.
    ENDIF.
    SORT lt_schedule BY vbeln.
    SORT lt_items BY vbeln.

    LOOP AT ct_orders ASSIGNING <ls_order>.
      READ TABLE lt_schedule TRANSPORTING NO FIELDS WITH KEY vbeln = <ls_order>-vbeln BINARY SEARCH.
      IF sy-subrc = 0.
        <ls_order>-state-schedule_blocked = abap_true.
      ENDIF.
      READ TABLE lt_items TRANSPORTING NO FIELDS WITH KEY vbeln = <ls_order>-vbeln BINARY SEARCH.
      IF sy-subrc = 0.
        <ls_order>-state-item_billing_blocked = abap_true.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
