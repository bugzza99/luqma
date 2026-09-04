# Release backlog and agent handoff

Last reviewed: 2026-09-02, after Phase 0.

This file is the durable handoff for work deliberately left outside Phase 0. A future
engineer or coding agent should treat every section as an independent change: inspect the
current repository and hosted state again, add or update tests first, implement only that
item, then run the release gate. Do not combine dependency upgrades, production config
changes and new product capabilities in one branch.

## Current Phase 0 state

- The Phase 0 working tree contains CI, cloud isolation, public-seam smoke tests, APK
  secret scanning and containment of unfinished features.
- Local analysis/unit/widget/PGlite suites passed repeatedly on the final code state.
- The dedicated Supabase test project passed 175 stack tests and 252 Flutter live tests.
- Cloud cleanup read back zero test cities, users, transient config, test plans, media
  rows and media objects after the run.
- Customer, merchant and admin arm64 release-mode APKs built successfully. CI APKs are
  debug-signed test artifacts and must never be shipped.
- No Phase 0 change was written to the production Supabase project.
- At the time this note was written, Phase 0 changes were still uncommitted on `master`.

The production snapshot taken before Phase 0 is in
`docs/release-baseline/2026-09-02-production.md`.

## P1 — Commit, push and activate the GitHub release gate

### Why this is pending

Creating a workflow file locally does not prove it runs on GitHub-hosted Windows runners.
The cloud job also cannot run until the repository has credentials for the dedicated test
project. A push is an external repository mutation and was not performed without explicit
authorization.

### Required work

1. Review the Phase 0 diff and commit it as one release-foundation change, or split it
   into focused commits without changing behavior.
2. Push a `codex/...` branch unless the owner explicitly requests a direct push to
   `master`.
3. Configure these GitHub Actions secrets:
   - `LUQMA_TEST_PROJECT_REF`
   - `LUQMA_TEST_DB_PASSWORD`
   - `LUQMA_TEST_SERVICE_KEY`
   - `LUQMA_TEST_ANON_KEY`
4. `LUQMA_TEST_PROJECT_REF` must identify the dedicated `luqma-test` project. Never put
   the production project credentials in these secrets. The cleanup runner contains an
   exact project-ref guard and must keep that guard.
5. Run the workflow manually once with `run_cloud=false`, then once with
   `run_cloud=true`.
6. Confirm the scheduled job is enabled and consider making the local job a required
   branch-protection check.

### Acceptance criteria

- The GitHub `Release gate` local job passes from a fresh runner.
- The manual cloud job passes all cleanup, stack and live repository suites.
- The final cleanup output reports zero in every residue category.
- No secret value appears in logs, artifacts, commits or APKs.
- A second consecutive workflow run passes without manual database cleanup.

## P1 — Migrate away from plugins applying the Kotlin Gradle plugin

### Evidence and impact

Flutter 3.44.4 currently builds all three APKs, but warns that `package_info_plus` and
`sentry_flutter` still apply the Kotlin Gradle plugin directly. Flutter states that a
future version will turn this warning into a build failure. This is not a current release
blocker, but it becomes one when Flutter or Android tooling is upgraded.

Versions observed during Phase 0:

- `package_info_plus`: 8.3.1 resolved
- `sentry_flutter`: 9.27.0 resolved
- Flutter: 3.44.4

Re-checked 2026-09-05, still on the same two versions, and the shape of the upgrade is
now known:

- `package_info_plus` 8.3.1 → **10.2.1**, two major versions. Not reachable without
  widening the constraint in all four pubspecs, and majors are where its Android side
  has been changing.
- `sentry_flutter` 9.27.0 → **9.29.0**, already inside `^9.0.0`; 10.0.0 is an alpha and
  is not a candidate.

This stayed undone deliberately rather than being half-taken. The acceptance criteria
below require a build with no warning **and** a device smoke test of start-up, Sentry
init and the version read, and the owner has not wanted APKs built this week. Taking the
safe Sentry minor on its own would not clear the warning — `package_info_plus` is the
other half — so it would be an unverified dependency bump that changes nothing
observable, which is the combination this file warns against everywhere else.

### Required work

1. Re-check the packages' current changelogs and Flutter's Built-in Kotlin migration
   guidance; do not assume the versions above are still current.
2. Determine whether upgrading either package removes the warning before editing Gradle
   files manually.
3. Upgrade one plugin at a time and inspect its transitive Android changes.
4. If a Gradle migration is still required, apply it consistently to customer, merchant
   and admin apps.
5. Do not run a broad `pub upgrade --major-versions` as part of this task.

### Acceptance criteria

- `tool/build-ci-apks.ps1` builds all three APKs without the Kotlin plugin warning.
- All Flutter analyzers and tests pass.
- Startup, Sentry initialization and version/build-number reads are smoke-tested on an
  Android device or emulator.
- The release gate passes twice from a clean checkout.

## DONE — Normalize the support WhatsApp config key

Closed 2026-09-04. `20260902000000_canonical_support_whatsapp.sql` made
`support_whatsapp` canonical with the old spelling kept as a fallback read, and the
production value was set to a real number the same day — it had been the empty string
since Phase 1, so the customer's support tile drew nothing whatever the key was called.

The original note follows, as the record of why.

### Superseded — Normalize the support WhatsApp config key

### Evidence and impact

The production snapshot contained `supportWhatsapp`, while the current admin form writes
`support_whatsapp`. Leaving both spellings creates two sources of truth and can make the
support action appear unconfigured even after an operator saves a number.

### Required work

1. Trace every read and write of both spellings before choosing the canonical key.
2. Prefer one canonical snake_case key if it matches the rest of the control plane.
3. Add a backward-compatible read or a one-time migration so an existing value is not
   lost.
4. Update the seed, admin form, config parser and documentation together.
5. Verify the current production value before performing any production write.

### Acceptance criteria

- Exactly one canonical key is written.
- Legacy data is read or migrated safely.
- Unit tests cover canonical, legacy, missing and conflicting values.
- Saving from Admin and reading from each consumer produces the same number.

## P1 — Decide and provision the minimum supported app version

### Evidence and impact

`min_supported_version` was absent in production during the Phase 0 snapshot. Setting it
too early can lock every installed client out; leaving it absent means there is no remote
kill switch for an unsafe old build.

### Required work

1. Decide the first shippable version/build for every app and confirm where users can
   actually download an update.
2. Verify version comparison behavior for patch/minor boundaries and malformed values.
3. Define an emergency rollback procedure before writing the production key.
4. Set the value only after the update distribution path is live and tested.

### Acceptance criteria

- Older, equal and newer versions are tested explicitly.
- A malformed or missing config does not brick a client.
- The update message and destination are useful and reachable.
- Removing or lowering the value restores access immediately.

## P2 — Implement contained product capabilities as separate projects

Phase 0 intentionally disabled the controls below because their visible UI or config did
not correspond to a complete end-to-end capability:

- OTP ordering/authentication
- AdMob
- public comments
- online payment
- marketing push campaigns

Do not simply re-enable their switches. Each capability needs its own threat model,
backend contract, failure states, observability, UX copy, unit/widget/integration tests and
rollback flag.

Marketing push specifically must not be re-enabled until approval creates a durable
delivery job, the sender records success/failure and retry limits, targeting is explicit,
and an operator can audit what was sent. An approved database row alone is not delivery.

**Marketing push met these on 2026-09-05 and is the one item on this list now enabled.**
`send_promotion_push` queues into `push_outbox`, which the existing drain owns along with
the lease, the retry cap and dead-token pruning; targeting is the campaign's city narrowed
by `zone_ids`, minus everyone who turned `users.marketing_push` off; and
`promotion_push_report` gives the admin queued/sent/waiting/exhausted per campaign without
exposing a single outbox row. The four remaining flags — OTP, AdMob, public comments,
online payment — are untouched and still disabled in AdminApp's config screen.

### Acceptance criteria for re-enabling any flag

- The capability works end to end on the dedicated test environment.
- Both success and failure are visible to the user/operator.
- Permissions and abuse limits are enforced server-side.
- Enabling, disabling and rollback are tested.
- The corresponding disabled-state tests are replaced with tests for the completed
  behavior, not merely deleted.

## Commands for the next agent

Run from the repository root in PowerShell:

```powershell
./tool/run_smoke_tests.ps1
./tool/run_tests.ps1 -SkipCloud
./tool/build-ci-apks.ps1
```

With the dedicated test credentials installed under `supabase/.temp/`:

```powershell
./tool/run_smoke_tests.ps1 -Cloud
./tool/run_tests.ps1 -CloudOnly
```

Before handing work back, also run:

```powershell
git diff --check
git status --short
```

Never commit `supabase/.temp`, production credentials, signing keys, or files under
`build/ci-apks`.
