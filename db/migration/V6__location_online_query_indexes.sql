-- Indexes for the bounded online location path:
-- one serving cell -> a few neighbor relations -> a bounded address candidate set.

CREATE INDEX IF NOT EXISTS idx_cell_sector_identity_active_version
    ON dispatch_assist.cell_sector (
        operator_code,
        rat,
        mcc,
        mnc,
        area_code,
        cell_id,
        version DESC
    )
    INCLUDE (
        id,
        site_location,
        nominal_radius_meters,
        quality_score,
        effective_from,
        effective_to
    )
    WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS idx_cell_neighbor_online_topn
    ON dispatch_assist.cell_neighbor_relation (
        serving_sector_id,
        relation_source,
        priority DESC,
        confidence_score DESC
    )
    INCLUDE (
        neighbor_sector_id,
        effective_from,
        effective_to
    )
    WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS idx_cell_nearby_address_online_topn
    ON dispatch_assist.cell_nearby_address_relation (
        cell_sector_id,
        rank_no
    )
    INCLUDE (
        standard_address_id,
        distance_meters,
        relation_source
    )
    WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS idx_standard_address_active_location_gist
    ON dispatch_assist.standard_address
    USING GIST (location)
    WHERE active = TRUE;
