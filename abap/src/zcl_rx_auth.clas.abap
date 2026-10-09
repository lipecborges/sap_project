"! Autorização por diagnóstico via objeto ZRX_DIAG
"! (campos ZRX_DIAGID e ACTVT, atividade 16 = executar).
"! O objeto de autorização e a role modelo ZRX_USER são criados na Fase 1a;
"! até lá, a verificação nega o acesso.
CLASS zcl_rx_auth DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_rx_authorizer.

ENDCLASS.



CLASS zcl_rx_auth IMPLEMENTATION.

  METHOD zif_rx_authorizer~is_allowed.
    DATA lv_id TYPE c LENGTH 10.

    lv_id = iv_diagnostic_id.
    AUTHORITY-CHECK OBJECT 'ZRX_DIAG'
      ID 'ZRX_DIAGID' FIELD lv_id
      ID 'ACTVT' FIELD '16'.
    IF sy-subrc = 0.
      rv_allowed = abap_true.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
