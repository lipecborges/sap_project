"! Classificação de ordens de produção (catálogo, PP-03 "Situação resumida"):
"! uma situação principal, sinalizadores e dias de atraso de início e de fim.
"! Mesma regra do simulador (services/sap-mock/src/pp/classify.ts).
"! A lógica usa a abreviação EN do status de sistema (TJ02T), nunca o texto no idioma do usuário.
"! O "Aprovada" e o bloqueio de liberação vêm do mapeamento da ZRX_PPSTAT_MAP (fonte a definir, V07).
CLASS zcl_rx_pp_status_map DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_classification,
        situation         TYPE string,
        flags             TYPE string_table,
        start_delay_days  TYPE i,
        finish_delay_days TYPE i,
      END OF ty_classification.

    CONSTANTS:
      BEGIN OF c_status,
        crtd TYPE string VALUE 'CRTD',
        rel  TYPE string VALUE 'REL',
        prel TYPE string VALUE 'PREL',
        pcnf TYPE string VALUE 'PCNF',
        cnf  TYPE string VALUE 'CNF',
        pdlv TYPE string VALUE 'PDLV',
        dlv  TYPE string VALUE 'DLV',
        teco TYPE string VALUE 'TECO',
        clsd TYPE string VALUE 'CLSD',
        dlfl TYPE string VALUE 'DLFL',
        lkd  TYPE string VALUE 'LKD',
        mspt TYPE string VALUE 'MSPT',
      END OF c_status.

    CONSTANTS:
      BEGIN OF c_situation,
        deleted               TYPE string VALUE 'DELETED',
        closed                TYPE string VALUE 'CLOSED',
        technically_completed TYPE string VALUE 'TECHNICALLY_COMPLETED',
        delivered             TYPE string VALUE 'DELIVERED',
        partially_delivered   TYPE string VALUE 'PARTIALLY_DELIVERED',
        confirmed             TYPE string VALUE 'CONFIRMED',
        in_production         TYPE string VALUE 'IN_PRODUCTION',
        released              TYPE string VALUE 'RELEASED',
        approved              TYPE string VALUE 'APPROVED',
        created               TYPE string VALUE 'CREATED',
      END OF c_situation.

    CONSTANTS:
      BEGIN OF c_flag,
        late_start             TYPE string VALUE 'LATE_START',
        late_finish            TYPE string VALUE 'LATE_FINISH',
        operation_late         TYPE string VALUE 'OPERATION_LATE',
        missing_parts          TYPE string VALUE 'MISSING_PARTS',
        locked                 TYPE string VALUE 'LOCKED',
        confirmed_not_received TYPE string VALUE 'CONFIRMED_NOT_RECEIVED',
        sales_order_at_risk    TYPE string VALUE 'SALES_ORDER_AT_RISK',
        reversed_confirmation  TYPE string VALUE 'REVERSED_CONFIRMATION',
      END OF c_flag.

    " Papéis que a ZRX_PPSTAT_MAP (coluna SITUATION) pode atribuir a um status.
    CONSTANTS:
      BEGIN OF c_role,
        approved       TYPE string VALUE 'APPROVED',
        blocks_release TYPE string VALUE 'BLOCKS_RELEASE',
      END OF c_role.

    CONSTANTS:
      BEGIN OF c_source,
        system_status TYPE string VALUE 'SYSTEM_STATUS',
        user_status   TYPE string VALUE 'USER_STATUS',
        field         TYPE string VALUE 'FIELD',
      END OF c_source.

    "! Janela (dias) em que um estorno de apontamento ainda é considerado recente.
    CONSTANTS c_reversal_window_days TYPE i VALUE 7.

    "! IV_TODAY é a data de referência dos atrasos; IV_TOLERANCE_DAYS vem de PP_LATE_TOLERANCE_DAYS.
    METHODS constructor
      IMPORTING iv_today                TYPE d
                iv_tolerance_days       TYPE i DEFAULT 0
                it_mapping              TYPE zif_rx_pp_reader=>ty_status_maps OPTIONAL
                iv_reversal_window_days TYPE i DEFAULT c_reversal_window_days.

    "! Classifica uma ordem. As tabelas podem trazer outras ordens: só as linhas da ordem são usadas.
    METHODS classify
      IMPORTING is_order                 TYPE zif_rx_pp_reader=>ty_order
                it_operations            TYPE zif_rx_pp_reader=>ty_operations
                it_components            TYPE zif_rx_pp_reader=>ty_components
                it_confirmations         TYPE zif_rx_pp_reader=>ty_confirmations
      RETURNING VALUE(rs_classification) TYPE ty_classification.

    "! Situação principal (avaliada de cima para baixo); "Aprovada" depende do mapeamento.
    METHODS situation_of
      IMPORTING is_order            TYPE zif_rx_pp_reader=>ty_order
      RETURNING VALUE(rv_situation) TYPE string.

    "! Status de usuário da ordem mapeados como BLOCKS_RELEASE (bloqueiam a liberação).
    METHODS blocking_user_statuses
      IMPORTING is_order         TYPE zif_rx_pp_reader=>ty_order
      RETURNING VALUE(rt_status) TYPE zif_rx_pp_reader=>ty_user_statuses.

    "! Fim programado de operação sem CNF anterior a (hoje - tolerância).
    METHODS is_operation_late
      IMPORTING is_operation   TYPE zif_rx_pp_reader=>ty_operation
      RETURNING VALUE(rv_late) TYPE abap_bool.

    CLASS-METHODS has_status
      IMPORTING it_status     TYPE zif_rx_pp_reader=>ty_statuses
                iv_status     TYPE csequence
      RETURNING VALUE(rv_has) TYPE abap_bool.

    "! Falta: indicador de falta na reserva ou estoque livre menor que a quantidade pendente.
    CLASS-METHODS is_short
      IMPORTING is_component    TYPE zif_rx_pp_reader=>ty_component
      RETURNING VALUE(rv_short) TYPE abap_bool.

    "! Situações em que a ordem não está mais em aberto (sem atraso nem falta de material).
    CLASS-METHODS is_finished
      IMPORTING iv_situation       TYPE csequence
      RETURNING VALUE(rv_finished) TYPE abap_bool.

    CLASS-METHODS situation_label
      IMPORTING iv_code         TYPE csequence
      RETURNING VALUE(rv_label) TYPE string.

    CLASS-METHODS flag_label
      IMPORTING iv_code         TYPE csequence
      RETURNING VALUE(rv_label) TYPE string.

    "! Códigos das situações, na ordem do contrato (PpSituation).
    CLASS-METHODS all_situations
      RETURNING VALUE(rt_codes) TYPE string_table.

    "! Códigos dos sinalizadores, na ordem do contrato (PpFlag).
    CLASS-METHODS all_flags
      RETURNING VALUE(rt_codes) TYPE string_table.

  PRIVATE SECTION.
    DATA mv_today TYPE d.
    DATA mv_limit TYPE d.
    DATA mv_reversal_since TYPE d.
    DATA mt_mapping TYPE zif_rx_pp_reader=>ty_status_maps.

    METHODS has_role
      IMPORTING is_order      TYPE zif_rx_pp_reader=>ty_order
                iv_role       TYPE string
      RETURNING VALUE(rv_has) TYPE abap_bool.

    METHODS is_late
      IMPORTING iv_date        TYPE d
      RETURNING VALUE(rv_late) TYPE abap_bool.

    METHODS any_operation_late
      IMPORTING is_order       TYPE zif_rx_pp_reader=>ty_order
                it_operations  TYPE zif_rx_pp_reader=>ty_operations
      RETURNING VALUE(rv_late) TYPE abap_bool.

    METHODS any_component_short
      IMPORTING is_order        TYPE zif_rx_pp_reader=>ty_order
                it_components   TYPE zif_rx_pp_reader=>ty_components
      RETURNING VALUE(rv_short) TYPE abap_bool.

    METHODS has_recent_reversal
      IMPORTING is_order           TYPE zif_rx_pp_reader=>ty_order
                it_confirmations   TYPE zif_rx_pp_reader=>ty_confirmations
      RETURNING VALUE(rv_reversed) TYPE abap_bool.

    METHODS is_at_risk
      IMPORTING is_order       TYPE zif_rx_pp_reader=>ty_order
      RETURNING VALUE(rv_risk) TYPE abap_bool.

ENDCLASS.



CLASS zcl_rx_pp_status_map IMPLEMENTATION.

  METHOD constructor.
    DATA lv_tolerance TYPE i.

    mv_today = iv_today.
    lv_tolerance = iv_tolerance_days.
    IF lv_tolerance < 0.
      lv_tolerance = 0.
    ENDIF.
    mv_limit = mv_today - lv_tolerance.
    mv_reversal_since = mv_today - iv_reversal_window_days.
    mt_mapping = it_mapping.
  ENDMETHOD.


  METHOD classify.
    DATA lv_open TYPE abap_bool.

    rs_classification-situation = situation_of( is_order ).
    IF is_finished( rs_classification-situation ) = abap_false.
      lv_open = abap_true.
    ENDIF.

    IF lv_open = abap_true.
      IF is_order-actual_start IS INITIAL AND is_late( is_order-sched_start ) = abap_true.
        rs_classification-start_delay_days = mv_today - is_order-sched_start.
      ENDIF.
      IF is_late( is_order-sched_finish ) = abap_true.
        rs_classification-finish_delay_days = mv_today - is_order-sched_finish.
      ENDIF.
    ENDIF.

    IF rs_classification-start_delay_days > 0.
      APPEND c_flag-late_start TO rs_classification-flags.
    ENDIF.
    IF rs_classification-finish_delay_days > 0.
      APPEND c_flag-late_finish TO rs_classification-flags.
    ENDIF.
    IF lv_open = abap_true AND any_operation_late( is_order = is_order it_operations = it_operations ) = abap_true.
      APPEND c_flag-operation_late TO rs_classification-flags.
    ENDIF.
    IF lv_open = abap_true
        AND ( has_status( it_status = is_order-system_status iv_status = c_status-mspt ) = abap_true
           OR any_component_short( is_order = is_order it_components = it_components ) = abap_true ).
      APPEND c_flag-missing_parts TO rs_classification-flags.
    ENDIF.
    IF has_status( it_status = is_order-system_status iv_status = c_status-lkd ) = abap_true.
      APPEND c_flag-locked TO rs_classification-flags.
    ENDIF.
    " Só para ordens totalmente confirmadas: em PCNF é normal a entrada vir no fim.
    IF has_status( it_status = is_order-system_status iv_status = c_status-cnf ) = abap_true
        AND has_status( it_status = is_order-system_status iv_status = c_status-dlv ) = abap_false
        AND is_order-delivered < is_order-confirmed.
      APPEND c_flag-confirmed_not_received TO rs_classification-flags.
    ENDIF.
    IF lv_open = abap_true AND is_at_risk( is_order ) = abap_true.
      APPEND c_flag-sales_order_at_risk TO rs_classification-flags.
    ENDIF.
    IF has_recent_reversal( is_order = is_order it_confirmations = it_confirmations ) = abap_true.
      APPEND c_flag-reversed_confirmation TO rs_classification-flags.
    ENDIF.
  ENDMETHOD.


  METHOD situation_of.
    DATA lt_status TYPE zif_rx_pp_reader=>ty_statuses.

    lt_status = is_order-system_status.
    IF has_status( it_status = lt_status iv_status = c_status-dlfl ) = abap_true.
      rv_situation = c_situation-deleted.
    ELSEIF has_status( it_status = lt_status iv_status = c_status-clsd ) = abap_true.
      rv_situation = c_situation-closed.
    ELSEIF has_status( it_status = lt_status iv_status = c_status-teco ) = abap_true.
      rv_situation = c_situation-technically_completed.
    ELSEIF has_status( it_status = lt_status iv_status = c_status-dlv ) = abap_true.
      rv_situation = c_situation-delivered.
    ELSEIF has_status( it_status = lt_status iv_status = c_status-pdlv ) = abap_true.
      rv_situation = c_situation-partially_delivered.
    ELSEIF has_status( it_status = lt_status iv_status = c_status-cnf ) = abap_true.
      rv_situation = c_situation-confirmed.
    ELSEIF has_status( it_status = lt_status iv_status = c_status-pcnf ) = abap_true.
      rv_situation = c_situation-in_production.
    ELSEIF has_status( it_status = lt_status iv_status = c_status-rel ) = abap_true
        OR has_status( it_status = lt_status iv_status = c_status-prel ) = abap_true.
      rv_situation = c_situation-released.
    ELSEIF has_role( is_order = is_order iv_role = c_role-approved ) = abap_true.
      rv_situation = c_situation-approved.
    ELSE.
      rv_situation = c_situation-created.
    ENDIF.
  ENDMETHOD.


  METHOD blocking_user_statuses.
    DATA lv_key TYPE c LENGTH 60.
    FIELD-SYMBOLS <ls_user> TYPE zif_rx_pp_reader=>ty_user_status.

    LOOP AT is_order-user_status ASSIGNING <ls_user>.
      CONCATENATE <ls_user>-profile '/' <ls_user>-code INTO lv_key.
      READ TABLE mt_mapping TRANSPORTING NO FIELDS
        WITH KEY source_type = c_source-user_status
                 source_value = lv_key
                 situation = c_role-blocks_release.
      IF sy-subrc = 0.
        APPEND <ls_user> TO rt_status.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD is_operation_late.
    IF has_status( it_status = is_operation-status iv_status = c_status-cnf ) = abap_false
        AND is_late( is_operation-sched_finish ) = abap_true.
      rv_late = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD has_status.
    READ TABLE it_status WITH KEY table_line = iv_status TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      rv_has = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD is_short.
    DATA lv_pending TYPE zif_rx_pp_reader=>ty_qty.

    lv_pending = is_component-required - is_component-withdrawn.
    IF is_component-missing = abap_true OR is_component-stock < lv_pending.
      rv_short = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD is_finished.
    IF iv_situation = c_situation-deleted
        OR iv_situation = c_situation-closed
        OR iv_situation = c_situation-technically_completed
        OR iv_situation = c_situation-delivered.
      rv_finished = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD situation_label.
    CASE iv_code.
      WHEN c_situation-deleted.
        rv_label = 'Eliminada'.
      WHEN c_situation-closed.
        rv_label = 'Fechada'.
      WHEN c_situation-technically_completed.
        rv_label = 'Encerrada tecnicamente'.
      WHEN c_situation-delivered.
        rv_label = 'Entregue'.
      WHEN c_situation-partially_delivered.
        rv_label = 'Entregue parcialmente'.
      WHEN c_situation-confirmed.
        rv_label = 'Produzida (confirmada)'.
      WHEN c_situation-in_production.
        rv_label = 'Em produção'.
      WHEN c_situation-released.
        rv_label = 'Liberada'.
      WHEN c_situation-approved.
        rv_label = 'Aprovada'.
      WHEN c_situation-created.
        rv_label = 'Criada'.
      WHEN OTHERS.
        rv_label = iv_code.
    ENDCASE.
  ENDMETHOD.


  METHOD flag_label.
    CASE iv_code.
      WHEN c_flag-late_start.
        rv_label = 'Atrasada no início'.
      WHEN c_flag-late_finish.
        rv_label = 'Atrasada no fim'.
      WHEN c_flag-operation_late.
        rv_label = 'Operação atrasada'.
      WHEN c_flag-missing_parts.
        rv_label = 'Falta de material'.
      WHEN c_flag-locked.
        rv_label = 'Bloqueada'.
      WHEN c_flag-confirmed_not_received.
        rv_label = 'Confirmada sem entrada'.
      WHEN c_flag-sales_order_at_risk.
        rv_label = 'Risco para o pedido do cliente'.
      WHEN c_flag-reversed_confirmation.
        rv_label = 'Apontamento estornado'.
      WHEN OTHERS.
        rv_label = iv_code.
    ENDCASE.
  ENDMETHOD.


  METHOD all_situations.
    APPEND c_situation-deleted TO rt_codes.
    APPEND c_situation-closed TO rt_codes.
    APPEND c_situation-technically_completed TO rt_codes.
    APPEND c_situation-delivered TO rt_codes.
    APPEND c_situation-partially_delivered TO rt_codes.
    APPEND c_situation-confirmed TO rt_codes.
    APPEND c_situation-in_production TO rt_codes.
    APPEND c_situation-released TO rt_codes.
    APPEND c_situation-approved TO rt_codes.
    APPEND c_situation-created TO rt_codes.
  ENDMETHOD.


  METHOD all_flags.
    APPEND c_flag-late_start TO rt_codes.
    APPEND c_flag-late_finish TO rt_codes.
    APPEND c_flag-operation_late TO rt_codes.
    APPEND c_flag-missing_parts TO rt_codes.
    APPEND c_flag-locked TO rt_codes.
    APPEND c_flag-confirmed_not_received TO rt_codes.
    APPEND c_flag-sales_order_at_risk TO rt_codes.
    APPEND c_flag-reversed_confirmation TO rt_codes.
  ENDMETHOD.


  METHOD has_role.
    DATA lv_key TYPE string.
    FIELD-SYMBOLS <ls_map> TYPE zif_rx_pp_reader=>ty_status_map.
    FIELD-SYMBOLS <ls_user> TYPE zif_rx_pp_reader=>ty_user_status.

    LOOP AT mt_mapping ASSIGNING <ls_map> WHERE situation = iv_role.
      CASE <ls_map>-source_type.
        WHEN c_source-system_status.
          IF has_status( it_status = is_order-system_status iv_status = <ls_map>-source_value ) = abap_true.
            rv_has = abap_true.
            RETURN.
          ENDIF.
        WHEN c_source-user_status.
          LOOP AT is_order-user_status ASSIGNING <ls_user>.
            CONCATENATE <ls_user>-profile '/' <ls_user>-code INTO lv_key.
            IF lv_key = <ls_map>-source_value.
              rv_has = abap_true.
              RETURN.
            ENDIF.
          ENDLOOP.
        WHEN c_source-field.
          READ TABLE is_order-field_marks WITH KEY table_line = <ls_map>-source_value TRANSPORTING NO FIELDS.
          IF sy-subrc = 0.
            rv_has = abap_true.
            RETURN.
          ENDIF.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.


  METHOD is_late.
    IF iv_date IS NOT INITIAL AND iv_date < mv_limit.
      rv_late = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD any_operation_late.
    FIELD-SYMBOLS <ls_operation> TYPE zif_rx_pp_reader=>ty_operation.

    LOOP AT it_operations ASSIGNING <ls_operation> WHERE aufnr = is_order-aufnr.
      IF is_operation_late( <ls_operation> ) = abap_true.
        rv_late = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD any_component_short.
    FIELD-SYMBOLS <ls_component> TYPE zif_rx_pp_reader=>ty_component.

    LOOP AT it_components ASSIGNING <ls_component> WHERE aufnr = is_order-aufnr.
      IF is_short( <ls_component> ) = abap_true.
        rv_short = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD has_recent_reversal.
    FIELD-SYMBOLS <ls_confirmation> TYPE zif_rx_pp_reader=>ty_confirmation.

    LOOP AT it_confirmations ASSIGNING <ls_confirmation>
        WHERE aufnr = is_order-aufnr AND reversed = abap_true AND date >= mv_reversal_since.
      rv_reversed = abap_true.
      RETURN.
    ENDLOOP.
  ENDMETHOD.


  METHOD is_at_risk.
    DATA lv_projected TYPE d.

    IF is_order-sales_order IS INITIAL OR is_order-requested_date IS INITIAL.
      RETURN.
    ENDIF.
    " Ordem atrasada só termina hoje, no melhor caso.
    lv_projected = is_order-sched_finish.
    IF lv_projected < mv_today.
      lv_projected = mv_today.
    ENDIF.
    IF lv_projected > is_order-requested_date.
      rv_risk = abap_true.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
