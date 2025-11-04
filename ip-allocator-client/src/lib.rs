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
//!     let client = Client::new("http://localhost:8000")?;
//!
//!     // Borrow an item
//!     let result = client.handlers_ip_borrow().await?;
//!     println!("Borrowed item: {:?}", result);
//!
//!     Ok(())
//! }
//! ```

#![allow(clippy::all)]
#![allow(unused_imports, dead_code)]

include!(concat!(env!("OUT_DIR"), "/codegen.rs"));
