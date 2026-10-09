#!/usr/bin/env bash
# Teste ponta a ponta do pacote self-hosted numa rede SEM internet (D23), incluindo PostgreSQL:
#   1) sobe postgres + API + sap-mock isolados da internet;
#   2) roda o fluxo completo (login, diagnóstico, painel, assistente, web, /api/ready, /metrics);
#   3) reinicia a API e confere que a sessão do login continua válida (sessões ficam no banco).
# Da raiz do repositório: pnpm test:selfhosted
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ ! -f .env ]; then
  cp .env.example .env
  created_env=true
fi
# Segredos descartáveis de teste, só se o .env ainda não os tiver.
[ -n "$(env_get SESSION_SECRET)" ] || env_set SESSION_SECRET "$(openssl rand -base64 32)"
[ -n "$(env_get POSTGRES_PASSWORD)" ] || env_set POSTGRES_PASSWORD "$(openssl rand -hex 24)"

files=(-f docker-compose.yml -f docker-compose.offline.yml --profile demo --profile test)
project() { docker compose "${files[@]}" "$@"; }
cleanup() {
  status=$?
  [ "$status" -eq 0 ] || project logs --tail=60 api postgres || true
  project down -v --remove-orphans || true
  [ "${created_env:-false}" = true ] && rm -f .env
  exit "$status"
}
trap cleanup EXIT

# SMOKE_SKIP_BUILD=1 usa as imagens raiox/*:local que já existem (ex.: construídas com um proxy corporativo).
build=(--build)
[ "${SMOKE_SKIP_BUILD:-}" = 1 ] && build=(--no-build)
project up -d "${build[@]}" --wait api sap-mock

log "Fluxo completo (rede sem internet)"
project run --rm smoke

log "Reiniciando a API: a sessão tem que sobreviver"
project restart api
project up -d --wait api
project run --rm -e SMOKE_PHASE=resume smoke

log "Smoke test do pacote self-hosted: OK"
