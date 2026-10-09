"! Leitura dos dados de ordens de produção (PP-01, PP-03 e PP-04).
"! Os tipos usam tipos ABAP embutidos, já harmonizados entre ECC e S/4. A interface não tem
"! lógica de negócio: interpretar status, atraso e falta de material é papel de
"! ZCL_RX_PP_STATUS_MAP e dos diagnósticos. Nos testes, um dublê local a implementa.
"! Os números de ordem trafegam como no banco (12 posições, com zeros à esquerda).
INTERFACE zif_rx_pp_reader PUBLIC.

  TYPES ty_aufnr TYPE c LENGTH 12.
  TYPES ty_aufnrs TYPE STANDARD TABLE OF ty_aufnr WITH DEFAULT KEY.
  "! Abreviação do status de sistema no idioma EN (TJ02T-TXT04): REL, PCNF, MSPT…
  TYPES ty_status TYPE c LENGTH 4.
  TYPES ty_statuses TYPE STANDARD TABLE OF ty_status WITH DEFAULT KEY.
  TYPES ty_qty TYPE p LENGTH 13 DECIMALS 3.

  TYPES:
    BEGIN OF ty_user_status,
      profile TYPE c LENGTH 8,
      code    TYPE c LENGTH 5,
      text    TYPE c LENGTH 40,
    END OF ty_user_status,
    ty_user_statuses TYPE STANDARD TABLE OF ty_user_status WITH DEFAULT KEY.

  " Cabeçalho da ordem. As datas programadas já vêm com o fallback para as datas base
  " (GSTRS vazio -> GSTRP; GLTRS vazio -> GLTRP) e o fim real é GLTRI (ou GETRI).
  TYPES:
    BEGIN OF ty_order,
      aufnr          TYPE ty_aufnr,
      objnr          TYPE c LENGTH 22,
      material       TYPE c LENGTH 40,
      description    TYPE c LENGTH 40,
      plant          TYPE c LENGTH 4,
      order_type     TYPE c LENGTH 4,
      mrp_controller TYPE c LENGTH 3,
      scheduler      TYPE c LENGTH 3,
      unit           TYPE c LENGTH 3,
      system_status  TYPE ty_statuses,
      user_status    TYPE ty_user_statuses,
      "! Valores da ZRX_PPSTAT_MAP (SOURCE_TYPE = FIELD) que a ordem satisfaz.
      field_marks    TYPE string_table,
      planned        TYPE ty_qty,
      confirmed      TYPE ty_qty,
      scrap          TYPE ty_qty,
      delivered      TYPE ty_qty,
      basic_start    TYPE d,
      basic_finish   TYPE d,
      sched_start    TYPE d,
      sched_finish   TYPE d,
      actual_start   TYPE d,
      actual_finish  TYPE d,
      sales_order    TYPE c LENGTH 10,
      sales_item     TYPE n LENGTH 6,
      "! Data pedida pelo cliente (VBEP-EDATU do pedido de venda vinculado).
      requested_date TYPE d,
    END OF ty_order,
    ty_orders TYPE STANDARD TABLE OF ty_order WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_operation,
      aufnr         TYPE ty_aufnr,
      vornr         TYPE c LENGTH 4,
      work_center   TYPE c LENGTH 8,
      description   TYPE c LENGTH 40,
      status        TYPE ty_statuses,
      sched_start   TYPE d,
      sched_finish  TYPE d,
      actual_start  TYPE d,
      actual_finish TYPE d,
      confirmed     TYPE ty_qty,
      scrap         TYPE ty_qty,
    END OF ty_operation,
    ty_operations TYPE STANDARD TABLE OF ty_operation WITH DEFAULT KEY.

  " Componente (reserva). STOCK é o estoque livre (MARD-LABST) do depósito da reserva
  " ou, sem depósito, de todo o centro. MISSING é o indicador de falta da reserva.
  TYPES:
    BEGIN OF ty_component,
      aufnr       TYPE ty_aufnr,
      material    TYPE c LENGTH 40,
      description TYPE c LENGTH 40,
      unit        TYPE c LENGTH 3,
      required    TYPE ty_qty,
      withdrawn   TYPE ty_qty,
      stock       TYPE ty_qty,
      missing     TYPE abap_bool,
    END OF ty_component,
    ty_components TYPE STANDARD TABLE OF ty_component WITH DEFAULT KEY.

  TYPES:
    BEGIN OF ty_confirmation,
      aufnr    TYPE ty_aufnr,
      date     TYPE d,
      vornr    TYPE c LENGTH 4,
      yield    TYPE ty_qty,
      scrap    TYPE ty_qty,
      user     TYPE c LENGTH 12,
      reversed TYPE abap_bool,
    END OF ty_confirmation,
    ty_confirmations TYPE STANDARD TABLE OF ty_confirmation WITH DEFAULT KEY.

  " Linha da ZRX_PPSTAT_MAP. SOURCE_TYPE: SYSTEM_STATUS, USER_STATUS ou FIELD.
  " SOURCE_VALUE: abreviação EN do status de sistema; PERFIL/STATUS (ex.: ZPP00001/E0002)
  " do status de usuário; TABELA-CAMPO=VALOR para FIELD. SITUATION: APPROVED ou BLOCKS_RELEASE.
  TYPES:
    BEGIN OF ty_status_map,
      source_type  TYPE c LENGTH 20,
      source_value TYPE c LENGTH 60,
      situation    TYPE c LENGTH 30,
    END OF ty_status_map,
    ty_status_maps TYPE STANDARD TABLE OF ty_status_map WITH DEFAULT KEY.

  " Configuração lida da ZRX_CONFIG (PP_LATE_TOLERANCE_DAYS e MAX_ROWS).
  TYPES:
    BEGIN OF ty_settings,
      tolerance_days TYPE i,
      max_rows       TYPE i,
    END OF ty_settings.

  " Filtros da lista de ordens (PP-04). Campos vazios não filtram.
  TYPES:
    BEGIN OF ty_filter,
      plant          TYPE c LENGTH 4,
      mrp_controller TYPE c LENGTH 3,
      order_type     TYPE c LENGTH 4,
      material       TYPE c LENGTH 40,
      date_from      TYPE d,
      date_to        TYPE d,
    END OF ty_filter.

  "! Cabeçalho, status de sistema/usuário e pedido de venda da ordem. Vazio (AUFNR inicial) se não existir.
  METHODS get_order
    IMPORTING iv_aufnr        TYPE ty_aufnr
    RETURNING VALUE(rs_order) TYPE ty_order.

  "! Ordens do centro com os filtros, no mesmo formato do GET_ORDER, por número de ordem.
  METHODS find_orders
    IMPORTING is_filter        TYPE ty_filter
    RETURNING VALUE(rt_orders) TYPE ty_orders.

  "! Existe alguma ordem de produção no centro (sem outros filtros)?
  METHODS has_orders
    IMPORTING iv_plant         TYPE csequence
    RETURNING VALUE(rv_exists) TYPE abap_bool.

  METHODS get_operations
    IMPORTING it_aufnr             TYPE ty_aufnrs
    RETURNING VALUE(rt_operations) TYPE ty_operations.

  METHODS get_components
    IMPORTING it_aufnr             TYPE ty_aufnrs
    RETURNING VALUE(rt_components) TYPE ty_components.

  "! Apontamentos em ordem cronológica. IV_SINCE (opcional) limita a data de lançamento.
  METHODS get_confirmations
    IMPORTING it_aufnr                TYPE ty_aufnrs
              iv_since                TYPE d OPTIONAL
    RETURNING VALUE(rt_confirmations) TYPE ty_confirmations.

  METHODS get_status_map
    RETURNING VALUE(rt_map) TYPE ty_status_maps.

  METHODS get_settings
    RETURNING VALUE(rs_settings) TYPE ty_settings.

  "! Autorização C_AFKO_AWK (centro e tipo de ordem, atividade 03). (validar)
  METHODS is_authorized
    IMPORTING iv_plant             TYPE csequence
              iv_order_type        TYPE csequence
    RETURNING VALUE(rv_authorized) TYPE abap_bool.

ENDINTERFACE.
