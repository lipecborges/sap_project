"! Formatação independente das configurações do usuário (formato de data e
"! decimal do SU01), para que o JSON seja sempre igual ao do sap-mock.
CLASS zcl_rx_format DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Remove zeros à esquerda (equivale à conversão ALPHA de saída).
    CLASS-METHODS alpha_out
      IMPORTING iv_value       TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

    "! Completa com zeros à esquerda até iv_length, se o valor for numérico.
    CLASS-METHODS alpha_in
      IMPORTING iv_value       TYPE csequence
                iv_length      TYPE i
      RETURNING VALUE(rv_text) TYPE string.

    "! AAAAMMDD → "AAAA-MM-DD" (data vazia → "").
    CLASS-METHODS date_iso
      IMPORTING iv_date        TYPE d
      RETURNING VALUE(rv_text) TYPE string.

    "! "AAAA-MM-DD" → AAAAMMDD.
    CLASS-METHODS date_from_iso
      IMPORTING iv_text        TYPE csequence
      RETURNING VALUE(rv_date) TYPE d.

    "! Número no padrão brasileiro: 1234.5 → "1.234,5" (até iv_decimals casas, sem zeros à direita).
    CLASS-METHODS number_br
      IMPORTING iv_value       TYPE p
                iv_decimals    TYPE i DEFAULT 3
      RETURNING VALUE(rv_text) TYPE string.

    "! Quantidade com unidade: "1.000 PC".
    CLASS-METHODS quantity
      IMPORTING iv_value       TYPE p
                iv_unit        TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

    "! Valor monetário: BRL → "R$ 1.150,00"; outras moedas → "1.150,00 USD".
    CLASS-METHODS money
      IMPORTING iv_amount      TYPE p
                iv_currency    TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

    "! Inteiro como texto, sem espaços: 42 → "42", -3 → "-3".
    CLASS-METHODS int
      IMPORTING iv_value       TYPE i
      RETURNING VALUE(rv_text) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS group_thousands
      IMPORTING iv_digits      TYPE string
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.



CLASS zcl_rx_format IMPLEMENTATION.

  METHOD alpha_out.
    rv_text = iv_value.
    CONDENSE rv_text.
    SHIFT rv_text LEFT DELETING LEADING '0'.
    IF rv_text IS INITIAL AND iv_value IS NOT INITIAL.
      rv_text = '0'.
    ENDIF.
  ENDMETHOD.


  METHOD alpha_in.
    DATA lv_text TYPE string.
    DATA lv_missing TYPE i.
    DATA lv_zeros TYPE string.

    lv_text = iv_value.
    CONDENSE lv_text.
    rv_text = lv_text.
    IF lv_text IS INITIAL OR lv_text CN '0123456789'.
      RETURN.
    ENDIF.
    lv_missing = iv_length - strlen( lv_text ).
    DO lv_missing TIMES.
      CONCATENATE lv_zeros '0' INTO lv_zeros.
    ENDDO.
    CONCATENATE lv_zeros lv_text INTO rv_text.
  ENDMETHOD.


  METHOD date_iso.
    DATA lv_text TYPE c LENGTH 8.

    IF iv_date IS INITIAL OR iv_date = '00000000'.
      RETURN.
    ENDIF.
    lv_text = iv_date.
    CONCATENATE lv_text(4) '-' lv_text+4(2) '-' lv_text+6(2) INTO rv_text.
  ENDMETHOD.


  METHOD date_from_iso.
    DATA lv_text TYPE string.

    lv_text = iv_text.
    IF strlen( lv_text ) <> 10.
      RETURN.
    ENDIF.
    CONCATENATE lv_text(4) lv_text+5(2) lv_text+8(2) INTO rv_date.
  ENDMETHOD.


  METHOD number_br.
    DATA lv_abs TYPE p LENGTH 16 DECIMALS 3.
    DATA lv_text TYPE string.
    DATA lv_int TYPE string.
    DATA lv_dec TYPE string.
    DATA lv_len TYPE i.

    lv_abs = abs( iv_value ).
    lv_text = lv_abs.
    CONDENSE lv_text NO-GAPS.
    SPLIT lv_text AT '.' INTO lv_int lv_dec.
    " Mantém no máximo iv_decimals casas e tira zeros à direita.
    lv_len = strlen( lv_dec ).
    IF lv_len > iv_decimals.
      lv_dec = lv_dec(iv_decimals).
    ENDIF.
    SHIFT lv_dec RIGHT DELETING TRAILING '0'.
    CONDENSE lv_dec.

    rv_text = group_thousands( lv_int ).
    IF lv_dec IS NOT INITIAL.
      CONCATENATE rv_text ',' lv_dec INTO rv_text.
    ENDIF.
    IF iv_value < 0.
      CONCATENATE '-' rv_text INTO rv_text.
    ENDIF.
  ENDMETHOD.


  METHOD quantity.
    rv_text = number_br( iv_value ).
    IF iv_unit IS NOT INITIAL.
      CONCATENATE rv_text iv_unit INTO rv_text SEPARATED BY space.
    ENDIF.
  ENDMETHOD.


  METHOD money.
    DATA lv_abs TYPE p LENGTH 16 DECIMALS 2.
    DATA lv_text TYPE string.
    DATA lv_int TYPE string.
    DATA lv_dec TYPE string.

    lv_abs = abs( iv_amount ).
    lv_text = lv_abs.
    CONDENSE lv_text NO-GAPS.
    SPLIT lv_text AT '.' INTO lv_int lv_dec.
    IF strlen( lv_dec ) < 2.
      CONCATENATE lv_dec '00' INTO lv_dec.
      lv_dec = lv_dec(2).
    ENDIF.
    lv_int = group_thousands( lv_int ).
    CONCATENATE lv_int ',' lv_dec INTO rv_text.
    IF iv_amount < 0.
      CONCATENATE '-' rv_text INTO rv_text.
    ENDIF.
    IF iv_currency = 'BRL'.
      CONCATENATE 'R$' rv_text INTO rv_text SEPARATED BY space.
    ELSE.
      CONCATENATE rv_text iv_currency INTO rv_text SEPARATED BY space.
    ENDIF.
  ENDMETHOD.


  METHOD int.
    rv_text = iv_value.
    CONDENSE rv_text NO-GAPS.
    IF rv_text CA '-'.
      REPLACE '-' IN rv_text WITH ''.
      CONCATENATE '-' rv_text INTO rv_text.
    ENDIF.
  ENDMETHOD.


  METHOD group_thousands.
    DATA lv_len TYPE i.
    DATA lv_pos TYPE i.
    DATA lv_chunk TYPE string.

    lv_len = strlen( iv_digits ).
    IF lv_len <= 3.
      rv_text = iv_digits.
      RETURN.
    ENDIF.
    lv_pos = lv_len MOD 3.
    IF lv_pos > 0.
      rv_text = iv_digits(lv_pos).
    ENDIF.
    WHILE lv_pos < lv_len.
      lv_chunk = iv_digits+lv_pos(3).
      IF rv_text IS INITIAL.
        rv_text = lv_chunk.
      ELSE.
        CONCATENATE rv_text '.' lv_chunk INTO rv_text.
      ENDIF.
      lv_pos = lv_pos + 3.
    ENDWHILE.
  ENDMETHOD.

ENDCLASS.
