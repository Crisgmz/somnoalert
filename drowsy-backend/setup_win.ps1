Param(
  [int]$Port = 8000,
  [switch]$RecreateVenv,
  [string]$PythonPath
)

$ErrorActionPreference = 'Stop'

function Find-Python310 {
  try {
    $cmd = @('py','-3.10','-c','import sys;print(sys.executable)')
    $exe = & $cmd 2>$null
    if ($LASTEXITCODE -eq 0 -and $exe) { return $exe.Trim() }
  } catch {}

  $candidates = @(
    "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
    'C:\\Python310\\python.exe'
  )
  foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
  return $null
}

function Show-Note($msg) { Write-Host "[i] $msg" -ForegroundColor Cyan }
function Show-Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Show-Warn($msg) { Write-Warning $msg }
function Show-Err($msg)  { Write-Host "[x] $msg" -ForegroundColor Red }

# Move to backend folder
Set-Location -Path $PSScriptRoot

if ($PythonPath) {
  $py = $PythonPath
  Show-Note "Usando Python provisto: $py"
} else {
  Show-Note "Buscando Python 3.10..."
  $py = Find-Python310
}
if (-not $py) {
  Show-Err "Python 3.10 no encontrado. Instala Python 3.10.x (64-bit) y reintenta."
  Show-Note "Descarga: https://www.python.org/downloads/release/python-31012/"
  exit 1
}
Show-Ok "Usando Python: $py"

$venvPath = Join-Path $PSScriptRoot '.venv'
if ($RecreateVenv -and (Test-Path $venvPath)) {
  Show-Note "Eliminando venv existente..."
  Remove-Item -Recurse -Force $venvPath
}

if (-not (Test-Path $venvPath)) {
  Show-Note "Creando entorno virtual..."
  & $py -m venv $venvPath
}

$pyvenv = Join-Path $venvPath 'Scripts\python.exe'
Show-Note "Actualizando pip/setuptools/wheel..."
& $pyvenv -m pip install --upgrade pip setuptools wheel

$req = Join-Path $PSScriptRoot 'requirements_windows.txt'
if (-not (Test-Path $req)) { $req = Join-Path $PSScriptRoot 'requirements.txt' }
Show-Note "Instalando dependencias desde $([System.IO.Path]::GetFileName($req)) ..."
& $pyvenv -m pip install -r $req

# Sanity check de .env
$envFile = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path $envFile)) {
  Show-Warn ".env no encontrado en $envFile. Se puede iniciar, pero Supabase no funcionara."
} else {
  function Get-EnvValue([string]$name) {
    $line = (Get-Content $envFile | Where-Object { $_ -match "^\s*$name\s*=" } | Select-Object -First 1)
    if ($null -eq $line) { return $null }
    return ($line -split '=',2)[1].Trim()
  }
  $url = Get-EnvValue 'SUPABASE_URL'
  $key = Get-EnvValue 'SUPABASE_SERVICE_ROLE_KEY'
  if ($url) { Show-Ok "SUPABASE_URL: $url" } else { Show-Warn "SUPABASE_URL no definido en .env" }
  if ($key) { Show-Ok "SUPABASE_SERVICE_ROLE_KEY: ***${($key.Substring(0,[Math]::Min(6,$key.Length)))}..." } else { Show-Warn "SUPABASE_SERVICE_ROLE_KEY no definido en .env" }
}

Show-Note "Levantando backend en puerto $Port ..."
& $pyvenv -m uvicorn app:app --host 0.0.0.0 --port $Port
