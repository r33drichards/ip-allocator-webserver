use rocket::local::blocking::Client;
use rocket::http::Status;

#[test]
fn test_borrow_returns_503_when_no_items_available() {
    // This test requires Redis to be running
    // Set REDIS_URL environment variable or it will use default
    let redis_url = std::env::var("REDIS_URL")
        .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

    // Create a Redis client and clear the freelist to ensure it's empty
    let client = redis::Client::open(redis_url.clone()).expect("Failed to connect to Redis");
    let mut con = client.get_connection().expect("Failed to get Redis connection");

    // Clear the freelist key to ensure it's empty
    let _: () = redis::cmd("DEL")
        .arg("freelist")
        .query(&mut con)
        .expect("Failed to clear freelist");

    // Build the Rocket app
    let rocket = ip_allocator_webserver::rocket(redis_url);
    let client = Client::tracked(rocket).expect("valid rocket instance");

    // Make a request to /borrow when the freelist is empty
    let response = client.get("/borrow").dispatch();

    // Should return 503 Service Unavailable, not 500 Internal Server Error
    assert_eq!(response.status(), Status::ServiceUnavailable);

    // Check the response body
    let body = response.into_string().expect("Response body");
    assert!(body.contains("No items available in the freelist"));
}

#[test]
fn test_borrow_returns_200_when_items_available() {
    // This test requires Redis to be running
    let redis_url = std::env::var("REDIS_URL")
        .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

    // Create a Redis client and add an item to the freelist
    let client = redis::Client::open(redis_url.clone()).expect("Failed to connect to Redis");
    let mut con = client.get_connection().expect("Failed to get Redis connection");

    // Clear the freelist first
    let _: () = redis::cmd("DEL")
        .arg("freelist")
        .query(&mut con)
        .expect("Failed to clear freelist");

    // Add a test item to the freelist
    let test_item = r#"{"ip":"192.168.1.1","port":8080}"#;
    let _: () = redis::cmd("SADD")
        .arg("freelist")
        .arg(test_item)
        .query(&mut con)
        .expect("Failed to add item to freelist");

    // Build the Rocket app
    let rocket = ip_allocator_webserver::rocket(redis_url);
    let client = Client::tracked(rocket).expect("valid rocket instance");

    // Make a request to /borrow when an item is available
    let response = client.get("/borrow").dispatch();

    // Should return 200 OK
    assert_eq!(response.status(), Status::Ok);

    // Check that the response contains the item
    let body = response.into_string().expect("Response body");
    assert!(body.contains("item"));
}

#[test]
fn test_borrow_blocking_wait_returns_item_when_available() {
    // This test requires Redis to be running
    let redis_url = std::env::var("REDIS_URL")
        .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

    // Create a Redis client and clear the freelist
    let client = redis::Client::open(redis_url.clone()).expect("Failed to connect to Redis");
    let mut con = client.get_connection().expect("Failed to get Redis connection");

    // Clear the freelist first
    let _: () = redis::cmd("DEL")
        .arg("freelist")
        .query(&mut con)
        .expect("Failed to clear freelist");

    // Build the Rocket app
    let rocket = ip_allocator_webserver::rocket(redis_url.clone());
    let test_client = rocket::local::blocking::Client::tracked(rocket).expect("valid rocket instance");

    // Spawn a thread that will add an item to the freelist after 2 seconds
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_secs(2));
        let client = redis::Client::open(redis_url).expect("Failed to connect to Redis");
        let mut con = client.get_connection().expect("Failed to get Redis connection");
        let test_item = r#"{"ip":"192.168.1.100","port":9090}"#;
        let _: () = redis::cmd("SADD")
            .arg("freelist")
            .arg(test_item)
            .query(&mut con)
            .expect("Failed to add item to freelist");

        // Publish notification
        let _: () = redis::cmd("PUBLISH")
            .arg("freelist:notify")
            .arg("item_returned")
            .query(&mut con)
            .expect("Failed to publish notification");
    });

    // Make a request with ?wait=5 - should block until item is available
    let start = std::time::Instant::now();
    let response = test_client.get("/borrow?wait=5").dispatch();
    let elapsed = start.elapsed();

    // Should return 200 OK
    assert_eq!(response.status(), rocket::http::Status::Ok);

    // Should have waited approximately 2 seconds (item was added after 2 seconds)
    assert!(elapsed.as_secs() >= 2);
    assert!(elapsed.as_secs() < 5);

    // Check that the response contains the item
    let body = response.into_string().expect("Response body");
    assert!(body.contains("item"));
}

#[test]
fn test_borrow_blocking_wait_timeout() {
    // This test requires Redis to be running
    let redis_url = std::env::var("REDIS_URL")
        .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

    // Create a Redis client and clear the freelist
    let client = redis::Client::open(redis_url.clone()).expect("Failed to connect to Redis");
    let mut con = client.get_connection().expect("Failed to get Redis connection");

    // Clear the freelist to ensure it's empty
    let _: () = redis::cmd("DEL")
        .arg("freelist")
        .query(&mut con)
        .expect("Failed to clear freelist");

    // Build the Rocket app
    let rocket = ip_allocator_webserver::rocket(redis_url);
    let client = rocket::local::blocking::Client::tracked(rocket).expect("valid rocket instance");

    // Make a request with ?wait=2 - should timeout after 2 seconds
    let start = std::time::Instant::now();
    let response = client.get("/borrow?wait=2").dispatch();
    let elapsed = start.elapsed();

    // Should return 503 Service Unavailable
    assert_eq!(response.status(), rocket::http::Status::ServiceUnavailable);

    // Should have waited approximately 2 seconds
    assert!(elapsed.as_secs() >= 2);
    assert!(elapsed.as_secs() < 3);

    // Check the response body
    let body = response.into_string().expect("Response body");
    assert!(body.contains("No items available in the freelist"));
}
