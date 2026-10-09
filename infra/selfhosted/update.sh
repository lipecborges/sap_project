#!/usr/bin/env bash
# Atualiza o Raio-X: backup, novas imagens, reinício, espera ficar pronto e mostra a versão.
# As migrações do banco rodam sozinhas quando a API nova sobe.
#
#   ./update.sh                              # baixa as imagens novas (RAIOX_API_IMAGE no .env)
#   ./update.sh --images raiox-images.tar    # sem internet: carrega as imagens do tar
#   ./update.sh --build                      # reconstrói as imagens a partir do código
#   ./update.sh --no-backup                  # pula o backup (não recomendado)
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

IMAGES_TAR="" BUILD=false BACKUP=true
while [ $# -gt 0 ]; do
  case "$1" in
    --images) [ $# -ge 2 ] || die "--images precisa do caminho do tar"; IMAGES_TAR="$(abs_path "$2")"; shift 2 ;;
    --build) BUILD=true; shift ;;
    --no-backup) BACKUP=false; shift ;;
    -h | --help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Opção desconhecida: $1 (use --help)" ;;
  esac
done

check_docker
[ -f .env ] || die ".env não encontrado: rode ./install.sh primeiro"

before="$(api_version || true)"
log "Versão atual: ${before:-desconhecida}"

if [ "$BACKUP" = true ]; then
  "$SELFHOSTED_DIR/backup.sh"
fi

if [ -n "$IMAGES_TAR" ]; then
  load_images "$IMAGES_TAR"
elif [ "$BUILD" = true ]; then
  log "Construindo as imagens"
  compose build
else
  log "Baixando as imagens novas"
  compose pull --ignore-buildable
fi

log "Aplicando"
compose up -d --no-build --remove-orphans
wait_ready 180

after="$(api_version || true)"
printf '\n\033[1;32mAtualização concluída.\033[0m Versão: %s -> %s\n' "${before:-?}" "${after:-?}"
docker image prune -f >/dev/null 2>&1 || true
