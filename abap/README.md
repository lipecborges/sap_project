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

Os diagnósticos (SD-01, MM-02, PP-01, PP-03, PP-04) entram nas Fases 1a/1b.

## Instalar num sistema SAP (7.02+)

1. Instale o [abapGit](https://abapgit.org) e crie o pacote `ZRX`.
2. Clone este repositório no abapGit (a pasta `/abap/src/` já está configurada em `.abapgit.xml`) e ative os objetos.
3. Na **SICF**, crie o serviço `/default_host/sap/bc/zrx/api` com o handler `ZCL_RX_HTTP_HANDLER` e logon padrão.
4. Teste: `curl -u USUARIO:SENHA "http://<host>:<porta>/sap/bc/zrx/api/v1/health?sap-client=100"`.

> Até a Fase 1a, o objeto de autorização `ZRX_DIAG` ainda não existe, e por isso a execução de diagnósticos é negada.
> Em NW 7.00/7.01 (sem abapGit), a entrega é por ordem de transporte (projeto, seção 5.5).

## Testes

- `pnpm abaplint`: sintaxe 7.00 e regras de estilo.
- `pnpm test:abap`: roda o ABAP Unit **fora do SAP** (abaplint transpiler + [open-abap](https://github.com/open-abap/open-abap)). Pega regressões de lógica a cada commit, mas não substitui o teste no SAP real, porque o runtime é outra implementação.
