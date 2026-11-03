# Install the Ditto Swift skill

The `ditto-swift` plugin ships the `swift-sdk` skill, including its references,
project generator and starter assets. The skill supports Swift on Apple platforms;
the agent/plugin can be installed on other operating systems, but building the app
requires a Mac with Xcode. Installing a skill does not install or license the Ditto
SDK. No Kotlin skill, cloud credentials, hooks or MCP servers are bundled.

## Contents

- [Choose an installation](#choose-an-installation)
- [Build standalone packages](#build-standalone-packages)
- [Claude Code and Claude Desktop](#claude-code-and-claude-desktop)
- [Codex CLI and Desktop](#codex-cli-and-desktop)
- [Cursor](#cursor)
- [GitHub Copilot CLI](#github-copilot-cli)
- [Antigravity CLI](#antigravity-cli)
- [Gemini CLI](#gemini-cli)
- [OpenCode and direct skill installation](#opencode-and-direct-skill-installation)
- [Activation and getting started](#activation-and-getting-started)
- [Updates and removal](#updates-and-removal)
- [Installation troubleshooting](#installation-troubleshooting)
- [Maintainer notes and sources](#maintainer-notes-and-sources)

## Choose an installation

| Host | Native route | Offline/local fallback |
|---|---|---|
| Claude Code CLI / Claude Desktop Code tab | Marketplace + `ditto-swift` | Local marketplace directory |
| Claude Desktop Customize | Add marketplace and install `ditto-swift` | Upload `swift-sdk.zip` as a skill |
| Codex CLI / Desktop | Marketplace + plugin browser | Materialized local marketplace |
| Cursor | Team marketplace on Teams/Enterprise | Materialized local plugin, when local imports are allowed |
| GitHub Copilot CLI | Plugin marketplace | Local plugin directory |
| Antigravity CLI | Local native plugin package | Workspace plugin directory |
| Gemini CLI | Local extension package | Direct native skill installation |
| OpenCode / other Agent Skills hosts | Direct skill directory | Copy instead of symlink |

GitHub installation requires access to `getditto/agent-skills` while the repository
is private. The GitHub steps below load the published branch; for an unmerged PR,
use the local package flow from that checkout. Public-directory listing/review is
separate from installing a GitHub or local marketplace.

## Build standalone packages

From an accessible clone, using Python 3.9+ (Windows: substitute `py -3`):

```bash
git clone https://github.com/getditto/agent-skills.git
cd agent-skills
python3 scripts/package-sdk-plugin.py --plugin ditto-swift --output dist/swift
```

For an existing checkout, start at the Python command. Choose a fresh output directory
for each build; the packager refuses to overwrite an existing output. It generates:

| Output | Use |
|---|---|
| `ditto-swift-marketplace/` and matching ZIP | Local catalogs for Claude, Codex, Cursor and Copilot |
| `ditto-swift-marketplace/plugins/ditto-swift/` | Standalone Agent Plugin with host compatibility metadata |
| `ditto-swift-plugin.zip` | Same standalone plugin, rooted at `ditto-swift/` |
| `ditto-swift-antigravity/` and matching ZIP | Antigravity manifest and real skill files |
| `ditto-swift-gemini/` and matching ZIP | Gemini extension and real skill files |
| `swift-sdk.zip` | Per-skill upload, rooted at `swift-sdk/SKILL.md` |
| `SHA256SUMS` | Archive checksums |

ZIP files are distribution artifacts: extract them before using a CLI that expects a
directory. The standalone packages contain real files and need no repository symlinks.
They preserve only the Swift plugin's declared contents. Maintainer links to repository
docs/tests are rewritten to GitHub; runtime references and assets remain local. The generated package manifest
records file hashes; hashes establish content identity, not model-answer correctness.

## Claude Code and Claude Desktop

In Claude Code CLI or the Desktop **Code** tab:

```text
/plugin marketplace add getditto/agent-skills
/plugin install ditto-swift@ditto-plugins
```

For a PR/local package, replace the marketplace source with the absolute path to
`dist/swift/ditto-swift-marketplace`. Run `/plugin` to inspect the installed skill.

In Desktop **Customize → Plugins**, add the repository as a marketplace and install
**Ditto Swift**. Where the UI does not offer marketplace installation, use **Skills →
Upload a skill** with the generated `swift-sdk.zip`. That fallback imports the skill,
not plugin metadata or MCP wiring. Start a new session after changing installations.

## Codex CLI and Desktop

```bash
codex plugin marketplace add getditto/agent-skills
```

Start Codex, open `/plugins` and install **Ditto Swift**. For a PR/local package,
register the absolute `ditto-swift-marketplace` directory instead of the GitHub source.
The native catalog is `.agents/plugins/marketplace.json`; its plugin path resolves
relative to the marketplace root.

In a desktop client exposing **Plugins → Add marketplace**, add that same source and
install **Ditto Swift**. Desktop surfaces vary by release/account; the local marketplace
and direct `.agents/skills` installation below are alternatives. The package supplies
display metadata and example prompts; it does not grant tool permissions.

## Cursor

On Teams/Enterprise, open **Dashboard → Plugins & MCPs → Team Marketplaces → Add
Marketplace → Import from Repo** and enter the repository URL. Enterprise requires an
admin. After import, install **ditto-swift** from Customize.

For a local install, copy the entire materialized
`ditto-swift-marketplace/plugins/ditto-swift/` directory to
`~/.cursor/plugins/local/ditto-swift/`, then restart Cursor or run **Developer: Reload
Window**. Confirm `swift-sdk` appears in Customize. Local imports must be allowed by
the client/team policy; Enterprise disables them by default. Do not symlink to a
directory outside `~/.cursor/plugins/local/`, because Cursor skips that link.

The repository supplies a Cursor catalog/manifest and a portable Agent Plugins
manifest. Public marketplace publication requires a separate review; these files do
not establish a public listing. See [Cursor's installation guide](https://cursor.com/docs/plugins).

## GitHub Copilot CLI

```bash
copilot plugin marketplace add getditto/agent-skills
copilot plugin install ditto-swift@ditto-plugins
copilot plugin list
```

For a local package, install the absolute path to
`ditto-swift-marketplace/plugins/ditto-swift` with `copilot plugin install`. The repo
provides `.github/plugin/marketplace.json`; Copilot also supports Claude-compatible
catalogs. Start a fresh session and inspect skill discovery.

## Antigravity CLI

Install the generated native package from a local directory:

```bash
agy plugin install ./dist/swift/ditto-swift-antigravity
agy plugin list --json
```

Alternatively, copy the whole generated plugin directory into a project's
`.agents/plugins/ditto-swift/`. Keep its `plugin.json` and `skills/` together.
The native manifest is deliberately separate from the portable Agent Plugins schema.
This route does not assume the CLI can select a nested plugin from a GitHub monorepo.

## Gemini CLI

```bash
gemini extensions install ./dist/swift/ditto-swift-gemini
gemini extensions list
```

Restart Gemini and inspect its available skills. This extension contains a real
`skills/swift-sdk/` tree and is Swift-only; installing the repository root as an
extension would not provide this scoped package. Gemini extensions support skills;
an MCP server is not required. Review normal installation consent prompts.

## OpenCode and direct skill installation

Copy `ditto-swift-marketplace/plugins/ditto-swift/skills/swift-sdk/` into the chosen
host's skill directory. Include `references/`, `scripts/` and `assets/`, not only
`SKILL.md`. For Codex and OpenCode, `.agents/skills/swift-sdk/` in a project or
`~/.agents/skills/swift-sdk/` for personal use are supported discovery locations.
OpenCode can also use `skills.paths`; this repository retains its existing config.
On Windows use a directory copy, avoiding symlink privilege requirements.

The host discovers the skill; the chosen model (including Kimi through OpenCode)
uses it. Skill installation and model availability/context budgets are separate.
Avoid installing the same skill both directly and through a plugin in one host;
duplicate registrations can produce ambiguous skill selectors.

## Activation and getting started

Confirm `swift-sdk` appears in the host's skill catalog (plugin hosts may namespace
it with `ditto-swift`). Use: **“Use the Ditto Swift skill to create a runnable SwiftUI
notes app with a diagnostics screen.”** The model should read the getting-started
reference and locate the installed generator/assets. Keep SDK integration requests
in the existing app; app generation is a conditional workflow.

The starter's README covers configuration and opening the generated Xcode project.
Generating files, compiling, launching and observing two-peer sync are separate
outcomes. A successful installation alone establishes none of the latter.

## Updates and removal

Use the host's plugin/extension update and uninstall controls for the installed source.
Examples: `copilot plugin update ditto-swift`, `copilot plugin uninstall ditto-swift`,
`gemini extensions update ditto-swift`, `gemini extensions uninstall ditto-swift`,
`agy plugin uninstall ditto-swift`. Claude/Codex/Cursor expose plugin management in
their plugin UI; Codex's `plugin marketplace upgrade` refreshes registered catalogs.
Rebuild/reinstall local packages to incorporate source changes. Direct folder copies
must be replaced or removed at their actual installation path. Updating a skill does
not change a generated customer's app or upgrade its pinned SDK.

## Installation troubleshooting

| Symptom | Check |
|---|---|
| Repository inaccessible | GitHub access/authentication; local package while the repo is private |
| Plugin absent from catalog | Correct host catalog, source root, published branch and refreshed session |
| Skill listed twice | Direct installation plus plugin installation; keep one registration |
| Only instructions installed | Copy the complete skill directory or use the generated archive |
| Generator cannot execute | Host command-tool availability/policy and Python 3.9+; respect managed approvals |
| Broken symlink after copying | Use a materialized package; a copied thin wrapper is not standalone |
| Skill installed on Windows/Linux but app cannot build | App generation works with Python; Apple app builds need macOS/Xcode |

## Maintainer notes and sources

Regenerate metadata with `python3 scripts/package-sdk-plugin.py --sync-manifests`;
check it with `--check`. The canonical Swift plugin identity/version comes from its
Claude manifest. Sync updates the Swift entry and preserves entries owned by other SDK
plugins (the same script serves `ditto-kotlin` via `--plugin ditto-kotlin`). The shared
host catalogs list every SDK plugin; the Claude catalog retains its concept plugins. Each host still
needs an installation/activation run on its supported client before being described
as runtime-verified. Record client versions and outcomes separately from structural
package checks. CI publishes package artifacts for review, not a marketplace listing.
See [the build and packaging evidence](swift-workflow-verification.md) for completed
checks and remaining client/runtime acceptance work.

- [OpenAI plugin packaging](https://developers.openai.com/plugins/build/plugins)
- [Claude plugin reference](https://code.claude.com/docs/en/plugins-reference)
- [Cursor plugin reference](https://cursor.com/docs/reference/plugins)
- [Copilot plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference)
- [Antigravity plugins](https://www.antigravity.google/docs/plugins?tab=cli)
- [Gemini extension reference](https://geminicli.com/docs/extensions/reference/)
- [OpenCode skills](https://opencode.ai/docs/skills/)
