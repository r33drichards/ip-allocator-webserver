//! IP Allocator API Client
//!
//! This crate provides a Rust client for the IP Allocator API.
//! The client is auto-generated from the OpenAPI specification.
//!
//! ## Example
//!
//! ```no_run
//! use ip_allocator_client::Client;
//!
//! #[tokio::main]
//! async fn main() -> Result<(), Box<dyn std::error::Error>> {
//!     let client = Client::new("http://localhost:8000");
//!
//!     // Borrow an item (immediate return, no params)
//!     let result = client.handlers_ip_borrow(None, None).await?;
//!     println!("Borrowed item: {:?}", result);
//!
//!     // Or pass params to subscribers and wait up to 30 seconds
//!     // let result = client.handlers_ip_borrow(Some("{\"key\":\"value\"}".into()), Some(30)).await?;
//!
//!     Ok(())
//! }
//! ```

#![allow(clippy::all)]
#![allow(unused_imports, dead_code)]

include!(concat!(env!("OUT_DIR"), "/codegen.rs"));
