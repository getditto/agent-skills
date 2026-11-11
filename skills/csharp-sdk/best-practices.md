# Application architecture

Use a long-lived application service for the Ditto instance and a view model for UI
state. Scope subscriptions/observers to the lifetime that actually needs their data.
A multi-window app may share an application store while giving each window an observer;
closing one window should not terminate another's store.

Keep DQL and DTO conversion in a small adapter with explicit async operations. The
bundled TaskStore is an example of that boundary, not a required repository abstraction.
Use dependency injection where the host already uses it; do not register an async
factory by blocking on OpenAsync in a synchronous DI registration. Initialize once
through an awaited application startup path.

Use field-level updates for edits. Choose stable document IDs independent of list
position; deserialize _id explicitly. Handle malformed external documents as observable
errors rather than crashing a native callback. For large lists, replace whole snapshots
with an identity-based diff after measuring UI costs.

Keep native resources out of the view model. Batch UI notifications when needed and
bound queued snapshots; preserving every observer notification can grow memory under
slow rendering. An observer is current state, not an audit log.

Separate development settings from production credential provisioning. Generated
appsettings.json is ignored by the starter's gitignore and embedded for local builds;
shipping tokens in that file is not a production authentication design. Revisit linking,
permissions and background behavior for the actual deployment target.

Sources: [Ditto testing](https://docs.ditto.live/sdk/latest/deployment/testing),
[observing changes](https://docs.ditto.live/sdk/latest/crud/observing-data-changes).
Architectural choices here are recommendations; executable API behavior is checked by
the fixture and identified separately in the capability map.
