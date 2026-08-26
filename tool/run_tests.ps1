# Runs the whole Luqma check suite from PowerShell.
#
# This is the one reliable entry point because the merchant_app tests must run from
# PowerShell, not Git Bash: Git Bash rewrites PROGRAMFILES to a POSIX-style path and the
# Android toolchain then fails to resolve it. A PowerShell session inherits the real
# Windows environment, so nothing here sets a variable — it just runs in the shell that
# already has the right one.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tool\run_tests.ps1

$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$core = Join-Path $root 'packages\luqma_core'
$apps = Join-Path $root 'apps'

$results = @()

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

    $results += [pscustomobject]@{ Suite = $Name; ExitCode = $code }
    if ($code -ne 0) {
        Write-Host "FAILED (exit $code)" -ForegroundColor Red
    } else {
        Write-Host "ok" -ForegroundColor Green
    }
}

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

# Schema and constraints on PGlite — no Docker, no stack.
Invoke-Check 'supabase test' (Join-Path $root 'supabase') { npm test }

Write-Host ""
Write-Host "===== summary =====" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$failed = @($results | Where-Object { $_.ExitCode -ne 0 })
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) suite(s) failed." -ForegroundColor Red
    exit 1
}

Write-Host "All suites passed." -ForegroundColor Green
exit 0
