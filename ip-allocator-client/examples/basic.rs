use ip_allocator_client::Client;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Create a new client
    let client = Client::new("http://localhost:8000");

    // Borrow an item from the freelist
    println!("🔄 Borrowing an item...");
    // First arg (params): Optional JSON string to pass to subscribers
    // Second arg (wait): None for immediate return, or Some(seconds) to wait for availability
    // Example: client.handlers_ip_borrow(Some("{\"key\":\"value\"}".into()), Some(30)).await?
    let borrow_result = client.handlers_ip_borrow(None, None).await?;
    println!("✅ Borrowed item: {:?}", borrow_result.item);
    println!("🎟️  Borrow token: {}", borrow_result.borrow_token);

    // Return the borrowed item to the freelist
    println!("\n🔄 Returning the item...");
    let return_input = ip_allocator_client::types::ReturnInput {
        item: borrow_result.item.clone(),
        borrow_token: borrow_result.borrow_token.clone(),
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
