use actix_web::{middleware::Logger, web, App, HttpResponse, HttpServer, Responder};
use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use chrono::Utc;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
struct SignRequest {
    key_id: String,
    algorithm: String,
    payload: String,
}

#[derive(Debug, Serialize)]
struct SignResponse {
    operation_id: String,
    key_id: String,
    algorithm: String,
    signature: String,
    timestamp: String,
    status: String,
}

#[derive(Debug, Deserialize)]
struct EncryptRequest {
    key_id: String,
    algorithm: String,
    plaintext: String,
}

#[derive(Debug, Serialize)]
struct EncryptResponse {
    operation_id: String,
    key_id: String,
    ciphertext: String,
    timestamp: String,
    status: String,
}

#[derive(Debug, Deserialize)]
struct GenerateKeyRequest {
    key_type: String,
    label: String,
}

#[derive(Debug, Serialize)]
struct GenerateKeyResponse {
    operation_id: String,
    key_id: String,
    key_type: String,
    label: String,
    public_key: Option<String>,
    created_at: String,
    status: String,
}

#[derive(Debug, Serialize)]
struct KeyInfo {
    key_id: String,
    key_type: String,
    label: String,
    created_at: String,
    status: String,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    service: String,
    version: String,
    hsm_status: String,
    timestamp: String,
}

// ---------------------------------------------------------------------------
// Handlers HTTP
// ---------------------------------------------------------------------------

async fn health() -> impl Responder {
    HttpResponse::Ok().json(HealthResponse {
        service: "HsmServer".into(),
        version: env!("CARGO_PKG_VERSION").into(),
        hsm_status: "OPERATIONAL".into(),
        timestamp: Utc::now().to_rfc3339(),
    })
}

async fn list_keys() -> impl Responder {
    let keys = vec![
        KeyInfo { key_id: "key-rsa-001".into(), key_type: "RSA-2048".into(), label: "signing-key-prod".into(),    created_at: "2026-01-15T08:00:00Z".into(), status: "ACTIVE".into() },
        KeyInfo { key_id: "key-aes-001".into(), key_type: "AES-256".into(),  label: "encryption-key-prod".into(), created_at: "2026-01-15T08:01:00Z".into(), status: "ACTIVE".into() },
        KeyInfo { key_id: "key-ec-001".into(),  key_type: "EC-P256".into(),  label: "ecdsa-key-prod".into(),     created_at: "2026-02-10T10:00:00Z".into(), status: "ACTIVE".into() },
    ];
    HttpResponse::Ok().json(keys)
}

async fn generate_key(body: web::Json<GenerateKeyRequest>) -> impl Responder {
    let mut rng = rand::thread_rng();
    let key_id = format!("key-{}", Uuid::new_v4());
    let public_key = match body.key_type.as_str() {
        t if t.starts_with("RSA") || t.starts_with("EC") => {
            let mut b = vec![0u8; 64]; rng.fill_bytes(&mut b); Some(B64.encode(&b))
        }
        _ => None,
    };
    HttpResponse::Created().json(GenerateKeyResponse {
        operation_id: Uuid::new_v4().to_string(),
        key_id,
        key_type: body.key_type.clone(),
        label: body.label.clone(),
        public_key,
        created_at: Utc::now().to_rfc3339(),
        status: "CREATED".into(),
    })
}

async fn sign(body: web::Json<SignRequest>) -> impl Responder {
    tokio::time::sleep(std::time::Duration::from_millis(5)).await;
    let mut rng = rand::thread_rng();
    let mut sig = vec![0u8; 64]; rng.fill_bytes(&mut sig);
    HttpResponse::Ok().json(SignResponse {
        operation_id: Uuid::new_v4().to_string(),
        key_id: body.key_id.clone(),
        algorithm: body.algorithm.clone(),
        signature: B64.encode(&sig),
        timestamp: Utc::now().to_rfc3339(),
        status: "SUCCESS".into(),
    })
}

async fn encrypt(body: web::Json<EncryptRequest>) -> impl Responder {
    tokio::time::sleep(std::time::Duration::from_millis(3)).await;
    let input_len = B64.decode(&body.plaintext).map(|b| b.len()).unwrap_or(32);
    let mut rng = rand::thread_rng();
    let mut cipher = vec![0u8; input_len + 16]; rng.fill_bytes(&mut cipher);
    HttpResponse::Ok().json(EncryptResponse {
        operation_id: Uuid::new_v4().to_string(),
        key_id: body.key_id.clone(),
        ciphertext: B64.encode(&cipher),
        timestamp: Utc::now().to_rfc3339(),
        status: "SUCCESS".into(),
    })
}

// ---------------------------------------------------------------------------
// Logica del servidor HTTP (compartida entre modo servicio y modo consola)
// ---------------------------------------------------------------------------

pub fn run_server() -> std::io::Result<()> {
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or("info")
    ).init();

    let host = std::env::var("HSM_HOST").unwrap_or_else(|_| "0.0.0.0".into());
    let port: u16 = std::env::var("HSM_PORT")
        .unwrap_or_else(|_| "8083".into())
        .parse()
        .unwrap_or(8083);

    log::info!("HsmServer iniciando en http://{}:{}", host, port);

    let rt = tokio::runtime::Runtime::new()?;
    rt.block_on(async {
        HttpServer::new(|| {
            App::new()
                .wrap(Logger::default())
                .route("/health",      web::get().to(health))
                .route("/hsm/keys",    web::get().to(list_keys))
                .route("/hsm/keys",    web::post().to(generate_key))
                .route("/hsm/sign",    web::post().to(sign))
                .route("/hsm/encrypt", web::post().to(encrypt))
        })
        .bind((host.as_str(), port))?
        .run()
        .await
    })
}

// ---------------------------------------------------------------------------
// Windows Service
// ---------------------------------------------------------------------------

#[cfg(windows)]
mod windows_service_impl {
    use windows_service::{
        define_windows_service,
        service::{
            ServiceControl, ServiceControlAccept, ServiceExitCode,
            ServiceState, ServiceStatus, ServiceType,
        },
        service_control_handler::{self, ServiceControlHandlerResult},
        service_dispatcher,
    };
    use std::sync::mpsc;
    use std::time::Duration;

    const SERVICE_NAME: &str = "InstanaLab-HsmServer";

    define_windows_service!(ffi_service_main, service_main);

    pub fn run_as_service() -> windows_service::Result<()> {
        service_dispatcher::start(SERVICE_NAME, ffi_service_main)
    }

    fn service_main(_args: Vec<std::ffi::OsString>) {
        let (shutdown_tx, shutdown_rx) = mpsc::channel();

        let status_handle = service_control_handler::register(
            SERVICE_NAME,
            move |ctrl| match ctrl {
                ServiceControl::Stop => {
                    let _ = shutdown_tx.send(());
                    ServiceControlHandlerResult::NoError
                }
                ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
                _ => ServiceControlHandlerResult::NotImplemented,
            },
        ).unwrap();

        // Reportar: iniciando
        status_handle.set_service_status(ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: ServiceState::StartPending,
            controls_accepted: ServiceControlAccept::empty(),
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::from_secs(10),
            process_id: None,
        }).unwrap();

        // Lanzar el servidor HTTP en un hilo separado
        std::thread::spawn(|| {
            if let Err(e) = crate::run_server() {
                log::error!("Error en servidor HTTP: {}", e);
            }
        });

        // Reportar: corriendo
        status_handle.set_service_status(ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: ServiceState::Running,
            controls_accepted: ServiceControlAccept::STOP,
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::from_secs(0),
            process_id: None,
        }).unwrap();

        // Esperar senal de stop
        let _ = shutdown_rx.recv();

        // Reportar: deteniendo
        status_handle.set_service_status(ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: ServiceState::Stopped,
            controls_accepted: ServiceControlAccept::empty(),
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::from_secs(0),
            process_id: None,
        }).unwrap();
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn main() {
    #[cfg(windows)]
    {
        // Si se lanza desde el SCM, correr como servicio.
        // Si se lanza desde consola (interactivo), correr directo.
        if std::env::var("HSM_CONSOLE").is_ok() {
            run_server().unwrap();
        } else {
            match windows_service_impl::run_as_service() {
                Ok(_) => {}
                Err(_) => {
                    // Fallo al conectar con SCM: probablemente modo consola
                    run_server().unwrap();
                }
            }
        }
    }

    #[cfg(not(windows))]
    run_server().unwrap();
}
