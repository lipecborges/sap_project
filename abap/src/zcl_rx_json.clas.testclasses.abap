*"* Testes do serializador JSON (sintaxe 7.00)
CLASS ltc_json DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_child,
        tcode TYPE string,
      END OF ty_child,
      BEGIN OF ty_sample,
        diagnostic_id TYPE string,
        duration_ms   TYPE i,
        amount        TYPE p LENGTH 8 DECIMALS 2,
        truncated     TYPE abap_bool,
        posting_date  TYPE d,
        tags          TYPE string_table,
        empty_child   TYPE ty_child,
        child         TYPE ty_child,
      END OF ty_sample.

    METHODS escape_special_characters FOR TESTING.
    METHODS camel_case FOR TESTING.
    METHODS structure_and_types FOR TESTING.
    METHODS empty_table FOR TESTING.
ENDCLASS.


CLASS ltc_json IMPLEMENTATION.

  METHOD escape_special_characters.
    DATA lv_input TYPE string.
    DATA lv_expected TYPE string.

    CONCATENATE 'a"b\c' cl_abap_char_utilities=>newline 'd' INTO lv_input.
    lv_expected = 'a\"b\\c\nd'.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_json=>escape_string( lv_input ) exp = lv_expected ).
  ENDMETHOD.

  METHOD camel_case.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_json=>to_camel_case( 'SUGGESTED_ACTION' )
                                        exp = 'suggestedAction' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_json=>to_camel_case( 'ID' ) exp = 'id' ).
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_json=>to_camel_case( 'BASIS_RELEASE' ) exp = 'basisRelease' ).
  ENDMETHOD.

  METHOD structure_and_types.
    DATA ls_sample TYPE ty_sample.
    DATA lv_expected TYPE string.

    ls_sample-diagnostic_id = 'SD-01'.
    ls_sample-duration_ms = 42.
    ls_sample-amount = '-12.50'.
    ls_sample-truncated = abap_true.
    ls_sample-posting_date = '20261009'.
    APPEND 'A' TO ls_sample-tags.
    APPEND 'B' TO ls_sample-tags.
    ls_sample-child-tcode = 'VA02'.

    CONCATENATE '{"diagnosticId":"SD-01","durationMs":42,"amount":-12.50,"truncated":true,'
                '"postingDate":"2026-10-09","tags":["A","B"],"child":{"tcode":"VA02"}}'
                INTO lv_expected.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_json=>serialize( ls_sample ) exp = lv_expected ).
  ENDMETHOD.

  METHOD empty_table.
    DATA lt_empty TYPE string_table.
    cl_abap_unit_assert=>assert_equals( act = zcl_rx_json=>serialize( lt_empty ) exp = '[]' ).
  ENDMETHOD.

ENDCLASS.
