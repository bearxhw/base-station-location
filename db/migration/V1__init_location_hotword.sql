-- 消防接处警定位与动态热词核心模型
-- 生产环境建议由 DBA 预装扩展；迁移账号执行本脚本。

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS dispatch_assist;

CREATE TABLE IF NOT EXISTS dispatch_assist.standard_address (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    address_code VARCHAR(64) NOT NULL,
    full_address VARCHAR(512) NOT NULL,
    normalized_address VARCHAR(512) NOT NULL,
    admin_division_code VARCHAR(32),
    province_name VARCHAR(64),
    city_name VARCHAR(64),
    district_name VARCHAR(64),
    street_name VARCHAR(128),
    road_name VARCHAR(128),
    road_no VARCHAR(64),
    poi_name VARCHAR(256),
    building_name VARCHAR(128),
    search_pinyin VARCHAR(1024),
    search_initials VARCHAR(256),
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    data_source VARCHAR(64) NOT NULL,
    quality_score NUMERIC(5,4) NOT NULL DEFAULT 1.0,
    source_updated_at TIMESTAMPTZ,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_standard_address_code UNIQUE (address_code),
    CONSTRAINT ck_standard_address_quality
        CHECK (quality_score >= 0 AND quality_score <= 1),
    CONSTRAINT ck_standard_address_version CHECK (version > 0)
);

CREATE INDEX IF NOT EXISTS idx_standard_address_normalized_trgm
    ON dispatch_assist.standard_address
    USING GIN (normalized_address gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_standard_address_pinyin_trgm
    ON dispatch_assist.standard_address
    USING GIN (search_pinyin gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_standard_address_location_gist
    ON dispatch_assist.standard_address
    USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_standard_address_admin_active
    ON dispatch_assist.standard_address (admin_division_code, active);

CREATE TABLE IF NOT EXISTS dispatch_assist.address_alias (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    standard_address_id UUID NOT NULL
        REFERENCES dispatch_assist.standard_address(id),
    alias VARCHAR(512) NOT NULL,
    normalized_alias VARCHAR(512) NOT NULL,
    alias_type VARCHAR(32) NOT NULL,
    data_source VARCHAR(64) NOT NULL,
    approved BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_address_alias
        UNIQUE (standard_address_id, normalized_alias),
    CONSTRAINT ck_address_alias_type
        CHECK (alias_type IN ('COMMON', 'OLD_NAME', 'ASR_VARIANT', 'SOCIAL_ADDRESS'))
);

CREATE INDEX IF NOT EXISTS idx_address_alias_normalized_trgm
    ON dispatch_assist.address_alias
    USING GIN (normalized_alias gin_trgm_ops);

CREATE TABLE IF NOT EXISTS dispatch_assist.cell_sector (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    operator_code VARCHAR(32) NOT NULL,
    rat VARCHAR(16) NOT NULL,
    mcc VARCHAR(3) NOT NULL,
    mnc VARCHAR(3) NOT NULL,
    area_code_type VARCHAR(8) NOT NULL,
    area_code VARCHAR(16) NOT NULL,
    cell_id VARCHAR(32) NOT NULL,
    pci INTEGER,
    site_name VARCHAR(256),
    site_location GEOGRAPHY(POINT, 4326) NOT NULL,
    azimuth_degrees NUMERIC(6,2),
    beam_width_degrees NUMERIC(6,2),
    nominal_radius_meters NUMERIC(12,3),
    coverage_geom GEOMETRY(MULTIPOLYGON, 4326),
    environment_type VARCHAR(16),
    data_source VARCHAR(64) NOT NULL,
    quality_score NUMERIC(5,4) NOT NULL DEFAULT 0.5,
    effective_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMPTZ,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_cell_sector_identity_version
        UNIQUE (operator_code, rat, mcc, mnc, area_code, cell_id, version),
    CONSTRAINT ck_cell_sector_rat
        CHECK (rat IN ('GSM', 'WCDMA', 'LTE', 'NR')),
    CONSTRAINT ck_cell_sector_area_code_type
        CHECK (area_code_type IN ('LAC', 'TAC')),
    CONSTRAINT ck_cell_sector_angles
        CHECK ((azimuth_degrees IS NULL OR
                (azimuth_degrees >= 0 AND azimuth_degrees < 360)) AND
               (beam_width_degrees IS NULL OR
                (beam_width_degrees > 0 AND beam_width_degrees <= 360))),
    CONSTRAINT ck_cell_sector_radius
        CHECK (nominal_radius_meters IS NULL OR nominal_radius_meters > 0),
    CONSTRAINT ck_cell_sector_environment
        CHECK (environment_type IS NULL OR
               environment_type IN ('URBAN', 'SUBURBAN', 'RURAL')),
    CONSTRAINT ck_cell_sector_quality
        CHECK (quality_score >= 0 AND quality_score <= 1),
    CONSTRAINT ck_cell_sector_period
        CHECK (effective_to IS NULL OR effective_to > effective_from),
    CONSTRAINT ck_cell_sector_coverage_valid
        CHECK (coverage_geom IS NULL OR ST_IsValid(coverage_geom))
);

CREATE INDEX IF NOT EXISTS idx_cell_sector_lookup
    ON dispatch_assist.cell_sector
    (operator_code, rat, mcc, mnc, area_code, cell_id, active);
CREATE INDEX IF NOT EXISTS idx_cell_sector_site_location_gist
    ON dispatch_assist.cell_sector
    USING GIST (site_location);
CREATE INDEX IF NOT EXISTS idx_cell_sector_coverage_gist
    ON dispatch_assist.cell_sector
    USING GIST (coverage_geom);

CREATE TABLE IF NOT EXISTS dispatch_assist.cell_neighbor_relation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    serving_sector_id UUID NOT NULL
        REFERENCES dispatch_assist.cell_sector(id),
    neighbor_sector_id UUID NOT NULL
        REFERENCES dispatch_assist.cell_sector(id),
    relation_source VARCHAR(32) NOT NULL,
    priority SMALLINT NOT NULL DEFAULT 0,
    confidence_score NUMERIC(5,4) NOT NULL DEFAULT 0.5,
    derivation_version VARCHAR(64),
    effective_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMPTZ,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_cell_neighbor_relation
        UNIQUE (serving_sector_id, neighbor_sector_id, effective_from),
    CONSTRAINT ck_cell_neighbor_not_self
        CHECK (serving_sector_id <> neighbor_sector_id),
    CONSTRAINT ck_cell_neighbor_source
        CHECK (relation_source IN
            ('OPERATOR', 'HANDOVER_STAT', 'MANUAL', 'SPATIAL_DERIVED')),
    CONSTRAINT ck_cell_neighbor_confidence
        CHECK (confidence_score >= 0 AND confidence_score <= 1),
    CONSTRAINT ck_cell_neighbor_period
        CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE INDEX IF NOT EXISTS idx_cell_neighbor_serving_active
    ON dispatch_assist.cell_neighbor_relation
    (serving_sector_id, active, priority DESC);

CREATE TABLE IF NOT EXISTS dispatch_assist.cell_nearby_address_relation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cell_sector_id UUID NOT NULL
        REFERENCES dispatch_assist.cell_sector(id),
    standard_address_id UUID NOT NULL
        REFERENCES dispatch_assist.standard_address(id),
    relation_source VARCHAR(32) NOT NULL,
    distance_meters NUMERIC(12,3),
    rank_no SMALLINT NOT NULL,
    build_version VARCHAR(64) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_cell_nearby_address
        UNIQUE (cell_sector_id, standard_address_id, build_version),
    CONSTRAINT ck_cell_nearby_address_source
        CHECK (relation_source IN
            ('COVERAGE_DIRECT', 'NEIGHBOR_COVERAGE', 'MANUAL')),
    CONSTRAINT ck_cell_nearby_address_distance
        CHECK (distance_meters IS NULL OR distance_meters >= 0),
    CONSTRAINT ck_cell_nearby_address_rank CHECK (rank_no > 0)
);

CREATE INDEX IF NOT EXISTS idx_cell_nearby_address_lookup
    ON dispatch_assist.cell_nearby_address_relation
    (cell_sector_id, active, rank_no);
CREATE INDEX IF NOT EXISTS idx_cell_nearby_address_address
    ON dispatch_assist.cell_nearby_address_relation
    (standard_address_id, active);

CREATE TABLE IF NOT EXISTS dispatch_assist.geo_jurisdiction (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    jurisdiction_code VARCHAR(64) NOT NULL,
    jurisdiction_type VARCHAR(32) NOT NULL,
    name VARCHAR(256) NOT NULL,
    admin_division_code VARCHAR(32),
    station_id VARCHAR(64),
    priority INTEGER NOT NULL DEFAULT 0,
    geom GEOMETRY(MULTIPOLYGON, 4326) NOT NULL,
    effective_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMPTZ,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_geo_jurisdiction_code_version
        UNIQUE (jurisdiction_code, version),
    CONSTRAINT ck_geo_jurisdiction_type
        CHECK (jurisdiction_type IN ('ADMIN', 'FIRE_STATION', 'KEY_AREA')),
    CONSTRAINT ck_geo_jurisdiction_period
        CHECK (effective_to IS NULL OR effective_to > effective_from),
    CONSTRAINT ck_geo_jurisdiction_geom_valid CHECK (ST_IsValid(geom))
);

CREATE INDEX IF NOT EXISTS idx_geo_jurisdiction_geom_gist
    ON dispatch_assist.geo_jurisdiction
    USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_geo_jurisdiction_active_type_priority
    ON dispatch_assist.geo_jurisdiction
    (active, jurisdiction_type, priority DESC);

CREATE TABLE IF NOT EXISTS dispatch_assist.geo_resource (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_id VARCHAR(64) NOT NULL,
    resource_type VARCHAR(32) NOT NULL,
    name VARCHAR(256) NOT NULL,
    admin_division_code VARCHAR(32),
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    source_updated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_geo_resource UNIQUE (resource_type, resource_id),
    CONSTRAINT ck_geo_resource_type
        CHECK (resource_type IN
            ('FIRE_STATION', 'HYDRANT', 'NATURAL_WATER', 'MICRO_STATION',
             'KEY_UNIT', 'PROFESSIONAL_TEAM'))
);

CREATE INDEX IF NOT EXISTS idx_geo_resource_location_gist
    ON dispatch_assist.geo_resource
    USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_geo_resource_type_active
    ON dispatch_assist.geo_resource (resource_type, active);

CREATE TABLE IF NOT EXISTS dispatch_assist.location_resolution (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id VARCHAR(64) NOT NULL,
    alarm_id VARCHAR(64),
    status VARCHAR(32) NOT NULL,
    decision_reason VARCHAR(64),
    model_version VARCHAR(64) NOT NULL,
    final_standard_address_id UUID
        REFERENCES dispatch_assist.standard_address(id),
    final_display_address VARCHAR(512),
    final_location GEOGRAPHY(POINT, 4326),
    admin_division_code VARCHAR(32),
    fire_jurisdiction_id UUID
        REFERENCES dispatch_assist.geo_jurisdiction(id),
    primary_station_id VARCHAR(64),
    confirmed_by VARCHAR(16),
    confirmed_at TIMESTAMPTZ,
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_location_resolution_session UNIQUE (session_id),
    CONSTRAINT ck_location_resolution_status
        CHECK (status IN
            ('RESOLVING', 'NEEDS_CONFIRMATION', 'AUTO_CONFIRMED',
             'MANUAL_CONFIRMED', 'UNRESOLVED')),
    CONSTRAINT ck_location_resolution_confirmed_by
        CHECK (confirmed_by IS NULL OR confirmed_by IN ('AUTO', 'OPERATOR')),
    CONSTRAINT ck_location_resolution_version CHECK (version > 0)
);

CREATE INDEX IF NOT EXISTS idx_location_resolution_alarm
    ON dispatch_assist.location_resolution (alarm_id);
CREATE INDEX IF NOT EXISTS idx_location_resolution_status_updated
    ON dispatch_assist.location_resolution (status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_location_resolution_final_location_gist
    ON dispatch_assist.location_resolution
    USING GIST (final_location);

CREATE TABLE IF NOT EXISTS dispatch_assist.location_evidence (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resolution_id UUID NOT NULL
        REFERENCES dispatch_assist.location_resolution(id),
    request_id VARCHAR(128) NOT NULL,
    source_type VARCHAR(32) NOT NULL,
    source_event_time TIMESTAMPTZ NOT NULL,
    raw_address VARCHAR(1024),
    unit_name VARCHAR(256),
    raw_longitude NUMERIC(10,7),
    raw_latitude NUMERIC(10,7),
    raw_coordinate_system VARCHAR(16),
    normalized_location GEOGRAPHY(POINT, 4326),
    coordinate_transform_version VARCHAR(64),
    provider_code VARCHAR(64),
    provider_request_id VARCHAR(256),
    provider_result_type VARCHAR(32),
    positioning_method VARCHAR(32),
    estimated_area GEOMETRY(MULTIPOLYGON, 4326),
    estimated_area_source VARCHAR(32),
    area_reliability NUMERIC(5,4),
    accuracy_meters NUMERIC(12,3),
    source_confidence NUMERIC(5,4),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_location_evidence_request_source
        UNIQUE (request_id, source_type),
    CONSTRAINT ck_location_evidence_source
        CHECK (source_type IN ('TELCO', 'INTERNET', 'IOT', 'ASR', 'OPERATOR')),
    CONSTRAINT ck_location_evidence_coordinate_system
        CHECK (raw_coordinate_system IS NULL OR
               raw_coordinate_system IN ('WGS84', 'GCJ02', 'BD09', 'CGCS2000')),
    CONSTRAINT ck_location_evidence_positioning_method
        CHECK (positioning_method IS NULL OR positioning_method IN
            ('PROVIDER_POINT', 'CELL_ID', 'E_CID', 'CELL_NEIGHBOR_FUSION',
             'INTERNET', 'IOT', 'OPERATOR_PICK')),
    CONSTRAINT ck_location_evidence_provider_result_type
        CHECK (provider_result_type IS NULL OR provider_result_type IN
            ('USER_ESTIMATE', 'CELL_COVERAGE', 'CELL_SITE_ONLY',
             'UNAVAILABLE')),
    CONSTRAINT ck_location_evidence_area_source
        CHECK (estimated_area_source IS NULL OR estimated_area_source IN
            ('PROVIDER', 'SERVING_SECTOR', 'SERVING_AND_NEIGHBORS',
             'DEFAULT_COVERAGE')),
    CONSTRAINT ck_location_evidence_area_reliability
        CHECK (area_reliability IS NULL OR
               (area_reliability >= 0 AND area_reliability <= 1)),
    CONSTRAINT ck_location_evidence_area_valid
        CHECK (estimated_area IS NULL OR ST_IsValid(estimated_area)),
    CONSTRAINT ck_location_evidence_longitude
        CHECK (raw_longitude IS NULL OR
               (raw_longitude >= -180 AND raw_longitude <= 180)),
    CONSTRAINT ck_location_evidence_latitude
        CHECK (raw_latitude IS NULL OR
               (raw_latitude >= -90 AND raw_latitude <= 90)),
    CONSTRAINT ck_location_evidence_accuracy
        CHECK (accuracy_meters IS NULL OR accuracy_meters >= 0),
    CONSTRAINT ck_location_evidence_confidence
        CHECK (source_confidence IS NULL OR
               (source_confidence >= 0 AND source_confidence <= 1)),
    CONSTRAINT ck_location_evidence_content
        CHECK (raw_address IS NOT NULL OR unit_name IS NOT NULL OR
               normalized_location IS NOT NULL OR
               estimated_area IS NOT NULL OR
               provider_result_type = 'UNAVAILABLE' OR
               (raw_longitude IS NOT NULL AND raw_latitude IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_location_evidence_resolution_time
    ON dispatch_assist.location_evidence
    (resolution_id, source_event_time DESC);
CREATE INDEX IF NOT EXISTS idx_location_evidence_location_gist
    ON dispatch_assist.location_evidence
    USING GIST (normalized_location);
CREATE INDEX IF NOT EXISTS idx_location_evidence_area_gist
    ON dispatch_assist.location_evidence
    USING GIST (estimated_area);
CREATE INDEX IF NOT EXISTS idx_location_evidence_metadata_gin
    ON dispatch_assist.location_evidence
    USING GIN (metadata);

CREATE TABLE IF NOT EXISTS dispatch_assist.location_cell_observation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    evidence_id UUID NOT NULL
        REFERENCES dispatch_assist.location_evidence(id),
    resolved_sector_id UUID
        REFERENCES dispatch_assist.cell_sector(id),
    relation_type VARCHAR(16) NOT NULL,
    operator_code VARCHAR(32) NOT NULL,
    rat VARCHAR(16) NOT NULL,
    mcc VARCHAR(3) NOT NULL,
    mnc VARCHAR(3) NOT NULL,
    area_code_type VARCHAR(8),
    area_code VARCHAR(16),
    cell_id VARCHAR(32) NOT NULL,
    pci INTEGER,
    rsrp_dbm NUMERIC(7,2),
    rsrq_db NUMERIC(7,2),
    rssi_dbm NUMERIC(7,2),
    timing_advance INTEGER,
    angle_of_arrival NUMERIC(7,2),
    observed_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_location_cell_relation
        CHECK (relation_type IN ('SERVING', 'NEIGHBOR')),
    CONSTRAINT ck_location_cell_rat
        CHECK (rat IN ('GSM', 'WCDMA', 'LTE', 'NR')),
    CONSTRAINT ck_location_cell_area_code_type
        CHECK (area_code_type IS NULL OR area_code_type IN ('LAC', 'TAC')),
    CONSTRAINT ck_location_cell_aoa
        CHECK (angle_of_arrival IS NULL OR
               (angle_of_arrival >= 0 AND angle_of_arrival < 360))
);

CREATE INDEX IF NOT EXISTS idx_location_cell_evidence_relation
    ON dispatch_assist.location_cell_observation
    (evidence_id, relation_type);
CREATE INDEX IF NOT EXISTS idx_location_cell_identity
    ON dispatch_assist.location_cell_observation
    (operator_code, rat, mcc, mnc, area_code, cell_id, observed_at DESC);

CREATE TABLE IF NOT EXISTS dispatch_assist.location_candidate (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resolution_id UUID NOT NULL
        REFERENCES dispatch_assist.location_resolution(id),
    resolution_version INTEGER NOT NULL,
    candidate_source VARCHAR(32) NOT NULL,
    source_ref_id VARCHAR(128),
    standard_address_id UUID
        REFERENCES dispatch_assist.standard_address(id),
    display_address VARCHAR(512) NOT NULL,
    candidate_location GEOGRAPHY(POINT, 4326) NOT NULL,
    admin_division_code VARCHAR(32),
    fire_jurisdiction_id UUID
        REFERENCES dispatch_assist.geo_jurisdiction(id),
    primary_station_id VARCHAR(64),
    text_score NUMERIC(5,4),
    coordinate_score NUMERIC(5,4),
    spatial_area_score NUMERIC(5,4),
    radio_measurement_score NUMERIC(5,4),
    source_score NUMERIC(5,4),
    total_score NUMERIC(5,4) NOT NULL,
    score_detail JSONB NOT NULL DEFAULT '{}'::jsonb,
    rank_no SMALLINT NOT NULL,
    model_version VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_location_candidate_rank
        UNIQUE (resolution_id, resolution_version, rank_no),
    CONSTRAINT ck_location_candidate_source
        CHECK (candidate_source IN
            ('STANDARD_ADDRESS', 'ADDRESS_ALIAS', 'POI', 'ROAD',
             'GEO_RESOURCE', 'EXTERNAL_GEOCODER')),
    CONSTRAINT ck_location_candidate_score
        CHECK (total_score >= 0 AND total_score <= 1),
    CONSTRAINT ck_location_candidate_rank CHECK (rank_no > 0)
);

CREATE INDEX IF NOT EXISTS idx_location_candidate_resolution_score
    ON dispatch_assist.location_candidate
    (resolution_id, resolution_version, total_score DESC);
CREATE INDEX IF NOT EXISTS idx_location_candidate_location_gist
    ON dispatch_assist.location_candidate
    USING GIST (candidate_location);

CREATE TABLE IF NOT EXISTS dispatch_assist.location_confirmation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resolution_id UUID NOT NULL
        REFERENCES dispatch_assist.location_resolution(id),
    request_id VARCHAR(128) NOT NULL,
    resolution_version INTEGER NOT NULL,
    confirmation_type VARCHAR(32) NOT NULL,
    candidate_id UUID
        REFERENCES dispatch_assist.location_candidate(id),
    manual_location GEOGRAPHY(POINT, 4326),
    manual_address VARCHAR(512),
    operator_id VARCHAR(64) NOT NULL,
    reason VARCHAR(512) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_location_confirmation_request UNIQUE (request_id),
    CONSTRAINT ck_location_confirmation_type
        CHECK (confirmation_type IN
            ('CANDIDATE_SELECTED', 'MAP_PICKED', 'ADDRESS_CORRECTED')),
    CONSTRAINT ck_location_confirmation_payload CHECK (
        (confirmation_type = 'CANDIDATE_SELECTED' AND candidate_id IS NOT NULL) OR
        (confirmation_type = 'MAP_PICKED' AND manual_location IS NOT NULL) OR
        (confirmation_type = 'ADDRESS_CORRECTED' AND manual_address IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_location_confirmation_resolution
    ON dispatch_assist.location_confirmation (resolution_id, created_at DESC);

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_manual_entry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scope_type VARCHAR(32) NOT NULL,
    scope_id VARCHAR(64) NOT NULL,
    word VARCHAR(128) NOT NULL,
    normalized_word VARCHAR(128) NOT NULL,
    category VARCHAR(32) NOT NULL,
    base_priority INTEGER NOT NULL DEFAULT 100,
    status VARCHAR(16) NOT NULL DEFAULT 'DRAFT',
    reason VARCHAR(512) NOT NULL,
    created_by VARCHAR(64) NOT NULL,
    approved_by VARCHAR(64),
    approved_at TIMESTAMPTZ,
    effective_from TIMESTAMPTZ,
    effective_to TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_hotword_manual_entry
        UNIQUE (scope_type, scope_id, normalized_word),
    CONSTRAINT ck_hotword_manual_scope
        CHECK (scope_type IN ('GLOBAL', 'CITY', 'DISTRICT', 'STATION')),
    CONSTRAINT ck_hotword_manual_category
        CHECK (category IN
            ('ADDRESS', 'ROAD', 'KEY_UNIT', 'FIRE_RESOURCE',
             'INCIDENT_TYPE', 'EQUIPMENT', 'MANUAL')),
    CONSTRAINT ck_hotword_manual_status
        CHECK (status IN ('DRAFT', 'APPROVED', 'REJECTED', 'DISABLED')),
    CONSTRAINT ck_hotword_manual_priority
        CHECK (base_priority >= 0 AND base_priority <= 100),
    CONSTRAINT ck_hotword_manual_period
        CHECK (effective_to IS NULL OR effective_from IS NULL OR
               effective_to > effective_from)
);

CREATE INDEX IF NOT EXISTS idx_hotword_manual_scope_status
    ON dispatch_assist.hotword_manual_entry
    (scope_type, scope_id, status, effective_from);

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_snapshot (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scope_type VARCHAR(32) NOT NULL,
    scope_id VARCHAR(64) NOT NULL,
    provider_code VARCHAR(64) NOT NULL,
    version_no INTEGER NOT NULL,
    status VARCHAR(32) NOT NULL,
    content_sha256 CHAR(64) NOT NULL,
    word_count INTEGER NOT NULL,
    build_reason VARCHAR(64) NOT NULL,
    source_cutoff_at TIMESTAMPTZ NOT NULL,
    provider_profile_version VARCHAR(64) NOT NULL,
    effective_at TIMESTAMPTZ,
    created_by VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_hotword_snapshot_version
        UNIQUE (scope_type, scope_id, provider_code, version_no),
    CONSTRAINT uk_hotword_snapshot_content
        UNIQUE (scope_type, scope_id, provider_code, content_sha256),
    CONSTRAINT ck_hotword_snapshot_scope
        CHECK (scope_type IN ('GLOBAL', 'CITY', 'DISTRICT', 'STATION')),
    CONSTRAINT ck_hotword_snapshot_status
        CHECK (status IN
            ('DRAFT', 'PUBLISHING', 'ACTIVE', 'FAILED',
             'SUPERSEDED', 'ROLLED_BACK')),
    CONSTRAINT ck_hotword_snapshot_version CHECK (version_no > 0),
    CONSTRAINT ck_hotword_snapshot_word_count CHECK (word_count >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uk_hotword_snapshot_one_active
    ON dispatch_assist.hotword_snapshot
    (scope_type, scope_id, provider_code)
    WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS idx_hotword_snapshot_scope_status
    ON dispatch_assist.hotword_snapshot
    (scope_type, scope_id, provider_code, status, version_no DESC);

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_snapshot_item (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_id UUID NOT NULL
        REFERENCES dispatch_assist.hotword_snapshot(id) ON DELETE CASCADE,
    word VARCHAR(128) NOT NULL,
    normalized_word VARCHAR(128) NOT NULL,
    category VARCHAR(32) NOT NULL,
    internal_score NUMERIC(8,3) NOT NULL,
    provider_weight INTEGER NOT NULL,
    source_refs JSONB NOT NULL DEFAULT '[]'::jsonb,
    selected_reason VARCHAR(256),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_hotword_snapshot_item
        UNIQUE (snapshot_id, normalized_word, category),
    CONSTRAINT ck_hotword_item_category
        CHECK (category IN
            ('ADDRESS', 'ROAD', 'KEY_UNIT', 'FIRE_RESOURCE',
             'INCIDENT_TYPE', 'EQUIPMENT', 'MANUAL')),
    CONSTRAINT ck_hotword_item_weight CHECK (provider_weight >= 0)
);

CREATE INDEX IF NOT EXISTS idx_hotword_item_snapshot_score
    ON dispatch_assist.hotword_snapshot_item
    (snapshot_id, internal_score DESC);
CREATE INDEX IF NOT EXISTS idx_hotword_item_source_refs_gin
    ON dispatch_assist.hotword_snapshot_item
    USING GIN (source_refs);

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_provider_release (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_id UUID NOT NULL
        REFERENCES dispatch_assist.hotword_snapshot(id),
    attempt_no INTEGER NOT NULL,
    idempotency_key VARCHAR(128) NOT NULL,
    status VARCHAR(32) NOT NULL,
    vendor_vocabulary_id VARCHAR(256),
    vendor_request_id VARCHAR(256),
    retry_count INTEGER NOT NULL DEFAULT 0,
    next_retry_at TIMESTAMPTZ,
    error_code VARCHAR(128),
    error_message VARCHAR(1024),
    submitted_at TIMESTAMPTZ,
    effective_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_hotword_release_attempt
        UNIQUE (snapshot_id, attempt_no),
    CONSTRAINT uk_hotword_release_idempotency UNIQUE (idempotency_key),
    CONSTRAINT ck_hotword_release_status
        CHECK (status IN
            ('PENDING', 'SUBMITTED', 'EFFECTIVE', 'RETRY_WAIT', 'FAILED')),
    CONSTRAINT ck_hotword_release_attempt CHECK (attempt_no > 0),
    CONSTRAINT ck_hotword_release_retry CHECK (retry_count >= 0)
);

CREATE INDEX IF NOT EXISTS idx_hotword_release_retry
    ON dispatch_assist.hotword_provider_release
    (status, next_retry_at)
    WHERE status IN ('PENDING', 'RETRY_WAIT', 'SUBMITTED');

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_consumer_binding (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_id UUID NOT NULL
        REFERENCES dispatch_assist.hotword_snapshot(id),
    consumer_type VARCHAR(32) NOT NULL,
    consumer_instance VARCHAR(128) NOT NULL,
    provider_code VARCHAR(64),
    payload_checksum CHAR(64) NOT NULL,
    delivery_mode VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL,
    external_version VARCHAR(256),
    external_load_id VARCHAR(256),
    retry_count INTEGER NOT NULL DEFAULT 0,
    next_retry_at TIMESTAMPTZ,
    error_code VARCHAR(128),
    error_message VARCHAR(1024),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    loaded_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_hotword_consumer_binding
        UNIQUE (snapshot_id, consumer_type, consumer_instance,
                payload_checksum),
    CONSTRAINT ck_hotword_consumer_type
        CHECK (consumer_type IN ('ASR', 'ELEMENT_EXTRACTOR', 'ADDRESS_ROBOT')),
    CONSTRAINT ck_hotword_consumer_delivery_mode
        CHECK (delivery_mode IN
            ('VOCABULARY_ID', 'FULL_SNAPSHOT', 'DELTA')),
    CONSTRAINT ck_hotword_consumer_status
        CHECK (status IN
            ('REQUESTED', 'LOADING', 'LOADED', 'FAILED', 'SUPERSEDED')),
    CONSTRAINT ck_hotword_consumer_retry CHECK (retry_count >= 0)
);

CREATE INDEX IF NOT EXISTS idx_hotword_consumer_binding_current
    ON dispatch_assist.hotword_consumer_binding
    (consumer_type, consumer_instance, status, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_hotword_consumer_binding_retry
    ON dispatch_assist.hotword_consumer_binding (status, next_retry_at)
    WHERE status IN ('REQUESTED', 'LOADING', 'FAILED');

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_id UUID NOT NULL
        REFERENCES dispatch_assist.hotword_snapshot(id),
    session_id VARCHAR(64) NOT NULL,
    recognized_word VARCHAR(128),
    corrected_word VARCHAR(128),
    confirmed_address_code VARCHAR(64),
    feedback_type VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_hotword_feedback_type
        CHECK (feedback_type IN
            ('CORRECT_HIT', 'MISSED', 'FALSE_BOOST', 'OPERATOR_CORRECTED')),
    CONSTRAINT ck_hotword_feedback_content
        CHECK (recognized_word IS NOT NULL OR corrected_word IS NOT NULL OR
               confirmed_address_code IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_hotword_feedback_snapshot_time
    ON dispatch_assist.hotword_feedback (snapshot_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_hotword_feedback_word
    ON dispatch_assist.hotword_feedback (recognized_word, corrected_word);

CREATE TABLE IF NOT EXISTS dispatch_assist.outbox_event (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type VARCHAR(64) NOT NULL,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(128) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'NEW',
    retry_count INTEGER NOT NULL DEFAULT 0,
    next_retry_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    locked_by VARCHAR(128),
    locked_at TIMESTAMPTZ,
    last_error VARCHAR(1024),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMPTZ,
    CONSTRAINT ck_outbox_status
        CHECK (status IN ('NEW', 'PROCESSING', 'PUBLISHED', 'FAILED')),
    CONSTRAINT ck_outbox_retry CHECK (retry_count >= 0)
);

CREATE INDEX IF NOT EXISTS idx_outbox_pending
    ON dispatch_assist.outbox_event
    (status, next_retry_at, created_at)
    WHERE status IN ('NEW', 'FAILED');
CREATE INDEX IF NOT EXISTS idx_outbox_aggregate
    ON dispatch_assist.outbox_event
    (aggregate_type, aggregate_id, created_at);

COMMENT ON SCHEMA dispatch_assist IS
    '消防接处警定位与动态热词服务';
COMMENT ON TABLE dispatch_assist.location_evidence IS
    '不可变的位置输入证据；metadata 禁止写入完整手机号、录音或凭证';
COMMENT ON TABLE dispatch_assist.location_candidate IS
    '一次解析版本产生的候选及可解释评分快照';
COMMENT ON TABLE dispatch_assist.hotword_snapshot IS
    '按范围和 ASR 厂商生成的不可变热词版本';
COMMENT ON TABLE dispatch_assist.hotword_feedback IS
    '仅保存词级反馈和标准地址编码，不保存完整通话文本或录音';
COMMENT ON TABLE dispatch_assist.outbox_event IS
    '与业务事务原子写入的可靠外部副作用事件';
