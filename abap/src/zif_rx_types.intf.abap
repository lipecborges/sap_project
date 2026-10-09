"! Tipos do contrato da API REST do Raio-X.
"! Espelham packages/contracts (TypeScript): o nome de cada componente vira
"! camelCase no JSON (ex.: SUGGESTED_ACTION -> suggestedAction).
"! Sintaxe compatível com NetWeaver 7.00.
INTERFACE zif_rx_types PUBLIC.

  CONSTANTS c_addon_version TYPE string VALUE '0.1.0'.
  CONSTANTS c_api_version TYPE string VALUE 'v1'.

  CONSTANTS:
    BEGIN OF c_status,
      ok            TYPE string VALUE 'OK',
      problem_found TYPE string VALUE 'PROBLEM_FOUND',
      not_found     TYPE string VALUE 'NOT_FOUND',
      error         TYPE string VALUE 'ERROR',
    END OF c_status.

  CONSTANTS:
    BEGIN OF c_severity,
      blocking TYPE string VALUE 'BLOCKING',
      warning  TYPE string VALUE 'WARNING',
      info     TYPE string VALUE 'INFO',
    END OF c_severity.

  CONSTANTS:
    BEGIN OF c_release,
      ecc TYPE string VALUE 'ECC',
      s4  TYPE string VALUE 'S4',
      nw  TYPE string VALUE 'NW',
    END OF c_release.

  CONSTANTS:
    BEGIN OF c_data_type,
      document TYPE string VALUE 'DOCUMENT',
      string   TYPE string VALUE 'STRING',
      integer  TYPE string VALUE 'INTEGER',
      date     TYPE string VALUE 'DATE',
      enum     TYPE string VALUE 'ENUM',
    END OF c_data_type.

  TYPES:
    BEGIN OF ty_param,
      name  TYPE string,
      value TYPE string,
    END OF ty_param,
    ty_params TYPE STANDARD TABLE OF ty_param WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_param_meta,
      name      TYPE string,
      label     TYPE string,
      data_type TYPE string,
      required  TYPE abap_bool,
      options   TYPE string_table,
    END OF ty_param_meta,
    ty_param_metas TYPE STANDARD TABLE OF ty_param_meta WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_diag_meta,
      id      TYPE string,
      version TYPE string,
      module  TYPE string,
      kind    TYPE string,
      title   TYPE string,
      params  TYPE ty_param_metas,
    END OF ty_diag_meta,
    ty_diag_metas TYPE STANDARD TABLE OF ty_diag_meta WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_evidence,
      source TYPE string,
      field  TYPE string,
      value  TYPE string,
      label  TYPE string,
    END OF ty_evidence,
    ty_evidences TYPE STANDARD TABLE OF ty_evidence WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_action,
      tcode       TYPE string,
      description TYPE string,
    END OF ty_action.

  TYPES:
    BEGIN OF ty_finding,
      code             TYPE string,
      severity         TYPE string,
      title            TYPE string,
      detail           TYPE string,
      evidence         TYPE ty_evidences,
      suggested_action TYPE ty_action,
    END OF ty_finding,
    ty_findings TYPE STANDARD TABLE OF ty_finding WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_object_ref,
      kind TYPE string,
      id   TYPE string,
    END OF ty_object_ref,
    ty_object_refs TYPE STANDARD TABLE OF ty_object_ref WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_system,
      sid           TYPE string,
      client        TYPE string,
      release       TYPE string,
      basis_release TYPE string,
    END OF ty_system.

  TYPES:
    BEGIN OF ty_fact,
      id    TYPE string,
      label TYPE string,
      value TYPE string,
    END OF ty_fact,
    ty_facts TYPE STANDARD TABLE OF ty_fact WITH DEFAULT KEY.

  TYPES ty_rows TYPE STANDARD TABLE OF string_table WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_table,
      id        TYPE string,
      title     TYPE string,
      keys      TYPE string_table,
      columns   TYPE string_table,
      rows      TYPE ty_rows,
      truncated TYPE abap_bool,
    END OF ty_table,
    ty_tables TYPE STANDARD TABLE OF ty_table WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_result,
      diagnostic_id TYPE string,
      version       TYPE string,
      object        TYPE ty_object_ref,
      system        TYPE ty_system,
      status        TYPE string,
      findings      TYPE ty_findings,
      related       TYPE ty_object_refs,
      facts         TYPE ty_facts,
      tables        TYPE ty_tables,
      executed_at   TYPE string,
      duration_ms   TYPE i,
    END OF ty_result.

  TYPES:
    BEGIN OF ty_health,
      addon_version TYPE string,
      api_version   TYPE string,
      system        TYPE ty_system,
      diagnostics   TYPE string_table,
    END OF ty_health.

  TYPES:
    BEGIN OF ty_me,
      user        TYPE string,
      language    TYPE string,
      diagnostics TYPE string_table,
    END OF ty_me.

  TYPES:
    BEGIN OF ty_diagnostics_response,
      diagnostics TYPE ty_diag_metas,
    END OF ty_diagnostics_response.

  TYPES:
    BEGIN OF ty_error_detail,
      code    TYPE string,
      message TYPE string,
    END OF ty_error_detail,
    BEGIN OF ty_error_response,
      error TYPE ty_error_detail,
    END OF ty_error_response.

ENDINTERFACE.
