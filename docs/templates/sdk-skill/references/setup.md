# Setup — TODO_LANGUAGE

> **Slugs are not uniform.** Resolve `<lang>` per directory using the table in
> `docs/SDK-SKILL-TEMPLATE.md` §8.1 — JS, Java, C# and Go do not follow the
> obvious pattern, and Go has no migration guides at all.
>
> **Sources for this file.** `sdk/latest/install-guides/<lang>.mdx` — for Java this is
> a directory: `install-guides/java/server.mdx` (v4 also has `java/android.mdx`),
> `sdk/latest/compatibility/<lang>.mdx`, `sdk/v4/install-guides/<lang>.mdx`,
> `sdk/latest/deployment/network-deployment.mdx`,
> `sdk/latest/deployment/bluetooth-on-linux.mdx`.
> Cite what you actually used. See `docs/SDK-SKILL-TEMPLATE.md` §8.

## CAP-01 Prerequisites and install

<!--
  - Minimum toolchain: compiler / runtime / SDK version, per supported version line.
  - Minimum target platform (OS version, API level, browser, .NET TFM, Rust edition).
  - The exact dependency declaration for 5.1.x, copy-pasteable, in the build-file fence
    from spec §9 rule 2. ONE canonical form per build system.
    Do NOT put the 4.14.x coordinate here -- references/versions.md owns every fact
    that differs across version lines. Link to it.
  - Transitive/native artifacts that must be added separately.
  - Supported architectures, and any that are explicitly dropped in v5.
  - Anything required before the first Ditto call (e.g. an init() that must be awaited).
-->

TODO

## CAP-02 Permissions and platform configuration

<!--
  - Manifest / entitlement / capability declarations required for mesh transports.
  - Runtime permission requests, and the SDK helper that performs them, if any.
  - What to call after permissions change so Ditto picks them up without a restart.
  - Build-system configuration: packaging options, linker flags, ProGuard/R8 rules,
    bundle-size considerations, trimming/AOT settings.
  - Which of the above are per-runtime (e.g. Web vs Node vs React Native) rather than
    per-language.
  - The symptom when each is missing -- usually "sync silently never starts".
-->

TODO
