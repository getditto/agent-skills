# Transports — TODO_LANGUAGE

> **Sources for this file.** `sdk/latest/sync/customizing-transport-configurations.mdx`,
> `sdk/latest/sync/managing-redundant-bluetooth-le-connections.mdx`,
> `sdk/latest/deployment/wifi-aware-chipset-considerations.mdx`,
> `sdk/latest/deployment/setting-routing-hints.mdx`.
>
> **Do not restate transport strategy or mesh formation** — that is the
> `ditto-mesh-networking` skill. This file is the API surface only.

## CAP-06 Customizing transports

<!--
  - Reading the current transport config.
  - Mutating it: the builder/struct shape, and the update-in-place helper if present.
  - Peer-to-peer: each radio the SDK exposes, its enable flag, and its options.
  - Connect: outbound websocket/TCP peers.
  - Listen: inbound TCP and HTTP listeners and their options.
  - Global options (e.g. connection limits, advertisement tuning).
  - Whether config can change after sync has started, and what a change interrupts.
  - Which radios are unavailable on which platforms in this SDK, with the symptom.
  - Transport conditions: the observable/event stream, the condition values, and what
    a consumer should do about each.
-->

TODO
