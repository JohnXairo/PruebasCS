# Laboratorio Microservicios C# — Instrumentación IBM Instana
## Windows Server 2019 / Windows Services

Este repositorio contiene **3 microservicios ASP.NET Core (.NET 8)** que corren como **Windows Services nativos** en Windows Server 2019, se comunican entre sí vía HTTP y están diseñados para practicar la **instrumentación manual con IBM Instana**.

## Arquitectura

```
Cliente HTTP
    │
    ▼
┌─────────────────────┐  HTTP   ┌──────────────────────┐
│  OrderService       │────────▶│  InventoryService    │
│  localhost:8080     │         │  localhost:8081      │
│                     │  HTTP   └──────────────────────┘
│                     │────────▶  NotificationService  │
└─────────────────────┘         │  localhost:8082      │
                                └──────────────────────┘
```

| Servicio                | Puerto | Windows Service Name                  |
|-------------------------|--------|---------------------------------------|
| **OrderService**        | 8080   | `InstanaLab-OrderService`             |
| **InventoryService**    | 8081   | `InstanaLab-InventoryService`         |
| **NotificationService** | 8082   | `InstanaLab-NotificationService`      |

## Prerequisitos

1. **Windows Server 2019** (o Windows 10/11 para pruebas locales)
2. **.NET 8 SDK** → https://dotnet.microsoft.com/download/dotnet/8.0
   ```powershell
   winget install Microsoft.DotNet.SDK.8
   ```
3. **PowerShell 5.1+** (incluido en WS2019)
4. Consola con **privilegios de Administrador**

> Los binarios se publican como **self-contained** (`win-x64`), por lo que el runtime de .NET **no necesita estar instalado** en el servidor destino si se usa el exe publicado. El SDK solo se necesita para compilar.

## Instalación rápida

```powershell
# Desde PowerShell como Administrador
git clone https://github.com/JohnXairo/PruebasCS.git
cd PruebasCS
.\scripts\install-services.ps1
```

El script hace automáticamente:
1. `dotnet publish` de cada proyecto (Release, self-contained, win-x64)
2. `sc.exe create` para registrar cada Windows Service
3. Configura `ASPNETCORE_URLS` como variable de entorno del servicio en el registro
4. `Start-Service` para arrancarlos

Directorio de instalación por defecto: `C:\InstanaLab\`  
Puede cambiarse:
```powershell
.\scripts\install-services.ps1 -InstallDir 'D:\Servicios'
```

## Verificar estado

```powershell
.\scripts\status-services.ps1
# O con el cmdlet nativo:
Get-Service 'InstanaLab-*'
```

O desde **services.msc** buscando "Instana Lab".

## Endpoints / Swagger UI

| Servicio              | Swagger                                   |
|-----------------------|-------------------------------------------|
| OrderService          | http://localhost:8080/swagger             |
| InventoryService      | http://localhost:8081/swagger             |
| NotificationService   | http://localhost:8082/swagger             |

## Endpoints principales

### OrderService (`:8080`)
| Método | Ruta           | Descripción                                        |
|--------|----------------|----------------------------------------------------||
| GET    | /orders        | Lista todas las órdenes                            |
| GET    | /orders/{id}   | Obtiene una orden por ID                           |
| POST   | /orders        | Crea una orden (llama a Inventory y Notification)  |

Body POST `/orders`:
```json
{
  "productId": 1,
  "quantity": 2,
  "customerEmail": "cliente@ejemplo.com"
}
```

### InventoryService (`:8081`)
| Método | Ruta                   | Descripción                    |
|--------|------------------------|--------------------------------|
| GET    | /inventory             | Lista todos los productos      |
| GET    | /inventory/{productId} | Consulta stock de un producto  |
| POST   | /inventory/reserve     | Reserva unidades de stock      |

### NotificationService (`:8082`)
| Método | Ruta             | Descripción                     |
|--------|------------------|---------------------------------|
| POST   | /notifications   | Envía una notificación          |
| GET    | /notifications   | Historial de notificaciones     |

## Desinstalar

```powershell
.\scripts\uninstall-services.ps1
```

## Instrumentación manual con Instana

> La instrumentación la realizas manualmente siguiendo los pasos de la [documentación oficial de Instana para .NET](https://www.ibm.com/docs/en/instana-observability/current?topic=technologies-monitoring-net-core).

### Pasos resumidos para Windows

1. **Instalar el Instana Host Agent** en el servidor (descarga desde tu tenant de Instana).
2. **Agregar el NuGet de Instana** a cada proyecto:
   ```powershell
   cd OrderService
   dotnet add package Instana.Tracing.Instrumentation
   ```
3. **Configurar las variables de entorno del servicio** en el registro de Windows.  
   Las claves están en `HKLM:\SYSTEM\CurrentControlSet\Services\<NombreServicio>` → valor `Environment` (MultiString):
   ```
   CORECLR_ENABLE_PROFILING=1
   CORECLR_PROFILER={cf0d821e-299b-5307-a3d8-b283c03916dd}
   CORECLR_PROFILER_PATH=C:\instana\profiler\win-x64\instana_tracing_clrprofiler_x64.dll
   INSTANA_AGENT_HOST=localhost
   INSTANA_AGENT_PORT=42699
   ```
   Ejemplo en PowerShell (como Administrador):
   ```powershell
   $svc   = 'InstanaLab-OrderService'
   $reg   = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
   $current = (Get-ItemProperty $reg).Environment
   $instanaVars = @(
       'CORECLR_ENABLE_PROFILING=1',
       'CORECLR_PROFILER={cf0d821e-299b-5307-a3d8-b283c03916dd}',
       'CORECLR_PROFILER_PATH=C:\instana\profiler\win-x64\instana_tracing_clrprofiler_x64.dll',
       'INSTANA_AGENT_HOST=localhost',
       'INSTANA_AGENT_PORT=42699'
   )
   Set-ItemProperty $reg -Name 'Environment' -Value ($current + $instanaVars)
   Restart-Service $svc
   ```
4. **Reiniciar cada servicio** para que tome las variables.
5. **Verificar trazas** en la UI de Instana → Infrastructure → tu host → Calls.

## Scripts disponibles

| Script                        | Descripción                                   |
|-------------------------------|-----------------------------------------------|
| `scripts\install-services.ps1`   | Publica, instala y arranca los 3 servicios |
| `scripts\uninstall-services.ps1` | Detiene y elimina los 3 servicios         |
| `scripts\status-services.ps1`    | Muestra el estado de los 3 servicios      |
