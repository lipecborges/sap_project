"! MM-02: Fatura de fornecedor bloqueada para pagamento.
"! Só lógica: decide os achados a partir dos dados do leitor (ZIF_RX_MM_READER).
"! Ordem dos achados: bloqueio do cabeçalho; por item, cada motivo de bloqueio seguido
"! da sua causa (preço, quantidade, data); bloqueio na partida da FI; ou "sem bloqueio".
CLASS zcl_rx_diag_mm02 DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_rx_diagnostic.

    "! IO_READER: leitor de dados (sem ele, cria ZCL_RX_MM_READER).
    "! IV_TODAY: data de hoje (sem ela, SY-DATUM).
    METHODS constructor
      IMPORTING io_reader TYPE REF TO zif_rx_mm_reader OPTIONAL
                iv_today  TYPE d OPTIONAL.

  PRIVATE SECTION.
    CONSTANTS c_state_blocked TYPE string VALUE 'Bloqueada'.
    CONSTANTS c_state_parked TYPE string VALUE 'Estacionada'.
    CONSTANTS c_state_released TYPE string VALUE 'Liberada'.

    DATA mo_reader TYPE REF TO zif_rx_mm_reader.
    DATA mv_today TYPE d.

    METHODS check_authorization
      IMPORTING is_header TYPE zif_rx_mm_reader=>ty_header
                it_items  TYPE zif_rx_mm_reader=>ty_items
      RAISING   zcx_rx_error.

    "! Nomes dos campos RSEG-SPGR* marcados, na ordem do catálogo.
    METHODS blocked_fields
      IMPORTING is_blocks        TYPE zif_rx_mm_reader=>ty_blocks
      RETURNING VALUE(rt_fields) TYPE string_table.

    METHODS add_payment_block
      IMPORTING is_header TYPE zif_rx_mm_reader=>ty_header
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_item_findings
      IMPORTING is_header TYPE zif_rx_mm_reader=>ty_header
                is_item   TYPE zif_rx_mm_reader=>ty_item
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_block
      IMPORTING iv_code   TYPE csequence
                iv_field  TYPE csequence
                iv_reason TYPE csequence
                iv_title  TYPE csequence
                iv_detail TYPE csequence
                iv_tcode  TYPE csequence OPTIONAL
                iv_action TYPE csequence OPTIONAL
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_price_findings
      IMPORTING is_header TYPE zif_rx_mm_reader=>ty_header
                is_item   TYPE zif_rx_mm_reader=>ty_item
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_quantity_findings
      IMPORTING is_item   TYPE zif_rx_mm_reader=>ty_item
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    "! Soma entradas (VGABE 1) e faturas (VGABE 2) do histórico; crédito (SHKZG H) subtrai.
    METHODS sum_history
      IMPORTING it_history  TYPE zif_rx_mm_reader=>ty_history
      EXPORTING ev_received TYPE p
                ev_invoiced TYPE p.

    METHODS add_date_block
      IMPORTING is_item   TYPE zif_rx_mm_reader=>ty_item
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_vendor_item_block
      IMPORTING is_header      TYPE zif_rx_mm_reader=>ty_header
                is_vendor_item TYPE zif_rx_mm_reader=>ty_vendor_item
      CHANGING  cs_result      TYPE zif_rx_types=>ty_result.

    METHODS add_related_orders
      IMPORTING it_items  TYPE zif_rx_mm_reader=>ty_items
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    METHODS add_facts
      IMPORTING is_header   TYPE zif_rx_mm_reader=>ty_header
                it_items    TYPE zif_rx_mm_reader=>ty_items
                iv_due_date TYPE d
                iv_state    TYPE string
      CHANGING  cs_result   TYPE zif_rx_types=>ty_result.

    "! Valor com 2 casas no padrão brasileiro, sem moeda: "1.150,00".
    METHODS decimal2
      IMPORTING iv_value       TYPE p
      RETURNING VALUE(rv_text) TYPE string.

    "! Pedido/item no formato "4500017788/10".
    METHODS po_ref
      IMPORTING is_item        TYPE zif_rx_mm_reader=>ty_item
      RETURNING VALUE(rv_text) TYPE string.

    METHODS vendor_text
      IMPORTING is_header      TYPE zif_rx_mm_reader=>ty_header
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.



CLASS zcl_rx_diag_mm02 IMPLEMENTATION.

  METHOD constructor.
    IF io_reader IS BOUND.
      mo_reader = io_reader.
    ELSE.
      CREATE OBJECT mo_reader TYPE zcl_rx_mm_reader.
    ENDIF.
    IF iv_today IS INITIAL.
      mv_today = sy-datum.
    ELSE.
      mv_today = iv_today.
    ENDIF.
  ENDMETHOD.


  METHOD zif_rx_diagnostic~get_metadata.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.

    rs_meta-id = 'MM-02'.
    rs_meta-version = '1.0'.
    rs_meta-module = 'MM'.
    rs_meta-kind = 'OBJECT'.
    rs_meta-title = 'Fatura de fornecedor bloqueada para pagamento'.

    ls_param-name = 'invoiceDocument'.
    ls_param-label = 'Documento de faturamento (MIRO)'.
    ls_param-data_type = zif_rx_types=>c_data_type-document.
    ls_param-required = abap_true.
    APPEND ls_param TO rs_meta-params.

    CLEAR ls_param.
    ls_param-name = 'fiscalYear'.
    ls_param-label = 'Exercício'.
    ls_param-data_type = zif_rx_types=>c_data_type-integer.
    ls_param-required = abap_true.
    APPEND ls_param TO rs_meta-params.
  ENDMETHOD.


  METHOD zif_rx_diagnostic~execute.
    DATA lv_document TYPE string.
    DATA lv_invoice TYPE string.
    DATA lv_year TYPE string.
    DATA lv_id TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_belnr TYPE zif_rx_mm_reader=>ty_belnr.
    DATA lv_gjahr TYPE zif_rx_mm_reader=>ty_gjahr.
    DATA ls_header TYPE zif_rx_mm_reader=>ty_header.
    DATA lt_items TYPE zif_rx_mm_reader=>ty_items.
    DATA ls_vendor_item TYPE zif_rx_mm_reader=>ty_vendor_item.
    DATA lv_due_date TYPE d.
    DATA lv_state TYPE string.
    DATA lv_bukrs TYPE zif_rx_mm_reader=>ty_bukrs.
    DATA lv_lifnr TYPE zif_rx_mm_reader=>ty_lifnr.
    FIELD-SYMBOLS <ls_item> TYPE zif_rx_mm_reader=>ty_item.

    lv_document = zcl_rx_params=>get( it_params = it_params iv_name = 'invoiceDocument' ).
    lv_year = zcl_rx_params=>get( it_params = it_params iv_name = 'fiscalYear' ).
    " Normaliza o documento: sem zeros à esquerda para exibir; com zeros até 10 posições para ler.
    lv_invoice = zcl_rx_format=>alpha_out( lv_document ).
    lv_document = zcl_rx_format=>alpha_in( iv_value = lv_invoice iv_length = 10 ).
    CONCATENATE lv_invoice '/' lv_year INTO lv_id.
    rs_result = zcl_rx_result=>create( iv_kind = 'SUPPLIER_INVOICE' iv_id = lv_id ).

    IF lv_year CO '0123456789' AND lv_document CO '0123456789' AND strlen( lv_document ) <= 10.
      lv_belnr = lv_document.
      lv_gjahr = lv_year.
      ls_header = mo_reader->read_header( iv_belnr = lv_belnr iv_gjahr = lv_gjahr ).
    ENDIF.

    IF ls_header-found = abap_false.
      CONCATENATE `O documento ` lv_invoice ` do exercício ` lv_year
        ` não existe na verificação de faturas (RBKP).` INTO lv_detail.
      zcl_rx_result=>set_not_found( EXPORTING iv_prefix = 'MM02'
                                              iv_title  = 'Fatura não encontrada'
                                              iv_detail = lv_detail
                                              iv_source = 'RBKP'
                                              iv_field  = 'BELNR'
                                              iv_value  = lv_invoice
                                              iv_label  = 'Documento de faturamento'
                                    CHANGING  cs_result = rs_result ).
      RETURN.
    ENDIF.

    lt_items = mo_reader->read_items( iv_belnr = lv_belnr iv_gjahr = lv_gjahr ).
    check_authorization( is_header = ls_header it_items = lt_items ).

    lv_due_date = ls_header-due_date.
    IF ls_header-parked = abap_true.
      lv_state = c_state_parked.
      lv_detail = 'A fatura foi estacionada e ainda não foi lançada, por isso não entra no pagamento.'.
      zcl_rx_result=>add_finding( EXPORTING iv_code     = 'MM02.PARKED'
                                            iv_severity = zif_rx_types=>c_severity-warning
                                            iv_title    = 'Fatura estacionada'
                                            iv_detail   = lv_detail
                                            iv_tcode    = 'MIR4'
                                            iv_action   = 'Completar e lançar a fatura'
                                  CHANGING  cs_result   = rs_result ).
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'RBKP'
                                             iv_field  = 'RBSTAT'
                                             iv_value  = ls_header-rbstat
                                             iv_label  = 'Status: estacionada'
                                   CHANGING  cs_result = rs_result ).
      add_facts( EXPORTING is_header   = ls_header
                           it_items    = lt_items
                           iv_due_date = lv_due_date
                           iv_state    = lv_state
                 CHANGING  cs_result   = rs_result ).
      zcl_rx_result=>settle_status( CHANGING cs_result = rs_result ).
      RETURN.
    ENDIF.

    " Partida do fornecedor na FI: traz o bloqueio da FI e o vencimento real.
    lv_bukrs = ls_header-bukrs.
    lv_lifnr = ls_header-lifnr.
    ls_vendor_item = mo_reader->read_vendor_item( iv_belnr = lv_belnr
                                                  iv_gjahr = lv_gjahr
                                                  iv_bukrs = lv_bukrs
                                                  iv_lifnr = lv_lifnr ).
    IF ls_vendor_item-found = abap_true AND ls_vendor_item-due_date IS NOT INITIAL.
      lv_due_date = ls_vendor_item-due_date.
    ENDIF.

    add_payment_block( EXPORTING is_header = ls_header CHANGING cs_result = rs_result ).
    LOOP AT lt_items ASSIGNING <ls_item>.
      add_item_findings( EXPORTING is_header = ls_header
                                   is_item   = <ls_item>
                         CHANGING  cs_result = rs_result ).
    ENDLOOP.
    add_vendor_item_block( EXPORTING is_header      = ls_header
                                     is_vendor_item = ls_vendor_item
                           CHANGING  cs_result      = rs_result ).

    IF rs_result-findings IS INITIAL.
      lv_detail = 'A fatura está lançada e liberada para pagamento. Vencimento conforme as condições de pagamento.'.
      zcl_rx_result=>add_finding(
        EXPORTING iv_code     = 'MM02.NOT_BLOCKED'
                  iv_severity = zif_rx_types=>c_severity-info
                  iv_title    = 'Fatura sem bloqueio'
                  iv_detail   = lv_detail
                  iv_tcode    = 'FBL1N'
                  iv_action   = 'Acompanhar a partida do fornecedor'
        CHANGING  cs_result   = rs_result ).
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'RBKP'
                                             iv_field  = 'ZLSPR'
                                             iv_value  = ''
                                             iv_label  = 'Bloqueio de pagamento: nenhum'
                                   CHANGING  cs_result = rs_result ).
      lv_state = c_state_released.
    ELSE.
      lv_state = c_state_blocked.
    ENDIF.

    add_related_orders( EXPORTING it_items = lt_items CHANGING cs_result = rs_result ).
    add_facts( EXPORTING is_header   = ls_header
                         it_items    = lt_items
                         iv_due_date = lv_due_date
                         iv_state    = lv_state
               CHANGING  cs_result   = rs_result ).
    zcl_rx_result=>settle_status( CHANGING cs_result = rs_result ).
  ENDMETHOD.


  METHOD check_authorization.
    DATA lv_message TYPE string.
    DATA lt_plants TYPE STANDARD TABLE OF zif_rx_mm_reader=>ty_werks WITH DEFAULT KEY.
    DATA lv_plant TYPE zif_rx_mm_reader=>ty_werks.
    DATA lv_bukrs TYPE zif_rx_mm_reader=>ty_bukrs.
    FIELD-SYMBOLS <ls_item> TYPE zif_rx_mm_reader=>ty_item.

    lv_bukrs = is_header-bukrs.
    IF mo_reader->is_authorized( lv_bukrs ) = abap_false.
      CONCATENATE `Sem autorização para a empresa ` is_header-bukrs ` (objeto F_BKPF_BUK).` INTO lv_message.
      RAISE EXCEPTION TYPE zcx_rx_error
        EXPORTING iv_http_status = 403 iv_code = 'NOT_AUTHORIZED' iv_text = lv_message.
    ENDIF.

    " Centros dos itens (sem repetir). (validar M_RECH_WRK)
    LOOP AT it_items ASSIGNING <ls_item> WHERE werks IS NOT INITIAL.
      READ TABLE lt_plants WITH KEY table_line = <ls_item>-werks TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND <ls_item>-werks TO lt_plants.
      ENDIF.
    ENDLOOP.
    LOOP AT lt_plants INTO lv_plant.
      IF mo_reader->is_authorized( iv_bukrs = lv_bukrs iv_werks = lv_plant ) = abap_false.
        CONCATENATE `Sem autorização para o centro ` lv_plant ` (objeto M_RECH_WRK).` INTO lv_message.
        RAISE EXCEPTION TYPE zcx_rx_error
          EXPORTING iv_http_status = 403 iv_code = 'NOT_AUTHORIZED' iv_text = lv_message.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD blocked_fields.
    IF is_blocks-spgrp IS NOT INITIAL.
      APPEND 'SPGRP' TO rt_fields.
    ENDIF.
    IF is_blocks-spgrm IS NOT INITIAL.
      APPEND 'SPGRM' TO rt_fields.
    ENDIF.
    IF is_blocks-spgrt IS NOT INITIAL.
      APPEND 'SPGRT' TO rt_fields.
    ENDIF.
    IF is_blocks-spgrg IS NOT INITIAL.
      APPEND 'SPGRG' TO rt_fields.
    ENDIF.
    IF is_blocks-spgrq IS NOT INITIAL.
      APPEND 'SPGRQ' TO rt_fields.
    ENDIF.
    IF is_blocks-spgrs IS NOT INITIAL.
      APPEND 'SPGRS' TO rt_fields.
    ENDIF.
    IF is_blocks-spgrc IS NOT INITIAL.
      APPEND 'SPGRC' TO rt_fields.
    ENDIF.
    IF is_blocks-spgrv IS NOT INITIAL.
      APPEND 'SPGRV' TO rt_fields.
    ENDIF.
  ENDMETHOD.


  METHOD add_payment_block.
    DATA lv_detail TYPE string.
    DATA lv_label TYPE string.

    IF is_header-zlspr IS INITIAL.
      RETURN.
    ENDIF.
    IF is_header-zlspr = 'R'.
      lv_detail = 'A verificação de faturas bloqueou o pagamento automaticamente (chave R).'.
      lv_label = 'Bloqueio de pagamento: verificação de faturas'.
    ELSE.
      CONCATENATE `O pagamento está bloqueado pela chave ` is_header-zlspr INTO lv_detail.
      IF is_header-zlspr_text IS NOT INITIAL.
        CONCATENATE lv_detail ` (` is_header-zlspr_text `)` INTO lv_detail.
      ENDIF.
      CONCATENATE lv_detail `.` INTO lv_detail.
      lv_label = 'Bloqueio de pagamento'.
      IF is_header-zlspr_text IS NOT INITIAL.
        CONCATENATE lv_label `: ` is_header-zlspr_text INTO lv_label.
      ENDIF.
    ENDIF.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'MM02.PAYMENT_BLOCK'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = 'Fatura bloqueada para pagamento'
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'MRBR'
                                          iv_action   = 'Liberar a fatura depois de resolver a divergência'
                                CHANGING  cs_result   = cs_result ).
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'RBKP'
                                           iv_field  = 'ZLSPR'
                                           iv_value  = is_header-zlspr
                                           iv_label  = lv_label
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_item_findings.
    DATA lt_fields TYPE string_table.
    DATA lv_field TYPE string.
    DATA lv_item TYPE string.
    DATA lv_order TYPE string.
    DATA lv_title TYPE string.
    DATA lv_detail TYPE string.

    lt_fields = blocked_fields( is_item-blocks ).
    lv_item = zcl_rx_format=>alpha_out( is_item-buzei ).
    lv_order = zcl_rx_format=>alpha_out( is_item-ebeln ).

    LOOP AT lt_fields INTO lv_field.
      CASE lv_field.
        WHEN 'SPGRP'.
          CONCATENATE `Item ` lv_item ` bloqueado por preço` INTO lv_title.
          CONCATENATE `O preço faturado do item ` lv_item ` está fora da tolerância em relação ao pedido `
            lv_order `.` INTO lv_detail.
          add_block( EXPORTING iv_code   = 'MM02.BLOCK_PRICE'
                               iv_field  = lv_field
                               iv_reason = 'preço'
                               iv_title  = lv_title
                               iv_detail = lv_detail
                     CHANGING  cs_result = cs_result ).
          add_price_findings( EXPORTING is_header = is_header
                                        is_item   = is_item
                              CHANGING  cs_result = cs_result ).
        WHEN 'SPGRM'.
          CONCATENATE `Item ` lv_item ` bloqueado por quantidade` INTO lv_title.
          add_block( EXPORTING iv_code   = 'MM02.BLOCK_QUANTITY'
                               iv_field  = lv_field
                               iv_reason = 'quantidade'
                               iv_title  = lv_title
                               iv_detail = 'A quantidade faturada é maior que a quantidade recebida.'
                               iv_tcode  = 'MRBR'
                               iv_action = 'Liberar depois de lançar a entrada de mercadoria'
                     CHANGING  cs_result = cs_result ).
          add_quantity_findings( EXPORTING is_item   = is_item
                                 CHANGING  cs_result = cs_result ).
        WHEN 'SPGRT'.
          add_date_block( EXPORTING is_item   = is_item
                          CHANGING  cs_result = cs_result ).
        WHEN 'SPGRG'.
          CONCATENATE `Item ` lv_item ` bloqueado por quantidade do preço` INTO lv_title.
          CONCATENATE `A quantidade na unidade de preço do pedido ` lv_order
            ` diverge da quantidade faturada no item ` lv_item `.` INTO lv_detail.
          add_block( EXPORTING iv_code   = 'MM02.BLOCK_PRICE_QTY'
                               iv_field  = lv_field
                               iv_reason = 'quantidade do preço do pedido'
                               iv_title  = lv_title
                               iv_detail = lv_detail
                               iv_tcode  = 'MRBR'
                               iv_action = 'Conferir a quantidade do preço e liberar'
                     CHANGING  cs_result = cs_result ).
        WHEN 'SPGRQ'.
          CONCATENATE `Item ` lv_item ` bloqueado manualmente` INTO lv_title.
          CONCATENATE `O item ` lv_item ` foi bloqueado manualmente na fatura.` INTO lv_detail.
          add_block( EXPORTING iv_code   = 'MM02.BLOCK_MANUAL'
                               iv_field  = lv_field
                               iv_reason = 'manual'
                               iv_title  = lv_title
                               iv_detail = lv_detail
                               iv_tcode  = 'MRBR'
                               iv_action = 'Liberar a fatura'
                     CHANGING  cs_result = cs_result ).
        WHEN 'SPGRS'.
          CONCATENATE `Item ` lv_item ` bloqueado por montante` INTO lv_title.
          CONCATENATE `O valor do item ` lv_item ` ultrapassa o limite de montante da verificação de faturas.`
            INTO lv_detail.
          add_block( EXPORTING iv_code   = 'MM02.BLOCK_AMOUNT'
                               iv_field  = lv_field
                               iv_reason = 'montante'
                               iv_title  = lv_title
                               iv_detail = lv_detail
                               iv_tcode  = 'MRBR'
                               iv_action = 'Conferir o valor e liberar'
                     CHANGING  cs_result = cs_result ).
        WHEN 'SPGRC'.
          CONCATENATE `Item ` lv_item ` bloqueado por qualidade` INTO lv_title.
          CONCATENATE `O item ` lv_item ` aguarda a liberação da inspeção de qualidade.` INTO lv_detail.
          add_block( EXPORTING iv_code   = 'MM02.BLOCK_QUALITY'
                               iv_field  = lv_field
                               iv_reason = 'qualidade'
                               iv_title  = lv_title
                               iv_detail = lv_detail
                               iv_tcode  = 'MRBR'
                               iv_action = 'Liberar depois da inspeção de qualidade'
                     CHANGING  cs_result = cs_result ).
        WHEN 'SPGRV'.
          CONCATENATE `Item ` lv_item ` bloqueado por projeto` INTO lv_title.
          CONCATENATE `O item ` lv_item ` está bloqueado por divergência de orçamento do projeto.` INTO lv_detail.
          add_block( EXPORTING iv_code   = 'MM02.BLOCK_PROJECT'
                               iv_field  = lv_field
                               iv_reason = 'projeto'
                               iv_title  = lv_title
                               iv_detail = lv_detail
                               iv_tcode  = 'MRBR'
                               iv_action = 'Conferir o orçamento do projeto e liberar'
                     CHANGING  cs_result = cs_result ).
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_block.
    DATA lv_label TYPE string.

    zcl_rx_result=>add_finding( EXPORTING iv_code     = iv_code
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = iv_title
                                          iv_detail   = iv_detail
                                          iv_tcode    = iv_tcode
                                          iv_action   = iv_action
                                CHANGING  cs_result   = cs_result ).
    CONCATENATE `Motivo de bloqueio: ` iv_reason INTO lv_label.
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'RSEG'
                                           iv_field  = iv_field
                                           iv_value  = 'X'
                                           iv_label  = lv_label
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_price_findings.
    DATA ls_po TYPE zif_rx_mm_reader=>ty_po_item.
    DATA ls_tolerance TYPE zif_rx_mm_reader=>ty_tolerance.
    DATA lv_ebeln TYPE zif_rx_mm_reader=>ty_ebeln.
    DATA lv_ebelp TYPE zif_rx_mm_reader=>ty_ebelp.
    DATA lv_bukrs TYPE zif_rx_mm_reader=>ty_bukrs.
    DATA lv_tolsl TYPE zif_rx_mm_reader=>ty_tolsl.
    DATA lv_po_price TYPE p LENGTH 13 DECIMALS 4.
    DATA lv_inv_price TYPE p LENGTH 13 DECIMALS 4.
    DATA lv_pct TYPE p LENGTH 9 DECIMALS 2.
    DATA lv_pct_abs TYPE p LENGTH 9 DECIMALS 2.
    DATA lv_pct_text TYPE string.
    DATA lv_signed TYPE string.
    DATA lv_po_money TYPE string.
    DATA lv_inv_money TYPE string.
    DATA lv_qty TYPE string.
    DATA lv_ref TYPE string.
    DATA lv_item TYPE string.
    DATA lv_title TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_label TYPE string.
    DATA lv_value TYPE string.
    DATA lv_limit TYPE string.
    DATA lv_exceeded TYPE abap_bool.

    lv_ebeln = is_item-ebeln.
    lv_ebelp = is_item-ebelp.
    ls_po = mo_reader->read_po_item( iv_ebeln = lv_ebeln iv_ebelp = lv_ebelp ).

    IF ls_po-found = abap_true AND ls_po-peinh > 0 AND is_item-menge > 0 AND ls_po-netpr > 0.
      lv_po_price = ls_po-netpr / ls_po-peinh.
      lv_inv_price = is_item-wrbtr / is_item-menge.
      lv_pct = ( lv_inv_price - lv_po_price ) * 100 / lv_po_price.
      IF lv_pct <> 0.
        lv_pct_abs = abs( lv_pct ).
        lv_pct_text = zcl_rx_format=>number_br( iv_value = lv_pct_abs iv_decimals = 1 ).
        IF lv_pct > 0.
          CONCATENATE `+` lv_pct_text INTO lv_signed.
        ELSE.
          CONCATENATE `-` lv_pct_text INTO lv_signed.
        ENDIF.
        lv_po_money = zcl_rx_format=>money( iv_amount = lv_po_price iv_currency = ls_po-waers ).
        lv_inv_money = zcl_rx_format=>money( iv_amount = lv_inv_price iv_currency = is_header-waers ).
        lv_qty = zcl_rx_format=>quantity( iv_value = is_item-menge iv_unit = is_item-meins ).
        CONCATENATE `Divergência de preço de ` lv_pct_text `%` INTO lv_title.
        CONCATENATE `Pedido: ` lv_po_money `/` ls_po-bprme `. Fatura: ` lv_inv_money `/` is_item-meins
          ` (` lv_signed `%), para ` lv_qty `.` INTO lv_detail.
        zcl_rx_result=>add_finding( EXPORTING iv_code     = 'MM02.PRICE_DIFF'
                                              iv_severity = zif_rx_types=>c_severity-blocking
                                              iv_title    = lv_title
                                              iv_detail   = lv_detail
                                              iv_tcode    = 'ME23N'
                                              iv_action   = 'Conferir o preço do pedido com o comprador'
                                    CHANGING  cs_result   = cs_result ).
        lv_ref = po_ref( is_item ).
        CONCATENATE `Preço do pedido ` lv_ref INTO lv_label.
        lv_value = decimal2( ls_po-netpr ).
        zcl_rx_result=>add_evidence( EXPORTING iv_source = 'EKPO'
                                               iv_field  = 'NETPR'
                                               iv_value  = lv_value
                                               iv_label  = lv_label
                                     CHANGING  cs_result = cs_result ).
        lv_item = zcl_rx_format=>alpha_out( is_item-buzei ).
        CONCATENATE `Valor faturado do item ` lv_item INTO lv_label.
        lv_value = decimal2( is_item-wrbtr ).
        zcl_rx_result=>add_evidence( EXPORTING iv_source = 'RSEG'
                                               iv_field  = 'WRBTR'
                                               iv_value  = lv_value
                                               iv_label  = lv_label
                                     CHANGING  cs_result = cs_result ).
      ENDIF.
    ENDIF.

    " Tolerância de preço (chave PP) da empresa. (validar chave)
    lv_bukrs = is_header-bukrs.
    lv_tolsl = 'PP'.
    ls_tolerance = mo_reader->read_tolerance( iv_bukrs = lv_bukrs iv_tolsl = lv_tolsl ).
    IF ls_tolerance-found = abap_true.
      IF lv_pct > ls_tolerance-proz1.
        lv_exceeded = abap_true.
      ENDIF.
      IF lv_exceeded = abap_true.
        lv_title = 'Tolerância de preço excedida'.
      ELSE.
        lv_title = 'Tolerância de preço'.
      ENDIF.
      lv_limit = zcl_rx_format=>number_br( iv_value = ls_tolerance-proz1 iv_decimals = 2 ).
      CONCATENATE `A chave de tolerância PP da empresa ` is_header-bukrs ` permite até ` lv_limit
        `% acima do preço do pedido.` INTO lv_detail.
      zcl_rx_result=>add_finding( EXPORTING iv_code     = 'MM02.TOLERANCE_INFO'
                                            iv_severity = zif_rx_types=>c_severity-info
                                            iv_title    = lv_title
                                            iv_detail   = lv_detail
                                  CHANGING  cs_result   = cs_result ).
      lv_value = decimal2( ls_tolerance-proz1 ).
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'T169G'
                                             iv_field  = 'PROZ1'
                                             iv_value  = lv_value
                                             iv_label  = 'Tolerância PP (limite superior %)'
                                   CHANGING  cs_result = cs_result ).
    ENDIF.
  ENDMETHOD.


  METHOD add_quantity_findings.
    DATA lt_history TYPE zif_rx_mm_reader=>ty_history.
    DATA lv_ebeln TYPE zif_rx_mm_reader=>ty_ebeln.
    DATA lv_ebelp TYPE zif_rx_mm_reader=>ty_ebelp.
    DATA lv_received TYPE p LENGTH 13 DECIMALS 3.
    DATA lv_invoiced TYPE p LENGTH 13 DECIMALS 3.
    DATA lv_missing TYPE p LENGTH 13 DECIMALS 3.
    DATA lv_received_text TYPE string.
    DATA lv_invoiced_text TYPE string.
    DATA lv_missing_text TYPE string.
    DATA lv_ref TYPE string.
    DATA lv_value TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_action TYPE string.

    lv_ebeln = is_item-ebeln.
    lv_ebelp = is_item-ebelp.
    lt_history = mo_reader->read_history( iv_ebeln = lv_ebeln iv_ebelp = lv_ebelp ).
    lv_ref = po_ref( is_item ).

    sum_history( EXPORTING it_history  = lt_history
                 IMPORTING ev_received = lv_received
                           ev_invoiced = lv_invoiced ).

    lv_received_text = zcl_rx_format=>quantity( iv_value = lv_received iv_unit = is_item-meins ).
    lv_invoiced_text = zcl_rx_format=>quantity( iv_value = lv_invoiced iv_unit = is_item-meins ).

    IF lt_history IS INITIAL.
      CONCATENATE `Não há entradas nem faturas no histórico do pedido ` lv_ref `.` INTO lv_detail.
      zcl_rx_result=>add_finding( EXPORTING iv_code     = 'MM02.QTY_DIFF'
                                            iv_severity = zif_rx_types=>c_severity-blocking
                                            iv_title    = 'Divergência de quantidade'
                                            iv_detail   = lv_detail
                                            iv_tcode    = 'ME23N'
                                            iv_action   = 'Conferir o histórico do pedido'
                                  CHANGING  cs_result   = cs_result ).
      RETURN.
    ENDIF.

    IF lv_received < lv_invoiced.
      lv_missing = lv_invoiced - lv_received.
      lv_missing_text = zcl_rx_format=>quantity( iv_value = lv_missing iv_unit = is_item-meins ).
      CONCATENATE `Recebido: ` lv_received_text `. Faturado: ` lv_invoiced_text `. Faltam ` lv_missing_text
        ` de entrada de mercadoria no pedido ` lv_ref `.` INTO lv_detail.
      CONCATENATE `Lançar a entrada de mercadoria dos ` lv_missing_text ` restantes` INTO lv_action.
      zcl_rx_result=>add_finding( EXPORTING iv_code     = 'MM02.GR_MISSING'
                                            iv_severity = zif_rx_types=>c_severity-blocking
                                            iv_title    = 'Entrada de mercadoria incompleta'
                                            iv_detail   = lv_detail
                                            iv_tcode    = 'MIGO'
                                            iv_action   = lv_action
                                  CHANGING  cs_result   = cs_result ).
    ELSE.
      " As entradas já cobrem as faturas: o bloqueio pode ser antigo e só falta liberar.
      CONCATENATE `Recebido: ` lv_received_text `. Faturado: ` lv_invoiced_text `. No histórico do pedido `
        lv_ref ` as entradas cobrem as faturas; o bloqueio de quantidade pode ser antigo.` INTO lv_detail.
      zcl_rx_result=>add_finding( EXPORTING iv_code     = 'MM02.QTY_DIFF'
                                            iv_severity = zif_rx_types=>c_severity-blocking
                                            iv_title    = 'Divergência de quantidade'
                                            iv_detail   = lv_detail
                                            iv_tcode    = 'MRBR'
                                            iv_action   = 'Reavaliar e liberar a fatura'
                                  CHANGING  cs_result   = cs_result ).
    ENDIF.
    lv_value = zcl_rx_format=>number_br( lv_received ).
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'EKBE'
                                           iv_field  = 'MENGE'
                                           iv_value  = lv_value
                                           iv_label  = 'Entradas de mercadoria (VGABE 1)'
                                 CHANGING  cs_result = cs_result ).
    lv_value = zcl_rx_format=>number_br( lv_invoiced ).
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'EKBE'
                                           iv_field  = 'MENGE'
                                           iv_value  = lv_value
                                           iv_label  = 'Faturas (VGABE 2)'
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD sum_history.
    DATA lv_signed TYPE p LENGTH 13 DECIMALS 3.
    FIELD-SYMBOLS <ls_line> TYPE zif_rx_mm_reader=>ty_history_line.

    ev_received = 0.
    ev_invoiced = 0.
    LOOP AT it_history ASSIGNING <ls_line>.
      IF <ls_line>-shkzg = 'H'.
        lv_signed = 0 - <ls_line>-menge.
      ELSE.
        lv_signed = <ls_line>-menge.
      ENDIF.
      CASE <ls_line>-vgabe.
        WHEN '1'.
          ev_received = ev_received + lv_signed.
        WHEN '2'.
          ev_invoiced = ev_invoiced + lv_signed.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_date_block.
    DATA ls_po TYPE zif_rx_mm_reader=>ty_po_item.
    DATA lt_history TYPE zif_rx_mm_reader=>ty_history.
    DATA lv_ebeln TYPE zif_rx_mm_reader=>ty_ebeln.
    DATA lv_ebelp TYPE zif_rx_mm_reader=>ty_ebelp.
    DATA lv_first_gr TYPE d.
    DATA lv_days TYPE i.
    DATA lv_days_text TYPE string.
    DATA lv_unit TYPE string.
    DATA lv_item TYPE string.
    DATA lv_order TYPE string.
    DATA lv_title TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_value TYPE string.
    FIELD-SYMBOLS <ls_line> TYPE zif_rx_mm_reader=>ty_history_line.

    lv_ebeln = is_item-ebeln.
    lv_ebelp = is_item-ebelp.
    ls_po = mo_reader->read_po_item( iv_ebeln = lv_ebeln iv_ebelp = lv_ebelp ).
    lt_history = mo_reader->read_history( iv_ebeln = lv_ebeln iv_ebelp = lv_ebelp ).

    " Primeira entrada de mercadoria (VGABE 1, não estorno) x data de remessa do pedido.
    LOOP AT lt_history ASSIGNING <ls_line> WHERE vgabe = '1' AND shkzg <> 'H'.
      IF lv_first_gr IS INITIAL OR <ls_line>-budat < lv_first_gr.
        lv_first_gr = <ls_line>-budat.
      ENDIF.
    ENDLOOP.
    IF ls_po-eindt IS NOT INITIAL AND lv_first_gr IS NOT INITIAL AND ls_po-eindt > lv_first_gr.
      lv_days = ls_po-eindt - lv_first_gr.
    ENDIF.

    lv_item = zcl_rx_format=>alpha_out( is_item-buzei ).
    lv_order = zcl_rx_format=>alpha_out( is_item-ebeln ).
    CONCATENATE `Item ` lv_item ` bloqueado por data` INTO lv_title.
    IF lv_days > 0.
      lv_days_text = zcl_rx_format=>int( lv_days ).
      IF lv_days = 1.
        lv_unit = 'dia'.
      ELSE.
        lv_unit = 'dias'.
      ENDIF.
      CONCATENATE `A mercadoria foi entregue ` lv_days_text ` ` lv_unit ` antes da data prevista no pedido `
        lv_order `, acima da tolerância.` INTO lv_detail.
    ELSE.
      CONCATENATE `A mercadoria foi entregue antes da data prevista no pedido ` lv_order
        `, acima da tolerância.` INTO lv_detail.
    ENDIF.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'MM02.BLOCK_DATE'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = lv_title
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'ME23N'
                                          iv_action   = 'Confirmar com o comprador se a entrega antecipada foi aceita'
                                CHANGING  cs_result   = cs_result ).
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'RSEG'
                                           iv_field  = 'SPGRT'
                                           iv_value  = 'X'
                                           iv_label  = 'Motivo de bloqueio: data'
                                 CHANGING  cs_result = cs_result ).
    lv_value = zcl_rx_format=>date_iso( ls_po-eindt ).
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'EKET'
                                           iv_field  = 'EINDT'
                                           iv_value  = lv_value
                                           iv_label  = 'Data de remessa prevista no pedido'
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_vendor_item_block.
    DATA lv_detail TYPE string.

    " Se a chave da partida é a mesma do cabeçalho, o PAYMENT_BLOCK já cobre. (validar)
    IF is_vendor_item-found = abap_false
        OR is_vendor_item-zlspr IS INITIAL
        OR is_vendor_item-zlspr = is_header-zlspr.
      RETURN.
    ENDIF.
    CONCATENATE `A partida do fornecedor na contabilidade financeira está bloqueada para pagamento (chave `
      is_vendor_item-zlspr `).` INTO lv_detail.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'MM02.FI_PAYMENT_BLOCK'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = 'Partida do fornecedor bloqueada na FI'
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'FB02'
                                          iv_action   = 'Remover o bloqueio de pagamento da partida'
                                CHANGING  cs_result   = cs_result ).
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'BSIK'
                                           iv_field  = 'ZLSPR'
                                           iv_value  = is_vendor_item-zlspr
                                           iv_label  = 'Bloqueio de pagamento na partida do fornecedor'
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_related_orders.
    DATA lt_orders TYPE string_table.
    DATA lt_fields TYPE string_table.
    DATA lv_order TYPE string.
    FIELD-SYMBOLS <ls_item> TYPE zif_rx_mm_reader=>ty_item.

    " Pedidos dos itens bloqueados, sem repetir.
    LOOP AT it_items ASSIGNING <ls_item> WHERE ebeln IS NOT INITIAL.
      lt_fields = blocked_fields( <ls_item>-blocks ).
      IF lt_fields IS INITIAL.
        CONTINUE.
      ENDIF.
      lv_order = zcl_rx_format=>alpha_out( <ls_item>-ebeln ).
      READ TABLE lt_orders WITH KEY table_line = lv_order TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND lv_order TO lt_orders.
        zcl_rx_result=>add_related( EXPORTING iv_kind   = 'PURCHASE_ORDER'
                                              iv_id     = lv_order
                                    CHANGING  cs_result = cs_result ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD add_facts.
    DATA lv_value TYPE string.
    DATA lv_order TYPE string.
    FIELD-SYMBOLS <ls_item> TYPE zif_rx_mm_reader=>ty_item.

    lv_value = vendor_text( is_header ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'vendor' iv_label = 'Fornecedor' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).
    lv_value = zcl_rx_format=>money( iv_amount = is_header-rmwwr iv_currency = is_header-waers ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'grossAmount' iv_label = 'Valor bruto' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'state' iv_label = 'Situação' iv_value = iv_state
                             CHANGING  cs_result = cs_result ).
    READ TABLE it_items INDEX 1 ASSIGNING <ls_item>.
    IF sy-subrc = 0 AND <ls_item>-ebeln IS NOT INITIAL.
      lv_order = zcl_rx_format=>alpha_out( <ls_item>-ebeln ).
      zcl_rx_result=>add_fact( EXPORTING iv_id = 'purchaseOrder' iv_label = 'Pedido de compra' iv_value = lv_order
                               CHANGING  cs_result = cs_result ).
    ENDIF.
    lv_value = zcl_rx_format=>date_iso( is_header-budat ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'postingDate' iv_label = 'Data de lançamento' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).
    lv_value = zcl_rx_format=>date_iso( iv_due_date ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'dueDate' iv_label = 'Vencimento' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).
    lv_value = is_header-bukrs.
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'companyCode' iv_label = 'Empresa' iv_value = lv_value
                             CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD decimal2.
    " MONEY devolve "R$ 1.150,00" para BRL; tira o prefixo e fica só o número.
    rv_text = zcl_rx_format=>money( iv_amount = iv_value iv_currency = 'BRL' ).
    SHIFT rv_text LEFT BY 3 PLACES.
  ENDMETHOD.


  METHOD po_ref.
    DATA lv_order TYPE string.
    DATA lv_item TYPE string.

    lv_order = zcl_rx_format=>alpha_out( is_item-ebeln ).
    lv_item = zcl_rx_format=>alpha_out( is_item-ebelp ).
    CONCATENATE lv_order '/' lv_item INTO rv_text.
  ENDMETHOD.


  METHOD vendor_text.
    DATA lv_lifnr TYPE string.

    lv_lifnr = zcl_rx_format=>alpha_out( is_header-lifnr ).
    IF is_header-vendor_name IS INITIAL.
      rv_text = lv_lifnr.
    ELSE.
      CONCATENATE lv_lifnr '·' is_header-vendor_name INTO rv_text SEPARATED BY space.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
