#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "${root_dir}"

set -a
# shellcheck disable=SC1091
source ./.env
set +a

output_file="${1:-${root_dir}/runtime/migration-144/location-144.dump}"
mkdir -p "$(dirname "${output_file}")"

container_dump="/tmp/location-migration-$$.dump"
cleanup() {
  docker exec wjx-location-postgis rm -f "${container_dump}" \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker exec wjx-location-postgis \
  pg_dump \
    -U "${LOCATION_DB_USER}" \
    -d "${LOCATION_DB_NAME}" \
    --format=custom \
    --compress=3 \
    --file="${container_dump}"

docker cp \
  "wjx-location-postgis:${container_dump}" \
  "${output_file}"
chmod 600 "${output_file}"

printf 'dumpPath=%s\n' "${output_file}"
printf 'dumpBytes=%s\n' "$(stat -c %s "${output_file}")"
printf 'dumpSha256=%s\n' "$(sha256sum "${output_file}" | cut -d ' ' -f 1)"
docker exec wjx-location-postgis \
  psql \
    -U "${LOCATION_DB_USER}" \
    -d "${LOCATION_DB_NAME}" \
    -At \
    -c "select 'snapshotAt=' || current_timestamp;" \
    -c "select 'addressInventory=' || count(*) from dispatch_assist.address_inventory;" \
    -c "select 'poi3=' || count(*) from ai.poi_3;" \
    -c "select 'aoi3=' || count(*) from ai.aoi_3;"

curl --fail --silent --show-error \
  "http://127.0.0.1:${LOCATION_HTTP_PORT:-18080}/actuator/health" \
  | jq -r '"sourceHealth=" + .status'
