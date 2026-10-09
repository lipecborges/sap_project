*"* Testes da validação de parâmetros
CLASS ltc_params DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS get_ignores_case FOR TESTING.
    METHODS required_and_numeric FOR TESTING.
    METHODS valid_params FOR TESTING.
    METHODS iso_date FOR TESTING.
    METHODS meta
      RETURNING VALUE(rs_meta) TYPE zif_rx_types=>ty_diag_meta.
ENDCLASS.


CLASS ltc_params IMPLEMENTATION.

  METHOD meta.
    DATA ls_param TYPE zif_rx_types=>ty_param_meta.

    rs_meta-id = 'MM-02'.
    ls_param-name = 'invoiceDocument'.
    ls_param-data_type = zif_rx_types=>c_data_type-document.
    ls_param-required = abap_true.
    APPEND ls_param TO rs_meta-params.
    CLEAR ls_param.
    ls_param-name = 'fiscalYear'.
    ls_param-data_type = zif_rx_types=>c_data_type-integer.
    ls_param-required = abap_true.
    APPEND ls_param TO rs_meta-params.
  ENDMETHOD.

  METHOD get_ignores_case.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_param TYPE zif_rx_types=>ty_param.

    ls_param-name = 'salesorder'.
    ls_param-value = ' 4500001 '.
    APPEND ls_param TO lt_params.
    cl_abap_unit_assert=>assert_equals(
      act = zcl_rx_params=>get( it_params = lt_params iv_name = 'salesOrder' )
      exp = '4500001' ).
  ENDMETHOD.

  METHOD required_and_numeric.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_param TYPE zif_rx_types=>ty_param.
    DATA lx_error TYPE REF TO zcx_rx_error.

    ls_param-name = 'invoiceDocument'.
    ls_param-value = 'abc'.
    APPEND ls_param TO lt_params.
    TRY.
        zcl_rx_params=>validate( is_meta = meta( ) it_params = lt_params ).
        cl_abap_unit_assert=>fail( 'Deveria rejeitar os parâmetros' ).
      CATCH zcx_rx_error INTO lx_error.
        cl_abap_unit_assert=>assert_equals( act = lx_error->mv_http_status exp = 400 ).
        cl_abap_unit_assert=>assert_equals(
          act = lx_error->mv_text
          exp = 'Parâmetros inválidos: invoiceDocument: Use apenas números; fiscalYear: Obrigatório' ).
    ENDTRY.
  ENDMETHOD.

  METHOD valid_params.
    DATA lt_params TYPE zif_rx_types=>ty_params.
    DATA ls_param TYPE zif_rx_types=>ty_param.
    DATA lx_error TYPE REF TO zcx_rx_error.

    ls_param-name = 'invoiceDocument'.
    ls_param-value = '5105600001'.
    APPEND ls_param TO lt_params.
    ls_param-name = 'fiscalYear'.
    ls_param-value = '2026'.
    APPEND ls_param TO lt_params.
    TRY.
        zcl_rx_params=>validate( is_meta = meta( ) it_params = lt_params ).
      CATCH zcx_rx_error INTO lx_error.
        cl_abap_unit_assert=>fail( lx_error->mv_text ).
    ENDTRY.
  ENDMETHOD.

  METHOD iso_date.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_params=>is_iso_date( '2026-10-09' ) exp = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_params=>is_iso_date( '09/10/2026' ) exp = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_params=>is_iso_date( '2026-1-091' ) exp = abap_false ).
  ENDMETHOD.

ENDCLASS.
