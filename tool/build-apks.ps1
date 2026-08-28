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
    & flutter build apk --release --split-per-abi --target-platform android-arm64 @defines
    if ($LASTEXITCODE -ne 0) { throw "$app failed to build" }

    $built = Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
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
