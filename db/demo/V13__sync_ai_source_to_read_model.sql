\set ON_ERROR_STOP on
\timing on

\if :{?sync_address_terms}
\else
  \set sync_address_terms true
\endif

-- Build the optional PostGIS search projection from the source-compatible
-- ai.* tables. The source hierarchy remains authoritative; this projection
-- only provides one indexed geometry contract for low-latency range queries.

BEGIN;
SET LOCAL synchronous_commit = OFF;

DELETE FROM dispatch_assist.address_inventory_term term
USING dispatch_assist.address_inventory inventory
WHERE term.inventory_id = inventory.id
  AND inventory.source_system = 'AI_SOURCE_SIM';

DELETE FROM dispatch_assist.address_inventory
WHERE source_system = 'AI_SOURCE_SIM';

DELETE FROM dispatch_assist.building_inventory
WHERE source_system = 'AI_SOURCE_SIM';

WITH source_geometry AS (
    SELECT building.*,
           CASE
             WHEN ST_SRID(building.geom) = 0
             THEN ST_SetSRID(ST_Force2D(building.geom), 4326)
             WHEN ST_SRID(building.geom) = 4326
             THEN ST_Force2D(building.geom)
             ELSE ST_Transform(ST_Force2D(building.geom), 4326)
           END AS geom_4326
    FROM ai.poi_1 building
    WHERE building.datafrom_by = 'SIM_V1'
      AND building.is_deleted = FALSE
      AND building.geom IS NOT NULL
      AND NOT ST_IsEmpty(building.geom)
),
normalized AS (
    SELECT source_geometry.*,
           ST_Multi(
               ST_CollectionExtract(
                   ST_MakeValid(source_geometry.geom_4326),
                   3
               )
           )::geometry(MULTIPOLYGON, 4326) AS normalized_geom
    FROM source_geometry
)
INSERT INTO dispatch_assist.building_inventory (
    source_system,
    source_building_id,
    data_version,
    building_name,
    short_name,
    address_name,
    area_code,
    source_aoi_id,
    aoi_name,
    geom,
    representative_point,
    above_ground_floors,
    underground_floors,
    height_meters,
    building_area_square_meters,
    building_usage_code,
    building_type_code,
    fire_rescue_access,
    sensitive_target,
    source_updated_at,
    active
)
SELECT 'AI_SOURCE_SIM',
       normalized.building_id,
       'REALISTIC_AI_SOURCE_V1',
       normalized.building_name,
       normalized.short_name,
       normalized.address_name,
       normalized.area_code,
       normalized.aoi_id,
       normalized.aoi_name,
       normalized.normalized_geom,
       ST_PointOnSurface(normalized.normalized_geom),
       special.met_upfloors,
       special.met_downfloors,
       special.met_height,
       special.met_buildingarea,
       special.buildusage_id,
       special.build_type_id,
       special.fire_rescue_access,
       special.sensitive_target,
       normalized.update_time,
       TRUE
FROM normalized
LEFT JOIN ai.poi_1_building_special special
  ON special.building_id = normalized.building_id
 AND special.is_deleted = FALSE
WHERE NOT ST_IsEmpty(normalized.normalized_geom)
  AND ST_IsValid(normalized.normalized_geom);

-- BUILDING projection. The source id remains the real poi_1 key.
INSERT INTO dispatch_assist.address_inventory (
    source_system,
    source_type,
    source_id,
    data_version,
    standard_name,
    short_name,
    full_address,
    aliases,
    parent_aoi_id,
    aoi_name,
    road_name,
    geom,
    representative_point,
    source_updated_at,
    active
)
SELECT 'AI_SOURCE_SIM',
       'BUILDING',
       'ai.poi_1:' || building.source_building_id,
       'REALISTIC_AI_SOURCE_V1',
       building.building_name,
       building.short_name,
       building.address_name,
       jsonb_strip_nulls(
           jsonb_build_array(building.short_name, building.aoi_name)
       ),
       CASE WHEN building.source_aoi_id IS NULL THEN NULL
            ELSE 'ai.aoi_3:' || building.source_aoi_id END,
       building.aoi_name,
       NULL,
       building.geom,
       building.representative_point,
       building.source_updated_at,
       TRUE
FROM dispatch_assist.building_inventory building
WHERE building.source_system = 'AI_SOURCE_SIM'
  AND building.data_version = 'REALISTIC_AI_SOURCE_V1'
  AND building.active = TRUE;

-- AOI-2 projection. area_id points to the authoritative ai.aoi_1 parent.
WITH normalized AS (
    SELECT aoi.*,
           ST_MakeValid(
               CASE
                 WHEN ST_SRID(aoi.geom) = 0
                 THEN ST_SetSRID(ST_Force2D(aoi.geom), 4326)
                 WHEN ST_SRID(aoi.geom) = 4326
                 THEN ST_Force2D(aoi.geom)
                 ELSE ST_Transform(ST_Force2D(aoi.geom), 4326)
               END
           ) AS normalized_geom
    FROM ai.aoi_2 aoi
    WHERE aoi.datafrom_by = 'SIM_V1'
      AND aoi.is_deleted = FALSE
      AND aoi.geom IS NOT NULL
      AND NOT ST_IsEmpty(aoi.geom)
)
INSERT INTO dispatch_assist.address_inventory (
    source_system, source_type, source_id, data_version,
    standard_name, short_name, full_address, aliases,
    parent_aoi_id, aoi_name, road_name, geom,
    representative_point, source_updated_at, active
)
SELECT 'AI_SOURCE_SIM',
       'AOI',
       'ai.aoi_2:' || normalized.aoi_id,
       'REALISTIC_AI_SOURCE_V1',
       normalized.aoi_name,
       normalized.alias_name,
       normalized.aoi_name,
       jsonb_strip_nulls(jsonb_build_array(normalized.alias_name)),
       'ai.aoi_1:' || normalized.area_id,
       normalized.aoi_name,
       NULL,
       normalized.normalized_geom,
       ST_PointOnSurface(normalized.normalized_geom),
       normalized.update_time,
       TRUE
FROM normalized
WHERE NOT ST_IsEmpty(normalized.normalized_geom)
  AND ST_IsValid(normalized.normalized_geom);

-- AOI-3 may have several AOI-2 parents. The single parent_aoi_id field keeps
-- a deterministic primary parent for display; the full N:N relationship stays
-- in ai.aoi_3_parent_ref and is never flattened away at source.
WITH primary_parent AS (
    SELECT relation.aoi_3_id,
           MIN(relation.aoi_2_id) AS aoi_2_id
    FROM ai.aoi_3_parent_ref relation
    WHERE relation.datafrom_by = 'SIM_V1'
      AND relation.is_deleted = FALSE
    GROUP BY relation.aoi_3_id
),
normalized AS (
    SELECT aoi.*,
           parent.aoi_2_id,
           ST_MakeValid(
               CASE
                 WHEN ST_SRID(aoi.geom) = 0
                 THEN ST_SetSRID(ST_Force2D(aoi.geom), 4326)
                 WHEN ST_SRID(aoi.geom) = 4326
                 THEN ST_Force2D(aoi.geom)
                 ELSE ST_Transform(ST_Force2D(aoi.geom), 4326)
               END
           ) AS normalized_geom
    FROM ai.aoi_3 aoi
    LEFT JOIN primary_parent parent ON parent.aoi_3_id = aoi.aoi_id
    WHERE aoi.datafrom_by = 'SIM_V1'
      AND aoi.is_deleted = FALSE
      AND aoi.geom IS NOT NULL
      AND NOT ST_IsEmpty(aoi.geom)
)
INSERT INTO dispatch_assist.address_inventory (
    source_system, source_type, source_id, data_version,
    standard_name, short_name, full_address, aliases,
    parent_aoi_id, aoi_name, road_name, geom,
    representative_point, source_updated_at, active
)
SELECT 'AI_SOURCE_SIM',
       'AOI',
       'ai.aoi_3:' || normalized.aoi_id,
       'REALISTIC_AI_SOURCE_V1',
       normalized.aoi_name,
       normalized.label_name,
       normalized.aoi_name,
       jsonb_strip_nulls(jsonb_build_array(normalized.label_name)),
       CASE WHEN normalized.aoi_2_id IS NULL THEN NULL
            ELSE 'ai.aoi_2:' || normalized.aoi_2_id END,
       normalized.aoi_name,
       NULL,
       normalized.normalized_geom,
       ST_PointOnSurface(normalized.normalized_geom),
       normalized.update_time,
       TRUE
FROM normalized
WHERE NOT ST_IsEmpty(normalized.normalized_geom)
  AND ST_IsValid(normalized.normalized_geom);

-- POI-3 projection. The building/floor hierarchy remains queryable through
-- ai.poi_3 -> ai.poi_2 -> ai.poi_1; parent_aoi_id records only AOI ancestry.
WITH normalized AS (
    SELECT poi.*,
           ST_MakeValid(
               CASE
                 WHEN ST_SRID(poi.geom) = 0
                 THEN ST_SetSRID(ST_Force2D(poi.geom), 4326)
                 WHEN ST_SRID(poi.geom) = 4326
                 THEN ST_Force2D(poi.geom)
                 ELSE ST_Transform(ST_Force2D(poi.geom), 4326)
               END
           ) AS normalized_geom
    FROM ai.poi_3 poi
    WHERE poi.datafrom_by = 'SIM_V1'
      AND poi.is_deleted = FALSE
      AND poi.geom IS NOT NULL
      AND NOT ST_IsEmpty(poi.geom)
)
INSERT INTO dispatch_assist.address_inventory (
    source_system, source_type, source_id, data_version,
    standard_name, short_name, full_address, aliases,
    parent_aoi_id, aoi_name, road_name, geom,
    representative_point, source_updated_at, active
)
SELECT 'AI_SOURCE_SIM',
       'POI',
       'ai.poi_3:' || normalized.poi_id,
       'REALISTIC_AI_SOURCE_V1',
       normalized.poi_name,
       normalized.label_name,
       normalized.address_name,
       jsonb_strip_nulls(
           jsonb_build_array(normalized.label_name, normalized.room_no)
       ),
       CASE WHEN normalized.aoi_id IS NULL THEN NULL
            ELSE 'ai.aoi_3:' || normalized.aoi_id END,
       parent.aoi_name,
       NULL,
       normalized.normalized_geom,
       ST_PointOnSurface(normalized.normalized_geom),
       normalized.update_time,
       TRUE
FROM normalized
LEFT JOIN ai.aoi_3 parent
  ON parent.aoi_id = normalized.aoi_id
 AND parent.is_deleted = FALSE
WHERE NOT ST_IsEmpty(normalized.normalized_geom)
  AND ST_IsValid(normalized.normalized_geom);

-- LOI road projection.
WITH normalized AS (
    SELECT road.*,
           ST_MakeValid(
               CASE
                 WHEN ST_SRID(road.geom) = 0
                 THEN ST_SetSRID(ST_Force2D(road.geom), 4326)
                 WHEN ST_SRID(road.geom) = 4326
                 THEN ST_Force2D(road.geom)
                 ELSE ST_Transform(ST_Force2D(road.geom), 4326)
               END
           ) AS normalized_geom
    FROM ai.loi_road road
    WHERE road.datafrom_by = 'SIM_V1'
      AND road.is_deleted = FALSE
      AND road.geom IS NOT NULL
      AND NOT ST_IsEmpty(road.geom)
)
INSERT INTO dispatch_assist.address_inventory (
    source_system, source_type, source_id, data_version,
    standard_name, short_name, full_address, aliases,
    parent_aoi_id, aoi_name, road_name, geom,
    representative_point, source_updated_at, active
)
SELECT 'AI_SOURCE_SIM',
       'LOI',
       'ai.loi_road:' || normalized.road_id,
       'REALISTIC_AI_SOURCE_V1',
       COALESCE(normalized.cn_name, normalized.road_id),
       normalized.cn_name,
       normalized.cn_name,
       '[]'::jsonb,
       CASE WHEN normalized.aoi_id IS NULL THEN NULL
            ELSE 'ai.aoi_3:' || normalized.aoi_id END,
       parent.aoi_name,
       normalized.cn_name,
       normalized.normalized_geom,
       ST_PointOnSurface(normalized.normalized_geom),
       normalized.update_time,
       TRUE
FROM normalized
LEFT JOIN ai.aoi_3 parent
  ON parent.aoi_id = normalized.aoi_id
 AND parent.is_deleted = FALSE
WHERE NOT ST_IsEmpty(normalized.normalized_geom)
  AND ST_IsValid(normalized.normalized_geom);

\if :sync_address_terms
INSERT INTO dispatch_assist.address_inventory_term (
    inventory_id,
    term,
    normalized_term,
    term_type,
    weight
)
SELECT inventory.id,
       term_source.term,
       regexp_replace(
           lower(btrim(term_source.term)),
           '[[:space:][:punct:]]+',
           '',
           'g'
       ),
       term_source.term_type,
       term_source.weight
FROM dispatch_assist.address_inventory inventory
CROSS JOIN LATERAL (
    SELECT inventory.standard_name, 'STANDARD', 100
    UNION ALL SELECT inventory.short_name, 'SHORT', 95
    UNION ALL SELECT inventory.full_address, 'FULL_ADDRESS', 90
    UNION ALL SELECT inventory.aoi_name, 'AOI', 80
    UNION ALL SELECT inventory.road_name, 'ROAD', 80
    UNION ALL
    SELECT alias.value, 'ALIAS', 95
    FROM jsonb_array_elements_text(inventory.aliases) alias(value)
) term_source(term, term_type, weight)
WHERE inventory.source_system = 'AI_SOURCE_SIM'
  AND inventory.active = TRUE
  AND term_source.term IS NOT NULL
  AND btrim(term_source.term) <> ''
ON CONFLICT DO NOTHING;
\endif

ANALYZE dispatch_assist.building_inventory;
ANALYZE dispatch_assist.address_inventory;
\if :sync_address_terms
ANALYZE dispatch_assist.address_inventory_term;
\endif

COMMIT;

SELECT source_type,
       COUNT(*) AS projected_count
FROM dispatch_assist.address_inventory
WHERE source_system = 'AI_SOURCE_SIM'
  AND data_version = 'REALISTIC_AI_SOURCE_V1'
  AND active = TRUE
GROUP BY source_type
ORDER BY source_type;
