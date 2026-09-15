$ErrorActionPreference = "Stop"
$py  = "C:\Users\odjoy\tripora\backend\venv\Scripts\python.exe"
$wd  = "C:\Users\odjoy\tripora\backend"
$outF = Join-Path $wd "repro_out.log"
$errF = Join-Path $wd "repro_err.log"

Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*tripora*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Remove-Item $outF,$errF -ErrorAction SilentlyContinue

$p = Start-Process -FilePath $py -ArgumentList "app.py" -WorkingDirectory $wd `
     -RedirectStandardOutput $outF -RedirectStandardError $errF -PassThru -WindowStyle Hidden

$booted = $false
for ($i = 0; $i -lt 100; $i++) {
  Start-Sleep -Milliseconds 500
  $c = Get-Content $errF -Raw -ErrorAction SilentlyContinue
  if ($c -match "Running on http") { $booted = $true; break }
}

if (-not $booted) {
  "NO BOOT"
  "=== err tail ==="
  Get-Content $errF -Tail 40 -ErrorAction SilentlyContinue
  "=== out tail ==="
  Get-Content $outF -Tail 20 -ErrorAction SilentlyContinue
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  exit 1
}

"BOOTED (pid {0}). registering with an unambiguously valid payload..." -f $p.Id
$email = "local-repro-" + (Get-Random -Minimum 100000000 -Maximum 999999999) + "@neon.local"
$body = '{"name":"Local Repro","email":"' + $email + '","password":"Loc0Repro!x1","preferred_language":"en","preferred_currency":"USD"}'

try {
  $r = Invoke-WebRequest -Uri "http://127.0.0.1:5000/api/auth/register" -Method Post `
       -ContentType "application/json" -Body $body -TimeoutSec 60 -ErrorAction Stop
  "register -> {0} | {1}" -f [int]$r.StatusCode, $r.Content
} catch {
  $resp = $_.Exception.Response
  if ($resp) {
    $sr = New-Object IO.StreamReader($resp.GetResponseStream())
    $b  = $sr.ReadToEnd()
    "register -> {0} | {1}" -f [int]$resp.StatusCode, $b
  } else {
    "register -> ERR: {0}" -f $_.Exception.Message
  }
}

Start-Sleep -Seconds 3
"=== REAL SERVER-SIDE EXCEPTION (only visible in backend log - names the exact DB failure) ==="
$loglines = @()
foreach ($f in @($errF,$outF)) {
  if (Test-Path $f) {
    foreach ($line in (Get-Content $f)) {
      if ($line -match "Traceback|Error|Exception|File \"|line [0-9]+, in|raise |sqlalchemy|psycopg|OperationalError|ProgrammingError|IntegrityError|duplicate|relation|could not connect|password|does not exist|does not have|147|ec2-neuron|neon|connect_timeout|role ") {
        $loglines += $line.Trim()
      }
    }
  }
}
$loglines | Select-Object -First 60
if (-not $loglines) { "  (no matching lines found - dumping last 25 raw lines)" ; Get-Content $errF,$outF -ErrorAction SilentlyContinue | Select-Object -Last 25 }

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
"BACKEND STOPPED"