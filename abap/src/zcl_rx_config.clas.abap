"! Configuração do add-on (tabela ZRX_CONFIG, mantida pelo cliente).
"! Chaves conhecidas:
"!   DISABLED:<id>             = X  desliga um diagnóstico (ex.: DISABLED:SD-01)
"!   PP_LATE_TOLERANCE_DAYS     = n  tolerância de atraso em dias (padrão 0)
"!   MAX_ROWS                   = n  limite de linhas das listas (padrão 500)
CLASS zcl_rx_config DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS get
      IMPORTING iv_key          TYPE csequence
      RETURNING VALUE(rv_value) TYPE string.

    CLASS-METHODS get_int
      IMPORTING iv_key          TYPE csequence
                iv_default      TYPE i
      RETURNING VALUE(rv_value) TYPE i.

    CLASS-METHODS is_enabled
      IMPORTING iv_diagnostic_id  TYPE csequence
      RETURNING VALUE(rv_enabled) TYPE abap_bool.

ENDCLASS.



CLASS zcl_rx_config IMPLEMENTATION.

  METHOD get.
    DATA lv_key TYPE c LENGTH 40.
    DATA lv_value TYPE c LENGTH 80.

    lv_key = iv_key.
    SELECT SINGLE config_value FROM zrx_config INTO lv_value WHERE config_key = lv_key.
    IF sy-subrc = 0.
      rv_value = lv_value.
    ENDIF.
  ENDMETHOD.


  METHOD get_int.
    DATA lv_value TYPE string.

    rv_value = iv_default.
    lv_value = get( iv_key ).
    CONDENSE lv_value.
    IF lv_value IS NOT INITIAL AND lv_value CO '0123456789'.
      rv_value = lv_value.
    ENDIF.
  ENDMETHOD.


  METHOD is_enabled.
    DATA lv_key TYPE string.

    CONCATENATE 'DISABLED:' iv_diagnostic_id INTO lv_key.
    IF get( lv_key ) = 'X'.
      rv_enabled = abap_false.
    ELSE.
      rv_enabled = abap_true.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
