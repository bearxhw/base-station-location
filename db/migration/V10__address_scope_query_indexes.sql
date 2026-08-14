-- Pure-query path: accelerate text subqueries inside a location scope.
-- No per-alarm address tables or rows are created by this migration.

CREATE INDEX IF NOT EXISTS idx_address_inventory_term_normalized_trgm
    ON dispatch_assist.address_inventory_term
    USING GIN (normalized_term gin_trgm_ops);

ANALYZE dispatch_assist.address_inventory;
ANALYZE dispatch_assist.address_inventory_term;
