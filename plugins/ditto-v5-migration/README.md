# ditto-v5-migration

Claude Code plugin providing per-platform skills for migrating Ditto SDK applications from **v4.14 to v5.0**.

## Available Skills

| Skill | Platform | Key Topics |
|-------|----------|------------|
| `migrate-swift` | Swift / iOS / macOS | `Ditto.open(config:)`, AsyncSequence observers, `expirationHandler` closure, `DittoStoreObservationHandlerWithSignalNext` back pressure |
| `migrate-kotlin` | Kotlin / Android | Package rename (`live.ditto.*` → `com.ditto.kotlin.*`), `.toDittoCbor()`, Flow observers, coroutine suspension back pressure |
| `migrate-cpp` | C++ | Header reduction (83→50), `Logger` rename, `StoreObservationHandlerWithSignalNext` / `SignalNext` back pressure |
| `migrate-rust` | Rust | `_v2` suffix removal, `AppId`→`DatabaseId`, `register_observer_with_signal_next` back pressure |
| `migrate-flutter` | Flutter / Dart | `Ditto.open()`, `remotePeers` List→Set, isolate-unsendable, back pressure handled internally |
| `migrate-js` | JavaScript / TypeScript / Node.js / React Native | `Ditto.open()` factory, `Store.transaction()`, `registerObserverWithSignalNext` back pressure |
| `migrate-dotnet` | .NET / C# | ~65 API removals, `WifiAwareConfig`, namespace reorganization, `Action<DittoQueryResult, Action>` back pressure |
| `migrate-go` | Go | New SDK in v5 — no v4 equivalent, goroutine-safe DQL API, `RegisterObserverWithSignalNext` back pressure |

Every skill also covers the universal v4→v5 changes and DQL Query Builder migration.

## Installation

### 1. Add the Ditto marketplace

```bash
/plugin marketplace add getditto/claude-code-plugins
```

### 2. Install this plugin

```bash
/plugin install ditto-v5-migration
```

### 3. Use a skill

In your Claude Code session, load the appropriate platform skill:

```
Use the migrate-swift skill to help me update this file
```

or reference it in a prompt:

```
I need to migrate this Kotlin file from Ditto v4 to v5. Load the migrate-kotlin skill and update the code.
```

## What the Skills Cover

Each skill provides Claude with:

1. **Universal v4→v5 changes** — `DittoConfig` initialization, `sync.start()`, auth handler closure, persistence directory, peer key rename
2. **DQL strict mode warning** — v5 defaults to `DQL_STRICT_MODE=false` (v4 default was `true`). This is a **silent breaking change**.
3. **Platform-specific breaking changes** — exact API renames, removals, and replacements
4. **DQL migration** — complete mapping from legacy Query Builder (`.collection().find()`) to DQL (`store.execute()`)
5. **Back-pressure observer pattern** — `SignalNext` / `registerObserverWithSignalNext` for each platform; coalescing behavior explained
6. **APIs removed without replacement** — per-platform table of removed APIs with no v5 equivalent
7. **New APIs in v5** — per-platform list of new additions
8. **Migration checklist** — checkbox list of every required change
9. **Common pitfalls** — errors developers commonly make during migration

## Related Plugins

- [ditto-dql](../ditto-dql) — Expert DQL query writing and optimization (independent of migration)

## Official Documentation

- Migration guides: https://docs.ditto.live/sdk/latest/migration-guides
- DQL reference: https://docs.ditto.live/dql/dql
