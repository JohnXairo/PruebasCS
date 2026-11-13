#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Publica, instala y arranca los 3 microservicios como Windows Services.

.DESCRIPTION
    - Compila cada proyecto en modo Release (self-contained, win-x64)
    - Crea el servicio con sc.exe usando New-Service (evita el alias sc = Set-Content)
    - Configura ASPNETCORE_URLS en el registro del servicio
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
# $PSScriptRoot es valido cuando se ejecuta con .\script.ps1
# Si es nulo (ejecucion directa en consola) usamos el directorio actual
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$repoRoot  = (Resolve-Path (Join-Path $scriptDir '..')).Path

Write-Host "[i] Raiz del repositorio: $repoRoot" -ForegroundColor DarkGray
Write-Host "[i] Directorio de instalacion: $InstallDir`n" -ForegroundColor DarkGray

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
        Url         = 'http://localhost:8081'
    },
    @{
        Name        = 'InstanaLab-NotificationService'
        DisplayName = 'Instana Lab - Notification Service'
        Description = 'Microservicio de notificaciones para laboratorio Instana'
        Project     = Join-Path $repoRoot 'NotificationService\NotificationService.csproj'
        Exe         = 'NotificationService.exe'
        Url         = 'http://localhost:8082'
    },
    @{
        Name        = 'InstanaLab-OrderService'
        DisplayName = 'Instana Lab - Order Service'
        Description = 'Microservicio de ordenes para laboratorio Instana (orquestador)'
        Project     = Join-Path $repoRoot 'OrderService\OrderService.csproj'
        Exe         = 'OrderService.exe'
        Url         = 'http://localhost:8080'
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

    # ---- 2. Publicar ----
    Write-Host "`n[>>] Publicando $($svc.Name)..." -ForegroundColor Yellow
    & dotnet publish $svc.Project `
        --configuration Release `
        --runtime win-x64 `
        --self-contained true `
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
        # Usar & "sc.exe" para evitar el alias sc -> Set-Content de PowerShell
        & "$env:SystemRoot\System32\sc.exe" delete $svc.Name
        Start-Sleep -Seconds 3
    }

    # ---- 4. Crear servicio con New-Service (mas confiable que sc.exe en PS) ----
    Write-Host "[+] Creando servicio: $($svc.Name)" -ForegroundColor Green
    New-Service `
        -Name        $svc.Name `
        -DisplayName $svc.DisplayName `
        -Description $svc.Description `
        -BinaryPathName "`"$exePath`"" `
        -StartupType Automatic

    # ---- 5. Configurar variables de entorno del servicio en el registro ----
    $regPath  = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
    $envValue = @("ASPNETCORE_URLS=$($svc.Url)")
    New-ItemProperty -Path $regPath -Name 'Environment' `
        -Value $envValue -PropertyType MultiString -Force | Out-Null
    Write-Host "    Variable de entorno: ASPNETCORE_URLS=$($svc.Url)" -ForegroundColor DarkGray

    # ---- 6. Iniciar servicio ----
    Write-Host "[>] Iniciando $($svc.Name)..." -ForegroundColor Cyan
    Start-Service -Name $svc.Name
    Start-Sleep -Seconds 3

    $status = (Get-Service -Name $svc.Name).Status
    if ($status -eq 'Running') {
        Write-Host "    [OK] Estado: $status" -ForegroundColor Green
    } else {
        Write-Warning "    Estado inesperado: $status - Revisa el Event Viewer (eventvwr.msc) > Windows Logs > Application"
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Instalacion completada" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OrderService        -> http://localhost:8080/swagger"
Write-Host "  InventoryService    -> http://localhost:8081/swagger"
Write-Host "  NotificationService -> http://localhost:8082/swagger"
Write-Host ""
Write-Host "Para ver los servicios: services.msc  o  Get-Service 'InstanaLab-*'"
