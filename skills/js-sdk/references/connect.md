# Open, authenticate, and close

## CAP-03 Connecting: config, opening, persistence directory

Use `await init()` then `await Ditto.open(new DittoConfig(databaseID, connect, path))`.
The complete [runtime](../assets/runtime.ts) implements this ordering. Supply an
application-owned persistent path on Node; a stable sandbox-relative path on native.
Do not make a new path on every launch to hide a directory-lock error. Browser paths
are only in-memory namespaces; closing/reloading loses the data.

## CAP-04 Authentication and identity

Server mode takes `{ mode: 'server', url }`; copy the URL and database ID from the
Portal's Connect via SDK panel rather than constructing a hostname. Register and
await `auth.setExpirationHandler` before `sync.start()`. The handler covers initial
login as well as refresh. Await `auth.login(token, provider)` and inspect
`result.error`: a resolved promise is not proof of authentication. `auth.status` and
`auth.observeStatus` report authentication separately from sync being active.

The runtime accepts `getToken`, so the application can fetch a fresh, short-lived
user token from its backend/secure credential store on each request. Present errors;
do not start unbounded immediate retries inside the handler. The playground provider
`Authenticator.DEVELOPMENT_PROVIDER` is for development, not production user auth.
Client configuration is extractable; never ship backend secrets, signing keys, or
privileged Portal credentials in `EXPO_PUBLIC_*`, `VITE_*`, or app assets.

Small-peer mode takes `{ mode: 'smallPeersOnly', privateKey? }` and needs
`setOfflineOnlyLicenseToken` before starting sync. Omitting the private key is an
unencrypted development configuration. Use an approved shared-key or authenticated
server deployment for customer data. The offline license does not replace user authorization.
Obtain credentials from the customer/Portal; a skill cannot invent them.

## CAP-05 Lifecycle: start/stop sync, shutdown, ownership

Use `sync.start()`, `sync.stop()`, `await close()`. Stop sync does not close the local store.
Unmount query consumers, cancel owned observers/subscriptions/fetchers, await in-flight
application writes, stop sync, then await closure of the owner. A closed runtime is terminal;
create a new owner for the next account after the old owner has finished closing.
Never share one account's cache directory with a different authorized data scope.
Closing is not data deletion; decide explicitly whether logout retains or removes
that user's cached data, after closure. Do not delete live Ditto files.

Sources: <https://docs.ditto.live/sdk/latest/migration-guides/node-js-v4>,
<https://docs.ditto.live/sdk/latest/auth-and-authorization/cloud-authentication>.

## Sources

Published `@dittolive/ditto@5.2.0`, `types/ditto.d.ts` (public API distribution);
[versioned API reference](https://software.ditto.live/js/Ditto/5.2.0/api-reference/). Examples use the same package in the executable fixture.
