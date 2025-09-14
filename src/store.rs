use redis::{Client, Commands, RedisResult};
use std::collections::HashSet;

// The key name for the IP address freelist in Redis
const FREELIST_KEY: &str = "ip_freelist";

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

    pub fn borrow_ip(&self) -> RedisResult<String> {
        // Connect to Redis
        let client = self.get_redis_client()?;
        let mut con = client.get_connection()?;
        
        // Try to pop an IP address from the freelist
        let ip: Option<String> = con.spop(FREELIST_KEY)?;
        
        // Return the IP or an error if none available
        ip.ok_or_else(|| {
            redis::RedisError::from((
                redis::ErrorKind::ResponseError,
                "No IP addresses available in the freelist",
            ))
        })
    }

    pub fn return_ip(&self, ip: &str) -> RedisResult<()> {
        // Simple validation to ensure the IP has some format
        if ip.trim().is_empty() {
            return Err(redis::RedisError::from((
                redis::ErrorKind::InvalidClientConfig,
                "Invalid IP address provided",
            )));
        }
        
        // Connect to Redis
        let client = self.get_redis_client()?;
        let mut con = client.get_connection()?;
        
        // Add the IP to the freelist
        let _added: i32 = con.sadd(FREELIST_KEY, ip)?;
        
        Ok(())
    }

    pub fn list_ips(&self) -> RedisResult<HashSet<String>> {
        // Connect to Redis
        let client = self.get_redis_client()?;
        let mut con = client.get_connection()?;
        
        // Get all IPs in the freelist
        let ips: HashSet<String> = con.smembers(FREELIST_KEY)?;
        
        Ok(ips)
    }
}