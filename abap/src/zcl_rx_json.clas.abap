"! Serializador JSON via RTTI, compatível com NetWeaver 7.00
"! (não depende de /UI2/CL_JSON nem do JSON nativo do sXML).
"! Regras:
"! - nomes de componentes viram camelCase (SUGGESTED_ACTION -> suggestedAction);
"! - estruturas totalmente vazias são omitidas (campos opcionais do contrato);
"! - ABAP_BOOL vira true/false; datas viram "AAAA-MM-DD" (vazia = null);
"! - números saem como número JSON; o resto sai como texto.
CLASS zcl_rx_json DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS serialize
      IMPORTING ig_data        TYPE any
      RETURNING VALUE(rv_json) TYPE string.

    CLASS-METHODS escape_string
      IMPORTING iv_text        TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS to_camel_case
      IMPORTING iv_name        TYPE csequence
      RETURNING VALUE(rv_name) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS serialize_structure
      IMPORTING ig_data        TYPE any
                io_type        TYPE REF TO cl_abap_structdescr
      RETURNING VALUE(rv_json) TYPE string.

    CLASS-METHODS serialize_table
      IMPORTING ig_data        TYPE any
      RETURNING VALUE(rv_json) TYPE string.

    CLASS-METHODS serialize_element
      IMPORTING ig_data        TYPE any
                io_type        TYPE REF TO cl_abap_typedescr
      RETURNING VALUE(rv_json) TYPE string.

    CLASS-METHODS format_number
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_json) TYPE string.

    CLASS-METHODS quote
      IMPORTING iv_text        TYPE csequence
      RETURNING VALUE(rv_json) TYPE string.

ENDCLASS.



CLASS zcl_rx_json IMPLEMENTATION.

  METHOD serialize.
    DATA lo_type TYPE REF TO cl_abap_typedescr.
    DATA lo_struct TYPE REF TO cl_abap_structdescr.

    lo_type = cl_abap_typedescr=>describe_by_data( ig_data ).
    CASE lo_type->kind.
      WHEN cl_abap_typedescr=>kind_struct.
        lo_struct ?= lo_type.
        rv_json = serialize_structure( ig_data = ig_data io_type = lo_struct ).
      WHEN cl_abap_typedescr=>kind_table.
        rv_json = serialize_table( ig_data ).
      WHEN cl_abap_typedescr=>kind_elem.
        rv_json = serialize_element( ig_data = ig_data io_type = lo_type ).
      WHEN OTHERS.
        " Referências e objetos não fazem parte do contrato.
        rv_json = 'null'.
    ENDCASE.
  ENDMETHOD.


  METHOD serialize_structure.
    DATA lt_parts TYPE string_table.
    DATA lv_part TYPE string.
    DATA lv_name TYPE string.
    DATA lv_value TYPE string.
    DATA lo_field_type TYPE REF TO cl_abap_typedescr.
    FIELD-SYMBOLS <ls_component> TYPE abap_compdescr.
    FIELD-SYMBOLS <lg_field> TYPE any.

    LOOP AT io_type->components ASSIGNING <ls_component>.
      ASSIGN COMPONENT <ls_component>-name OF STRUCTURE ig_data TO <lg_field>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      lo_field_type = cl_abap_typedescr=>describe_by_data( <lg_field> ).
      IF lo_field_type->kind = cl_abap_typedescr=>kind_struct AND <lg_field> IS INITIAL.
        CONTINUE.
      ENDIF.
      lv_name = to_camel_case( <ls_component>-name ).
      lv_value = serialize( <lg_field> ).
      CONCATENATE '"' lv_name '":' lv_value INTO lv_part.
      APPEND lv_part TO lt_parts.
    ENDLOOP.

    CONCATENATE LINES OF lt_parts INTO rv_json SEPARATED BY ','.
    CONCATENATE '{' rv_json '}' INTO rv_json.
  ENDMETHOD.


  METHOD serialize_table.
    DATA lt_parts TYPE string_table.
    DATA lv_part TYPE string.
    FIELD-SYMBOLS <lt_table> TYPE ANY TABLE.
    FIELD-SYMBOLS <lg_line> TYPE any.

    ASSIGN ig_data TO <lt_table>.
    LOOP AT <lt_table> ASSIGNING <lg_line>.
      lv_part = serialize( <lg_line> ).
      APPEND lv_part TO lt_parts.
    ENDLOOP.

    CONCATENATE LINES OF lt_parts INTO rv_json SEPARATED BY ','.
    CONCATENATE '[' rv_json ']' INTO rv_json.
  ENDMETHOD.


  METHOD serialize_element.
    DATA lv_text TYPE string.
    DATA lv_name TYPE string.

    lv_name = io_type->get_relative_name( ).
    IF lv_name = 'ABAP_BOOL' OR lv_name = 'BOOLE_D' OR lv_name = 'XFELD'.
      IF ig_data IS INITIAL.
        rv_json = 'false'.
      ELSE.
        rv_json = 'true'.
      ENDIF.
      RETURN.
    ENDIF.

    CASE io_type->type_kind.
      WHEN cl_abap_typedescr=>typekind_int
          OR cl_abap_typedescr=>typekind_int1
          OR cl_abap_typedescr=>typekind_int2
          OR cl_abap_typedescr=>typekind_packed
          OR cl_abap_typedescr=>typekind_float.
        lv_text = ig_data.
        rv_json = format_number( lv_text ).

      WHEN cl_abap_typedescr=>typekind_date.
        IF ig_data IS INITIAL OR ig_data = '00000000'.
          rv_json = 'null'.
        ELSE.
          lv_text = ig_data.
          CONCATENATE '"' lv_text(4) '-' lv_text+4(2) '-' lv_text+6(2) '"' INTO rv_json.
        ENDIF.

      WHEN cl_abap_typedescr=>typekind_time.
        lv_text = ig_data.
        CONCATENATE '"' lv_text(2) ':' lv_text+2(2) ':' lv_text+4(2) '"' INTO rv_json.

      WHEN OTHERS.
        lv_text = ig_data.
        rv_json = quote( lv_text ).
    ENDCASE.
  ENDMETHOD.


  METHOD format_number.
    " Conversão ABAP para texto coloca o sinal no fim ("12.5-"): JSON exige no início.
    DATA lv_last TYPE i.

    rv_json = iv_text.
    CONDENSE rv_json NO-GAPS.
    lv_last = strlen( rv_json ) - 1.
    IF lv_last > 0 AND rv_json+lv_last(1) = '-'.
      rv_json = rv_json(lv_last).
      CONCATENATE '-' rv_json INTO rv_json.
    ENDIF.
  ENDMETHOD.


  METHOD quote.
    rv_json = escape_string( iv_text ).
    CONCATENATE '"' rv_json '"' INTO rv_json.
  ENDMETHOD.


  METHOD escape_string.
    rv_text = iv_text.
    REPLACE ALL OCCURRENCES OF '\' IN rv_text WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN rv_text WITH '\"'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_text WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_text WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN rv_text WITH '\t'.
  ENDMETHOD.


  METHOD to_camel_case.
    DATA lv_name TYPE string.
    DATA lt_words TYPE string_table.
    DATA lv_first TYPE c LENGTH 1.
    DATA lv_rest TYPE string.
    DATA lv_rest_length TYPE i.
    FIELD-SYMBOLS <lv_word> TYPE string.

    lv_name = iv_name.
    TRANSLATE lv_name TO LOWER CASE.
    SPLIT lv_name AT '_' INTO TABLE lt_words.

    LOOP AT lt_words ASSIGNING <lv_word>.
      IF sy-tabix = 1.
        rv_name = <lv_word>.
        CONTINUE.
      ENDIF.
      IF <lv_word> IS INITIAL.
        CONTINUE.
      ENDIF.
      lv_first = <lv_word>.
      TRANSLATE lv_first TO UPPER CASE.
      lv_rest_length = strlen( <lv_word> ) - 1.
      CLEAR lv_rest.
      IF lv_rest_length > 0.
        lv_rest = <lv_word>+1(lv_rest_length).
      ENDIF.
      CONCATENATE rv_name lv_first lv_rest INTO rv_name.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
