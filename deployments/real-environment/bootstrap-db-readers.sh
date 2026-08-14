#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
set -a
# shellcheck disable=SC1091
source ./.env
set +a

container="wjx-location-real-postgis"

validate_role() {
  [[ "$1" =~ ^[a-z_][a-z0-9_]*$ ]] || {
    echo "invalid database role: $1" >&2
    exit 1
  }
}

validate_secret() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "database password contains unsupported characters" >&2
    exit 1
  }
}

provision_reader() {
  local reader_user="$1"
  local reader_password="$2"
  validate_role "${reader_user}"
  validate_secret "${reader_password}"

  docker exec -i "${container}" \
    psql -U "${LOCATION_DB_USER}" -d "${LOCATION_DB_NAME}" \
    -v ON_ERROR_STOP=1 \
    -v reader_user="${reader_user}" \
    -v reader_password="${reader_password}" \
    -v owner_role="${LOCATION_DB_USER}" >/dev/null <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L',
              :'reader_user', :'reader_password')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = :'reader_user'
)
\gexec
SELECT format('ALTER ROLE %I LOGIN PASSWORD %L',
              :'reader_user', :'reader_password')
\gexec
SELECT format('ALTER ROLE %I SET default_transaction_read_only = on',
              :'reader_user')
\gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I',
              current_database(), :'reader_user')
\gexec
SELECT format('GRANT USAGE ON SCHEMA dispatch_assist, ai TO %I',
              :'reader_user')
\gexec
SELECT format('GRANT SELECT ON ALL TABLES IN SCHEMA dispatch_assist, ai TO %I',
              :'reader_user')
\gexec
SELECT format('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA dispatch_assist, ai TO %I',
              :'reader_user')
\gexec
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA dispatch_assist GRANT SELECT ON TABLES TO %I',
              :'owner_role', :'reader_user')
\gexec
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA ai GRANT SELECT ON TABLES TO %I',
              :'owner_role', :'reader_user')
\gexec
SQL
}

provision_reader "${LOCATION_DB_HOTWORD_USER}" \
  "${LOCATION_DB_HOTWORD_PASSWORD}"
provision_reader "${LOCATION_DB_ADDRESSBOT_USER}" \
  "${LOCATION_DB_ADDRESSBOT_PASSWORD}"

echo "real-environment downstream database readers are ready"

