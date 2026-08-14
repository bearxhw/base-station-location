-- Explain the exact short-circuit query used to derive READY/EMPTY.
-- Usage:
-- psql -v resolution_id=<uuid> -v resolution_version=1 \
--   -v inventory_version=REALISTIC_AI_SOURCE_V1 \
--   -f explain_address_scope_exists.sql

\if :{?resolution_id}
\else
\echo 'resolution_id is required'
\quit
\endif

\if :{?resolution_version}
\else
\echo 'resolution_version is required'
\quit
\endif

\if :{?inventory_version}
\else
\echo 'inventory_version is required'
\quit
\endif

EXPLAIN (ANALYZE, BUFFERS)
WITH resolution_scope AS MATERIALIZED (
    SELECT resolution.search_area
    FROM dispatch_assist.location_resolution resolution
    WHERE resolution.id = CAST(:'resolution_id' AS uuid)
      AND resolution.version = :resolution_version
)
SELECT EXISTS (
    SELECT 1
    FROM resolution_scope resolution
    JOIN dispatch_assist.address_inventory inventory
      ON inventory.active = TRUE
     AND inventory.data_version = :'inventory_version'
     AND inventory.geom && resolution.search_area::geometry
     AND ST_Intersects(
           inventory.geom,
           resolution.search_area::geometry)
);
