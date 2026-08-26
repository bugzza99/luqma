# Tests that need the database

`flutter test` runs `test/` and nothing here. These need a running Supabase:

```
supabase start
flutter test test_live -j 1
```

**`-j 1` is not optional.** `flutter test` runs files concurrently, and every file here
talks to the same database — so two suites racing produce a different failure each run
and none of them is about the code. Serially the suite is green twice in a row; in
parallel it is green nowhere twice.

The alternative would be a database per file, which is a lot of machinery to avoid one
flag on a suite that takes fifty seconds.

## Why they are separate

Everything in `test/` runs against fakes and pure logic, so it works on any machine with
Flutter and nothing else. That matters — it is what keeps the suite worth running on every
save.

These are the other half, and the pre-launch audit is the reason they exist. It found a
paid feature that had shipped invisible to every customer in the city, and the finding
behind the finding was that **the fakes are more permissive than the real backend**: a
green suite proved the screens worked against the fake and nothing more.

So a repository implementation is tested against a real database, with the real policies
in front of it. `test/` proves the screens; `test_live/` proves the repositories.

## What they assume

- `supabase start` is running. The stack sits 1000 above the Supabase defaults on this
  machine — 55321 for the API — because Windows reserves 54084-54683 for Hyper-V. See
  `supabase/config.toml`.
- The migrations are applied. `supabase db reset` if in doubt.
- They clean up after themselves and make their own city, so they can run against a
  database that has been seeded and can be run twice in a row.
