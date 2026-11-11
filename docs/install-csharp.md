# Install the Ditto C# / .NET skill

The `ditto-csharp` plugin contains one portable skill, `csharp-sdk`, with its references,
five local dotnet-new templates and an optional generator. It includes no credentials,
private-source dependency or required MCP server. Installing the skill does not install
the .NET SDK, target workloads or a Ditto license.

## Claude-compatible marketplace

```text
/plugin marketplace add getditto/agent-skills
/plugin install ditto-csharp@ditto-plugins
```

For an unmerged branch, use a local materialized package from that checkout.

## Standalone and host packages

```bash
python3 scripts/package-sdk-plugin.py --plugin ditto-csharp --output dist/csharp
```

The output contains a scoped marketplace, standalone plugin, Gemini and Antigravity
packages, `csharp-sdk.zip`, and checksums. Extract a ZIP before supplying a directory
to a host. The generated catalogs/manifests follow the existing SDK packaging workflow;
see the repository's [installation overview](../README.md) for the host-specific route.
Use a fresh output directory; packaging refuses to overwrite existing files.

Codex, Claude, Cursor, Copilot CLI and other compatible hosts can consume their generated
manifest/package. A direct Agent Skills installation needs the entire `csharp-sdk`
directory, not just SKILL.md: the references and executable assets are required.
The generated archives materialize symlinks and do not require the repository checkout.

## Create an app

Ask the agent to use `csharp-sdk` to create the chosen native app type. The skill routes
to Console, Windows Forms, MAUI, Uno or Avalonia guidance. Windows Forms includes net48,
net481 and modern .NET. The Uno/Avalonia starters are desktop applications; WebAssembly
is explicitly excluded.

From the installed skill directory:

```bash
python3 scripts/create-app.py console /path/to/Tasks --name Tasks
```

The generator resolves a stable compatible Ditto package and creates a self-contained
project. Or install `assets/templates` using `dotnet new install` and use one of the
`ditto-*` templates directly with an explicit `--ditto-version`. Configure the generated
appsettings.json before running. See the skill's project-generation reference for all
frameworks and platform prerequisites.

## Verification limits

Portable packaging is checked independently from live agent behavior. A manifest that
loads successfully does not certify every agent/model. Runtime evidence and known gaps
are recorded in the [skill README](../skills/csharp-sdk/README.md) and
[test harness](../tests/csharp-sdk/README.md).
