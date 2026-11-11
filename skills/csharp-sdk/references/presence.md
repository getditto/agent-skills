# Presence

## CAP-13 Presence graph and connection requests

Sources: [mesh presence](https://docs.ditto.live/sdk/latest/sync/using-mesh-presence),
[connection requests](https://docs.ditto.live/sdk/latest/sync/handling-connection-requests).

Read `ditto.Presence.Graph`; RemotePeers is the current remote peer list. Subscribe
through Presence.Observe(callback) and retain the returned handle. Use
SetPeerMetadata(Dictionary<string,object>) or SetPeerMetadataJsonString(string) for
application metadata. A peer appearing is not proof that a particular document synced.

Presence.ConnectionRequestHandler is an async function returning a
DittoConnectionRequestAuthorization. Use the exact authorization types of the installed
package, enforce the application's policy, and avoid letting callback exceptions cross
native code. Never auto-authorize arbitrary peers merely to make a demo pass.

The TCP fixture verifies a connected remote peer after actual document replication.
Connection-request authorization is source/API documented, not executed by that test;
use an appropriate multi-peer authorization fixture before claiming it is validated.
