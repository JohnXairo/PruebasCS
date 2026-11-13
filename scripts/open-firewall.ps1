#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Abre los puertos TCP 8080, 8081 y 8082 en el Firewall de Windows
    para que los servicios del laboratorio Instana sean accesibles desde la red.

.NOTES
    Ejecutar como Administrador.
    Tambien puede usarse para reparar las reglas si fueron borradas.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ports = @(
    @{ Port = 8080; Service = 'OrderService' },
    @{ Port = 8081; Service = 'InventoryService' },
    @{ Port = 8082; Service = 'NotificationService' }
)

Write-Host "`n=== Configurando reglas de Firewall ===`n" -ForegroundColor Cyan

foreach ($entry in $ports) {
    $ruleName = "InstanaLab-$($entry.Port)-TCP"

    # Eliminar si ya existe para recrear limpia
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-NetFirewallRule -DisplayName $ruleName
        Write-Host "[~] Regla existente eliminada: $ruleName" -ForegroundColor DarkYellow
    }

    New-NetFirewallRule `
        -DisplayName  $ruleName `
        -Direction    Inbound `
        -Protocol     TCP `
        -LocalPort    $entry.Port `
        -Action       Allow `
        -Profile      Any | Out-Null

    Write-Host "[+] Puerto $($entry.Port) TCP abierto  ($($entry.Service))" -ForegroundColor Green
}

Write-Host ""
Write-Host "Verificacion actual de puertos en escucha (netstat):" -ForegroundColor Cyan
netstat -ano | Select-String -Pattern ':808[012]'

$ip = (Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.InterfaceAlias -notlike '*Loopback*' } |
       Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "Accede desde otra maquina con:" -ForegroundColor Cyan
Write-Host "  http://${ip}:8080/swagger   (OrderService)"
Write-Host "  http://${ip}:8081/swagger   (InventoryService)"
Write-Host "  http://${ip}:8082/swagger   (NotificationService)"
