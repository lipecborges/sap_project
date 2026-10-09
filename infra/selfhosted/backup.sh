#!/usr/bin/env bash
# Backup do banco do Raio-X: pg_dump em formato custom para ./backups/raiox-AAAAMMDD-HHMMSS.dump
# e remoção dos backups mais velhos que BACKUP_RETENTION_DAYS (padrão 14).
#
#   ./backup.sh
# Agendar (cron do root, todo dia às 02:15):  15 2 * * * /opt/raiox/infra/selfhosted/backup.sh >> /var/log/raiox-backup.log 2>&1
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ -f .env ] || die ".env não encontrado: rode ./install.sh primeiro"
retention="${BACKUP_RETENTION_DAYS:-$(env_get BACKUP_RETENTION_DAYS)}"
retention="${retention:-14}"
prefix="${BACKUP_PREFIX:-raiox}"

umask 077
mkdir -p backups
stamp="$(date +%Y%m%d-%H%M%S)"
file="backups/${prefix}-${stamp}.dump"

log "Gerando $file"
# Grava num arquivo temporário e só renomeia se o pg_dump terminar bem (nunca deixa backup pela metade).
if ! compose exec -T postgres pg_dump -U raiox -d raiox --format=custom >"$file.partial"; then
  rm -f "$file.partial"
  die "pg_dump falhou. O serviço postgres está rodando? (docker compose ps)"
fi
[ -s "$file.partial" ] || { rm -f "$file.partial"; die "Backup vazio"; }
mv "$file.partial" "$file"
log "Backup concluído ($(du -h "$file" | cut -f1))"

removed="$(find backups -maxdepth 1 -name '*.dump' -type f -mtime "+$retention" -print -delete | wc -l)"
log "Retenção de ${retention} dias: ${removed} backup(s) antigo(s) removido(s)"
