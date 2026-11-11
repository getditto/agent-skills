# Transport configuration

## CAP-06 Customizing transports

Source: [customizing transports](https://docs.ditto.live/sdk/latest/sync/customizing-transport-configurations),
Ditto 5.2.0 public DittoTransportConfigBuilder and executed TCP peer fixture.

`ditto.UpdateTransportConfig(config => { ... })` edits a builder and applies it.
The v5 property path is `config.PeerToPeer.BluetoothLE.Enabled`, not a Swift/Kotlin
property spelling. Other paths include PeerToPeer.Lan, Awdl and WifiAware.
For deterministic TCP testing, disable peer discovery radios, set Listen.Tcp.Enabled,
Listen.Tcp.InterfaceIp and Listen.Tcp.Port on one peer, and add `host:port` to
Connect.TcpServers on the other. Port is ushort. Give peers distinct directories,
the same database ID, valid offline licenses and matching subscriptions.

The desktop starters default to LAN/server connectivity with peer-to-peer radio
flags disabled. Set EnablePeerToPeerRadios only after configuring the target's required
permissions. The MAUI starter includes declarations and the runtime permission hook.
A transport flag existing in the assembly does not mean a platform implements it.

Use the mesh skill or [platform compatibility](https://docs.ditto.live/sdk/latest/compatibility/c-sharp)
for strategy and radio availability. Simulator/emulator success does not validate BLE,
AWDL or Wi-Fi Aware. Apply configuration deliberately; do not repeatedly replace it
from UI rendering code.
