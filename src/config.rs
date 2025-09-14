use std::collections::HashMap;

use serde::Deserialize;

#[derive(Debug, Deserialize, Clone, Default)]
pub struct SubscriberDef {
    pub post: String,
    #[serde(default)]
    pub mustSuceed: bool,
}

#[derive(Debug, Deserialize, Clone, Default)]
pub struct OperationSubscribers {
    #[serde(default)]
    pub subscribers: HashMap<String, SubscriberDef>,
}

#[derive(Debug, Deserialize, Clone, Default)]
pub struct AppConfig {
    #[serde(default)]
    pub borrow: OperationSubscribers,
    #[serde(default)]
    pub r#return: OperationSubscribers,
}

impl AppConfig {
    pub fn from_toml_str(input: &str) -> Result<Self, toml::de::Error> {
        toml::from_str::<AppConfig>(input)
    }

    pub fn from_path(path: &std::path::Path) -> anyhow::Result<Self> {
        let contents = std::fs::read_to_string(path)?;
        let cfg = toml::from_str::<AppConfig>(&contents)?;
        Ok(cfg)
    }
}


