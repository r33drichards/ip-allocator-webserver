use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::RwLock;
use tokio::sync::broadcast;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OperationStatus {
    Pending,
    InProgress,
    Succeeded,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Operation {
    pub id: String,
    pub item: Value,
    pub status: OperationStatus,
    pub message: Option<String>,
    pub must_succeed: HashSet<String>,
    pub subscribers: HashMap<String, OperationStatus>,
}

impl Operation {
    pub fn new(id: String, item: Value, must_succeed: HashSet<String>) -> Self {
        let mut subscribers = HashMap::new();
        for name in &must_succeed {
            subscribers.insert(name.clone(), OperationStatus::Pending);
        }
        Self {
            id,
            item,
            status: OperationStatus::Pending,
            message: None,
            must_succeed,
            subscribers,
        }
    }
}

#[derive(Clone)]
pub struct OperationStore {
    inner: Arc<RwLock<HashMap<String, Operation>>>,
}

impl OperationStore {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub async fn create(&self, id: String, item: Value, must: HashSet<String>) -> Operation {
        let op = Operation::new(id.clone(), item, must);
        let mut guard = self.inner.write().await;
        guard.insert(id.clone(), op.clone());
        op
    }

    pub async fn get(&self, id: &str) -> Option<Operation> {
        let guard = self.inner.read().await;
        guard.get(id).cloned()
    }

    pub async fn update_message(&self, id: &str, msg: Option<String>) {
        let mut guard = self.inner.write().await;
        if let Some(op) = guard.get_mut(id) {
            op.message = msg;
        }
    }

    pub async fn set_status(&self, id: &str, status: OperationStatus) {
        let mut guard = self.inner.write().await;
        if let Some(op) = guard.get_mut(id) {
            op.status = status;
        }
    }

    pub async fn update_subscriber(
        &self,
        id: &str,
        name: &str,
        status: OperationStatus,
    ) -> Option<Operation> {
        let mut guard = self.inner.write().await;
        if let Some(op) = guard.get_mut(id) {
            op.subscribers.insert(name.to_string(), status);
            return Some(op.clone());
        }
        None
    }

    pub async fn get_all(&self) -> Vec<Operation> {
        let guard = self.inner.read().await;
        guard.values().cloned().collect()
    }

    pub async fn delete(&self, id: &str) -> bool {
        let mut guard = self.inner.write().await;
        guard.remove(id).is_some()
    }
}

#[derive(Clone)]
pub struct Broadcasters {
    inner: Arc<RwLock<HashMap<String, broadcast::Sender<String>>>>,
}

impl Broadcasters {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub async fn subscribe(&self, id: &str) -> broadcast::Receiver<String> {
        let mut guard = self.inner.write().await;
        match guard.get(id) {
            Some(tx) => tx.subscribe(),
            None => {
                let (tx, rx) = broadcast::channel(64);
                guard.insert(id.to_string(), tx);
                rx
            }
        }
    }

    pub async fn notify(&self, id: &str, payload: String) {
        let mut guard = self.inner.write().await;
        let tx = guard.entry(id.to_string()).or_insert_with(|| {
            let (tx, _rx) = broadcast::channel(64);
            tx
        });
        let _ = tx.send(payload);
    }
}


