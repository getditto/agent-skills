# Generate an application

The skill includes local `dotnet new` templates and a resolver/generator. No private
repository, MCP server or repo test directory is needed by the generated application.
Run these commands from the installed skill's directory, substituting your destination:

```bash
python3 scripts/create-app.py console /path/to/Tasks --name Tasks
python3 scripts/create-app.py winforms /path/to/Tasks --name Tasks --framework net48
python3 scripts/create-app.py winforms /path/to/Tasks --name Tasks --framework net10.0-windows
python3 scripts/create-app.py maui /path/to/Tasks --name Tasks
python3 scripts/create-app.py uno /path/to/Tasks --name Tasks
python3 scripts/create-app.py avalonia /path/to/Tasks --name Tasks
```

Each command creates one independent app. The generator requires Python 3 and .NET,
resolves the highest stable v5 NuGet version and prints it, uses a temporary template
hive, and refuses to overwrite a nonempty output directory. It does not install a
global template or change an existing project's dependencies. Use `--sdk-version 5.2.0`
for a reproducible baseline. A failed version lookup is an error, not a silent fallback.
Review release notes and validate any package newer than the known baseline.

## Native dotnet new alternative

Python is optional. The .NET CLI can use the bundled templates directly. Unlike the
generator, `dotnet new install` registers them in your user template hive until you
uninstall them. Run these from the skill directory:

```bash
dotnet new install ./assets/templates
dotnet new ditto-console -n Tasks --ditto-version 5.2.0
dotnet new uninstall ./assets/templates
```

To leave no global registration, add `--debug:custom-hive <temporary directory>` to
both the install and the `dotnet new` commands instead of uninstalling.

Other short names: ditto-winforms, ditto-maui, ditto-uno, ditto-avalonia.
For WinForms, `--framework` accepts net48, net481 or net10.0-windows.
The explicit 5.2.0 command reproduces the verified baseline; resolve the current stable
version from [NuGet metadata](https://api.nuget.org/v3-flatcontainer/ditto/index.json)
for a new project and supply it with --ditto-version. Never equate a template default
with the latest available release.

## Configure and run

Edit the generated appsettings.json. For offline operation set DatabaseId and
OfflineLicense. For server operation set DatabaseId, Url and Token. An empty
AuthProvider selects the Development (playground) provider; set your production
provider's name instead, and obtain per-user tokens at runtime rather than embedding a
token: pass a `fetchToken` callback to `TasksViewModel.StartAsync` / `TaskStore.StartAsync`
and leave Token empty. Anything in appsettings.json is compiled into the app. Desktop environment variables DITTOTASKS_DATABASE_ID, DITTOTASKS_OFFLINE_LICENSE,
DITTOTASKS_URL, DITTOTASKS_TOKEN and DITTOTASKS_AUTH_PROVIDER override the corresponding
fields. DITTOTASKS_PERSISTENCE_DIRECTORY optionally overrides the store path (useful
for test isolation). The prefix keeps them apart from variables Ditto's native core
reads. Without that override, each app stores data in a subdirectory named after the
DatabaseId: Ditto treats data in a reused store as new and syncs it, so switching from a
development to a production database ID must not reopen the old store. Do not set an external path on mobile unless the application has access to it.

The file is embedded at build time so mobile apps do not depend on a shell environment.
Rebuild after changing it. It is gitignored by generated projects. The committed
appsettings.example.json is embedded instead when appsettings.json is absent, so a
fresh clone builds and fails at startup with a message naming the missing setting.
The skill itself ships only placeholders, never usable credentials.

Each app exposes add, edit, toggle completion and delete operations, an observed list,
persistent storage and orderly cleanup. Desktop defaults disable BLE/AWDL/Wi-Fi Aware;
MAUI includes platform declarations and requests permissions before sync. Read the
framework guide before enabling radios or background behavior.

Choose the intended OS/architecture explicitly. The Uno starter targets Skia desktop;
the Avalonia starter targets desktop. Neither creates a browser project. Source files
are copied into each generated app; the application does not reference this skill.
