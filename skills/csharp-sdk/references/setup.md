# Setup and native dependencies

## CAP-01 Prerequisites

Source: [C# installation](https://docs.ditto.live/sdk/latest/install-guides/c-sharp),
[5.2.0 package](https://www.nuget.org/packages/Ditto/5.2.0).

The package ships net8.0, netstandard2.0, net8.0-android34.0, net8.0-ios15.4 and
net8.0-maccatalyst16.4 assemblies. These are package assets, not an exhaustive list
of supported host runtime versions. The bundled modern starters target .NET 10;
WinForms additionally targets net48/net481. Install the appropriate .NET SDK/workloads
and the .NET Framework targeting pack on Windows for legacy development.

Use `dotnet add package Ditto --version VERSION` after resolving a stable version.
For ordinary projects, the canonical declaration is a `PackageReference` in the
startup .csproj. In a Central Package Management solution, put its version in
Directory.Packages.props and retain an unversioned PackageReference in the project.
Do not mix central and project-local versions accidentally. Existing packages.config
applications use Visual Studio's NuGet Package Manager/nuget restore and MSBuild.

## CAP-02 Build configuration

The skill's native-target boundary follows [Ditto compatibility](https://docs.ditto.live/sdk/latest/compatibility/c-sharp).
Windows desktop requires win-x64, not AnyCPU preferring 32-bit or win-arm64.
macOS desktop requires osx-arm64. Linux has x64 and ARM64 native assets; validate
the target distribution/libc against the support table, not just the CPU.
Mobile assets are distinct from desktop assets; Mac Catalyst is not osx-arm64.

For net48/481 use PlatformTarget=x64 and Prefer32Bit=false. With PackageReference,
set RuntimeIdentifier=win-x64 on the executable. Install Ditto directly on that
executable even if a class library also references it: Framework project-reference
chains do not reliably propagate native DLLs. For packages.config verify the native
package's .targets imports survived NuGet restore; do not copy an arbitrary DLL from
another SDK version. See [WinForms](winforms.md).

Mobile permissions are implemented in the MAUI starter's AndroidManifest.xml and
Apple Info.plist files; read [MAUI](maui.md) for runtime ordering and target minimums.
WebAssembly has no native Ditto backend. Never add browser-wasm/browserwasm to a
Ditto C# application based on NuGet's computed compatibility table.

Test `dotnet publish` output on its destination OS, including native loading.
Do not enable trimming, NativeAOT or single-file publishing merely because restore
succeeds; each can alter reflection serialization or native library resolution.
The desktop starters leave trimming off. Apple workloads require their normal linking
pipeline; the starter selects MtouchLink=None for its baseline. Validate release
linking/AOT separately before changing that setting.
