-- Explain a representative address-robot query against one logical scope.
-- Usage:
-- psql -v scope_id=<uuid> -v name_pattern='%DENSE_URBAN%' \
--   -f explain_address_scope_filtered_query.sql

\if :{?scope_id}
\else
\echo 'scope_id is required'
\quit
\endif

\if :{?name_pattern}
\else
\echo 'name_pattern is required'
\quit
\endif

EXPLAIN (ANALYZE, BUFFERS)
SELECT inventory_id,
       source_type,
       standard_name,
       full_address,
       aoi_name,
       road_name,
       longitude,
       latitude
FROM dispatch_assist.logical_address_scope_item
WHERE scope_id = CAST(:'scope_id' AS uuid)
  AND source_type IN ('AOI', 'POI')
  AND (standard_name ILIKE :'name_pattern'
       OR full_address ILIKE :'name_pattern')
ORDER BY inventory_id
LIMIT 100;
