# Application architecture

Keep SDK ownership in one application/account runtime, query intent in repositories or
hooks, and UI in platform components. Prefer the shared provider assets for both web
and mobile; do not wrap Ditto's local reactive store in an HTTP polling layer.

Begin with a complete vertical slice: open/authenticate, a persistent local write,
a query observer, a matching sync subscription, loading/error/empty UI, and a second
peer verification. State when a local write has completed; don't imply server delivery.

Separate deployment choices from component design. A demo offline license is sufficient
for a local smoke test. Production auth uses backend-issued user tokens and appropriate
permissions. Account changes must not flash the previous account's rows.

Use narrow projections when lists grow. Keep a broad subscription only when its memory,
storage and privacy costs match the application's data scope. Cancelling a screen's
observer should not accidentally cancel the application-wide cache subscription.

The provider owns no visual components, so React DOM and React Native can supply their
own loading/error UIs. The task decoder enforces an intentional string-UUID schema.
