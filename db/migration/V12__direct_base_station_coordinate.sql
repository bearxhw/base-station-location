-- V12: make direct base-station WGS84 X/Y a first-class location input.

ALTER TABLE dispatch_assist.location_resolution
    DROP CONSTRAINT IF EXISTS ck_location_resolution_evidence_level;
ALTER TABLE dispatch_assist.location_resolution
    ADD CONSTRAINT ck_location_resolution_evidence_level
        CHECK (evidence_level IS NULL OR evidence_level IN
            ('L0_UNAVAILABLE',
             'L1_CELL_ID_ONLY',
             'L1_BASE_STATION_COORDINATE_ONLY',
             'L2_REPORTED_NEIGHBOR',
             'L3_OPERATOR_ESTIMATE',
             'L4_USER_ESTIMATE',
             'L5_DEVICE_PRECISE'));

ALTER TABLE dispatch_assist.location_evidence
    DROP CONSTRAINT IF EXISTS ck_location_evidence_source;
ALTER TABLE dispatch_assist.location_evidence
    ADD CONSTRAINT ck_location_evidence_source
        CHECK (source_type IN
            ('TELCO', 'CTI_COORDINATE', 'INTERNET', 'IOT', 'ASR',
             'OPERATOR'));

ALTER TABLE dispatch_assist.location_evidence
    DROP CONSTRAINT IF EXISTS ck_location_evidence_positioning_method;
ALTER TABLE dispatch_assist.location_evidence
    ADD CONSTRAINT ck_location_evidence_positioning_method
        CHECK (positioning_method IS NULL OR positioning_method IN
            ('PROVIDER_POINT', 'BASE_STATION_COORDINATE', 'CELL_ID',
             'E_CID', 'CELL_NEIGHBOR_FUSION', 'INTERNET', 'IOT',
             'OPERATOR_PICK'));

COMMENT ON COLUMN dispatch_assist.location_resolution.evidence_level IS
    'Evidence grade; L1_BASE_STATION_COORDINATE_ONLY is a site-level, not caller-level, position.';
