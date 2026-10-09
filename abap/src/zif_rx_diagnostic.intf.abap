"! Contrato de um diagnóstico. Toda classe que implementa esta interface
"! é registrada automaticamente (ZCL_RX_DIAGNOSTIC_REGISTRY).
INTERFACE zif_rx_diagnostic PUBLIC.

  "! Metadados: id (ex.: SD-01), versão, módulo, tipo e parâmetros.
  METHODS get_metadata
    RETURNING VALUE(rs_meta) TYPE zif_rx_types=>ty_diag_meta.

  "! Executa o diagnóstico. Somente leitura: nunca altera dados nem faz COMMIT.
  "! O roteador preenche diagnosticId, system, executedAt e durationMs.
  METHODS execute
    IMPORTING it_params        TYPE zif_rx_types=>ty_params
    RETURNING VALUE(rs_result) TYPE zif_rx_types=>ty_result
    RAISING   zcx_rx_error.

ENDINTERFACE.
