#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

umask 077
touch .env

ensure_setting() {
  local key="$1"
  local value="$2"
  if ! grep -q "^${key}=" .env; then
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}

ensure_secret() {
  local key="$1"
  if ! grep -q "^${key}=" .env; then
    printf '%s=%s\n' "$key" "$(openssl rand -hex 24)" >> .env
  fi
}

ensure_setting LOCATION_HTTP_BIND 0.0.0.0
ensure_setting LOCATION_HTTP_PORT 18080
ensure_setting LOCATION_DB_BIND 0.0.0.0
ensure_setting LOCATION_DB_PORT 15432
ensure_setting LOCATION_DB_NAME dispatch_assist
ensure_setting LOCATION_DB_USER location_app
ensure_secret LOCATION_DB_PASSWORD
ensure_setting LOCATION_DB_HOTWORD_USER location_hotword_reader
ensure_secret LOCATION_DB_HOTWORD_PASSWORD
ensure_setting LOCATION_DB_ADDRESSBOT_USER location_addressbot_reader
ensure_secret LOCATION_DB_ADDRESSBOT_PASSWORD
ensure_setting LOCATION_ACTIVE_INVENTORY_VERSION REALISTIC_AI_SOURCE_V1

ensure_setting LOCATION_RABBITMQ_BIND 0.0.0.0
ensure_setting LOCATION_RABBITMQ_PORT 5672
ensure_setting LOCATION_RABBITMQ_MANAGEMENT_BIND 127.0.0.1
ensure_setting LOCATION_RABBITMQ_MANAGEMENT_PORT 15672
ensure_setting LOCATION_RABBITMQ_VHOST /location
ensure_setting LOCATION_RABBITMQ_ADMIN_USER location_admin
ensure_secret LOCATION_RABBITMQ_ADMIN_PASSWORD
ensure_setting LOCATION_RABBITMQ_PUBLISHER_USER location_publisher
ensure_secret LOCATION_RABBITMQ_PUBLISHER_PASSWORD
ensure_setting LOCATION_RABBITMQ_HOTWORD_USER location_hotword
ensure_secret LOCATION_RABBITMQ_HOTWORD_PASSWORD
ensure_setting LOCATION_RABBITMQ_ADDRESSBOT_USER location_addressbot
ensure_secret LOCATION_RABBITMQ_ADDRESSBOT_PASSWORD

chmod 600 .env
