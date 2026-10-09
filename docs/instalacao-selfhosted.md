# Instalação Self-hosted

Guia para instalar, operar e atualizar o Raio-X numa VM Linux do cliente. O pacote roda **sem acesso à internet** (decisão D23): as imagens podem ser levadas num arquivo, e o assistente de IA funciona em modo `demo` (regras locais) sem nenhuma chamada externa.

Arquivos do pacote: `infra/selfhosted/` (`docker-compose.yml`, `.env.example`, `install.sh`, `update.sh`, `backup.sh`, `restore.sh`).

## Requisitos da VM

| Item | Mínimo | Observação |
|---|---|---|
| Sistema | Linux x86_64 (Ubuntu 22.04+, Debian 12+, RHEL 9+) | |
| Docker Engine | 24.0 ou mais novo | com o plugin **Docker Compose 2.24+** (`docker compose version`) |
| CPU / memória | 2 vCPU / 4 GB | a API e o PostgreSQL têm limite de 1 GB cada |
| Disco | 20 GB livres | banco, logs (rotacionados em 5 × 10 MB por contêiner) e backups |
| Rede | a VM alcança o SAP (HTTP/HTTPS da ICF) | internet só para baixar imagens e para `AI_PROVIDER=anthropic` |
| Utilitários | `bash`, `openssl` | usados pelos scripts |

No SAP, o add-on ABAP precisa estar instalado e o serviço ICF ativo (veja [abap/INSTALACAO.md](../abap/INSTALACAO.md)).

## Portas

| Porta | Quem | Exposta? |
|---|---|---|
| `8080` (muda com `RAIOX_PORT`) | API + interface web (HTTP) | sim, na VM. Em produção, deixe só o proxy HTTPS (443) chegar nela |
| `5432` | PostgreSQL | **não**: só a rede interna do Compose enxerga o banco |

## Instalação

```bash
git clone <repositório> /opt/raiox && cd /opt/raiox/infra/selfhosted
./install.sh
```

O script é idempotente (pode rodar de novo sem estragar nada). Ele: confere as versões do Docker/Compose; cria o `.env` a partir de `.env.example` se não existir; gera `SESSION_SECRET` e `POSTGRES_PASSWORD` com `openssl` quando estão vazios; baixa as imagens, sobe os serviços e espera `/api/ready` responder.

Depois da primeira execução, **edite o `.env`**: `SAP_BASE_URL` (endereço do SAP visto de dentro da VM) e `SAP_CLIENT`, e rode `./install.sh` de novo. Opções: `--demo` (sobe também o simulador SAP, para demonstração), `--build` (constrói as imagens do código), `--images <tar>` (sem internet).

> Guarde uma cópia do `.env` num cofre. **Não troque `SESSION_SECRET`** depois de instalar: sem a chave original, as sessões ativas e a senha SAP cifrada no banco ficam ilegíveis (os usuários só precisam entrar de novo). `POSTGRES_PASSWORD` vale na criação do volume do banco; para trocar depois, use `ALTER USER` dentro do PostgreSQL e atualize o `.env`.

### Instalação sem internet

Numa máquina com internet e Docker, na raiz do repositório:

```bash
tools/release/save-images.sh            # gera raiox-images.tar e raiox-images.tar.sha256
```

Copie o repositório (ou só a pasta `infra/selfhosted/`) e o `raiox-images.tar` para a VM e rode:

```bash
sha256sum -c raiox-images.tar.sha256
./install.sh --images /caminho/raiox-images.tar    # equivale a: docker load -i raiox-images.tar && docker compose up -d
```

O tar contém a API (com a interface web embutida), a imagem do PostgreSQL e, por padrão, o simulador SAP (`WITH_DEMO=false` para omitir).

## Atualização

```bash
./update.sh                                # baixa as imagens novas
./update.sh --images raiox-images.tar      # sem internet
```

O script faz **backup antes**, atualiza as imagens, reaplica (`up -d`), espera `/api/ready` e mostra a versão antiga e a nova. As migrações do banco rodam sozinhas quando a API nova sobe. Se algo der errado, volte as imagens anteriores e use `./restore.sh` com o backup feito pelo script.

## Backup e restauração

```bash
./backup.sh                  # grava backups/raiox-AAAAMMDD-HHMMSS.dump (pg_dump, formato custom)
./restore.sh backups/raiox-20260101-021500.dump
```

- Os backups mais velhos que `BACKUP_RETENTION_DAYS` (padrão 14) são apagados a cada execução.
- Agende no `cron` do root: `15 2 * * * /opt/raiox/infra/selfhosted/backup.sh >> /var/log/raiox-backup.log 2>&1`.
- Copie `backups/` para fora da VM (o dump contém a senha SAP das sessões ativas, mas **cifrada** com `SESSION_SECRET`; guarde o `.env` separado).
- `restore.sh` pede a confirmação digitada (`restaurar`), tira um backup `pre-restore-*` do estado atual, para a API, recria o banco, restaura e sobe a API de novo.
- Teste a restauração numa VM de homologação pelo menos uma vez.

## HTTPS com proxy reverso

O contêiner da API fala HTTP. Coloque na frente um proxy com TLS (certificado da empresa) e, no `.env`:

```
COOKIE_SECURE=true     # cookie de sessão só por HTTPS e cabeçalho HSTS
TRUST_PROXY=true       # padrão; o proxy envia X-Forwarded-For (IP real nos logs, na auditoria e nos limites)
```

Aplique com `docker compose up -d`. Para que só o proxy alcance a API, publique a porta apenas no loopback: no `.env`, `RAIOX_PORT=127.0.0.1:8080`.

**nginx**

```nginx
server {
  listen 443 ssl http2;
  server_name raiox.empresa.local;
  ssl_certificate     /etc/ssl/raiox/fullchain.pem;
  ssl_certificate_key /etc/ssl/raiox/privkey.pem;

  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Request-Id $request_id;
    # Respostas do assistente chegam por streaming (SSE): sem buffer.
    proxy_buffering off;
    proxy_read_timeout 300s;
  }
}
```

**Caddy** (certificado automático ou `tls cert.pem key.pem`)

```
raiox.empresa.local {
  reverse_proxy 127.0.0.1:8080 {
    flush_interval -1
  }
}
```

Se a API ficar exposta direto a clientes (sem proxy), use `TRUST_PROXY=false`, senão qualquer cliente pode forjar o `X-Forwarded-For`.

## Monitoramento

| Endpoint | Para quê |
|---|---|
| `GET /api/health` | **vivo**: o processo responde (não toca no banco nem no SAP). Traz versão e modo |
| `GET /api/ready` | **pronto**: o banco responde. É o healthcheck do Compose; `503` se o banco cair |
| `GET /metrics` | métricas Prometheus. **Desligado** (404) até definir `METRICS_TOKEN` no `.env`; exige `Authorization: Bearer <token>` |

Métricas: processo Node (CPU, memória, event loop), `http_request_duration_seconds` (por rota, método e status) e `raiox_diagnostic_duration_seconds` (por diagnóstico e resultado). Exemplo de coleta:

```yaml
scrape_configs:
  - job_name: raiox
    metrics_path: /metrics
    authorization: { credentials: "<METRICS_TOKEN>" }
    static_configs: [{ targets: ["raiox.empresa.local:443"] }]
```

Não exponha `/metrics` na internet: bloqueie no proxy se o Prometheus estiver na mesma rede.

Logs: JSON, uma linha por evento, com `reqId`. O cabeçalho `x-request-id` é aceito do proxy (ou gerado) e devolvido nas respostas, o mesmo id da auditoria. `authorization`, `cookie`, `set-cookie` e campos `password` saem como `[REDACTED]`. Veja com `docker compose logs -f api`.

### Limites de requisições

Por IP (memória do processo): `RATE_LIMIT_MAX` (600) por `RATE_LIMIT_WINDOW_SECONDS` (60) no geral e `RATE_LIMIT_LOGIN_MAX` (10) por `RATE_LIMIT_LOGIN_WINDOW_SECONDS` (60) em `/auth/login` e `/auth/check`, por IP + usuário. Excedido, a API responde `429` com `{"error":{"code":"RATE_LIMITED",...}}`. O limite é por réplica; no Cloud com várias réplicas será preciso um armazenamento compartilhado.

## Solução de problemas

| Sintoma | O que verificar |
|---|---|
| `install.sh`: "Compose ... antigo demais" | atualize o plugin `docker-compose-plugin` (2.24+) |
| `required variable ... is missing` | `SESSION_SECRET` ou `POSTGRES_PASSWORD` vazio no `.env`: rode `./install.sh` |
| API não fica pronta | `docker compose logs api postgres`; o banco tem que estar `healthy` (`docker compose ps`) |
| `password authentication failed` | `POSTGRES_PASSWORD` do `.env` difere da usada ao criar o volume. Restaure a senha original ou recrie o volume (apaga os dados) |
| Login dá 401 com senha certa | `SAP_BASE_URL` alcançável da VM? Teste: `docker compose exec api wget -qO- $SAP_BASE_URL/sap/bc/zrx/api/v1/health` |
| Login dá 429 | muitas tentativas por IP + usuário; espere a janela (veja `Retry-After`) |
| Todos os usuários aparecem com o mesmo IP na auditoria | falta o `X-Forwarded-For` no proxy (ou `TRUST_PROXY=false`) |
| Sessão cai logo após o login com HTTPS | `COOKIE_SECURE=true` sem HTTPS no navegador, ou o proxy não envia `X-Forwarded-Proto` |
| `/metrics` dá 404 | `METRICS_TOKEN` não definido (desligado de propósito); 401 = token errado |
| Disco enchendo | `docker system df`; apague backups antigos; os logs já rotacionam |
| Sem internet e `docker compose pull` falha | normal: use `--images raiox-images.tar` |

Teste automatizado do pacote (no repositório, exige Docker): `pnpm test:selfhosted` sobe tudo numa rede **sem internet**, roda o fluxo completo, reinicia a API e confere que a sessão sobrevive.
