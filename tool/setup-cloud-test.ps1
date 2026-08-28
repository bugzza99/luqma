# Writes the credentials `tool\run_tests.ps1` needs to run the two suites that require a
# real Postgres — `supabase test:stack` and `test_live` — against the dedicated cloud
# project rather than a local stack.
#
# Why a project of its own, and not `luqma-edku`: both suites are destructive. One full
# run leaves roughly thirteen staff rows, nine auth users, seven merchants, five cities
# and four orders behind. `tool/cleanup-cloud-test-residue.sql` exists because they were
# once pointed at the real project and somebody had to clean it out by hand.
#
# Everything written here lands in `supabase/.temp/`, which is gitignored. The service
# key can do anything on that project, so it never leaves this machine.
#
# Usage:
#   $env:SUPABASE_ACCESS_TOKEN = '<a personal access token>'
#   powershell -ExecutionPolicy Bypass -File tool\setup-cloud-test.ps1 `
#       -ProjectRef letdxuiypazbcfxbafab -DbPassword '<the project database password>'
#
# `-DbPassword` may be omitted once `supabase/.temp/test-db-password.txt` exists; there is
# no way to read a project's database password back from the API, so a lost one is reset
# from the dashboard rather than recovered.

param(
    [Parameter(Mandatory = $true)][string]$ProjectRef,
    [string]$DbPassword,
    [string]$AccessToken = $env:SUPABASE_ACCESS_TOKEN
)

$ErrorActionPreference = 'Stop'

if (-not $AccessToken) {
    Write-Host "No access token. Set `$env:SUPABASE_ACCESS_TOKEN or pass -AccessToken." -ForegroundColor Red
    Write-Host "Create one at https://supabase.com/dashboard/account/tokens"
    exit 1
}

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$temp = Join-Path $root 'supabase\.temp'
if (-not (Test-Path $temp)) { New-Item -ItemType Directory -Path $temp | Out-Null }

$pwFile = Join-Path $temp 'test-db-password.txt'
if ($DbPassword) {
    Set-Content -Path $pwFile -Value $DbPassword -NoNewline -Encoding utf8
} elseif (-not (Test-Path $pwFile)) {
    Write-Host "No database password. Pass -DbPassword." -ForegroundColor Red
    Write-Host "It cannot be read back from the API; reset it under Settings > Database."
    exit 1
}

Set-Content -Path (Join-Path $temp 'test-project-ref') -Value $ProjectRef -NoNewline -Encoding utf8

$keys = Invoke-RestMethod -Method Get `
    -Uri "https://api.supabase.com/v1/projects/$ProjectRef/api-keys" `
    -Headers @{ Authorization = "Bearer $AccessToken" }

foreach ($pair in @(
    @{ Id = 'anon';         File = 'test-anon-key.txt' },
    @{ Id = 'service_role'; File = 'test-service-key.txt' }
)) {
    $key = ($keys | Where-Object { $_.id -eq $pair.Id }).api_key
    if (-not $key) {
        Write-Host "The project returned no $($pair.Id) key." -ForegroundColor Red
        exit 1
    }
    Set-Content -Path (Join-Path $temp $pair.File) -Value $key -NoNewline -Encoding utf8
}

Write-Host "Wrote four files to supabase\.temp for project $ProjectRef." -ForegroundColor Green
Write-Host ""
Write-Host "A project that has never had the migrations still needs, once:" -ForegroundColor Cyan
Write-Host "  npx supabase db push --project-ref $ProjectRef"
Write-Host "  npx supabase --experimental config push --project-ref $ProjectRef"
Write-Host ""
Write-Host "The second is not optional. The custom access token hook is configuration," -ForegroundColor Cyan
Write-Host "not schema, so `db push` does not carry it — and without it every policy that"
Write-Host "reads a role sees nothing, which reads as a broken boundary rather than a"
Write-Host "missing setting."
