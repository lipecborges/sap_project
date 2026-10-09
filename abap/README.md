# Add-on ABAP (pacote `ZRX`)

API REST do Raio-X dentro do SAP. **Sintaxe NetWeaver 7.00** (decisão D17), verificada pelo abaplint.

## Objetos

| Objeto | Papel |
|---|---|
| `ZCL_RX_HTTP_HANDLER` | Handler do serviço ICF. Só traduz HTTP ↔ roteador |
| `ZCL_RX_ROUTER` | Rotas `/v1/health`, `/v1/me`, `/v1/diagnostics`, `/v1/diagnostics/{id}` |
| `ZCL_RX_JSON` | Serializador JSON próprio (RTTI), sem `/UI2/CL_JSON` |
| `ZCL_RX_PARAMS` | Leitura e validação dos parâmetros (mesmas regras do TypeScript) |
| `ZCL_RX_DIAGNOSTIC_REGISTRY` | Descobre as classes que implementam `ZIF_RX_DIAGNOSTIC` |
| `ZCL_RX_AUTH` / `ZIF_RX_AUTHORIZER` | Autorização pelo objeto `ZRX_DIAG` |
| `ZCL_RX_SYSTEM_INFO` | SID, mandante e release (ECC, S4 ou NW) |
| `ZIF_RX_TYPES` | Tipos do contrato (espelham `packages/contracts`) |
| `ZIF_RX_DIAGNOSTIC` | Interface de cada diagnóstico |
| `ZCX_RX_ERROR` | Erro com status HTTP e código do contrato |
| `ZCL_RX_RESULT` / `ZCL_RX_FORMAT` | Montagem do resultado e formatação (datas ISO, valores e quantidades em pt-BR, zeros à esquerda) |
| `ZCL_RX_CONFIG` / `ZCL_RX_LOGGER` | Leitura da `ZRX_CONFIG` e gravação da `ZRX_LOG` |

### Diagnósticos

| Módulo | Leitor (interface + real) | Diagnósticos | Apoio |
|---|---|---|---|
| SD | `ZIF_RX_SD_READER` / `ZCL_RX_SD_READER` | `ZCL_RX_DIAG_SD01`, `ZCL_RX_DIAG_SD10` | `ZCL_RX_SD_STAGE` (etapa travada) |
| MM | `ZIF_RX_MM_READER` / `ZCL_RX_MM_READER` | `ZCL_RX_DIAG_MM02`, `ZCL_RX_DIAG_MM10` | |
| PP | `ZIF_RX_PP_READER` / `ZCL_RX_PP_READER` | `ZCL_RX_DIAG_PP01`, `ZCL_RX_DIAG_PP03`, `ZCL_RX_DIAG_PP04` | `ZCL_RX_PP_STATUS_MAP` (situação), `ZCL_RX_PP_VIEW` (apresentação) |

O registro descobre os diagnósticos sozinho (classes que implementam `ZIF_RX_DIAGNOSTIC`). Cada diagnóstico tem testes com um dublê do leitor; o leitor real é validado no SAP ([pendências T-SAP](../docs/pendencias-de-teste.md)). Regras de desenvolvimento: [guia ABAP](../docs/abap-guia-desenvolvimento.md).

### Tabelas

| Tabela | Conteúdo |
|---|---|
| `ZRX_LOG` | Uma linha por execução (usuário, diagnóstico, status, duração, parâmetros) |
| `ZRX_CONFIG` | `DISABLED:<id>`, `PP_LATE_TOLERANCE_DAYS`, `MAX_ROWS`, `PP_FIELD_TABLES` |
| `ZRX_PPSTAT_MAP` | Mapeamento de status (sistema, usuário ou campo) para situações como "Aprovada" |

## Instalar num sistema SAP (7.02+)

1. Instale o [abapGit](https://abapgit.org) e crie o pacote `ZRX`.
2. Clone este repositório no abapGit (a pasta `/abap/src/` já está configurada em `.abapgit.xml`) e ative os objetos.
3. Na **SICF**, crie o serviço `/default_host/sap/bc/zrx/api` com o handler `ZCL_RX_HTTP_HANDLER` e logon padrão.
4. Teste: `curl -u USUARIO:SENHA "http://<host>:<porta>/sap/bc/zrx/api/v1/health?sap-client=100"`.

> Passo a passo completo, com autorização (`ZRX_DIAG`, role `ZRX_USER`), configuração e solução de problemas: [INSTALACAO.md](INSTALACAO.md). Sem a autorização, a execução de diagnósticos é negada (403).
> Em NW 7.00/7.01 (sem abapGit), a entrega é por ordem de transporte (projeto, seção 5.5).

## Testes

- `pnpm abaplint`: sintaxe 7.00 e regras de estilo.
- `pnpm test:abap`: roda o ABAP Unit **fora do SAP** (abaplint transpiler + [open-abap](https://github.com/open-abap/open-abap)). Pega regressões de lógica a cada commit, mas não substitui o teste no SAP real, porque o runtime é outra implementação.
