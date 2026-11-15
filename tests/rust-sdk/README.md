# tests/rust-sdk — executable evidence for the `rust-sdk` skill

## Contents

- [Layout](#layout)
- [Running](#running)
- [What each suite proves](#what-each-suite-proves)
- [Editing published code](#editing-published-code)
- [Prerequisites and pitfalls](#prerequisites-and-pitfalls)

Every Rust code block the skill publishes (except the `SKILL.md` excerpt and three
"wrong form" fragments) is generated from files here by `scripts/sync-snippets.py`, and
every behavioural claim marked *executed* is an assertion in one of these tests.

## Layout

```
tests/rust-sdk/
├── minimal-app/               # Cargo project; the committed pin is the baseline (5.2.0)
│   ├── Cargo.toml  Cargo.lock  rust-toolchain.toml  .cargo/config.toml
│   ├── src/main.rs            # examples/minimal-app.md (whole file)
│   └── tests/
│       ├── behavior.rs        # threads, drop semantics, back-pressure, panics, errors
│       ├── async_semantics.rs # first-poll completion, cancellation, deadlock, defaults
│       ├── patterns.rs        # references/tokio.md snippets + their tests
│       └── reference_samples.rs # every other reference snippet + tests
├── v4-app/                    # 4.14.7: DittoConfig, *_v2 methods, disable_sync_with_v3
└── scripts/run-fixture.sh     # runs minimal-app against any SDK version
```

## Running

```bash
# Baseline (the committed pin):
tests/rust-sdk/scripts/run-fixture.sh
# Another version, on a temporary copy (the committed files stay unchanged):
tests/rust-sdk/scripts/run-fixture.sh 5.1.0
# The v4 fixture:
(cd tests/rust-sdk/v4-app && cargo run)
```

`DITTO_OFFLINE_LICENSE` comes from the environment or the repo-root `.env`. Builds
go to `tests/rust-sdk/.target/<version>/` (gitignored) so versions do not evict each
other. The script asserts the minimal app's three output lines and then runs every
test with `--test-threads=1`.

CI: `.github/workflows/rust-skill-tests.yml` runs 5.0.4, 5.1.0 and 5.2.0 on Ubuntu, plus
`cargo fmt --check`, `cargo clippy --all-targets -- -D warnings` and the 4.14.7 fixture.

## What each suite proves

- **behavior.rs** — observer callbacks run on Ditto threads without a Tokio context;
  the initial callback; dropping an observer or subscription `Arc` does not cancel it,
  `cancel()` does; `signal_next` coalescing; plain-`INSERT` conflict text; non-`SELECT`
  observers; `NotActivated`; current-thread runtimes; transaction rollback rules;
  integer round-trips; index/EVICT; `system:data_sync_info`; log callback, disk usage
  and presence; error kinds (syntax, read-only transaction, bad license, null system
  parameter); a second open of a locked directory; the expiration handler's first call
  and thread; and, in child processes, that panics abort after `Ditto::open` (callbacks,
  `tokio::spawn` tasks, even with an app hook for callbacks) but not before it.
- **async_semantics.rs** — `execute` completes inside its first poll and is lazy;
  dropping `signal_next` stalls the observer; the acked bridge paces delivery;
  cancelling a transaction wedges later ones; cancelling `Ditto::open` aborts;
  `store().execute` inside a transaction deadlocks; `TransportConfig::default() != new()`;
  attachments with and without the `ATTACHMENT` declaration.
- **patterns.rs / reference_samples.rs** — the published code runs: the guard, the
  observer bridge, `spawn_blocking`, shared state, shutdown, typed queries, upserts,
  a PN-counter transaction, subscriptions, `Differ`, attachments, presence, logging,
  disk usage, error matching, transports, the test harness and support bundles
  (5.2.0; asserted absent on older lines).

Version-dependent behaviour is asserted per version (`Ditto::version()`), so a change in
a new SDK release fails here before the skill goes stale.

## Editing published code

Edit the marked region in these files (`// snippet:start <name>` … `// snippet:end <name>`),
then run `python3 scripts/sync-snippets.py` from the repo root. CI runs it with
`--check`. Keep `cargo fmt` and `cargo clippy --all-targets -- -D warnings` clean: the
published code is what Rust developers will paste.

## Prerequisites and pitfalls

- **rustc 1.91.0** via `rust-toolchain.toml`; 1.98+ cannot compile `dittolive-ditto-sys`.
  A Homebrew `cargo` earlier on `PATH` ignores rustup's pin — put `~/.cargo/bin` first.
- **Linux** needs `.cargo/config.toml`'s `--allow-multiple-definition` flag to link.
- The first build downloads `libdittoffi.a` (110–200 MB) with `curl`.
- Child-process tests report through exit codes and use watchdogs; a hang becomes a
  failure, not a stuck CI job.
- Once Ditto is open, a failing assertion aborts the whole test binary. Use
  `--exact <name>` (or `cargo nextest`) to isolate a failure.
