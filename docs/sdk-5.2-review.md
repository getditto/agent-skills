# SDK 5.2.0 adversarial review

Reviewed on 2026-11-03 by three independent reviewers (A, B and C). Each reviewed
the update across the seven skill families shipped in this independent PR, supporting references, generators, tests,
CI and evidence claims, including relevant unchanged guidance. Initial findings
were collected independently, then each reviewer checked the pooled evidence and
voted explicitly. No correction began before all three agreed to its problem and
scope. Two additional problems discovered by new tests went through the same vote.
Follow-up reviewer checks of the fixes found no additional actionable defects.

## Independent release base

This PR is based directly on `main` at `ef653ca`, retaining its Swift 5.2.0 additions,
release workflow and dependency security updates. It excludes the unmerged
JavaScript/shared native-configuration skills from PR #36. The three reviewers
also checked the port for missing references and unintended regressions.

## Findings and agreement

Every finding below received **AGREE from A, B and C** before correction.

| ID | Problem | Correction and validation |
|---|---|---|
| F1 | Tests passed even when the Swift generator default was changed back to a fixed SDK version | Default CLI tests supply controlled Git tags and verify newest stable selection; lookup failure must leave no generated project |
| F2 | Kotlin guidance implied Android Keystore could export raw Ditto key bytes | Distinguish a non-exportable wrapping key from separately persisted, encrypted application-managed Ditto bytes; retain the Android integration evidence limit |
| F3 | Documentation claimed execution of 74 function names, but the index had 73 and 28 lacked executable catalog coverage | Add a representative semantic case for each of 73 names, an exact index-to-test coverage check, and execution on all four SDKs; scope claims to those cases |
| F4 | Negative-integer tests checked matches without exercising typed reads | Seed negative values with DQL literals and assert decoded `-5` and `Int.MIN_VALUE`, separately from binding checks |
| F5 | Kotlin metadata guidance still described insert-time rejection and recommended deprecated overloads | State 5.2.0 string-valued creation and immediate `IllegalArgumentException`; label older behavior; existing metadata test passes |
| F6 | Guidance incorrectly described the size of the replication delta as the limit condition | Describe the resulting document size; add a two-peer test for rejected over-limit merges, document-specific diagnostics and continued independent-document sync |
| F7 | The alias-ordering test did not exercise the advertised sort-before-fetch fix | Label the test general alias coverage and the specific planner fix source-reviewed; independent probes confirmed the test also passes on 5.1.0 |
| F8 | XOR guidance claimed support on 4.x and a planned return in 5.1 | State rejection on all four tested releases, preserve the explicit negative example and portable expansion |
| F9 | Swift preview guidance called multicast a 5.1.0-only case | State introduction in 5.1.0 and availability in 5.2.0, confirmed against the shipped public interface and existing version test |
| F10 | `date_diff` documentation reversed the subtraction direction | Document `d1 - d2` and reverse the days-since-release example; independently reproduced on all four SDKs |
| F11 | `request_info().start_time` was documented as numeric | Document an ISO 8601 timestamp string with timezone offset; assert parseability and request-time bounds on all four SDKs |
| F12 | Combining main’s Swift 5.2 API documentation with this update exceeded the 20,000-character reference limit | All three reviewers agreed to consolidate duplicated API details into `sdk-5.2.md`, preserving anchors, enum/error mappings, compiler guards and published-version evidence |

## Test evidence

The integrated `cd tests/dql && npm test` run passed: **1,324 catalog/function
outcomes** across four SDKs, with no unexpected failures, plus the 5.2.0 regression
and two-peer degradation checks.

- The DQL catalog retains 258 entries and 250 result goldens. The corrected date
  query's content-addressed ID was migrated with its existing row-count assertion.
- The new function runner executes 73 representative semantic cases on each of
  4.14.6, 5.0.3, 5.1.0 and 5.2.0: **292 additional passing outcomes**.
- The merge-limit regression uses two 5.2.0 peers over TCP loopback. Both accept
  their own 3 MiB field, reject the over-limit incoming merge, report the intended
  `documentTooBig` degradation and retain only their local field. A control document
  still advances after degradation.
- All 21 Swift generator/packaging Python tests and all 19 Kotlin JVM tests pass.
- Isolated negative controls fail as intended: a hardcoded generator default;
  fallback to a fixed version after lookup failure; an incorrect decoded negative
  value; an indexed function without a test; and an incorrect function result.

The integrated commands and Swift and native build results are recorded in
[SDK 5.2.0 validation](sdk-5.2-validation.md). SDK fixture pins are reproducible
test inputs; customer-facing Swift/Kotlin guidance still resolves latest stable.

## Limits

Review and representative tests do not establish every overload or deployment
condition. Physical radios, Android Keystore integration, production migration, eviction/re-sync recovery after degradation,
and the specific sort-before-fetch alias plan remain outside the executed evidence
for this review. These limits are explicit; they are not counted as passing tests.
