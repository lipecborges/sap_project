"! Regras comuns de vendas (SD) para SD-01 e SD-10: em que etapa o pedido está
"! parado e por quê. A ordem é a cadeia do processo: crédito → remessa →
"! saída de mercadoria → faturamento (a primeira etapa travada vence).
CLASS zcl_rx_sd_stage DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Códigos de etapa (iguais ao enum SdStage do contrato, mais COMPLETED).
    CONSTANTS:
      BEGIN OF c_stage,
        credit      TYPE string VALUE 'CREDIT',
        delivery    TYPE string VALUE 'DELIVERY',
        goods_issue TYPE string VALUE 'GOODS_ISSUE',
        billing     TYPE string VALUE 'BILLING',
        completed   TYPE string VALUE 'COMPLETED',
      END OF c_stage.

    "! Primeira etapa travada; COMPLETED se já faturado; vazio se nada trava.
    CLASS-METHODS classify
      IMPORTING is_state        TYPE zif_rx_sd_reader=>ty_order_state
      RETURNING VALUE(rv_stage) TYPE string.

    "! Nome da etapa em português (Crédito, Remessa, Saída de mercadoria…).
    CLASS-METHODS label
      IMPORTING iv_stage       TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

    "! Motivo principal em linguagem de negócio.
    CLASS-METHODS reason
      IMPORTING is_state       TYPE zif_rx_sd_reader=>ty_order_state
                iv_stage       TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

    "! CMGST B ou C: crédito não aprovado (validar valores, pendência V01).
    CLASS-METHODS is_credit_blocked
      IMPORTING iv_status         TYPE csequence
      RETURNING VALUE(rv_blocked) TYPE abap_bool.

    "! UVALL A ou B: pedido incompleto.
    CLASS-METHODS is_incomplete
      IMPORTING iv_status            TYPE csequence
      RETURNING VALUE(rv_incomplete) TYPE abap_bool.

    "! Sem remessa criada e o status de remessa do pedido ainda é A/B.
    CLASS-METHODS has_no_delivery
      IMPORTING is_state     TYPE zif_rx_sd_reader=>ty_order_state
      RETURNING VALUE(rv_no) TYPE abap_bool.

    "! Status de faturamento A ou B: ainda há o que faturar.
    CLASS-METHODS is_billing_open
      IMPORTING iv_status      TYPE csequence
      RETURNING VALUE(rv_open) TYPE abap_bool.

    "! Primeira letra minúscula ("Verificar preço" → "verificar preço").
    CLASS-METHODS lower_first
      IMPORTING iv_text        TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

    "! "a, b e c".
    CLASS-METHODS join_list
      IMPORTING it_items       TYPE string_table
      RETURNING VALUE(rv_text) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS is_delivery_stage
      IMPORTING is_state        TYPE zif_rx_sd_reader=>ty_order_state
      RETURNING VALUE(rv_stage) TYPE abap_bool.

    CLASS-METHODS delivery_reason
      IMPORTING is_state       TYPE zif_rx_sd_reader=>ty_order_state
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS billing_reason
      IMPORTING is_state       TYPE zif_rx_sd_reader=>ty_order_state
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.



CLASS zcl_rx_sd_stage IMPLEMENTATION.

  METHOD classify.
    IF is_state-billing_status = 'C'.
      rv_stage = c_stage-completed.
    ELSEIF is_credit_blocked( is_state-credit_status ) = abap_true.
      rv_stage = c_stage-credit.
    ELSEIF is_delivery_stage( is_state ) = abap_true.
      rv_stage = c_stage-delivery.
    ELSEIF is_state-pending_delivery IS NOT INITIAL.
      rv_stage = c_stage-goods_issue.
    ELSEIF is_state-billing_block IS NOT INITIAL
        OR is_state-item_billing_blocked = abap_true
        OR is_billing_open( is_state-billing_status ) = abap_true.
      rv_stage = c_stage-billing.
    ENDIF.
  ENDMETHOD.


  METHOD label.
    CASE iv_stage.
      WHEN c_stage-credit.
        rv_text = 'Crédito'.
      WHEN c_stage-delivery.
        rv_text = 'Remessa'.
      WHEN c_stage-goods_issue.
        rv_text = 'Saída de mercadoria'.
      WHEN c_stage-billing.
        rv_text = 'Faturamento'.
      WHEN c_stage-completed.
        rv_text = 'Concluído'.
      WHEN OTHERS.
        rv_text = 'Sem etapa travada'.
    ENDCASE.
  ENDMETHOD.


  METHOD reason.
    DATA lv_delivery TYPE string.

    CASE iv_stage.
      WHEN c_stage-credit.
        rv_text = 'Bloqueio de crédito'.
      WHEN c_stage-delivery.
        rv_text = delivery_reason( is_state ).
      WHEN c_stage-goods_issue.
        lv_delivery = zcl_rx_format=>alpha_out( is_state-pending_delivery ).
        CONCATENATE 'Remessa' lv_delivery 'sem saída de mercadoria'
          INTO rv_text SEPARATED BY space.
      WHEN c_stage-billing.
        rv_text = billing_reason( is_state ).
      WHEN c_stage-completed.
        rv_text = 'Faturado'.
    ENDCASE.
  ENDMETHOD.


  METHOD is_credit_blocked.
    IF iv_status = 'B' OR iv_status = 'C'.
      rv_blocked = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD is_incomplete.
    IF iv_status = 'A' OR iv_status = 'B'.
      rv_incomplete = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD has_no_delivery.
    IF is_state-delivery_count = 0
        AND ( is_state-delivery_status = 'A' OR is_state-delivery_status = 'B' ).
      rv_no = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD is_billing_open.
    IF iv_status = 'A' OR iv_status = 'B'.
      rv_open = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD lower_first.
    DATA lv_first TYPE string.
    DATA lv_rest TYPE string.

    IF iv_text IS INITIAL.
      RETURN.
    ENDIF.
    rv_text = iv_text.
    lv_first = rv_text(1).
    TRANSLATE lv_first TO LOWER CASE.
    lv_rest = rv_text+1.
    CONCATENATE lv_first lv_rest INTO rv_text.
  ENDMETHOD.


  METHOD join_list.
    DATA lv_item TYPE string.
    DATA lv_count TYPE i.
    DATA lv_index TYPE i.

    lv_count = lines( it_items ).
    LOOP AT it_items INTO lv_item.
      lv_index = sy-tabix.
      IF lv_index > 1.
        " Antes do último item entra "e"; antes dos demais, vírgula.
        IF lv_index < lv_count.
          CONCATENATE rv_text ',' INTO rv_text.
        ELSE.
          CONCATENATE rv_text 'e' INTO rv_text SEPARATED BY space.
        ENDIF.
        CONCATENATE rv_text lv_item INTO rv_text SEPARATED BY space.
      ELSE.
        rv_text = lv_item.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD is_delivery_stage.
    IF is_state-delivery_block IS NOT INITIAL
        OR is_state-schedule_blocked = abap_true
        OR is_incomplete( is_state-incompletion_status ) = abap_true
        OR has_no_delivery( is_state ) = abap_true.
      rv_stage = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD delivery_reason.
    DATA lt_parts TYPE string_table.
    DATA lv_part TYPE string.

    IF is_state-delivery_block IS NOT INITIAL OR is_state-schedule_blocked = abap_true.
      APPEND 'Bloqueio de remessa' TO lt_parts.
    ENDIF.
    IF is_incomplete( is_state-incompletion_status ) = abap_true.
      APPEND 'Pedido incompleto' TO lt_parts.
    ENDIF.
    IF lt_parts IS INITIAL.
      rv_text = 'Remessa ainda não criada'.
      RETURN.
    ENDIF.
    LOOP AT lt_parts INTO lv_part.
      IF sy-tabix = 1.
        rv_text = lv_part.
      ELSE.
        lv_part = lower_first( lv_part ).
        CONCATENATE rv_text '+' lv_part INTO rv_text SEPARATED BY space.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD billing_reason.
    DATA lv_text TYPE string.

    IF is_state-billing_block IS NOT INITIAL.
      rv_text = 'Bloqueio de faturamento'.
      IF is_state-billing_block_text IS NOT INITIAL.
        lv_text = lower_first( is_state-billing_block_text ).
        CONCATENATE '(' lv_text ')' INTO lv_text.
        CONCATENATE rv_text lv_text INTO rv_text SEPARATED BY space.
      ENDIF.
    ELSEIF is_state-item_billing_blocked = abap_true.
      rv_text = 'Bloqueio de faturamento em item'.
    ELSE.
      rv_text = 'Aguardando faturamento'.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
