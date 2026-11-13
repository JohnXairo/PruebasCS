use actix_web::{middleware::Logger, web, App, HttpResponse, HttpServer, Responder};
use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use chrono::Utc;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Modelos de request / response
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
struct SignRequest {
    key_id: String,
    algorithm: String, // e.g. "RSA-SHA256", "ECDSA-P256"
    payload: String,   // base64-encoded data to sign
}

#[derive(Debug, Serialize)]
struct SignResponse {
    operation_id: String,
    key_id: String,
    algorithm: String,
    signature: String, // base64-encoded simulated signature
    timestamp: String,
    status: String,
}

#[derive(Debug, Deserialize)]
struct EncryptRequest {
    key_id: String,
    algorithm: String, // e.g. "AES-256-GCM"
    plaintext: String, // base64-encoded plaintext
}

#[derive(Debug, Serialize)]
struct EncryptResponse {
    operation_id: String,
    key_id: String,
    ciphertext: String, // base64-encoded simulated ciphertext
    timestamp: String,
    status: String,
}

#[derive(Debug, Deserialize)]
struct GenerateKeyRequest {
    key_type: String,  // e.g. "RSA-2048", "AES-256", "EC-P256"
    label: String,
}

#[derive(Debug, Serialize)]
struct GenerateKeyResponse {
    operation_id: String,
    key_id: String,
    key_type: String,
    label: String,
    public_key: Option<String>, // base64, solo para claves asimetricas
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
// Handlers
// ---------------------------------------------------------------------------

/// GET /health
async fn health() -> impl Responder {
    HttpResponse::Ok().json(HealthResponse {
        service: "HsmServer".into(),
        version: env!("CARGO_PKG_VERSION").into(),
        hsm_status: "OPERATIONAL".into(),
        timestamp: Utc::now().to_rfc3339(),
    })
}

/// GET /hsm/keys  — lista de claves simuladas
async fn list_keys() -> impl Responder {
    let keys = vec![
        KeyInfo {
            key_id: "key-rsa-001".into(),
            key_type: "RSA-2048".into(),
            label: "signing-key-prod".into(),
            created_at: "2026-01-15T08:00:00Z".into(),
            status: "ACTIVE".into(),
        },
        KeyInfo {
            key_id: "key-aes-001".into(),
            key_type: "AES-256".into(),
            label: "encryption-key-prod".into(),
            created_at: "2026-01-15T08:01:00Z".into(),
            status: "ACTIVE".into(),
        },
        KeyInfo {
            key_id: "key-ec-001".into(),
            key_type: "EC-P256".into(),
            label: "ecdsa-key-prod".into(),
            created_at: "2026-02-10T10:00:00Z".into(),
            status: "ACTIVE".into(),
        },
    ];
    HttpResponse::Ok().json(keys)
}

/// POST /hsm/keys  — generar una nueva clave (simulada)
async fn generate_key(body: web::Json<GenerateKeyRequest>) -> impl Responder {
    log::info!("generate_key: type={} label={}", body.key_type, body.label);

    let mut rng = rand::thread_rng();
    let mut key_bytes = vec![0u8; 16];
    rng.fill_bytes(&mut key_bytes);
    let key_id = format!("key-{}", Uuid::new_v4());

    // Claves asimetricas exponen una clave publica simulada
    let public_key = match body.key_type.as_str() {
        t if t.starts_with("RSA") || t.starts_with("EC") => {
            let mut pub_bytes = vec![0u8; 64];
            rng.fill_bytes(&mut pub_bytes);
            Some(B64.encode(&pub_bytes))
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

/// POST /hsm/sign  — firmar datos (simulado)
async fn sign(body: web::Json<SignRequest>) -> impl Responder {
    log::info!("sign: key_id={} algorithm={}", body.key_id, body.algorithm);

    // Simular latencia de operacion HSM real (no bloqueante)
    tokio::time::sleep(std::time::Duration::from_millis(5)).await;

    let mut rng = rand::thread_rng();
    let mut sig_bytes = vec![0u8; 64];
    rng.fill_bytes(&mut sig_bytes);

    HttpResponse::Ok().json(SignResponse {
        operation_id: Uuid::new_v4().to_string(),
        key_id: body.key_id.clone(),
        algorithm: body.algorithm.clone(),
        signature: B64.encode(&sig_bytes),
        timestamp: Utc::now().to_rfc3339(),
        status: "SUCCESS".into(),
    })
}

/// POST /hsm/encrypt  — cifrar datos (simulado)
async fn encrypt(body: web::Json<EncryptRequest>) -> impl Responder {
    log::info!("encrypt: key_id={} algorithm={}", body.key_id, body.algorithm);

    tokio::time::sleep(std::time::Duration::from_millis(3)).await;

    // Simular ciphertext: bytes aleatorios del mismo tamano que el input
    let input_len = B64
        .decode(&body.plaintext)
        .map(|b| b.len())
        .unwrap_or(32);

    let mut rng = rand::thread_rng();
    let mut cipher_bytes = vec![0u8; input_len + 16]; // +16 simula GCM tag
    rng.fill_bytes(&mut cipher_bytes);

    HttpResponse::Ok().json(EncryptResponse {
        operation_id: Uuid::new_v4().to_string(),
        key_id: body.key_id.clone(),
        ciphertext: B64.encode(&cipher_bytes),
        timestamp: Utc::now().to_rfc3339(),
        status: "SUCCESS".into(),
    })
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Inicializar logger (RUST_LOG=info por defecto)
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or("info")
    ).init();

    let host = std::env::var("HSM_HOST").unwrap_or_else(|_| "0.0.0.0".into());
    let port: u16 = std::env::var("HSM_PORT")
        .unwrap_or_else(|_| "8083".into())
        .parse()
        .expect("HSM_PORT debe ser un numero valido");

    log::info!("HsmServer iniciando en http://{}:{}", host, port);

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
}
