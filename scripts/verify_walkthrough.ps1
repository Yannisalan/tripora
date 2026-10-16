<#
.SYNOPSIS
  Executes the Tripora release-build walkthrough suite against the production
  backend on an Android emulator, in three phases:

    1) online_test.dart  - register, consent-before-generate, live AI generate,
                           itinerary + add-to-calendar, trips list + offline
                           cache, flights read-only, language switch, theme,
                           reachability scan. Leaves an active session.
    2) offline_test.dart - airplane mode: offline banner, cached trip, graceful
                           generate error with no hang.
    3) cleanup_test.dart - forgot-password request, logout wipes offline cache,
                           re-login, account deletion, credentials rejected.

  Phase 2 is skipped (with a note) if phase 1 could not create any trip and
  nothing was cached, because the offline banner path would not be reachable.

.PARAMETER Device
  Target device id (default: emulator-5554).

.PARAMETER OutDir
  Where to write the per-phase logs (default: ./verify-logs-<timestamp>).
#>
[CmdletBinding()]
param(
    [string]$Device = 'emulator-5554',
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent $PSScriptRoot
$frontend  = Join-Path $repoRoot 'frontend'
$define    = '--dart-define=API_BASE_URL=https://tripora-4mt3.onrender.com'

if (-not $OutDir) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutDir = Join-Path $repoRoot "verify-logs-$stamp"
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
Write-Host "=== Walkthrough logs -> $OutDir"

function Invoke-Drive {
    param(
        [string]$Target,
        [string]$Label
    )
    $log = Join-Path $OutDir "$Label.log"
    Write-Host ""; Write-Host ">>> PHASE $Label (drive profile $Target)"
    Push-Location $frontend
    try {
        # `flutter drive` refuses to build non-web apps in release mode because
        # release AOT binaries expose no Dart VM service for the driver to talk
        # to. Profile mode is AOT + VM service, so the integration test suite
        # runs against the production backend with the same compiled Dart code
        # and prod constants. The isolated RELEASE artifact itself was already
        # verified separately (strings scan, cert, install, launch, render).
        & flutter drive --profile `
            --driver=test_driver/integration_test.dart `
            --target="integration_test/$Target" `
            -d $Device `
            $define 2>&1 | Tee-Object -FilePath $log
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    Write-Host "<<< PHASE $Label exit=$code"
    return $code
}

function Test-Marker {
    param([string]$Log, [string]$Pattern)
    if (-not (Test-Path $Log)) { return $false }
    return (Select-String -Path $Log -Pattern $Pattern -Quiet)
}

function Set-AirplaneMode {
    param([bool]$Enabled)
    $value = if ($Enabled) { 'enable' } else { 'disable' }
    & adb -s $Device shell cmd connectivity airplane-mode $value 2>$null | Out-Null
    Start-Sleep -Milliseconds 500
    if ($Enabled) {
        & adb -s $Device shell svc wifi disable 2>$null | Out-Null
        & adb -s $Device shell svc data disable 2>$null | Out-Null
    } else {
        & adb -s $Device shell svc data enable 2>$null | Out-Null
        & adb -s $Device shell svc wifi enable 2>$null | Out-Null
    }
    Start-Sleep -Seconds 4
    Write-Host "==> airplane-mode=$Enabled applied on $Device"
}

# ---------------------------------------------------------------------------
# Deviceless preflight
# ---------------------------------------------------------------------------
$devices = & adb devices
if (-not ($devices -match "`tdevice")) {
    Write-Error "No emulator/device found. Boot an AVD first, e.g.:`n  emulator -avd Pixel_8 -no-window -no-audio -gpu swiftshader_indirect -no-snapshot -no-boot-anim -no-metrics"
}

# ---------------------------------------------------------------------------
# Warm up the backend. Render's free tier sleeps after ~15 min idle and wakes
# on demand, which can take 30-60s and blows the test's short probe timeouts.
# Poll until it answers (any HTTP status) or give up after 180s.
# ---------------------------------------------------------------------------
Write-Host "--- warming backend (cold start can take ~60s)"
$warmUrl = "https://tripora-4mt3.onrender.com/api/auth/me"
$warmOk = $false
for ($i = 0; $i -lt 18; $i++) {
    $code = (& curl.exe -sS -o NUL -w "%{http_code}" --max-time 20 $warmUrl 2>$null | Out-String).Trim()
    if ($code -match '^\d{3}$') { Write-Host "--- backend answered HTTP $code"; $warmOk = $true; break }
    Write-Host "--- waiting for backend ($i/18) ..."
    Start-Sleep -Seconds 10
}
if (-not $warmOk) { Write-Host "WARNING: backend did not wake within 180s; continuing anyway" }

# ---------------------------------------------------------------------------
# Reset the install so the profile-signed suite can be installed cleanly.
# ---------------------------------------------------------------------------
& adb -s $Device uninstall com.tripora.app 2>$null | Out-Null

# ---------------------------------------------------------------------------
# PHASE 1 - online walkthrough
# ---------------------------------------------------------------------------
$c1 = Invoke-Drive -Target 'online_test.dart' -Label '1-online'
if ($c1 -ne 0) {
    Write-Host "PHASE 1 FAILED (exit=$c1). Follow-up phases skipped."
    exit $c1
}

$log1 = Join-Path $OutDir '1-online.log'
$hasTrip = Test-Marker -Log $log1 -Pattern 'WALKTHROUGH_STATUS] trip_available'

# ---------------------------------------------------------------------------
# PHASE 2 - offline walkthrough (airplane mode)
# ---------------------------------------------------------------------------
$c2 = 0
if ($hasTrip) {
    Set-AirplaneMode -Enabled $true
    $c2 = Invoke-Drive -Target 'offline_test.dart' -Label '2-offline'
} else {
    Write-Host "SKIPPING phase 2: phase 1 produced no cached trip."
}
Set-AirplaneMode -Enabled $false

# ---------------------------------------------------------------------------
# PHASE 3 - cleanup (account deletion)
# ---------------------------------------------------------------------------
$c3 = Invoke-Drive -Target 'cleanup_test.dart' -Label '3-cleanup'

Write-Host ""
Write-Host "=============================="
Write-Host "WALKTHROUGH RESULT"
Write-Host "  phase 1 (online)  : $(if ($c1 -eq 0) {'PASS'} else {"FAIL($c1)"})"
Write-Host "  phase 2 (offline) : $(if (-not $hasTrip) {'SKIPPED'} elseif ($c2 -eq 0) {'PASS'} else {"FAIL($c2)"})"
Write-Host "  phase 3 (cleanup) : $(if ($c3 -eq 0) {'PASS'} else {"FAIL($c3)"})"
Write-Host "  logs -> $OutDir"
Write-Host "=============================="

if ($c1 -ne 0) { exit $c1 }
if ($hasTrip -and $c2 -ne 0) { exit $c2 }
if ($c3 -ne 0) { exit $c3 }
exit 0