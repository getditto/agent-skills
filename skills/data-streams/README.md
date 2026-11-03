# data-streams

Agent skill explaining **Ditto Data Streams**, the preview API for low-latency,
bidirectional raw-byte channels between two reachable peers over named topics. It covers
the concepts and lifecycle for every SDK that has the API; the Kotlin and Swift spelling
lives in those SDK skills.

**Language-agnostic.** Per-language code: [`skills/kotlin-sdk/references/data-streams.md`](../kotlin-sdk/references/data-streams.md)
and [`skills/swift-sdk/references/data-streams.md`](../swift-sdk/references/data-streams.md).

## What's inside

| File | Contents |
|---|---|
| `SKILL.md` | What streams are and are not, the seven-step lifecycle, reliability, send modes, setup, anti-patterns, routing |
| `references/lifecycle-and-ownership.md` | Every handle, who closes it, candidates and `take()`, receive-callback rules, shutdown order |
| `references/reliability-and-delivery.md` | Reliable vs unreliable, send statuses, backpressure, `maxSendSize`, arguments, compression |
| `references/setup-and-transports.md` | NGN switches (environment variables and 5.2.0 `systemParameters`), transports, presence discovery, platform notes |
| `references/troubleshooting.md` | Observed error strings and what fixes them |
| `examples/patterns.md` | Telemetry (docs quickstart), whiteboard (two topics, role by key order), push-to-talk (unreliable fan-out with send deadlines) |
| `best-practices.md` | Twelve rules before writing code |

## Supported versions

| SDK | Data Streams available | How |
|---|---|---|
| Kotlin | 5.1.0 and later (docs floor); classes also present in 5.0.3 | `@file:OptIn(com.ditto.kotlin.PreviewDataStreams::class)`, `ditto.dataStreams` |
| Swift | 5.2.0 and later only | `@_spi(PreviewDataStreams) import DittoSwift`, `ditto.dataStreams`; absent from 5.1.0 |
| Others | not documented | — |

Status: **Public Preview**, "may receive breaking changes without notice"
(<https://docs.ditto.live/sdk/latest/sync/data-streams>). Last verified: 2026-10-28.

## Verification

Claims marked **executed** come from two-peer fixtures that run two Ditto instances in one
process over a TCP loopback listener with NGN enabled:

- `tests/kotlin-sdk/minimal-app/src/test/kotlin/DataStreamsTest.kt` (JVM; CI matrix
  5.0.3 / 5.1.0 / 5.2.0 — see `tests/kotlin-sdk/README.md` for which versions the Data
  Streams tests apply to).
- `tests/swift-sdk/Tests/SwiftSDKSkillTests/DataStreamsTests.swift` (macOS, 5.2.0; compiled
  only when the fixture is pinned to 5.2.0).

Each fixture proves: bytes round-trip both ways on one reliable stream; `sendAndForget`
delivers; the monitoring overload reaches `Sent`; `closeSync`/`closeAndWait` is
`ClosedByRemote` on the other side; reliability mismatch is rejected; a borrowed candidate
is unusable after its callback while a taken one works; closing the acceptor leaves open
streams alive and new connects fail; invalid topics are rejected; one acceptor per topic;
arguments travel both ways; the receive callback is not on the main thread.

Docs-sourced claims cite <https://docs.ditto.live/sdk/latest/sync/data-streams>. Patterns
labelled "reference app" describe Ditto's whiteboard and push-to-talk sample apps and are
design guidance, not SDK contracts.

Not verified: multi-hop streams through an intermediate peer; Android-to-Android or
Apple-to-Android streams over Bluetooth LE or Wi-Fi Aware; behaviour under
`replication_over_ngn = true`.
