#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
set -a
# shellcheck disable=SC1091
source ./.env
set +a

docker compose ps
printf 'health='
curl --fail --silent --show-error "http://127.0.0.1:${LOCATION_HTTP_PORT:-18082}/actuator/health"
echo
docker exec -i wjx-location-real-postgis psql -U "${LOCATION_DB_USER}" -d "${LOCATION_DB_NAME}" -Atc \
  "SELECT source_type || '=' || COUNT(*) FROM dispatch_assist.address_inventory WHERE source_system='ODS7ALM_AI_REAL' AND data_version='${LOCATION_ACTIVE_INVENTORY_VERSION}' AND active=TRUE GROUP BY source_type ORDER BY source_type"
docker exec wjx-location-real-rabbitmq rabbitmqctl -q list_queues \
  -p "${LOCATION_RABBITMQ_VHOST}" name messages_ready messages_unacknowledged consumers

