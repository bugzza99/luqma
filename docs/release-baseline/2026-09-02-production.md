# Production baseline — 2026-09-02

Read-only snapshot taken before Phase 0 changes.

## Supabase

- Project ref: `vqcivwdoekyfqhfmnuos`
- Status: `ACTIVE_HEALTHY`
- Region: `eu-central-1`
- Local/remote migrations: 43/43 matched through `20260831050000`
- Active Edge Functions: `create-staff-account` v2, `reset-customer-password` v2,
  `send-push` v4

## Public config rows

```json
[
  {
    "key": "supportWhatsapp",
    "value": "",
    "updated_at": "2026-08-25T17:54:53.791773+03:00"
  }
]
```

`min_supported_version` was absent and was not changed. The four unfinished feature
flags were absent, so their compiled defaults were `false`. Marketing push had no remote
override and therefore used the compiled default until Phase 0 containment.

## CI activation

The local release gate needs no repository secrets. The scheduled/manual cloud job is
deliberately restricted to the dedicated `luqma-test` project and requires these GitHub
Actions secrets:

- `LUQMA_TEST_PROJECT_REF`
- `LUQMA_TEST_DB_PASSWORD`
- `LUQMA_TEST_SERVICE_KEY`
- `LUQMA_TEST_ANON_KEY`

The cleanup runner also checks the exact test project ref before deleting anything and
refuses to run against production.

## Known non-blocking build debt

Flutter 3.44.4 warns that `package_info_plus` and `sentry_flutter` still apply the Kotlin
Gradle plugin directly. Current release APKs build successfully; dependency/Kotlin
migration belongs in a later isolated upgrade phase.

Detailed deferred work, acceptance criteria and next-agent commands are maintained in
`docs/18-release-backlog.md`.
