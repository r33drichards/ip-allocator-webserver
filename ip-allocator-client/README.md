# IP Allocator Client

Rust API client for the IP Allocator webserver, auto-generated from the OpenAPI specification using [progenitor](https://github.com/oxidecomputer/progenitor).

## Installation

Add this to your `Cargo.toml`:

```toml
[dependencies]
ip-allocator-client = "0.1"
```

## Usage

```rust
use ip_allocator_client::Client;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Create a new client
    let client = Client::new("http://localhost:8000")?;

    // Borrow an item from the freelist
    let result = client.handlers_ip_borrow().await?;
    println!("Borrowed item: {:?}", result);

    // Return an item
    let return_result = client.handlers_ip_return_item(
        &ip_allocator_client::types::ReturnInput {
            item: serde_json::json!({"ip": "192.168.1.1"}),
        }
    ).await?;
    println!("Return operation: {:?}", return_result);

    // Check operation status
    let status = client.handlers_ip_get_operation_status(&return_result.operation_id).await?;
    println!("Operation status: {:?}", status);

    Ok(())
}
```

## Features

- Fully typed API client generated from OpenAPI spec
- Async/await support via tokio
- Built on reqwest with rustls for TLS
- Comprehensive error handling

## Development

This SDK is auto-generated from the OpenAPI specification. To regenerate:

1. Update the OpenAPI spec: `cargo run --release -- --print-openapi > openapi.json`
2. Rebuild the client: `cd ip-allocator-client && cargo build`

## License

MIT
