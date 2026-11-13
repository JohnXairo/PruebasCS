<#
.SYNOPSIS
    Muestra el estado de los 3 Windows Services del laboratorio Instana.
#>

$serviceNames = @(
    'InstanaLab-OrderService',
    'InstanaLab-InventoryService',
    'InstanaLab-NotificationService'
)

Write-Host "`n=== Estado de Servicios - Instana Lab ===`n" -ForegroundColor Cyan

foreach ($name in $serviceNames) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) {
        $color = if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' }
        Write-Host ("  {0,-45} [{1}]" -f $svc.DisplayName, $svc.Status) -ForegroundColor $color
    } else {
        Write-Host "  $name  [NO INSTALADO]" -ForegroundColor DarkYellow
    }
}

Write-Host ""
