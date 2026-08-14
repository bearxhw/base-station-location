#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

bash ./bootstrap-env.sh
set -a
# shellcheck disable=SC1091
source ./.env
set +a

ensure_image() {
  local image="$1"
  local archive="$2"
  if docker image inspect "${image}" >/dev/null 2>&1; then
    return
  fi
  if [[ ! -f "${archive}" ]]; then
    echo "${image} is missing and ${archive} was not found" >&2
    exit 1
  fi
  docker load --input "${archive}"
}

ensure_image "wjx-location-postgis:18-3.6" \
  "wjx-location-postgis-18-3.6-arm64.tar"
ensure_image "rabbitmq:4.3.4-management-alpine" \
  "wjx-location-rabbitmq-4.3.4-arm64.tar"

docker compose up -d postgis rabbitmq
bash ./bootstrap-rabbitmq.sh
bash ./bootstrap-db-readers.sh
docker compose up -d --build app

port="${LOCATION_HTTP_PORT:-18080}"

for _ in $(seq 1 150); do
  if curl --fail --silent --show-error "http://127.0.0.1:${port}/actuator/health" >/dev/null; then
    echo "location service is ready on port ${port}"
    exit 0
  fi
  sleep 2
done

docker compose ps
docker compose logs --tail=120 app postgis rabbitmq
echo "location service did not become ready in time" >&2
exit 1
