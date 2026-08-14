-- Runtime fields required to restore the location aggregate without
-- approximating circle radii from persisted polygons.

ALTER TABLE dispatch_assist.location_resolution
    ADD COLUMN IF NOT EXISTS hard_center GEOGRAPHY(POINT, 4326),
    ADD COLUMN IF NOT EXISTS hard_radius_meters NUMERIC(12,3),
    ADD COLUMN IF NOT EXISTS search_center GEOGRAPHY(POINT, 4326),
    ADD COLUMN IF NOT EXISTS search_radius_meters NUMERIC(12,3),
    ADD COLUMN IF NOT EXISTS neighbor_cell_ids TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS warnings TEXT[] NOT NULL DEFAULT '{}';

ALTER TABLE dispatch_assist.location_resolution
    DROP CONSTRAINT IF EXISTS ck_location_resolution_area_radii;
ALTER TABLE dispatch_assist.location_resolution
    ADD CONSTRAINT ck_location_resolution_area_radii CHECK (
        (hard_radius_meters IS NULL OR hard_radius_meters > 0)
        AND (search_radius_meters IS NULL OR search_radius_meters > 0)
    );

CREATE INDEX IF NOT EXISTS idx_location_resolution_hard_center_gist
    ON dispatch_assist.location_resolution USING GIST (hard_center);
CREATE INDEX IF NOT EXISTS idx_location_resolution_search_center_gist
    ON dispatch_assist.location_resolution USING GIST (search_center);
