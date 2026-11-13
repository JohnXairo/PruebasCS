#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Publica, instala y arranca los 3 microservicios como Windows Services.

.DESCRIPTION
    - Compila cada proyecto en modo Release (self-contained, win-x64)
    - Crea el servicio con sc.exe
    - Lo configura para arranque automatico
    - Lo inicia

.PARAMETER InstallDir
    Directorio donde se copiaran los binarios publicados.
    Por defecto: C:\InstanaLab

.EXAMPLE
    .\install-services.ps1
    .\install-services.ps1 -InstallDir D:\Servicios\InstanaLab
#>
param(
    [string]$InstallDir = 'C:\InstanaLab'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------
# Definicion de los 3 servicios
# ----------------------------------------------------------------
$services = @(
    @{
        Name        = 'InstanaLab-InventoryService'
        DisplayName = 'Instana Lab - Inventory Service'
        Description = 'Microservicio de inventario para laboratorio Instana'
        Project     = Join-Path $PSScriptRoot '..\InventoryService\InventoryService.csproj'
        Exe         = 'InventoryService.exe'
        Url         = 'http://localhost:8081'
    },
    @{
        Name        = 'InstanaLab-NotificationService'
        DisplayName = 'Instana Lab - Notification Service'
        Description = 'Microservicio de notificaciones para laboratorio Instana'
        Project     = Join-Path $PSScriptRoot '..\NotificationService\NotificationService.csproj'
        Exe         = 'NotificationService.exe'
        Url         = 'http://localhost:8082'
    },
    @{
        Name        = 'InstanaLab-OrderService'
        DisplayName = 'Instana Lab - Order Service'
        Description = 'Microservicio de ordenes para laboratorio Instana (orquestador)'
        Project     = Join-Path $PSScriptRoot '..\OrderService\OrderService.csproj'
        Exe         = 'OrderService.exe'
        Url         = 'http://localhost:8080'
    }
)
# OrderService depende de los otros dos, por eso va ultimo

# ----------------------------------------------------------------
# Crear directorio de instalacion
# ----------------------------------------------------------------
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
    Write-Host "[+] Directorio creado: $InstallDir" -ForegroundColor Cyan
}

foreach ($svc in $services) {
    $svcDir = Join-Path $InstallDir $svc.Name

    # ---- 1. Publicar ----
    Write-Host "`n[>>] Publicando $($svc.Name)..." -ForegroundColor Yellow
    dotnet publish $svc.Project `
        --configuration Release `
        --runtime win-x64 `
        --self-contained true `
        --output $svcDir

    if ($LASTEXITCODE -ne 0) { throw "Error publicando $($svc.Name)" }

    $exePath = Join-Path $svcDir $svc.Exe

    # ---- 2. Desinstalar si ya existe ----
    $existing = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "[!] Servicio existente encontrado, deteniendo y eliminando..." -ForegroundColor DarkYellow
        if ($existing.Status -eq 'Running') {
            Stop-Service -Name $svc.Name -Force
        }
        sc.exe delete $svc.Name | Out-Null
        Start-Sleep -Seconds 2
    }

    # ---- 3. Crear servicio ----
    Write-Host "[+] Creando servicio: $($svc.Name)" -ForegroundColor Green
    sc.exe create $svc.Name `
        binPath= "`"$exePath`"" `
        DisplayName= $svc.DisplayName `
        start= auto | Out-Null

    sc.exe description $svc.Name $svc.Description | Out-Null

    # ---- 4. Configurar URL en registro (variable de entorno del servicio) ----
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
    $envEntry = "ASPNETCORE_URLS=$($svc.Url)"
    New-ItemProperty -Path $regPath -Name 'Environment' `
        -Value @($envEntry) -PropertyType MultiString -Force | Out-Null

    # ---- 5. Iniciar servicio ----
    Write-Host "[>] Iniciando $($svc.Name)..." -ForegroundColor Cyan
    Start-Service -Name $svc.Name
    Start-Sleep -Seconds 2

    $status = (Get-Service -Name $svc.Name).Status
    Write-Host "    Estado: $status" -ForegroundColor $(if ($status -eq 'Running') { 'Green' } else { 'Red' })
}

Write-Host "`n[OK] Instalacion completada." -ForegroundColor Green
Write-Host "  OrderService       -> http://localhost:8080/swagger"
Write-Host "  InventoryService   -> http://localhost:8081/swagger"
Write-Host "  NotificationService-> http://localhost:8082/swagger"
