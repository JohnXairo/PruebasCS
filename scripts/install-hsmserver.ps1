#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Compila e instala HsmServer (Rust) como Windows Service.

.DESCRIPTION
    - Requiere Rust toolchain instalado (rustup + cargo)
    - Compila en modo release
    - Registra como Windows Service usando un wrapper CMD que inyecta
      las variables de entorno antes de lanzar el exe (los binarios Rust
      nativos no leen el registro Environment del SCM directamente)
    - Abre el puerto 8083 en el Firewall

.PARAMETER InstallDir
    Directorio de instalacion. Por defecto: C:\InstanaLab\HsmServer

.EXAMPLE
    .\scripts\install-hsmserver.ps1
#>
param(
    [string]$InstallDir = 'C:\InstanaLab\HsmServer'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir  = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$repoRoot   = (Resolve-Path (Join-Path $scriptDir '..')).Path
$projectDir = Join-Path $repoRoot 'HsmServer'
$exePath    = Join-Path $InstallDir 'hsmserver.exe'
$wrapperPath = Join-Path $InstallDir 'hsmserver-svc.cmd'
$svcName    = 'InstanaLab-HsmServer'
$port       = 8083

# ---- Verificar Rust ----
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Error "Cargo (Rust) no encontrado. Instala Rust desde https://rustup.rs"
    exit 1
}
Write-Host "[OK] Rust/Cargo detectado: $(cargo --version)" -ForegroundColor Green

# ---- Compilar ----
Write-Host "`n[>>] Compilando HsmServer (Release)..." -ForegroundColor Yellow
Push-Location $projectDir
& cargo build --release --target x86_64-pc-windows-msvc
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Error "Error compilando HsmServer"
    exit 1
}
Pop-Location

# ---- Copiar binario ----
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
}
$compiledExe = Join-Path $projectDir 'target\x86_64-pc-windows-msvc\release\hsmserver.exe'
Copy-Item $compiledExe $exePath -Force
Write-Host "    Exe copiado: $exePath" -ForegroundColor DarkGray

# ---- Generar wrapper CMD que inyecta variables de entorno ----
# Los binarios Rust nativos no leen el registro SCM Environment directamente.
# El wrapper setea las variables y lanza el exe en primer plano (no en background)
# para que el SCM pueda controlar el proceso correctamente.
$wrapperContent = @"
@echo off
set HSM_HOST=0.0.0.0
set HSM_PORT=$port
set RUST_LOG=info
"$exePath"
"@
Set-Content -Path $wrapperPath -Value $wrapperContent -Encoding ASCII
Write-Host "    Wrapper creado: $wrapperPath" -ForegroundColor DarkGray

# ---- Desinstalar si existe ----
$existing = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[!] Servicio existente, eliminando..." -ForegroundColor DarkYellow
    if ($existing.Status -eq 'Running') {
        Stop-Service -Name $svcName -Force
        Start-Sleep -Seconds 2
    }
    & "$env:SystemRoot\System32\sc.exe" delete $svcName
    $elapsed = 0
    while ((Get-Service -Name $svcName -ErrorAction SilentlyContinue) -and $elapsed -lt 30) {
        Write-Host "    Esperando SCM... ($elapsed s)" -ForegroundColor DarkGray
        Start-Sleep -Seconds 2; $elapsed += 2
    }
}

# ---- Crear servicio apuntando al wrapper CMD ----
# binPath: cmd.exe /c wrapper.cmd  — el SCM lanza cmd que a su vez lanza el exe
$binPath = "cmd.exe /c `"$wrapperPath`""
Write-Host "[+] Creando servicio: $svcName" -ForegroundColor Green
& "$env:SystemRoot\System32\sc.exe" create $svcName `
    binPath= $binPath `
    DisplayName= "Instana Lab - HSM Server (Rust)" `
    start= auto

& "$env:SystemRoot\System32\sc.exe" description $svcName `
    "Servicio HSM simulado en Rust para laboratorio Instana"

# ---- Firewall ----
$fwRule = "InstanaLab-$port-TCP"
$fwExisting = Get-NetFirewallRule -DisplayName $fwRule -ErrorAction SilentlyContinue
if ($fwExisting) { Remove-NetFirewallRule -DisplayName $fwRule }
New-NetFirewallRule -DisplayName $fwRule -Direction Inbound -Protocol TCP `
    -LocalPort $port -Action Allow -Profile Any | Out-Null
Write-Host "    Firewall: puerto TCP $port abierto" -ForegroundColor DarkGray

# ---- Iniciar ----
Write-Host "[>] Iniciando $svcName..." -ForegroundColor Cyan
Start-Service -Name $svcName
Start-Sleep -Seconds 4

$status = (Get-Service -Name $svcName).Status
if ($status -eq 'Running') {
    Write-Host "    [OK] Estado: $status" -ForegroundColor Green
} else {
    Write-Warning "    Estado: $status - Revisa eventvwr.msc > Windows Logs > Application"
}

$ip = (Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.InterfaceAlias -notlike '*Loopback*' } |
       Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "  HsmServer -> http://${ip}:$port/health"
Write-Host "  Endpoints:"
Write-Host "    GET  http://${ip}:$port/health"
Write-Host "    GET  http://${ip}:$port/hsm/keys"
Write-Host "    POST http://${ip}:$port/hsm/keys"
Write-Host "    POST http://${ip}:$port/hsm/sign"
Write-Host "    POST http://${ip}:$port/hsm/encrypt"
