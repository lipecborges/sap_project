*"* Testes de formatação (devem bater com o sap-mock: pt-BR, sem depender do usuário)
CLASS ltc_format DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS alpha FOR TESTING.
    METHODS dates FOR TESTING.
    METHODS numbers FOR TESTING.
    METHODS money FOR TESTING.
ENDCLASS.


CLASS ltc_format IMPLEMENTATION.

  METHOD alpha.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_format=>alpha_out( '0004500123' ) exp = '4500123' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_format=>alpha_in( iv_value = '4500123' iv_length = 10 )
                                        exp = '0004500123' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_format=>alpha_in( iv_value = 'ABC' iv_length = 10 ) exp = 'ABC' ).
  ENDMETHOD.

  METHOD dates.
    DATA lv_date TYPE d VALUE '20261009'.
    DATA lv_empty TYPE d.

    cl_abap_unit_assert=>assert_equals( act = zcl_rx_format=>date_iso( lv_date ) exp = '2026-10-09' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_format=>date_iso( lv_empty ) exp = '' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_format=>date_from_iso( '2026-10-09' ) exp = lv_date ).
  ENDMETHOD.

  METHOD numbers.
    DATA lv_p TYPE p LENGTH 13 DECIMALS 3.

    lv_p = 1000.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_format=>quantity( iv_value = lv_p iv_unit = 'PC' )
                                        exp = '1.000 PC' ).
    lv_p = '1234567.5'.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_format=>number_br( lv_p ) exp = '1.234.567,5' ).
    lv_p = 12.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_format=>number_br( lv_p ) exp = '12' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_format=>int( -3 ) exp = '-3' ).
  ENDMETHOD.

  METHOD money.
    DATA lv_amount TYPE p LENGTH 13 DECIMALS 2.

    lv_amount = '48450'.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_format=>money( iv_amount = lv_amount iv_currency = 'BRL' )
                                        exp = 'R$ 48.450,00' ).
    lv_amount = '1150.5'.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_format=>money( iv_amount = lv_amount iv_currency = 'USD' )
                                        exp = '1.150,50 USD' ).
  ENDMETHOD.

ENDCLASS.
