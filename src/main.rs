use dotenv::dotenv;
use std::env;

use ip_allocator_webserver::{rocket_with_config, print_openapi_spec, store::Store, config};

#[rocket::main]
async fn main() {
    dotenv().ok();
    let args: Vec<String> = env::args().collect();
    if args.contains(&"--print-openapi".to_string()) {
        print_openapi_spec();
        return;
    }

    let redis_url = env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1/".to_string());

    // Load config from optional --config <path>
    let mut args_iter = args.iter();
    let mut app_config = ip_allocator_webserver::config::AppConfig::default();
    while let Some(arg) = args_iter.next() {
        if arg == "--config" {
            if let Some(path) = args_iter.next() {
                let path = std::path::Path::new(path);
                match ip_allocator_webserver::config::AppConfig::from_path(path) {
                    Ok(cfg) => app_config = cfg,
                    Err(e) => {
                        eprintln!("Failed to load config from {}: {}", path.display(), e);
                        std::process::exit(2);
                    }
                }
            }
        }
    }

    let store = Store::new(redis_url.clone());

    // Test Redis connection on startup - fail fast if unavailable
    if let Err(e) = store.test_connection() {
        eprintln!("=================================================");
        eprintln!("ERROR: Failed to connect to Redis");
        eprintln!("=================================================");
        eprintln!();
        eprintln!("Connection error: {}", e);
        eprintln!();
        eprintln!("Current REDIS_URL: {}", redis_url);
        eprintln!();
        eprintln!("Please ensure that:");
        eprintln!("  1. Redis server is running and accessible");
        eprintln!("  2. The REDIS_URL environment variable is set correctly");
        eprintln!("     Example: export REDIS_URL='redis://127.0.0.1:6379/'");
        eprintln!("  3. Network connectivity allows access to the Redis server");
        eprintln!("  4. Redis authentication credentials are correct (if required)");
        eprintln!();
        eprintln!("=================================================");
        std::process::exit(1);
    }

    println!("✓ Successfully connected to Redis at {}", redis_url);

    let _ = rocket_with_config(redis_url, app_config)
        .launch()
        .await;
}