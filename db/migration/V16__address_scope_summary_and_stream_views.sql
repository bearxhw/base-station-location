-- Explicitly distinguish a queryable logical scope that contains address
-- candidates from one whose spatial result is empty. Scope creation uses a
-- short-circuiting EXISTS query; no exact count is calculated or stored.

ALTER TABLE dispatch_assist.logical_address_scope
    ADD COLUMN IF NOT EXISTS result_status VARCHAR(16)
        NOT NULL DEFAULT 'UNKNOWN';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'ck_logical_address_scope_result_status'
          AND conrelid =
              'dispatch_assist.logical_address_scope'::regclass
    ) THEN
        ALTER TABLE dispatch_assist.logical_address_scope
            ADD CONSTRAINT ck_logical_address_scope_result_status
            CHECK (result_status IN ('UNKNOWN', 'READY', 'EMPTY'));
    END IF;
END
$$;

-- Legacy handles remain UNKNOWN until they are reused by a new positioning
-- request. This deliberately avoids a full spatial backfill during rollout.
CREATE OR REPLACE VIEW
    dispatch_assist.logical_address_scope_summary AS
SELECT scope.scope_id,
       scope.location_resolution_id,
       scope.location_resolution_version,
       scope.inventory_version,
       scope.result_status AS scope_status,
       scope.created_at,
       scope.expires_at
FROM dispatch_assist.logical_address_scope scope
WHERE scope.status = 'ACTIVE'
  AND (scope.expires_at IS NULL
       OR scope.expires_at > CURRENT_TIMESTAMP);

-- Narrow projection for consumers that really need to stream address word
-- surfaces. It avoids geometry and source payload transfer.
CREATE OR REPLACE VIEW
    dispatch_assist.logical_address_scope_hotword_item AS
SELECT item.scope_id,
       item.inventory_id,
       item.source_type,
       item.standard_name,
       item.short_name,
       item.full_address,
       item.aliases,
       item.aoi_name,
       item.road_name
FROM dispatch_assist.logical_address_scope_item item;

-- Compact source-reference projection for address-robot follow-up queries.
CREATE OR REPLACE VIEW
    dispatch_assist.logical_address_scope_source_ref_item AS
SELECT item.scope_id,
       item.inventory_id,
       item.source_type,
       item.source_table,
       item.source_record_id,
       item.hit_level,
       item.longitude,
       item.latitude
FROM dispatch_assist.logical_address_scope_item item;

COMMENT ON COLUMN
    dispatch_assist.logical_address_scope.result_status IS
    'UNKNOWN for legacy handles, READY when at least one spatial match exists, EMPTY when no match exists.';
COMMENT ON VIEW
    dispatch_assist.logical_address_scope_summary IS
    'Lightweight handle status; it does not rerun or count the spatial result.';
COMMENT ON VIEW
    dispatch_assist.logical_address_scope_hotword_item IS
    'Narrow address-word projection; query by scope_id and stream only when required.';
COMMENT ON VIEW
    dispatch_assist.logical_address_scope_source_ref_item IS
    'Compact source-reference projection for address-bot follow-up queries.';

ANALYZE dispatch_assist.logical_address_scope;
