*"* Testes do roteador com dublês de diagnóstico e de autorização
CLASS ltd_diagnostic DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_rx_diagnostic.
ENDCLASS.

CLASS ltd_diagnostic IMPLEMENTATION.
  METHOD zif_rx_diagnostic~get_metadata.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.

    rs_meta-id = 'ZT-01'.
    rs_meta-version = '1.0'.
    rs_meta-module = 'SD'.
    rs_meta-kind = 'OBJECT'.
    rs_meta-title = 'Diagnóstico de teste'.
    ls_param-name = 'salesOrder'.
    ls_param-label = 'Pedido de venda'.
    ls_param-data_type = zif_rx_types=>c_data_type-document.
    ls_param-required = abap_true.
    APPEND ls_param TO rs_meta-params.
  ENDMETHOD.

  METHOD zif_rx_diagnostic~execute.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.

    rs_result-object-kind = 'SALES_ORDER'.
    rs_result-object-id = zcl_rx_params=>get( it_params = it_params iv_name = 'salesOrder' ).
    rs_result-status = zif_rx_types=>c_status-problem_found.
    ls_finding-code = 'ZT01.TEST'.
    ls_finding-severity = zif_rx_types=>c_severity-blocking.
    ls_finding-title = 'Achado de teste'.
    APPEND ls_finding TO rs_result-findings.
  ENDMETHOD.
ENDCLASS.


CLASS ltd_authorizer DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_rx_authorizer.
    DATA mv_allow TYPE abap_bool VALUE abap_true.
ENDCLASS.

CLASS ltd_authorizer IMPLEMENTATION.
  METHOD zif_rx_authorizer~is_allowed.
    rv_allowed = mv_allow.
  ENDMETHOD.
ENDCLASS.


CLASS ltc_router DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO zcl_rx_router.
    DATA mo_authorizer TYPE REF TO ltd_authorizer.

    METHODS setup.
    METHODS params
      IMPORTING iv_sales_order   TYPE string
      RETURNING VALUE(rt_params) TYPE zif_rx_types=>ty_params.
    METHODS assert_contains
      IMPORTING iv_json TYPE string
                iv_part TYPE string.

    METHODS unknown_route FOR TESTING.
    METHODS health FOR TESTING.
    METHODS run_ok FOR TESTING.
    METHODS run_unknown FOR TESTING.
    METHODS run_not_authorized FOR TESTING.
    METHODS run_invalid_params FOR TESTING.
ENDCLASS.


CLASS ltc_router IMPLEMENTATION.

  METHOD setup.
    DATA lo_registry TYPE REF TO zcl_rx_diagnostic_registry.
    DATA lo_diagnostic TYPE REF TO ltd_diagnostic.

    CREATE OBJECT lo_registry EXPORTING iv_discover = abap_false.
    CREATE OBJECT lo_diagnostic.
    lo_registry->register( lo_diagnostic ).
    CREATE OBJECT mo_authorizer.
    CREATE OBJECT mo_cut EXPORTING io_registry = lo_registry io_authorizer = mo_authorizer.
  ENDMETHOD.

  METHOD params.
    DATA ls_param TYPE zif_rx_types=>ty_param.

    ls_param-name = 'salesOrder'.
    ls_param-value = iv_sales_order.
    APPEND ls_param TO rt_params.
  ENDMETHOD.

  METHOD assert_contains.
    IF iv_json NS iv_part.
      cl_abap_unit_assert=>fail( msg = iv_part detail = iv_json ).
    ENDIF.
  ENDMETHOD.

  METHOD unknown_route.
    DATA ls_response TYPE zcl_rx_router=>ty_response.
    DATA lt_params TYPE zif_rx_types=>ty_params.

    ls_response = mo_cut->dispatch( iv_method = 'GET' iv_path = '/v2/health' it_params = lt_params ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-status exp = 404 ).
    assert_contains( iv_json = ls_response-json iv_part = '"code":"ROUTE_NOT_FOUND"' ).
  ENDMETHOD.

  METHOD health.
    DATA ls_response TYPE zcl_rx_router=>ty_response.
    DATA lt_params TYPE zif_rx_types=>ty_params.

    ls_response = mo_cut->dispatch( iv_method = 'GET' iv_path = '/v1/health' it_params = lt_params ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-status exp = 200 ).
    assert_contains( iv_json = ls_response-json iv_part = '"addonVersion":"0.1.0"' ).
    assert_contains( iv_json = ls_response-json iv_part = '"diagnostics":["ZT-01"]' ).
  ENDMETHOD.

  METHOD run_ok.
    DATA ls_response TYPE zcl_rx_router=>ty_response.

    ls_response = mo_cut->dispatch( iv_method = 'post'
                                    iv_path   = '/v1/diagnostics/ZT-01'
                                    it_params = params( '4500001' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-status exp = 200 ).
    assert_contains( iv_json = ls_response-json iv_part = '"diagnosticId":"ZT-01"' ).
    assert_contains( iv_json = ls_response-json iv_part = '"object":{"kind":"SALES_ORDER","id":"4500001"}' ).
    assert_contains( iv_json = ls_response-json iv_part = '"status":"PROBLEM_FOUND"' ).
  ENDMETHOD.

  METHOD run_unknown.
    DATA ls_response TYPE zcl_rx_router=>ty_response.

    ls_response = mo_cut->dispatch( iv_method = 'POST' iv_path = '/v1/diagnostics/XX-99' it_params = params( '1' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-status exp = 404 ).
    assert_contains( iv_json = ls_response-json iv_part = '"code":"UNKNOWN_DIAGNOSTIC"' ).
  ENDMETHOD.

  METHOD run_not_authorized.
    DATA ls_response TYPE zcl_rx_router=>ty_response.

    mo_authorizer->mv_allow = abap_false.
    ls_response = mo_cut->dispatch( iv_method = 'POST' iv_path = '/v1/diagnostics/ZT-01' it_params = params( '1' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-status exp = 403 ).
    assert_contains( iv_json = ls_response-json iv_part = '"code":"NOT_AUTHORIZED"' ).
  ENDMETHOD.

  METHOD run_invalid_params.
    DATA ls_response TYPE zcl_rx_router=>ty_response.

    ls_response = mo_cut->dispatch( iv_method = 'POST' iv_path = '/v1/diagnostics/ZT-01' it_params = params( 'ABC' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-status exp = 400 ).
    assert_contains( iv_json = ls_response-json iv_part = '"code":"INVALID_PARAMS"' ).
  ENDMETHOD.

ENDCLASS.
