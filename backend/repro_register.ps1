$ErrorActionPreference = "Continue"
$py = "C:\Users\odjoy\tripora\backend\venv\Scripts\python.exe"
$wd = "C:\Users\odjoy\tripora\backend"
$outLog = Join-Path $wd "repro_local_out.log"
$errLog = Join-Path $wd "repro_local_err.log"
Remove-Item $outLog,$errLog -ErrorAction SilentlyContinue

# Kill any leftover tripora backend python so we own port 5000
Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^python' -and $_.CommandLine -like '*tripora*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1

"starting backend (same Neon DB as Render, from backend\.env)..."
$proc = Start-Process -FilePath $py -ArgumentList "app.py" -WorkingDirectory $wd `
    -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru -WindowStyle Hidden

$booted = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Milliseconds 500
    $c = Get-Content $errLog -Raw -ErrorAction SilentlyContinue
    if ($c -match "Running on http") { $booted = $true; break }
}

if (-not $booted) {
    "NO BOOT. stderr tail:"
    Get-Content $errLog -Tail 40 -ErrorAction SilentlyContinue
    "stdout tail:"
    Get-Content $outLog -Tail 20 -ErrorAction SilentlyContinue
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    exit 1
}
"booted (pid $($proc.Id)). posting register with clean/unique/policy payload..."

$email = "local-" + (Get-Random -Minimum 100000000 -Maximum 999999999) + "@neon.dev"
$body = @{
    name               = "Local Save Probe"
    email              = $email
    password           = "Loc4l!Probe7x"
    preferred_language = "en"
    preferred_currency = "USD"
} | ConvertTo-Json

try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:5000/api/auth/register" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 60 -ErrorAction Stop
    "REGISTER -> {0} | {1}" -f [int]$r.StatusCode, $r.Content
} catch {
    $resp = $_.Exception.Response
    if ($resp) {
        $reader = New-Object IO.StreamReader($resp.GetResponseStream())
        $b = $reader.ReadToEnd()
        "REGISTER -> {0} | {1}" -f [int]$resp.StatusCode, $b
    } else {
        "REGISTER -> ERR: {0}" -f $_.Exception.Message
    }
}

Start-Sleep -Seconds 3
"=== THE REAL BACKEND-SIDE EXCEPTION (this is what Render hides; names the failing SQL/DB/column) ==="
Get-Content $errLog,$outLog -ErrorAction SilentlyContinue |
    Select-String -Pattern 'Traceback|File "[^"]+|line [0-9]+, in|          |raise |sqlalchemy|psycopg|OperationalError|ProgrammingError|IntegrityError|DataError|UndefinedTable|UndefinedColumn|does not exist|does not have|relation |column |password authentication|timeout|Timed out|could not connect|connection.*(closed|reset|refused)|Neon|DATABASE|StringIO|Execute failed|duplicate key' |
    ForEach-Object { $_.Line } | Select-Object -First 50

Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
"backend stopped"