# Concurrency and threading — Flutter

Which isolate each SDK callback and call runs on, and what that forces the calling code to
do. The load-bearing rules are in
[`SKILL.md` § Concurrency and threading model](../SKILL.md#concurrency-and-threading-model);
this file is the detail. The docs are silent on most of this; the table is from the SDK
source at each tag, with the executed results named.

## Contents

- [Where each callback runs](#where-each-callback-runs)
- [The rules](#the-rules)
- [Getting from a callback to the UI](#getting-from-a-callback-to-the-ui)

## Where each callback runs

"Registering isolate" means the isolate whose code made the call; in a Flutter app that
is the UI (root) isolate unless you spawn others. Dart runs callbacks on that isolate's
event loop, one at a time, between frames.

| API | Where its work or callback runs |
|---|---|
| `store.execute` | 5.1.0+ native: a long-lived worker isolate per `Ditto`, spawned on the first call and ended by `close()`; concurrent calls queue on it. 5.0.x native: a new isolate per call (`compute`). 4.14.x and **web**: the calling isolate, so a large result blocks frames ([web.md](web.md#execute-on-the-main-thread)). The `Future` completes on the calling isolate on every line |
| `Transaction.execute` | Native, every line: an asynchronous core call (`dittoffi_transaction_execute_async_throws`) whose completion is a `NativeCallable.listener` on the calling isolate; not the execute worker and not `compute`, so it does not queue behind `store.execute` calls. Web: the calling isolate |
| `Ditto.open` | 5.2.0 native: the open runs in a `compute` isolate; the `Future` completes on the caller |
| `registerObserver` `onChange` and `changes` | The registering isolate, in the zone that registered it: through a port on 5.0.4 and 5.2.0, a `NativeCallable.listener` on 5.1.0 |
| `registerObserverV2`, `registerObserverWithSignalNext` (5.1.0+) | The registering isolate (`NativeCallable.listener`) |
| `presence.observe` | The isolate that called `observe`; the first graph on the next event-loop turn |
| `presence.connectionRequestHandler` | The isolate that set it; its `Future` must complete within about 10 s |
| `auth.setExpirationHandler` handler | The isolate that set it; nothing awaits an `async` handler |
| `fetchAttachment` events | The isolate that called `fetchAttachment` |
| `observeTransportConditions` (5.1.0+) | The isolate that called it |
| `DittoLogger.customLogCallback` | The isolate that first initialized Ditto's logger (on `Ditto.init()` / `Ditto.open`) |

Sources: `lib/src/bridge/native/store.dart` (`dittoffiTransactionExecute`, lines 1031-1071 @ `sdk-release-5.2.0`; `store/transaction.dart:79`), `open.dart`, `presence.dart`, `auth.dart`,
`logger.dart` @ `sdk-release-5.2.0` and `sdk-release-5.1.0`; `lib/src/core/native/store.dart`
in ditto_live 5.0.4 (`compute` per `execute`, line 26; the transaction call at line 571 is the async FFI form); `flutter/ditto_live/lib/src/core/native/store.dart`
@ `sdk-release-4.14.7` (inline call); `lib/src/bridge/wasm/store.dart` @
`sdk-release-5.2.0` (web: no worker). A `NativeCallable.listener` delivers on the
isolate that created it (Dart's `dart:ffi` documentation).

`Store.experimentalSkipExecuteIsolateOffload` (5.1.0+, `@experimental`, static) runs
native `execute` inline on the calling isolate instead: faster for many tiny queries, but
a slow one then blocks the UI. It applies to the whole isolate and has no effect on web.

## The rules

1. **Use Ditto from the isolate that opened it.** `Ditto` and `Store` are
   `@pragma("vm:isolate-unsendable")` (`ditto.dart`, `store/store.dart` in ditto_live
   5.0.4 and @ `sdk-release-5.1.0`, `sdk-release-5.2.0`; not in 4.14.7): they cannot be sent to another isolate, so Dart
   rejects them in a `SendPort.send` or `Isolate.spawn` message. To move heavy work off
   the UI isolate, read the data with Ditto, then pass the plain maps to `Isolate.run`.
   Not executed here.
2. **Every callback runs on the UI isolate. Keep it short.** Copy what you need
   (`result.items.map((i) => i.value).toList()`), hand it to a `ValueNotifier`, return.
   Decoding thousands of items inside an observer is UI-thread work.
3. **On web nothing runs off the UI thread**, `execute` included: 5,000 small documents
   decoded in one `execute` blocked the page for 79 ms (5.2.0) and 55 ms (5.1.0); with
   `LIMIT 50`, 2 ms (executed, dart2js release, Chrome 157). Bound queries on web.
4. **Slow consumers use signal-next, not `await` in `onChange`.** `onChange` is
   `void Function(QueryResult)`: an `async` callback is not awaited, so results keep
   arriving while the previous one is still being processed. On 5.1.0+ use
   `registerObserverWithSignalNext` and signal when done
   ([observers.md](observers.md#back-pressure-registerobserverwithsignalnext-510)).
5. **Read-write transactions run one at a time**; others wait for the current one
   (dartdoc of `Store.transaction`). Keep the callback to DQL.
6. **No locks are needed for Ditto's callbacks:** they run one at a time on one event
   loop, never in parallel with your widget code.

## Getting from a callback to the UI

The listener and the widgets share the UI isolate, so there is no thread hop: set a
`ValueNotifier` (or call `notifyListeners`) in the `changes` listener and let a
`ListenableBuilder` rebuild. Results arrive in order. The repository and view model
that do this are in [widget-integration.md](widget-integration.md); the observer is the
repository's, not the widget's.

- In a `State` that listens itself, check `mounted` before `setState`, since a result
  can arrive after the widget is gone ([widget-integration.md](widget-integration.md#small-app-variant)).
- Never call `setState` with the `Iterable` from `result.items`: copy it to a `List`
  first ([anti-patterns.md](anti-patterns.md#setstate-with-resultitems)).
- A listener closure keeps everything it captures alive until the listener and the
  observer are cancelled ([lifetimes.md](lifetimes.md#what-to-retain-and-the-symptom-if-you-dont)).
