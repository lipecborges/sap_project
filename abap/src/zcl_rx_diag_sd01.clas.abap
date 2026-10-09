"! SD-01: Por que o pedido de venda não faturou?
"! Segue a cadeia do processo (pedido → crédito → remessa → saída de mercadoria →
"! faturamento) e mostra todos os achados. Só lógica: os dados vêm do leitor
"! (ZIF_RX_SD_READER), o que permite testar sem SAP. Paridade com o sap-mock
"! (services/sap-mock/src/fixtures/sd01.ts): códigos, severidades e ordem.
CLASS zcl_rx_diag_sd01 DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_rx_diagnostic.

    "! IO_READER: sem ele, usa o leitor real (ZCL_RX_SD_READER).
    "! IV_TODAY: sem ele, usa a data do sistema.
    METHODS constructor
      IMPORTING io_reader TYPE REF TO zif_rx_sd_reader OPTIONAL
                iv_today  TYPE d OPTIONAL.

  PRIVATE SECTION.
    " Tudo o que foi lido do pedido, para as verificações.
    TYPES:
      BEGIN OF ty_context,
        header      TYPE zif_rx_sd_reader=>ty_order_header,
        items       TYPE zif_rx_sd_reader=>ty_items,
        missing     TYPE zif_rx_sd_reader=>ty_missing_fields,
        followups   TYPE zif_rx_sd_reader=>ty_followups,
        s4          TYPE abap_bool,
        billing_due TYPE abap_bool,
        "! Já houve um achado de crédito, bloqueio de remessa ou incompletude
        blocked     TYPE abap_bool,
      END OF ty_context.

    DATA mo_reader TYPE REF TO zif_rx_sd_reader.
    DATA mv_today TYPE d.

    METHODS load_context
      IMPORTING is_header         TYPE zif_rx_sd_reader=>ty_order_header
      RETURNING VALUE(rs_context) TYPE ty_context.

    METHODS check_order
      CHANGING cs_context TYPE ty_context
               cs_result  TYPE zif_rx_types=>ty_result.

    METHODS check_credit
      CHANGING cs_context TYPE ty_context
               cs_result  TYPE zif_rx_types=>ty_result.

    METHODS check_delivery_block
      CHANGING cs_context TYPE ty_context
               cs_result  TYPE zif_rx_types=>ty_result.

    METHODS check_schedule_block
      CHANGING cs_context TYPE ty_context
               cs_result  TYPE zif_rx_types=>ty_result.

    METHODS check_incomplete
      CHANGING cs_context TYPE ty_context
               cs_result  TYPE zif_rx_types=>ty_result.

    METHODS check_not_delivered
      IMPORTING is_context TYPE ty_context
      CHANGING  cs_result  TYPE zif_rx_types=>ty_result.

    METHODS check_goods_issue
      IMPORTING is_context TYPE ty_context
      CHANGING  cs_result  TYPE zif_rx_types=>ty_result.

    METHODS check_billing_block
      IMPORTING is_context TYPE ty_context
      CHANGING  cs_result  TYPE zif_rx_types=>ty_result.

    METHODS check_billing_due
      IMPORTING is_context TYPE ty_context
      CHANGING  cs_result  TYPE zif_rx_types=>ty_result.

    METHODS check_billed
      IMPORTING is_context TYPE ty_context
      CHANGING  cs_result  TYPE zif_rx_types=>ty_result.

    METHODS check_rejected_items
      IMPORTING is_context TYPE ty_context
      CHANGING  cs_result  TYPE zif_rx_types=>ty_result.

    METHODS check_not_relevant_items
      IMPORTING is_context TYPE ty_context
      CHANGING  cs_result  TYPE zif_rx_types=>ty_result.

    METHODS add_facts
      IMPORTING is_context TYPE ty_context
      CHANGING  cs_result  TYPE zif_rx_types=>ty_result.

    METHODS add_related
      IMPORTING is_context TYPE ty_context
      CHANGING  cs_result  TYPE zif_rx_types=>ty_result.

    "! Origem (tabela) dos status do cabeçalho: VBUK no ECC, VBAK no S/4.
    METHODS header_source
      IMPORTING is_context       TYPE ty_context
      RETURNING VALUE(rv_source) TYPE string.

    "! Origem do status da remessa: VBUK no ECC, LIKP no S/4.
    METHODS delivery_source
      IMPORTING is_context       TYPE ty_context
      RETURNING VALUE(rv_source) TYPE string.

    "! "100234 · Nome do cliente".
    METHODS customer_text
      IMPORTING is_header      TYPE zif_rx_sd_reader=>ty_order_header
      RETURNING VALUE(rv_text) TYPE string.

    "! "01 (Bloqueio geral)", ou só o código se não houver texto.
    METHODS code_with_text
      IMPORTING iv_code        TYPE csequence
                iv_text        TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

    "! Número do item sem zeros ("000020" → "20").
    METHODS item_no
      IMPORTING iv_posnr       TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

    "! Texto do status A/B/C de remessa, incompletude e saída de mercadoria.
    METHODS status_text
      IMPORTING iv_status      TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

    METHODS missing_text
      IMPORTING is_missing     TYPE zif_rx_sd_reader=>ty_missing_field
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.



CLASS zcl_rx_diag_sd01 IMPLEMENTATION.

  METHOD constructor.
    IF io_reader IS BOUND.
      mo_reader = io_reader.
    ELSE.
      CREATE OBJECT mo_reader TYPE zcl_rx_sd_reader.
    ENDIF.
    IF iv_today IS INITIAL.
      mv_today = sy-datum.
    ELSE.
      mv_today = iv_today.
    ENDIF.
  ENDMETHOD.


  METHOD zif_rx_diagnostic~get_metadata.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.

    rs_meta-id = 'SD-01'.
    rs_meta-version = '1.0'.
    rs_meta-module = 'SD'.
    rs_meta-kind = 'OBJECT'.
    rs_meta-title = 'Pedido de venda não faturado'.
    ls_param-name = 'salesOrder'.
    ls_param-label = 'Pedido de venda'.
    ls_param-data_type = zif_rx_types=>c_data_type-document.
    ls_param-required = abap_true.
    APPEND ls_param TO rs_meta-params.
  ENDMETHOD.


  METHOD zif_rx_diagnostic~execute.
    DATA lv_input TYPE string.
    DATA lv_id TYPE string.
    DATA lv_vbeln TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_message TYPE string.
    DATA ls_header TYPE zif_rx_sd_reader=>ty_order_header.
    DATA ls_context TYPE ty_context.

    lv_input = zcl_rx_params=>get( it_params = it_params iv_name = 'salesOrder' ).
    lv_id = zcl_rx_format=>alpha_out( lv_input ).
    rs_result = zcl_rx_result=>create( iv_kind = 'SALES_ORDER' iv_id = lv_id ).

    lv_vbeln = zcl_rx_format=>alpha_in( iv_value = lv_id iv_length = 10 ).
    IF strlen( lv_vbeln ) <= 10.
      ls_header = mo_reader->get_header( lv_vbeln ).
    ENDIF.
    IF ls_header-exists = abap_false.
      CONCATENATE 'O pedido de venda' lv_id 'não existe neste sistema/mandante.'
        INTO lv_detail SEPARATED BY space.
      zcl_rx_result=>set_not_found( EXPORTING iv_prefix = 'SD01'
                                              iv_title  = 'Pedido não encontrado'
                                              iv_detail = lv_detail
                                              iv_source = 'VBAK'
                                              iv_field  = 'VBELN'
                                              iv_value  = lv_id
                                              iv_label  = 'Pedido de venda'
                                    CHANGING  cs_result = rs_result ).
      RETURN.
    ENDIF.

    IF mo_reader->is_authorized( iv_vkorg = ls_header-vkorg
                                 iv_vtweg = ls_header-vtweg
                                 iv_spart = ls_header-spart
                                 iv_auart = ls_header-auart ) = abap_false.
      CONCATENATE 'Sem autorização para o pedido de venda' lv_id
                  '(objetos V_VBAK_VKO e V_VBAK_AAT)'
        INTO lv_message SEPARATED BY space.
      RAISE EXCEPTION TYPE zcx_rx_error
        EXPORTING iv_http_status = 403 iv_code = 'NOT_AUTHORIZED' iv_text = lv_message.
    ENDIF.

    ls_context = load_context( ls_header ).
    check_order( CHANGING cs_context = ls_context cs_result = rs_result ).
    check_rejected_items( EXPORTING is_context = ls_context CHANGING cs_result = rs_result ).
    check_not_relevant_items( EXPORTING is_context = ls_context CHANGING cs_result = rs_result ).
    add_facts( EXPORTING is_context = ls_context CHANGING cs_result = rs_result ).
    add_related( EXPORTING is_context = ls_context CHANGING cs_result = rs_result ).
    zcl_rx_result=>settle_status( CHANGING cs_result = rs_result ).
  ENDMETHOD.


  METHOD load_context.
    DATA ls_item TYPE zif_rx_sd_reader=>ty_item.
    DATA ls_followup TYPE zif_rx_sd_reader=>ty_followup.
    DATA lt_followups TYPE zif_rx_sd_reader=>ty_followups.

    rs_context-header = is_header.
    rs_context-s4 = mo_reader->is_s4( ).
    rs_context-items = mo_reader->get_items( is_header-vbeln ).
    rs_context-missing = mo_reader->get_missing_fields( is_header-vbeln ).
    rs_context-followups = mo_reader->get_followups( is_header-vbeln ).
    lt_followups = rs_context-followups.
    rs_context-billing_due = mo_reader->is_billing_due( iv_vbeln = is_header-vbeln it_followups = lt_followups ).

    " Indicadores que o leitor não preenche no cabeçalho: vêm dos itens e das remessas.
    LOOP AT rs_context-items INTO ls_item.
      IF ls_item-schedule_block IS NOT INITIAL.
        rs_context-header-state-schedule_blocked = abap_true.
      ENDIF.
      IF ls_item-billing_block IS NOT INITIAL.
        rs_context-header-state-item_billing_blocked = abap_true.
      ENDIF.
    ENDLOOP.
    LOOP AT rs_context-followups INTO ls_followup
        WHERE category = zif_rx_sd_reader=>c_followup-delivery.
      rs_context-header-state-delivery_count = rs_context-header-state-delivery_count + 1.
      IF rs_context-header-state-pending_delivery IS INITIAL
          AND ( ls_followup-goods_issue_status = 'A' OR ls_followup-goods_issue_status = 'B' ).
        rs_context-header-state-pending_delivery = ls_followup-doc_number.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD check_order.
    " Pedido já faturado: os bloqueios deixam de importar.
    IF cs_context-header-state-billing_status = 'C'.
      check_billed( EXPORTING is_context = cs_context CHANGING cs_result = cs_result ).
      RETURN.
    ENDIF.
    check_credit( CHANGING cs_context = cs_context cs_result = cs_result ).
    check_delivery_block( CHANGING cs_context = cs_context cs_result = cs_result ).
    check_schedule_block( CHANGING cs_context = cs_context cs_result = cs_result ).
    check_incomplete( CHANGING cs_context = cs_context cs_result = cs_result ).
    check_not_delivered( EXPORTING is_context = cs_context CHANGING cs_result = cs_result ).
    check_goods_issue( EXPORTING is_context = cs_context CHANGING cs_result = cs_result ).
    check_billing_block( EXPORTING is_context = cs_context CHANGING cs_result = cs_result ).
    check_billing_due( EXPORTING is_context = cs_context CHANGING cs_result = cs_result ).
  ENDMETHOD.


  METHOD check_credit.
    DATA lv_detail TYPE string.
    DATA lv_value TYPE string.
    DATA lv_customer TYPE string.
    DATA lv_tcode TYPE string.
    DATA lv_action TYPE string.
    DATA lv_label TYPE string.

    IF zcl_rx_sd_stage=>is_credit_blocked( cs_context-header-state-credit_status ) = abap_false.
      RETURN.
    ENDIF.
    cs_context-blocked = abap_true.

    lv_value = zcl_rx_format=>money( iv_amount   = cs_context-header-netwr
                                     iv_currency = cs_context-header-waerk ).
    lv_customer = zcl_rx_format=>alpha_out( cs_context-header-kunnr ).
    CONCATENATE 'A verificação de crédito não aprovou o pedido (valor' lv_value
                ') do cliente' lv_customer '.'
      INTO lv_detail SEPARATED BY space.
    REPLACE ' )' IN lv_detail WITH ')'.
    REPLACE ' .' IN lv_detail WITH '.'.

    " ECC: liberação em VKM3. S/4 com FSCM: decisão de crédito (validar, pendência V02).
    IF cs_context-s4 = abap_true.
      lv_tcode = 'UKM_MY_DCDS'.
      lv_action = 'Solicitar a decisão de crédito ao responsável (FSCM)'.
    ELSE.
      lv_tcode = 'VKM3'.
      lv_action = 'Solicitar a liberação ao responsável de crédito'.
    ENDIF.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'SD01.CREDIT_BLOCK'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = 'Pedido bloqueado por crédito'
                                          iv_detail   = lv_detail
                                          iv_tcode    = lv_tcode
                                          iv_action   = lv_action
                                CHANGING  cs_result   = cs_result ).
    IF cs_context-header-state-credit_status = 'C'.
      lv_label = 'Status de crédito: não aprovado, liberado em parte'.
    ELSE.
      lv_label = 'Status de crédito: não aprovado'.
    ENDIF.
    lv_value = cs_context-header-state-credit_status.
    zcl_rx_result=>add_evidence( EXPORTING iv_source = header_source( cs_context )
                                           iv_field  = 'CMGST'
                                           iv_value  = lv_value
                                           iv_label  = lv_label
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD check_delivery_block.
    DATA lv_detail TYPE string.
    DATA lv_label TYPE string.
    DATA lv_code TYPE string.
    DATA lv_text TYPE string.

    IF cs_context-header-state-delivery_block IS INITIAL.
      RETURN.
    ENDIF.
    cs_context-blocked = abap_true.
    lv_code = cs_context-header-state-delivery_block.
    lv_text = cs_context-header-delivery_block_text.

    lv_label = code_with_text( iv_code = lv_code iv_text = lv_text ).
    CONCATENATE 'O pedido está com o bloqueio de remessa' lv_label '.'
      INTO lv_detail SEPARATED BY space.
    REPLACE ' .' IN lv_detail WITH '.'.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'SD01.DELIVERY_BLOCK_HEADER'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = 'Bloqueio de remessa no cabeçalho'
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'VA02'
                                          iv_action   = 'Remover o bloqueio de remessa, se autorizado'
                                CHANGING  cs_result   = cs_result ).
    IF lv_text IS INITIAL.
      lv_label = 'Bloqueio de remessa'.
    ELSE.
      CONCATENATE 'Bloqueio de remessa:' lv_text INTO lv_label SEPARATED BY space.
    ENDIF.
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'VBAK'
                                           iv_field  = 'LIFSK'
                                           iv_value  = lv_code
                                           iv_label  = lv_label
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD check_schedule_block.
    DATA lt_numbers TYPE string_table.
    DATA lv_number TYPE string.
    DATA lv_list TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_label TYPE string.
    DATA lv_code TYPE string.
    FIELD-SYMBOLS <ls_item> TYPE zif_rx_sd_reader=>ty_item.

    LOOP AT cs_context-items ASSIGNING <ls_item> WHERE schedule_block IS NOT INITIAL.
      lv_number = item_no( <ls_item>-posnr ).
      APPEND lv_number TO lt_numbers.
    ENDLOOP.
    IF lt_numbers IS INITIAL.
      RETURN.
    ENDIF.
    cs_context-blocked = abap_true.

    lv_list = zcl_rx_sd_stage=>join_list( lt_numbers ).
    CONCATENATE 'Há bloqueio de remessa na divisão de remessa dos itens:' lv_list '.'
      INTO lv_detail SEPARATED BY space.
    REPLACE ' .' IN lv_detail WITH '.'.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'SD01.DELIVERY_BLOCK_SCHEDULE'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = 'Bloqueio de remessa na divisão'
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'VA02'
                                          iv_action   = 'Remover o bloqueio de remessa da divisão, se autorizado'
                                CHANGING  cs_result   = cs_result ).
    LOOP AT cs_context-items ASSIGNING <ls_item> WHERE schedule_block IS NOT INITIAL.
      lv_number = item_no( <ls_item>-posnr ).
      lv_code = <ls_item>-schedule_block.
      CONCATENATE 'Bloqueio de remessa do item' lv_number INTO lv_label SEPARATED BY space.
      IF <ls_item>-schedule_block_text IS NOT INITIAL.
        CONCATENATE lv_label ':' INTO lv_label.
        CONCATENATE lv_label <ls_item>-schedule_block_text INTO lv_label SEPARATED BY space.
      ENDIF.
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'VBEP'
                                             iv_field  = 'LIFSP'
                                             iv_value  = lv_code
                                             iv_label  = lv_label
                                   CHANGING  cs_result = cs_result ).
    ENDLOOP.
  ENDMETHOD.


  METHOD check_incomplete.
    DATA lt_texts TYPE string_table.
    DATA lv_text TYPE string.
    DATA lv_list TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_label TYPE string.
    DATA lv_status TYPE string.
    DATA lv_status_incomplete TYPE abap_bool.
    FIELD-SYMBOLS <ls_missing> TYPE zif_rx_sd_reader=>ty_missing_field.

    lv_status_incomplete = zcl_rx_sd_stage=>is_incomplete( cs_context-header-state-incompletion_status ).
    IF lv_status_incomplete = abap_false AND cs_context-missing IS INITIAL.
      RETURN.
    ENDIF.
    cs_context-blocked = abap_true.

    LOOP AT cs_context-missing ASSIGNING <ls_missing>.
      lv_text = missing_text( <ls_missing> ).
      APPEND lv_text TO lt_texts.
    ENDLOOP.
    IF lt_texts IS INITIAL.
      lv_detail = 'O status de incompletude do pedido indica dados obrigatórios faltantes para remessa e faturamento.'.
    ELSE.
      lv_list = zcl_rx_sd_stage=>join_list( lt_texts ).
      CONCATENATE 'Faltam dados obrigatórios para remessa e faturamento:' lv_list '.'
        INTO lv_detail SEPARATED BY space.
      REPLACE ' .' IN lv_detail WITH '.'.
    ENDIF.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'SD01.INCOMPLETE'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = 'Pedido incompleto'
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'VA02'
                                          iv_action   = 'Completar os dados pelo log de incompletude'
                                CHANGING  cs_result   = cs_result ).
    LOOP AT cs_context-missing ASSIGNING <ls_missing>.
      lv_text = missing_text( <ls_missing> ).
      CONCATENATE 'Campo faltante:' lv_text INTO lv_label SEPARATED BY space.
      lv_status = <ls_missing>-field_name.
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'VBUV'
                                             iv_field  = 'FDNAM'
                                             iv_value  = lv_status
                                             iv_label  = lv_label
                                   CHANGING  cs_result = cs_result ).
    ENDLOOP.
    IF lv_status_incomplete = abap_true.
      lv_text = status_text( cs_context-header-state-incompletion_status ).
      CONCATENATE 'Status de incompletude:' lv_text INTO lv_label SEPARATED BY space.
      lv_status = cs_context-header-state-incompletion_status.
      zcl_rx_result=>add_evidence( EXPORTING iv_source = header_source( cs_context )
                                             iv_field  = 'UVALL'
                                             iv_value  = lv_status
                                             iv_label  = lv_label
                                   CHANGING  cs_result = cs_result ).
    ENDIF.
  ENDMETHOD.


  METHOD check_not_delivered.
    DATA lv_detail TYPE string.
    DATA lv_value TYPE string.
    DATA lv_label TYPE string.
    DATA lv_text TYPE string.

    " Só vale a pena avisar quando nada do que vem antes explica a falta de remessa.
    IF is_context-blocked = abap_true
        OR zcl_rx_sd_stage=>has_no_delivery( is_context-header-state ) = abap_false.
      RETURN.
    ENDIF.
    lv_detail = 'Nenhum bloqueio impede a remessa, mas ela ainda não foi criada.'.
    CONCATENATE lv_detail 'Confira a lista de remessas.' INTO lv_detail SEPARATED BY space.
    zcl_rx_result=>add_finding(
      EXPORTING iv_code     = 'SD01.NOT_DELIVERED'
                iv_severity = zif_rx_types=>c_severity-warning
                iv_title    = 'Remessa ainda não criada'
                iv_detail   = lv_detail
                iv_tcode    = 'VL01N'
                iv_action   = 'Criar a remessa do pedido ou conferir a lista de remessas pendentes'
      CHANGING  cs_result   = cs_result ).
    lv_value = is_context-header-state-delivery_status.
    lv_text = status_text( is_context-header-state-delivery_status ).
    CONCATENATE 'Status de remessa:' lv_text INTO lv_label SEPARATED BY space.
    zcl_rx_result=>add_evidence( EXPORTING iv_source = header_source( is_context )
                                           iv_field  = 'LFSTK'
                                           iv_value  = lv_value
                                           iv_label  = lv_label
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD check_goods_issue.
    DATA lt_deliveries TYPE string_table.
    DATA lv_number TYPE string.
    DATA lv_list TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_label TYPE string.
    DATA lv_value TYPE string.
    DATA lv_text TYPE string.
    DATA lv_action TYPE string.
    FIELD-SYMBOLS <ls_followup> TYPE zif_rx_sd_reader=>ty_followup.

    LOOP AT is_context-followups ASSIGNING <ls_followup>
        WHERE category = zif_rx_sd_reader=>c_followup-delivery
          AND ( goods_issue_status = 'A' OR goods_issue_status = 'B' ).
      lv_number = zcl_rx_format=>alpha_out( <ls_followup>-doc_number ).
      APPEND lv_number TO lt_deliveries.
    ENDLOOP.
    IF lt_deliveries IS INITIAL.
      RETURN.
    ENDIF.

    lv_list = zcl_rx_sd_stage=>join_list( lt_deliveries ).
    IF lines( lt_deliveries ) = 1.
      CONCATENATE 'A remessa' lv_list 'foi criada, mas a saída de mercadoria não foi lançada.'
                  'O faturamento depende dela. Rode o diagnóstico SD-02 para a remessa.'
        INTO lv_detail SEPARATED BY space.
    ELSE.
      CONCATENATE 'As remessas' lv_list 'foram criadas, mas a saída de mercadoria não foi lançada.'
                  'O faturamento depende dela. Rode o diagnóstico SD-02 para cada remessa.'
        INTO lv_detail SEPARATED BY space.
    ENDIF.
    READ TABLE lt_deliveries INTO lv_number INDEX 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    CONCATENATE 'Lançar a saída de mercadoria da remessa' lv_number INTO lv_action SEPARATED BY space.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'SD01.GOODS_ISSUE_PENDING'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = 'Remessa sem saída de mercadoria'
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'VL02N'
                                          iv_action   = lv_action
                                CHANGING  cs_result   = cs_result ).
    LOOP AT is_context-followups ASSIGNING <ls_followup>
        WHERE category = zif_rx_sd_reader=>c_followup-delivery
          AND ( goods_issue_status = 'A' OR goods_issue_status = 'B' ).
      lv_number = zcl_rx_format=>alpha_out( <ls_followup>-doc_number ).
      CONCATENATE 'Documento subsequente: remessa' lv_number INTO lv_label SEPARATED BY space.
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'VBFA'
                                             iv_field  = 'VBTYP_N'
                                             iv_value  = zif_rx_sd_reader=>c_followup-delivery
                                             iv_label  = lv_label
                                   CHANGING  cs_result = cs_result ).
      lv_text = status_text( <ls_followup>-goods_issue_status ).
      CONCATENATE 'Status de saída de mercadoria:' lv_text INTO lv_label SEPARATED BY space.
      lv_value = <ls_followup>-goods_issue_status.
      zcl_rx_result=>add_evidence( EXPORTING iv_source = delivery_source( is_context )
                                             iv_field  = 'WBSTK'
                                             iv_value  = lv_value
                                             iv_label  = lv_label
                                   CHANGING  cs_result = cs_result ).
    ENDLOOP.
  ENDMETHOD.


  METHOD check_billing_block.
    DATA lt_numbers TYPE string_table.
    DATA lv_part TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_label TYPE string.
    DATA lv_code TYPE string.
    DATA lv_number TYPE string.
    DATA lv_list TYPE string.
    FIELD-SYMBOLS <ls_item> TYPE zif_rx_sd_reader=>ty_item.

    IF is_context-header-state-billing_block IS INITIAL
        AND is_context-header-state-item_billing_blocked = abap_false.
      RETURN.
    ENDIF.

    IF is_context-header-state-billing_block IS NOT INITIAL.
      lv_code = is_context-header-state-billing_block.
      lv_label = code_with_text( iv_code = lv_code iv_text = is_context-header-state-billing_block_text ).
      CONCATENATE 'O pedido está com o bloqueio de faturamento' lv_label '.'
        INTO lv_detail SEPARATED BY space.
      REPLACE ' .' IN lv_detail WITH '.'.
    ENDIF.
    LOOP AT is_context-items ASSIGNING <ls_item> WHERE billing_block IS NOT INITIAL.
      lv_number = item_no( <ls_item>-posnr ).
      APPEND lv_number TO lt_numbers.
    ENDLOOP.
    IF lt_numbers IS NOT INITIAL.
      lv_list = zcl_rx_sd_stage=>join_list( lt_numbers ).
      CONCATENATE 'Há bloqueio de faturamento nos itens:' lv_list '.'
        INTO lv_part SEPARATED BY space.
      REPLACE ' .' IN lv_part WITH '.'.
      CONCATENATE lv_detail lv_part INTO lv_detail SEPARATED BY space.
    ENDIF.
    CONDENSE lv_detail.

    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'SD01.BILLING_BLOCK'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = 'Bloqueio de faturamento'
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'VA02'
                                          iv_action   = 'Verificar o motivo e remover o bloqueio, se autorizado'
                                CHANGING  cs_result   = cs_result ).
    IF is_context-header-state-billing_block IS NOT INITIAL.
      lv_code = is_context-header-state-billing_block.
      IF is_context-header-state-billing_block_text IS INITIAL.
        lv_label = 'Bloqueio de faturamento'.
      ELSE.
        CONCATENATE 'Bloqueio de faturamento:' is_context-header-state-billing_block_text
          INTO lv_label SEPARATED BY space.
      ENDIF.
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'VBAK'
                                             iv_field  = 'FAKSK'
                                             iv_value  = lv_code
                                             iv_label  = lv_label
                                   CHANGING  cs_result = cs_result ).
    ENDIF.
    LOOP AT is_context-items ASSIGNING <ls_item> WHERE billing_block IS NOT INITIAL.
      lv_number = item_no( <ls_item>-posnr ).
      lv_code = <ls_item>-billing_block.
      CONCATENATE 'Bloqueio de faturamento do item' lv_number INTO lv_label SEPARATED BY space.
      IF <ls_item>-billing_block_text IS NOT INITIAL.
        CONCATENATE lv_label ':' INTO lv_label.
        CONCATENATE lv_label <ls_item>-billing_block_text INTO lv_label SEPARATED BY space.
      ENDIF.
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'VBAP'
                                             iv_field  = 'FAKSP'
                                             iv_value  = lv_code
                                             iv_label  = lv_label
                                   CHANGING  cs_result = cs_result ).
    ENDLOOP.
  ENDMETHOD.


  METHOD check_billing_due.
    DATA lv_order TYPE string.
    DATA lv_detail TYPE string.

    IF is_context-billing_due = abap_false
        OR is_context-header-state-billing_block IS NOT INITIAL
        OR is_context-header-state-item_billing_blocked = abap_true
        OR is_context-header-state-pending_delivery IS NOT INITIAL
        OR zcl_rx_sd_stage=>is_billing_open( is_context-header-state-billing_status ) = abap_false.
      RETURN.
    ENDIF.
    lv_order = zcl_rx_format=>alpha_out( is_context-header-vbeln ).
    lv_detail = 'Nada bloqueia o pedido: ele está na lista de faturamento.'.
    CONCATENATE lv_detail 'Falta apenas executar o faturamento.' INTO lv_detail SEPARATED BY space.
    zcl_rx_result=>add_finding(
      EXPORTING iv_code     = 'SD01.BILLING_DUE'
                iv_severity = zif_rx_types=>c_severity-info
                iv_title    = 'Pedido na lista de faturamento'
                iv_detail   = lv_detail
                iv_tcode    = 'VF04'
                iv_action   = 'Processar a lista de faturamento'
      CHANGING  cs_result   = cs_result ).
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'VKDFS'
                                           iv_field  = 'VBELN'
                                           iv_value  = lv_order
                                           iv_label  = 'Documento na lista de faturamento'
                                 CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD check_billed.
    DATA lt_invoices TYPE string_table.
    DATA lt_origins TYPE string_table.
    DATA lv_number TYPE string.
    DATA lv_list TYPE string.
    DATA lv_origins TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_label TYPE string.
    DATA lv_action TYPE string.
    DATA lv_order TYPE string.
    FIELD-SYMBOLS <ls_followup> TYPE zif_rx_sd_reader=>ty_followup.

    lv_order = zcl_rx_format=>alpha_out( is_context-header-vbeln ).
    LOOP AT is_context-followups ASSIGNING <ls_followup>
        WHERE category = zif_rx_sd_reader=>c_followup-invoice.
      lv_number = zcl_rx_format=>alpha_out( <ls_followup>-doc_number ).
      APPEND lv_number TO lt_invoices.
      lv_number = zcl_rx_format=>alpha_out( <ls_followup>-predecessor ).
      IF lv_number <> lv_order.
        READ TABLE lt_origins WITH KEY table_line = lv_number TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND lv_number TO lt_origins.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF lt_invoices IS INITIAL.
      lv_detail = 'O faturamento do pedido está concluído,'.
      CONCATENATE lv_detail 'mas nenhuma fatura foi encontrada no fluxo de documentos.'
        INTO lv_detail SEPARATED BY space.
      zcl_rx_result=>add_finding(
        EXPORTING iv_code     = 'SD01.ALREADY_BILLED'
                  iv_severity = zif_rx_types=>c_severity-info
                  iv_title    = 'Pedido já faturado'
                  iv_detail   = lv_detail
        CHANGING  cs_result   = cs_result ).
      RETURN.
    ENDIF.

    lv_list = zcl_rx_sd_stage=>join_list( lt_invoices ).
    IF lines( lt_invoices ) = 1.
      CONCATENATE 'O pedido foi faturado pela fatura' lv_list INTO lv_detail SEPARATED BY space.
    ELSE.
      CONCATENATE 'O pedido foi faturado pelas faturas' lv_list INTO lv_detail SEPARATED BY space.
    ENDIF.
    IF lt_origins IS NOT INITIAL.
      lv_origins = zcl_rx_sd_stage=>join_list( lt_origins ).
      IF lines( lt_origins ) = 1.
        CONCATENATE lv_detail ', a partir da remessa' lv_origins INTO lv_detail SEPARATED BY space.
      ELSE.
        CONCATENATE lv_detail ', a partir das remessas' lv_origins INTO lv_detail SEPARATED BY space.
      ENDIF.
      REPLACE ' ,' IN lv_detail WITH ','.
    ENDIF.
    CONCATENATE lv_detail '.' INTO lv_detail.

    READ TABLE lt_invoices INTO lv_number INDEX 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    CONCATENATE 'Exibir a fatura' lv_number INTO lv_action SEPARATED BY space.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'SD01.ALREADY_BILLED'
                                          iv_severity = zif_rx_types=>c_severity-info
                                          iv_title    = 'Pedido já faturado'
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'VF03'
                                          iv_action   = lv_action
                                CHANGING  cs_result   = cs_result ).
    LOOP AT lt_invoices INTO lv_number.
      CONCATENATE 'Documento subsequente: fatura' lv_number INTO lv_label SEPARATED BY space.
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'VBFA'
                                             iv_field  = 'VBTYP_N'
                                             iv_value  = zif_rx_sd_reader=>c_followup-invoice
                                             iv_label  = lv_label
                                   CHANGING  cs_result = cs_result ).
    ENDLOOP.
  ENDMETHOD.


  METHOD check_rejected_items.
    DATA lv_number TYPE string.
    DATA lv_title TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_reason TYPE string.
    DATA lv_label TYPE string.
    DATA lv_code TYPE string.
    FIELD-SYMBOLS <ls_item> TYPE zif_rx_sd_reader=>ty_item.

    LOOP AT is_context-items ASSIGNING <ls_item> WHERE rejection_reason IS NOT INITIAL.
      lv_number = item_no( <ls_item>-posnr ).
      lv_code = <ls_item>-rejection_reason.
      lv_reason = lv_code.
      IF <ls_item>-rejection_text IS NOT INITIAL.
        CONCATENATE lv_reason ':' INTO lv_reason.
        CONCATENATE lv_reason <ls_item>-rejection_text INTO lv_reason SEPARATED BY space.
      ENDIF.
      CONCATENATE 'Item' lv_number 'recusado' INTO lv_title SEPARATED BY space.
      CONCATENATE 'O item' lv_number 'foi recusado (motivo' lv_reason INTO lv_detail SEPARATED BY space.
      CONCATENATE lv_detail ')' INTO lv_detail.
      CONCATENATE lv_detail 'e não será faturado.' INTO lv_detail SEPARATED BY space.
      zcl_rx_result=>add_finding( EXPORTING iv_code     = 'SD01.ITEM_REJECTED'
                                            iv_severity = zif_rx_types=>c_severity-info
                                            iv_title    = lv_title
                                            iv_detail   = lv_detail
                                            iv_tcode    = 'VA02'
                                            iv_action   = 'Se a recusa foi indevida, remover o motivo de recusa'
                                  CHANGING  cs_result   = cs_result ).
      CONCATENATE 'Motivo de recusa do item' lv_number INTO lv_label SEPARATED BY space.
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'VBAP'
                                             iv_field  = 'ABGRU'
                                             iv_value  = lv_code
                                             iv_label  = lv_label
                                   CHANGING  cs_result = cs_result ).
    ENDLOOP.
  ENDMETHOD.


  METHOD check_not_relevant_items.
    DATA lt_numbers TYPE string_table.
    DATA lv_number TYPE string.
    DATA lv_list TYPE string.
    DATA lv_detail TYPE string.
    DATA lv_label TYPE string.
    DATA lv_category TYPE string.
    DATA lv_title TYPE string.
    FIELD-SYMBOLS <ls_item> TYPE zif_rx_sd_reader=>ty_item.

    " Itens recusados já têm o próprio achado; os demais sem FKREL nunca serão faturados.
    LOOP AT is_context-items ASSIGNING <ls_item>
        WHERE rejection_reason IS INITIAL AND billing_relevant = abap_false.
      lv_number = item_no( <ls_item>-posnr ).
      APPEND lv_number TO lt_numbers.
    ENDLOOP.
    IF lt_numbers IS INITIAL.
      RETURN.
    ENDIF.

    lv_list = zcl_rx_sd_stage=>join_list( lt_numbers ).
    IF lines( lt_numbers ) = 1.
      lv_title = 'Item sem relevância para faturamento'.
      CONCATENATE 'O item' lv_list 'não é relevante para faturamento (categoria de item).'
        'Ele não será faturado.'
        INTO lv_detail SEPARATED BY space.
    ELSE.
      lv_title = 'Itens sem relevância para faturamento'.
      CONCATENATE 'Os itens' lv_list 'não são relevantes para faturamento (categoria de item).'
        'Eles não serão faturados.'
        INTO lv_detail SEPARATED BY space.
    ENDIF.
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'SD01.NOT_BILLING_RELEVANT'
                                          iv_severity = zif_rx_types=>c_severity-info
                                          iv_title    = lv_title
                                          iv_detail   = lv_detail
                                          iv_tcode    = 'VOV7'
                                          iv_action   = 'Rever a categoria de item com o consultor SD'
                                CHANGING  cs_result   = cs_result ).
    LOOP AT is_context-items ASSIGNING <ls_item>
        WHERE rejection_reason IS INITIAL AND billing_relevant = abap_false.
      lv_number = item_no( <ls_item>-posnr ).
      lv_category = <ls_item>-item_category.
      CONCATENATE 'Item' lv_number 'com categoria' lv_category 'sem relevância para faturamento'
        INTO lv_label SEPARATED BY space.
      zcl_rx_result=>add_evidence( EXPORTING iv_source = 'TVAP'
                                             iv_field  = 'FKREL'
                                             iv_value  = ''
                                             iv_label  = lv_label
                                   CHANGING  cs_result = cs_result ).
    ENDLOOP.
  ENDMETHOD.


  METHOD add_facts.
    DATA lv_stage TYPE string.
    DATA lv_value TYPE string.

    lv_value = customer_text( is_context-header ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'customer' iv_label = 'Cliente' iv_value = lv_value
                             CHANGING cs_result = cs_result ).
    lv_value = zcl_rx_format=>money( iv_amount   = is_context-header-netwr
                                     iv_currency = is_context-header-waerk ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'netValue' iv_label = 'Valor líquido' iv_value = lv_value
                             CHANGING cs_result = cs_result ).
    lv_stage = zcl_rx_sd_stage=>classify( is_context-header-state ).
    lv_value = zcl_rx_sd_stage=>label( lv_stage ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'stage' iv_label = 'Etapa' iv_value = lv_value
                             CHANGING cs_result = cs_result ).
    lv_value = is_context-header-vkorg.
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'salesOrg' iv_label = 'Org. de vendas' iv_value = lv_value
                             CHANGING cs_result = cs_result ).
    lv_value = zcl_rx_format=>date_iso( is_context-header-erdat ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'createdOn' iv_label = 'Criado em' iv_value = lv_value
                             CHANGING cs_result = cs_result ).
    lv_value = zcl_rx_format=>date_iso( is_context-header-vdatu ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'requestedDate' iv_label = 'Data desejada pelo cliente'
                                       iv_value = lv_value
                             CHANGING cs_result = cs_result ).
    lv_value = zcl_rx_format=>int( is_context-header-item_count ).
    zcl_rx_result=>add_fact( EXPORTING iv_id = 'items' iv_label = 'Itens' iv_value = lv_value
                             CHANGING cs_result = cs_result ).
  ENDMETHOD.


  METHOD add_related.
    DATA lv_number TYPE string.
    FIELD-SYMBOLS <ls_followup> TYPE zif_rx_sd_reader=>ty_followup.

    " Remessas primeiro, depois as faturas (como no sap-mock).
    LOOP AT is_context-followups ASSIGNING <ls_followup>
        WHERE category = zif_rx_sd_reader=>c_followup-delivery.
      lv_number = zcl_rx_format=>alpha_out( <ls_followup>-doc_number ).
      zcl_rx_result=>add_related( EXPORTING iv_kind = 'DELIVERY' iv_id = lv_number
                                  CHANGING  cs_result = cs_result ).
    ENDLOOP.
    LOOP AT is_context-followups ASSIGNING <ls_followup>
        WHERE category = zif_rx_sd_reader=>c_followup-invoice.
      lv_number = zcl_rx_format=>alpha_out( <ls_followup>-doc_number ).
      zcl_rx_result=>add_related( EXPORTING iv_kind = 'BILLING_DOCUMENT' iv_id = lv_number
                                  CHANGING  cs_result = cs_result ).
    ENDLOOP.
  ENDMETHOD.


  METHOD header_source.
    IF is_context-s4 = abap_true.
      rv_source = 'VBAK'.
    ELSE.
      rv_source = 'VBUK'.
    ENDIF.
  ENDMETHOD.


  METHOD delivery_source.
    IF is_context-s4 = abap_true.
      rv_source = 'LIKP'.
    ELSE.
      rv_source = 'VBUK'.
    ENDIF.
  ENDMETHOD.


  METHOD customer_text.
    DATA lv_code TYPE string.
    DATA lv_name TYPE string.

    lv_code = zcl_rx_format=>alpha_out( is_header-kunnr ).
    lv_name = is_header-customer_name.
    IF lv_name IS INITIAL.
      rv_text = lv_code.
    ELSE.
      CONCATENATE lv_code '·' lv_name INTO rv_text SEPARATED BY space.
    ENDIF.
  ENDMETHOD.


  METHOD code_with_text.
    DATA lv_text TYPE string.

    rv_text = iv_code.
    lv_text = iv_text.
    IF lv_text IS NOT INITIAL.
      CONCATENATE '(' lv_text ')' INTO lv_text.
      CONCATENATE rv_text lv_text INTO rv_text SEPARATED BY space.
    ENDIF.
  ENDMETHOD.


  METHOD item_no.
    rv_text = zcl_rx_format=>alpha_out( iv_posnr ).
  ENDMETHOD.


  METHOD status_text.
    CASE iv_status.
      WHEN 'A'.
        rv_text = 'não processado'.
      WHEN 'B'.
        rv_text = 'parcialmente processado'.
      WHEN 'C'.
        rv_text = 'concluído'.
      WHEN OTHERS.
        rv_text = 'não relevante'.
    ENDCASE.
  ENDMETHOD.


  METHOD missing_text.
    DATA lv_item TYPE string.

    rv_text = zcl_rx_sd_stage=>lower_first( is_missing-field_text ).
    IF rv_text IS INITIAL.
      rv_text = is_missing-field_name.
    ENDIF.
    " Faltas de item dizem em qual item (000000 = cabeçalho).
    IF is_missing-posnr IS NOT INITIAL AND is_missing-posnr <> '000000'.
      lv_item = item_no( is_missing-posnr ).
      CONCATENATE rv_text '(item' lv_item ')' INTO rv_text SEPARATED BY space.
      REPLACE ' )' IN rv_text WITH ')'.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
