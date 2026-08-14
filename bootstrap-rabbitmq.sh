#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
set -a
# shellcheck disable=SC1091
source ./.env
set +a

rabbit_container="wjx-location-rabbitmq"

for _ in $(seq 1 90); do
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' "${rabbit_container}" 2>/dev/null || true)"
  [[ "${health}" == "healthy" ]] && break
  sleep 2
done

if [[ "${health:-}" != "healthy" ]]; then
  docker logs --tail=120 "${rabbit_container}" >&2 || true
  echo "RabbitMQ did not become healthy" >&2
  exit 1
fi

ensure_vhost() {
  local vhost="$1"
  if ! docker exec "${rabbit_container}" rabbitmqctl -q list_vhosts name \
      | grep -Fxq "${vhost}"; then
    docker exec "${rabbit_container}" rabbitmqctl add_vhost "${vhost}"
  fi
}

ensure_user() {
  local username="$1"
  local password="$2"
  if docker exec "${rabbit_container}" rabbitmqctl -q list_users \
      | awk '{print $1}' | grep -Fxq "${username}"; then
    docker exec "${rabbit_container}" rabbitmqctl change_password \
      "${username}" "${password}" >/dev/null
  else
    docker exec "${rabbit_container}" rabbitmqctl add_user \
      "${username}" "${password}" >/dev/null
  fi
}

ensure_vhost "${LOCATION_RABBITMQ_VHOST}"
ensure_user "${LOCATION_RABBITMQ_ADMIN_USER}" \
  "${LOCATION_RABBITMQ_ADMIN_PASSWORD}"
ensure_user "${LOCATION_RABBITMQ_PUBLISHER_USER}" \
  "${LOCATION_RABBITMQ_PUBLISHER_PASSWORD}"
ensure_user "${LOCATION_RABBITMQ_HOTWORD_USER}" \
  "${LOCATION_RABBITMQ_HOTWORD_PASSWORD}"
ensure_user "${LOCATION_RABBITMQ_ADDRESSBOT_USER}" \
  "${LOCATION_RABBITMQ_ADDRESSBOT_PASSWORD}"

docker exec "${rabbit_container}" rabbitmqctl set_user_tags \
  "${LOCATION_RABBITMQ_ADMIN_USER}" administrator >/dev/null
docker exec "${rabbit_container}" rabbitmqctl set_permissions \
  -p "${LOCATION_RABBITMQ_VHOST}" \
  "${LOCATION_RABBITMQ_ADMIN_USER}" '.*' '.*' '.*' >/dev/null
docker exec "${rabbit_container}" rabbitmqctl set_permissions \
  -p "${LOCATION_RABBITMQ_VHOST}" \
  "${LOCATION_RABBITMQ_PUBLISHER_USER}" \
  '^location\.address-scope\..*$' \
  '^location\.address-scope\..*$' \
  '^location\.address-scope\..*$' >/dev/null
docker exec "${rabbit_container}" rabbitmqctl set_permissions \
  -p "${LOCATION_RABBITMQ_VHOST}" \
  "${LOCATION_RABBITMQ_HOTWORD_USER}" \
  '^$' '^$' '^location\.address-scope\.hotword\.v1(\.dlq)?$' >/dev/null
docker exec "${rabbit_container}" rabbitmqctl set_permissions \
  -p "${LOCATION_RABBITMQ_VHOST}" \
  "${LOCATION_RABBITMQ_ADDRESSBOT_USER}" \
  '^$' '^$' '^location\.address-scope\.addressbot\.v1(\.dlq)?$' >/dev/null

urlencode() {
  local value="$1"
  local encoded=""
  local character
  local hex
  local index
  LC_ALL=C
  for ((index = 0; index < ${#value}; index++)); do
    character="${value:index:1}"
    case "${character}" in
      [a-zA-Z0-9.~_-]) encoded+="${character}" ;;
      *)
        printf -v hex '%%%02X' "'${character}"
        encoded+="${hex}"
        ;;
    esac
  done
  printf '%s' "${encoded}"
}

management_url="http://127.0.0.1:${LOCATION_RABBITMQ_MANAGEMENT_PORT:-15672}/api"
vhost_path="$(urlencode "${LOCATION_RABBITMQ_VHOST}")"
netrc_file="$(mktemp)"
trap 'rm -f "${netrc_file}"' EXIT
chmod 600 "${netrc_file}"
printf 'machine 127.0.0.1 login %s password %s\n' \
  "${LOCATION_RABBITMQ_ADMIN_USER}" \
  "${LOCATION_RABBITMQ_ADMIN_PASSWORD}" > "${netrc_file}"

api_request() {
  local method="$1"
  local path="$2"
  local body="$3"
  curl --fail --silent --show-error \
    --netrc-file "${netrc_file}" \
    -X "${method}" \
    -H 'Content-Type: application/json' \
    --data "${body}" \
    "${management_url}/${path}" >/dev/null
}

api_request PUT \
  "exchanges/${vhost_path}/location.address-scope.v1" \
  '{"type":"direct","durable":true,"auto_delete":false,"internal":false,"arguments":{}}'
api_request PUT \
  "exchanges/${vhost_path}/location.address-scope.dlx.v1" \
  '{"type":"direct","durable":true,"auto_delete":false,"internal":false,"arguments":{}}'

for queue in \
  location.address-scope.hotword.v1 \
  location.address-scope.addressbot.v1; do
  api_request PUT "queues/${vhost_path}/${queue}" \
    "{\"durable\":true,\"auto_delete\":false,\"arguments\":{\"x-dead-letter-exchange\":\"location.address-scope.dlx.v1\",\"x-dead-letter-routing-key\":\"${queue}.dead\"}}"
  api_request PUT "queues/${vhost_path}/${queue}.dlq" \
    '{"durable":true,"auto_delete":false,"arguments":{}}'
  api_request POST \
    "bindings/${vhost_path}/e/location.address-scope.v1/q/${queue}" \
    '{"routing_key":"address.scope.ready.v1","arguments":{}}'
  api_request POST \
    "bindings/${vhost_path}/e/location.address-scope.dlx.v1/q/${queue}.dlq" \
    "{\"routing_key\":\"${queue}.dead\",\"arguments\":{}}"
done

echo "RabbitMQ users, vhost, exchanges and queues are ready"
