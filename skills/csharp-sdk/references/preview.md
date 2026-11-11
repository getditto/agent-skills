# Preview and platform-specific APIs

## CAP-20 Availability

The public NuGet Ditto **5.2.0** assembly exposes no Data Streams types or Ditto stream
entry point. This was checked by enumerating exported types and public members of the
published assembly, independently of Swift/Kotlin support. Do not invent stream APIs,
opt-in attributes or NGN flags to translate their examples into C#.

Platform-specific permission helpers exist in the Android/iOS/Mac Catalyst assemblies;
they are not available in the plain desktop assembly. Guard their use by target.
DittoConfig.SystemParameters is available in the v5 configuration surface. A key
accepted by the native core does not imply a supported C# feature surface.

Sources: [NuGet 5.2.0](https://www.nuget.org/packages/Ditto/5.2.0),
[Data Streams documentation](https://docs.ditto.live/sdk/latest/sync/data-streams),
and public assembly inspection recorded in the test harness. Re-check the actual
package when a later release announces C# preview support.
