# Best practices — Ditto Flutter SDK

Judgement calls with more than one working answer. Rules with a nameable symptom are in
[`SKILL.md` § Anti-patterns](SKILL.md#anti-patterns); the API surface is in `references/`.
Nothing here is a new claim: each point links to the reference that carries its evidence.

## Contents

- [Instance ownership](#instance-ownership)
- [Structuring async work](#structuring-async-work)
- [Retaining handles](#retaining-handles)
- [Writes](#writes)
- [Reads and observers](#reads-and-observers)
- [Error handling](#error-handling)
- [Sync handling](#sync-handling)
- [Performance](#performance)
- [Common mistakes](#common-mistakes)
- [The agent verification loop](#the-agent-verification-loop)

## Instance ownership

- **A service object, created in `main` before `runApp`,** owns the one `Ditto`
  (`DittoService` in [connect.md](references/connect.md#open-configure-close-on-failure)).
  Pass it down through constructors, or through the dependency mechanism the app already
  uses. Opening in a widget's `initState` ties the instance to a widget that can be
  rebuilt or remounted, and a second open of the directory fails.
- **Configure inside the open step** — license or expiration handler, transports,
  `sync.start()` — so a failed start closes the instance instead of leaving the directory
  locked. Show the error and let the user relaunch; do not retry in-process.
- **The service outlives every screen.** Repositories hold observers and subscriptions
  for as long as the data need lasts; screens hold neither. The root widget's lifecycle
  listener stops sync on pause when the app does not need background sync, and closes on
  a desktop exit request ([widget-integration.md](references/widget-integration.md#app-lifecycle)).
- **Debug builds only** get a per-launch persistence directory, so a hot restart does not
  collide with the orphaned instance. Release builds pass no `persistenceDirectory`.

## Structuring async work

- **`await` every `execute`,** or hand its `Future` to something that does. It fails
  through the `Future`, so a dropped one loses the error
  ([errors.md](references/errors.md#where-errors-surface)).
- **Callbacks are not `async` boundaries.** Every Ditto callback runs on the UI isolate
  and `onChange` is not awaited: copy `result.items` to a list, hand it to a
  `ValueNotifier`, return ([concurrency.md](references/concurrency.md#the-rules)).
- **Use signal-next (5.1.0+) only when processing a result takes longer than the query
  changes**, for example a render that awaits I/O. A plain observer is simpler and has no
  signal to forget.
- **Heavy work goes to `Isolate.run` as plain maps.** `Ditto` and `Store` cannot cross
  isolates: read with Ditto on the UI isolate, then send the decoded maps (source; not
  executed).
- **Sequence start-up in one `async` function** (open, configure, `sync.start()`), not
  in `initState` callbacks that can interleave
  ([connect.md](references/connect.md#open-configure-close-on-failure)).

## Retaining handles

Every handle has one owner that outlives the need and cancels it while Ditto is open;
the table of handles and symptoms is in
[lifetimes.md](references/lifetimes.md#what-to-retain-and-the-symptom-if-you-dont).

- **Repositories own observers and subscriptions**, as fields; a `State` owns one only
  in a small app, and cancels it in `dispose()`.
- **The owner of an observer also owns its one `changes` listener.** Expose a
  `ValueNotifier` of copied maps, never the stream.

### State management

- **Start with Flutter's own types:** a repository exposing a `ValueNotifier`, a
  `ChangeNotifier` view model and `ListenableBuilder`, as in
  [widget-integration.md](references/widget-integration.md#default-pattern-service-repository-view-model).
  This needs no package and no code generation.
- **Adapt to the app's existing state management rather than adding one.** If the app
  already uses Riverpod, expose the repository's notifier through a provider that
  creates the repository once and disposes it (`ref.onDispose`) while Ditto is open. If it
  uses Bloc, have the repository feed a Cubit or Bloc, which emits plain data. If it uses
  `provider`, hand a `ChangeNotifier` over with `ChangeNotifierProvider.value`. These
  integrations were not executed; the constraints that matter are the same everywhere:
  one owner holds the observer's single `changes` listener, state holds copied maps or
  your own models (never `QueryResult` items), and the owner cancels while Ditto is open.
- **Never expose an observer's raw `changes` stream to widgets or to a state library that
  re-subscribes** (a `StreamProvider`, a `StreamBuilder`): it accepts one listener for
  the observer's lifetime.

## Writes

- **Bind values with `arguments:`; never build the DQL string from them**
  ([store.md](references/store.md#cap-08-executing-dql)).
- **A fixed `_id` with `ON ID CONFLICT DO UPDATE`** makes a write safe to repeat, as the
  minimal app does; a generated `_id` on a retried write makes a duplicate.

### When a transaction earns its cost

A read-write transaction holds the store's only write slot until its callback returns;
every other read-write transaction waits.

- **Use one when writes must land together or not at all** — an order and its lines — or
  when a write depends on a read that must not change in between (insert only if no
  document has the same plate).
- **Do not wrap a single statement** (a multi-document `UPDATE … WHERE` is one): the
  wrapper adds nothing but the held write slot.
- **Do not use one to batch unrelated writes for speed.** Unmeasured here; the cost is
  the blocked writer, not the statements.
- **Keep the callback to `tx.execute` calls.** Validate input before opening it, and do
  no network, file or UI work inside it.
- **Read-only transactions** (`isReadOnly: true`) run concurrently and give a consistent
  view across several reads.

Details and executed results: [store.md](references/store.md#cap-09-transactions).

## Reads and observers

Each observer is a live query the store re-evaluates when matching documents change,
and its results are decoded on the UI isolate.

- **Default to one observer per screen-level data need**, with the `WHERE` clause the
  screen needs, held by a repository and shared by every widget that shows that data.
  Several widgets showing the same collection read one `ValueNotifier`, not one observer
  each.
- **Prefer narrow over broad** when a broad query would decode many documents a screen
  never shows: a `SELECT * FROM cars` observer decodes every car on every change. On web
  this decoding blocks frames (5,000 small documents: about 80 ms in one task, executed
  on dart2js; [web.md](references/web.md#execute-on-the-main-thread)); bound it with
  `WHERE` and `LIMIT`.
- **Prefer one broad observer** when several screens derive different views from the
  same small set: one observer and in-memory filtering is cheaper than many live queries
  over the same documents. Unmeasured beyond the web figure above; profile your own data.

## Error handling

- **Catch `DittoException` and `DittoError` by name**: they are unrelated types. Let
  anything else propagate ([errors.md](references/errors.md#two-unrelated-families)).
- **Surface, do not retry:** a rejected query (fix the statement), a failed open or
  configure (close, show the error, have the user relaunch; do not re-open in-process),
  `File already locked` (a second instance exists; find it).
- **A rejected login is data, not a throw:** read `AuthResponse.exception` and ask the
  user again ([connect.md](references/connect.md#cap-04-authentication-and-identity)).
- **Treat `DittoError` as a bug report:** log it with its stack trace and rethrow.
- **Wrap `sync.start()` and `register*` in `try`:** they throw at the call, while
  `execute` and `open` fail their `Future`.

## Sync handling

- **Subscriptions are separate from observers.** A subscription says what to sync and is
  usually broader and longer-lived than any one screen's observer. Register it once when
  the data need starts ([sync.md](references/sync.md#cap-07-sync-subscriptions)).
- **Start sync once, in the open step,** after the license or expiration handler and
  the transports. Sync scopes go before it, after every open
  ([sync.md](references/sync.md#sync-scopes)).
- **Stop on pause only when the app does not need background sync**, and restart on
  resume; never `close()` on pause
  ([widget-integration.md](references/widget-integration.md#app-lifecycle)).
- **Do not build UI on "is it synced".** There is no status API, and the
  `system:data_sync_info` query can hang: poll it with a timeout, off any path the user
  waits on, and show a timeout as "unknown" ([sync.md](references/sync.md#cap-14-sync-status)).

## Performance

Measured only on web; everything else here is unmeasured, so profile your own data.

- **Decode less.** Results are decoded on the UI isolate (on web, `execute` runs there
  too): 5,000 small documents took about 80 ms in one task on dart2js, `LIMIT 50` 2 ms
  ([web.md](references/web.md#execute-on-the-main-thread)). Bound queries a screen
  runs with `WHERE` and `LIMIT`, and map `items` once.
- **Fewer live queries over the same documents:** share one observer per data need
  rather than one per widget.
- **Index the fields a hot `WHERE` filters on**
  ([store.md](references/store.md#cap-10-indexing)); unmeasured here.
- **Evict what the device no longer needs** rather than letting the store grow
  ([store.md](references/store.md#cap-17-device-storage-management)).

## Common mistakes

Choices that work in a demo and cost later; the ones with an error message are in
[anti-patterns.md](references/anti-patterns.md).

- **Opening Ditto in a widget.** It works until the widget is remounted.
- **One observer per list row.** Each is a live query; observe the list once.
- **A subscription per screen visit that is never cancelled.** It stays registered after
  the handle is dropped.
- **Closing Ditto to "reset" it.** Re-opening in one process aborted or hung the app in
  tests; cancel handles instead, and close only on exit.
- **Treating a clean `flutter analyze` as proof.** Run the loop below.

## The agent verification loop

After editing Ditto code, run these in order and fix each before the next:

1. **`dart format .`** (or `dart format --set-exit-if-changed .` to check only).
2. **`flutter analyze --fatal-infos`**, or the Dart MCP server's `analyze_files` tool if
   one is connected. Turn on `unawaited_futures` and `discarded_futures` in
   `analysis_options.yaml`: they catch an un-awaited `execute`, whose failure would
   otherwise be lost, and `close()` called from `State.dispose()`. `strict-casts`,
   `strict-inference` and `strict-raw-types` catch the `dynamic` that `item.value`
   returns leaking into typed code.
3. **Host tests** (`flutter test`) for widgets and view models, against fakes: Ditto does
   not load there.
4. **`integration_test`** on a desktop or device target for anything that touches the
   store: `flutter test integration_test/<file>.dart -d macos` (or `-d linux`,
   `-d windows`, or a device ID), with the license passed through
   `--dart-define-from-file` and a per-test timeout
   ([testing.md](references/testing.md#ditto-in-the-loop-integration_test)). For web,
   `flutter drive ... -d chrome`.

Report what ran and what did not: a build that analyzes cleanly has not shown that an
observer delivers.
