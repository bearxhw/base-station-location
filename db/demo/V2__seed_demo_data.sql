SET search_path TO dispatch_assist, public;

INSERT INTO dispatch_assist.standard_address (
    id, address_code, full_address, normalized_address,
    admin_division_code, district_name, road_name, road_no, poi_name,
    location, data_source, quality_score
) VALUES
    ('00000000-0000-0000-0000-000000000001', 'ADDR-001',
     '北京市东城区东长安街天安门东侧', '北京市东城区东长安街天安门东侧',
     '110101', '东城区', '东长安街', NULL, '天安门东',
     ST_GeogFromText('SRID=4326;POINT(116.4010 39.9168)'),
     'DEMO_ADDRESS_GOVERNANCE', 0.98),
    ('00000000-0000-0000-0000-000000000002', 'ADDR-002',
     '北京市东城区王府井大街88号', '北京市东城区王府井大街88号',
     '110101', '东城区', '王府井大街', '88号', '王府井',
     ST_GeogFromText('SRID=4326;POINT(116.4115 39.9151)'),
     'DEMO_ADDRESS_GOVERNANCE', 0.99),
    ('00000000-0000-0000-0000-000000000003', 'ADDR-003',
     '北京市西城区西长安街复兴门方向', '北京市西城区西长安街复兴门方向',
     '110102', '西城区', '西长安街', NULL, '复兴门',
     ST_GeogFromText('SRID=4326;POINT(116.3830 39.9170)'),
     'DEMO_ADDRESS_GOVERNANCE', 0.95),
    ('00000000-0000-0000-0000-000000000004', 'ADDR-004',
     '北京市朝阳区建国路88号现代城', '北京市朝阳区建国路88号现代城',
     '110105', '朝阳区', '建国路', '88号', '现代城',
     ST_GeogFromText('SRID=4326;POINT(116.4750 39.9070)'),
     'DEMO_ADDRESS_GOVERNANCE', 0.97)
ON CONFLICT (address_code) DO UPDATE SET
    full_address = EXCLUDED.full_address,
    normalized_address = EXCLUDED.normalized_address,
    location = EXCLUDED.location,
    quality_score = EXCLUDED.quality_score,
    updated_at = CURRENT_TIMESTAMP;

INSERT INTO dispatch_assist.address_alias (
    standard_address_id, alias, normalized_alias, alias_type,
    data_source, approved
) VALUES
    ('00000000-0000-0000-0000-000000000001', '天安门东', '天安门东',
     'COMMON', 'DEMO_ADDRESS_GOVERNANCE', TRUE),
    ('00000000-0000-0000-0000-000000000002', '王府井88号', '王府井88号',
     'COMMON', 'DEMO_ADDRESS_GOVERNANCE', TRUE),
    ('00000000-0000-0000-0000-000000000004', 'SOHO现代城', 'soho现代城',
     'COMMON', 'DEMO_ADDRESS_GOVERNANCE', TRUE)
ON CONFLICT (standard_address_id, normalized_alias) DO UPDATE SET
    approved = TRUE,
    updated_at = CURRENT_TIMESTAMP;

INSERT INTO dispatch_assist.cell_sector (
    id, operator_code, rat, mcc, mnc, area_code_type, area_code, cell_id,
    site_name, site_location, azimuth_degrees, beam_width_degrees,
    nominal_radius_meters, coverage_geom, environment_type,
    data_source, quality_score, effective_from
) VALUES
    ('10000000-0000-0000-0000-000000000001',
     'CMCC', 'LTE', '460', '00', 'TAC', '12345', '1001',
     '东长安街模拟站', ST_GeogFromText('SRID=4326;POINT(116.3971 39.9165)'),
     80, 120, 1200,
     ST_Multi(ST_GeomFromText(
       'POLYGON((116.3971 39.9165,116.4098 39.9110,116.4110 39.9220,116.3971 39.9165))', 4326)),
     'URBAN', 'DEMO_OPERATOR', 0.80, '2026-01-01T00:00:00+08:00'),
    ('10000000-0000-0000-0000-000000000002',
     'CMCC', 'LTE', '460', '00', 'TAC', '12345', '1002',
     '王府井模拟站', ST_GeogFromText('SRID=4326;POINT(116.4140 39.9160)'),
     260, 120, 1100,
     ST_Multi(ST_GeomFromText(
       'POLYGON((116.4140 39.9160,116.4015 39.9215,116.4010 39.9105,116.4140 39.9160))', 4326)),
     'URBAN', 'DEMO_OPERATOR', 0.80, '2026-01-01T00:00:00+08:00'),
    ('10000000-0000-0000-0000-000000000003',
     'CMCC', 'LTE', '460', '00', 'TAC', '12345', '1003',
     '西长安街模拟站', ST_GeogFromText('SRID=4326;POINT(116.3805 39.9180)'),
     90, 120, 1000,
     ST_Multi(ST_GeomFromText(
       'POLYGON((116.3805 39.9180,116.3918 39.9125,116.3922 39.9230,116.3805 39.9180))', 4326)),
     'URBAN', 'DEMO_SPATIAL_FALLBACK', 0.65, '2026-01-01T00:00:00+08:00')
ON CONFLICT (
    operator_code, rat, mcc, mnc, area_code, cell_id, version
) DO UPDATE SET
    site_name = EXCLUDED.site_name,
    site_location = EXCLUDED.site_location,
    coverage_geom = EXCLUDED.coverage_geom,
    updated_at = CURRENT_TIMESTAMP;

INSERT INTO dispatch_assist.cell_neighbor_relation (
    id, serving_sector_id, neighbor_sector_id, relation_source,
    priority, confidence_score, derivation_version, effective_from
) VALUES (
    '20000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000002',
    'SPATIAL_DERIVED', 100, 0.90, 'demo-global-cell-conversion-v1',
    '2026-01-01T00:00:00+08:00'
)
ON CONFLICT (
    serving_sector_id, neighbor_sector_id, effective_from
) DO UPDATE SET
    active = TRUE,
    priority = EXCLUDED.priority,
    confidence_score = EXCLUDED.confidence_score,
    updated_at = CURRENT_TIMESTAMP;

INSERT INTO dispatch_assist.cell_nearby_address_relation (
    cell_sector_id, standard_address_id, relation_source,
    distance_meters, rank_no, build_version
)
SELECT
    cell.id,
    address.id,
    CASE
        WHEN ST_DWithin(
            cell.site_location,
            address.location,
            cell.nominal_radius_meters)
        THEN 'COVERAGE_DIRECT'
        ELSE 'NEIGHBOR_COVERAGE'
    END,
    ST_Distance(cell.site_location, address.location),
    ROW_NUMBER() OVER (
        PARTITION BY cell.id
        ORDER BY ST_Distance(cell.site_location, address.location)
    ),
    'demo-global-cell-conversion-v1'
FROM dispatch_assist.cell_sector cell
JOIN dispatch_assist.standard_address address
  ON address.address_code IN ('ADDR-001', 'ADDR-002', 'ADDR-003')
WHERE cell.cell_id IN ('1001', '1002', '1003')
ON CONFLICT (
    cell_sector_id, standard_address_id, build_version
) DO UPDATE SET
    relation_source = EXCLUDED.relation_source,
    distance_meters = EXCLUDED.distance_meters,
    rank_no = EXCLUDED.rank_no,
    active = TRUE,
    updated_at = CURRENT_TIMESTAMP;

INSERT INTO dispatch_assist.hotword_manual_entry (
    scope_type, scope_id, word, normalized_word, category,
    base_priority, status, reason, created_by, approved_by,
    approved_at, effective_from
) VALUES
    ('CITY', '110100', '王府井大街', '王府井大街', 'ADDRESS',
     90, 'APPROVED', 'Demo 标准地址', 'demo', 'demo',
     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('CITY', '110100', '现代城', '现代城', 'KEY_UNIT',
     90, 'APPROVED', 'Demo 重点单位', 'demo', 'demo',
     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('CITY', '110100', '高层建筑火灾', '高层建筑火灾', 'INCIDENT_TYPE',
     95, 'APPROVED', 'Demo 警情类型', 'demo', 'demo',
     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('CITY', '110100', '举高喷射消防车', '举高喷射消防车', 'EQUIPMENT',
     80, 'APPROVED', 'Demo 装备', 'demo', 'demo',
     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (scope_type, scope_id, normalized_word) DO UPDATE SET
    status = 'APPROVED',
    base_priority = EXCLUDED.base_priority,
    updated_at = CURRENT_TIMESTAMP;
