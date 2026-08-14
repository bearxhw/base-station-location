#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "${root_dir}"

set -a
# shellcheck disable=SC1091
source ./.env
set +a

dump_file="${1:-${root_dir}/runtime/migration-144/location-144.dump}"
volume_name="wjx-location-postgis-data"
restore_container="wjx-location-postgis-restore"

if [[ ! -s "${dump_file}" ]]; then
  echo "database dump is missing or empty: ${dump_file}" >&2
  exit 1
fi
if docker volume inspect "${volume_name}" >/dev/null 2>&1; then
  echo "refusing to overwrite existing volume: ${volume_name}" >&2
  exit 1
fi
if docker container inspect "${restore_container}" >/dev/null 2>&1; then
  echo "restore container already exists: ${restore_container}" >&2
  exit 1
fi

cleanup() {
  docker rm -f "${restore_container}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create "${volume_name}" >/dev/null
docker run -d \
  --name "${restore_container}" \
  -e "POSTGRES_DB=${LOCATION_DB_NAME}" \
  -e "POSTGRES_USER=${LOCATION_DB_USER}" \
  -e "POSTGRES_PASSWORD=${LOCATION_DB_PASSWORD}" \
  -v "${volume_name}:/var/lib/postgresql" \
  wjx-location-postgis:18-3.6 >/dev/null

for _ in $(seq 1 120); do
  if docker exec "${restore_container}" \
       pg_isready \
         -U "${LOCATION_DB_USER}" \
         -d "${LOCATION_DB_NAME}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

docker exec "${restore_container}" \
  pg_isready \
    -U "${LOCATION_DB_USER}" \
    -d "${LOCATION_DB_NAME}" >/dev/null

docker cp "${dump_file}" "${restore_container}:/tmp/location.dump"
docker exec "${restore_container}" \
  pg_restore \
    -U "${LOCATION_DB_USER}" \
    -d "${LOCATION_DB_NAME}" \
    --no-owner \
    --no-acl \
    --exit-on-error \
    /tmp/location.dump

docker exec "${restore_container}" \
  vacuumdb \
    -U "${LOCATION_DB_USER}" \
    -d "${LOCATION_DB_NAME}" \
    --analyze-in-stages

docker exec "${restore_container}" rm -f /tmp/location.dump
docker stop "${restore_container}" >/dev/null
docker rm "${restore_container}" >/dev/null
trap - EXIT

printf 'restoredDumpSha256=%s\n' \
  "$(sha256sum "${dump_file}" | cut -d ' ' -f 1)"
printf 'restoredVolume=%s\n' "${volume_name}"
