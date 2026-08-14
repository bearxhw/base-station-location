-- Read-only acceptance query. Exact counts are calculated only for explicit
-- verification; logical-scope creation itself uses a short-circuiting EXISTS.
-- Usage:
-- psql -v ready_scope=<uuid> -v empty_scope=<uuid> \
--   -f verify_address_scope_status.sql

\if :{?ready_scope}
\else
\echo 'ready_scope is required'
\quit
\endif

\if :{?empty_scope}
\else
\echo 'empty_scope is required'
\quit
\endif

SELECT scope.scope_id,
       scope.scope_status,
       scope.inventory_version,
       scope.expires_at
FROM dispatch_assist.logical_address_scope_summary scope
WHERE scope.scope_id IN (
    CAST(:'ready_scope' AS uuid),
    CAST(:'empty_scope' AS uuid))
ORDER BY scope.scope_id;

SELECT 'READY_ACTUAL_COUNT' AS metric,
       COUNT(*) AS metric_value
FROM dispatch_assist.logical_address_scope_item
WHERE scope_id = CAST(:'ready_scope' AS uuid)
UNION ALL
SELECT 'EMPTY_ACTUAL_COUNT',
       COUNT(*)
FROM dispatch_assist.logical_address_scope_item
WHERE scope_id = CAST(:'empty_scope' AS uuid)
ORDER BY metric;

SELECT event.aggregate_id AS scope_id,
       event.status AS outbox_status,
       event.retry_count,
       event.payload #>> '{addressScopeRef,scopeStatus}'
           AS event_scope_status
FROM dispatch_assist.outbox_event event
WHERE event.aggregate_id IN (
    CAST(:'ready_scope' AS uuid),
    CAST(:'empty_scope' AS uuid))
ORDER BY event.aggregate_id;
