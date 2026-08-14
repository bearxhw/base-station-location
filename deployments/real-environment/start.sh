#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
bash ./bootstrap-env.sh
set -a
# shellcheck disable=SC1091
source ./.env
set +a

for image in wjx-location-postgis:18-3.6 rabbitmq:4.3.4-management-alpine wjx-location-service:1.0.0; do
  docker image inspect "${image}" >/dev/null 2>&1 || {
    echo "required local image is missing: ${image}" >&2
    exit 1
  }
done

docker compose up -d postgis rabbitmq
bash ./bootstrap-rabbitmq.sh

projected_count="$(docker exec -i wjx-location-real-postgis \
  psql -U "${LOCATION_DB_USER}" -d "${LOCATION_DB_NAME}" -Atc \
  "SELECT COUNT(*) FROM dispatch_assist.address_inventory WHERE source_system='ODS7ALM_AI_REAL' AND data_version='${LOCATION_ACTIVE_INVENTORY_VERSION}' AND active=TRUE" 2>/dev/null || echo 0)"
if [[ "${projected_count}" == "0" ]]; then
  bash ./import-real-source.sh
  projected_count="$(docker exec -i wjx-location-real-postgis \
    psql -U "${LOCATION_DB_USER}" -d "${LOCATION_DB_NAME}" -Atc \
    "SELECT COUNT(*) FROM dispatch_assist.address_inventory WHERE source_system='ODS7ALM_AI_REAL' AND data_version='${LOCATION_ACTIVE_INVENTORY_VERSION}' AND active=TRUE")"
fi

bash ./bootstrap-db-readers.sh
docker compose up -d app

for _ in $(seq 1 150); do
  if curl --fail --silent --show-error "http://127.0.0.1:${LOCATION_HTTP_PORT:-18082}/actuator/health" >/dev/null; then
    echo "real location service is ready on port ${LOCATION_HTTP_PORT:-18082}; projected addresses=${projected_count:-unknown}"
    exit 0
  fi
  sleep 2
done

docker compose ps
docker compose logs --tail=120 app postgis rabbitmq
echo "real location service did not become ready in time" >&2
exit 1
