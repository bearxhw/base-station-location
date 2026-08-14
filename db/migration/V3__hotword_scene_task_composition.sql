-- 十二类场所场景、三类救援任务及会话级热词组合。
-- V1 的 hotword_snapshot 仍负责地域基础快照；本迁移负责可版本化场景库和会话组合审计。

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_library (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_code VARCHAR(64) NOT NULL,
    library_name VARCHAR(128) NOT NULL,
    library_dimension VARCHAR(32) NOT NULL,
    version_no INTEGER NOT NULL DEFAULT 1,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_hotword_library_code_version
        UNIQUE (library_code, version_no),
    CONSTRAINT ck_hotword_library_dimension
        CHECK (library_dimension IN ('PLACE_SCENE', 'RESCUE_TASK')),
    CONSTRAINT ck_hotword_library_status
        CHECK (status IN ('DRAFT', 'ACTIVE', 'SUPERSEDED', 'DISABLED')),
    CONSTRAINT ck_hotword_library_version CHECK (version_no > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uk_hotword_library_one_active
    ON dispatch_assist.hotword_library (library_code)
    WHERE status = 'ACTIVE';

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_term (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    word VARCHAR(128) NOT NULL,
    normalized_word VARCHAR(128) NOT NULL,
    category VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_hotword_term_normalized_category
        UNIQUE (normalized_word, category)
);

CREATE INDEX IF NOT EXISTS idx_hotword_term_normalized
    ON dispatch_assist.hotword_term (normalized_word);

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_term_library_rel (
    library_id UUID NOT NULL
        REFERENCES dispatch_assist.hotword_library(id) ON DELETE CASCADE,
    term_id UUID NOT NULL
        REFERENCES dispatch_assist.hotword_term(id) ON DELETE CASCADE,
    internal_score INTEGER NOT NULL,
    match_keywords JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (library_id, term_id),
    CONSTRAINT ck_hotword_term_library_score
        CHECK (internal_score BETWEEN 0 AND 100),
    CONSTRAINT ck_hotword_term_library_keywords
        CHECK (jsonb_typeof(match_keywords) = 'array')
);

CREATE INDEX IF NOT EXISTS idx_hotword_term_library_term
    ON dispatch_assist.hotword_term_library_rel (term_id);
CREATE INDEX IF NOT EXISTS idx_hotword_term_library_keywords
    ON dispatch_assist.hotword_term_library_rel USING GIN (match_keywords);

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_scene_match (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id VARCHAR(128) NOT NULL,
    session_id VARCHAR(64) NOT NULL,
    signal_sha256 CHAR(64) NOT NULL,
    rule_version VARCHAR(64) NOT NULL,
    suggested_primary_task VARCHAR(64) NOT NULL,
    primary_task VARCHAR(64) NOT NULL,
    selected_place_libraries JSONB NOT NULL DEFAULT '[]'::jsonb,
    auxiliary_task_packs JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_hotword_scene_match_request UNIQUE (request_id),
    CONSTRAINT ck_hotword_scene_match_places
        CHECK (jsonb_typeof(selected_place_libraries) = 'array'),
    CONSTRAINT ck_hotword_scene_match_auxiliary
        CHECK (jsonb_typeof(auxiliary_task_packs) = 'array')
);

CREATE INDEX IF NOT EXISTS idx_hotword_scene_match_session
    ON dispatch_assist.hotword_scene_match (session_id, created_at DESC);

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_scene_match_item (
    match_id UUID NOT NULL
        REFERENCES dispatch_assist.hotword_scene_match(id) ON DELETE CASCADE,
    library_id UUID NOT NULL
        REFERENCES dispatch_assist.hotword_library(id),
    score NUMERIC(5,4) NOT NULL,
    evidence JSONB NOT NULL DEFAULT '[]'::jsonb,
    selection_role VARCHAR(24) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (match_id, library_id),
    CONSTRAINT ck_hotword_scene_match_item_score
        CHECK (score BETWEEN 0 AND 1),
    CONSTRAINT ck_hotword_scene_match_item_evidence
        CHECK (jsonb_typeof(evidence) = 'array'),
    CONSTRAINT ck_hotword_scene_match_item_role
        CHECK (selection_role IN
            ('MATCHED', 'SELECTED_PLACE', 'PRIMARY_TASK',
             'AUXILIARY_TASK', 'NOT_SELECTED'))
);

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_composition (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    composition_key CHAR(64) NOT NULL,
    scene_match_id UUID
        REFERENCES dispatch_assist.hotword_scene_match(id),
    session_id VARCHAR(64) NOT NULL,
    scope_type VARCHAR(32) NOT NULL,
    scope_id VARCHAR(64) NOT NULL,
    provider_code VARCHAR(64) NOT NULL,
    consumer_type VARCHAR(32) NOT NULL,
    component_libraries JSONB NOT NULL,
    before_dedup_term_count INTEGER NOT NULL,
    after_dedup_term_count INTEGER NOT NULL,
    payload_checksum CHAR(64) NOT NULL,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_hotword_composition_key UNIQUE (composition_key),
    CONSTRAINT ck_hotword_composition_scope
        CHECK (scope_type IN ('GLOBAL', 'CITY', 'DISTRICT', 'STATION')),
    CONSTRAINT ck_hotword_composition_consumer
        CHECK (consumer_type IN ('ASR', 'ELEMENT_EXTRACTOR', 'ADDRESS_ROBOT')),
    CONSTRAINT ck_hotword_composition_components
        CHECK (jsonb_typeof(component_libraries) = 'array'),
    CONSTRAINT ck_hotword_composition_counts
        CHECK (before_dedup_term_count >= after_dedup_term_count
            AND after_dedup_term_count >= 0)
);

CREATE INDEX IF NOT EXISTS idx_hotword_composition_session_consumer
    ON dispatch_assist.hotword_composition
    (session_id, consumer_type, created_at DESC);

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_composition_item (
    composition_id UUID NOT NULL
        REFERENCES dispatch_assist.hotword_composition(id) ON DELETE CASCADE,
    ordinal_no INTEGER NOT NULL,
    word VARCHAR(128) NOT NULL,
    normalized_word VARCHAR(128) NOT NULL,
    category VARCHAR(64) NOT NULL,
    internal_score INTEGER NOT NULL,
    library_codes JSONB NOT NULL,
    PRIMARY KEY (composition_id, ordinal_no),
    CONSTRAINT uk_hotword_composition_item
        UNIQUE (composition_id, normalized_word, category),
    CONSTRAINT ck_hotword_composition_item_score
        CHECK (internal_score BETWEEN 0 AND 100),
    CONSTRAINT ck_hotword_composition_item_libraries
        CHECK (jsonb_typeof(library_codes) = 'array')
);

CREATE TABLE IF NOT EXISTS dispatch_assist.hotword_payload_chunk (
    composition_id UUID NOT NULL
        REFERENCES dispatch_assist.hotword_composition(id) ON DELETE CASCADE,
    chunk_no INTEGER NOT NULL,
    first_ordinal_no INTEGER NOT NULL,
    last_ordinal_no INTEGER NOT NULL,
    term_count INTEGER NOT NULL,
    payload_checksum CHAR(64) NOT NULL,
    delivery_status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    external_chunk_id VARCHAR(256),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    loaded_at TIMESTAMPTZ,
    PRIMARY KEY (composition_id, chunk_no),
    CONSTRAINT ck_hotword_payload_chunk_range
        CHECK (chunk_no > 0 AND first_ordinal_no > 0
            AND last_ordinal_no >= first_ordinal_no
            AND term_count = last_ordinal_no - first_ordinal_no + 1),
    CONSTRAINT ck_hotword_payload_chunk_status
        CHECK (delivery_status IN ('PENDING', 'SUBMITTED', 'LOADED', 'FAILED'))
);

INSERT INTO dispatch_assist.hotword_library
    (library_code, library_name, library_dimension)
VALUES
    ('HIGH_RISK_CARE', '高危弱照护', 'PLACE_SCENE'),
    ('COMMERCIAL_DENSE', '商业密集', 'PLACE_SCENE'),
    ('TRANSPORT_HUB', '交通枢纽', 'PLACE_SCENE'),
    ('RESIDENTIAL_LODGING', '居住住宿', 'PLACE_SCENE'),
    ('OFFICE_WORKPLACE', '办公场所', 'PLACE_SCENE'),
    ('INDUSTRIAL', '工业', 'PLACE_SCENE'),
    ('ENERGY_FACILITY', '能源设施', 'PLACE_SCENE'),
    ('CULTURE_RELIGION', '文化宗教', 'PLACE_SCENE'),
    ('RURAL_OPEN_AIR', '农村露天', 'PLACE_SCENE'),
    ('SMALL_FUNCTIONAL', '小型功能场所', 'PLACE_SCENE'),
    ('ABANDONED_TEMPORARY', '废弃临时场所', 'PLACE_SCENE'),
    ('EDUCATION_TRAINING', '教育培训', 'PLACE_SCENE'),
    ('FIRE_FIGHTING', '灭火救援', 'RESCUE_TASK'),
    ('SOCIAL_ASSISTANCE', '社会救助', 'RESCUE_TASK'),
    ('EMERGENCY_RESCUE', '应急救援', 'RESCUE_TASK')
ON CONFLICT (library_code, version_no) DO NOTHING;

COMMENT ON TABLE dispatch_assist.hotword_library IS
    '十二类场所场景库与三类救援任务词包的版本化目录';
COMMENT ON TABLE dispatch_assist.hotword_term_library_rel IS
    '标准词与多个库的多对多关系；同词不因多库成员关系而复制';
COMMENT ON TABLE dispatch_assist.hotword_scene_match IS
    '场所多标签与唯一主任务的会话级识别审计头';
COMMENT ON TABLE dispatch_assist.hotword_composition IS
    '基础词、场所库和任务词包按消费者组合后的幂等载荷头';
COMMENT ON TABLE dispatch_assist.hotword_payload_chunk IS
    '按厂商或消费者容量切分的载荷块及独立投递状态';
