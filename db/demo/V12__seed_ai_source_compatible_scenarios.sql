\set ON_ERROR_STOP on
\timing on

-- Seeds the real-compatible ai source tables. Entity ratios are based on the
-- 2026-08-03 sample: AOI-2 78, AOI-3 38, POI-1 152, POI-3 2204, roads 490.
-- Unlike the current sample (where poi_2 is empty), the Demo creates floors
-- so the intended POI-1 -> POI-2 -> POI-3 hierarchy can be verified.

BEGIN;
SET LOCAL synchronous_commit = OFF;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM dispatch_assist.demo_location_scenario
        WHERE data_version = 'REALISTIC_AI_SOURCE_V1'
    ) THEN
        RAISE EXCEPTION
            'Run V10__seed_realistic_location_scenarios.sql first';
    END IF;
END
$$;

-- Delete only rows owned by this repeatable Demo dataset.
DELETE FROM ai.aoi_3_entrance_exit WHERE datafrom_by = 'SIM_V1';
DELETE FROM ai.aoi_3_parent_ref WHERE datafrom_by = 'SIM_V1';
DELETE FROM ai.poi_1_entrance_exit WHERE datafrom_by = 'SIM_V1';
DELETE FROM ai.poi_1_building_special WHERE datafrom_by = 'SIM_V1';
DELETE FROM ai.poi_3 WHERE datafrom_by = 'SIM_V1';
DELETE FROM ai.poi_2 WHERE datafrom_by = 'SIM_V1';
DELETE FROM ai.poi_1 WHERE datafrom_by = 'SIM_V1';
DELETE FROM ai.loi_road WHERE datafrom_by = 'SIM_V1';
DELETE FROM ai.aoi_3 WHERE datafrom_by = 'SIM_V1';
DELETE FROM ai.aoi_2 WHERE datafrom_by = 'SIM_V1';
DELETE FROM ai.aoi_1 WHERE datafrom_by = 'SIM_V1';

CREATE TEMP TABLE ai_sim_counts ON COMMIT DROP AS
WITH base AS (
    SELECT scenario.scenario_code,
           scenario.anchor_longitude,
           scenario.anchor_latitude,
           scenario.address_spread_x_meters,
           scenario.address_spread_y_meters,
           GREATEST(5, scenario.address_count) AS target_address_count
    FROM dispatch_assist.demo_location_scenario scenario
    WHERE scenario.data_version = 'REALISTIC_AI_SOURCE_V1'
),
allocated AS (
    SELECT base.*,
           GREATEST(
               1,
               ROUND(target_address_count * 78.0 / 2962.0)::integer
           ) AS aoi_2_count,
           GREATEST(
               1,
               ROUND(target_address_count * 38.0 / 2962.0)::integer
           ) AS aoi_3_count,
           GREATEST(
               1,
               ROUND(target_address_count * 152.0 / 2962.0)::integer
           ) AS building_count,
           GREATEST(
               1,
               ROUND(target_address_count * 2204.0 / 2962.0)::integer
           ) AS poi_count
    FROM base
)
SELECT allocated.*,
       GREATEST(
           1,
           target_address_count
               - aoi_2_count
               - aoi_3_count
               - building_count
               - poi_count
       ) AS road_count
FROM allocated;

CREATE TEMP TABLE ai_sim_entity_point ON COMMIT DROP AS
WITH entity_counts AS (
    SELECT counts.*,
           entity.entity_type,
           entity.entity_count
    FROM ai_sim_counts counts
    CROSS JOIN LATERAL (
        VALUES
            ('A2', counts.aoi_2_count),
            ('A3', counts.aoi_3_count),
            ('B1', counts.building_count),
            ('P3', counts.poi_count),
            ('R1', counts.road_count)
    ) entity(entity_type, entity_count)
),
generated AS (
    SELECT entity_counts.*,
           sequence_no,
           CEIL(SQRT(entity_count::numeric))::integer AS grid_width
    FROM entity_counts
    CROSS JOIN LATERAL generate_series(
        1,
        entity_counts.entity_count
    ) sequence_source(sequence_no)
),
positioned AS (
    SELECT generated.*,
           ((sequence_no - 1) % grid_width)::integer AS grid_column,
           ((sequence_no - 1) / grid_width)::integer AS grid_row,
           CEIL(entity_count::numeric / grid_width)::integer
               AS grid_height
    FROM generated
)
SELECT positioned.*,
       anchor_longitude
           + (
               (
                   grid_column::double precision
                       / GREATEST(1, grid_width - 1)
                       - 0.5
               ) * 2 * address_spread_x_meters
               + CASE entity_type
                   WHEN 'A3' THEN 25
                   WHEN 'B1' THEN 45
                   WHEN 'P3' THEN 65
                   ELSE 0
                 END
             )
             / (
                 111320.0
                 * COS(RADIANS(anchor_latitude))
               ) AS longitude,
       anchor_latitude
           + (
               (
                   grid_row::double precision
                       / GREATEST(1, grid_height - 1)
                       - 0.5
               ) * 2 * address_spread_y_meters
             ) / 111320.0 AS latitude
FROM positioned;

CREATE INDEX ON ai_sim_entity_point (
    scenario_code,
    entity_type,
    sequence_no
);

-- AOI-1 administrative parents. The real table has no PK, so the Demo uses
-- deterministic unique values without adding a source-incompatible key.
INSERT INTO ai.aoi_1 (
    area_id,
    area_code,
    area_name,
    addrlevel_id,
    parent_code,
    seq,
    update_time,
    is_deleted,
    datafrom_by
)
SELECT substr(md5(point.scenario_code || ':A1:'
                  || point.sequence_no), 1, 32),
       substr(md5(point.scenario_code || ':AC:'
                  || point.sequence_no), 1, 12),
       point.scenario_code || '行政区域' || point.sequence_no,
       '4',
       substr(md5(point.scenario_code || ':ROOT'), 1, 12),
       point.sequence_no,
       CURRENT_TIMESTAMP,
       FALSE,
       'SIM_V1'
FROM ai_sim_entity_point point
WHERE point.entity_type = 'A2';

INSERT INTO ai.aoi_2 (
    aoi_id,
    aoi_name,
    alias_name,
    area_id,
    aoi_typeid,
    aoi_typename,
    coord_sys,
    longitude,
    latitude,
    geom,
    radius,
    data_source,
    captured_at,
    create_by,
    create_time,
    update_by,
    update_time,
    is_deleted,
    datafrom_by
)
SELECT substr(md5(point.scenario_code || ':A2:'
                  || point.sequence_no), 1, 32),
       point.scenario_code || '二级区域' || point.sequence_no,
       point.scenario_code || '区域' || point.sequence_no,
       substr(md5(point.scenario_code || ':A1:'
                  || point.sequence_no), 1, 32),
       'A2_SIM',
       '二级区域',
       'WGS84',
       point.longitude,
       point.latitude,
       ST_MakeEnvelope(
           point.longitude
               - 220.0
                 / (111320.0 * COS(RADIANS(point.latitude))),
           point.latitude - 220.0 / 111320.0,
           point.longitude
               + 220.0
                 / (111320.0 * COS(RADIANS(point.latitude))),
           point.latitude + 220.0 / 111320.0,
           4326),
       220,
       'REALISTIC_AI_SOURCE',
       CURRENT_TIMESTAMP,
       'demo',
       CURRENT_TIMESTAMP,
       NULL,
       CURRENT_TIMESTAMP,
       FALSE,
       'SIM_V1'
FROM ai_sim_entity_point point
WHERE point.entity_type = 'A2';

INSERT INTO ai.aoi_3 (
    aoi_id,
    aoi_name,
    label_name,
    area_id,
    aoi_typeid,
    aoi_typename,
    coord_sys,
    longitude,
    latitude,
    geom,
    aoi_area,
    org_id,
    data_source,
    captured_at,
    create_by,
    create_time,
    update_by,
    update_time,
    is_deleted,
    datafrom_by
)
SELECT substr(md5(point.scenario_code || ':A3:'
                  || point.sequence_no), 1, 32),
       point.scenario_code || '三级区域' || point.sequence_no,
       point.scenario_code || '小区' || point.sequence_no,
       substr(md5(point.scenario_code || ':A1:'
                  || parent.parent_sequence), 1, 32),
       'A3_SIM',
       '三级区域',
       'WGS84',
       point.longitude,
       point.latitude,
       ST_Multi(
           ST_MakeEnvelope(
               point.longitude
                   - 90.0
                     / (111320.0 * COS(RADIANS(point.latitude))),
               point.latitude - 90.0 / 111320.0,
               point.longitude
                   + 90.0
                     / (111320.0 * COS(RADIANS(point.latitude))),
               point.latitude + 90.0 / 111320.0,
               4326)),
       32400,
       NULL,
       'REALISTIC_AI_SOURCE',
       CURRENT_TIMESTAMP,
       'demo',
       CURRENT_TIMESTAMP,
       NULL,
       CURRENT_TIMESTAMP,
       FALSE,
       'SIM_V1'
FROM ai_sim_entity_point point
JOIN ai_sim_counts counts USING (scenario_code)
CROSS JOIN LATERAL (
    SELECT MOD(point.sequence_no - 1, counts.aoi_2_count) + 1
               AS parent_sequence
) parent
WHERE point.entity_type = 'A3';

INSERT INTO ai.aoi_3_parent_ref (
    id,
    aoi_3_id,
    aoi_2_id,
    create_by,
    create_time,
    update_by,
    update_time,
    is_deleted,
    datafrom_by
)
SELECT substr(md5(point.scenario_code || ':A3REF:'
                  || point.sequence_no || ':' || parent_offset), 1, 32),
       substr(md5(point.scenario_code || ':A3:'
                  || point.sequence_no), 1, 32),
       substr(md5(point.scenario_code || ':A2:'
                  || (
                      MOD(
                          point.sequence_no + parent_offset - 2,
                          counts.aoi_2_count
                      ) + 1
                  )), 1, 32),
       'demo',
       CURRENT_TIMESTAMP,
       NULL,
       CURRENT_TIMESTAMP,
       FALSE,
       'SIM_V1'
FROM ai_sim_entity_point point
JOIN ai_sim_counts counts USING (scenario_code)
CROSS JOIN LATERAL generate_series(
    1,
    LEAST(5, counts.aoi_2_count)
) offset_source(parent_offset)
WHERE point.entity_type = 'A3';

INSERT INTO ai.aoi_3_entrance_exit (
    id,
    aoi_id,
    name,
    longitude,
    latitude,
    geom,
    coord_sys,
    gate_type,
    is_firepass,
    status,
    create_by,
    create_time,
    update_by,
    update_time,
    is_deleted,
    datafrom_by
)
SELECT substr(md5(point.scenario_code || ':A3GATE:'
                  || point.sequence_no), 1, 32),
       substr(md5(point.scenario_code || ':A3:'
                  || point.sequence_no), 1, 32),
       '区域出入口' || point.sequence_no,
       point.longitude,
       point.latitude,
       ST_SetSRID(ST_MakePoint(point.longitude, point.latitude), 4326),
       'WGS84',
       1,
       MOD(point.sequence_no, 2) = 0,
       'ACTIVE',
       'demo',
       CURRENT_TIMESTAMP,
       NULL,
       CURRENT_TIMESTAMP,
       FALSE,
       'SIM_V1'
FROM ai_sim_entity_point point
WHERE point.entity_type = 'A3'
  AND MOD(point.sequence_no, 4) = 0;

INSERT INTO ai.poi_1 (
    building_id,
    building_name,
    short_name,
    area_code,
    city_name,
    county_name,
    street_name,
    address_name,
    longitude,
    latitude,
    geom,
    coord_sys,
    org_id,
    aoi_id,
    aoi_name,
    data_source,
    captured_at,
    create_by,
    create_time,
    update_by,
    update_time,
    is_deleted,
    datafrom_by
)
SELECT substr(md5(point.scenario_code || ':B1:'
                  || point.sequence_no), 1, 32),
       point.scenario_code || '建筑' || point.sequence_no,
       point.scenario_code || '楼' || point.sequence_no,
       substr(md5(point.scenario_code || ':AREA'), 1, 12),
       '模拟市',
       '模拟区',
       '场景路',
       point.scenario_code || '场景路' || point.sequence_no || '号',
       point.longitude
           + 480.0
             / (111320.0 * COS(RADIANS(point.latitude))),
       point.latitude,
       CASE
         WHEN MOD(point.sequence_no, 2) = 0
         THEN ST_Multi(
                ST_MakeEnvelope(
                    point.longitude
                        - 18.0
                          / (111320.0 * COS(RADIANS(point.latitude))),
                    point.latitude - 18.0 / 111320.0,
                    point.longitude
                        + 18.0
                          / (111320.0 * COS(RADIANS(point.latitude))),
                    point.latitude + 18.0 / 111320.0,
                    4326))
         ELSE ST_MakeEnvelope(
                point.longitude
                    - 18.0
                      / (111320.0 * COS(RADIANS(point.latitude))),
                point.latitude - 18.0 / 111320.0,
                point.longitude
                    + 18.0
                      / (111320.0 * COS(RADIANS(point.latitude))),
                point.latitude + 18.0 / 111320.0,
                4326)
       END,
       'WGS84',
       NULL,
       substr(md5(point.scenario_code || ':A3:'
                  || parent.parent_sequence), 1, 32),
       point.scenario_code || '三级区域' || parent.parent_sequence,
       'REALISTIC_AI_SOURCE',
       CURRENT_TIMESTAMP,
       'demo',
       CURRENT_TIMESTAMP,
       NULL,
       CURRENT_TIMESTAMP,
       FALSE,
       'SIM_V1'
FROM ai_sim_entity_point point
JOIN ai_sim_counts counts USING (scenario_code)
CROSS JOIN LATERAL (
    SELECT MOD(point.sequence_no - 1, counts.aoi_3_count) + 1
               AS parent_sequence
) parent
WHERE point.entity_type = 'B1';

INSERT INTO ai.poi_1_building_special (
    building_id,
    met_buildingarea,
    met_height,
    met_floorheight,
    met_upheight,
    met_upfloors,
    met_downfloors,
    met_depth,
    met_podiumfloors,
    met_floors,
    met_standardarea,
    met_coverarea,
    met_e_nearby,
    met_s_nearby,
    met_w_nearby,
    met_n_nearby,
    sensitive_target,
    climbing_position,
    met_climbing,
    fire_rescue_access,
    buildusage_id,
    build_type_id,
    storage_material,
    floor_plan_url,
    diagram3d_url,
    create_by,
    create_time,
    update_by,
    update_time,
    is_deleted,
    datafrom_by
)
SELECT building.building_id,
       1200 + MOD(row_number() OVER (), 800),
       18 + MOD(row_number() OVER (), 80),
       3.5,
       15,
       5 + MOD(row_number() OVER (), 25),
       MOD(row_number() OVER (), 4),
       6,
       1,
       5 + MOD(row_number() OVER (), 25),
       120,
       900,
       12,
       12,
       12,
       12,
       NULL,
       '北侧登高面',
       20,
       '东侧消防救援口',
       '1602',
       CASE WHEN MOD(row_number() OVER (), 3) = 0
            THEN '10' ELSE '20' END,
       NULL,
       NULL,
       NULL,
       'demo',
       CURRENT_TIMESTAMP,
       NULL,
       CURRENT_TIMESTAMP,
       FALSE,
       'SIM_V1'
FROM ai.poi_1 building
WHERE building.datafrom_by = 'SIM_V1'
  AND building.is_deleted = FALSE;

INSERT INTO ai.poi_2 (
    floor_id,
    floor_name,
    building_id,
    floor_typeid,
    floor_typename,
    relative_height,
    floor_area,
    data_source,
    captured_at,
    create_by,
    create_time,
    update_by,
    update_time,
    is_deleted,
    datafrom_by
)
SELECT substr(md5(building.building_id || ':F:' || floor_no), 1, 32),
       floor_no || '层',
       building.building_id,
       'FLOOR',
       '标准楼层',
       (floor_no - 1) * 3.5,
       900,
       'REALISTIC_AI_SOURCE',
       CURRENT_TIMESTAMP,
       'demo',
       CURRENT_TIMESTAMP,
       NULL,
       CURRENT_TIMESTAMP,
       FALSE,
       'SIM_V1'
FROM ai.poi_1 building
CROSS JOIN generate_series(1, 3) floor_source(floor_no)
WHERE building.datafrom_by = 'SIM_V1'
  AND building.is_deleted = FALSE;

INSERT INTO ai.poi_3 (
    poi_id,
    poi_name,
    label_name,
    poi_typeid,
    poi_typename,
    floor_id,
    coord_sys,
    longitude,
    latitude,
    geom,
    area_id,
    address_name,
    aoi_id,
    building_id,
    org_id,
    room_no,
    poi_area,
    create_by,
    create_time,
    update_by,
    update_time,
    is_deleted,
    datafrom_by
)
SELECT substr(md5(point.scenario_code || ':P3:'
                  || point.sequence_no), 1, 32),
       point.scenario_code || '场所' || point.sequence_no,
       point.scenario_code || '单位' || point.sequence_no,
       'POI_SIM',
       '室内场所',
       substr(md5(building.building_id || ':F:'
                  || floor_no), 1, 32),
       'WGS84',
       ST_X(center.point_geom),
       ST_Y(center.point_geom),
       center.point_geom,
       parent_aoi.area_id,
       building.address_name || ' ' || floor_no || '层',
       building.aoi_id,
       building.building_id,
       NULL,
       'R-' || point.sequence_no,
       30,
       'demo',
       CURRENT_TIMESTAMP,
       NULL,
       CURRENT_TIMESTAMP,
       FALSE,
       'SIM_V1'
FROM ai_sim_entity_point point
JOIN ai_sim_counts counts USING (scenario_code)
CROSS JOIN LATERAL (
    SELECT MOD(point.sequence_no - 1, counts.building_count) + 1
               AS building_sequence,
           MOD(point.sequence_no - 1, 3) + 1 AS floor_no
) relation
JOIN ai.poi_1 building
  ON building.building_id = substr(
       md5(point.scenario_code || ':B1:'
           || relation.building_sequence),
       1,
       32)
JOIN ai.aoi_3 parent_aoi
  ON parent_aoi.aoi_id = building.aoi_id
 AND parent_aoi.is_deleted = FALSE
CROSS JOIN LATERAL (
    SELECT ST_PointOnSurface(building.geom) AS point_geom
) center
WHERE point.entity_type = 'P3';

-- The real sample currently has no poi_1_entrance_exit rows. The table is
-- retained but deliberately left empty in this dataset.

INSERT INTO ai.loi_road (
    road_id,
    cn_name,
    mesh,
    area_code,
    aoi_id,
    geom,
    coord_sys,
    loi_typeid,
    loi_typename,
    start_node,
    end_node,
    road_class,
    road_length,
    road_width,
    lane_no,
    lane_width,
    road_direct,
    road_toll,
    road_owner,
    road_status,
    road_form,
    side_road,
    inner_cross,
    service_road,
    slipe_road,
    entry_exit,
    slip_road,
    is_roundabout,
    is_bridge,
    is_ferry,
    is_tunnel,
    is_elevated,
    func_class,
    object_type,
    data_source,
    captured_at,
    create_by,
    create_time,
    update_by,
    update_time,
    is_deleted,
    datafrom_by
)
SELECT substr(md5(point.scenario_code || ':R1:'
                  || point.sequence_no), 1, 32),
       point.scenario_code || '道路' || point.sequence_no,
       substr(md5(point.scenario_code || ':MESH'), 1, 10),
       substr(md5(point.scenario_code || ':AREA'), 1, 12),
       substr(md5(point.scenario_code || ':A3:'
                  || parent.parent_sequence), 1, 32),
       ST_Multi(
           ST_MakeLine(
               ST_SetSRID(
                   ST_MakePoint(
                       point.longitude
                           - 80.0
                             / (
                                 111320.0
                                 * COS(RADIANS(point.latitude))
                               ),
                       point.latitude),
                   4326),
               ST_SetSRID(
                   ST_MakePoint(
                       point.longitude
                           + 80.0
                             / (
                                 111320.0
                                 * COS(RADIANS(point.latitude))
                               ),
                       point.latitude),
                   4326))),
       'WGS84',
       'ROAD',
       '道路',
       substr(md5(point.scenario_code || ':RS:'
                  || point.sequence_no), 1, 32),
       substr(md5(point.scenario_code || ':RE:'
                  || point.sequence_no), 1, 32),
       '3',
       160,
       12,
       2,
       3.5,
       0,
       0,
       0,
       1,
       1,
       0,
       0,
       0,
       0,
       0,
       0,
       0,
       0,
       0,
       0,
       0,
       3,
       'ROAD_SEGMENT',
       'REALISTIC_AI_SOURCE',
       CURRENT_TIMESTAMP,
       'demo',
       CURRENT_TIMESTAMP,
       NULL,
       CURRENT_TIMESTAMP,
       FALSE,
       'SIM_V1'
FROM ai_sim_entity_point point
JOIN ai_sim_counts counts USING (scenario_code)
CROSS JOIN LATERAL (
    SELECT MOD(point.sequence_no - 1, counts.aoi_3_count) + 1
               AS parent_sequence
) parent
WHERE point.entity_type = 'R1';

ANALYZE ai.aoi_1;
ANALYZE ai.aoi_2;
ANALYZE ai.aoi_3;
ANALYZE ai.aoi_3_parent_ref;
ANALYZE ai.poi_1;
ANALYZE ai.poi_1_building_special;
ANALYZE ai.poi_2;
ANALYZE ai.poi_3;
ANALYZE ai.loi_road;

COMMIT;

SELECT source_table,
       source_count
FROM (
    SELECT 'aoi_1' AS source_table, COUNT(*) AS source_count
    FROM ai.aoi_1 WHERE datafrom_by = 'SIM_V1'
    UNION ALL
    SELECT 'aoi_2', COUNT(*) FROM ai.aoi_2
    WHERE datafrom_by = 'SIM_V1'
    UNION ALL
    SELECT 'aoi_3', COUNT(*) FROM ai.aoi_3
    WHERE datafrom_by = 'SIM_V1'
    UNION ALL
    SELECT 'aoi_3_parent_ref', COUNT(*) FROM ai.aoi_3_parent_ref
    WHERE datafrom_by = 'SIM_V1'
    UNION ALL
    SELECT 'aoi_3_entrance_exit', COUNT(*)
    FROM ai.aoi_3_entrance_exit WHERE datafrom_by = 'SIM_V1'
    UNION ALL
    SELECT 'poi_1', COUNT(*) FROM ai.poi_1
    WHERE datafrom_by = 'SIM_V1'
    UNION ALL
    SELECT 'poi_1_building_special', COUNT(*)
    FROM ai.poi_1_building_special WHERE datafrom_by = 'SIM_V1'
    UNION ALL
    SELECT 'poi_1_entrance_exit', COUNT(*)
    FROM ai.poi_1_entrance_exit WHERE datafrom_by = 'SIM_V1'
    UNION ALL
    SELECT 'poi_2', COUNT(*) FROM ai.poi_2
    WHERE datafrom_by = 'SIM_V1'
    UNION ALL
    SELECT 'poi_3', COUNT(*) FROM ai.poi_3
    WHERE datafrom_by = 'SIM_V1'
    UNION ALL
    SELECT 'loi_road', COUNT(*) FROM ai.loi_road
    WHERE datafrom_by = 'SIM_V1'
) summary
ORDER BY source_table;
