-- Versioned global address read model and per-location address-subset snapshots.
-- AOI/POI/LOI importers write to address_inventory using the same contract.

CREATE TABLE IF NOT EXISTS dispatch_assist.address_inventory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_system VARCHAR(64) NOT NULL,
    source_type VARCHAR(16) NOT NULL,
    source_id VARCHAR(128) NOT NULL,
    data_version VARCHAR(64) NOT NULL,
    standard_name VARCHAR(512) NOT NULL,
    short_name VARCHAR(512),
    full_address VARCHAR(1024),
    aliases JSONB NOT NULL DEFAULT '[]'::jsonb,
    parent_aoi_id VARCHAR(128),
    aoi_name VARCHAR(512),
    road_name VARCHAR(512),
    geom GEOMETRY(GEOMETRY, 4326) NOT NULL,
    representative_point GEOMETRY(POINT, 4326) NOT NULL,
    source_updated_at TIMESTAMP,
    synced_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_address_inventory_source_type CHECK (
        source_type IN ('BUILDING', 'AOI', 'POI', 'LOI')
    ),
    CONSTRAINT ck_address_inventory_aliases_array CHECK (
        jsonb_typeof(aliases) = 'array'
    ),
    CONSTRAINT ck_address_inventory_valid_geom CHECK (
        ST_IsValid(geom)
    ),
    CONSTRAINT ck_address_inventory_nonempty_geom CHECK (
        NOT ST_IsEmpty(geom)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS
    uk_address_inventory_active_source
    ON dispatch_assist.address_inventory (
        source_system,
        source_type,
        source_id
    )
    WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS idx_address_inventory_active_geom_gist
    ON dispatch_assist.address_inventory
    USING GIST (geom)
    WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS idx_address_inventory_active_version_type
    ON dispatch_assist.address_inventory (
        data_version,
        source_type,
        source_id
    )
    WHERE active = TRUE;

CREATE TABLE IF NOT EXISTS dispatch_assist.address_subset (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_resolution_id UUID NOT NULL
        REFERENCES dispatch_assist.location_resolution(id),
    location_resolution_version BIGINT NOT NULL,
    inventory_version VARCHAR(64) NOT NULL,
    status VARCHAR(16) NOT NULL,
    item_count BIGINT NOT NULL DEFAULT 0,
    term_count BIGINT NOT NULL DEFAULT 0,
    building_count BIGINT NOT NULL DEFAULT 0,
    aoi_count BIGINT NOT NULL DEFAULT 0,
    poi_count BIGINT NOT NULL DEFAULT 0,
    loi_count BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    error_message VARCHAR(1024),
    CONSTRAINT ck_address_subset_status CHECK (
        status IN ('BUILDING', 'READY', 'FAILED')
    ),
    CONSTRAINT ck_address_subset_counts CHECK (
        item_count >= 0
        AND term_count >= 0
        AND building_count >= 0
        AND aoi_count >= 0
        AND poi_count >= 0
        AND loi_count >= 0
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS uk_address_subset_active_version
    ON dispatch_assist.address_subset (
        location_resolution_id,
        location_resolution_version,
        inventory_version
    )
    WHERE status IN ('BUILDING', 'READY');

CREATE INDEX IF NOT EXISTS idx_address_subset_expiry
    ON dispatch_assist.address_subset (expires_at)
    WHERE status = 'READY';

CREATE TABLE IF NOT EXISTS dispatch_assist.address_subset_item (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subset_id UUID NOT NULL
        REFERENCES dispatch_assist.address_subset(id)
        ON DELETE CASCADE,
    inventory_id UUID NOT NULL
        REFERENCES dispatch_assist.address_inventory(id),
    source_type VARCHAR(16) NOT NULL,
    source_id VARCHAR(128) NOT NULL,
    standard_name VARCHAR(512) NOT NULL,
    short_name VARCHAR(512),
    full_address VARCHAR(1024),
    aliases JSONB NOT NULL,
    parent_aoi_id VARCHAR(128),
    aoi_name VARCHAR(512),
    road_name VARCHAR(512),
    hit_level VARCHAR(16) NOT NULL,
    sort_distance DOUBLE PRECISION NOT NULL,
    distance_meters NUMERIC(14,3) NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    rank_no BIGINT NOT NULL,
    CONSTRAINT ck_address_subset_item_hit_level CHECK (
        hit_level IN ('HARD_AREA', 'SEARCH_AREA')
    ),
    CONSTRAINT ck_address_subset_item_distance CHECK (
        distance_meters >= 0
    ),
    CONSTRAINT ck_address_subset_item_rank CHECK (
        rank_no > 0
    ),
    CONSTRAINT uk_address_subset_item_source UNIQUE (
        subset_id,
        source_type,
        source_id
    ),
    CONSTRAINT uk_address_subset_item_rank UNIQUE (
        subset_id,
        rank_no
    )
);

CREATE INDEX IF NOT EXISTS idx_address_subset_item_type
    ON dispatch_assist.address_subset_item (
        subset_id,
        source_type,
        rank_no
    );

-- Make existing building data immediately usable by the Demo. Production
-- AOI/POI/LOI data is synchronized by a separate, coordinate-validated job.
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
    geom,
    representative_point,
    source_updated_at,
    active
)
SELECT building.source_system,
       'BUILDING',
       building.source_building_id,
       building.data_version,
       building.building_name,
       building.short_name,
       building.address_name,
       '[]'::jsonb,
       building.source_aoi_id,
       building.aoi_name,
       building.geom,
       building.representative_point,
       building.source_updated_at,
       building.active
FROM dispatch_assist.building_inventory building
WHERE building.active = TRUE
ON CONFLICT DO NOTHING;
