"! Registro de cada execução em ZRX_LOG (quem, o quê, quando, resultado, duração).
"! A gravação é efetivada no fim da requisição HTTP (commit implícito do ICF);
"! nenhum diagnóstico faz COMMIT WORK.
CLASS zcl_rx_logger DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS write
      IMPORTING iv_diagnostic_id TYPE csequence
                it_params        TYPE zif_rx_types=>ty_params
                iv_status        TYPE csequence
                iv_http_status   TYPE i
                iv_duration_ms   TYPE i.

ENDCLASS.



CLASS zcl_rx_logger IMPLEMENTATION.

  METHOD write.
    DATA ls_log TYPE zrx_log.
    DATA lv_params TYPE string.
    DATA lv_pair TYPE string.
    FIELD-SYMBOLS <ls_param> TYPE zif_rx_types=>ty_param.

    LOOP AT it_params ASSIGNING <ls_param>.
      CONCATENATE <ls_param>-name '=' <ls_param>-value INTO lv_pair.
      IF lv_params IS INITIAL.
        lv_params = lv_pair.
      ELSE.
        CONCATENATE lv_params '&' lv_pair INTO lv_params.
      ENDIF.
    ENDLOOP.

    GET TIME STAMP FIELD ls_log-timestampl.
    ls_log-uname = sy-uname.
    ls_log-diag_id = iv_diagnostic_id.
    ls_log-status = iv_status.
    ls_log-http_status = iv_http_status.
    ls_log-duration_ms = iv_duration_ms.
    ls_log-params = lv_params.
    " Log não pode derrubar o diagnóstico: chave duplicada (mesmo instante) é ignorada.
    INSERT zrx_log FROM ls_log.                           "#EC CI_SUBRC
  ENDMETHOD.

ENDCLASS.
