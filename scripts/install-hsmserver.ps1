#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Compila e instala HsmServer (Rust) como Windows Service nativo.

.DESCRIPTION
    - Requiere Rust toolchain (rustup + cargo)
    - Compila con soporte nativo Windows Service (crate windows-service)
    - Registra el exe directamente como servicio (sin wrappers)
    - Las variables de entorno se configuran en el registro del SCM
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

# ---- Crear servicio (exe nativo Windows Service) ----
Write-Host "[+] Creando servicio: $svcName" -ForegroundColor Green
New-Service `
    -Name           $svcName `
    -DisplayName    'Instana Lab - HSM Server (Rust)' `
    -Description    'Servicio HSM simulado en Rust para laboratorio Instana' `
    -BinaryPathName "`"$exePath`"" `
    -StartupType    Automatic

# ---- Variables de entorno en registro del servicio ----
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName"
New-ItemProperty -Path $regPath -Name 'Environment' `
    -Value @("HSM_HOST=0.0.0.0", "HSM_PORT=$port", "RUST_LOG=info") `
    -PropertyType MultiString -Force | Out-Null
Write-Host "    HSM_HOST=0.0.0.0, HSM_PORT=$port, RUST_LOG=info" -ForegroundColor DarkGray

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
Write-Host ""
Write-Host "Para correr en modo consola (pruebas): set HSM_CONSOLE=1 && hsmserver.exe"
