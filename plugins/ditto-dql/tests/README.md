# DQL Skill Tests

Automated tests that run every DQL example query in the `ditto-dql` skill against actual Ditto Node SDK installations.

## Supported versions

- `@dittolive/ditto@4.14.4` (LTS)
- `@dittolive/ditto@5.0.0` (current)

## Usage

    npm install
    npm run transform           # one-time: build pedagogical-schema test data
    npm run extract             # rebuild catalog.json from skill markdown
    npm run test                # run against both SDK versions
    npm run report              # render the latest result summary

## Layout

See `docs/superpowers/plans/2026-05-26-dql-skill-test-harness.md` in this repo for the design.

## License token

Set `DITTO_PLAYGROUND_TOKEN` or `DITTO_OFFLINE_LICENSE` in your environment before running.
