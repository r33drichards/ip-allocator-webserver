use rocket::serde::json::Json;
use rocket::State;
use rocket_okapi::openapi;
use rocket_okapi::okapi::schemars::JsonSchema;
use rocket::serde::{Deserialize, Serialize};
use tokio::sync::Mutex;

use crate::error::{Error, OResult};
use crate::AppState;
use crate::store::Store;
use crate::ops::OperationStatus;
use rocket::response::stream::{Event, EventStream};
use rocket::tokio::time::{interval, Duration};

#[derive(Serialize, Deserialize, JsonSchema, Clone)]
pub struct ReturnIPInput {
    ip: String,
}

#[derive(Serialize, Deserialize, JsonSchema, Clone)]
pub struct ReturnIPOutput {
    success: bool,
    message: String,
}

#[derive(Serialize, Deserialize, JsonSchema, Clone)]
pub struct BorrowIPOutput {
    ip: String,
}

#[derive(Serialize, Deserialize, JsonSchema, Clone)]
pub struct ListIPsOutput {
    ips: Vec<String>,
}

#[derive(Serialize, Deserialize, JsonSchema, Clone)]
pub struct OperationRef {
    operation_id: String,
    status: String,
}

#[derive(Serialize, Deserialize, JsonSchema, Clone)]
pub struct OperationStatusOutput {
    operation_id: String,
    status: String,
    message: Option<String>,
}

/// Borrow an IP address from the freelist
#[openapi]
#[get("/ip/borrow")]
pub async fn borrow_ip(
    store: &State<Mutex<Store>>,
    app: &State<AppState>,
) -> OResult<BorrowIPOutput> {
    let store = store.lock().await;
    match store.borrow_ip() {
        Ok(ip) => {
            if let Err((msg, _must)) = app.subs.notify_borrow(&app.config, &ip).await {
                // On borrow failure for must-succeed subscriber, return IP to freelist as rollback
                let _ = store.return_ip(&ip);
                return Err(Error::new("Subscriber Error", Some(&msg), 502));
            }
            Ok(Json(BorrowIPOutput { ip }))
        }
        Err(e) => Err(crate::error::Error::from(e)),
    }
}

/// Return an IP address to the freelist
#[openapi]
#[post("/ip/return", data = "<input>")]
pub async fn return_ip(
    _store: &State<Mutex<Store>>,
    app: &State<AppState>,
    input: Json<ReturnIPInput>,
) -> OResult<OperationRef> {
    // Create operation
    let op_id = uuid::Uuid::new_v4().to_string();
    let op_id_resp = op_id.clone();
    let ip_value = input.ip.clone();
    let subs = app.subs.clone();
    let ops = app.ops.clone();
    let sse = app.sse.clone();
    let cfg = app.config.clone();
    let redis_url = app.redis_url.clone();

    // Spawn workflow in background
    tokio::spawn(async move {
        use std::collections::HashSet;
        // identify must-succeed subscribers
        let mut must: HashSet<String> = HashSet::new();
        for (name, def) in &cfg.r#return.subscribers {
            if def.mustSuceed {
                must.insert(name.clone());
            }
        }
        let _ = ops.create(op_id.clone(), ip_value.clone(), must).await;
        sse.notify(&op_id, serde_json::json!({"event":"created"}).to_string()).await;

        // Run notifications sequentially respecting must-succeed
        match subs.notify_return(&cfg, &ip_value).await {
            Ok(()) => {
                ops.set_status(&op_id, OperationStatus::InProgress).await;
                sse.notify(&op_id, serde_json::json!({"event":"notifications_ok"}).to_string()).await;
                let store = Store::new(redis_url);
                match store.return_ip(&ip_value) {
                    Ok(_) => {
                        ops.set_status(&op_id, OperationStatus::Succeeded).await;
                        sse.notify(&op_id, serde_json::json!({"event":"completed"}).to_string()).await;
                    }
                    Err(e) => {
                        ops.update_message(&op_id, Some(e.to_string())).await;
                        ops.set_status(&op_id, OperationStatus::Failed).await;
                        sse.notify(&op_id, serde_json::json!({"event":"failed","reason":e.to_string()}).to_string()).await;
                    }
                }
            }
            Err((msg, _)) => {
                ops.update_message(&op_id, Some(msg.clone())).await;
                ops.set_status(&op_id, OperationStatus::Failed).await;
                sse.notify(&op_id, serde_json::json!({"event":"failed","reason":msg}).to_string()).await;
            }
        }
    });

    Ok(Json(OperationRef { operation_id: op_id_resp, status: "accepted".to_string() }))
}

/// List all available IP addresses in the freelist
#[openapi]
#[get("/ip/list")]
pub async fn list_ips(
    store: &State<Mutex<Store>>,
) -> OResult<ListIPsOutput> {
    let store = store.lock().await;
    
    match store.list_ips() {
        Ok(ips) => {
            Ok(Json(ListIPsOutput {
                ips: ips.into_iter().collect(),
            }))
        },
        Err(e) => {
            Err(crate::error::Error::from(e))
        }
    }
}

/// Poll the status of an async operation
#[openapi]
#[get("/operations/<id>")]
pub async fn get_operation_status(app: &State<AppState>, id: &str) -> OResult<OperationStatusOutput> {
    if let Some(op) = app.ops.get(id).await {
        Ok(Json(OperationStatusOutput {
            operation_id: op.id,
            status: format!("{:?}", op.status).to_lowercase(),
            message: op.message,
        }))
    } else {
        Err(Error::new("Not Found", Some("operation not found"), 404))
    }
}

/// Subscribe to Server-Sent Events for an operation
#[get("/operations/<id>/events")] 
pub async fn stream_operation_events(app: &State<AppState>, id: &str) -> EventStream![] {
    let mut rx = app.sse.subscribe(id).await;
    EventStream! {
        let mut ping = interval(Duration::from_secs(15));
        loop {
            tokio::select! {
                Ok(msg) = rx.recv() => yield Event::data(msg),
                _ = ping.tick() => yield Event::data("ping"),
            }
        }
    }
}