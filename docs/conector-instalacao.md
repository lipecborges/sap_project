# Instalação do conector Raio-X

O conector fica na rede da empresa, ao lado do SAP, e se conecta **de dentro para fora** à nuvem do Raio-X. Serve só para a versão Cloud; no Self-hosted a API fala direto com o SAP.

## Requisitos

- Uma máquina (ou contêiner) na rede interna que alcance o SAP por HTTP/HTTPS.
- Docker, ou Node.js 22 para rodar sem contêiner.
- Add-on ZRX instalado e o serviço ICF `/sap/bc/zrx/api/v1` ativo no SAP.
- **Firewall: apenas saída TCP 443** para o endereço do Raio-X. Nenhuma regra de entrada.

## Gerar o token

1. Entre no Raio-X como administrador e abra **Administração → Conectores**.
2. Clique em **Novo conector**, dê um nome (ex.: "Planta São Paulo") e confirme.
3. Copie o token exibido. Ele aparece **uma única vez**; se perder, revogue o conector e crie outro.
4. Associe o conector ao sistema SAP em **Administração → Sistemas SAP**.

## Executar com Docker

```bash
docker run -d --name raiox-connector --restart unless-stopped \
  -e RAIOX_URL=wss://acme.raiox.app \
  -e RAIOX_CONNECTOR_TOKEN=<token> \
  -e SAP_BASE_URL=https://sap.empresa.local:44300 \
  raiox/connector
```

Para ver o estado: `docker logs -f raiox-connector`. Quando a linha `"conector online"` aparecer, o conector está pronto; a tela de conectores mostra "online".

## Variáveis

| Variável | Obrigatória | Descrição |
|---|---|---|
| `RAIOX_URL` | sim | Endereço da API: `wss://…` (produção) ou `ws://…` (só desenvolvimento) |
| `RAIOX_CONNECTOR_TOKEN` | sim | Token gerado na administração |
| `SAP_BASE_URL` | sim | Origem do SAP na rede interna, ex.: `https://sap.empresa.local:44300` |
| `SAP_API_PATH` | não | Caminho do add-on (padrão `/sap/bc/zrx/api/v1`). O conector recusa qualquer outro caminho |
| `SAP_TIMEOUT_MS` | não | Limite por chamada ao SAP (padrão `30000`) |
| `SAP_CA_FILE` | não | Arquivo PEM com a CA que assina o certificado do SAP, se for interna. Monte o arquivo no contêiner (`-v /caminho/ca.pem:/ca.pem -e SAP_CA_FILE=/ca.pem`) |
| `LOG_LEVEL` | não | `debug`, `info` (padrão), `warn`, `error` ou `silent` |

## Operação

- Se a conexão cair, o conector reconecta sozinho (1 s a 60 s entre tentativas).
- Token inválido ou revogado: o conector registra o erro e encerra. Gere um novo token e reinicie.
- `docker stop` (SIGTERM) encerra de forma graciosa, aguardando as chamadas em andamento.
- Os logs são JSON, uma linha por evento, sem senhas, cabeçalhos nem corpos de resposta.

Detalhes do protocolo: [conector-protocolo.md](conector-protocolo.md).
