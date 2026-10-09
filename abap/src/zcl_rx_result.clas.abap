"! Montagem do resultado padrão (contrato DiagnosticResult).
"! Mantém o formato igual em todos os diagnósticos e no sap-mock.
CLASS zcl_rx_result DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS create
      IMPORTING iv_kind          TYPE csequence
                iv_id            TYPE csequence
      RETURNING VALUE(rs_result) TYPE zif_rx_types=>ty_result.

    "! Acrescenta um achado. Evidências entram depois com ADD_EVIDENCE.
    CLASS-METHODS add_finding
      IMPORTING iv_code     TYPE csequence
                iv_severity TYPE csequence
                iv_title    TYPE csequence
                iv_detail   TYPE csequence OPTIONAL
                iv_tcode    TYPE csequence OPTIONAL
                iv_action   TYPE csequence OPTIONAL
      CHANGING  cs_result   TYPE zif_rx_types=>ty_result.

    "! Evidência no último achado incluído.
    CLASS-METHODS add_evidence
      IMPORTING iv_source TYPE csequence
                iv_field  TYPE csequence
                iv_value  TYPE csequence
                iv_label  TYPE csequence
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    CLASS-METHODS add_fact
      IMPORTING iv_id     TYPE csequence
                iv_label  TYPE csequence
                iv_value  TYPE csequence
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    CLASS-METHODS add_related
      IMPORTING iv_kind   TYPE csequence
                iv_id     TYPE csequence
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    "! Coluna de tabela: chave estável + rótulo.
    CLASS-METHODS add_column
      IMPORTING iv_key   TYPE csequence
                iv_label TYPE csequence
      CHANGING  cs_table TYPE zif_rx_types=>ty_table.

    "! NOT_FOUND com um achado INFO "<prefixo>.NOT_FOUND".
    CLASS-METHODS set_not_found
      IMPORTING iv_prefix TYPE csequence
                iv_title  TYPE csequence
                iv_detail TYPE csequence
                iv_source TYPE csequence
                iv_field  TYPE csequence
                iv_value  TYPE csequence
                iv_label  TYPE csequence
      CHANGING  cs_result TYPE zif_rx_types=>ty_result.

    "! OK vira PROBLEM_FOUND se houver achado BLOCKING ou WARNING.
    CLASS-METHODS settle_status
      CHANGING cs_result TYPE zif_rx_types=>ty_result.

ENDCLASS.



CLASS zcl_rx_result IMPLEMENTATION.

  METHOD create.
    rs_result-version = '1.0'.
    rs_result-status = zif_rx_types=>c_status-ok.
    rs_result-object-kind = iv_kind.
    rs_result-object-id = iv_id.
  ENDMETHOD.


  METHOD add_finding.
    DATA ls_finding TYPE zif_rx_types=>ty_finding.

    ls_finding-code = iv_code.
    ls_finding-severity = iv_severity.
    ls_finding-title = iv_title.
    ls_finding-detail = iv_detail.
    ls_finding-suggested_action-tcode = iv_tcode.
    ls_finding-suggested_action-description = iv_action.
    APPEND ls_finding TO cs_result-findings.
  ENDMETHOD.


  METHOD add_evidence.
    DATA ls_evidence TYPE zif_rx_types=>ty_evidence.
    DATA lv_last TYPE i.
    FIELD-SYMBOLS <ls_finding> TYPE zif_rx_types=>ty_finding.

    lv_last = lines( cs_result-findings ).
    IF lv_last = 0.
      RETURN.
    ENDIF.
    READ TABLE cs_result-findings INDEX lv_last ASSIGNING <ls_finding>.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    ls_evidence-source = iv_source.
    ls_evidence-field = iv_field.
    ls_evidence-value = iv_value.
    ls_evidence-label = iv_label.
    APPEND ls_evidence TO <ls_finding>-evidence.
  ENDMETHOD.


  METHOD add_fact.
    DATA ls_fact TYPE zif_rx_types=>ty_fact.

    ls_fact-id = iv_id.
    ls_fact-label = iv_label.
    ls_fact-value = iv_value.
    APPEND ls_fact TO cs_result-facts.
  ENDMETHOD.


  METHOD add_related.
    DATA ls_ref TYPE zif_rx_types=>ty_object_ref.

    ls_ref-kind = iv_kind.
    ls_ref-id = iv_id.
    APPEND ls_ref TO cs_result-related.
  ENDMETHOD.


  METHOD add_column.
    DATA lv_text TYPE string.

    lv_text = iv_key.
    APPEND lv_text TO cs_table-keys.
    lv_text = iv_label.
    APPEND lv_text TO cs_table-columns.
  ENDMETHOD.


  METHOD set_not_found.
    DATA lv_code TYPE string.

    CONCATENATE iv_prefix '.NOT_FOUND' INTO lv_code.
    cs_result-status = zif_rx_types=>c_status-not_found.
    add_finding( EXPORTING iv_code     = lv_code
                           iv_severity = zif_rx_types=>c_severity-info
                           iv_title    = iv_title
                           iv_detail   = iv_detail
                 CHANGING  cs_result   = cs_result ).
    add_evidence( EXPORTING iv_source = iv_source
                            iv_field  = iv_field
                            iv_value  = iv_value
                            iv_label  = iv_label
                  CHANGING  cs_result = cs_result ).
  ENDMETHOD.


  METHOD settle_status.
    FIELD-SYMBOLS <ls_finding> TYPE zif_rx_types=>ty_finding.

    IF cs_result-status <> zif_rx_types=>c_status-ok.
      RETURN.
    ENDIF.
    LOOP AT cs_result-findings ASSIGNING <ls_finding>
        WHERE severity = zif_rx_types=>c_severity-blocking
           OR severity = zif_rx_types=>c_severity-warning.
      cs_result-status = zif_rx_types=>c_status-problem_found.
      RETURN.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
