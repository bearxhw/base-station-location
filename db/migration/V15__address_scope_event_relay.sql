-- Reliable handle-only notification for reusable logical address scopes.
-- Address rows remain in address_inventory and are never copied to outbox.

CREATE INDEX IF NOT EXISTS idx_outbox_address_scope_relay
    ON dispatch_assist.outbox_event (
        event_type,
        status,
        next_retry_at,
        locked_at,
        created_at
    )
    WHERE event_type = 'address.scope.ready.v1'
      AND status IN ('NEW', 'FAILED', 'PROCESSING');

COMMENT ON INDEX dispatch_assist.idx_outbox_address_scope_relay IS
    'Supports SKIP LOCKED relay of handle-only address.scope.ready.v1 events.';
