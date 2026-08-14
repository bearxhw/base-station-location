#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
set -a
# shellcheck disable=SC1091
source ./.env
set +a

docker compose ps

curl --fail --silent --show-error \
  "http://127.0.0.1:${LOCATION_HTTP_PORT:-18080}/actuator/health"
echo

docker exec wjx-location-rabbitmq rabbitmqctl -q list_queues \
  -p "${LOCATION_RABBITMQ_VHOST}" name messages_ready messages_unacknowledged consumers
