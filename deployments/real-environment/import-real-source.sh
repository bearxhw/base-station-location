#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
set -a
# shellcheck disable=SC1091
source ./.env
set +a

dump_file="${1:-runtime/real-ai-source.dump}"
container="wjx-location-real-postgis"

if [[ ! -f "${dump_file}" ]]; then
  echo "real source dump not found: ${dump_file}" >&2
  exit 1
fi

for _ in $(seq 1 90); do
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' "${container}" 2>/dev/null || true)"
  [[ "${health}" == "healthy" ]] && break
  sleep 2
done
[[ "${health:-}" == "healthy" ]] || { echo "real PostGIS is not healthy" >&2; exit 1; }

docker exec -i "${container}" psql -U "${LOCATION_DB_USER}" -d "${LOCATION_DB_NAME}" \
  -v ON_ERROR_STOP=1 -c 'DROP SCHEMA IF EXISTS ai CASCADE; CREATE SCHEMA ai;' >/dev/null

docker exec -i "${container}" pg_restore \
  -U "${LOCATION_DB_USER}" -d "${LOCATION_DB_NAME}" \
  --no-owner --no-privileges --exit-on-error < "${dump_file}"

docker exec -i "${container}" psql -U "${LOCATION_DB_USER}" -d "${LOCATION_DB_NAME}" \
  -v ON_ERROR_STOP=1 \
  -v inventory_version="${LOCATION_ACTIVE_INVENTORY_VERSION}" \
  < sync-real-address-read-model.sql

docker exec -i "${container}" psql -U "${LOCATION_DB_USER}" -d "${LOCATION_DB_NAME}" \
  -v ON_ERROR_STOP=1 -At <<'SQL'
SELECT 'raw_total=' || SUM(row_count)
FROM (
  SELECT COUNT(*) row_count FROM ai.aoi_2
  UNION ALL SELECT COUNT(*) FROM ai.aoi_3
  UNION ALL SELECT COUNT(*) FROM ai.aoi_3_entrance_exit
  UNION ALL SELECT COUNT(*) FROM ai.aoi_3_parent_ref
  UNION ALL SELECT COUNT(*) FROM ai.loi_road
  UNION ALL SELECT COUNT(*) FROM ai.poi_1
  UNION ALL SELECT COUNT(*) FROM ai.poi_1_building_special
  UNION ALL SELECT COUNT(*) FROM ai.poi_1_entrance_exit
  UNION ALL SELECT COUNT(*) FROM ai.poi_2
  UNION ALL SELECT COUNT(*) FROM ai.poi_3
) source_counts;
SELECT 'projected_total=' || COUNT(*)
FROM dispatch_assist.address_inventory
WHERE source_system = 'ODS7ALM_AI_REAL'
  AND data_version = 'ODS7ALM_AI_REAL_20260810_V1'
  AND active = TRUE;
SQL

echo "real source tables and spatial read model are ready"
