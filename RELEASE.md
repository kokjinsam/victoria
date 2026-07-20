# Release procedure

Victoria's first release is prepared and published manually. GitHub release notes derive from
`CHANGELOG.md`; do not maintain a separate release-notes file.

## Release candidate

1. Change the Mix version to `0.1.0-rc.1` in one release-only change. The release notes may remain under
   `Unreleased` until the stable release.
2. Run the local release checks: `mix check`, `mix docs --warnings-as-errors`,
   `mix hex.publish --dry-run`, `scripts/release/audit_package.sh`, and both consumer smoke scripts.
3. Push the exact commit and confirm every branch release-readiness CI job passes, including both exact
   Elixir/OTP candidates and the real Apalache consumer.
4. With separate tag authorization, create the local tag `v0.1.0-rc.1`, run
   `git describe --tags --exact-match`, and run the version check with
   `GITHUB_REF=refs/tags/v0.1.0-rc.1 scripts/release/check_version.sh`. RC validation requires only tag/Mix
   agreement; it does not require a matching changelog heading.
5. Push the validated tag only with separate push authorization and confirm its tag CI passes.
6. Create a GitHub prerelease from the changelog only with separate release authorization. Do not publish
   the RC to Hex unless separately authorized.

Do not advertise an exact Elixir/OTP combination until its CI job has passed on the release commit. Do not
require `.tool-versions` to represent every compatibility lane.

## Final release

1. Restore the Mix version and changelog heading to `0.1.0`, and replace `Unreleased` on that heading with
   the UTC release date.
2. Run the complete release gate again from a clean worktree.
3. With separate tag authorization, create the local tag `v0.1.0`, run
   `git describe --tags --exact-match`, and run
   `GITHUB_REF=refs/tags/v0.1.0 scripts/release/check_version.sh`. Stable validation requires tag/Mix
   agreement and a matching dated `CHANGELOG.md` heading.
4. Push the validated tag only with separate push authorization and confirm its tag CI passes.
5. Create the GitHub release from `CHANGELOG.md` only with separate release authorization.
6. From the tagged commit, inspect `mix hex.publish --dry-run`, then run `mix hex.publish` interactively only
   with separate publication authorization.

After publication, verify the package page, HexDocs, source links, changelog, and both workflows from a new
project using the actual Hex dependency. Post-publication verification is a separately authorized step.

## CI-only helpers

The release-readiness workflow owns CI environment setup and the real Apalache jobs.
`scripts/release/install_apalache.sh` is an Ubuntu CI-only helper; it is not a local release check.
The version-consistency job is tag-only and invokes `scripts/release/check_version.sh` only for `refs/tags/v*`.

Feature development stops after the RC. Only packaging, documentation, compatibility-declaration, security,
or demonstrated release-blocking runtime defects belong in the release lane.
