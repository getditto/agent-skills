# Anti-patterns — the wrong form, the right form, and the symptom

## Contents

- [Assuming a floating-point field is `Double`](#assuming-a-floating-point-field-is-double)
- [Forgetting `signalNext()` on an exit path](#forgetting-signalnext-on-an-exit-path)
- [Assigning a fresh `DittoTransportConfig()`](#assigning-a-fresh-dittotransportconfig)
- [Dematerializing before diffing](#dematerializing-before-diffing)
- [A retroactive `Sendable` shim on v5](#a-retroactive-sendable-shim-on-v5)
- [Treating `sync.isActive` as "connected"](#treating-syncisactive-as-connected)
- [Building the server URL from the database ID](#building-the-server-url-from-the-database-id)

Each of these compiles. Most produce no error at runtime either — the symptom is a
silent wrong result, a frozen screen, or a device that never finds a peer again. The
one-line rules are in [`SKILL.md` § Anti-patterns](../SKILL.md#anti-patterns); this file
carries the code and the diagnosis.

## Assuming a floating-point field is `Double`

```swift
let price = item.value["price"] as? Double                  // WRONG
let price = (item.value["price"] as? NSNumber)?.doubleValue // CORRECT

// BETTER — let Codable widen it
struct Car: Codable { let price: Double }
let car = try JSONDecoder().decode(Car.self, from: item.jsonData())
```

**Symptom:** `nil` for some rows and a value for others *in the same column* — a value
that fits binary32 (`19999.5`) comes back as `Float`, one that does not (`0.1`) as
`Double`. A `guard let` just skips the row: no error, no log.

Booleans are the exception — they decode as plain `Bool`. Numbers arrive as the
narrowest CBOR type that holds them, so the Swift type depends on the *value*, not the
column.

## Forgetting `signalNext()` on an exit path

```swift
try ditto.store.registerObserver(query: q) { [weak self] result, signalNext in
    guard let self else { return }   // WRONG — signalNext is never called
    self.apply(result.items)
    signalNext()
}

try ditto.store.registerObserver(query: q) { [weak self] result, signalNext in
    defer { signalNext() }           // CORRECT — every exit path, exactly once
    guard let self else { return }
    self.apply(result.items)
}
```

**Symptom:** the observer stops delivering forever — no error, no log, no crash. The
screen silently freezes on stale data.

This applies only to `handlerWithSignalNext`. The default `handler:` auto-signals on
return. Back-pressure mode selection is in
[`observers.md`](observers.md#back-pressure-handler-versus-handlerwithsignalnext).

## Assigning a fresh `DittoTransportConfig()`

```swift
var config = DittoTransportConfig()                                  // WRONG
config.connect.webSocketURLs = ["wss://REPLACE_ME_WITH_YOUR_HOST"]
ditto.transportConfig = config

ditto.updateTransportConfig {                                        // CORRECT
    $0.connect.webSocketURLs = ["wss://REPLACE_ME_WITH_YOUR_HOST"]
}
```

**Symptom:** every peer-to-peer transport is turned off — a live instance has
`bluetoothLE`, `lan` and `awdl` enabled, a default-constructed value has them all
`false`. No error, `sync.isActive == true`, and the device never finds a peer again.

## Dematerializing before diffing

```swift
let diff = differ.diff(items)   // CORRECT — diff first, THEN extract
let cars = items.map { item in defer { item.dematerialize() }; return Car(item.value) }
```

**Symptom:** `DittoDiffer.diff(_:)` needs the items materialized and decodes with `try!`,
so reversing these two lines is a crash, not a throw.

`map`, never `compactMap` — the index sets are computed over `items`, so a dropped row
makes `performBatchUpdates` raise *"invalid number of rows in section 0"*. Detail:
[`observers.md`](observers.md#dittodiffer).

This is the one place the "extract and `dematerialize()` promptly" rule inverts. The
correct order is always **diff → extract → dematerialize**.

## A retroactive `Sendable` shim on v5

```swift
extension Ditto: @unchecked Sendable {}   // WRONG on 5.0.x / 5.1.x
```

**Symptom:** `error: conformance of 'Ditto' to protocol 'Sendable' was already stated in
the type's module 'DittoSwift'`. Delete it.

On 4.14.x use `@preconcurrency import DittoSwift` instead of a shim; without it the
compiler says `error: sending 'ditto' risks causing data races`.

## Treating `sync.isActive` as "connected"

**Symptom:** a UI reporting "online" on an offline-only peer with every radio disabled.

`isActive` means *sync was started*, nothing more. Read
`presence.graph.localPeer.isConnectedToDittoServer` and `graph.remotePeers` instead.

## Building the server URL from the database ID

```swift
// WRONG
connect: .server(url: URL(string: "https://\(databaseID).cloud.ditto.live")!)
```

**Symptom:** authentication never succeeds.

Copy the portal's *Connect via SDK* value verbatim — an `https://` URL, not derived from
the database ID. `.server(url:)` takes a `URL`, not a `String`, and `databaseID` has an
uppercase `ID`.
