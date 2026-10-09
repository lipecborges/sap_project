"! Roteador da API REST (independente do ICF, para poder ser testado).
"! Rotas (relativas ao nó ICF /sap/bc/zrx/api):
"!   GET  /v1/health            versão do add-on e dados do sistema
"!   GET  /v1/me                usuário, idioma e diagnósticos permitidos
"!   GET  /v1/diagnostics       catálogo (metadados)
"!   POST /v1/diagnostics/{id}  executa um diagnóstico (parâmetros planos)
CLASS zcl_rx_router DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_response,
        status TYPE i,
        json   TYPE string,
      END OF ty_response.

    METHODS constructor
      IMPORTING io_registry   TYPE REF TO zcl_rx_diagnostic_registry OPTIONAL
                io_authorizer TYPE REF TO zif_rx_authorizer OPTIONAL.

    METHODS dispatch
      IMPORTING iv_method          TYPE csequence
                iv_path            TYPE csequence
                it_params          TYPE zif_rx_types=>ty_params
      RETURNING VALUE(rs_response) TYPE ty_response.

  PRIVATE SECTION.
    DATA mo_registry TYPE REF TO zcl_rx_diagnostic_registry.
    DATA mo_authorizer TYPE REF TO zif_rx_authorizer.

    METHODS health
      RETURNING VALUE(rs_response) TYPE ty_response.

    METHODS me
      RETURNING VALUE(rs_response) TYPE ty_response.

    METHODS list_diagnostics
      RETURNING VALUE(rs_response) TYPE ty_response.

    METHODS run_diagnostic
      IMPORTING iv_id              TYPE string
                it_params          TYPE zif_rx_types=>ty_params
      RETURNING VALUE(rs_response) TYPE ty_response
      RAISING   zcx_rx_error.

    METHODS allowed_ids
      RETURNING VALUE(rt_ids) TYPE string_table.

    METHODS error_response
      IMPORTING iv_status          TYPE i
                iv_code            TYPE string
                iv_message         TYPE string
      RETURNING VALUE(rs_response) TYPE ty_response.

    METHODS route_not_found
      IMPORTING iv_method TYPE csequence
                iv_path   TYPE csequence
      RAISING   zcx_rx_error.

    CLASS-METHODS iso_timestamp
      RETURNING VALUE(rv_iso) TYPE string.

ENDCLASS.



CLASS zcl_rx_router IMPLEMENTATION.

  METHOD constructor.
    IF io_registry IS BOUND.
      mo_registry = io_registry.
    ELSE.
      CREATE OBJECT mo_registry.
    ENDIF.
    IF io_authorizer IS BOUND.
      mo_authorizer = io_authorizer.
    ELSE.
      CREATE OBJECT mo_authorizer TYPE zcl_rx_auth.
    ENDIF.
  ENDMETHOD.


  METHOD dispatch.
    DATA lv_path TYPE string.
    DATA lt_segments TYPE string_table.
    DATA lv_version TYPE string.
    DATA lv_resource TYPE string.
    DATA lv_id TYPE string.
    DATA lv_count TYPE i.
    DATA lv_method TYPE string.
    DATA lx_error TYPE REF TO zcx_rx_error.
    DATA lx_root TYPE REF TO cx_root.
    DATA lv_text TYPE string.

    lv_method = iv_method.
    TRANSLATE lv_method TO UPPER CASE.
    lv_path = iv_path.
    SPLIT lv_path AT '/' INTO TABLE lt_segments.
    DELETE lt_segments WHERE table_line IS INITIAL.
    lv_count = lines( lt_segments ).
    " Segmentos ausentes ficam vazios e caem em ROUTE_NOT_FOUND.
    READ TABLE lt_segments INDEX 1 INTO lv_version.       "#EC CI_SUBRC
    READ TABLE lt_segments INDEX 2 INTO lv_resource.      "#EC CI_SUBRC
    READ TABLE lt_segments INDEX 3 INTO lv_id.            "#EC CI_SUBRC

    TRY.
        IF lv_version <> zif_rx_types=>c_api_version.
          route_not_found( iv_method = lv_method iv_path = lv_path ).
        ENDIF.

        IF lv_resource = 'health' AND lv_count = 2 AND lv_method = 'GET'.
          rs_response = health( ).
        ELSEIF lv_resource = 'me' AND lv_count = 2 AND lv_method = 'GET'.
          rs_response = me( ).
        ELSEIF lv_resource = 'diagnostics' AND lv_count = 2 AND lv_method = 'GET'.
          rs_response = list_diagnostics( ).
        ELSEIF lv_resource = 'diagnostics' AND lv_count = 3 AND lv_method = 'POST'.
          rs_response = run_diagnostic( iv_id = lv_id it_params = it_params ).
        ELSE.
          route_not_found( iv_method = lv_method iv_path = lv_path ).
        ENDIF.

      CATCH zcx_rx_error INTO lx_error.
        rs_response = error_response( iv_status  = lx_error->mv_http_status
                                      iv_code    = lx_error->mv_code
                                      iv_message = lx_error->mv_text ).
      CATCH cx_root INTO lx_root.
        " Erro inesperado em um diagnóstico: nunca deixa o ICF devolver dump/HTML.
        lv_text = lx_root->get_text( ).
        rs_response = error_response( iv_status = 500 iv_code = 'INTERNAL' iv_message = lv_text ).
    ENDTRY.
  ENDMETHOD.


  METHOD health.
    DATA ls_health TYPE zif_rx_types=>ty_health.
    DATA lt_diagnostics TYPE zcl_rx_diagnostic_registry=>ty_diagnostics.
    DATA lo_diagnostic TYPE REF TO zif_rx_diagnostic.
    DATA ls_meta TYPE zif_rx_types=>ty_diag_meta.

    ls_health-addon_version = zif_rx_types=>c_addon_version.
    ls_health-api_version = zif_rx_types=>c_api_version.
    ls_health-system = zcl_rx_system_info=>get( ).
    lt_diagnostics = mo_registry->get_all( ).
    LOOP AT lt_diagnostics INTO lo_diagnostic.
      ls_meta = lo_diagnostic->get_metadata( ).
      APPEND ls_meta-id TO ls_health-diagnostics.
    ENDLOOP.

    rs_response-status = 200.
    rs_response-json = zcl_rx_json=>serialize( ls_health ).
  ENDMETHOD.


  METHOD me.
    DATA ls_me TYPE zif_rx_types=>ty_me.
    DATA lv_language TYPE c LENGTH 2.

    CALL FUNCTION 'CONVERSION_EXIT_ISOLA_OUTPUT'
      EXPORTING
        input  = sy-langu
      IMPORTING
        output = lv_language.

    ls_me-user = sy-uname.
    ls_me-language = lv_language.
    ls_me-diagnostics = allowed_ids( ).

    rs_response-status = 200.
    rs_response-json = zcl_rx_json=>serialize( ls_me ).
  ENDMETHOD.


  METHOD list_diagnostics.
    DATA ls_body TYPE zif_rx_types=>ty_diagnostics_response.
    DATA lt_diagnostics TYPE zcl_rx_diagnostic_registry=>ty_diagnostics.
    DATA lo_diagnostic TYPE REF TO zif_rx_diagnostic.
    DATA ls_meta TYPE zif_rx_types=>ty_diag_meta.

    lt_diagnostics = mo_registry->get_all( ).
    LOOP AT lt_diagnostics INTO lo_diagnostic.
      ls_meta = lo_diagnostic->get_metadata( ).
      APPEND ls_meta TO ls_body-diagnostics.
    ENDLOOP.

    rs_response-status = 200.
    rs_response-json = zcl_rx_json=>serialize( ls_body ).
  ENDMETHOD.


  METHOD run_diagnostic.
    DATA lo_diagnostic TYPE REF TO zif_rx_diagnostic.
    DATA ls_meta TYPE zif_rx_types=>ty_diag_meta.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA lv_message TYPE string.
    DATA lv_start TYPE i.
    DATA lv_end TYPE i.

    lo_diagnostic = mo_registry->get_by_id( iv_id ).
    IF lo_diagnostic IS NOT BOUND OR zcl_rx_config=>is_enabled( iv_id ) = abap_false.
      CONCATENATE 'Diagnóstico' iv_id 'não existe' INTO lv_message SEPARATED BY space.
      RAISE EXCEPTION TYPE zcx_rx_error
        EXPORTING iv_http_status = 404 iv_code = 'UNKNOWN_DIAGNOSTIC' iv_text = lv_message.
    ENDIF.

    IF mo_authorizer->is_allowed( iv_id ) = abap_false.
      CONCATENATE 'Sem autorização para o diagnóstico' iv_id '(objeto ZRX_DIAG)' INTO lv_message SEPARATED BY space.
      RAISE EXCEPTION TYPE zcx_rx_error
        EXPORTING iv_http_status = 403 iv_code = 'NOT_AUTHORIZED' iv_text = lv_message.
    ENDIF.

    ls_meta = lo_diagnostic->get_metadata( ).
    zcl_rx_params=>validate( is_meta = ls_meta it_params = it_params ).

    GET RUN TIME FIELD lv_start.
    ls_result = lo_diagnostic->execute( it_params ).
    GET RUN TIME FIELD lv_end.

    ls_result-diagnostic_id = ls_meta-id.
    IF ls_result-version IS INITIAL.
      ls_result-version = ls_meta-version.
    ENDIF.
    IF ls_result-status IS INITIAL.
      ls_result-status = zif_rx_types=>c_status-ok.
    ENDIF.
    ls_result-system = zcl_rx_system_info=>get( ).
    ls_result-executed_at = iso_timestamp( ).
    ls_result-duration_ms = ( lv_end - lv_start ) / 1000.

    rs_response-status = 200.
    rs_response-json = zcl_rx_json=>serialize( ls_result ).
    zcl_rx_logger=>write( iv_diagnostic_id = ls_meta-id
                          it_params        = it_params
                          iv_status        = ls_result-status
                          iv_http_status   = rs_response-status
                          iv_duration_ms   = ls_result-duration_ms ).
  ENDMETHOD.


  METHOD allowed_ids.
    DATA lt_diagnostics TYPE zcl_rx_diagnostic_registry=>ty_diagnostics.
    DATA lo_diagnostic TYPE REF TO zif_rx_diagnostic.
    DATA ls_meta TYPE zif_rx_types=>ty_diag_meta.

    lt_diagnostics = mo_registry->get_all( ).
    LOOP AT lt_diagnostics INTO lo_diagnostic.
      ls_meta = lo_diagnostic->get_metadata( ).
      IF mo_authorizer->is_allowed( ls_meta-id ) = abap_true.
        APPEND ls_meta-id TO rt_ids.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD error_response.
    DATA ls_error TYPE zif_rx_types=>ty_error_response.

    ls_error-error-code = iv_code.
    ls_error-error-message = iv_message.
    rs_response-status = iv_status.
    rs_response-json = zcl_rx_json=>serialize( ls_error ).
  ENDMETHOD.


  METHOD route_not_found.
    DATA lv_message TYPE string.

    CONCATENATE 'Rota' iv_method iv_path 'não existe' INTO lv_message SEPARATED BY space.
    RAISE EXCEPTION TYPE zcx_rx_error
      EXPORTING iv_http_status = 404 iv_code = 'ROUTE_NOT_FOUND' iv_text = lv_message.
  ENDMETHOD.


  METHOD iso_timestamp.
    DATA lv_timestamp TYPE timestamp.
    DATA lv_date TYPE d.
    DATA lv_time TYPE t.
    DATA lv_zone TYPE timezone VALUE 'UTC'.

    GET TIME STAMP FIELD lv_timestamp.
    CONVERT TIME STAMP lv_timestamp TIME ZONE lv_zone INTO DATE lv_date TIME lv_time.
    CONCATENATE lv_date(4) '-' lv_date+4(2) '-' lv_date+6(2) 'T'
                lv_time(2) ':' lv_time+2(2) ':' lv_time+4(2) 'Z'
                INTO rv_iso.
  ENDMETHOD.

ENDCLASS.
