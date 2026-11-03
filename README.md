# Agent Skills for Ditto

AI agent skills for [Ditto](https://ditto.com) — the peer-to-peer sync platform.
Skills follow the cross-tool [`SKILL.md`](docs/SKILLS-TEMPLATE.md) convention and
work with **Claude Code, opencode, Codex, Gemini**, and any other agent tool that
loads skills.

**Note: This repo is currently private, but we intend to make it PUBLIC for
customer use. Do not add skills or content that are not appropriate for
customer use.**

## Available skills

| Skill | Claude Code plugin | Description |
|-------|--------------------|-------------|
| [write-dql](skills/write-dql) | `ditto-dql` | DQL (Ditto Query Language) assistance for queries, subscriptions, and data operations. Covers Ditto SDK 4.14.x (LTS), 5.0.x, and 5.1.x (JOINs, composite indexes, RETURNING, ADVISE). |
| [ditto-mesh-networking](skills/ditto-mesh-networking) | `ditto-mesh` | Peer-to-peer mesh and transports — Bluetooth LE, LAN/mDNS, AWDL, Wi-Fi Aware, WebSocket, explicit TCP. Peer discovery and multihop routing, the transport configuration model and its runtime-update semantics, and how transport choice shapes your data model. |
| [sync-subscriptions](skills/sync-subscriptions) (`sync-subscriptions`) | `ditto-subscriptions` | How Ditto sync subscriptions work: query rules and limitations, mesh propagation, multi-hop flooding, and troubleshooting missing documents. Covers Ditto SDK 4.14.x (LTS), 5.0.x, and 5.1.x. |
| [data-streams](skills/data-streams) (`data-streams`) | `ditto-data-streams` | Ditto Data Streams (preview): low-latency, bidirectional raw-byte channels between two peers over named topics — lifecycle, candidate ownership, reliable vs unreliable, NGN setup, troubleshooting. Kotlin 5.1.0+ and Swift 5.2.0+ (SPI); code in the SDK skills. |
| [data-modeling](skills/data-modeling) (`data-modeling`) | `ditto-data-modeling` | CRDT-aware data modeling: REGISTER/MAP/COUNTER/ATTACHMENT semantics, embed-vs-split decisions, document size budgets, and raw-JSON review. Covers Ditto SDK 4.14.x (LTS) and 5.0.x/5.1.x. |
| [kotlin-sdk](skills/kotlin-sdk) (`kotlin-sdk`) | `ditto-kotlin` | Ditto Kotlin SDK for Android and JVM: Gradle setup, connecting, authentication, transports, subscriptions, DQL execution, observers with coroutines/Flow, attachments, presence, and testing. Covers Ditto SDK 4.14.x (LTS), 5.0.x, and 5.1.x. |
| [swift-sdk](skills/swift-sdk) (`swift-sdk`) | `ditto-swift` | Ditto Swift SDK for iOS, iPadOS, macOS (AppKit) and Mac Catalyst: `DittoConfig`/`Ditto.open`, sync and subscriptions, DQL execution, store observers and `DittoDiffer`, attachments, presence, Swift 6 concurrency and object lifetimes. Covers Ditto SDK 4.14.x (LTS), 5.0.x, and 5.1.x. |

## Repository layout

```
skills/          Canonical skills (the portable unit: SKILL.md + references/ + examples/)
agents/<plugin>/ Portable agent definitions (markdown), namespaced per plugin
tests/<skill>/   Executable verification for each skill's documented examples
plugins/         Thin scoped wrappers and host metadata; canonical content stays in skills/
docs/            Contributor docs (skill templates, SDK skill spec, plans)
```

Skill content lives exactly once in `skills/`. Everything tool-specific wraps
or points at it.

## Releases

Tags (`v*`) publish a GitHub release via the [Release workflow](.github/workflows/release.yml)
with two assets:

- **`ditto-skills.tar.gz`** — a slim archive of `skills/` + `LICENSE.md` +
  `skills-manifest.json`. This is what the Ditto CLI downloads for
  `dittosh skills add|update`; it excludes `tests/`, `docs/`, `plugins/` and
  other repo-only directories, so installs stay fast as the test suites grow.
- **`skills-manifest.json`** — every skill's name, path, and description,
  parsed from the `SKILL.md` frontmatter, for tooling that lists available
  skills without downloading the archive.

Cut a release by pushing a tag (`git tag v1.0.0 && git push origin v1.0.0`)
or from the Actions tab (Release workflow → Run workflow). The workflow runs
`scripts/validate-sdk-skills.py` first and refuses to publish a broken skill.

## Swift getting started

The Swift skill includes a runnable SwiftUI project generator, diagnostics screen,
and getting-started/deliverables/troubleshooting references. It can also integrate
an existing Swift app in place.

**[Install Ditto Swift in your agent](docs/install-swift.md)** — Claude Code and Desktop,
Codex CLI and Desktop, Cursor, Copilot CLI, Antigravity CLI, Gemini CLI and OpenCode.
Standalone packages and per-skill upload ZIPs are generated from the canonical skill.

## Kotlin getting started

The Kotlin skill covers Android (4.14.x and 5.x) and the JVM (5.x): Gradle setup,
coroutine-native observers, lifetimes and threading, plus a Gradle project-generation
guide. Its JVM fixture runs in CI against 5.0.3, 5.1.0 and 5.2.0.

**[Install Ditto Kotlin in your agent](docs/install-kotlin.md)** — the same hosts as
Swift; standalone packages are generated with `--plugin ditto-kotlin`.

## Installation by tool

For the SDK skills, use the host-specific guides ([Swift](docs/install-swift.md),
[Kotlin](docs/install-kotlin.md)) for local/PR packages, activation, updates and
removal. Existing concept skills retain the routes below.

### Claude Code

Install via the bundled plugin marketplace (backed by thin wrappers in
`plugins/`). **Each plugin ships only its own skill** — install just the ones
you want:

```bash
/plugin marketplace add getditto/agent-skills

/plugin install ditto-dql            # DQL skill + dql-expert agent
/plugin install ditto-mesh           # ditto-mesh-networking skill
/plugin install ditto-subscriptions  # sync-subscriptions skill
/plugin install ditto-data-modeling  # data-modeling skill
/plugin install ditto-data-streams   # data-streams skill
/plugin install ditto-kotlin         # kotlin-sdk skill
/plugin install ditto-swift          # swift-sdk skill
```

`.claude-plugin/marketplace.json` → `plugins/<plugin>/.claude-plugin/plugin.json`
→ per-item symlinks into `skills/` and `agents/<plugin>/`. A wrapper never
symlinks the whole `skills/` tree, so adding a skill to the repo does not
change what an already-installed plugin provides.

### opencode

The repo ships `.opencode/opencode.json` with `skills.paths: ["./skills"]`,
so opening this repo in opencode loads the skills automatically.

For global use, copy or symlink the skill into `~/.agents/skills/` or set
`skills.paths` in `~/.config/opencode/opencode.jsonc`:

```bash
# link only the skills you want
ln -s "$(pwd)/skills/write-dql" ~/.agents/skills/write-dql
ln -s "$(pwd)/skills/ditto-mesh-networking" ~/.agents/skills/ditto-mesh-networking
```

### Codex / Gemini / other tools

Any tool that supports the `SKILL.md` convention (a directory of skills, each
with YAML `name` + `description` frontmatter) can load these. Point the tool's
skills directory at this repo's `skills/` folder, or copy/symlink the
individual skill directory into the tool's expected location, e.g.:

```bash
# Codex — link only the skills you want
ln -s "$(pwd)/skills/write-dql" ~/.agents/skills/write-dql
ln -s "$(pwd)/skills/ditto-mesh-networking" ~/.agents/skills/ditto-mesh-networking
```

Consult your tool's documentation for its skills directory location.

**Windows contributors:** use copy instead of symlink unless your Git install
has symlink support enabled.

## MCP servers

The repo provides MCP server endpoints for enhanced Ditto assistance:

| Server | Endpoint | Description |
|--------|----------|-------------|
| `ditto-docs` | <https://docs.ditto.live/mcp> | Access Ditto documentation directly |

- **Claude Code / Claude-format tools**: `.mcp.json` at the repo root is
  picked up automatically (via `mcp-remote`).
- **Other tools**: add the same endpoints using your tool's MCP config
  ([example opencode config](https://opencode.ai/docs/mcp-servers/)).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a new skill and
[docs/SKILLS-TEMPLATE.md](docs/SKILLS-TEMPLATE.md) for the skill template.

## About Ditto

Ditto is a mobile database with built-in edge device connectivity and
resiliency. It enables apps to synchronize without relying on a central
server or constant cloud connectivity using:

- **CRDTs** for automatic conflict resolution
- **Peer-to-peer mesh** networking
- **DQL** — a SQL-like query language
- **Offline-first** architecture

Learn more at [docs.ditto.live](https://docs.ditto.live).

## License

MIT
