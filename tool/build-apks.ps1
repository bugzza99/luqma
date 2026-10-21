param([string]$Only, [string]$PublishableKey)

# Builds the three release APKs, with every dart-define they need.
#
# The alternative is the long command in CLAUDE.md, typed by hand three times. That is
# three chances to forget a flag — and forgetting one is silent: a build with no
# LUQMA_SENTRY_DSN reports nothing and looks identical, and a build with no
# LUQMA_SUPABASE_URL points at nothing and only says so when somebody opens it.
#
#   powershell -ExecutionPolicy Bypass -File tool\build-apks.ps1
#
# The key is fetched from the linked project rather than pasted. It is public by design
# — it is what every phone carries, and RLS is what actually protects the data — but
# fetching it means it cannot go stale here and cannot be typed wrong.
#
# The parse and the release checks live in release-common.ps1, shared with the App Bundle
# build. They are not copied here: the parse once shipped every key in the project inside
# an APK, and the scan is the only thing that noticed.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'release-common.ps1')

$publishable = if ($PublishableKey) { $PublishableKey } else { Get-LuqmaPublishableKey }
$defines = Get-LuqmaReleaseDefines -PublishableKey $publishable

$outDir = Join-Path $root 'apks'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# arm64 only, and NOT split per ABI.
#
# `--split-per-abi` exists so several architectures of one release can sit side by side on
# Play, and it does that by adding 1000 x the architecture's index to the version code:
# arm64 is index 2, so build 9 shipped as **2009**. That is what حسابي has been showing
# people on support calls, and it reads as a year rather than as a build.
#
# We ship one architecture, so the offset buys nothing and costs a number nobody can
# interpret. Without the flag the output is a single `app-release.apk` whose version code
# is the build number in `pubspec.yaml`, which is what the screen is trying to say.
#
# A universal APK is still the wrong answer: three times the size for architectures no
# phone in Edku runs — and `--target-platform` alone does **not** prevent one. It limits
# Flutter's engine and compiled Dart and says nothing about the plugins, so the first
# build without the split flag came out at 53.5 MB carrying x86_64 and armeabi-v7a copies
# of libmaplibre.so. What keeps it to one architecture is `ndk { abiFilters }` in each
# app's `build.gradle.kts`.
$targets = @('customer_app', 'merchant_app', 'admin_app')
if ($Only) {
  $targets = @($targets | Where-Object { $_ -eq "${Only}_app" -or $_ -eq $Only })
  if ($targets.Count -eq 0) {
    throw "No app called '$Only'. Use customer, merchant or admin."
  }
}

# The application ids are permanent once published, and every deep link, every Play
# listing and every installed copy is keyed on them. Reading them back from the APK is
# the check that the manifest merger did not rename anything on the way through.
$applicationIds = @{
  customer_app = 'com.luqma.customer'
  merchant_app = 'com.luqma.merchant'
  admin_app    = 'com.luqma.admin'
}

# MapLibre's AAR declares both location permissions even though neither app asks for the
# device's location: the map centers on the chosen zone and the marker is placed by hand.
# The app manifests remove them at the merger; this list makes the removal provable, and
# fails the build if a dependency quietly puts them back.
#
# MerchantApp also drops `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`: it was declared but no
# screen ever asked for it, and Play treats it as a restricted permission.
$forbiddenPermissions = @{
  customer_app = @(
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION'
  )
  merchant_app = @(
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'
  )
  admin_app = @()
}

foreach ($app in $targets) {
  Write-Host "`n=== $app ===" -ForegroundColor Cyan
  Push-Location (Join-Path $root "apps\$app")
  try {
    # `clean` first — caution, not a fix, and worth being honest about which.
    #
    # A stale kernel was the first explanation for the keys that turned up in these APKs,
    # and it was wrong: a cleaned build reproduced the leak exactly, which is what pointed
    # at the `ConvertFrom-Json` line above. Flutter does keep a compiled kernel per build
    # directory, and a define baked into one is a plausible way to ship a value nobody
    # passed — it just was not what happened here.
    #
    # It stays because two minutes an app is nothing against a release built from
    # something other than the code in front of you, and because a build that produces
    # the same bytes every time is the one you can reason about when it goes wrong again.
    & flutter clean | Out-Null
    & flutter build apk --release --target-platform android-arm64 @defines
    if ($LASTEXITCODE -ne 0) { throw "$app failed to build" }

    $built = Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-release.apk'

    # Nothing ships without being read first.
    #
    # A `service_role` JWT inside an APK is not a leak that needs an attacker: the file
    # sits on the phone, unzipping it takes seconds, and that key bypasses every policy
    # in the database — every address, every phone number, and the ability to delete all
    # of it. It happened here, and nothing in the build said a word.
    #
    # So the build reads its own output. `Assert-NoPrivilegedKeys` opens the archive and
    # reads every entry — the first scan read the APK as one text blob and only worked
    # while the interesting entry happened to be stored.
    Assert-NoPrivilegedKeys $built

    # The manifest is read back from the APK, not from the Gradle file: merged permissions
    # are what Play sees, and MapLibre's location pair used to arrive without a line in
    # any manifest this repository owns.
    Test-ReleaseApk -Path $built -ApplicationId $applicationIds[$app] -ForbiddenPermissions $forbiddenPermissions[$app] -MinimumTargetSdk 36 | Out-Null

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
