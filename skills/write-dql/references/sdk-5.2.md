# DQL in SDK 5.2.0

5.2.0 is the latest known baseline, not a permanent “latest” dependency pin.
JOINs, composite indexes, RETURNING and ADVISE still require 5.1+; the following
changes require **5.2.0**. Validate the actual resolved SDK for newer releases.

## Mutation and planner fixes

`DELETE FROM collection USE IDS 'a', 'b'` and `EVICT FROM collection USE IDS 'a', 'b'`
now remove the selected documents. In 5.1.0 they parsed but removed nothing; on
4.14.6/5.0.3 they are parse errors. `WHERE _id IN (…)` remains portable. DELETE
replicates deletion; EVICT removes only the local copy. Check read-back state when
validating mutations, not just parser success or mutation result row counts.

5.2 also fixes mixed ASC/DESC composite-index ordering, full-document fetches for
indexed SELECT *, constant-on-left index span comparisons, and multi-property
`ANY … SATISFIES` conditions. Recheck affected query results after upgrading; these
are correctness fixes, not new syntax gates.

The release notes also report a fix for projection-alias `ORDER BY` in plans that
sort **before fetching documents**. That specific planner fix is source-reviewed:
the local harness checks general alias ordering, but its query also passes on 5.1.0
and does not exercise a sort-before-fetch plan.

## Diagnostics

- `SELECT * FROM system:sync_degradations` lists documents with degraded sync.
- `EXECUTE FUNCTION system_request_support_bundle()` generates a local support
  bundle. It is **unavailable in JS Web**. Use the app's authorized diagnostic path;
  running it on one peer does not itself broadcast a command to other peers.
- `SELECT * FROM system:support_bundles` lists retained bundles. Rate, timeout and
  retention parameters bound capture. A bundle can contain sensitive diagnostics.
- `system:metrics` adds query request/failure/execution-time, transport-health and
  DSOQ counters. Most virtual-collection observers are now change-driven, not timers.
- Preview `system_trace_sync_propagation()` requests traces for subsequent changes
  **in the same write transaction**; Big Peer propagation tracing is unsupported.
  Consult the release's API before constructing transaction code; do not present it
  as a stable cross-version tracing API.

## Startup system parameters

Use the language's `DittoConfig.systemParameters` before opening for startup-only
settings. Invalid names/types fail at open. `ALTER SYSTEM SET` still changes runtime
settings; it does not persist overrides across app restart. `ngn_data_streams_enabled`
and `ngn_sync_enabled` replace the deprecated NGN names; sync true with streams false
now fails at sync start. Do not change these flags just to run ordinary DQL queries.

Sources: [5.2 common release notes](https://docs.ditto.live/sdk/latest/release-notes-hub/swift),
[virtual collections](https://docs.ditto.live/dql/virtual-collections),
[support bundles](https://docs.ditto.live/sdk/latest/deployment/support-bundles).
The DQL catalog and `tests/dql/runner/sdk52.mjs` validate local query behavior; radio,
Big Peer and production diagnostic workflows require their own integration checks.
