# Flutter SDK skill: no-skill baselines

Evidence for CONTRIBUTING.md's "Does it need to exist?": what current models answer for
three of the `flutter_*` cases in [cases.json](cases.json) with **no skills installed**.
Run on 2026-11-18, once per host, with the same prompts, isolation and limits as the
skill runs ([README.md](README.md)): Claude Code 2.1.327 (`claude-opus-5-5`) and Codex
0.169.1 (`gpt-6.1-sol`, fresh `HOME` and `CODEX_HOME`, catalog of four vendor builtins
only). Both hosts searched the workspace, found no guidance and answered from training;
five of the six answers said so. Full answers and scores are in
[results.json](results.json) (`"run": "flutter-no-skill-baseline"`). Raw traces are
private.

Criteria passed (routing excluded, so out of six), against the same hosts with the skill
on the final tree:

| Case | Claude, no skill | Codex, no skill | Claude, skill | Codex, skill |
|---|---|---|---|---|
| `flutter_statefulwidget_observer` | 4 (1 partial) | 4 (1 partial) | 6 | 6 |
| `flutter_hot_restart_observer` | 4 (1 partial) | 3 (1 partial) | 3 (3 partial) | 3 (3 partial) |
| `flutter_web_base_href` | 0 (1 partial) | 0 (2 partial) | 6 | 6 |

## StatefulWidget observer

Both answers were tidy widgets: the query was registered in `initState`, the color was
bound as an argument, and the results were copied to a list behind a `mounted` check.
Both passed **`onChange`** to `registerObserver`. In ditto_live 5.0–5.2.0 that also
buffers every result in the never-listened `changes` stream, so memory grows for as long
as the screen is open. Claude's answer also assumed the v4 `ditto.startSync()`. The
generated Dart compiled.

## Hot restart

This was the closest of the three. Both hosts rejected the static holder, because hot
restart resets statics, and explained that the old native instance still holds the lock.
Claude suggested a debug-only per-launch directory and a full restart, and said the
directory does not prevent the crash. Codex suggested upgrading past 5.2.0 and a
pre-restart plugin hook, and gave no workaround for the lock. Neither knew that V1
observers survive on 5.2.0 while V2 observers crash, nor that release builds must keep
the SDK default directory rather than the install guide's `'ditto'`.

## Web app below `/app/`

Neither host knew the fix: the default shim URL is absolute, and
`Ditto.init(wasmShimUrl: './assets/packages/ditto_live/lib/assets/ditto.wasm.js')` is
needed. Neither warned against `--wasm` builds. Claude used the v4 API (`OnlineWithAuthenticationIdentity`,
`enableDittoCloudSync`, `startSync()`) and said the data is stored in the browser; the
web store is in memory and empty after a page load. Codex said COOP/COEP headers are
required, which Ditto does not need, and said it could not verify the 5.2.0 asset names
or init parameters. Both did say that browsers sync only over WebSocket, and Claude named
`'wasm-unsafe-eval'` for CSP.

## Reading

On these tasks the models know Flutter well and Ditto's Flutter specifics poorly. They
miss the `onChange` buffering defect, which line's observers crash after a hot restart,
and every web deployment detail, and they reach for v4 APIs. With the skill, both hosts
passed every criterion of the observer and web cases and failed none of the hot-restart
case. Its partials are 5.1.0 and web clauses that the 5.2.0 macOS/iOS answers left out.
This is one run per host, a smoke test rather than a benchmark. Scores are literal against
the criteria; hot-restart criterion 6 was reworded after the first scoring to call the
presence crash an inference, as the skill does, which changed no baseline score.
