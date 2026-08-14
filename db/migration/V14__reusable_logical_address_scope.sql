-- Reusable, non-materialized logical address sub-library.
-- One row freezes the location polygon and inventory version for one call;
-- no address membership rows are copied.

CREATE TABLE IF NOT EXISTS dispatch_assist.logical_address_scope (
    scope_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_resolution_id UUID NOT NULL
        REFERENCES dispatch_assist.location_resolution(id),
    location_resolution_version INTEGER NOT NULL,
    inventory_version VARCHAR(64) NOT NULL,
    hard_area GEOGRAPHY(MULTIPOLYGON, 4326) NOT NULL,
    search_area GEOGRAPHY(MULTIPOLYGON, 4326) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ,
    CONSTRAINT uk_logical_address_scope_source UNIQUE (
        location_resolution_id,
        location_resolution_version,
        inventory_version
    ),
    CONSTRAINT ck_logical_address_scope_version CHECK (
        location_resolution_version > 0
    ),
    CONSTRAINT ck_logical_address_scope_status CHECK (
        status IN ('ACTIVE', 'EXPIRED')
    ),
    CONSTRAINT ck_logical_address_scope_area CHECK (
        NOT ST_IsEmpty(hard_area::geometry)
        AND NOT ST_IsEmpty(search_area::geometry)
        AND ST_IsValid(hard_area::geometry)
        AND ST_IsValid(search_area::geometry)
    )
);

CREATE INDEX IF NOT EXISTS idx_logical_address_scope_inventory_active
    ON dispatch_assist.logical_address_scope (
        inventory_version,
        scope_id
    )
    WHERE status = 'ACTIVE';

CREATE INDEX IF NOT EXISTS idx_logical_address_scope_expiry
    ON dispatch_assist.logical_address_scope (expires_at)
    WHERE status = 'ACTIVE' AND expires_at IS NOT NULL;

-- Required by the address_subset_item -> address_inventory foreign key.
-- Without an inventory_id-leading index, retiring one inventory version
-- repeatedly scans the whole subset table for every deleted address row.
CREATE INDEX IF NOT EXISTS idx_address_subset_item_inventory_fk
    ON dispatch_assist.address_subset_item (inventory_id);

CREATE OR REPLACE VIEW dispatch_assist.logical_address_scope_item AS
SELECT scope.scope_id,
       scope.location_resolution_id,
       scope.location_resolution_version,
       scope.inventory_version,
       inventory.id AS inventory_id,
       inventory.source_type,
       inventory.source_id,
       inventory.standard_name,
       inventory.short_name,
       inventory.full_address,
       inventory.aliases,
       inventory.parent_aoi_id,
       inventory.aoi_name,
       inventory.road_name,
       CASE
         WHEN inventory.geom && scope.hard_area::geometry
          AND ST_Intersects(
                  inventory.geom,
                  scope.hard_area::geometry)
         THEN 'HARD_AREA'
         ELSE 'SEARCH_AREA'
       END AS hit_level,
       ST_X(inventory.representative_point) AS longitude,
       ST_Y(inventory.representative_point) AS latitude,
       inventory.source_system,
       CASE
         WHEN POSITION(':' IN inventory.source_id) > 0
         THEN split_part(inventory.source_id, ':', 1)
         ELSE inventory.source_system
       END AS source_table,
       CASE
         WHEN POSITION(':' IN inventory.source_id) > 0
         THEN split_part(inventory.source_id, ':', 2)
         ELSE inventory.source_id
       END AS source_record_id
FROM dispatch_assist.logical_address_scope scope
JOIN dispatch_assist.address_inventory inventory
  ON inventory.active = TRUE
 AND inventory.data_version = scope.inventory_version
 AND inventory.geom && scope.search_area::geometry
 AND ST_Intersects(
       inventory.geom,
       scope.search_area::geometry)
WHERE scope.status = 'ACTIVE'
  AND (scope.expires_at IS NULL OR scope.expires_at > CURRENT_TIMESTAMP);

COMMENT ON TABLE dispatch_assist.logical_address_scope IS
    'Immutable range handle for downstream address queries; stores polygons and version only, never address copies.';
COMMENT ON VIEW dispatch_assist.logical_address_scope_item IS
    'Directly queryable logical sub-library; callers must filter by scope_id so PostgreSQL can use the address GIST index.';
