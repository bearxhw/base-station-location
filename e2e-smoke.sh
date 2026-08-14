#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
set -a
# shellcheck disable=SC1091
source ./.env
set +a

hotword_queue="location.address-scope.hotword.v1"
addressbot_queue="location.address-scope.addressbot.v1"
response_file="$(mktemp)"
netrc_file="$(mktemp)"
trap 'rm -f "${response_file}" "${netrc_file}"' EXIT
chmod 600 "${netrc_file}"
printf 'machine 127.0.0.1 login %s password %s\n' \
  "${LOCATION_RABBITMQ_ADMIN_USER}" \
  "${LOCATION_RABBITMQ_ADMIN_PASSWORD}" > "${netrc_file}"
vhost_path="$(jq -nr --arg value "${LOCATION_RABBITMQ_VHOST}" '$value|@uri')"
management_url="http://127.0.0.1:${LOCATION_RABBITMQ_MANAGEMENT_PORT:-15672}/api"

queue_delivery_count() {
  local queue="$1"
  curl --fail --silent --show-error \
    --netrc-file "${netrc_file}" \
    "${management_url}/queues/${vhost_path}/${queue}" \
  | jq -er '.message_stats.deliver // 0'
}

queue_consumer_count() {
  local queue="$1"
  curl --fail --silent --show-error \
    --netrc-file "${netrc_file}" \
    "${management_url}/queues/${vhost_path}/${queue}" \
  | jq -er '.consumers // 0'
}

message_matches_contract() {
  local queue="$1"
  curl --fail --silent --show-error \
    --netrc-file "${netrc_file}" \
    -X POST \
    -H 'Content-Type: application/json' \
    --data '{"count":100,"ackmode":"ack_requeue_true","encoding":"auto","truncate":50000}' \
    "${management_url}/queues/${vhost_path}/${queue}/get" \
  | jq -e \
      --arg scope "${scope_id}" \
      --argjson center_longitude "${search_longitude}" \
      --argjson center_latitude "${search_latitude}" \
      --argjson radius_meters "${search_radius_meters}" \
      --arg positioning_method "${positioning_method}" \
      'any(.[];
        (.payload | fromjson) as $event
        | $event.specversion == "1.0"
          and $event.type == "address.scope.ready.v1"
          and $event.datacontenttype == "application/json"
          and $event.subject == $scope
          and $event.id == $event.data.eventId
          and $event.data.addressScopeRef.scopeId == $scope
          and $event.data.locationScope.centerLongitude == $center_longitude
          and $event.data.locationScope.centerLatitude == $center_latitude
          and $event.data.locationScope.radiusMeters == $radius_meters
          and $event.data.locationScope.coordinateSystem == "WGS84"
          and $event.data.locationScope.shapeType == "CIRCLE"
          and $event.data.locationScope.positioningMethod == $positioning_method
          and ($event.data | has("items") | not)
      )' \
      >/dev/null
}

request_id="location-mq-e2e-$(date +%s%N)"
session_id="call-mq-e2e-$(date +%s%N)"
hotword_deliver_before="$(queue_delivery_count "${hotword_queue}")"

start_ms="$(date +%s%3N)"
api_seconds="$(curl --fail --silent --show-error \
  -o "${response_file}" \
  -w '%{time_total}' \
  -X POST "http://127.0.0.1:${LOCATION_HTTP_PORT:-18080}/api/v1/location/resolutions" \
  -H 'Content-Type: application/json' \
  --data "{
    \"requestId\":\"${request_id}\",
    \"sessionId\":\"${session_id}\",
    \"alarmId\":\"alarm-mq-e2e\",
    \"sourceType\":\"CTI_COORDINATE\",
    \"baseStationCoordinate\":{
      \"longitude\":116.33,
      \"latitude\":39.92,
      \"coordinateSystem\":\"WGS84\",
      \"accuracyMeters\":30
    },
    \"radiusMeters\":2000
  }")"

scope_id="$(jq -er '.data.addressScopeRef.scopeId' "${response_file}")"
resolution_id="$(jq -er '.data.resolutionId' "${response_file}")"
search_longitude="$(jq -er '.data.searchLongitude' "${response_file}")"
search_latitude="$(jq -er '.data.searchLatitude' "${response_file}")"
search_radius_meters="$(jq -er '.data.searchRadiusMeters' "${response_file}")"
positioning_method="$(jq -er '.data.positioningMethod' "${response_file}")"
[[ "${scope_id}" =~ ^[0-9a-fA-F-]{36}$ ]] || {
  echo "location response did not contain a valid scopeId" >&2
  cat "${response_file}" >&2
  exit 1
}

for _ in $(seq 1 100); do
  outbox_details="$(docker exec -i wjx-location-postgis \
    psql -U "${LOCATION_DB_USER}" -d "${LOCATION_DB_NAME}" \
    -v ON_ERROR_STOP=1 -At -F '|' -c \
    "select status, retry_count, round(extract(epoch from (published_at - created_at)) * 1000, 3), payload #>> '{locationScope,centerLongitude}', payload #>> '{locationScope,centerLatitude}', payload #>> '{locationScope,radiusMeters}', payload #>> '{locationScope,coordinateSystem}', payload #>> '{locationScope,shapeType}', payload #>> '{locationScope,positioningMethod}' from dispatch_assist.outbox_event where aggregate_id = '${scope_id}'::uuid and event_type = 'address.scope.ready.v1';")"
  IFS='|' read -r outbox_status outbox_retry_count broker_confirm_ms \
    outbox_longitude outbox_latitude outbox_radius \
    outbox_coordinate_system outbox_shape_type outbox_positioning_method \
    <<< "${outbox_details}"
  if [[ "${outbox_status:-}" == "PUBLISHED" ]]; then
    break
  fi
  sleep 0.05
done

if [[ "${outbox_status:-}" != "PUBLISHED" ]]; then
  echo "scope event was not confirmed by RabbitMQ" >&2
  exit 1
fi

jq -en \
  --argjson outbox_longitude "${outbox_longitude}" \
  --argjson outbox_latitude "${outbox_latitude}" \
  --argjson outbox_radius "${outbox_radius}" \
  --argjson search_longitude "${search_longitude}" \
  --argjson search_latitude "${search_latitude}" \
  --argjson search_radius "${search_radius_meters}" \
  '$outbox_longitude == $search_longitude
    and $outbox_latitude == $search_latitude
    and $outbox_radius == $search_radius' >/dev/null \
  && [[ "${outbox_coordinate_system}" == "WGS84" \
        && "${outbox_shape_type}" == "CIRCLE" \
        && "${outbox_positioning_method}" == "${positioning_method}" ]] || {
  echo "Outbox locationScope did not match the HTTP search scope" >&2
  printf 'httpScope=%s,%s,%s,%s\n' \
    "${search_longitude}" \
    "${search_latitude}" \
    "${search_radius_meters}" \
    "${positioning_method}" >&2
  printf 'outboxScope=%s,%s,%s,%s,%s,%s\n' \
    "${outbox_longitude}" \
    "${outbox_latitude}" \
    "${outbox_radius}" \
    "${outbox_coordinate_system}" \
    "${outbox_shape_type}" \
    "${outbox_positioning_method}" >&2
  exit 1
}

for queue in "${hotword_queue}" "${addressbot_queue}"; do
  found=false
  queue_consumers="$(queue_consumer_count "${queue}")"
  if [[ "${queue}" == "${hotword_queue}" \
        && "${queue_consumers}" -gt 0 ]]; then
    verification_mode="LIVE_CONSUMER_DELIVERY"
    for _ in $(seq 1 50); do
      hotword_deliver_after="$(queue_delivery_count "${hotword_queue}")"
      if (( hotword_deliver_after > hotword_deliver_before )); then
        found=true
        break
      fi
      sleep 0.05
    done
  else
    verification_mode="BODY_INSPECTED"
    for _ in $(seq 1 50); do
      if message_matches_contract "${queue}"; then
        found=true
        break
      fi
      sleep 0.05
    done
  fi
  [[ "${found}" == "true" ]] || {
    echo "scope event was not readable from ${queue}" >&2
    exit 1
  }
  if [[ "${queue}" == "${hotword_queue}" ]]; then
    hotword_verification_mode="${verification_mode}"
  else
    addressbot_verification_mode="${verification_mode}"
  fi
done
event_ready_ms=$(( $(date +%s%3N) - start_ms ))

query_as_reader() {
  local username="$1"
  local password="$2"
  local sql="$3"
  PGPASSWORD="${password}" PGCONNECT_TIMEOUT=5 \
    psql -h 127.0.0.1 -p "${LOCATION_DB_PORT:-15432}" \
      -U "${username}" -d "${LOCATION_DB_NAME}" \
      -v ON_ERROR_STOP=1 -Atc "${sql}"
}

scope_sql="select count(*) from dispatch_assist.logical_address_scope_item where scope_id = '${scope_id}'::uuid;"
hotword_count="$(query_as_reader \
  "${LOCATION_DB_HOTWORD_USER}" \
  "${LOCATION_DB_HOTWORD_PASSWORD}" \
  "${scope_sql}")"
addressbot_count="$(query_as_reader \
  "${LOCATION_DB_ADDRESSBOT_USER}" \
  "${LOCATION_DB_ADDRESSBOT_PASSWORD}" \
  "${scope_sql}")"

[[ "${hotword_count}" == "${addressbot_count}" ]] || {
  echo "downstream readers returned different logical scope counts" >&2
  exit 1
}

type_counts="$(query_as_reader \
  "${LOCATION_DB_ADDRESSBOT_USER}" \
  "${LOCATION_DB_ADDRESSBOT_PASSWORD}" \
  "select source_type || '=' || count(*) from dispatch_assist.logical_address_scope_item where scope_id = '${scope_id}'::uuid group by source_type order by source_type;")"
verification_ms=$(( $(date +%s%3N) - start_ms ))
api_ms="$(awk -v seconds="${api_seconds}" 'BEGIN {printf "%.3f", seconds * 1000}')"

printf 'requestId=%s\n' "${request_id}"
printf 'resolutionId=%s\n' "${resolution_id}"
printf 'scopeId=%s\n' "${scope_id}"
printf 'apiTimeMs=%s\n' "${api_ms}"
printf 'eventReadyMs=%s\n' "${event_ready_ms}"
printf 'brokerConfirmMs=%s\n' "${broker_confirm_ms}"
printf 'fullVerificationMs=%s\n' "${verification_ms}"
printf 'hotwordMessageVerified=true\n'
printf 'addressbotMessageVerified=true\n'
printf 'hotwordVerificationMode=%s\n' "${hotword_verification_mode}"
printf 'addressbotVerificationMode=%s\n' "${addressbot_verification_mode}"
printf 'logicalScopeItems=%s\n' "${hotword_count}"
printf 'sourceTypeCounts=%s\n' "$(printf '%s' "${type_counts}" | paste -sd, -)"
printf 'outboxStatus=%s\n' "${outbox_status}"
printf 'outboxRetryCount=%s\n' "${outbox_retry_count}"
printf 'messageBodyVerified=true\n'
printf 'locationScopeVerified=true\n'
