"! Handler HTTP do serviço ICF /sap/bc/zrx/api (transação SICF).
"! Só traduz HTTP <-> roteador; toda a lógica fica em ZCL_RX_ROUTER.
CLASS zcl_rx_http_handler DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_extension.

  PRIVATE SECTION.
    CLASS-METHODS reason_phrase
      IMPORTING iv_status        TYPE i
      RETURNING VALUE(rv_reason) TYPE string.

ENDCLASS.



CLASS zcl_rx_http_handler IMPLEMENTATION.

  METHOD if_http_extension~handle_request.
    DATA lv_method TYPE string.
    DATA lv_path TYPE string.
    DATA lv_reason TYPE string.
    DATA lt_fields TYPE tihttpnvp.
    DATA ls_field TYPE ihttpnvp.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_param TYPE zif_rx_types=>ty_param.
    DATA lo_router TYPE REF TO zcl_rx_router.
    DATA ls_response TYPE zcl_rx_router=>ty_response.

    lv_method = server->request->get_header_field( '~request_method' ).
    lv_path = server->request->get_header_field( '~path_info' ).

    " Query string + corpo application/x-www-form-urlencoded.
    server->request->get_form_fields( CHANGING fields = lt_fields ).
    LOOP AT lt_fields INTO ls_field.
      " sap-client, sap-language etc. são parâmetros técnicos do ICF.
      IF ls_field-name CP 'sap-*'.
        CONTINUE.
      ENDIF.
      ls_param-name = ls_field-name.
      ls_param-value = ls_field-value.
      APPEND ls_param TO lt_params.
    ENDLOOP.

    CREATE OBJECT lo_router.
    ls_response = lo_router->dispatch( iv_method = lv_method iv_path = lv_path it_params = lt_params ).

    lv_reason = reason_phrase( ls_response-status ).
    server->response->set_status( code = ls_response-status reason = lv_reason ).
    server->response->set_header_field( name = 'Content-Type' value = 'application/json; charset=utf-8' ).
    server->response->set_header_field( name = 'Cache-Control' value = 'no-store' ).
    server->response->set_cdata( ls_response-json ).
  ENDMETHOD.


  METHOD reason_phrase.
    CASE iv_status.
      WHEN 200.
        rv_reason = 'OK'.
      WHEN 400.
        rv_reason = 'Bad Request'.
      WHEN 403.
        rv_reason = 'Forbidden'.
      WHEN 404.
        rv_reason = 'Not Found'.
      WHEN OTHERS.
        rv_reason = 'Internal Server Error'.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
