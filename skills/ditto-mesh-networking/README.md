# ditto-mesh-networking skill

AI agent skill covering [Ditto](https://ditto.com)'s peer-to-peer mesh: the network
transports, how peers discover each other and route updates, how the transport
configuration works and what changes when you update it at runtime, and how your transport
mix should shape your data model.

Works with any agent tool that supports the `SKILL.md` convention (Claude Code, opencode,
Codex, Gemini, etc.).

## Scope

This skill is **conceptual and configuration-model** guidance. It deliberately keeps code
to a minimum:

- **Per-language API syntax** — property names, builder shapes, permission calls — belongs
  in the Ditto SDK skill for that language. This skill describes the configuration
  *structure* that every SDK exposes, so the language skills only have to cover syntax.
- **Query syntax** belongs in the `write-dql` skill. The exception is the handful of
  `ALTER SYSTEM` / `system:` statements that configure transports, which are the same
  everywhere and are covered here.

## What's included

| File | Covers |
|---|---|
| [`SKILL.md`](SKILL.md) | Entry point: transports at a glance, the config model, runtime-update rules, how transports shape data modeling, anti-patterns |
| [`references/transports.md`](references/transports.md) | Per-transport deep dive — BLE, LAN, AWDL, Wi-Fi Aware, WebSocket, explicit TCP: range, bandwidth, discovery, platforms, failure modes, and how to choose a mix |
| [`references/transport-config.md`](references/transport-config.md) | Every configuration field, its default, and the exact semantics of updating the config while sync is running |
| [`references/mesh-formation.md`](references/mesh-formation.md) | The six-stage sync lifecycle, the multiplexer and rainbow connection, presence graph and multihop routing, connection caps, churn, sync groups |
| [`references/platform-requirements.md`](references/platform-requirements.md) | Permissions, entitlements, manifest entries, and OS prerequisites per platform, plus a diagnosis order |
| [`references/versions.md`](references/versions.md) | Which SDK version or which SDK each version-gated claim applies to |
| [`best-practices.md`](best-practices.md) | Designing data and transports together — document sizing, attachments, subscription scoping, and the checklist |
| [`examples/deployment-scenarios.md`](examples/deployment-scenarios.md) | Six worked deployments, each mapping a constraint to a transport config *and* a data model |

## Key ideas

- **The rainbow connection.** A peer runs several transports at once; the multiplexer pools
  every physical link to a given remote peer into one virtual connection and switches
  between them automatically. Leave transports enabled unless you have a measured reason
  not to.
- **A self-constructed `TransportConfig` starts with everything disabled.** Read-modify-write
  is the safe update pattern; building a fresh config to change one field is how teams take
  production transports down.
- **Runtime updates are diffed per transport.** Enabled→disabled drops that transport's
  connections immediately; unchanged transports are untouched; nothing is ever lost, because
  writes continue offline and CRDT merge reconciles on reconnect. The one exception is
  `global.syncGroup`, which forces an internal sync restart if changed while sync is active.
- **Transport choice reaches into your schema.** Bluetooth LE delivers roughly 20 KB/s, and
  both merge cost and document visibility are whole-document properties. If BLE is a
  transport you depend on, prefer many small documents; if it isn't, Ditto's default advice
  (embed related data) stands.

## Supported versions

Written against **Ditto SDK 4.14.x (LTS), 5.0.x, 5.1.x and 5.2.0**. **Last verified: 2026-09-02.**
Version- and SDK-specific behavior is tabulated in
[`references/versions.md`](references/versions.md).

## Verification status

Content is drawn from Ditto's public documentation and the Ditto core transport
implementation. Per-transport connection budgets are described by their relative ordering
rather than exact counts, because those are internal defaults that change between releases.
Platform gates and configuration defaults reflect current SDK behavior; version-sensitive
behavior is tabulated in [`references/versions.md`](references/versions.md).

This skill documents a handful of executable statements (`ALTER SYSTEM SET
TRANSPORTS_DISCOVERED_PEERS`, `mesh_chooser_*`, `document_size_*_limit_bytes`,
`SELECT ... FROM system:transports_info`). **They are not currently exercised by any test
harness** — the `tests/dql/` extractor only walks `skills/write-dql/`. Treat them as
documentation-verified, not execution-verified, and see the tracking note in
`CONTRIBUTING.md` before relying on exact syntax.

## Installation

See the agent-skills repository README for per-tool install instructions.
