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
use serde_json::Value;

#[derive(Serialize, Deserialize, JsonSchema, Clone)]
pub struct ReturnInput {
    item: Value,
    borrow_token: String,
}

#[derive(Serialize, Deserialize, JsonSchema, Clone)]
pub struct SubmitInput {
    item: Value,
}

#[derive(Serialize, Deserialize, JsonSchema, Clone)]
pub struct ReturnIPOutput {
    success: bool,
    message: String,
}

#[derive(Serialize, Deserialize, JsonSchema, Clone)]
pub struct BorrowOutput {
    item: Value,
    borrow_token: String,
}

// listing is intentionally removed for generic store

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

/// Borrow an item from the freelist
///
/// Returns an item along with a borrow_token that must be provided when returning the item.
/// Optional query parameter `wait` specifies the maximum number of seconds to wait
/// for an item to become available. If not specified, returns immediately.
/// If specified, the request will block until an item becomes available or the timeout is reached.
#[openapi]
#[get("/borrow?<wait>")]
pub async fn borrow(
    store: &State<Mutex<Store>>,
    app: &State<AppState>,
    wait: Option<u64>,
) -> OResult<BorrowOutput> {
    let store = store.lock().await;

    // Determine whether to use blocking or non-blocking borrow
    let result = if let Some(wait_secs) = wait {
        // Use blocking borrow with timeout
        use std::time::Duration;
        store.borrow_blocking(Duration::from_secs(wait_secs))
    } else {
        // Use non-blocking borrow (original behavior)
        store.borrow()
    };

    match result {
        Ok(item) => {
            if let Err((msg, _must)) = app.subs.notify_borrow(&app.config, &item).await {
                // On subscriber failure for must-succeed, return item to freelist as rollback
                let _ = store.return_item(&item);
                return Err(Error::new("Subscriber Error", Some(&msg), 502));
            }

            // Generate a borrow token and record the borrowed item
            let borrow_token = uuid::Uuid::new_v4().to_string();
            if let Err(e) = store.record_borrowed(&item, &borrow_token) {
                // Failed to record borrow - rollback by returning item to freelist
                let _ = store.return_item(&item);
                return Err(Error::from(e));
            }

            Ok(Json(BorrowOutput { item, borrow_token }))
        }
        Err(e) => Err(crate::error::Error::from(e)),
    }
}

/// Return an item to the freelist
///
/// Requires the borrow_token that was provided when the item was borrowed.
/// This prevents accidentally returning an item currently borrowed by someone else.
#[openapi]
#[post("/return", data = "<input>")]
pub async fn return_item(
    store: &State<Mutex<Store>>,
    app: &State<AppState>,
    input: Json<ReturnInput>,
) -> OResult<OperationRef> {
    // Verify the borrow token before proceeding
    let store_lock = store.lock().await;
    if let Err(e) = store_lock.verify_borrow_token(&input.item, &input.borrow_token) {
        return Err(Error::from(e));
    }
    drop(store_lock); // Release lock before spawning async task

    // Create operation
    let op_id = uuid::Uuid::new_v4().to_string();
    let op_id_resp = op_id.clone();
    let item_value = input.item.clone();
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
        let _ = ops.create(op_id.clone(), item_value.clone(), must).await;
        sse.notify(&op_id, serde_json::json!({"event":"created"}).to_string()).await;

        // Run notifications sequentially respecting must-succeed
        match subs.notify_return(&cfg, &item_value).await {
            Ok(()) => {
                ops.set_status(&op_id, OperationStatus::InProgress).await;
                sse.notify(&op_id, serde_json::json!({"event":"notifications_ok"}).to_string()).await;
                let store = Store::new(redis_url);
                match store.return_item(&item_value) {
                    Ok(_) => {
                        // Remove the borrowed record after successful return
                        let _ = store.remove_borrowed_record(&item_value);
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

/// Submit an item to the freelist
///
/// Adds an item to the freelist without requiring a borrow token.
/// This allows items to be added directly to the freelist.
#[openapi]
#[post("/submit", data = "<input>")]
pub async fn submit_item(
    _store: &State<Mutex<Store>>,
    app: &State<AppState>,
    input: Json<SubmitInput>,
) -> OResult<OperationRef> {
    // No borrow token verification needed - direct submission

    // Create operation
    let op_id = uuid::Uuid::new_v4().to_string();
    let op_id_resp = op_id.clone();
    let item_value = input.item.clone();
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
        for (name, def) in &cfg.submit.subscribers {
            if def.mustSuceed {
                must.insert(name.clone());
            }
        }
        let _ = ops.create(op_id.clone(), item_value.clone(), must).await;
        sse.notify(&op_id, serde_json::json!({"event":"created"}).to_string()).await;

        // Run notifications sequentially respecting must-succeed
        match subs.notify_submit(&cfg, &item_value).await {
            Ok(()) => {
                ops.set_status(&op_id, OperationStatus::InProgress).await;
                sse.notify(&op_id, serde_json::json!({"event":"notifications_ok"}).to_string()).await;
                let store = Store::new(redis_url);
                match store.return_item(&item_value) {
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

// list endpoint removed

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