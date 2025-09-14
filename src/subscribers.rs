use std::collections::HashMap;

use crate::config::{AppConfig, SubscriberDef};
use reqwest::Client;
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct BorrowEventPayload<'a> {
    pub ip: &'a str,
}

#[derive(Debug, Serialize)]
pub struct ReturnEventPayload<'a> {
    pub ip: &'a str,
}

pub struct Subscribers {
    http: Client,
}

impl Subscribers {
    pub fn new() -> Self {
        Self {
            http: Client::new(),
        }
    }

    pub async fn notify_borrow(
        &self,
        cfg: &AppConfig,
        ip: &str,
    ) -> Result<(), (String, bool)> {
        self.dispatch(&cfg.borrow.subscribers, &BorrowEventPayload { ip }).await
    }

    pub async fn notify_return(
        &self,
        cfg: &AppConfig,
        ip: &str,
    ) -> Result<(), (String, bool)> {
        self.dispatch(&cfg.r#return.subscribers, &ReturnEventPayload { ip }).await
    }

    async fn dispatch<T: Serialize + ?Sized>(
        &self,
        subs: &HashMap<String, SubscriberDef>,
        body: &T,
    ) -> Result<(), (String, bool)> {
        for (name, def) in subs {
            let resp = self.http.post(&def.post).json(&body).send().await;
            match resp.and_then(|r| r.error_for_status()) {
                Ok(_) => {}
                Err(e) => {
                    if def.mustSuceed {
                        return Err((format!("subscriber `{}` failed: {}", name, e), true));
                    }
                }
            }
        }
        Ok(())
    }
}


