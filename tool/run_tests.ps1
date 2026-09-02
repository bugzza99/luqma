# Runs the whole Luqma check suite from PowerShell.
#
# This is the one reliable entry point because the merchant_app tests must run from
# PowerShell, not Git Bash: Git Bash rewrites PROGRAMFILES to a POSIX-style path and the
# Android toolchain then fails to resolve it. A PowerShell session inherits the real
# Windows environment, so nothing here sets a variable — it just runs in the shell that
# already has the right one.
#
# The two suites that need a real Postgres — `test:stack` and `test_live` — run against
# the dedicated cloud project `luqma-test`, not against a local stack. They are
# destructive by nature (each full run leaves staff, auth users, merchants, cities and
# orders behind), which is why they get a project of their own rather than being pointed
# at `luqma-edku`; `tool/cleanup-cloud-test-residue.sql` is what pointing them at the
# real project cost last time. Nothing here needs Docker.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tool\run_tests.ps1
#         powershell -ExecutionPolicy Bypass -File tool\run_tests.ps1 -SkipCloud
#         powershell -ExecutionPolicy Bypass -File tool\run_tests.ps1 -CloudOnly

param([switch]$SkipCloud, [switch]$CloudOnly)

if ($SkipCloud -and $CloudOnly) {
    throw '-SkipCloud and -CloudOnly cannot be used together.'
}

$ErrorActionPreference = 'Continue'

# The repository, not `tool/`: this script's own directory is one level down, and every
# path below is built from here.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$core = Join-Path $root 'packages\luqma_core'
$apps = Join-Path $root 'apps'
$temp = Join-Path $root 'supabase\.temp'

# Script scope, and deliberately: `$results += …` inside a function writes to a *local*
# copy, so a plain `$results` here stays empty for ever and the summary reports "all
# passed" however many suites failed. It did exactly that.
$script:results = @()

function Invoke-Check {
    param(
        [string]$Name,
        [string]$WorkingDir,
        [scriptblock]$Body
    )

    Write-Host ""
    Write-Host "===== $Name =====" -ForegroundColor Cyan
    Push-Location $WorkingDir
    try {
        & $Body
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    $script:results += [pscustomobject]@{ Suite = $Name; Result = "$code" }
    if ($code -ne 0) {
        Write-Host "FAILED (exit $code)" -ForegroundColor Red
    } else {
        Write-Host "ok" -ForegroundColor Green
    }
}

# A suite that did not run is not a suite that passed. It goes in the table under its own
# word so the summary can never read as a clean sweep it did not earn.
function Skip-Check {
    param([string]$Name, [string]$Why)
    Write-Host ""
    Write-Host "===== $Name =====" -ForegroundColor Cyan
    Write-Host "SKIPPED — $Why" -ForegroundColor Yellow
    $script:results += [pscustomobject]@{ Suite = $Name; Result = 'skipped' }
}

if (-not $CloudOnly) {
    # Generated localizations come first: a new l10n string is otherwise a compile error
    # that points at the call site rather than at the missing step.
    Invoke-Check 'gen-l10n' $core { flutter gen-l10n }

    foreach ($package in @(
        @{ Name = 'luqma_core';  Dir = $core },
        @{ Name = 'customer_app'; Dir = (Join-Path $apps 'customer_app') },
        @{ Name = 'merchant_app'; Dir = (Join-Path $apps 'merchant_app') },
        @{ Name = 'admin_app';    Dir = (Join-Path $apps 'admin_app') }
    )) {
        Invoke-Check "$($package.Name) analyze" $package.Dir { flutter analyze }
        Invoke-Check "$($package.Name) test"    $package.Dir { flutter test }
    }

    # Schema and constraints on PGlite — Postgres compiled to WebAssembly, so this one
    # needs nothing installed and nothing running.
    Invoke-Check 'supabase test' (Join-Path $root 'supabase') { npm test }
}

# ---- the two suites that need a real Postgres ------------------------------------
#
# Credentials live in `supabase/.temp/` (gitignored), written by tool\setup-cloud-test.ps1.
# A fresh clone has none of them, and that is a skip rather than a failure.

$refFile = Join-Path $temp 'test-project-ref'
$missing = @('test-project-ref', 'test-db-password.txt', 'test-service-key.txt',
             'test-anon-key.txt') |
    Where-Object { -not (Test-Path (Join-Path $temp $_)) }

if ($SkipCloud) {
    Skip-Check 'supabase test:stack' '-SkipCloud was passed'
    Skip-Check 'luqma_core test_live' '-SkipCloud was passed'
} elseif ($missing.Count -gt 0) {
    $why = "no cloud test credentials (missing: $($missing -join ', ')) — run tool\setup-cloud-test.ps1"
    Skip-Check 'supabase test:stack' $why
    Skip-Check 'luqma_core test_live' $why
} else {
    $ref     = (Get-Content $refFile -Raw).Trim()
    $dbPass  = (Get-Content (Join-Path $temp 'test-db-password.txt') -Raw).Trim()
    $service = (Get-Content (Join-Path $temp 'test-service-key.txt') -Raw).Trim()
    $anon    = (Get-Content (Join-Path $temp 'test-anon-key.txt') -Raw).Trim()

    # Session mode (5432), not transaction mode (6543): these tests hold a transaction
    # open across statements and set a role inside it, which a transaction pooler cannot
    # carry between them.
    $env:DATABASE_URL =
        "postgresql://postgres.${ref}:${dbPass}@aws-0-eu-central-1.pooler.supabase.com:5432/postgres"
    $env:LUQMA_TEST_PROJECT_REF = $ref

    try {
        # The hosted suite has to start and finish empty. File-level tearDown hooks are
        # still useful, but a killed runner never reaches them; this outer boundary is
        # what makes the next run independent of the previous one. A failed boundary is
        # a hard stop: never add more writes to a database whose isolation is unknown.
        Invoke-Check 'cloud cleanup: before' (Join-Path $root 'supabase') {
            node test\cleanup-cloud.mjs
        }
        $cleanBefore = $script:results[-1].Result -eq '0'

        if (-not $cleanBefore) {
            Skip-Check 'supabase test:stack' 'cloud isolation could not be established'
            Skip-Check 'cloud cleanup: between suites' 'the stack suite did not run'
            Skip-Check 'luqma_core test_live' 'cloud isolation could not be established'
        } else {
            Invoke-Check 'supabase test:stack' (Join-Path $root 'supabase') {
                npm run test:stack
            }

            Invoke-Check 'cloud cleanup: between suites' (Join-Path $root 'supabase') {
                node test\cleanup-cloud.mjs
            }
            $cleanBetween = $script:results[-1].Result -eq '0'

            if (-not $cleanBetween) {
                Skip-Check 'luqma_core test_live' 'cloud isolation failed between suites'
            } else {
                # `-j 1` is not optional: these files all talk to the same database, and
                # `flutter test` runs files concurrently — in parallel the suite fails
                # somewhere different every run and none of it is about the code.
                #
                # All three keys are needed. The anon key is the one that is easy to
                # forget, because only `phone_auth_test` uses it — it signs up the way a
                # phone does rather than with the service key, since "can an
                # administrator make an account" is a different question from the one
                # that file asks. Left out, the harness falls back to the local stack's
                # demo key, GoTrue refuses it, and five tests fail as though signup were
                # broken.
                Invoke-Check 'luqma_core test_live' $core {
                    flutter test test_live -j 1 --timeout 2m `
                        --dart-define=SUPABASE_URL="https://$ref.supabase.co" `
                        --dart-define=SUPABASE_SERVICE_KEY="$service" `
                        --dart-define=SUPABASE_ANON_KEY="$anon"
                }
            }
        }
    } finally {
        # Attempt this even after a failed suite or PowerShell exception. The next run
        # also starts with the same assertion, so cancellation cannot silently convert
        # residue into a passing build.
        Invoke-Check 'cloud cleanup: after' (Join-Path $root 'supabase') {
            node test\cleanup-cloud.mjs
        }
        Remove-Item Env:\DATABASE_URL -ErrorAction SilentlyContinue
        Remove-Item Env:\LUQMA_TEST_PROJECT_REF -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "===== summary =====" -ForegroundColor Cyan
$script:results | Format-Table -AutoSize

$failed  = @($script:results | Where-Object { $_.Result -ne '0' -and $_.Result -ne 'skipped' })
$skipped = @($script:results | Where-Object { $_.Result -eq 'skipped' })

if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) suite(s) failed." -ForegroundColor Red
    exit 1
}

if ($skipped.Count -gt 0) {
    Write-Host "All suites that ran passed — $($skipped.Count) skipped." -ForegroundColor Yellow
    exit 0
}

Write-Host "All suites passed." -ForegroundColor Green
exit 0
