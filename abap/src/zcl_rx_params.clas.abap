"! Leitura e validação dos parâmetros planos (form/query string).
"! Mesmas regras de validateParams em packages/contracts.
"! A busca por nome ignora maiúsculas/minúsculas, porque o ICF pode
"! normalizar o nome dos campos do formulário.
CLASS zcl_rx_params DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS get
      IMPORTING it_params       TYPE zif_rx_types=>ty_params
                iv_name         TYPE csequence
      RETURNING VALUE(rv_value) TYPE string.

    "! Valida contra os metadados e levanta INVALID_PARAMS (HTTP 400) com todos os problemas.
    CLASS-METHODS validate
      IMPORTING is_meta   TYPE zif_rx_types=>ty_diag_meta
                it_params TYPE zif_rx_types=>ty_params
      RAISING   zcx_rx_error.

    CLASS-METHODS is_iso_date
      IMPORTING iv_value     TYPE csequence
      RETURNING VALUE(rv_ok) TYPE abap_bool.

ENDCLASS.



CLASS zcl_rx_params IMPLEMENTATION.

  METHOD get.
    DATA lv_wanted TYPE string.
    DATA lv_name TYPE string.
    FIELD-SYMBOLS <ls_param> TYPE zif_rx_types=>ty_param.

    lv_wanted = iv_name.
    TRANSLATE lv_wanted TO LOWER CASE.
    LOOP AT it_params ASSIGNING <ls_param>.
      lv_name = <ls_param>-name.
      TRANSLATE lv_name TO LOWER CASE.
      IF lv_name = lv_wanted.
        rv_value = <ls_param>-value.
        CONDENSE rv_value.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD validate.
    DATA lt_errors TYPE string_table.
    DATA lv_error TYPE string.
    DATA lv_value TYPE string.
    DATA lv_message TYPE string.
    DATA lv_name TYPE string.
    FIELD-SYMBOLS <ls_meta> TYPE zif_rx_types=>ty_param_meta.

    LOOP AT is_meta-params ASSIGNING <ls_meta>.
      CLEAR lv_error.
      lv_value = get( it_params = it_params iv_name = <ls_meta>-name ).
      IF lv_value IS INITIAL.
        IF <ls_meta>-required = abap_true.
          lv_error = 'Obrigatório'.
        ENDIF.
      ELSEIF ( <ls_meta>-data_type = zif_rx_types=>c_data_type-integer
            OR <ls_meta>-data_type = zif_rx_types=>c_data_type-document )
            AND lv_value CN '0123456789'.
        lv_error = 'Use apenas números'.
      ELSEIF <ls_meta>-data_type = zif_rx_types=>c_data_type-date
            AND is_iso_date( lv_value ) = abap_false.
        lv_error = 'Use o formato AAAA-MM-DD'.
      ELSEIF <ls_meta>-data_type = zif_rx_types=>c_data_type-enum.
        READ TABLE <ls_meta>-options WITH KEY table_line = lv_value TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          lv_error = 'Valor inválido'.
        ENDIF.
      ENDIF.
      IF lv_error IS NOT INITIAL.
        " Sem RESPECTING BLANKS (7.02+): os espaços entram via SEPARATED BY space.
        CONCATENATE <ls_meta>-name ':' INTO lv_name.
        CONCATENATE lv_name lv_error INTO lv_error SEPARATED BY space.
        APPEND lv_error TO lt_errors.
      ENDIF.
    ENDLOOP.

    IF lt_errors IS NOT INITIAL.
      lv_message = 'Parâmetros inválidos:'.
      LOOP AT lt_errors INTO lv_error.
        IF sy-tabix > 1.
          CONCATENATE lv_message ';' INTO lv_message.
        ENDIF.
        CONCATENATE lv_message lv_error INTO lv_message SEPARATED BY space.
      ENDLOOP.
      RAISE EXCEPTION TYPE zcx_rx_error
        EXPORTING
          iv_http_status = 400
          iv_code        = 'INVALID_PARAMS'
          iv_text        = lv_message.
    ENDIF.
  ENDMETHOD.


  METHOD is_iso_date.
    DATA lv_value TYPE string.
    DATA lv_date TYPE d.

    lv_value = iv_value.
    IF strlen( lv_value ) <> 10 OR lv_value+4(1) <> '-' OR lv_value+7(1) <> '-'.
      RETURN.
    ENDIF.
    CONCATENATE lv_value(4) lv_value+5(2) lv_value+8(2) INTO lv_date.
    IF lv_date CN '0123456789'.
      RETURN.
    ENDIF.
    rv_ok = abap_true.
  ENDMETHOD.

ENDCLASS.
