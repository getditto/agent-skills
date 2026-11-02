# Install Ditto JavaScript skills

Install **ditto-js** to get js-sdk, js-node, js-web, js-react-native, js-expo and
native-app-config together. They have local sibling references and the Expo generator
uses assets from those siblings. Do not upload only js-expo and expect a complete app.

## Choose your agent

| Host | Installation |
|---|---|
| Claude Code | Add marketplace `getditto/agent-skills`, then install `ditto-js@ditto-plugins`. For an unpublished branch use a local checkout as the marketplace. |
| Codex CLI/Desktop | Add this repository/local checkout as a plugin marketplace and select **Ditto JavaScript**. The wrapper includes Codex metadata. |
| Cursor / Copilot CLI | Add the repository marketplace and select `ditto-js`; the corresponding catalogs are included. |
| Gemini CLI | Use the generated standalone ditto-js directory, which includes gemini-extension.json; don't install the repository root as an extension. |
| OpenCode / other SKILL.md hosts | Copy all six directories from the portable bundle's skills/ into the host's configured skills directory, keeping their sibling names. |
| Claude Desktop skill uploads | Prefer the plugin marketplace. A single-folder upload does not preserve these sibling dependencies; use a host that can install the full bundle rather than claiming an isolated Expo ZIP is self-contained. |

Host interfaces change; use the agent's supported local-plugin/skill installation flow.
No MCP server is required for the bundled example code. Public docs remain available
when the user needs a capability outside this verified set.

## Local branch or release package

From the repository root:

```bash
python3 scripts/package-js-plugin.py --check
python3 scripts/package-js-plugin.py --output /tmp/ditto-js-package
```

Choose a new output directory. `ditto-js-plugin.zip` contains the standalone plugin;
`ditto-js-skills.zip` contains all six portable skills. Archives contain real files and no node_modules, credentials, tests or internal checkout
dependencies. SHA256SUMS is written beside the archives.
Extract the plugin ZIP to install its ditto-js directory in a host supporting local plugins.
The packager preserves local sibling links and rewrites contributor-only links to GitHub.

## Build an app

Ask: “Build an Expo task app with Ditto, local CRUD, sync, and iOS/Android setup.”
The Expo recipe generates a project with a tested provider, query hook, permission
flow and task UI. Supply the application's database ID and development offline license
(or server URL, provider and a user-token source for authenticated sync). Those values
must come from the customer's Portal/account; the skill cannot supply credentials.

For Node or a website, name that target in the request. Browser Ditto is memory-only;
a website must not be promised native persistence or radio mesh transports.

## Shared native configuration

`ditto-native-config` is also available as a standalone Claude plugin; its canonical
native-app-config folder works in any SKILL.md host. Swift links to this resource;
Kotlin and future Flutter/.NET integrations should apply the same OS declarations through
their own framework adapters. This does not make SDK package installation universal.

## Verification and updates

See [the test report](../tests/js-sdk/README.md) for exact tested versions and boundaries.
Replace the six skills together on update, preserving their sibling layout. Remove
only those installed directories/plugin on uninstall; never remove application data.
