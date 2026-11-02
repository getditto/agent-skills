# Transport configuration

## CAP-06 Customizing transports

Use `ditto.updateTransportConfig(config => { ... })` to apply a modified configuration;
mutating a detached config without assigning it does not apply changes. Fields include
peerToPeer.bluetoothLE.isEnabled, peerToPeer.awdl.isEnabled,
peerToPeer.wifiAware.isEnabled, peerToPeer.lan.isEnabled, listen.tcp and
connect.tcpServers. Do not enable a radio unsupported by the target.

Server mode's URL belongs in DittoConfig.connect; advanced direct-peer endpoints live
in transport configuration. For deterministic local tests, disable automatic radios
and use a loopback TCP listener and a separate peer directory. Do not use that test
configuration as a production transport policy. Runtime changes may disrupt connections.

The browser supports WebSockets, not BLE/AWDL/Wi-Fi Aware/TCP listeners. For native,
permission decisions live in [shared OS config](../../native-app-config/SKILL.md).
Selection strategy belongs to ditto-mesh-networking, or
<https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations>.

Source: published `@dittolive/ditto@5.2.0` `types/ditto.d.ts`, TransportConfig.
