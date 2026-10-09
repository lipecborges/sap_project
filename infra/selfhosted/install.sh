#!/usr/bin/env bash
# Instala (ou reaplica, é idempotente) o Raio-X Self-hosted numa VM Linux com Docker.
#
#   ./install.sh                         # com internet (baixa as imagens) ou imagens já carregadas
#   ./install.sh --images raiox-images.tar   # sem internet: carrega as imagens do tar antes de subir
#   ./install.sh --demo                  # inclui o simulador SAP (sap-mock), para demonstração
#   ./install.sh --build                 # constrói as imagens a partir do código (desenvolvimento)
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

IMAGES_TAR="" DEMO=false BUILD=false
while [ $# -gt 0 ]; do
  case "$1" in
    --images) [ $# -ge 2 ] || die "--images precisa do caminho do tar"; IMAGES_TAR="$(abs_path "$2")"; shift 2 ;;
    --demo) DEMO=true; shift ;;
    --build) BUILD=true; shift ;;
    -h | --help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Opção desconhecida: $1 (use --help)" ;;
  esac
done

check_docker

if [ ! -f .env ]; then
  log "Criando .env a partir de .env.example"
  cp .env.example .env
  chmod 600 .env
else
  log ".env já existe: mantido"
fi

if [ -z "$(env_get SESSION_SECRET)" ]; then
  command -v openssl >/dev/null 2>&1 || die "openssl não encontrado (necessário para gerar os segredos)"
  env_set SESSION_SECRET "$(openssl rand -base64 32)"
  log "SESSION_SECRET gerado"
fi
if [ -z "$(env_get POSTGRES_PASSWORD)" ]; then
  env_set POSTGRES_PASSWORD "$(openssl rand -hex 24)"
  log "POSTGRES_PASSWORD gerado"
fi
if [ "$DEMO" = true ] && ! grep -qE '^COMPOSE_PROFILES=.*demo' .env; then
  env_set COMPOSE_PROFILES demo
  log "Perfil demo ativado (sap-mock)"
fi

if [ -n "$IMAGES_TAR" ]; then
  load_images "$IMAGES_TAR"
elif [ "$BUILD" = true ]; then
  log "Construindo as imagens"
  compose build
else
  log "Baixando as imagens"
  compose pull --ignore-buildable || warn "Não consegui baixar as imagens; seguindo com as que já existem localmente."
fi

log "Subindo os serviços"
compose up -d --no-build
wait_ready 180

port="$(env_get RAIOX_PORT)"
printf '\n\033[1;32mRaio-X instalado.\033[0m Versão %s. Acesse http://<ip-da-vm>:%s\n' "$(api_version)" "${port:-8080}"
echo "Próximos passos: HTTPS com proxy reverso, backup agendado e monitoramento (docs/instalacao-selfhosted.md)."
