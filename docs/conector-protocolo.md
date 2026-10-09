# Protocolo conector ↔ gateway (v1)

Decisão D35: o conector roda na rede do cliente e abre uma conexão **de saída** (WebSocket sobre TLS) até a API do Raio-X. A API usa essa conexão para enviar as requisições HTTP destinadas ao add-on SAP. Nenhuma porta de entrada é aberta no cliente.

Implementação: `services/api/src/connector/` (gateway) e `services/connector/` (conector).

## Conexão e autenticação

- Endpoint: `GET /connector/v1/ws` (upgrade para WebSocket). Produção: `wss://`.
- Cabeçalho `Authorization: Bearer <token>` na requisição de upgrade. O token é gerado na tela de administração (conectores), aparece uma única vez e é guardado apenas como hash SHA-256.
- Token inválido ou revogado: a API responde **401** antes do upgrade. O conector trata 401 como definitivo e para.
- Revogar o conector na administração fecha a conexão ativa (código 4001).
- Se o mesmo conector conectar de novo, a nova conexão substitui a anterior, que é fechada (código 4000).

## Quadros

Todos os quadros são mensagens de texto com um objeto JSON, no máximo 5 MB cada. Quadros binários, JSON inválido ou quadros fora do formato fecham a conexão (1003 ou 1008).

### Conector → API

```json
{ "type": "hello", "v": 1, "version": "0.1.0", "sapBaseUrlHost": "sap.empresa.local:44300" }
```

Primeiro quadro, enviado logo após conectar (prazo de 10 s). `sapBaseUrlHost` é opcional e só informativo.

```json
{ "type": "response", "id": "…", "status": 200, "contentType": "application/json", "body": "…" }
```

Resposta HTTP do SAP. `body` é sempre texto; `contentType` é omitido se o SAP não enviou.

```json
{ "type": "error", "id": "…", "code": "FORBIDDEN_PATH", "message": "…" }
```

O conector não conseguiu atender. Códigos: `FORBIDDEN_PATH`, `FORBIDDEN_METHOD`, `SAP_TIMEOUT`, `SAP_UNREACHABLE`, `RESPONSE_TOO_LARGE`, `INTERNAL`. A API converte qualquer `error` em `503 SAP_UNAVAILABLE`.

### API → conector

```json
{ "type": "welcome", "v": 1, "connectorId": "cn_ab12cd34ef56" }
```

Resposta ao `hello`. A partir daqui o conector é considerado **online**.

```json
{
  "type": "request", "id": "uuid", "method": "GET",
  "path": "/sap/bc/zrx/api/v1/me?sap-client=100",
  "headers": { "authorization": "Basic …", "accept": "application/json" },
  "body": "…", "timeoutMs": 30000
}
```

`id` é único por requisição e casa com o `response`/`error`. `path` inclui a query. `body` só existe em `POST`. As requisições são concorrentes e as respostas podem chegar em qualquer ordem.

## Limites e prazos

- Até **32 requisições simultâneas** por conector; acima disso a API responde 503 imediatamente.
- Sem resposta em `timeoutMs` (mais 2 s de folga), a API responde `503 SAP_UNAVAILABLE`. Se o socket fechar, todas as pendentes falham com 503.
- Conector offline: `503 SAP_UNAVAILABLE` ("Conector … offline").
- **Heartbeat:** a API envia `ping` do WebSocket a cada 20 s e derruba a conexão se não houver `pong` em 45 s. O conector reinicia a conexão se ficar 60 s sem receber `ping`.
- Reconexão do conector: backoff exponencial de 1 s a 60 s, com jitter.

## Segurança no conector

O conector só executa o que a política local permite, mesmo que a nuvem peça outra coisa:

- métodos apenas `GET` e `POST`;
- o caminho (normalizado, sem `..`) deve estar sob `SAP_API_PATH` (padrão `/sap/bc/zrx/api/v1`), senão `FORBIDDEN_PATH`;
- só os cabeçalhos `authorization`, `accept` e `content-type` são repassados;
- credenciais, cabeçalhos e corpos nunca são gravados em log.

## Versionamento

O campo `v` identifica a versão do protocolo (hoje `1`). Mudanças incompatíveis usam novo caminho (`/connector/v2/ws`), mantendo o v1 enquanto houver conectores instalados.
