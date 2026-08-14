#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
set -a
# shellcheck disable=SC1091
source ./.env
set +a

netrc_file="$(mktemp)"
trap 'rm -f "${netrc_file}"' EXIT
chmod 600 "${netrc_file}"
printf 'machine 127.0.0.1 login %s password %s\n' \
  "${LOCATION_RABBITMQ_ADMIN_USER}" \
  "${LOCATION_RABBITMQ_ADMIN_PASSWORD}" > "${netrc_file}"
vhost_path="$(jq -nr --arg value "${LOCATION_RABBITMQ_VHOST}" '$value|@uri')"

printf 'jarSha256='
sha256sum location-service.jar | awk '{print $1}'

printf 'health='
curl --fail --silent --show-error \
  "http://127.0.0.1:${LOCATION_HTTP_PORT:-18080}/actuator/health" \
  | jq -c .

printf 'containers='
docker compose ps --format json \
  | jq -sc '[.[] | {Name, State, Health, Status}]'

printf 'queues='
curl --fail --silent --show-error \
  --netrc-file "${netrc_file}" \
  "http://127.0.0.1:${LOCATION_RABBITMQ_MANAGEMENT_PORT:-15672}/api/queues/${vhost_path}" \
  | jq -c '[.[]
      | select(.name | startswith("location.address-scope."))
      | {name, messages_ready, messages_unacknowledged, consumers}]'

printf 'latestOutbox='
docker exec -i wjx-location-postgis \
  psql -U "${LOCATION_DB_USER}" -d "${LOCATION_DB_NAME}" -Atc \
  "select json_build_object(
      'aggregateId', aggregate_id,
      'status', status,
      'retryCount', retry_count,
      'hasLocationScope', payload ? 'locationScope'
   )
   from dispatch_assist.outbox_event
   where event_type = 'address.scope.ready.v1'
   order by created_at desc
   limit 1;"
