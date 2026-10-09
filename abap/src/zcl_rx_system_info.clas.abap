"! Identifica o sistema: SID, mandante e release (ECC, S/4 ou só NetWeaver).
CLASS zcl_rx_system_info DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS get
      RETURNING VALUE(rs_system) TYPE zif_rx_types=>ty_system.

    CLASS-METHODS is_s4
      RETURNING VALUE(rv_s4) TYPE abap_bool.

ENDCLASS.



CLASS zcl_rx_system_info IMPLEMENTATION.

  METHOD get.
    DATA lv_release TYPE cvers-release.

    rs_system-sid = sy-sysid.
    rs_system-client = sy-mandt.

    SELECT SINGLE release FROM cvers INTO lv_release WHERE component = 'SAP_BASIS'. "#EC CI_SUBRC
    rs_system-basis_release = lv_release.

    IF is_s4( ) = abap_true.
      rs_system-release = zif_rx_types=>c_release-s4.
      RETURN.
    ENDIF.

    SELECT SINGLE release FROM cvers INTO lv_release WHERE component = 'SAP_APPL'.
    IF sy-subrc = 0.
      rs_system-release = zif_rx_types=>c_release-ecc.
    ELSE.
      " Só a plataforma ABAP, sem ERP (ex.: ABAP Platform Trial).
      rs_system-release = zif_rx_types=>c_release-nw.
    ENDIF.
  ENDMETHOD.


  METHOD is_s4.
    DATA lv_component TYPE cvers-component.

    SELECT SINGLE component FROM cvers INTO lv_component WHERE component = 'S4CORE'.
    IF sy-subrc = 0.
      rv_s4 = abap_true.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
