#!/usr/bin/env bash
# Restaura o banco do Raio-X a partir de um backup gerado por backup.sh. SUBSTITUI todos os dados atuais.
#
#   ./restore.sh backups/raiox-20260101-021500.dump
#   ./restore.sh --yes arquivo.dump      # sem pedir confirmação (automação)
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

YES=false FILE=""
for arg in "$@"; do
  case "$arg" in
    --yes) YES=true ;;
    -h | --help) sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "Opção desconhecida: $arg" ;;
    *) FILE="$(abs_path "$arg")" ;;
  esac
done
[ -n "$FILE" ] || die "Uso: ./restore.sh [--yes] <arquivo.dump>"
[ -s "$FILE" ] || die "Arquivo não encontrado ou vazio: $FILE"
[ -f .env ] || die ".env não encontrado: rode ./install.sh primeiro"

if [ "$YES" != true ]; then
  printf 'Isto APAGA o banco atual do Raio-X e restaura %s.\nDigite "restaurar" para continuar: ' "$FILE"
  read -r answer || answer=""
  [ "$answer" = "restaurar" ] || die "Cancelado."
fi

log "Garantindo que o banco está de pé"
compose up -d postgres
until compose exec -T postgres pg_isready -U raiox -d postgres >/dev/null 2>&1; do sleep 2; done

# Rede de segurança: backup do estado atual antes de apagar (se o banco existir e estiver íntegro).
if compose exec -T postgres psql -U raiox -d raiox -c 'select 1' >/dev/null 2>&1; then
  log "Backup de segurança do estado atual"
  BACKUP_PREFIX=pre-restore "$SELFHOSTED_DIR/backup.sh" || warn "Backup de segurança falhou; seguindo."
fi

log "Parando a API"
compose stop api

log "Recriando o banco e restaurando"
compose exec -T postgres psql -U raiox -d postgres -v ON_ERROR_STOP=1 \
  -c 'drop database if exists raiox with (force)' \
  -c 'create database raiox owner raiox'
compose exec -T postgres pg_restore -U raiox -d raiox --no-owner --exit-on-error <"$FILE"

log "Subindo a API"
compose up -d api
wait_ready 180
log "Restauração concluída. Versão da API: $(api_version)"
