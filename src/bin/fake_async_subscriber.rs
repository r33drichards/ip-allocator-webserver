use std::collections::HashMap;
use std::env;
use std::time::Duration;

use rocket::serde::{Deserialize, Serialize, json::Json};
use rocket::{get, post, routes, State};
use tokio::sync::Mutex;

#[derive(Clone)]
struct AppState {
    operations: std::sync::Arc<Mutex<HashMap<String, bool>>>,
    delay: Duration,
}

#[derive(Deserialize)]
#[serde(crate = "rocket::serde")]
struct ReturnPayload {
    ip: String,
}

#[derive(Serialize)]
#[serde(crate = "rocket::serde")]
struct AckResponse {
    operation_id: String,
    status: String,
}

#[derive(Serialize)]
#[serde(crate = "rocket::serde")]
struct StatusResponse {
    status: String,
    message: Option<String>,
}

#[post("/return", data = "<payload>")]
async fn handle_return(state: &State<AppState>, payload: Json<ReturnPayload>) -> Json<AckResponse> {
    let _ip = payload.ip.clone();
    let op_id = uuid::Uuid::new_v4().to_string();
    let op_id_resp = op_id.clone();

    {
        let mut ops = state.operations.lock().await;
        ops.insert(op_id.clone(), false);
    }

    let operations = state.operations.clone();
    let delay = state.delay;
    tokio::spawn(async move {
        tokio::time::sleep(delay).await;
        let mut ops = operations.lock().await;
        if let Some(done) = ops.get_mut(&op_id) {
            *done = true;
        }
    });

    Json(AckResponse { operation_id: op_id_resp, status: "accepted".to_string() })
}

#[get("/operations/status?<id>")] 
async fn get_status(state: &State<AppState>, id: &str) -> Json<StatusResponse> {
    let ops = state.operations.lock().await;
    let status = match ops.get(id) {
        Some(true) => "succeeded".to_string(),
        Some(false) => "pending".to_string(),
        None => "pending".to_string(),
    };
    Json(StatusResponse { status, message: None })
}

#[rocket::launch]
fn rocket() -> _ {
    let delay_secs: u64 = env::var("FAKE_SUB_DELAY_SECS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(15);

    rocket::build()
        .manage(AppState {
            operations: std::sync::Arc::new(Mutex::new(HashMap::new())),
            delay: Duration::from_secs(delay_secs),
        })
        .mount("/", routes![handle_return, get_status])
}


