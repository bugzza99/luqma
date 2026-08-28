# Builds the three release APKs, with every dart-define they need.
#
# The alternative is the long command in CLAUDE.md, typed by hand three times. That is
# three chances to forget a flag — and forgetting one is silent: a build with no
# LUQMA_SENTRY_DSN reports nothing and looks identical, and a build with no
# LUQMA_SUPABASE_URL points at nothing and only says so when somebody opens it.
#
#   powershell -ExecutionPolicy Bypass -File tool\build-apks.ps1
#
# The anon key is fetched from the linked project rather than pasted. It is public by
# design — it is what every phone carries, and RLS is what actually protects the data —
# but fetching it means it cannot go stale here and cannot be typed wrong.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ref  = 'vqcivwdoekyfqhfmnuos'

# The Sentry DSN. Public by design too — it ships inside every APK and can only be used
# to *send* events, never to read them. Compiled in rather than left to a flag so a
# release build cannot quietly go un-instrumented.
$dsn = 'https://2271d9cf126307f61a8f17bf4ceab890@o4511984137994240.ingest.de.sentry.io/4511984143695952'

Write-Host "Fetching the publishable key from $ref…"

# ErrorActionPreference is relaxed around this one call on purpose. The Supabase CLI
# writes its "a new version is available" notice to stderr, and Windows PowerShell wraps
# any native stderr line in an ErrorRecord — which under 'Stop' kills the script over a
# version banner. The exit code is what actually says whether it worked.
$keys = $null
try {
  $ErrorActionPreference = 'Continue'
  $keys = (npx supabase projects api-keys --project-ref $ref --output json 2>$null) | Out-String
} finally {
  $ErrorActionPreference = 'Stop'
}

# The `sb_publishable_…` key, not the legacy `anon` JWT.
#
# Both are public and both work. The difference is what happens when one has to be
# killed: the legacy `anon` and `service_role` keys share the project's single JWT
# secret, so revoking either means rotating that secret and invalidating both — every
# installed app stops at once. The new keys are revoked one at a time.
#
# Matched by prefix rather than by name: the API returns two keys called `default`, one
# publishable and one secret, and picking by name would be a coin toss between the key
# every phone carries and the key that bypasses every policy in the database.
# `@(…)` around the parse, and it is the whole bug this script once shipped.
#
# Windows PowerShell 5.1 hands `ConvertFrom-Json`'s array to the pipeline as ONE object.
# `Where-Object { $_.api_key -like '…' }` then tests the *array* of every api_key at
# once — which passes, because one of them matches — and `.api_key` on what comes back
# is every key in the project, joined.
#
# The earlier version selected by `$_.name -eq 'anon'` and had exactly the same shape, so
# the value it handed to `--dart-define` was all four keys at once. Two things followed,
# and it took a night to connect them: the apps carried a key nobody meant to ship — the
# production `service_role` — and they could not talk to Supabase at all, because the key
# they authenticated with was four keys in a trench coat.
#
# So the parse is forced to enumerate, and the result is checked for being one string of
# the right shape. A guess about a pipeline is not something to ship a key on.
$parsed = @($keys | ConvertFrom-Json | ForEach-Object { $_ })
$publishable = @($parsed | Where-Object { $_.api_key -like 'sb_publishable_*' })[0].api_key

if ($publishable -isnot [string]) {
  throw ("Reading the publishable key from $ref gave a " +
         "$($publishable.GetType().Name) instead of one string. Refusing to build: " +
         "that is how every key in the project ends up inside an APK.")
}
if ($publishable -notlike 'sb_publishable_*') {
  throw ("Could not read a publishable key from $ref. Is the CLI logged in " +
         "(npx supabase login), and does the project have the new API keys enabled?")
}

$defines = @(
  "--dart-define=LUQMA_SUPABASE_URL=https://$ref.supabase.co",
  "--dart-define=LUQMA_SUPABASE_PUBLISHABLE_KEY=$publishable",
  "--dart-define=LUQMA_SENTRY_DSN=$dsn"
)

$outDir = Join-Path $root 'apks'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# arm64 only, split per ABI. A universal APK is three times the size for two
# architectures no phone in Edku runs.
foreach ($app in @('customer_app', 'merchant_app', 'admin_app')) {
  Write-Host "`n=== $app ===" -ForegroundColor Cyan
  Push-Location (Join-Path $root "apps\$app")
  try {
    # `clean` first, and it is not caution — it is a fix.
    #
    # Flutter reuses a compiled kernel (`.dart_tool/flutter_build/<hash>/app.dill`)
    # between builds, and a dart-define that was passed once stays baked into it. A
    # release built here once carried the production **service_role** key, which nothing
    # in this repository reads and this script has never passed: it came from an earlier
    # build made with the `test_live` defines, and every later build inherited it.
    #
    # An extra two minutes per app against shipping a key that bypasses every policy in
    # the database is not a trade worth thinking about.
    & flutter clean | Out-Null
    & flutter build apk --release --split-per-abi --target-platform android-arm64 @defines
    if ($LASTEXITCODE -ne 0) { throw "$app failed to build" }

    $built = Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'

    # Nothing ships without being read first.
    #
    # A `service_role` JWT inside an APK is not a leak that needs an attacker: the file
    # sits on the phone, unzipping it takes seconds, and that key bypasses every policy
    # in the database — every address, every phone number, and the ability to delete all
    # of it. It happened here, and nothing in the build said a word.
    #
    # So the build reads its own output. A key whose payload says `service_role` fails
    # the build rather than reaching `apks/`.
    $blob = [IO.File]::ReadAllText($built, [Text.Encoding]::ASCII)
    foreach ($jwt in ([regex]'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{20,}').Matches($blob)) {
      $payload = $jwt.Value.Split('.')[1].Replace('-', '+').Replace('_', '/')
      switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
      try { $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) }
      catch { continue }
      if ($json -match '"role"\s*:\s*"service_role"') {
        throw ("$app embeds a service_role key. It bypasses every policy in the database, " +
               "and an APK is a file anybody can open. Rotate that key, then build again.")
      }
    }

    $name  = $app -replace '_app$', ''
    Copy-Item $built (Join-Path $outDir "luqma-$name.apk") -Force
  } finally {
    Pop-Location
  }
}

Write-Host "`nDone. APKs in $outDir" -ForegroundColor Green
Get-ChildItem $outDir -Filter *.apk |
  Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } |
  Format-Table -AutoSize
