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

Write-Host "Fetching the anon key from $ref…"

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

$anon = ($keys | ConvertFrom-Json | Where-Object { $_.name -eq 'anon' }).api_key
if (-not $anon) {
  throw "Could not read the anon key. Is the CLI logged in? Try: npx supabase login"
}

$defines = @(
  "--dart-define=LUQMA_SUPABASE_URL=https://$ref.supabase.co",
  "--dart-define=LUQMA_SUPABASE_ANON_KEY=$anon",
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
