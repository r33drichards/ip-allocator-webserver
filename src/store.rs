use redis::{Client, Commands, RedisResult};
use serde_json::Value;
use std::time::Duration;

// The key name for the freelist in Redis
const FREELIST_KEY: &str = "freelist";
// Pub/Sub channel for notifying when items are returned to the freelist
const FREELIST_NOTIFY_CHANNEL: &str = "freelist:notify";
// Hash key for tracking borrowed items and their owners
const BORROWED_ITEMS_KEY: &str = "borrowed_items";

#[derive(Clone)]
pub struct Store {
    redis_url: String,
}

impl Store {
    pub fn new(redis_url: String) -> Self {
        Self { redis_url }
    }

    fn get_redis_client(&self) -> RedisResult<Client> {
        redis::Client::open(self.redis_url.clone())
    }

    /// Test the Redis connection to ensure it's working
    /// This should be called on startup to fail fast if Redis is unavailable
    pub fn test_connection(&self) -> RedisResult<()> {
        let client = self.get_redis_client()?;
        let mut con = client.get_connection()?;
        // Simple PING command to verify connection
        redis::cmd("PING").query::<()>(&mut con)?;
        Ok(())
    }

    pub fn borrow(&self) -> RedisResult<Value> {
        // Connect to Redis
        let client = self.get_redis_client()?;
        let mut con = client.get_connection()?;

        // Try to pop a value from the freelist
        let raw: Option<String> = con.spop(FREELIST_KEY)?;

        // Return the JSON value or an error if none available
        match raw {
            Some(s) => serde_json::from_str::<Value>(&s).map_err(|e| {
                redis::RedisError::from((
                    redis::ErrorKind::TypeError,
                    "Stored value is not valid JSON",
                    format!("{}", e),
                ))
            }),
            None => Err(redis::RedisError::from((
                redis::ErrorKind::ResponseError,
                "No items available in the freelist",
            ))),
        }
    }

    /// Borrow with blocking wait - will wait up to timeout_secs for an item to become available
    /// Uses Redis Pub/Sub to be notified when items are returned to the freelist
    pub fn borrow_blocking(&self, timeout: Duration) -> RedisResult<Value> {
        let client = self.get_redis_client()?;

        // First, try a non-blocking borrow
        match self.borrow() {
            Ok(item) => return Ok(item),
            Err(e) => {
                // If error is not "no items available", return it immediately
                if !e.to_string().contains("No items available in the freelist") {
                    return Err(e);
                }
                // Otherwise, continue to blocking wait
            }
        }

        // Set up pub/sub connection to listen for notifications
        let mut pubsub_conn = client.get_connection()?;
        let mut pubsub = pubsub_conn.as_pubsub();
        pubsub.subscribe(FREELIST_NOTIFY_CHANNEL)?;

        // Set timeout for pub/sub
        let start = std::time::Instant::now();

        loop {
            // Calculate remaining timeout
            let elapsed = start.elapsed();
            if elapsed >= timeout {
                // Timeout reached, return error
                return Err(redis::RedisError::from((
                    redis::ErrorKind::ResponseError,
                    "No items available in the freelist (timeout)",
                )));
            }

            let remaining = timeout - elapsed;

            // Wait for notification with remaining timeout
            pubsub.set_read_timeout(Some(remaining))?;

            // Try to receive a message (this blocks until message or timeout)
            match pubsub.get_message() {
                Ok(_msg) => {
                    // Notification received, try to borrow again
                    match self.borrow() {
                        Ok(item) => return Ok(item),
                        Err(e) => {
                            // If still no items, another client may have grabbed it
                            // Continue waiting for next notification
                            if !e.to_string().contains("No items available in the freelist") {
                                return Err(e);
                            }
                            // Otherwise loop and wait for next notification
                        }
                    }
                }
                Err(e) => {
                    // Check if this is a timeout error
                    if e.is_timeout() {
                        // Timeout - return no items available error
                        return Err(redis::RedisError::from((
                            redis::ErrorKind::ResponseError,
                            "No items available in the freelist (timeout)",
                        )));
                    }
                    // Other error - return it
                    return Err(e);
                }
            }
        }
    }

    pub fn return_item(&self, value: &Value) -> RedisResult<()> {
        // Connect to Redis
        let client = self.get_redis_client()?;
        let mut con = client.get_connection()?;

        // Add the item (as serialized JSON) to the freelist
        let payload = serde_json::to_string(value).map_err(|e| {
            redis::RedisError::from((
                redis::ErrorKind::TypeError,
                "Failed to serialize JSON",
                format!("{}", e),
            ))
        })?;
        let _added: i32 = con.sadd(FREELIST_KEY, payload)?;

        // Notify any waiting clients via Pub/Sub
        let _: () = redis::cmd("PUBLISH")
            .arg(FREELIST_NOTIFY_CHANNEL)
            .arg("item_returned")
            .query(&mut con)?;

        Ok(())
    }

    /// Record that an item has been borrowed by a specific owner
    pub fn record_borrowed(&self, item: &Value, owner_id: &str) -> RedisResult<()> {
        let client = self.get_redis_client()?;
        let mut con = client.get_connection()?;

        let item_key = serde_json::to_string(item).map_err(|e| {
            redis::RedisError::from((
                redis::ErrorKind::TypeError,
                "Failed to serialize JSON",
                format!("{}", e),
            ))
        })?;

        // Store the owner_id in a hash map with the item as the key
        let _: () = con.hset(BORROWED_ITEMS_KEY, item_key, owner_id)?;
        Ok(())
    }

    /// Verify that the owner_id matches the one who borrowed the item
    /// Returns Ok(()) if authorized, Err if not authorized or item not found
    pub fn verify_owner(&self, item: &Value, owner_id: &str) -> RedisResult<()> {
        let client = self.get_redis_client()?;
        let mut con = client.get_connection()?;

        let item_key = serde_json::to_string(item).map_err(|e| {
            redis::RedisError::from((
                redis::ErrorKind::TypeError,
                "Failed to serialize JSON",
                format!("{}", e),
            ))
        })?;

        // Get the stored owner_id for this item
        let stored_owner: Option<String> = con.hget(BORROWED_ITEMS_KEY, &item_key)?;

        match stored_owner {
            Some(stored) if stored == owner_id => Ok(()),
            Some(_) => Err(redis::RedisError::from((
                redis::ErrorKind::ResponseError,
                "Unauthorized: Item is owned by a different owner",
            ))),
            None => Err(redis::RedisError::from((
                redis::ErrorKind::ResponseError,
                "Item not found in borrowed items",
            ))),
        }
    }

    /// Remove the borrowed item record after successful return
    pub fn remove_borrowed_record(&self, item: &Value) -> RedisResult<()> {
        let client = self.get_redis_client()?;
        let mut con = client.get_connection()?;

        let item_key = serde_json::to_string(item).map_err(|e| {
            redis::RedisError::from((
                redis::ErrorKind::TypeError,
                "Failed to serialize JSON",
                format!("{}", e),
            ))
        })?;

        // Remove the item from the borrowed_items hash
        let _: () = con.hdel(BORROWED_ITEMS_KEY, item_key)?;
        Ok(())
    }
}