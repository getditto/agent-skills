# Install the Ditto Kotlin skill

The `ditto-kotlin` plugin ships the `kotlin-sdk` skill, including its references and
the Gradle project-generation guide. The skill covers the Ditto Kotlin SDK on Android
(4.14.x and 5.x) and the JVM (5.x). Installing a skill does not install or license the
Ditto SDK. No Swift skill, cloud credentials, hooks or MCP servers are bundled.

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
- [Maintainer notes](#maintainer-notes)

## Choose an installation

| Host | Native route | Offline/local fallback |
|---|---|---|
| Claude Code CLI / Claude Desktop Code tab | Marketplace + `ditto-kotlin` | Local marketplace directory |
| Claude Desktop Customize | Add marketplace and install `ditto-kotlin` | Upload `kotlin-sdk.zip` as a skill |
| Codex CLI / Desktop | Marketplace + plugin browser | Materialized local marketplace |
| Cursor | Team marketplace on Teams/Enterprise | Materialized local plugin, when local imports are allowed |
| GitHub Copilot CLI | Plugin marketplace | Local plugin directory |
| Antigravity CLI | Local native plugin package | Workspace plugin directory |
| Gemini CLI | Local extension package | Direct native skill installation |
| OpenCode / other Agent Skills hosts | Direct skill directory | Copy instead of symlink |

GitHub installation requires access to `getditto/agent-skills` while the repository
is private. For an unmerged PR, use the local package flow from that checkout.

## Build standalone packages

From an accessible clone, using Python 3.9+ (Windows: substitute `py -3`):

```bash
git clone https://github.com/getditto/agent-skills.git
cd agent-skills
python3 scripts/package-sdk-plugin.py --plugin ditto-kotlin --output dist/kotlin
```

Choose a fresh output directory for each build; the packager refuses to overwrite an
existing output. It generates:

| Output | Use |
|---|---|
| `ditto-kotlin-marketplace/` and matching ZIP | Local catalogs for Claude, Codex, Cursor and Copilot |
| `ditto-kotlin-marketplace/plugins/ditto-kotlin/` | Standalone Agent Plugin with host compatibility metadata |
| `ditto-kotlin-plugin.zip` | Same standalone plugin, rooted at `ditto-kotlin/` |
| `ditto-kotlin-antigravity/` and matching ZIP | Antigravity manifest and real skill files |
| `ditto-kotlin-gemini/` and matching ZIP | Gemini extension and real skill files |
| `kotlin-sdk.zip` | Per-skill upload, rooted at `kotlin-sdk/SKILL.md` |
| `SHA256SUMS` | Archive checksums |

ZIP files are distribution artifacts: extract them before using a CLI that expects a
directory. The standalone packages contain real files and need no repository symlinks;
maintainer links to repository docs/tests are rewritten to GitHub URLs.

## Claude Code and Claude Desktop

```text
/plugin marketplace add getditto/agent-skills
/plugin install ditto-kotlin@ditto-plugins
```

For a PR/local package, replace the marketplace source with the absolute path to
`dist/kotlin/ditto-kotlin-marketplace`. Run `/plugin` to inspect the installed skill.
In Desktop **Customize → Plugins**, add the repository as a marketplace and install
**Ditto Kotlin**; where marketplace installation is not offered, use **Skills → Upload a
skill** with `kotlin-sdk.zip`. Start a new session after changing installations.

## Codex CLI and Desktop

```bash
codex plugin marketplace add getditto/agent-skills
```

Start Codex, open `/plugins` and install **Ditto Kotlin**. For a PR/local package,
register the absolute `ditto-kotlin-marketplace` directory instead. The native catalog
is `.agents/plugins/marketplace.json`; its plugin path resolves relative to the
marketplace root. Codex also discovers a copied skill directory at
`.agents/skills/kotlin-sdk/` (project) or `~/.agents/skills/kotlin-sdk/` (personal).

## Cursor

On Teams/Enterprise, open **Dashboard → Plugins & MCPs → Team Marketplaces → Add
Marketplace → Import from Repo** and enter the repository URL, then install
**ditto-kotlin** from Customize. For a local install, copy the materialized
`ditto-kotlin-marketplace/plugins/ditto-kotlin/` directory to
`~/.cursor/plugins/local/ditto-kotlin/` and reload the window. Local imports must be
allowed by the client/team policy. See [Cursor's installation guide](https://cursor.com/docs/plugins).

## GitHub Copilot CLI

```bash
copilot plugin marketplace add getditto/agent-skills
copilot plugin install ditto-kotlin@ditto-plugins
copilot plugin list
```

For a local package, install the absolute path to
`ditto-kotlin-marketplace/plugins/ditto-kotlin`. The repo provides
`.github/plugin/marketplace.json`; Copilot also reads Claude-compatible catalogs.

## Antigravity CLI

```bash
agy plugin install ./dist/kotlin/ditto-kotlin-antigravity
agy plugin list --json
```

Or copy the generated plugin directory into a project's `.agents/plugins/ditto-kotlin/`,
keeping `plugin.json` and `skills/` together.

## Gemini CLI

```bash
gemini extensions install ./dist/kotlin/ditto-kotlin-gemini
gemini extensions list
```

The extension contains a real `skills/kotlin-sdk/` tree and is Kotlin-only.

## OpenCode and direct skill installation

Copy `ditto-kotlin-marketplace/plugins/ditto-kotlin/skills/kotlin-sdk/` into the host's
skill directory — the whole directory, including `references/` and `examples/`, not
only `SKILL.md`. OpenCode reads `skills.paths`; opening this repository in OpenCode
loads every canonical skill through the committed `.opencode/opencode.json`. For a
personal install add the copied directory to `skills.paths` in
`~/.config/opencode/opencode.jsonc`. On Windows copy rather than symlink.

The host discovers the skill; the chosen model (including Kimi through OpenCode) uses
it. Avoid installing the same skill both directly and through a plugin in one host;
duplicate registrations can produce ambiguous skill selectors.

## Activation and getting started

Confirm `kotlin-sdk` appears in the host's skill catalog (plugin hosts may namespace it
as `ditto-kotlin:kotlin-sdk`). Try: **"Use the Ditto Kotlin skill to add a
ViewModel-backed observer for the `cars` collection to this Android app."** The model
should establish the SDK version line first and read only the matching reference
sections. Generating a project, compiling it and observing sync are separate outcomes;
a successful installation alone establishes none of them.

## Updates and removal

Use the host's plugin/extension update and uninstall controls for the installed
source, e.g. `copilot plugin update ditto-kotlin`, `gemini extensions uninstall
ditto-kotlin`, `agy plugin uninstall ditto-kotlin`; Claude, Codex and Cursor expose
plugin management in their plugin UI. Rebuild local packages to pick up source changes;
replace or remove direct folder copies at their installation path.

## Maintainer notes

Regenerate metadata with `python3 scripts/package-sdk-plugin.py --plugin ditto-kotlin
--sync-manifests`; check it with `--check`. The plugin identity and version come from
`plugins/ditto-kotlin/.claude-plugin/plugin.json`. Sync updates only the Kotlin entry in
the shared host catalogs and preserves entries owned by other SDK plugins. Each host
still needs an installation/activation run on its supported client before being
described as runtime-verified; structural package checks are not that.
