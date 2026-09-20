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

## MOSTLY DONE — Migrate away from plugins applying the Kotlin Gradle plugin

Worked through on 2026-09-20. Three of the four plugins are clear; the fourth is blocked
by a package we do not choose, and the block is recorded here so nobody spends the
evening rediscovering it.

**Upgraded, and each one verified by a build rather than by a changelog:**

- `package_info_plus` 8.3.1 → **10.2.1**. The breaking changes in 9.0.0 and 10.0.0 are
  platform minimums only — AGP >= 8.12.1, Gradle >= 8.13, Kotlin 2.2.0, win32 6.0.0,
  Flutter >= 3.41.6 — and this repository was already above every one of them. The Dart
  API we use, `PackageInfo.fromPlatform()`, did not change. 10.2.0 moved its Android
  build to `build.gradle.kts` and applies KGP only below AGP 9, so it left the warning.
- `maplibre_gl` 0.27.0 → **0.27.1**, which applies KGP only when no Kotlin extension
  exists yet. It was never in this file's list because the map was added after it was
  written — a reminder that the list is evidence from a build, not a memory.
- `sentry_flutter` 9.27.0 → **9.30.0** (with `sentry`). 9.30 made its KGP application
  conditional on AGP 9 **and** on `android.builtInKotlin` not being `'false'`.

**What is left, and why it cannot be taken here.** The warning now names
`sentry_flutter` alone, and it names it because all three apps carry
`android.builtInKotlin=false` — set by the Flutter template, which is what sentry 9.30
reads. Setting it to `true` was tried and **fails the build** in
`app_links-7.2.1/android/build.gradle.kts`, which applies `org.jetbrains.kotlin.android`
with no version check; AGP 9 refuses that outright. `app_links` is already at its latest
version and is not a dependency we picked — it arrives under `supabase_flutter`.

So this waits on `app_links`. When it migrates, flipping that one line in the three
`gradle.properties` files clears the last warning with no other change; the comment
beside the flag says so. Do not flip it before then, and do not work around it by
pinning an older `app_links` — that is a transitive pin on the auth client.

### Verification performed

- `flutter build apk --debug` on customer_app, before and after each upgrade. The warning
  went from `maplibre_gl, sentry_flutter` (with package_info_plus already dropped) to
  `sentry_flutter` alone.
- `tool/run_tests.ps1 -SkipCloud`: gen-l10n, four analyzers, four Flutter suites and the
  PGlite schema suite all passed. The two cloud suites were skipped and are not
  implicated — a Flutter dependency cannot reach Postgres.
- Still outstanding from the original acceptance criteria: a release build of all three
  APKs through `tool/build-apks.ps1`, and a device smoke test of start-up, Sentry init
  and the version read. `PackageInfo.fromPlatform()` is what حسابي shows as the build
  number, so that read is the one to look at on the handset.

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
