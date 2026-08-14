\set ON_ERROR_STOP on
\timing on

-- Realistic coordinate-location POC data.
--
-- This seed deliberately differs from the uniform scale grid:
--   1. site spacing and coverage vary by urban/rural environment;
--   2. one physical site owns multiple sector rows;
--   3. one scene has LTE and NR co-located at every site;
--   4. a transport corridor is long and narrow;
--   5. a library-edge scene has fewer than the target six neighbors;
--   6. an isolated site has no usable neighbor;
--   7. an inactive stale row is placed at the exact active anchor coordinate;
--   8. Address data is seeded into real-compatible ai source tables by V12.
--
-- Override address volume when a faster smoke test is needed:
-- psql ... -v address_scale=0.10 -f V10__seed_realistic_location_scenarios.sql
-- Keep one address_scale value for one data_version. Address rows are treated
-- as immutable versioned input and are not deleted on an idempotent rerun.

\if :{?address_scale}
\else
  \set address_scale 1.00
\endif

-- Retained only for reproducing the older benchmark. The normal Demo path
-- must seed ai.* source tables and then run the explicit V13 projection.
\if :{?seed_legacy_address_inventory}
\else
  \set seed_legacy_address_inventory false
\endif

BEGIN;
SET LOCAL synchronous_commit = OFF;

DROP TABLE IF EXISTS pg_temp.realistic_scenario_definition;
CREATE TEMP TABLE realistic_scenario_definition (
    scenario_no INTEGER PRIMARY KEY,
    scenario_code VARCHAR(32) UNIQUE NOT NULL,
    display_name VARCHAR(128) NOT NULL,
    operator_code VARCHAR(32) UNIQUE NOT NULL,
    environment_type VARCHAR(16) NOT NULL,
    layout_type VARCHAR(24) NOT NULL,
    center_longitude DOUBLE PRECISION NOT NULL,
    center_latitude DOUBLE PRECISION NOT NULL,
    grid_rows INTEGER NOT NULL,
    grid_columns INTEGER NOT NULL,
    site_spacing_meters DOUBLE PRECISION NOT NULL,
    sector_rows_per_site INTEGER NOT NULL,
    rat_profile VARCHAR(16) NOT NULL,
    radius_factor DOUBLE PRECISION NOT NULL,
    minimum_radius_meters DOUBLE PRECISION NOT NULL,
    maximum_radius_meters DOUBLE PRECISION NOT NULL,
    fallback_radius_meters DOUBLE PRECISION NOT NULL,
    max_neighbor_distance_meters DOUBLE PRECISION NOT NULL,
    base_address_count INTEGER NOT NULL,
    address_spread_x_meters DOUBLE PRECISION NOT NULL,
    address_spread_y_meters DOUBLE PRECISION NOT NULL,
    expected_neighbor_count INTEGER NOT NULL,
    expected_neighbor_source VARCHAR(32) NOT NULL,
    expected_warning VARCHAR(64)
);

INSERT INTO realistic_scenario_definition VALUES
    (1, 'DENSE_URBAN', 'Dense urban core', 'SIM_DENSE',
     'URBAN', 'STAGGERED_GRID', 116.330000, 39.920000,
     9, 9, 220, 3, 'LTE',
     0.55, 100, 500, 180, 3000,
     36000, 1400, 1400, 6, 'SPATIAL_DERIVED', NULL),
    (2, 'URBAN', 'Ordinary urban area', 'SIM_URBAN',
     'URBAN', 'STAGGERED_GRID', 116.520000, 39.920000,
     7, 7, 450, 3, 'LTE',
     0.60, 150, 900, 320, 4000,
     24000, 2100, 2100, 6, 'SPATIAL_DERIVED', NULL),
    (3, 'SUBURBAN', 'Suburban area', 'SIM_SUBURBAN',
     'SUBURBAN', 'STAGGERED_GRID', 116.330000, 40.100000,
     7, 7, 900, 3, 'LTE',
     0.65, 300, 1800, 650, 6000,
     12000, 3600, 3600, 6, 'SPATIAL_DERIVED', NULL),
    (4, 'RURAL', 'Sparse rural area', 'SIM_RURAL',
     'RURAL', 'STAGGERED_GRID', 116.650000, 40.120000,
     5, 5, 1800, 3, 'LTE',
     0.70, 800, 3500, 1400, 8000,
     6000, 5200, 5200, 6, 'SPATIAL_DERIVED', NULL),
    (5, 'TRANSPORT_CORRIDOR', 'Expressway and railway corridor',
     'SIM_CORRIDOR', 'SUBURBAN', 'CORRIDOR',
     116.160000, 39.700000,
     1, 25, 650, 2, 'LTE',
     0.65, 300, 1600, 500, 5000,
     9000, 9000, 650, 6, 'SPATIAL_DERIVED', NULL),
    (6, 'COLOCATED_MIXED_RAT', 'Co-located LTE and NR multi-sector sites',
     'SIM_MIXED', 'URBAN', 'STAGGERED_GRID',
     116.670000, 39.750000,
     5, 5, 500, 6, 'LTE_NR',
     0.60, 180, 1000, 360, 5000,
     8000, 1800, 1800, 6, 'SPATIAL_DERIVED', NULL),
    (7, 'LIBRARY_EDGE', 'Edge of the available station library',
     'SIM_EDGE', 'RURAL', 'EDGE_LINE',
     116.900000, 40.050000,
     1, 5, 1600, 3, 'LTE',
     0.70, 700, 2600, 1200, 8000,
     3000, 4000, 1400, 4, 'SPATIAL_DERIVED',
     'SPATIAL_NEIGHBOR_COUNT_BELOW_TARGET'),
    (8, 'ISOLATED_SITE', 'Isolated station with no other site in range',
     'SIM_ISOLATED', 'RURAL', 'ISOLATED',
     116.950000, 39.700000,
     1, 1, 1000, 3, 'LTE',
     0.70, 800, 3500, 1800, 5000,
     1000, 1000, 1000, 0, 'NONE',
     'SPATIAL_NEIGHBORS_NOT_AVAILABLE');

CREATE TABLE IF NOT EXISTS dispatch_assist.demo_location_scenario (
    scenario_code VARCHAR(32) PRIMARY KEY,
    display_name VARCHAR(128) NOT NULL,
    data_version VARCHAR(64) NOT NULL,
    environment_type VARCHAR(16) NOT NULL,
    layout_type VARCHAR(24) NOT NULL,
    anchor_longitude DOUBLE PRECISION NOT NULL,
    anchor_latitude DOUBLE PRECISION NOT NULL,
    physical_site_count INTEGER NOT NULL,
    active_sector_count INTEGER NOT NULL,
    address_count INTEGER NOT NULL,
    address_spread_x_meters DOUBLE PRECISION NOT NULL DEFAULT 1000,
    address_spread_y_meters DOUBLE PRECISION NOT NULL DEFAULT 1000,
    expected_neighbor_count INTEGER NOT NULL,
    expected_neighbor_source VARCHAR(32) NOT NULL,
    expected_warning VARCHAR(64),
    notes VARCHAR(512),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE dispatch_assist.demo_location_scenario
    ADD COLUMN IF NOT EXISTS address_spread_x_meters
        DOUBLE PRECISION NOT NULL DEFAULT 1000;
ALTER TABLE dispatch_assist.demo_location_scenario
    ADD COLUMN IF NOT EXISTS address_spread_y_meters
        DOUBLE PRECISION NOT NULL DEFAULT 1000;

DELETE FROM dispatch_assist.cell_neighbor_relation relation
WHERE relation.serving_sector_id IN (
          SELECT id
          FROM dispatch_assist.cell_sector
          WHERE data_source = 'REALISTIC_COORDINATE_SCENARIO'
      )
   OR relation.neighbor_sector_id IN (
          SELECT id
          FROM dispatch_assist.cell_sector
          WHERE data_source = 'REALISTIC_COORDINATE_SCENARIO'
      );

WITH physical_sites AS (
    SELECT definition.*,
           grid_row,
           grid_column,
           grid_row * definition.grid_columns
               + grid_column + 1 AS site_no,
           definition.center_longitude
               + (
                   (grid_column
                       - (definition.grid_columns - 1) / 2.0)
                       * definition.site_spacing_meters
                   + CASE
                       WHEN definition.layout_type = 'STAGGERED_GRID'
                            AND MOD(grid_row, 2) = 1
                            AND grid_row
                                <> (definition.grid_rows - 1) / 2
                       THEN definition.site_spacing_meters * 0.18
                       ELSE 0
                     END
                 )
                 / (
                     111320.0
                     * COS(RADIANS(definition.center_latitude))
                   ) AS site_longitude,
           definition.center_latitude
               + (
                   (grid_row
                       - (definition.grid_rows - 1) / 2.0)
                       * definition.site_spacing_meters
                   + CASE
                       WHEN definition.layout_type = 'CORRIDOR'
                       THEN SIN(grid_column * PI() / 4.0) * 80
                       ELSE 0
                     END
                 ) / 111320.0 AS site_latitude
    FROM realistic_scenario_definition definition
    CROSS JOIN LATERAL generate_series(
        0,
        definition.grid_rows - 1
    ) row_source(grid_row)
    CROSS JOIN LATERAL generate_series(
        0,
        definition.grid_columns - 1
    ) column_source(grid_column)
),
sector_variants AS (
    SELECT physical_sites.*,
           variant_no,
           CASE
             WHEN rat_profile = 'LTE_NR' AND variant_no > 3
             THEN 'NR'
             ELSE 'LTE'
           END AS rat,
           CASE MOD(variant_no - 1, 3)
             WHEN 1 THEN 6.0
             ELSE 0.0
           END AS longitude_offset_meters,
           CASE MOD(variant_no - 1, 3)
             WHEN 2 THEN -6.0
             ELSE 0.0
           END AS latitude_offset_meters
    FROM physical_sites
    CROSS JOIN LATERAL generate_series(
        1,
        physical_sites.sector_rows_per_site
    ) variant_source(variant_no)
)
INSERT INTO dispatch_assist.cell_sector (
    operator_code,
    rat,
    mcc,
    mnc,
    area_code_type,
    area_code,
    cell_id,
    pci,
    site_name,
    site_location,
    azimuth_degrees,
    beam_width_degrees,
    nominal_radius_meters,
    coverage_geom,
    environment_type,
    data_source,
    quality_score,
    effective_from,
    active,
    version
)
SELECT operator_code,
       rat,
       '460',
       LPAD(scenario_no::text, 2, '0'),
       'TAC',
       (93000 + scenario_no)::text,
       (
         scenario_no * 1000000
         + site_no * 10
         + variant_no
       )::text,
       MOD(site_no * 17 + variant_no * 31, 504),
       scenario_code || '-SITE-' || LPAD(site_no::text, 4, '0'),
       ST_SetSRID(
           ST_MakePoint(
               site_longitude
                   + longitude_offset_meters
                     / (
                         111320.0
                         * COS(RADIANS(site_latitude))
                       ),
               site_latitude
                   + latitude_offset_meters / 111320.0
           ),
           4326
       )::geography,
       MOD((variant_no - 1) * 120, 360),
       120,
       NULL,
       NULL,
       environment_type,
       'REALISTIC_COORDINATE_SCENARIO',
       CASE
         WHEN rat_profile = 'LTE_NR' AND variant_no = 4 THEN 0.99
         WHEN variant_no = 1 THEN 0.97
         ELSE 0.82 - MOD(variant_no - 1, 3) * 0.03
       END,
       '2026-07-30T00:00:00+08:00',
       TRUE,
       9301
FROM sector_variants
ON CONFLICT (
    operator_code,
    rat,
    mcc,
    mnc,
    area_code,
    cell_id,
    version
) DO UPDATE SET
    pci = EXCLUDED.pci,
    site_name = EXCLUDED.site_name,
    site_location = EXCLUDED.site_location,
    azimuth_degrees = EXCLUDED.azimuth_degrees,
    beam_width_degrees = EXCLUDED.beam_width_degrees,
    environment_type = EXCLUDED.environment_type,
    data_source = EXCLUDED.data_source,
    quality_score = EXCLUDED.quality_score,
    effective_from = EXCLUDED.effective_from,
    effective_to = NULL,
    active = TRUE,
    updated_at = CURRENT_TIMESTAMP;

-- A stale row at the exact dense-urban anchor must never win the lookup.
INSERT INTO dispatch_assist.cell_sector (
    operator_code,
    rat,
    mcc,
    mnc,
    area_code_type,
    area_code,
    cell_id,
    site_name,
    site_location,
    nominal_radius_meters,
    coverage_geom,
    environment_type,
    data_source,
    quality_score,
    effective_from,
    effective_to,
    active,
    version
) VALUES (
    'SIM_DENSE',
    'LTE',
    '460',
    '01',
    'TAC',
    '93001',
    '1999999',
    'DENSE_URBAN-STALE-ROW',
    ST_SetSRID(ST_MakePoint(116.330000, 39.920000), 4326)::geography,
    9999,
    ST_Multi(
        ST_Buffer(
            ST_SetSRID(
                ST_MakePoint(116.330000, 39.920000),
                4326
            )::geography,
            9999
        )::geometry
    ),
    'URBAN',
    'REALISTIC_COORDINATE_SCENARIO',
    1.0,
    '2025-01-01T00:00:00+08:00',
    '2026-01-01T00:00:00+08:00',
    FALSE,
    9999
)
ON CONFLICT (
    operator_code,
    rat,
    mcc,
    mnc,
    area_code,
    cell_id,
    version
) DO UPDATE SET
    site_name = EXCLUDED.site_name,
    site_location = EXCLUDED.site_location,
    nominal_radius_meters = EXCLUDED.nominal_radius_meters,
    coverage_geom = EXCLUDED.coverage_geom,
    data_source = EXCLUDED.data_source,
    quality_score = EXCLUDED.quality_score,
    effective_from = EXCLUDED.effective_from,
    effective_to = EXCLUDED.effective_to,
    active = FALSE,
    updated_at = CURRENT_TIMESTAMP;

CREATE TEMP TABLE realistic_site_group
ON COMMIT DROP
AS
SELECT sector.id AS sector_id,
       MIN(peer.id::text)::uuid AS site_group_id
FROM dispatch_assist.cell_sector sector
JOIN dispatch_assist.cell_sector peer
  ON peer.data_source = 'REALISTIC_COORDINATE_SCENARIO'
 AND peer.active = TRUE
 AND peer.operator_code = sector.operator_code
 AND peer.rat = sector.rat
 AND ST_DWithin(
       sector.site_location,
       peer.site_location,
       50)
WHERE sector.data_source = 'REALISTIC_COORDINATE_SCENARIO'
  AND sector.active = TRUE
GROUP BY sector.id;

CREATE UNIQUE INDEX idx_realistic_site_group_sector
    ON realistic_site_group(sector_id);
CREATE INDEX idx_realistic_site_group_group
    ON realistic_site_group(site_group_id);
ANALYZE realistic_site_group;

CREATE TEMP TABLE realistic_neighbor_selection
ON COMMIT DROP
AS
SELECT serving.id AS serving_id,
       neighbor.id AS neighbor_id,
       neighbor.distance_meters,
       neighbor.rank_no
FROM dispatch_assist.cell_sector serving
JOIN realistic_scenario_definition definition
  ON definition.operator_code = serving.operator_code
JOIN realistic_site_group serving_group
  ON serving_group.sector_id = serving.id
CROSS JOIN LATERAL (
    SELECT distinct_site.id,
           distinct_site.distance_meters,
           ROW_NUMBER() OVER (
               ORDER BY distinct_site.distance_meters,
                        distinct_site.id)::integer AS rank_no
    FROM (
        SELECT DISTINCT ON (candidate_pool.site_group_id)
               candidate_pool.id,
               candidate_pool.site_group_id,
               candidate_pool.distance_meters
        FROM (
            SELECT candidate.id,
                   candidate_group.site_group_id,
                   ST_Distance(
                       serving.site_location,
                       candidate.site_location) AS distance_meters,
                   candidate.quality_score
            FROM dispatch_assist.cell_sector candidate
            JOIN realistic_site_group candidate_group
              ON candidate_group.sector_id = candidate.id
            WHERE candidate.data_source =
                    'REALISTIC_COORDINATE_SCENARIO'
              AND candidate.active = TRUE
              AND candidate.operator_code = serving.operator_code
              AND candidate.rat = serving.rat
              AND candidate_group.site_group_id
                    <> serving_group.site_group_id
              AND NOT ST_DWithin(
                    serving.site_location,
                    candidate.site_location,
                    50)
              AND ST_DWithin(
                    serving.site_location,
                    candidate.site_location,
                    definition.max_neighbor_distance_meters)
            ORDER BY serving.site_location <-> candidate.site_location,
                     candidate.quality_score DESC,
                     candidate.id
            LIMIT 96
        ) candidate_pool
        ORDER BY candidate_pool.site_group_id,
                 candidate_pool.distance_meters,
                 candidate_pool.quality_score DESC,
                 candidate_pool.id
    ) distinct_site
    ORDER BY distinct_site.distance_meters,
             distinct_site.id
    LIMIT 12
) neighbor
WHERE serving.data_source = 'REALISTIC_COORDINATE_SCENARIO'
  AND serving.active = TRUE;

CREATE INDEX idx_realistic_neighbor_serving_rank
    ON realistic_neighbor_selection(serving_id, rank_no);
ANALYZE realistic_neighbor_selection;

CREATE TEMP TABLE realistic_radius_profile
ON COMMIT DROP
AS
SELECT serving.id AS serving_id,
       CASE
         WHEN COUNT(neighbor.neighbor_id) = 0
         THEN definition.fallback_radius_meters
         ELSE
           GREATEST(
               definition.minimum_radius_meters,
               LEAST(
                   definition.maximum_radius_meters,
                   PERCENTILE_CONT(0.5) WITHIN GROUP (
                       ORDER BY neighbor.distance_meters
                   ) FILTER (WHERE neighbor.rank_no <= 6)
                       * definition.radius_factor
               )
           )
       END AS inferred_radius_meters
FROM dispatch_assist.cell_sector serving
JOIN realistic_scenario_definition definition
  ON definition.operator_code = serving.operator_code
LEFT JOIN realistic_neighbor_selection neighbor
  ON neighbor.serving_id = serving.id
WHERE serving.data_source = 'REALISTIC_COORDINATE_SCENARIO'
  AND serving.active = TRUE
GROUP BY serving.id,
         definition.radius_factor,
         definition.minimum_radius_meters,
         definition.maximum_radius_meters,
         definition.fallback_radius_meters;

UPDATE dispatch_assist.cell_sector sector
SET nominal_radius_meters = profile.inferred_radius_meters,
    coverage_geom = ST_Multi(
        ST_Buffer(
            sector.site_location,
            profile.inferred_radius_meters
        )::geometry
    ),
    updated_at = CURRENT_TIMESTAMP
FROM realistic_radius_profile profile
WHERE sector.id = profile.serving_id;

INSERT INTO dispatch_assist.cell_neighbor_relation (
    serving_sector_id,
    neighbor_sector_id,
    relation_source,
    priority,
    confidence_score,
    derivation_version,
    effective_from,
    active
)
SELECT neighbor.serving_id,
       neighbor.neighbor_id,
       'SPATIAL_DERIVED',
       (100 - neighbor.rank_no)::smallint,
       GREATEST(
           0.05,
           1 - neighbor.distance_meters
               / definition.max_neighbor_distance_meters
       ),
       'realistic-coordinate-scenario-v1',
       '2026-07-30T00:00:00+08:00',
       TRUE
FROM realistic_neighbor_selection neighbor
JOIN dispatch_assist.cell_sector serving
  ON serving.id = neighbor.serving_id
JOIN realistic_scenario_definition definition
  ON definition.operator_code = serving.operator_code;

\if :seed_legacy_address_inventory
WITH scaled_definition AS (
    SELECT definition.*,
           GREATEST(
               1,
               ROUND(
                   definition.base_address_count
                   * :address_scale::numeric
               )::integer
           ) AS target_address_count
    FROM realistic_scenario_definition definition
),
generated AS (
    SELECT definition.*,
           sequence_no,
           CEIL(SQRT(definition.target_address_count::numeric))::integer
               AS grid_width
    FROM scaled_definition definition
    CROSS JOIN LATERAL generate_series(
        1,
        definition.target_address_count
    ) sequence_source(sequence_no)
),
positioned AS (
    SELECT generated.*,
           ((sequence_no - 1) % grid_width)::integer AS grid_column,
           ((sequence_no - 1) / grid_width)::integer AS grid_row,
           CEIL(
               target_address_count::numeric / grid_width
           )::integer AS grid_height
    FROM generated
),
typed AS (
    SELECT positioned.*,
           CASE
             WHEN MOD(sequence_no, 20) IN (0, 1) THEN 'AOI'
             WHEN MOD(sequence_no, 20) IN (2, 3, 4) THEN 'POI'
             WHEN MOD(sequence_no, 20) = 5 THEN 'LOI'
             ELSE 'BUILDING'
           END AS source_type,
           center_longitude
               + (
                   (
                     grid_column::double precision
                     / GREATEST(1, grid_width - 1)
                     - 0.5
                   )
                   * 2 * address_spread_x_meters
                 )
                 / (
                     111320.0
                     * COS(RADIANS(center_latitude))
                   ) AS longitude,
           center_latitude
               + (
                   (
                     grid_row::double precision
                     / GREATEST(1, grid_height - 1)
                     - 0.5
                   )
                   * 2 * address_spread_y_meters
                 ) / 111320.0 AS latitude
    FROM positioned
)
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
SELECT 'REALISTIC_SCENARIO',
       source_type,
       scenario_code || '-' || source_type || '-' || sequence_no,
       'REALISTIC_LEGACY_V1',
       scenario_code || '-' || source_type || '-' || sequence_no,
       scenario_code || '-S-' || sequence_no,
       scenario_code || ' scenario road '
           || (MOD(sequence_no, 80) + 1)
           || ' number ' || sequence_no,
       jsonb_build_array(
           scenario_code || '-alias-' || MOD(sequence_no, 200)
       ),
       scenario_code || '-AOI-' || (MOD(sequence_no, 200) + 1),
       scenario_code || '-aoi-' || (MOD(sequence_no, 200) + 1),
       scenario_code || '-road-' || (MOD(sequence_no, 80) + 1),
       CASE
         WHEN source_type IN ('POI', 'LOI')
         THEN ST_SetSRID(
                ST_MakePoint(longitude, latitude),
                4326)
         ELSE ST_Multi(
                ST_MakeEnvelope(
                    longitude
                        - 12.0
                          / (
                              111320.0
                              * COS(RADIANS(latitude))
                            ),
                    latitude - 12.0 / 111320.0,
                    longitude
                        + 12.0
                          / (
                              111320.0
                              * COS(RADIANS(latitude))
                            ),
                    latitude + 12.0 / 111320.0,
                    4326))
       END,
       ST_SetSRID(
           ST_MakePoint(longitude, latitude),
           4326),
       CURRENT_TIMESTAMP,
       TRUE
FROM typed
WHERE NOT EXISTS (
    SELECT 1
    FROM dispatch_assist.address_inventory existing_inventory
    WHERE existing_inventory.source_system = 'REALISTIC_SCENARIO'
      AND existing_inventory.data_version = 'REALISTIC_LEGACY_V1'
    LIMIT 1
)
ON CONFLICT (
    source_system,
    source_type,
    source_id
) WHERE active = TRUE
DO NOTHING;

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
           'g'),
       term_source.term_type,
       term_source.weight
FROM dispatch_assist.address_inventory inventory
CROSS JOIN LATERAL (
    VALUES
        (inventory.standard_name, 'STANDARD', 100),
        (inventory.short_name, 'SHORT', 95),
        (inventory.full_address, 'FULL_ADDRESS', 90),
        (inventory.aoi_name, 'AOI', 80),
        (inventory.road_name, 'ROAD', 80)
) term_source(term, term_type, weight)
WHERE inventory.source_system = 'REALISTIC_SCENARIO'
  AND term_source.term IS NOT NULL
  AND btrim(term_source.term) <> ''
  AND NOT EXISTS (
      SELECT 1
      FROM dispatch_assist.address_inventory_term existing_term
      JOIN dispatch_assist.address_inventory existing_inventory
        ON existing_inventory.id = existing_term.inventory_id
      WHERE existing_inventory.source_system = 'REALISTIC_SCENARIO'
        AND existing_inventory.data_version = 'REALISTIC_LEGACY_V1'
      LIMIT 1
  )
ON CONFLICT DO NOTHING;
\endif

INSERT INTO dispatch_assist.demo_location_scenario (
    scenario_code,
    display_name,
    data_version,
    environment_type,
    layout_type,
    anchor_longitude,
    anchor_latitude,
    physical_site_count,
    active_sector_count,
    address_count,
    address_spread_x_meters,
    address_spread_y_meters,
    expected_neighbor_count,
    expected_neighbor_source,
    expected_warning,
    notes,
    updated_at
)
SELECT definition.scenario_code,
       definition.display_name,
       'REALISTIC_AI_SOURCE_V1',
       definition.environment_type,
       definition.layout_type,
       definition.center_longitude,
       definition.center_latitude,
       definition.grid_rows * definition.grid_columns,
       COUNT(DISTINCT sector.id)::integer,
       GREATEST(
           1,
           ROUND(
               definition.base_address_count
               * :address_scale::numeric
           )::integer
       ),
       definition.address_spread_x_meters,
       definition.address_spread_y_meters,
       definition.expected_neighbor_count,
       definition.expected_neighbor_source,
       definition.expected_warning,
       'Coordinate anchor tolerance is 50 m; coverage radius is derived '
           || 'from neighbor spacing and is not the anchor tolerance.',
       CURRENT_TIMESTAMP
FROM realistic_scenario_definition definition
JOIN dispatch_assist.cell_sector sector
  ON sector.operator_code = definition.operator_code
 AND sector.data_source = 'REALISTIC_COORDINATE_SCENARIO'
 AND sector.active = TRUE
GROUP BY definition.scenario_code,
         definition.display_name,
         definition.environment_type,
         definition.layout_type,
         definition.center_longitude,
         definition.center_latitude,
         definition.grid_rows,
         definition.grid_columns,
         definition.base_address_count,
         definition.address_spread_x_meters,
         definition.address_spread_y_meters,
         definition.expected_neighbor_count,
         definition.expected_neighbor_source,
         definition.expected_warning
ON CONFLICT (scenario_code) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    data_version = EXCLUDED.data_version,
    environment_type = EXCLUDED.environment_type,
    layout_type = EXCLUDED.layout_type,
    anchor_longitude = EXCLUDED.anchor_longitude,
    anchor_latitude = EXCLUDED.anchor_latitude,
    physical_site_count = EXCLUDED.physical_site_count,
    active_sector_count = EXCLUDED.active_sector_count,
    address_count = EXCLUDED.address_count,
    address_spread_x_meters = EXCLUDED.address_spread_x_meters,
    address_spread_y_meters = EXCLUDED.address_spread_y_meters,
    expected_neighbor_count = EXCLUDED.expected_neighbor_count,
    expected_neighbor_source = EXCLUDED.expected_neighbor_source,
    expected_warning = EXCLUDED.expected_warning,
    notes = EXCLUDED.notes,
    updated_at = CURRENT_TIMESTAMP;

ANALYZE dispatch_assist.cell_sector;
ANALYZE dispatch_assist.cell_neighbor_relation;
ANALYZE dispatch_assist.address_inventory;
ANALYZE dispatch_assist.address_inventory_term;

COMMIT;

SELECT scenario.scenario_code,
       scenario.environment_type,
       scenario.layout_type,
       scenario.physical_site_count,
       scenario.active_sector_count,
       scenario.address_count,
       scenario.expected_neighbor_count,
       ROUND(MIN(sector.nominal_radius_meters), 1) AS minimum_radius_meters,
       ROUND(AVG(sector.nominal_radius_meters), 1) AS average_radius_meters,
       ROUND(MAX(sector.nominal_radius_meters), 1) AS maximum_radius_meters
FROM dispatch_assist.demo_location_scenario scenario
JOIN dispatch_assist.cell_sector sector
  ON sector.operator_code = (
       SELECT operator_code
       FROM (
           VALUES
             ('DENSE_URBAN', 'SIM_DENSE'),
             ('URBAN', 'SIM_URBAN'),
             ('SUBURBAN', 'SIM_SUBURBAN'),
             ('RURAL', 'SIM_RURAL'),
             ('TRANSPORT_CORRIDOR', 'SIM_CORRIDOR'),
             ('COLOCATED_MIXED_RAT', 'SIM_MIXED'),
             ('LIBRARY_EDGE', 'SIM_EDGE'),
             ('ISOLATED_SITE', 'SIM_ISOLATED')
       ) mapping(scenario_code, operator_code)
       WHERE mapping.scenario_code = scenario.scenario_code
     )
 AND sector.data_source = 'REALISTIC_COORDINATE_SCENARIO'
 AND sector.active = TRUE
GROUP BY scenario.scenario_code,
         scenario.environment_type,
         scenario.layout_type,
         scenario.physical_site_count,
         scenario.active_sector_count,
         scenario.address_count,
         scenario.expected_neighbor_count
ORDER BY scenario.scenario_code;

\if :seed_legacy_address_inventory
SELECT source_type,
       COUNT(*) AS address_count
FROM dispatch_assist.address_inventory
WHERE source_system = 'REALISTIC_SCENARIO'
GROUP BY source_type
ORDER BY source_type;
\endif

SELECT COUNT(*) FILTER (WHERE active = TRUE) AS active_rows,
       COUNT(*) FILTER (WHERE active = FALSE) AS inactive_stale_rows,
       COUNT(*) AS total_rows
FROM dispatch_assist.cell_sector
WHERE data_source = 'REALISTIC_COORDINATE_SCENARIO';
