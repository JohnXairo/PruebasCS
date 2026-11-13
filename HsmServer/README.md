# HsmServer — Rust

Servicio HTTP simulando un **Hardware Security Module (HSM)** desarrollado en Rust con [Actix-Web](https://actix.rs/). Diseñado para el laboratorio de instrumentación con IBM Instana.

## Puerto
`8083`

## Prerequisitos

- [Rust toolchain](https://rustup.rs/) (incluye `cargo`)
- Target Windows: `rustup target add x86_64-pc-windows-msvc`
- Visual Studio Build Tools (MSVC linker)

## Compilar y ejecutar localmente

```powershell
cd HsmServer
cargo run
# Escucha en http://0.0.0.0:8083
```

## Instalar como Windows Service

```powershell
# Desde PowerShell como Administrador, en la raiz del repo:
.\scripts\install-hsmserver.ps1
```

## Endpoints

| Método | Ruta           | Descripción                        |
|--------|----------------|------------------------------------|
| GET    | /health        | Estado del servicio HSM            |
| GET    | /hsm/keys      | Lista las claves disponibles       |
| POST   | /hsm/keys      | Genera una nueva clave             |
| POST   | /hsm/sign      | Firma datos con una clave          |
| POST   | /hsm/encrypt   | Cifra datos con una clave          |

### POST /hsm/keys
```json
{ "key_type": "RSA-2048", "label": "mi-clave" }
```

### POST /hsm/sign
```json
{ "key_id": "key-rsa-001", "algorithm": "RSA-SHA256", "payload": "aGVsbG8=" }
```

### POST /hsm/encrypt
```json
{ "key_id": "key-aes-001", "algorithm": "AES-256-GCM", "plaintext": "aGVsbG8=" }
```

## Instrumentación Instana

El servicio incluye las dependencias de OpenTelemetry (`opentelemetry`, `opentelemetry-otlp`, `tracing-opentelemetry`) listas para configurar el agente Instana.

Variables de entorno relevantes:

| Variable              | Valor por defecto | Descripción                    |
|-----------------------|-------------------|--------------------------------|
| `HSM_HOST`            | `0.0.0.0`         | Interfaz de escucha            |
| `HSM_PORT`            | `8083`            | Puerto HTTP                    |
| `RUST_LOG`            | `info`            | Nivel de log                   |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | —       | Endpoint OTLP del Instana Agent|
