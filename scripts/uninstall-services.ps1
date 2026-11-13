#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Detiene y elimina los 3 Windows Services del laboratorio Instana.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$serviceNames = @(
    'InstanaLab-OrderService',
    'InstanaLab-InventoryService',
    'InstanaLab-NotificationService'
)

foreach ($name in $serviceNames) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -eq 'Running') {
            Write-Host "[>] Deteniendo $name..." -ForegroundColor Yellow
            Stop-Service -Name $name -Force
            Start-Sleep -Seconds 2
        }
        Write-Host "[-] Eliminando $name..." -ForegroundColor Red
        sc.exe delete $name | Out-Null
        Write-Host "    Eliminado." -ForegroundColor DarkGray
    } else {
        Write-Host "[i] $name no encontrado, omitiendo." -ForegroundColor DarkGray
    }
}

Write-Host "`n[OK] Desinstalacion completada." -ForegroundColor Green
