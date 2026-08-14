-- Address terms are derived once when the global inventory is synchronized.
-- Per-alarm subsets store membership only and reuse these immutable terms.

CREATE TABLE IF NOT EXISTS dispatch_assist.address_inventory_term (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inventory_id UUID NOT NULL
        REFERENCES dispatch_assist.address_inventory(id)
        ON DELETE CASCADE,
    term VARCHAR(1024) NOT NULL,
    normalized_term VARCHAR(1024) NOT NULL,
    term_type VARCHAR(16) NOT NULL,
    weight INTEGER NOT NULL,
    CONSTRAINT ck_address_inventory_term_type CHECK (
        term_type IN (
            'STANDARD',
            'SHORT',
            'ALIAS',
            'FULL_ADDRESS',
            'AOI',
            'ROAD'
        )
    ),
    CONSTRAINT ck_address_inventory_term_weight CHECK (
        weight BETWEEN 1 AND 100
    ),
    CONSTRAINT uk_address_inventory_term UNIQUE (
        inventory_id,
        normalized_term
    )
);

CREATE INDEX IF NOT EXISTS idx_address_inventory_term_load
    ON dispatch_assist.address_inventory_term (inventory_id, id);

CREATE INDEX IF NOT EXISTS idx_address_subset_item_inventory
    ON dispatch_assist.address_subset_item (
        subset_id,
        rank_no,
        inventory_id
    );

INSERT INTO dispatch_assist.address_inventory_term (
    inventory_id,
    term,
    normalized_term,
    term_type,
    weight
)
SELECT inventory.id,
       term_source.term,
       regexp_replace(
           lower(btrim(term_source.term)),
           '[[:space:][:punct:]]+',
           '',
           'g'),
       term_source.term_type,
       term_source.weight
FROM dispatch_assist.address_inventory inventory
CROSS JOIN LATERAL (
    SELECT inventory.standard_name AS term,
           'STANDARD' AS term_type,
           100 AS weight
    UNION ALL
    SELECT inventory.short_name,
           'SHORT',
           95
    UNION ALL
    SELECT inventory.full_address,
           'FULL_ADDRESS',
           90
    UNION ALL
    SELECT inventory.aoi_name,
           'AOI',
           80
    UNION ALL
    SELECT inventory.road_name,
           'ROAD',
           80
    UNION ALL
    SELECT alias.value,
           'ALIAS',
           95
    FROM jsonb_array_elements_text(inventory.aliases)
            AS alias(value)
) term_source
WHERE inventory.active = TRUE
  AND term_source.term IS NOT NULL
  AND btrim(term_source.term) <> ''
ON CONFLICT DO NOTHING;

ANALYZE dispatch_assist.address_inventory_term;
