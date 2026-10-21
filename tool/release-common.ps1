# Shared release plumbing, dot-sourced by the build scripts.
#
# Two producers need the same three things: the production publishable key, the
# dart-defines every store build must carry, and a scan of whatever came out. They must
# not grow two copies of the parse — the parse once shipped every key in the project
# inside an APK, and the scan is the only thing that noticed. That story is kept with
# the code that now owns it.

$script:LuqmaProjectRef = 'vqcivwdoekyfqhfmnuos'

# Public by design: it ships inside every APK/AAB and can only be used to *send* events
# to Sentry, never to read them. Compiled in rather than left to a flag so a release
# build cannot quietly go un-instrumented.
$script:LuqmaSentryDsn = 'https://2271d9cf126307f61a8f17bf4ceab890@o4511984137994240.ingest.de.sentry.io/4511984143695952'

function Get-LuqmaReleaseDefines {
    param([Parameter(Mandatory)][string]$PublishableKey)

    if ($PublishableKey -notlike 'sb_publishable_*') {
        throw ("The Supabase key handed to the build does not look publishable: " +
               "'$PublishableKey'. Refusing to compile a release around it.")
    }

    return @(
        "--dart-define=LUQMA_SUPABASE_URL=https://$script:LuqmaProjectRef.supabase.co",
        "--dart-define=LUQMA_SUPABASE_PUBLISHABLE_KEY=$PublishableKey",
        "--dart-define=LUQMA_SENTRY_DSN=$script:LuqmaSentryDsn"
    )
}

function Get-LuqmaPublishableKey {
    param([string]$ProjectRef)

    if (-not $ProjectRef) { $ProjectRef = $script:LuqmaProjectRef }

    Write-Host "Fetching the publishable key from $ProjectRef…"

    # The `sb_publishable_…` key, not the legacy `anon` JWT.
    #
    # Both are public and both work. The difference is what happens when one has to be
    # killed: the legacy `anon` and `service_role` keys share the project's single JWT
    # secret, so revoking either means rotating that secret and invalidating both —
    # every installed app stops at once. The new keys are revoked one at a time.
    #
    # Matched by prefix rather than by name: the API returns two keys called `default`,
    # one publishable and one secret, and picking by name would be a coin toss between
    # the key every phone carries and the key that bypasses every policy in the database.
    #
    # `@(…)` around the parse, and it is the whole bug this code once shipped.
    #
    # Windows PowerShell 5.1 hands `ConvertFrom-Json`'s array to the pipeline as ONE
    # object. `Where-Object { $_.api_key -like '…' }` then tests the *array* of every
    # api_key at once — which passes, because one of them matches — and `.api_key` on
    # what comes back is every key in the project, joined.
    #
    # The earlier version selected by `$_.name -eq 'anon'` and had exactly the same
    # shape, so the value it handed to `--dart-define` was all four keys at once. Two
    # things followed, and it took a night to connect them: the apps carried a key
    # nobody meant to ship — the production `service_role` — and they could not talk to
    # Supabase at all, because the key they authenticated with was four keys in a
    # trench coat.
    #
    # So the parse is forced to enumerate, and the result is checked for being one
    # string of the right shape. A guess about a pipeline is not something to ship a
    # key on.
    #
    # ErrorActionPreference is relaxed around the one native call on purpose. The
    # Supabase CLI writes its "a new version is available" notice to stderr, and
    # Windows PowerShell wraps any native stderr line in an ErrorRecord — which under
    # 'Stop' kills the script over a version banner. The exit code is what actually
    # says whether it worked.
    $keys = $null
    $exitCode = 0
    try {
        $ErrorActionPreference = 'Continue'
        $keys = (npx supabase projects api-keys --project-ref $ProjectRef --output json 2>$null) | Out-String
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = 'Stop'
    }

    if ($exitCode -ne 0) {
        throw ('npx supabase projects api-keys failed with exit code {0}. Run npx supabase login and try again; no key was read.' -f $exitCode)
    }
    if (-not $keys -or -not $keys.Trim()) {
        throw ('The Supabase CLI returned no output for {0}; no key was read.' -f $ProjectRef)
    }

    $parsed = @($keys | ConvertFrom-Json | ForEach-Object { $_ })
    $publishable = @($parsed | Where-Object { $_.api_key -like 'sb_publishable_*' })[0].api_key

    if ($null -eq $publishable -or $publishable -isnot [string]) {
        $actual = if ($null -eq $publishable) { 'nothing' } else { $publishable.GetType().Name }
        throw ("Reading the publishable key from $ProjectRef gave $actual instead of one " +
               "string. Refusing to build: that is how every key in the project ends up " +
               "inside an APK.")
    }
    if ($publishable -notlike 'sb_publishable_*') {
        throw ("Could not read a publishable key from $ProjectRef. Is the CLI logged in " +
               "(npx supabase login), and does the project have the new API keys enabled?")
    }

    return $publishable
}

function Assert-NoPrivilegedKeys {
    param([Parameter(Mandatory)][string]$Path)

    # An APK/AAB is a zip, and a release build is mostly deflated bytes. Reading the
    # file as text (what the first scan did) only works while the interesting entry
    # happens to be stored; opening the archive and reading each entry is the check
    # that keeps working when Gradle changes its compression.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $resolved = (Resolve-Path $Path).Path
    $zip = [System.IO.Compression.ZipFile]::OpenRead($resolved)
    try {
        foreach ($entry in $zip.Entries) {
            $stream = $entry.Open()
            try {
                $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
                try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
            } finally {
                $stream.Dispose()
            }

            if ($text -match 'sb_secret_[A-Za-z0-9_-]+') {
                throw ("$Path embeds a Supabase secret key. It bypasses every policy in " +
                       "the database, and an APK is a file anybody can open. Rotate that " +
                       "key, then build again.")
            }
            if ($text -match '"role"\s*:\s*"service_role"') {
                throw ("$Path embeds a service_role JWT. It bypasses every policy in the " +
                       "database, and an APK is a file anybody can open. Rotate that key, " +
                       "then build again.")
            }

            # The JWT scan stays even with the JSON check above: a key can be embedded
            # without the literal `"role":"service_role"` surviving beside it.
            foreach ($jwt in ([regex]'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{20,}').Matches($text)) {
                $payload = $jwt.Value.Split('.')[1].Replace('-', '+').Replace('_', '/')
                switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
                try { $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) }
                catch { continue }
                if ($json -match '"role"\s*:\s*"service_role"') {
                    throw ("$Path embeds a service_role JWT. It bypasses every policy in " +
                           "the database, and an APK is a file anybody can open. Rotate " +
                           "that key, then build again.")
                }
            }
        }
    } finally {
        $zip.Dispose()
    }
}

function Get-AndroidBuildTool {
    param([Parameter(Mandatory)][string]$Name)

    $exe = if ($env:OS -eq 'Windows_NT') { "$Name.exe" } else { $Name }
    $roots = @(
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    foreach ($root in $roots) {
        $buildTools = Join-Path $root 'build-tools'
        if (-not (Test-Path $buildTools)) { continue }

        $candidate = Get-ChildItem $buildTools -Directory |
            Sort-Object { try { [version]$_.Name } catch { [version]'0.0.0' } } -Descending |
            ForEach-Object { Join-Path $_.FullName $exe } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1

        if ($candidate) { return $candidate }
    }

    throw ("Could not find $Name in the Android SDK. Set ANDROID_HOME or install " +
           "Android SDK build-tools; the release check needs it to read the manifest " +
           "that actually shipped, not the one we think we wrote.")
}

function Test-ReleaseApk {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ApplicationId,
        [string[]]$ForbiddenPermissions = @(),
        [int]$MinimumTargetSdk = 0
    )

    $aapt2 = Get-AndroidBuildTool 'aapt2'
    $badging = (& $aapt2 dump badging $Path 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "$aapt2 could not read $Path"
    }

    if ($badging -notmatch [regex]::Escape("package: name='$ApplicationId'")) {
        throw ("$Path is not $ApplicationId. The applicationId is permanent once " +
               "published, and a bundle under the wrong id cannot be fixed later.")
    }

    if ($MinimumTargetSdk -gt 0) {
        $target = [regex]::Match($badging, "targetSdkVersion:'(\d+)'")
        if (-not $target.Success) {
            throw "$Path has no targetSdkVersion in its manifest."
        }
        if ([int]$target.Groups[1].Value -lt $MinimumTargetSdk) {
            throw ("$Path targets API $($target.Groups[1].Value), below the Play minimum " +
                   "of $MinimumTargetSdk.")
        }
    }

    foreach ($permission in $ForbiddenPermissions) {
        if ($badging -match [regex]::Escape($permission)) {
            throw ("$Path still declares $permission. A permission nobody uses turns into " +
                   "a Play review question and a Data safety answer that disagrees with " +
                   "the binary. Remove it at the manifest merger, then build again.")
        }
    }

    return $badging
}
