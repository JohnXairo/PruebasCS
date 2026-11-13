#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Publica, instala y arranca los 3 microservicios como Windows Services.

.DESCRIPTION
    - Compila cada proyecto en modo Release (framework-dependent, win-x64)
      NOTA: framework-dependent es REQUERIDO para que el profiler CLR de Instana
      pueda inyectarse. Self-contained empaqueta su propio runtime y bloquea la inyeccion.
    - Crea el servicio con New-Service
    - Configura ASPNETCORE_URLS=http://0.0.0.0:<puerto> para acceso externo
    - Abre los puertos 8080/8081/8082 en el Firewall de Windows
    - Lo inicia

.PARAMETER InstallDir
    Directorio donde se copiaran los binarios publicados.
    Por defecto: C:\InstanaLab

.EXAMPLE
    # Desde PowerShell como Administrador, en la raiz del repo:
    .\scripts\install-services.ps1
    .\scripts\install-services.ps1 -InstallDir 'D:\Servicios'
#>
param(
    [string]$InstallDir = 'C:\InstanaLab'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolver la raiz del repo (un nivel arriba de /scripts)
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$repoRoot  = (Resolve-Path (Join-Path $scriptDir '..')).Path

Write-Host "[i] Raiz del repositorio: $repoRoot" -ForegroundColor DarkGray
Write-Host "[i] Directorio de instalacion: $InstallDir`n" -ForegroundColor DarkGray

# ----------------------------------------------------------------
# Verificar que .NET 8 runtime esta instalado (requerido por framework-dependent)
# ----------------------------------------------------------------
$runtimeInstalled = dotnet --list-runtimes 2>$null | Select-String 'Microsoft.AspNetCore.App 8\.'
if (-not $runtimeInstalled) {
    Write-Warning "No se detecto el runtime ASP.NET Core 8 instalado."
    Write-Warning "Descargalo desde: https://dotnet.microsoft.com/download/dotnet/8.0"
    Write-Warning "Instala el 'ASP.NET Core Runtime 8.x (x64)' antes de continuar."
    $resp = Read-Host "Continuar de todos modos? (s/N)"
    if ($resp -notmatch '^[sS]$') { exit 1 }
}

# ----------------------------------------------------------------
# Definicion de los 3 servicios
# Orden: Inventory y Notification primero, Order al final (depende de ambos)
# ----------------------------------------------------------------
$services = @(
    @{
        Name        = 'InstanaLab-InventoryService'
        DisplayName = 'Instana Lab - Inventory Service'
        Description = 'Microservicio de inventario para laboratorio Instana'
        Project     = Join-Path $repoRoot 'InventoryService\InventoryService.csproj'
        Exe         = 'InventoryService.exe'
        Url         = 'http://0.0.0.0:8081'
        Port        = 8081
    },
    @{
        Name        = 'InstanaLab-NotificationService'
        DisplayName = 'Instana Lab - Notification Service'
        Description = 'Microservicio de notificaciones para laboratorio Instana'
        Project     = Join-Path $repoRoot 'NotificationService\NotificationService.csproj'
        Exe         = 'NotificationService.exe'
        Url         = 'http://0.0.0.0:8082'
        Port        = 8082
    },
    @{
        Name        = 'InstanaLab-OrderService'
        DisplayName = 'Instana Lab - Order Service'
        Description = 'Microservicio de ordenes para laboratorio Instana (orquestador)'
        Project     = Join-Path $repoRoot 'OrderService\OrderService.csproj'
        Exe         = 'OrderService.exe'
        Url         = 'http://0.0.0.0:8080'
        Port        = 8080
    }
)

# ----------------------------------------------------------------
# Crear directorio raiz de instalacion
# ----------------------------------------------------------------
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
    Write-Host "[+] Directorio creado: $InstallDir" -ForegroundColor Cyan
}

foreach ($svc in $services) {

    $svcDir  = Join-Path $InstallDir $svc.Name
    $exePath = Join-Path $svcDir $svc.Exe

    # ---- 1. Verificar que el .csproj existe ----
    if (-not (Test-Path $svc.Project)) {
        Write-Error "No se encontro el proyecto: $($svc.Project)"
        exit 1
    }

    # ---- 2. Publicar (framework-dependent: NO --self-contained) ----
    Write-Host "`n[>>] Publicando $($svc.Name)..." -ForegroundColor Yellow
    & dotnet publish $svc.Project `
        --configuration Release `
        --runtime win-x64 `
        --no-self-contained `
        --output $svcDir

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error en dotnet publish para $($svc.Name). Exitcode: $LASTEXITCODE"
        exit 1
    }

    if (-not (Test-Path $exePath)) {
        Write-Error "El exe no se genero en: $exePath"
        exit 1
    }
    Write-Host "    Exe publicado: $exePath" -ForegroundColor DarkGray

    # ---- 3. Desinstalar si ya existe ----
    $existing = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "[!] Servicio ya existe, deteniendo y eliminando..." -ForegroundColor DarkYellow
        if ($existing.Status -eq 'Running') {
            Stop-Service -Name $svc.Name -Force
            Start-Sleep -Seconds 2
        }
        & "$env:SystemRoot\System32\sc.exe" delete $svc.Name
        Start-Sleep -Seconds 3
    }

    # ---- 4. Crear servicio con New-Service ----
    Write-Host "[+] Creando servicio: $($svc.Name)" -ForegroundColor Green
    New-Service `
        -Name           $svc.Name `
        -DisplayName    $svc.DisplayName `
        -Description    $svc.Description `
        -BinaryPathName "`"$exePath`"" `
        -StartupType    Automatic

    # ---- 5. ASPNETCORE_URLS en el registro del servicio ----
    $regPath  = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
    $envValue = @("ASPNETCORE_URLS=$($svc.Url)")
    New-ItemProperty -Path $regPath -Name 'Environment' `
        -Value $envValue -PropertyType MultiString -Force | Out-Null
    Write-Host "    ASPNETCORE_URLS=$($svc.Url)" -ForegroundColor DarkGray

    # ---- 6. Abrir puerto en Windows Firewall ----
    $fwRuleName   = "InstanaLab-$($svc.Port)-TCP"
    $existingRule = Get-NetFirewallRule -DisplayName $fwRuleName -ErrorAction SilentlyContinue
    if ($existingRule) { Remove-NetFirewallRule -DisplayName $fwRuleName }
    New-NetFirewallRule `
        -DisplayName $fwRuleName `
        -Direction   Inbound `
        -Protocol    TCP `
        -LocalPort   $svc.Port `
        -Action      Allow `
        -Profile     Any | Out-Null
    Write-Host "    Firewall: puerto TCP $($svc.Port) abierto" -ForegroundColor DarkGray

    # ---- 7. Iniciar servicio ----
    Write-Host "[>] Iniciando $($svc.Name)..." -ForegroundColor Cyan
    Start-Service -Name $svc.Name
    Start-Sleep -Seconds 3

    $status = (Get-Service -Name $svc.Name).Status
    if ($status -eq 'Running') {
        Write-Host "    [OK] Estado: $status" -ForegroundColor Green
    } else {
        Write-Warning "    Estado inesperado: $status - Revisa eventvwr.msc > Windows Logs > Application"
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Instalacion completada" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.InterfaceAlias -notlike '*Loopback*' } |
       Select-Object -First 1).IPAddress
Write-Host "  IP del servidor       : $ip"
Write-Host "  OrderService          : http://${ip}:8080/swagger"
Write-Host "  InventoryService      : http://${ip}:8081/swagger"
Write-Host "  NotificationService   : http://${ip}:8082/swagger"
Write-Host ""
Write-Host "IMPORTANTE: Las variables del profiler CLR de Instana deben estar"
Write-Host "configuradas en el registro de cada servicio para ver trazas."
Write-Host "Ejecuta .\scripts\configure-instana-profiler.ps1 si aun no las has configurado."
