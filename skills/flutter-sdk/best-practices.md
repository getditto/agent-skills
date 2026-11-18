# Best practices — Ditto Flutter SDK

Judgement calls with more than one working answer. Rules with a nameable symptom are in
[`SKILL.md` § Anti-patterns](SKILL.md#anti-patterns); the API surface is in `references/`.

## Contents

- [Where the instance lives](#where-the-instance-lives)
- [One broad observer or many narrow ones](#one-broad-observer-or-many-narrow-ones)
- [State management](#state-management)
- [When a transaction earns its cost](#when-a-transaction-earns-its-cost)
- [The agent verification loop](#the-agent-verification-loop)

## Where the instance lives

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

## One broad observer or many narrow ones

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
- **Subscriptions are separate from observers.** A subscription says what to sync and is
  usually broader and longer-lived than any one screen's observer. Register it once when
  the data need starts ([sync.md](references/sync.md#cap-07-sync-subscriptions)).
- **Use signal-next (5.1.0+) only when processing a result takes longer than the query
  changes**, for example a render that awaits I/O. A plain observer is simpler and has no
  signal to forget.

## State management

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

## When a transaction earns its cost

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
