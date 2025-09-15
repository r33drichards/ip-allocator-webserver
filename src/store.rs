use redis::{Client, Commands, RedisResult};
use serde_json::Value;

// The key name for the freelist in Redis
const FREELIST_KEY: &str = "freelist";

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
        
        Ok(())
    }
}