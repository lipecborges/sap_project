#!/usr/bin/env bash
# Funções comuns de install.sh, update.sh, backup.sh e restore.sh (use com: source "$(dirname "$0")/lib.sh").
# shellcheck shell=bash

CALLER_DIR="$PWD"
SELFHOSTED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SELFHOSTED_DIR"

# Caminho informado pelo usuário, relativo à pasta de onde o script foi chamado.
abs_path() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$CALLER_DIR" "$1" ;; esac; }

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33maviso:\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31merro:\033[0m %s\n' "$*" >&2
  exit 1
}

# Compara versões numéricas: version_ge 2.24.5 2.20 → verdadeiro.
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

# Valor de uma chave do .env (vazio se ausente ou comentada).
env_get() { { grep -E "^$1=" .env 2>/dev/null || true; } | tail -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }

# Grava/atualiza CHAVE=valor no .env sem tocar no resto do arquivo.
env_set() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  if grep -qE "^$key=" .env; then
    awk -v k="$key" -v v="$value" 'BEGIN{FS=OFS="="} $1==k {print k "=" v; next} {print}' .env >"$tmp"
  else
    cat .env >"$tmp"
    printf '%s=%s\n' "$key" "$value" >>"$tmp"
  fi
  cat "$tmp" >.env
  rm -f "$tmp"
}

check_docker() {
  command -v docker >/dev/null 2>&1 || die "Docker não encontrado. Instale o Docker Engine 24 ou mais novo."
  docker info >/dev/null 2>&1 || die "Não consegui falar com o Docker. O serviço está ativo e seu usuário está no grupo 'docker'?"
  local engine compose
  engine="$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"
  compose="$(docker compose version --short 2>/dev/null || true)"
  [ -n "$compose" ] || die "Docker Compose v2 não encontrado (comando 'docker compose'). Instale o plugin docker-compose-plugin."
  version_ge "${engine:-0}" 24.0 || die "Docker $engine é antigo demais: use 24.0 ou mais novo."
  version_ge "${compose#v}" 2.24 || die "Docker Compose $compose é antigo demais: use 2.24 ou mais novo."
  log "Docker $engine, Compose ${compose#v}"
}

compose() { docker compose "$@"; }

# Espera a API responder /api/ready (banco acessível) por até $1 segundos. Testa de dentro do contêiner,
# então funciona mesmo sem a porta publicada.
wait_ready() {
  local timeout="${1:-120}" waited=0
  log "Aguardando a API ficar pronta (até ${timeout}s)"
  until compose exec -T api wget -qO- http://127.0.0.1:3000/api/ready >/dev/null 2>&1; do
    waited=$((waited + 3))
    if [ "$waited" -ge "$timeout" ]; then
      compose ps || true
      compose logs --tail=40 api || true
      die "A API não ficou pronta em ${timeout}s. Veja os logs acima (docker compose logs api)."
    fi
    sleep 3
  done
  log "API pronta"
}

# Versão da API em execução.
api_version() {
  compose exec -T api wget -qO- http://127.0.0.1:3000/api/health 2>/dev/null |
    sed -n 's/.*"version":"\([^"]*\)".*/\1/p'
}

# Carrega as imagens de um tar gerado por tools/release/save-images.sh (instalação sem internet).
load_images() {
  [ -f "$1" ] || die "Arquivo de imagens não encontrado: $1"
  log "Carregando imagens de $1"
  docker load -i "$1"
}
