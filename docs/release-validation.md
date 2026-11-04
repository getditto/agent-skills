# v0.5.0 release verification

This checklist prepares the release used to verify
[ditto-cli PR #6](https://github.com/getditto/ditto-cli/pull/6).
Merging the preparation PR does not publish a release: the Release workflow
runs only on a tag push or manual dispatch.

## Publish after merge

Follow the release preconditions in [AGENTS.md](../AGENTS.md#releases): use a
clean, current `main`, check its CI, and review the content being published.
For this first tagged release, review the full `skills/` tree because there
is no previous tag to diff against.

```bash
gh workflow run Release --repo getditto/agent-skills --ref main -f tag=v0.5.0
gh run list --repo getditto/agent-skills --workflow release.yml --limit 1
gh release view v0.5.0 --repo getditto/agent-skills
```

Wait for the dispatched run to succeed. Confirm the release targets the
reviewed main commit, includes both `ditto-skills.tar.gz` and
`skills-manifest.json`, and lists these seven skills:

- `data-modeling`
- `data-streams`
- `ditto-mesh-networking`
- `kotlin-sdk`
- `swift-sdk`
- `sync-subscriptions`
- `write-dql`

## Exercise the CLI PR against the published assets

Use a `dittosh` build containing PR #6. Authenticate with GitHub while the
skills repository is private. Run the following in one shell; each install
uses a temporary project so existing developer installations are untouched.

```bash
export GITHUB_TOKEN="$(gh auth token)"
dittosh skills versions

release_project="$(mktemp -d)"
dittosh skills add write-dql --ref v0.5.0 --agent claude --project "$release_project"
dittosh skills add --all --ref v0.5.0 --agent codex --project "$release_project"
dittosh skills list --project "$release_project"
dittosh skills update --all --ref v0.5.0 --project "$release_project"

# Verify Antigravity in a separate project (it shares .agents/skills with OpenCode).
antigravity_project="$(mktemp -d)"
dittosh skills add --all --ref v0.5.0 --agent antigravity --project "$antigravity_project"
dittosh skills list --project "$antigravity_project"
dittosh skills update --all --ref v0.5.0 --project "$antigravity_project"

# Exercise the full-repository fallback, then update to the slim release.
migration_project="$(mktemp -d)"
dittosh skills add swift-sdk --ref main --agent claude --project "$migration_project"
dittosh skills update --all --ref v0.5.0 --project "$migration_project"
dittosh skills list --project "$migration_project"
```

Expected results:

- `versions` shows `v0.5.0` as `latest` with `slim_asset: yes` immediately
  after publication, before a newer release is published.
- The first project contains one Claude skill and all seven Codex skills,
  with `v0.5.0` recorded for every install.
- Updating that project reports the installs are already current.
- The Antigravity project contains all seven skills under `.agents/skills/`,
  with `v0.5.0` recorded for each. Listing also reports them for OpenCode,
  which uses the same project directory; updating reports they are already current.
- The second project starts with a `main` install and updates to `v0.5.0`.
- Skill directories include their references, examples, and assets, but no
  repository-level `tests/`, `docs/`, or `plugins/` directories are installed.

Record actual output in the release preparation PR and the CLI PR's test
checklist. These live checks remain pending until the release is published;
a locally built archive alone cannot verify GitHub's authenticated asset download.
