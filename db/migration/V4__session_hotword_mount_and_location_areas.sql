-- V4: separate evidence-backed positioning area from address-recall area,
-- and persist session-to-static-library mount history.

ALTER TABLE dispatch_assist.location_resolution
    ADD COLUMN IF NOT EXISTS hard_area GEOGRAPHY(POLYGON, 4326),
    ADD COLUMN IF NOT EXISTS search_area GEOGRAPHY(POLYGON, 4326),
    ADD COLUMN IF NOT EXISTS evidence_level VARCHAR(32),
    ADD COLUMN IF NOT EXISTS positioning_method VARCHAR(48),
    ADD COLUMN IF NOT EXISTS neighbor_source VARCHAR(32);

ALTER TABLE dispatch_assist.location_resolution
    DROP CONSTRAINT IF EXISTS ck_location_resolution_evidence_level;
ALTER TABLE dispatch_assist.location_resolution
    ADD CONSTRAINT ck_location_resolution_evidence_level
        CHECK (evidence_level IS NULL OR evidence_level IN
            ('L0_UNAVAILABLE', 'L1_CELL_ID_ONLY', 'L2_REPORTED_NEIGHBOR',
             'L3_OPERATOR_ESTIMATE', 'L4_USER_ESTIMATE', 'L5_DEVICE_PRECISE'));

ALTER TABLE dispatch_assist.location_resolution
    DROP CONSTRAINT IF EXISTS ck_location_resolution_neighbor_source;
ALTER TABLE dispatch_assist.location_resolution
    ADD CONSTRAINT ck_location_resolution_neighbor_source
        CHECK (neighbor_source IS NULL OR neighbor_source IN
            ('NONE', 'REPORTED', 'OPERATOR', 'HANDOVER_STAT',
             'MANUAL', 'SPATIAL_DERIVED'));

CREATE INDEX IF NOT EXISTS idx_location_resolution_hard_area_gist
    ON dispatch_assist.location_resolution USING GIST (hard_area);
CREATE INDEX IF NOT EXISTS idx_location_resolution_search_area_gist
    ON dispatch_assist.location_resolution USING GIST (search_area);

COMMENT ON COLUMN dispatch_assist.location_resolution.hard_area IS
    'Only the area supported by evidence from this call; spatial-derived neighbors must not enlarge confidence.';
COMMENT ON COLUMN dispatch_assist.location_resolution.search_area IS
    'Expanded address-recall area; configured or spatial-derived neighbors may enlarge it.';

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_session_mount (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id VARCHAR(128) NOT NULL,
    session_id VARCHAR(64) NOT NULL,
    alarm_id VARCHAR(64),
    consumer_instance VARCHAR(128) NOT NULL,
    provider_code VARCHAR(64) NOT NULL,
    element_version BIGINT NOT NULL,
    mount_version INTEGER NOT NULL,
    operation VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL,
    selected_library_refs JSONB NOT NULL DEFAULT '[]'::jsonb,
    before_dedup_term_count INTEGER NOT NULL,
    after_dedup_term_count INTEGER NOT NULL,
    payload_checksum CHAR(64) NOT NULL,
    provider_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    warnings JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_hotword_session_mount_request UNIQUE (request_id),
    CONSTRAINT uk_hotword_session_mount_element
        UNIQUE (session_id, consumer_instance, element_version),
    CONSTRAINT ck_hotword_session_mount_element_version
        CHECK (element_version > 0),
    CONSTRAINT ck_hotword_session_mount_version
        CHECK (mount_version > 0),
    CONSTRAINT ck_hotword_session_mount_operation
        CHECK (operation IN
            ('INITIAL_LOAD', 'UNCHANGED', 'REBIND', 'RECONNECT_REQUIRED')),
    CONSTRAINT ck_hotword_session_mount_status
        CHECK (status IN ('MOUNT_READY', 'PENDING_RECONNECT')),
    CONSTRAINT ck_hotword_session_mount_counts
        CHECK (before_dedup_term_count >= after_dedup_term_count
            AND after_dedup_term_count >= 0),
    CONSTRAINT ck_hotword_session_mount_libraries
        CHECK (jsonb_typeof(selected_library_refs) = 'array'),
    CONSTRAINT ck_hotword_session_mount_payload
        CHECK (jsonb_typeof(provider_payload) = 'object'),
    CONSTRAINT ck_hotword_session_mount_warnings
        CHECK (jsonb_typeof(warnings) = 'array')
);

CREATE INDEX IF NOT EXISTS idx_hotword_session_mount_current
    ON dispatch_assist.hotword_session_mount
    (session_id, consumer_instance, element_version DESC);

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_session_library_binding (
    mount_id UUID NOT NULL
        REFERENCES dispatch_assist.hotword_session_mount(id) ON DELETE CASCADE,
    library_id UUID NOT NULL
        REFERENCES dispatch_assist.hotword_library(id),
    static_version INTEGER NOT NULL,
    dimension VARCHAR(24) NOT NULL,
    binding_status VARCHAR(16) NOT NULL DEFAULT 'SELECTED',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (mount_id, library_id),
    CONSTRAINT ck_hotword_session_library_dimension
        CHECK (dimension IN ('PLACE_SCENE', 'RESCUE_TASK')),
    CONSTRAINT ck_hotword_session_library_binding_status
        CHECK (binding_status = 'SELECTED')
);

COMMENT ON TABLE dispatch_assist.hotword_session_mount IS
    'Alarm-session mount plans. A row changes only the session binding/payload; it never updates a static hotword library.';
COMMENT ON TABLE dispatch_assist.hotword_session_library_binding IS
    'Exact immutable static-library versions selected for one session mount.';

CREATE TABLE IF NOT EXISTS dispatch_assist.cell_identity_alias (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cell_sector_id UUID NOT NULL
        REFERENCES dispatch_assist.cell_sector(id),
    identity_type VARCHAR(16) NOT NULL,
    raw_identity VARCHAR(128) NOT NULL,
    raw_radix INTEGER,
    normalized_identity VARCHAR(128) NOT NULL,
    mnc_length SMALLINT,
    enodeb_id BIGINT,
    lte_sector_id INTEGER,
    gnodeb_id BIGINT,
    nr_sector_id BIGINT,
    normalization_version VARCHAR(32) NOT NULL,
    valid_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_cell_identity_alias
        UNIQUE (identity_type, normalized_identity, valid_from),
    CONSTRAINT ck_cell_identity_alias_type
        CHECK (identity_type IN ('CGI', 'ECGI', 'NCGI', 'VENDOR_PRIVATE')),
    CONSTRAINT ck_cell_identity_alias_radix
        CHECK (raw_radix IS NULL OR raw_radix IN (10, 16)),
    CONSTRAINT ck_cell_identity_alias_mnc_length
        CHECK (mnc_length IS NULL OR mnc_length IN (2, 3)),
    CONSTRAINT ck_cell_identity_alias_period
        CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE INDEX IF NOT EXISTS idx_cell_identity_alias_lookup
    ON dispatch_assist.cell_identity_alias
    (identity_type, normalized_identity, valid_to);

COMMENT ON TABLE dispatch_assist.cell_identity_alias IS
    'Preserves raw CGI/ECGI/NCGI/vendor identifiers and normalized LTE/NR components with validity periods.';
