#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source ./.env
  set +a
fi

docker compose ps
curl --fail --silent --show-error http://127.0.0.1:${LOCATION_HTTP_PORT:-18080}/actuator/health
printf '\n'

docker inspect wjx-location-postgis wjx-location-rabbitmq wjx-location-service \
  --format '{{.Name}} status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}} restarts={{.RestartCount}}'

docker exec -i wjx-location-postgis \
  psql -U "${LOCATION_DB_USER:-location_app}" -d "${LOCATION_DB_NAME:-dispatch_assist}" \
  -v ON_ERROR_STOP=1 -At <<'SQL'
select postgis_version();
select 'cell_sector', count(*) from dispatch_assist.cell_sector;
select 'neighbor_relation', count(*) from dispatch_assist.cell_neighbor_relation;
select data_version || ':' || source_type, count(*)
from dispatch_assist.address_inventory
group by data_version, source_type
order by data_version, source_type;
select 'outbox:' || status, count(*)
from dispatch_assist.outbox_event
where event_type = 'address.scope.ready.v1'
group by status
order by status;
SQL

docker exec -e PGPASSWORD="${LOCATION_DB_HOTWORD_PASSWORD}" \
  wjx-location-postgis psql -h 127.0.0.1 \
  -U "${LOCATION_DB_HOTWORD_USER}" -d "${LOCATION_DB_NAME}" \
  -v ON_ERROR_STOP=1 -Atc \
  "select current_user, current_setting('default_transaction_read_only'), count(*) from dispatch_assist.logical_address_scope_item;"

docker exec -e PGPASSWORD="${LOCATION_DB_ADDRESSBOT_PASSWORD}" \
  wjx-location-postgis psql -h 127.0.0.1 \
  -U "${LOCATION_DB_ADDRESSBOT_USER}" -d "${LOCATION_DB_NAME}" \
  -v ON_ERROR_STOP=1 -Atc \
  "select current_user, current_setting('default_transaction_read_only'), count(*) from ai.poi_3;"

docker exec -i wjx-location-postgis \
  psql -U "${LOCATION_DB_USER}" -d "${LOCATION_DB_NAME}" \
  -v ON_ERROR_STOP=1 -At \
  -v hotword_user="${LOCATION_DB_HOTWORD_USER}" \
  -v addressbot_user="${LOCATION_DB_ADDRESSBOT_USER}" <<'SQL'
WITH business_objects AS (
    SELECT table_schema, table_name
    FROM information_schema.tables
    WHERE table_schema IN ('dispatch_assist', 'ai')
), readers AS (
    SELECT :'hotword_user'::text AS role_name
    UNION ALL
    SELECT :'addressbot_user'::text
)
SELECT role_name,
       COUNT(*) AS business_objects,
       COUNT(*) FILTER (
           WHERE has_table_privilege(
               role_name,
               format('%I.%I', table_schema, table_name),
               'SELECT'
           )
       ) AS selectable_objects,
       COUNT(*) FILTER (
           WHERE has_table_privilege(role_name,
                     format('%I.%I', table_schema, table_name), 'INSERT')
              OR has_table_privilege(role_name,
                     format('%I.%I', table_schema, table_name), 'UPDATE')
              OR has_table_privilege(role_name,
                     format('%I.%I', table_schema, table_name), 'DELETE')
              OR has_table_privilege(role_name,
                     format('%I.%I', table_schema, table_name), 'TRUNCATE')
       ) AS writable_objects
FROM readers
CROSS JOIN business_objects
GROUP BY role_name
ORDER BY role_name;
SQL

docker exec wjx-location-rabbitmq rabbitmqctl -q list_queues \
  -p "${LOCATION_RABBITMQ_VHOST}" name messages_ready messages_unacknowledged consumers

docker exec wjx-location-rabbitmq rabbitmqctl authenticate_user \
  "${LOCATION_RABBITMQ_HOTWORD_USER}" \
  "${LOCATION_RABBITMQ_HOTWORD_PASSWORD}" >/dev/null
docker exec wjx-location-rabbitmq rabbitmqctl authenticate_user \
  "${LOCATION_RABBITMQ_ADDRESSBOT_USER}" \
  "${LOCATION_RABBITMQ_ADDRESSBOT_PASSWORD}" >/dev/null
docker exec wjx-location-rabbitmq rabbitmqctl -q list_permissions \
  -p "${LOCATION_RABBITMQ_VHOST}"

if docker compose logs --since=60s app postgis rabbitmq 2>&1 \
  | grep -E 'ERROR|Exception|FATAL|PANIC'; then
  echo 'recent component logs contain errors' >&2
  exit 1
fi

echo 'location component verification passed'
