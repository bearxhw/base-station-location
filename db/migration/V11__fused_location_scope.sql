-- Persist the authoritative address-recall scope as a union of the serving
-- cell and selected neighbor coverage components. A fused scope may be
-- disconnected, so Polygon is widened to MultiPolygon.

DROP INDEX IF EXISTS dispatch_assist.idx_location_resolution_hard_area_gist;
DROP INDEX IF EXISTS dispatch_assist.idx_location_resolution_search_area_gist;

ALTER TABLE dispatch_assist.location_resolution
    ALTER COLUMN hard_area
        TYPE GEOGRAPHY(MULTIPOLYGON, 4326)
        USING ST_Multi(hard_area::geometry)::geography,
    ALTER COLUMN search_area
        TYPE GEOGRAPHY(MULTIPOLYGON, 4326)
        USING ST_Multi(search_area::geometry)::geography;

CREATE INDEX IF NOT EXISTS idx_location_resolution_hard_area_gist
    ON dispatch_assist.location_resolution USING GIST (hard_area);
CREATE INDEX IF NOT EXISTS idx_location_resolution_search_area_gist
    ON dispatch_assist.location_resolution USING GIST (search_area);

COMMENT ON COLUMN dispatch_assist.location_resolution.hard_area IS
    'Evidence-backed MultiPolygon. Coordinate-only spatial neighbors do not enlarge this area.';
COMMENT ON COLUMN dispatch_assist.location_resolution.search_area IS
    'Authoritative logical-address scope: union of serving and selected neighbor coverage components.';
