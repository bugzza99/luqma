# Fast release smoke checks at the four public seams Phase 0 protects. These are selected
# from the normal suites rather than copied into a second set of look-alike tests.

param([switch]$Cloud)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$failures = 0

function Invoke-Smoke {
    param([string]$Name, [string]$WorkingDir, [scriptblock]$Body)
    Write-Host "`n===== smoke: $Name =====" -ForegroundColor Cyan
    Push-Location $WorkingDir
    try {
        & $Body
        if ($LASTEXITCODE -ne 0) { $script:failures++ }
    } finally {
        Pop-Location
    }
}

Invoke-Smoke 'customer checkout' (Join-Path $root 'apps\customer_app') {
    flutter test test\checkout_screen_test.dart --no-pub `
        --plain-name 'the order goes out and the basket is emptied'
}
Invoke-Smoke 'merchant accepts an order' (Join-Path $root 'apps\merchant_app') {
    flutter test test\inbox_screen_test.dart --no-pub `
        --plain-name 'the order leaves the inbox once answered'
}
Invoke-Smoke 'admin routing' (Join-Path $root 'apps\admin_app') {
    flutter test test\router_test.dart --no-pub `
        --plain-name 'an admin lands on the module grid inside the shell'
}

if ($Cloud) {
    $temp = Join-Path $root 'supabase\.temp'
    $required = @(
        'test-project-ref',
        'test-db-password.txt',
        'test-service-key.txt',
        'test-anon-key.txt'
    )
    $missing = $required | Where-Object { -not (Test-Path (Join-Path $temp $_)) }
    if ($missing.Count -gt 0) {
        throw "Cloud smoke credentials missing: $($missing -join ', ')"
    }
    $ref = (Get-Content (Join-Path $temp 'test-project-ref') -Raw).Trim()
    $dbPass = (Get-Content (Join-Path $temp 'test-db-password.txt') -Raw).Trim()
    $service = (Get-Content (Join-Path $temp 'test-service-key.txt') -Raw).Trim()
    $anon = (Get-Content (Join-Path $temp 'test-anon-key.txt') -Raw).Trim()
    $env:LUQMA_TEST_PROJECT_REF = $ref
    $env:DATABASE_URL =
        "postgresql://postgres.${ref}:${dbPass}@aws-0-eu-central-1.pooler.supabase.com:5432/postgres"
    try {
        Invoke-Smoke 'cloud isolation: before' (Join-Path $root 'supabase') {
            node test\cleanup-cloud.mjs
        }
        if ($failures -gt 0) {
            throw 'Cloud isolation could not be established; refusing to run a write test.'
        }
        Invoke-Smoke 'place_order through Supabase' (Join-Path $root 'packages\luqma_core') {
            flutter test test_live\order_repository_test.dart -j 1 --timeout 2m --no-pub `
                --plain-name 'prices come from the menu, not from the phone' `
                --dart-define=SUPABASE_URL="https://$ref.supabase.co" `
                --dart-define=SUPABASE_SERVICE_KEY="$service" `
                --dart-define=SUPABASE_ANON_KEY="$anon"
        }
    } finally {
        # Always leave the dedicated project empty, including after a failed assertion.
        Invoke-Smoke 'cloud isolation: after' (Join-Path $root 'supabase') {
            node test\cleanup-cloud.mjs
        }
        Remove-Item Env:\DATABASE_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\LUQMA_TEST_PROJECT_REF -ErrorAction SilentlyContinue
    }
}

if ($failures -gt 0) {
    Write-Host "`n$failures smoke check(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll requested smoke checks passed." -ForegroundColor Green
