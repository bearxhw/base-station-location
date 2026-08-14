-- Local read model for querying all buildings covered by a cell-location area.
-- Source AOI/POI/LOI tables remain read-only and are synchronized separately.

CREATE TABLE IF NOT EXISTS dispatch_assist.building_inventory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_system VARCHAR(64) NOT NULL,
    source_building_id VARCHAR(128) NOT NULL,
    data_version VARCHAR(64) NOT NULL,
    building_name VARCHAR(512) NOT NULL,
    short_name VARCHAR(512),
    address_name VARCHAR(1024),
    area_code VARCHAR(32),
    source_aoi_id VARCHAR(128),
    aoi_name VARCHAR(512),
    geom GEOMETRY(MULTIPOLYGON, 4326) NOT NULL,
    representative_point GEOMETRY(POINT, 4326) NOT NULL,
    above_ground_floors INTEGER,
    underground_floors INTEGER,
    height_meters NUMERIC(12,3),
    building_area_square_meters NUMERIC(16,3),
    building_usage_code VARCHAR(64),
    building_type_code VARCHAR(64),
    fire_rescue_access VARCHAR(1024),
    sensitive_target TEXT,
    source_updated_at TIMESTAMP,
    synced_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_building_inventory_valid_geom CHECK (ST_IsValid(geom)),
    CONSTRAINT ck_building_inventory_nonempty_geom CHECK (NOT ST_IsEmpty(geom))
);

CREATE UNIQUE INDEX IF NOT EXISTS
    uk_building_inventory_active_source_id
    ON dispatch_assist.building_inventory (
        source_system,
        source_building_id
    )
    WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS idx_building_inventory_active_geom_gist
    ON dispatch_assist.building_inventory
    USING GIST (geom)
    WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS idx_building_inventory_active_version
    ON dispatch_assist.building_inventory (
        data_version,
        source_building_id
    )
    WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS idx_building_inventory_active_aoi
    ON dispatch_assist.building_inventory (source_aoi_id)
    WHERE active = TRUE;

CREATE TABLE IF NOT EXISTS dispatch_assist.building_inventory_reject (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_system VARCHAR(64) NOT NULL,
    source_building_id VARCHAR(128),
    data_version VARCHAR(64) NOT NULL,
    reject_code VARCHAR(64) NOT NULL,
    reject_reason VARCHAR(1024) NOT NULL,
    source_payload JSONB NOT NULL,
    rejected_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_building_inventory_reject_version_code
    ON dispatch_assist.building_inventory_reject (
        data_version,
        reject_code
    );

CREATE TABLE IF NOT EXISTS dispatch_assist.building_search_run (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_resolution_id UUID NOT NULL
        REFERENCES dispatch_assist.location_resolution(id),
    location_resolution_version BIGINT NOT NULL,
    inventory_version VARCHAR(64) NOT NULL,
    hard_area GEOMETRY(POLYGON, 4326) NOT NULL,
    search_area GEOMETRY(POLYGON, 4326) NOT NULL,
    result_count INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    CONSTRAINT ck_building_search_run_status CHECK (
        status IN ('RUNNING', 'COMPLETED', 'FAILED')
    ),
    CONSTRAINT ck_building_search_run_result_count CHECK (
        result_count >= 0
    )
);

CREATE INDEX IF NOT EXISTS idx_building_search_run_resolution
    ON dispatch_assist.building_search_run (
        location_resolution_id,
        location_resolution_version,
        created_at DESC
    );

CREATE TABLE IF NOT EXISTS dispatch_assist.building_search_result (
    search_run_id UUID NOT NULL
        REFERENCES dispatch_assist.building_search_run(id)
        ON DELETE CASCADE,
    building_id UUID NOT NULL
        REFERENCES dispatch_assist.building_inventory(id),
    hit_level VARCHAR(16) NOT NULL,
    distance_meters NUMERIC(12,3) NOT NULL,
    rank_no INTEGER NOT NULL,
    PRIMARY KEY (search_run_id, building_id),
    CONSTRAINT ck_building_search_result_hit_level CHECK (
        hit_level IN ('HARD_AREA', 'SEARCH_AREA')
    ),
    CONSTRAINT ck_building_search_result_distance CHECK (
        distance_meters >= 0
    ),
    CONSTRAINT ck_building_search_result_rank CHECK (
        rank_no > 0
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS uk_building_search_result_rank
    ON dispatch_assist.building_search_result (search_run_id, rank_no);

