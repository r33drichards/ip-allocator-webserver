use ip_allocator_client::Client;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Create a new client
    let client = Client::new("http://localhost:8000");

    // Borrow an item from the freelist
    println!("🔄 Borrowing an item...");
    // Pass None for immediate return, or Some(seconds) to wait for availability
    // Example: client.handlers_ip_borrow(Some(30)).await? // Wait up to 30 seconds
    let borrow_result = client.handlers_ip_borrow(None).await?;
    println!("✅ Borrowed item: {:?}", borrow_result);

    // Return an item to the freelist
    println!("\n🔄 Returning an item...");
    let return_input = ip_allocator_client::types::ReturnInput {
        item: serde_json::json!({"ip": "192.168.1.100"}),
    };
    let return_result = client.handlers_ip_return_item(&return_input).await?;
    println!("✅ Return operation initiated: {:?}", return_result);

    // Check operation status
    println!("\n🔄 Checking operation status...");
    let status = client
        .handlers_ip_get_operation_status(&return_result.operation_id)
        .await?;
    println!("✅ Operation status: {:?}", status);

    Ok(())
}
