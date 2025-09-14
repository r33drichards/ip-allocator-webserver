use rocket::serde::json::Json;
use rocket::State;
use rocket_okapi::openapi;
use rocket_okapi::okapi::schemars::JsonSchema;
use rocket::serde::{Deserialize, Serialize};
use tokio::sync::Mutex;

use crate::error::{Error, OResult};
use crate::AppState;
use crate::store::Store;
use crate::guards::debug_header;

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
    store: &State<Mutex<Store>>,
    app: &State<AppState>,
    input: Json<ReturnIPInput>,
) -> OResult<ReturnIPOutput> {
    // Notify subscribers first; if a must-succeed fails, do not return IP
    if let Err((msg, _must)) = app.subs.notify_return(&app.config, &input.ip).await {
        return Err(Error::new("Subscriber Error", Some(&msg), 502));
    }

    let store = store.lock().await;
    match store.return_ip(&input.ip) {
        Ok(_) => Ok(Json(ReturnIPOutput {
            success: true,
            message: format!("Successfully returned IP: {}", input.ip),
        })),
        Err(e) => Err(crate::error::Error::from(e)),
    }
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