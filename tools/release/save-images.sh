#!/usr/bin/env bash
# Gera o pacote de imagens para instalar o Raio-X sem internet (decisão D23).
# Constrói as imagens da API (e do simulador SAP) e junta com a do PostgreSQL num único tar:
#
#   tools/release/save-images.sh [saida.tar]       # padrão: raiox-images.tar na raiz do repositório
#
# Variáveis: RAIOX_API_IMAGE, RAIOX_SAP_MOCK_IMAGE, RAIOX_POSTGRES_IMAGE (tags), NODE_IMAGE (base do build),
#            WITH_DEMO=false para não incluir o simulador SAP.
#
# Na VM sem internet:  docker load -i raiox-images.tar  (ou ./install.sh --images raiox-images.tar)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:-$root/raiox-images.tar}"
compose_file="$root/infra/selfhosted/docker-compose.yml"
WITH_DEMO="${WITH_DEMO:-true}"

command -v docker >/dev/null 2>&1 || { echo "erro: Docker não encontrado" >&2; exit 1; }

profile=()
[ "$WITH_DEMO" = true ] && profile=(--profile demo)

# O compose exige os segredos só para interpolar; aqui valores descartáveis bastam (nada é gravado nas imagens).
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-build-only}"
export SESSION_SECRET="${SESSION_SECRET:-build-only}"
# O serviço api lê o .env (env_file): sem ele o compose nem monta a configuração. Usa um temporário.
if [ ! -f "$root/infra/selfhosted/.env" ]; then
  cp "$root/infra/selfhosted/.env.example" "$root/infra/selfhosted/.env"
  trap 'rm -f "$root/infra/selfhosted/.env"' EXIT
fi

echo "==> Construindo as imagens"
docker compose -f "$compose_file" ${profile[@]+"${profile[@]}"} build

echo "==> Baixando a imagem do PostgreSQL"
docker compose -f "$compose_file" pull postgres

mapfile -t images < <(docker compose -f "$compose_file" ${profile[@]+"${profile[@]}"} config --images | sort -u)
echo "==> Salvando em $out:"
printf '    %s\n' "${images[@]}"
docker save -o "$out" "${images[@]}"
(cd "$(dirname "$out")" && sha256sum "$(basename "$out")" >"$(basename "$out").sha256")
echo "==> Pronto: $out ($(du -h "$out" | cut -f1)). Confira com: sha256sum -c $(basename "$out").sha256"
