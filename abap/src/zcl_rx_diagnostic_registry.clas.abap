"! Registro dos diagnósticos disponíveis.
"! Descobre automaticamente as classes globais que implementam ZIF_RX_DIAGNOSTIC;
"! nos testes, use iv_discover = abap_false e REGISTER para injetar dublês.
CLASS zcl_rx_diagnostic_registry DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_diagnostics TYPE STANDARD TABLE OF REF TO zif_rx_diagnostic WITH DEFAULT KEY.

    METHODS constructor
      IMPORTING iv_discover TYPE abap_bool DEFAULT abap_true.

    METHODS register
      IMPORTING io_diagnostic TYPE REF TO zif_rx_diagnostic.

    METHODS get_all
      RETURNING VALUE(rt_diagnostics) TYPE ty_diagnostics.

    METHODS get_by_id
      IMPORTING iv_id                TYPE csequence
      RETURNING VALUE(ro_diagnostic) TYPE REF TO zif_rx_diagnostic.

  PRIVATE SECTION.
    DATA mt_diagnostics TYPE ty_diagnostics.

    METHODS discover.

ENDCLASS.



CLASS zcl_rx_diagnostic_registry IMPLEMENTATION.

  METHOD constructor.
    IF iv_discover = abap_true.
      discover( ).
    ENDIF.
  ENDMETHOD.


  METHOD register.
    APPEND io_diagnostic TO mt_diagnostics.
  ENDMETHOD.


  METHOD get_all.
    rt_diagnostics = mt_diagnostics.
  ENDMETHOD.


  METHOD get_by_id.
    DATA lo_diagnostic TYPE REF TO zif_rx_diagnostic.
    DATA ls_meta TYPE zif_rx_types=>ty_diag_meta.

    LOOP AT mt_diagnostics INTO lo_diagnostic.
      ls_meta = lo_diagnostic->get_metadata( ).
      IF ls_meta-id = iv_id.
        ro_diagnostic = lo_diagnostic.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD discover.
    " RELTYPE '1' = implementação de interface; VERSION '1' = ativa (validar no sistema).
    DATA lt_classes TYPE STANDARD TABLE OF seometarel-clsname WITH DEFAULT KEY.
    DATA lv_class TYPE seometarel-clsname.
    DATA lo_diagnostic TYPE REF TO zif_rx_diagnostic.

    SELECT clsname FROM seometarel INTO TABLE lt_classes
      WHERE refclsname = 'ZIF_RX_DIAGNOSTIC'
        AND reltype = '1'
        AND version = '1'
      ORDER BY clsname.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_classes INTO lv_class.
      TRY.
          CREATE OBJECT lo_diagnostic TYPE (lv_class).
          APPEND lo_diagnostic TO mt_diagnostics.
        CATCH cx_sy_create_object_error.
          " Classe abstrata ou inconsistente: fica fora do catálogo.
          CONTINUE.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
