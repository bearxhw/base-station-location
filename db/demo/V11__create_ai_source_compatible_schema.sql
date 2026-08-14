\set ON_ERROR_STOP on

-- Local source-schema simulation captured from ods7alm.ai on 2026-08-03.
-- These tables intentionally preserve the real source contract, including
-- nullable generic geometry columns and the absence of foreign keys/GiST.

CREATE SCHEMA IF NOT EXISTS ai;

CREATE TABLE IF NOT EXISTS ai.aoi_1 (
    area_id VARCHAR(32),
    area_code VARCHAR(12),
    area_name VARCHAR(64),
    addrlevel_id VARCHAR(1),
    parent_code VARCHAR(12),
    seq INTEGER,
    update_time TIMESTAMP,
    is_deleted BOOLEAN,
    datafrom_by VARCHAR(32)
);

CREATE TABLE IF NOT EXISTS ai.aoi_2 (
    aoi_id VARCHAR(32) NOT NULL,
    aoi_name VARCHAR(255) NOT NULL,
    alias_name VARCHAR(255) NOT NULL,
    area_id VARCHAR(32) NOT NULL,
    aoi_typeid VARCHAR(32) NOT NULL,
    aoi_typename VARCHAR(32),
    coord_sys VARCHAR(32) NOT NULL DEFAULT 'WGS84',
    longitude NUMERIC(19,8) NOT NULL,
    latitude NUMERIC(19,8) NOT NULL,
    geom GEOMETRY,
    radius INTEGER NOT NULL DEFAULT 0,
    data_source VARCHAR(32) NOT NULL,
    captured_at TIMESTAMP NOT NULL,
    create_by VARCHAR(36) NOT NULL,
    create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_by VARCHAR(36),
    update_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    datafrom_by VARCHAR(32) NOT NULL DEFAULT '7.0',
    CONSTRAINT aoi_2_pkey PRIMARY KEY (aoi_id)
);

CREATE INDEX IF NOT EXISTS aoi_2_aoi_name
    ON ai.aoi_2 USING GIN (aoi_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS aoi_2_lnt_lat
    ON ai.aoi_2 (longitude, latitude);

CREATE TABLE IF NOT EXISTS ai.aoi_3 (
    aoi_id VARCHAR(32) NOT NULL,
    aoi_name VARCHAR(255) NOT NULL,
    label_name VARCHAR(255) NOT NULL,
    area_id VARCHAR(32) NOT NULL,
    aoi_typeid VARCHAR(32) NOT NULL,
    aoi_typename VARCHAR(32),
    coord_sys VARCHAR(32) NOT NULL DEFAULT 'WGS84',
    longitude NUMERIC(19,8) NOT NULL,
    latitude NUMERIC(19,8) NOT NULL,
    geom GEOMETRY NOT NULL,
    aoi_area NUMERIC(11,2) NOT NULL DEFAULT 0,
    org_id VARCHAR(32),
    data_source VARCHAR(32) NOT NULL,
    captured_at TIMESTAMP NOT NULL,
    create_by VARCHAR(36) NOT NULL,
    create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_by VARCHAR(36),
    update_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    datafrom_by VARCHAR(32) NOT NULL DEFAULT '7.0',
    CONSTRAINT aoi_3_pkey PRIMARY KEY (aoi_id)
);

CREATE INDEX IF NOT EXISTS aoi_3_aoi_name
    ON ai.aoi_3 USING GIN (aoi_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS aoi_3_area_id
    ON ai.aoi_3 (area_id);
CREATE INDEX IF NOT EXISTS aoi_3_lnt_lat
    ON ai.aoi_3 (longitude, latitude);

CREATE TABLE IF NOT EXISTS ai.aoi_3_entrance_exit (
    id VARCHAR(32) NOT NULL,
    aoi_id VARCHAR(32) NOT NULL,
    name VARCHAR(50) NOT NULL,
    longitude NUMERIC(19,8),
    latitude NUMERIC(19,8),
    geom GEOMETRY,
    coord_sys VARCHAR(32) NOT NULL DEFAULT 'WGS84',
    gate_type INTEGER NOT NULL,
    is_firepass BOOLEAN,
    status VARCHAR(32),
    create_by VARCHAR(36) NOT NULL,
    create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_by VARCHAR(36),
    update_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    datafrom_by VARCHAR(32) NOT NULL DEFAULT '7.0',
    CONSTRAINT aoi_3_entrance_exit_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS aoi_3_entrance_exit_aoi_id
    ON ai.aoi_3_entrance_exit (aoi_id);

CREATE TABLE IF NOT EXISTS ai.aoi_3_parent_ref (
    id VARCHAR(32) NOT NULL,
    aoi_3_id VARCHAR(32) NOT NULL,
    aoi_2_id VARCHAR(32) NOT NULL,
    create_by VARCHAR(36) NOT NULL,
    create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_by VARCHAR(36),
    update_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    datafrom_by VARCHAR(32) NOT NULL DEFAULT '7.0',
    CONSTRAINT aoi_3_parent_ref_pkey PRIMARY KEY (id),
    CONSTRAINT aoi_3_parent_ref_ukey
        UNIQUE (aoi_2_id, aoi_3_id, is_deleted)
);

CREATE TABLE IF NOT EXISTS ai.poi_1 (
    building_id VARCHAR(32) NOT NULL,
    building_name VARCHAR(255) NOT NULL,
    short_name VARCHAR(255),
    area_code VARCHAR(32) NOT NULL,
    city_name VARCHAR(32) NOT NULL,
    county_name VARCHAR(32) NOT NULL,
    street_name VARCHAR(32),
    address_name VARCHAR(255) NOT NULL,
    longitude NUMERIC(19,8) NOT NULL,
    latitude NUMERIC(19,8) NOT NULL,
    geom GEOMETRY,
    coord_sys VARCHAR(32) NOT NULL DEFAULT 'WGS84',
    org_id VARCHAR(32),
    aoi_id VARCHAR(32) NOT NULL,
    aoi_name VARCHAR(255),
    data_source VARCHAR(32) NOT NULL,
    captured_at TIMESTAMP NOT NULL,
    create_by VARCHAR(36) NOT NULL,
    create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_by VARCHAR(36),
    update_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    datafrom_by VARCHAR(32) NOT NULL DEFAULT '7.0',
    CONSTRAINT poi_12_pkey PRIMARY KEY (building_id)
);

CREATE INDEX IF NOT EXISTS poi_12_aoi_id
    ON ai.poi_1 (aoi_id);
CREATE INDEX IF NOT EXISTS poi_12_area_code
    ON ai.poi_1 (area_code);
CREATE INDEX IF NOT EXISTS poi_1_lnt_lat
    ON ai.poi_1 (longitude, latitude);
CREATE INDEX IF NOT EXISTS poi_1_name
    ON ai.poi_1 USING GIN (building_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS poi_1_org_id
    ON ai.poi_1 (org_id);

CREATE TABLE IF NOT EXISTS ai.poi_1_building_special (
    building_id VARCHAR(32) NOT NULL,
    met_buildingarea NUMERIC(11,2),
    met_height NUMERIC(11,2),
    met_floorheight NUMERIC(11,2),
    met_upheight NUMERIC(11,2),
    met_upfloors INTEGER,
    met_downfloors INTEGER,
    met_depth NUMERIC(11,2),
    met_podiumfloors INTEGER,
    met_floors INTEGER,
    met_standardarea NUMERIC(11,2),
    met_coverarea NUMERIC(11,2),
    met_e_nearby NUMERIC(8,2) DEFAULT 0,
    met_s_nearby NUMERIC(8,2) DEFAULT 0,
    met_w_nearby NUMERIC(8,2) DEFAULT 0,
    met_n_nearby NUMERIC(8,2) DEFAULT 0,
    sensitive_target TEXT,
    climbing_position VARCHAR(255),
    met_climbing NUMERIC(11,2),
    fire_rescue_access VARCHAR(255),
    buildusage_id VARCHAR(32),
    build_type_id VARCHAR(32) NOT NULL,
    storage_material TEXT,
    floor_plan_url VARCHAR(255),
    diagram3d_url VARCHAR(255),
    create_by VARCHAR(36) NOT NULL,
    create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_by VARCHAR(36),
    update_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    datafrom_by VARCHAR(32) NOT NULL DEFAULT '7.0',
    CONSTRAINT poi_1_building_special_pkey PRIMARY KEY (building_id)
);

CREATE INDEX IF NOT EXISTS building_special_build_type_id
    ON ai.poi_1_building_special (build_type_id);
CREATE INDEX IF NOT EXISTS building_special_buildusage_id
    ON ai.poi_1_building_special (buildusage_id);

CREATE TABLE IF NOT EXISTS ai.poi_1_entrance_exit (
    id VARCHAR(32) NOT NULL,
    building_id VARCHAR(32) NOT NULL,
    name VARCHAR(50) NOT NULL,
    longitude NUMERIC(19,8),
    latitude NUMERIC(19,8),
    geom GEOMETRY,
    coord_sys VARCHAR(32) NOT NULL DEFAULT 'WGS84',
    gate_type INTEGER NOT NULL,
    status VARCHAR(32),
    create_by VARCHAR(36) NOT NULL,
    create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_by VARCHAR(36),
    update_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    datafrom_by VARCHAR(32) NOT NULL DEFAULT '7.0',
    CONSTRAINT poi_1_entrance_exit_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS entrance_exit_building_id
    ON ai.poi_1_entrance_exit (building_id);

CREATE TABLE IF NOT EXISTS ai.poi_2 (
    floor_id VARCHAR(32) NOT NULL,
    floor_name VARCHAR(255) NOT NULL,
    building_id VARCHAR(32) NOT NULL,
    floor_typeid VARCHAR(32) NOT NULL,
    floor_typename VARCHAR(32),
    relative_height NUMERIC(6,2),
    floor_area NUMERIC(11,2),
    data_source VARCHAR(32) NOT NULL,
    captured_at TIMESTAMP NOT NULL,
    create_by VARCHAR(36) NOT NULL,
    create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_by VARCHAR(36),
    update_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    datafrom_by VARCHAR(32) NOT NULL DEFAULT '7.0',
    CONSTRAINT poi_2_pkey PRIMARY KEY (floor_id)
);

CREATE INDEX IF NOT EXISTS poi_2_building_id
    ON ai.poi_2 (building_id);

CREATE TABLE IF NOT EXISTS ai.poi_3 (
    poi_id VARCHAR(32) NOT NULL,
    poi_name VARCHAR(255) NOT NULL,
    label_name VARCHAR(100),
    poi_typeid VARCHAR(32) NOT NULL,
    poi_typename VARCHAR(32),
    floor_id VARCHAR(32),
    coord_sys VARCHAR(32) NOT NULL DEFAULT 'WGS84',
    longitude NUMERIC(19,8) NOT NULL,
    latitude NUMERIC(19,8) NOT NULL,
    geom GEOMETRY,
    area_id VARCHAR(32) NOT NULL,
    address_name VARCHAR(255) NOT NULL,
    aoi_id VARCHAR(32),
    building_id VARCHAR(32),
    org_id VARCHAR(32),
    room_no VARCHAR(20),
    poi_area NUMERIC(11,2),
    create_by VARCHAR(36) NOT NULL,
    create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_by VARCHAR(36),
    update_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    datafrom_by VARCHAR(32) NOT NULL DEFAULT '7.0',
    CONSTRAINT poi_3_pkey PRIMARY KEY (poi_id)
);

CREATE INDEX IF NOT EXISTS poi_3_aoi_id
    ON ai.poi_3 (aoi_id);
CREATE INDEX IF NOT EXISTS poi_3_area_id
    ON ai.poi_3 (area_id);
CREATE INDEX IF NOT EXISTS poi_3_building_id
    ON ai.poi_3 (building_id);
CREATE INDEX IF NOT EXISTS poi_3_lnt_lat
    ON ai.poi_3 (longitude, latitude);
CREATE INDEX IF NOT EXISTS poi_3_name
    ON ai.poi_3 USING GIN (poi_name gin_trgm_ops);

CREATE TABLE IF NOT EXISTS ai.loi_road (
    road_id VARCHAR(32) NOT NULL,
    cn_name VARCHAR(254),
    mesh VARCHAR(10) NOT NULL,
    area_code VARCHAR(12),
    aoi_id VARCHAR(32),
    geom GEOMETRY,
    coord_sys VARCHAR(32) NOT NULL DEFAULT 'WGS84',
    loi_typeid VARCHAR(32) NOT NULL,
    loi_typename VARCHAR(32),
    start_node VARCHAR(64) NOT NULL,
    end_node VARCHAR(64) NOT NULL,
    road_class VARCHAR(10) NOT NULL,
    road_length NUMERIC(16,6),
    road_width NUMERIC(16,6),
    lane_no SMALLINT,
    lane_width NUMERIC(15,2),
    road_direct SMALLINT,
    road_toll SMALLINT,
    road_owner SMALLINT,
    road_status SMALLINT NOT NULL,
    road_form SMALLINT NOT NULL,
    side_road SMALLINT NOT NULL,
    inner_cross SMALLINT NOT NULL,
    service_road SMALLINT NOT NULL,
    slipe_road SMALLINT NOT NULL,
    entry_exit SMALLINT NOT NULL,
    slip_road SMALLINT NOT NULL,
    is_roundabout SMALLINT NOT NULL,
    is_bridge SMALLINT,
    is_ferry SMALLINT,
    is_tunnel SMALLINT,
    is_elevated SMALLINT,
    func_class SMALLINT,
    object_type VARCHAR(32),
    data_source VARCHAR(32) NOT NULL,
    captured_at TIMESTAMP NOT NULL,
    create_by VARCHAR(36) NOT NULL,
    create_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_by VARCHAR(36),
    update_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    datafrom_by VARCHAR(32) NOT NULL DEFAULT '7.0',
    CONSTRAINT loi_road_pkey PRIMARY KEY (road_id)
);

COMMENT ON SCHEMA ai IS
    'Demo-only source schema compatible with the real ods7alm.ai contract.';
