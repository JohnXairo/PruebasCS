#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Reinicia los 3 Windows Services del laboratorio Instana.
    Util tras cambios de configuracion o actualizacion de binarios.
#>

$serviceNames = @(
    'InstanaLab-InventoryService',
    'InstanaLab-NotificationService',
    'InstanaLab-OrderService'
)

Write-Host "`n=== Reiniciando servicios Instana Lab ===`n" -ForegroundColor Cyan

foreach ($name in $serviceNames) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Warning "$name no encontrado. Ejecuta install-services.ps1 primero."
        continue
    }
    Write-Host "[>] Reiniciando $name..." -ForegroundColor Yellow
    Restart-Service -Name $name -Force
    Start-Sleep -Seconds 2
    $status = (Get-Service -Name $name).Status
    Write-Host "    Estado: $status" -ForegroundColor $(if ($status -eq 'Running') {'Green'} else {'Red'})
}

Write-Host ""
