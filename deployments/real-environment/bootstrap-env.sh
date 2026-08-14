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
ensure_setting LOCATION_HTTP_PORT 18082
ensure_setting LOCATION_DB_BIND 0.0.0.0
ensure_setting LOCATION_DB_PORT 15433
ensure_setting LOCATION_DB_NAME dispatch_assist
ensure_setting LOCATION_DB_USER location_real_app
ensure_secret LOCATION_DB_PASSWORD
ensure_setting LOCATION_DB_HOTWORD_USER location_real_hotword_reader
ensure_secret LOCATION_DB_HOTWORD_PASSWORD
ensure_setting LOCATION_DB_ADDRESSBOT_USER location_real_addressbot_reader
ensure_secret LOCATION_DB_ADDRESSBOT_PASSWORD
ensure_setting LOCATION_ACTIVE_INVENTORY_VERSION ODS7ALM_AI_REAL_20260810_V1

ensure_setting LOCATION_RABBITMQ_BIND 0.0.0.0
ensure_setting LOCATION_RABBITMQ_PORT 5673
ensure_setting LOCATION_RABBITMQ_MANAGEMENT_BIND 127.0.0.1
ensure_setting LOCATION_RABBITMQ_MANAGEMENT_PORT 15673
ensure_setting LOCATION_RABBITMQ_VHOST /location-real
ensure_setting LOCATION_RABBITMQ_ADMIN_USER location_real_admin
ensure_secret LOCATION_RABBITMQ_ADMIN_PASSWORD
ensure_setting LOCATION_RABBITMQ_PUBLISHER_USER location_real_publisher
ensure_secret LOCATION_RABBITMQ_PUBLISHER_PASSWORD
ensure_setting LOCATION_RABBITMQ_HOTWORD_USER location_real_hotword
ensure_secret LOCATION_RABBITMQ_HOTWORD_PASSWORD
ensure_setting LOCATION_RABBITMQ_ADDRESSBOT_USER location_real_addressbot
ensure_secret LOCATION_RABBITMQ_ADDRESSBOT_PASSWORD
ensure_setting LOCATION_RABBITMQ_EXCHANGE location.real.address-scope.v1
ensure_setting LOCATION_RABBITMQ_DLX location.real.address-scope.dlx.v1
ensure_setting LOCATION_RABBITMQ_HOTWORD_QUEUE location.real.address-scope.hotword.v1
ensure_setting LOCATION_RABBITMQ_ADDRESSBOT_QUEUE location.real.address-scope.addressbot.v1

chmod 600 .env

