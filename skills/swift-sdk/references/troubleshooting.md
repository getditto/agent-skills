# Troubleshooting a Ditto Swift integration

First separate package/build, launch, local database, authentication, and peer-sync
failures. Collect the resolved SDK pin, target OS, destination, relevant operation
error and ownership boundary. Request a small redacted excerpt; do not request tokens
or a whole persistence directory. Change one demonstrated cause at a time.

## Build and launch

| Symptom | Inspect | Action |
|---|---|---|
| Package cannot resolve or symbols differ | Resolved package version, toolchain, deployment floor | Match API forms to the pin; see [versions.md](versions.md), not a guessed latest API |
| Script missing after installation | Installed `swift-sdk/scripts/` and `assets/` | Install the complete skill directory/package; a lone `SKILL.md` is insufficient |
| `dyld` reports an unsigned Ditto framework | Loader error and target signing settings | Restore enabled signing and embedded frameworks; use ad-hoc signing for local builds; see [setup.md](setup.md#code-signing-and-the-embedded-xcframework) |
| Physical iOS install needs a profile | Target Signing & Capabilities, team and bundle ID | Select the user's development team; Simulator signing is not physical-device provisioning |
| Starter reports missing configuration | `App/LocalConfig.plist` bundled resource | Set both values locally, then rebuild; after cloning, copy the example file first |

## Local data and UI

| Symptom | Inspect | Action |
|---|---|---|
| Persistence directory locked | Multiple instances/processes using the same directory | Keep one app-lived instance per directory; close its owner before reopening; do not delete the store |
| Insert succeeds but list is unchanged | Observer query/arguments and retained handle | Confirm the local observer matches the document; do not patch the list manually to hide a broken observer |
| Old results replace newer results | Task created per callback, cross-actor payload | Decode Sendable values in the callback and use one bounded-stream consumer; see [concurrency.md](concurrency.md) |
| Callback continues after screen closes | Handle cancellation, captured owners | Explicitly cancel screen-scoped observers/subscriptions; app-scoped ownership can intentionally outlive the screen |
| v4 write/read behaves differently | Strict-mode state and v3-sync compatibility | Use the 4.14.x branch in [versions.md](versions.md); avoid replaying deprecated v4 calls on v5 |

## No remote documents

Work through the chain in order:

1. **Local operation:** does each peer read back its own write? Capture its actual
   error first. Peer networking cannot repair a failed local operation.
2. **Identity:** do peers use the intended database and compatible identity/license
   configuration? For server mode, inspect login completion and expiration handling
   from [connect.md](connect.md). Keep credentials redacted.
3. **Subscription:** does the receiving peer retain a subscription that matches the
   missing document? An observer reads the local store; it does not request remote data.
4. **Presence:** inspect remote peers and connection types. `sync.isActive` only says
   sync was started. An empty graph is not proof that an auth handler ran or succeeded.
5. **Transport/permissions:** compare actual devices and OS support. Check local-network
   and Bluetooth grants, Bonjour entries, Mac sandbox network entitlements and the
   reachable LAN/firewall. Do not infer BLE/AWDL support from a Simulator result.
6. **Path and holdings:** an intermediate peer must hold the document and subscriptions
   must permit propagation. A server helps only if it holds the missing data and is
   permitted to deliver it. Consult the subscription concept skill or the official
   [sync guidance](https://docs.ditto.live/sdk/latest/sync/syncing-data).

Use [presence.md](presence.md) and [observability.md](observability.md) to gather a
small diagnostic snapshot. Distinguish current observed connections from configured
transports, and a successful local commit from mesh-wide convergence. Do not expose
credentials in diagnostic UI, logs or support exports.

## Starter diagnostics and limits

The generated Diagnostics screen exposes local readiness, store path, displayed
document count, last observer delivery, requested sync state, remote peer count,
observed connection types and the last operation error. Refresh it for a new presence
snapshot. It does not claim server login state, replication completeness or a
transport-specific health check. Pause/resume stops/starts SDK sync while leaving
the local database usable; it is a simulation, not an OS network-loss test.

Technical sources: [Swift installation](https://docs.ditto.live/sdk/latest/install-guides/swift),
[mesh presence](https://docs.ditto.live/sdk/latest/sync/using-mesh-presence),
[transport configuration](https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations).
