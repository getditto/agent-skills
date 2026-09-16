# Presence and connection requests — TODO_LANGUAGE

> **Sources for this file.** `sdk/latest/sync/using-mesh-presence.mdx`,
> `sdk/latest/sync/handling-connection-requests.mdx`.
>
> **Do not restate mesh formation** — that is the `ditto-mesh-networking` skill.

## CAP-13 Presence and connection requests

<!--
  - Reading the presence graph once: local peer and remote peers.
  - Observing the graph over time; which thread the callback arrives on; retention.
  - The peer object: identity, device name, OS, connection list, and what each means.
  - Connection objects: type, endpoints, and how to interpret an approximate distance.
  - Serializing the graph to JSON for diagnostics or the presence viewer.
  - Peer metadata: setting it, size limits, the shapes accepted, and how remote peers
    read it. Note the propagation delay -- it is not instantaneous.
  - The connection-request handler: signature, how to allow or deny, what happens by
    default if no handler is set, and which thread it is invoked on.
-->

TODO
