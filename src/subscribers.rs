use std::collections::HashMap;

use crate::config::{AppConfig, SubscriberDef};
use reqwest::Client;
use serde::Serialize;
use serde_json::Value;
use serde::Deserialize;
use tokio::time::{sleep, Duration};
use reqwest::Url;

#[derive(Debug, Serialize)]
pub struct BorrowEventPayload<'a> {
    pub item: &'a Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<&'a Value>,
}

#[derive(Debug, Serialize)]
pub struct ReturnEventPayload<'a> {
    pub item: &'a Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<&'a Value>,
}

#[derive(Debug, Serialize)]
pub struct SubmitEventPayload<'a> {
    pub item: &'a Value,
}

#[derive(Clone)]
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
        item: &Value,
        params: Option<&Value>,
    ) -> Result<(), (String, bool)> {
        self.dispatch_and_wait(&cfg.borrow.subscribers, &BorrowEventPayload { item, params }).await
    }

    pub async fn notify_return(
        &self,
        cfg: &AppConfig,
        item: &Value,
        params: Option<&Value>,
    ) -> Result<(), (String, bool)> {
        self.dispatch_and_wait(&cfg.r#return.subscribers, &ReturnEventPayload { item, params }).await
    }

    pub async fn notify_submit(
        &self,
        cfg: &AppConfig,
        item: &Value,
    ) -> Result<(), (String, bool)> {
        self.dispatch_and_wait(&cfg.submit.subscribers, &SubmitEventPayload { item }).await
    }

}

#[derive(Debug, Deserialize)]
struct OperationAck {
    #[serde(default)]
    operation_id: String,
    #[serde(default)]
    status: String,
}

impl Subscribers {

    async fn dispatch_and_wait<T: Serialize + ?Sized>(
        &self,
        subs: &HashMap<String, SubscriberDef>,
        body: &T,
    ) -> Result<(), (String, bool)> {
        for (name, def) in subs {
            let resp = match self.http.post(&def.post).json(&body).send().await {
                Ok(r) => r,
                Err(e) => {
                    if def.mustSuceed { return Err((format!("subscriber `{}` request error: {}", name, e), true)); }
                    else { continue; }
                }
            };

            if !resp.status().is_success() {
                if def.mustSuceed { return Err((format!("subscriber `{}` http {}", name, resp.status()), true)); }
                else { continue; }
            }

            if def.mustSuceed && def.r#async {
                // Try to read operation_id and poll until completion
                let ack: OperationAck = match resp.json().await {
                    Ok(a) => a,
                    Err(e) => { return Err((format!("subscriber `{}`: invalid JSON ack: {}", name, e), true)); }
                };
                if ack.operation_id.is_empty() {
                    return Err((format!("subscriber `{}` did not return operation_id" , name), true));
                }

                // Derive status URL from base of post URL
                let post_url = Url::parse(&def.post).map_err(|e| (format!("bad post url for `{}`: {}", name, e), true))?;
                let mut base = post_url;
                let _ = base.path(); // ensure parse
                base.set_path("/operations/status");
                base.set_query(Some(&format!("id={}", ack.operation_id)));

                // Poll until succeeded/failed
                #[derive(Deserialize)]
                struct StatusResp { status: String, message: Option<String> }
                let mut attempts = 0u32;
                let max_attempts = 1800u32; // ~1 hour at 2s interval
                loop {
                    let res = self.http.get(base.as_str()).send().await;
                    match res {
                        Ok(r) if r.status().is_success() => {
                            match r.json::<StatusResp>().await {
                                Ok(sr) => {
                                    let s = sr.status.to_lowercase();
                                    if s == "succeeded" || s == "success" || s == "ok" {
                                        break; // done
                                    } else if s == "failed" || s == "error" {
                                        return Err((format!("subscriber `{}` op failed: {}", name, sr.message.unwrap_or_default()), true));
                                    }
                                }
                                Err(e) => {
                                    return Err((format!("subscriber `{}` status parse error: {}", name, e), true));
                                }
                            }
                        }
                        Ok(r) => {
                            return Err((format!("subscriber `{}` status http {}", name, r.status()), true));
                        }
                        Err(e) => {
                            return Err((format!("subscriber `{}` status request error: {}", name, e), true));
                        }
                    }
                    attempts += 1;
                    if attempts >= max_attempts { return Err((format!("subscriber `{}` op timeout", name), true)); }
                    sleep(Duration::from_secs(2)).await;
                }
            }
        }
        Ok(())
    }
}


