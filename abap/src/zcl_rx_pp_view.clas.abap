"! Apresentação comum dos diagnósticos de produção (PP-01, PP-03 e PP-04):
"! status em texto, percentuais, datas e a tabela de componentes.
CLASS zcl_rx_pp_view DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Status separados por espaço: "REL PCNF MSPT".
    CLASS-METHODS status_text
      IMPORTING it_status      TYPE zif_rx_pp_reader=>ty_statuses
      RETURNING VALUE(rv_text) TYPE string.

    "! Parte / total como percentual inteiro (arredondado); total zero -> 0.
    CLASS-METHODS percent
      IMPORTING iv_part       TYPE zif_rx_pp_reader=>ty_qty
                iv_total      TYPE zif_rx_pp_reader=>ty_qty
      RETURNING VALUE(rv_pct) TYPE i.

    "! Data AAAA-MM-DD ou "—" quando vazia.
    CLASS-METHODS date_or_dash
      IMPORTING iv_date        TYPE d
      RETURNING VALUE(rv_text) TYPE string.

    "! Junta os textos com IV_SEPARATOR (sem espaço depois dele) e, se IV_SPACE, com um espaço após o separador.
    CLASS-METHODS join
      IMPORTING it_values      TYPE string_table
                iv_separator   TYPE csequence
                iv_space       TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(rv_text) TYPE string.

    "! Tabela "components" (necessário, retirado, pendente, estoque livre e falta?) da ordem.
    CLASS-METHODS components_table
      IMPORTING iv_aufnr        TYPE zif_rx_pp_reader=>ty_aufnr
                it_components   TYPE zif_rx_pp_reader=>ty_components
      RETURNING VALUE(rs_table) TYPE zif_rx_types=>ty_table.

ENDCLASS.



CLASS zcl_rx_pp_view IMPLEMENTATION.

  METHOD status_text.
    DATA lv_status TYPE string.
    FIELD-SYMBOLS <lv_item> TYPE zif_rx_pp_reader=>ty_status.

    LOOP AT it_status ASSIGNING <lv_item>.
      lv_status = <lv_item>.
      IF rv_text IS INITIAL.
        rv_text = lv_status.
      ELSE.
        CONCATENATE rv_text lv_status INTO rv_text SEPARATED BY space.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD percent.
    DATA lv_value TYPE p LENGTH 16 DECIMALS 3.

    IF iv_total = 0.
      RETURN.
    ENDIF.
    lv_value = iv_part * 100 / iv_total.
    rv_pct = lv_value.
  ENDMETHOD.


  METHOD date_or_dash.
    IF iv_date IS INITIAL.
      rv_text = '—'.
    ELSE.
      rv_text = zcl_rx_format=>date_iso( iv_date ).
    ENDIF.
  ENDMETHOD.


  METHOD join.
    DATA lv_item TYPE string.
    DATA lv_first TYPE abap_bool VALUE abap_true.

    LOOP AT it_values INTO lv_item.
      IF lv_first = abap_true.
        rv_text = lv_item.
        lv_first = abap_false.
      ELSE.
        CONCATENATE rv_text iv_separator INTO rv_text.
        IF iv_space = abap_true.
          CONCATENATE rv_text lv_item INTO rv_text SEPARATED BY space.
        ELSE.
          CONCATENATE rv_text lv_item INTO rv_text.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD components_table.
    DATA lt_row TYPE string_table.
    DATA lv_pending TYPE zif_rx_pp_reader=>ty_qty.
    DATA lv_text TYPE string.
    FIELD-SYMBOLS <ls_component> TYPE zif_rx_pp_reader=>ty_component.

    rs_table-id = 'components'.
    rs_table-title = 'Componentes'.
    zcl_rx_result=>add_column( EXPORTING iv_key = 'material' iv_label = 'Material' CHANGING cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'description' iv_label = 'Descrição' CHANGING cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'required' iv_label = 'Necessário' CHANGING cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'withdrawn' iv_label = 'Retirado' CHANGING cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'pending' iv_label = 'Pendente' CHANGING cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'stock' iv_label = 'Estoque livre' CHANGING cs_table = rs_table ).
    zcl_rx_result=>add_column( EXPORTING iv_key = 'short' iv_label = 'Falta?' CHANGING cs_table = rs_table ).

    LOOP AT it_components ASSIGNING <ls_component> WHERE aufnr = iv_aufnr.
      CLEAR lt_row.
      lv_text = zcl_rx_format=>alpha_out( <ls_component>-material ).
      APPEND lv_text TO lt_row.
      lv_text = <ls_component>-description.
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_format=>quantity( iv_value = <ls_component>-required iv_unit = <ls_component>-unit ).
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_format=>quantity( iv_value = <ls_component>-withdrawn iv_unit = <ls_component>-unit ).
      APPEND lv_text TO lt_row.
      lv_pending = <ls_component>-required - <ls_component>-withdrawn.
      lv_text = zcl_rx_format=>quantity( iv_value = lv_pending iv_unit = <ls_component>-unit ).
      APPEND lv_text TO lt_row.
      lv_text = zcl_rx_format=>quantity( iv_value = <ls_component>-stock iv_unit = <ls_component>-unit ).
      APPEND lv_text TO lt_row.
      IF zcl_rx_pp_status_map=>is_short( <ls_component> ) = abap_true.
        lv_text = 'Sim'.
      ELSE.
        lv_text = 'Não'.
      ENDIF.
      APPEND lv_text TO lt_row.
      APPEND lt_row TO rs_table-rows.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
