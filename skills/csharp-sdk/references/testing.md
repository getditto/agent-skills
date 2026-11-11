# Validation

## CAP-18 Testing

Source: [Ditto testing guidance](https://docs.ditto.live/sdk/latest/deployment/testing)
and executed NuGet fixture. Public docs may contain older API forms; compile against
the selected package rather than copying those forms without verification.

Use distinct temporary directories for peers/tests and configure a valid offline license.
Provide a database ID when the license is bound to it. Test actual observations and
read-back values; a zero exit code or successful restore does not establish correctness.

The repository harness covers real store queries, serialized values, observers,
back-pressure, async enumeration cancellation, transactions, persistence, attachments,
TCP replication/presence, and the exact shared starter implementation. It verifies the
loaded SDK version. Known failures are explicit skips with a reason; they are not passes.
A test-host watchdog prevents a native deadlock from hanging CI indefinitely.

Generated-app checks install templates in an isolated hive, generate outside the source
tree, compile the output and exercise the published console app. Source synchronization
checks prevent embedded template copies from drifting from the tested adapter. The
normative minimal program is byte-compared with its compiled fixture.

Classify evidence separately: package/API inspection; compile; desktop/simulator runtime;
physical-device radios; server integration. Do not promote compile-only evidence to
runtime support. A localhost peer test is not a BLE or cloud-durability test.

When testing another agent, install only the packaged skill into a fresh workspace,
request a realistic app/fix without supplying the intended answer, then build/run the
result. Record host/model, selected package, skill reads and the artifacts. Portability
means the files follow the convention, not that every model has been behavior-certified.
