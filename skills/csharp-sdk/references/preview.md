# Preview and platform-specific APIs

## CAP-20 Availability

The public NuGet Ditto **5.2.0** assembly exposes no Data Streams types or Ditto stream
entry point. This was checked by enumerating exported types and public members of the
published assembly, independently of Swift/Kotlin support. Do not invent stream APIs,
opt-in attributes or NGN flags to translate their examples into C#.

Platform-specific permission helpers exist in the Android/iOS/Mac Catalyst assemblies;
they are not available in the plain desktop assembly. Guard their use by target.
`DittoConfig.SystemParameters` exists from **5.2.0** only (absent in 5.0.x and 5.1.x).
On 5.2.0, set startup-only system parameters there, before `OpenAsync`, because they do
not take effect when changed with `ALTER SYSTEM` after open; use `ALTER SYSTEM` through
`ExecuteAsync` for runtime changes. A key accepted by the native core does not imply a
supported C# feature surface.

Sources: [NuGet 5.2.0](https://www.nuget.org/packages/Ditto/5.2.0),
[Data Streams documentation](https://docs.ditto.live/sdk/latest/sync/data-streams),
and enumeration of the 5.2.0 assembly's public types and members. Re-check the actual
package when a later release announces C# preview support.
