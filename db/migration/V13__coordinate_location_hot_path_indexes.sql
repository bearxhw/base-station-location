-- V13: indexes for the direct-coordinate hot path.
--
-- The global cell library may contain inactive history rows. The partial
-- GiST index keeps the online 50 m anchor lookup focused on active rows.
-- Spatial-derived neighbor relations are built offline; the partial B-tree
-- serves the online Top-N lookup without scanning unrelated relation types.

CREATE INDEX IF NOT EXISTS idx_cell_sector_active_site_location_gist
    ON dispatch_assist.cell_sector
    USING GIST (site_location)
    WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS idx_cell_neighbor_spatial_active_serving
    ON dispatch_assist.cell_neighbor_relation (
        serving_sector_id,
        priority DESC,
        confidence_score DESC,
        neighbor_sector_id
    )
    WHERE active = TRUE
      AND relation_source = 'SPATIAL_DERIVED';

ANALYZE dispatch_assist.cell_sector;
ANALYZE dispatch_assist.cell_neighbor_relation;

COMMENT ON INDEX dispatch_assist.idx_cell_sector_active_site_location_gist IS
    'Direct WGS84 X/Y to active base-station anchor lookup.';
COMMENT ON INDEX dispatch_assist.idx_cell_neighbor_spatial_active_serving IS
    'Offline-derived neighbor pool lookup for one serving sector.';
