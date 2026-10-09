"! Verificação de autorização do usuário para um diagnóstico.
"! Interface separada para permitir dublês nos testes unitários.
INTERFACE zif_rx_authorizer PUBLIC.

  METHODS is_allowed
    IMPORTING iv_diagnostic_id  TYPE csequence
    RETURNING VALUE(rv_allowed) TYPE abap_bool.

ENDINTERFACE.
