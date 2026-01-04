use rocket::serde::json::Json;
use rocket::State;
use rocket_okapi::openapi;
use rocket_okapi::okapi::schemars::JsonSchema;
use rocket::serde::{Deserialize, Serialize};
use rocket::response::content::RawHtml;
use tokio::sync::Mutex;
use serde_json::Value;

use crate::error::{Error, OResult};
use crate::AppState;
use crate::store::Store;

#[derive(Serialize, Deserialize, JsonSchema)]
pub struct ItemsList {
    items: Vec<Value>,
    count: usize,
}

#[derive(Serialize, Deserialize, JsonSchema)]
pub struct BorrowedItem {
    item: Value,
    borrow_token: String,
}

#[derive(Serialize, Deserialize, JsonSchema)]
pub struct BorrowedItemsList {
    borrowed: Vec<BorrowedItem>,
    count: usize,
}

#[derive(Serialize, Deserialize, JsonSchema)]
pub struct DeleteItemInput {
    item: Value,
}

#[derive(Serialize, Deserialize, JsonSchema)]
pub struct ForceReturnInput {
    item: Value,
}

#[derive(Serialize, Deserialize, JsonSchema)]
pub struct SuccessResponse {
    success: bool,
    message: String,
}

#[derive(Serialize, Deserialize, JsonSchema)]
pub struct OperationsList {
    operations: Vec<OperationDetail>,
    count: usize,
}

#[derive(Serialize, Deserialize, JsonSchema)]
pub struct OperationDetail {
    id: String,
    item: Value,
    status: String,
    message: Option<String>,
}

#[derive(Serialize, Deserialize, JsonSchema)]
pub struct StatsResponse {
    free_count: usize,
    borrowed_count: usize,
    pending_operations: usize,
    failed_operations: usize,
}

/// List all items in the freelist (Admin)
#[openapi(tag = "Admin")]
#[get("/admin/items")]
pub async fn list_items(store: &State<Mutex<Store>>) -> OResult<ItemsList> {
    let store = store.lock().await;
    match store.list_all_items() {
        Ok(items) => {
            let count = items.len();
            Ok(Json(ItemsList { items, count }))
        }
        Err(e) => Err(Error::from(e)),
    }
}

/// List all borrowed items (Admin)
#[openapi(tag = "Admin")]
#[get("/admin/borrowed")]
pub async fn list_borrowed(store: &State<Mutex<Store>>) -> OResult<BorrowedItemsList> {
    let store = store.lock().await;
    match store.list_borrowed_items() {
        Ok(borrowed_tuples) => {
            let borrowed: Vec<BorrowedItem> = borrowed_tuples
                .into_iter()
                .map(|(item, borrow_token)| BorrowedItem { item, borrow_token })
                .collect();
            let count = borrowed.len();
            Ok(Json(BorrowedItemsList { borrowed, count }))
        }
        Err(e) => Err(Error::from(e)),
    }
}

/// Delete an item from the freelist (Admin)
#[openapi(tag = "Admin")]
#[delete("/admin/items", data = "<input>")]
pub async fn delete_item(
    store: &State<Mutex<Store>>,
    input: Json<DeleteItemInput>,
) -> OResult<SuccessResponse> {
    let store = store.lock().await;
    match store.delete_item(&input.item) {
        Ok(deleted) => {
            if deleted {
                Ok(Json(SuccessResponse {
                    success: true,
                    message: "Item deleted successfully".to_string(),
                }))
            } else {
                Err(Error::new("Not Found", Some("Item not found in freelist"), 404))
            }
        }
        Err(e) => Err(Error::from(e)),
    }
}

/// Force return a borrowed item (Admin)
#[openapi(tag = "Admin")]
#[post("/admin/force-return", data = "<input>")]
pub async fn force_return(
    store: &State<Mutex<Store>>,
    input: Json<ForceReturnInput>,
) -> OResult<SuccessResponse> {
    let store = store.lock().await;
    match store.force_return(&input.item) {
        Ok(_) => Ok(Json(SuccessResponse {
            success: true,
            message: "Item force-returned to freelist".to_string(),
        })),
        Err(e) => Err(Error::from(e)),
    }
}

/// Delete a borrowed item without returning it to the freelist (Admin)
#[openapi(tag = "Admin")]
#[delete("/admin/borrowed", data = "<input>")]
pub async fn delete_borrowed_item(
    store: &State<Mutex<Store>>,
    input: Json<DeleteItemInput>,
) -> OResult<SuccessResponse> {
    let store = store.lock().await;
    match store.delete_borrowed_item(&input.item) {
        Ok(deleted) => {
            if deleted {
                Ok(Json(SuccessResponse {
                    success: true,
                    message: "Borrowed item deleted successfully".to_string(),
                }))
            } else {
                Err(Error::new("Not Found", Some("Item not found in borrowed items"), 404))
            }
        }
        Err(e) => Err(Error::from(e)),
    }
}

/// List all operations (Admin)
#[openapi(tag = "Admin")]
#[get("/admin/operations")]
pub async fn list_operations(app: &State<AppState>) -> OResult<OperationsList> {
    let ops = app.ops.get_all().await;
    let operations: Vec<OperationDetail> = ops
        .into_iter()
        .map(|op| OperationDetail {
            id: op.id,
            item: op.item,
            status: format!("{:?}", op.status),
            message: op.message,
        })
        .collect();
    let count = operations.len();
    Ok(Json(OperationsList { operations, count }))
}

/// Delete an operation (Admin)
#[openapi(tag = "Admin")]
#[delete("/admin/operations/<id>")]
pub async fn delete_operation(app: &State<AppState>, id: &str) -> OResult<SuccessResponse> {
    if app.ops.delete(id).await {
        Ok(Json(SuccessResponse {
            success: true,
            message: "Operation deleted".to_string(),
        }))
    } else {
        Err(Error::new("Not Found", Some("Operation not found"), 404))
    }
}

/// Get system statistics (Admin)
#[openapi(tag = "Admin")]
#[get("/admin/stats")]
pub async fn get_stats(store: &State<Mutex<Store>>, app: &State<AppState>) -> OResult<StatsResponse> {
    let store = store.lock().await;

    let free_count = store.list_all_items().unwrap_or_default().len();
    let borrowed_count = store.list_borrowed_items().unwrap_or_default().len();

    let ops = app.ops.get_all().await;
    let pending_operations = ops.iter().filter(|op| {
        matches!(op.status, crate::ops::OperationStatus::Pending | crate::ops::OperationStatus::InProgress)
    }).count();
    let failed_operations = ops.iter().filter(|op| {
        matches!(op.status, crate::ops::OperationStatus::Failed)
    }).count();

    Ok(Json(StatsResponse {
        free_count,
        borrowed_count,
        pending_operations,
        failed_operations,
    }))
}

/// Serve the admin UI HTML page
#[get("/admin")]
pub async fn admin_ui() -> RawHtml<&'static str> {
    RawHtml(include_str!("../../static/admin.html"))
}

/// Serve the admin favicon SVG
#[get("/static/admin-favicon.svg")]
pub async fn admin_favicon() -> (rocket::http::ContentType, &'static str) {
    (rocket::http::ContentType::SVG, include_str!("../../static/admin-favicon.svg"))
}
