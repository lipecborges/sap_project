"! Erro de negócio da API: carrega o status HTTP e o código do contrato
"! (ErrorCode em packages/contracts).
CLASS zcx_rx_error DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  CREATE PUBLIC.

  PUBLIC SECTION.
    DATA mv_http_status TYPE i READ-ONLY.
    DATA mv_code TYPE string READ-ONLY.
    DATA mv_text TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING
        textid         LIKE textid OPTIONAL
        previous       LIKE previous OPTIONAL
        iv_http_status TYPE i DEFAULT 500
        iv_code        TYPE string DEFAULT 'INTERNAL'
        iv_text        TYPE string OPTIONAL.

    METHODS get_text REDEFINITION.

ENDCLASS.



CLASS zcx_rx_error IMPLEMENTATION.

  METHOD constructor.
    super->constructor( textid = textid previous = previous ).
    mv_http_status = iv_http_status.
    mv_code = iv_code.
    mv_text = iv_text.
  ENDMETHOD.

  METHOD get_text.
    result = mv_text.
  ENDMETHOD.

ENDCLASS.
