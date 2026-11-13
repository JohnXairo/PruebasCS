# Laboratorio Microservicios C# — Instrumentación IBM Instana

Este repositorio contiene **3 microservicios ASP.NET Core (.NET 8)** que se comunican entre sí vía HTTP, diseñados para practicar la **instrumentación manual con IBM Instana**.

## Arquitectura

```
Cliente HTTP
    │
    ▼
┌─────────────┐    HTTP    ┌───────────────────┐
│ OrderService│──────────▶│ InventoryService   │
│  :8080      │           │  :8081             │
│             │    HTTP    └───────────────────┘
│             │──────────▶ NotificationService │
└─────────────┘            :8082               │
                           └───────────────────┘
```

| Servicio               | Puerto | Responsabilidad                               |
|------------------------|--------|-----------------------------------------------|
| **OrderService**       | 8080   | Crear y consultar órdenes; orquesta los demás |
| **InventoryService**   | 8081   | Consultar stock y reservar unidades           |
| **NotificationService**| 8082   | Enviar notificaciones al cliente              |

## Prerequisitos

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Docker + Docker Compose](https://docs.docker.com/get-docker/)
- Instana Agent corriendo en el host (puerto 42699)

## Levantar con Docker Compose

```bash
docker-compose up --build
```

Endpoints disponibles:
- Swagger OrderService → http://localhost:8080/swagger
- Swagger InventoryService → http://localhost:8081/swagger
- Swagger NotificationService → http://localhost:8082/swagger

## Endpoints principales

### OrderService (`:8080`)
| Método | Ruta           | Descripción                                        |
|--------|----------------|----------------------------------------------------|
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
| Método | Ruta             | Descripción                         |
|--------|------------------|-------------------------------------|
| POST   | /notifications   | Envía una notificación              |
| GET    | /notifications   | Historial de notificaciones         |

## Instrumentación manual con Instana

> La instrumentación la realizas manualmente siguiendo los pasos de la [documentación oficial de Instana para .NET](https://www.ibm.com/docs/en/instana-observability/current?topic=technologies-monitoring-net-core).

### Pasos resumidos

1. **Instalar el Instana .NET Agent** en el host o como sidecar.
2. **Agregar el NuGet de Instana** a cada proyecto:
   ```bash
   dotnet add package Instana.Tracing.Instrumentation
   ```
3. **Configurar variables de entorno** `CORECLR_ENABLE_PROFILING`, `CORECLR_PROFILER`, `CORECLR_PROFILER_PATH`, `INSTANA_AGENT_HOST` y `INSTANA_AGENT_PORT` (ver comentarios en `docker-compose.yml`).
4. **Verificar trazas** en la UI de Instana → Infrastructure → tu host → Calls.

## Variables de entorno relevantes

| Variable                        | Valor por defecto               | Descripción                   |
|---------------------------------|---------------------------------|-------------------------------|
| `INSTANA_AGENT_HOST`            | `host.docker.internal`          | Host del Instana Agent        |
| `INSTANA_AGENT_PORT`            | `42699`                         | Puerto del Instana Agent      |
| `Services__InventoryService`    | `http://inventoryservice:8081`  | URL del Inventory Service     |
| `Services__NotificationService` | `http://notificationservice:8082` | URL del Notification Service |
