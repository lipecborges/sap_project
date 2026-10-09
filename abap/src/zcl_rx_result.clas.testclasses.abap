*"* Testes da montagem do resultado
CLASS ltc_result DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS finding_with_evidence FOR TESTING.
    METHODS settle_status FOR TESTING.
    METHODS not_found FOR TESTING.
ENDCLASS.


CLASS ltc_result IMPLEMENTATION.

  METHOD finding_with_evidence.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.

    ls_result = zcl_rx_result=>create( iv_kind = 'SALES_ORDER' iv_id = '4500001' ).
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'SD01.CREDIT_BLOCK'
                                          iv_severity = zif_rx_types=>c_severity-blocking
                                          iv_title    = 'Pedido bloqueado por crédito'
                                          iv_tcode    = 'VKM3'
                                CHANGING  cs_result   = ls_result ).
    zcl_rx_result=>add_evidence( EXPORTING iv_source = 'VBUK'
                                           iv_field  = 'CMGST'
                                           iv_value  = 'B'
                                           iv_label  = 'Status de crédito'
                                 CHANGING  cs_result = ls_result ).
    READ TABLE ls_result-findings INDEX 1 INTO ls_finding. "#EC CI_SUBRC
    cl_abap_unit_assert=>assert_equals( act = lines( ls_finding-evidence ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-suggested_action-tcode exp = 'VKM3' ).
  ENDMETHOD.

  METHOD settle_status.
    DATA ls_result TYPE zif_rx_types=>ty_result.

    ls_result = zcl_rx_result=>create( iv_kind = 'X' iv_id = '1' ).
    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'XX01.INFO'
                                          iv_severity = zif_rx_types=>c_severity-info
                                          iv_title    = 'Info'
                                CHANGING  cs_result   = ls_result ).
    zcl_rx_result=>settle_status( CHANGING cs_result = ls_result ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = zif_rx_types=>c_status-ok ).

    zcl_rx_result=>add_finding( EXPORTING iv_code     = 'XX01.WARN'
                                          iv_severity = zif_rx_types=>c_severity-warning
                                          iv_title    = 'Atenção'
                                CHANGING  cs_result   = ls_result ).
    zcl_rx_result=>settle_status( CHANGING cs_result = ls_result ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = zif_rx_types=>c_status-problem_found ).
  ENDMETHOD.

  METHOD not_found.
    DATA ls_result TYPE zif_rx_types=>ty_result.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.

    ls_result = zcl_rx_result=>create( iv_kind = 'SALES_ORDER' iv_id = '9' ).
    zcl_rx_result=>set_not_found( EXPORTING iv_prefix = 'SD01'
                                            iv_title  = 'Pedido não encontrado'
                                            iv_detail = 'x'
                                            iv_source = 'VBAK'
                                            iv_field  = 'VBELN'
                                            iv_value  = '9'
                                            iv_label  = 'Pedido'
                                  CHANGING  cs_result = ls_result ).
    READ TABLE ls_result-findings INDEX 1 INTO ls_finding. "#EC CI_SUBRC
    cl_abap_unit_assert=>assert_equals( act = ls_result-status exp = zif_rx_types=>c_status-not_found ).
    cl_abap_unit_assert=>assert_equals( act = ls_finding-code exp = 'SD01.NOT_FOUND' ).
  ENDMETHOD.

ENDCLASS.
