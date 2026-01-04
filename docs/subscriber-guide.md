# Subscriber Development Guide

This guide walks you through creating a subscriber service for the IP Allocator Webserver. Subscribers are webhook endpoints that receive notifications when items are borrowed, returned, or submitted to the pool.

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Subscriber Types](#subscriber-types)
4. [Event Payloads](#event-payloads)
5. [Configuration](#configuration)
6. [Examples](#examples)
7. [Testing Your Subscriber](#testing-your-subscriber)
8. [Deployment](#deployment)

## Overview

Subscribers enable event-driven workflows by receiving HTTP POST requests when pool operations occur:

- **Borrow Events**: Triggered when an item is borrowed from the pool
- **Return Events**: Triggered when an item is returned to the pool
- **Submit Events**: Triggered when a new item is submitted to the pool

Each subscriber can be configured as:
- **Synchronous** or **Asynchronous** (for long-running operations)
- **Must-succeed** or **Fire-and-forget** (determines if failures block the operation)

## Quick Start

Generate a new subscriber project using the included utility:

```bash
# Generate a Python subscriber
./scripts/generate-subscriber.sh --name my-subscriber --type python --event borrow

# Generate a Node.js subscriber
./scripts/generate-subscriber.sh --name my-subscriber --type nodejs --event return

# Generate a Rust subscriber
./scripts/generate-subscriber.sh --name my-subscriber --type rust --event borrow
```

This creates a ready-to-run subscriber project with:
- HTTP server handling the webhook endpoint
- Proper request/response handling for sync or async mode
- Health check endpoint
- Docker and docker-compose configuration
- Example tests

## Subscriber Types

### Synchronous Subscribers

Synchronous subscribers process the event and return immediately. The IP allocator waits for the response before completing the operation.

**Use when:**
- Processing takes less than a few seconds
- You need to validate or transform the item
- Simple logging or auditing

**Response:** Return HTTP 200 with any JSON body to indicate success.

```python
@app.post("/on-borrow")
def on_borrow(payload: dict):
    item = payload["item"]
    params = payload.get("params", {})
    # Process synchronously
    log_borrow_event(item, params)
    return {"status": "ok"}
```

### Asynchronous Subscribers

Asynchronous subscribers are for long-running operations. They return an operation ID immediately, and the IP allocator polls for completion.

**Use when:**
- Processing takes more than a few seconds
- You need to provision resources
- Complex multi-step workflows

**Response Flow:**
1. Return HTTP 200 with `{"operation_id": "<uuid>"}`
2. IP allocator polls `GET /operations/status?id=<uuid>`
3. Return `{"status": "pending"}` while processing
4. Return `{"status": "succeeded"}` when complete
5. Return `{"status": "failed", "message": "..."}` on error

```python
@app.post("/on-return")
async def on_return(payload: dict):
    operation_id = str(uuid.uuid4())
    # Start background processing
    background_tasks.add_task(cleanup_resource, operation_id, payload["item"])
    return {"operation_id": operation_id}

@app.get("/operations/status")
def get_status(id: str):
    status = get_operation_status(id)  # "pending", "succeeded", or "failed"
    return {"status": status}
```

## Event Payloads

### Borrow Event

```json
{
  "item": "<any JSON value>",
  "params": { "optional": "query parameters from borrow request" }
}
```

### Return Event

```json
{
  "item": "<any JSON value>",
  "params": { "optional": "parameters from return request body" }
}
```

### Submit Event

```json
{
  "item": "<any JSON value>"
}
```

## Configuration

### TOML Configuration

Create a config file for the IP allocator:

```toml
# config.toml

# Borrow subscribers
[borrow.subscribers.provisioner]
post = "http://my-subscriber:8080/on-borrow"
mustSucceed = true      # Operation fails if subscriber fails
async = false           # Synchronous processing

[borrow.subscribers.long-setup]
post = "http://setup-service:8080/setup"
mustSucceed = true
async = true            # Async with polling

[borrow.subscribers.audit-log]
post = "http://audit:8080/log"
mustSucceed = false     # Fire-and-forget, failures don't block
async = false

# Return subscribers
[return.subscribers.cleanup]
post = "http://cleanup-service:8080/cleanup"
mustSucceed = true
async = true

# Submit subscribers
[submit.subscribers.validator]
post = "http://validator:8080/validate"
mustSucceed = true
async = false
```

### NixOS Configuration

```nix
services.ip-allocator-webserver = {
  enable = true;
  subscribers = {
    borrow.subscribers.provisioner = {
      post = "http://my-subscriber:8080/on-borrow";
      mustSucceed = true;
      async = false;
    };
    return.subscribers.cleanup = {
      post = "http://cleanup:8080/cleanup";
      mustSucceed = true;
      async = true;
    };
  };
};
```

## Examples

### Python (FastAPI) Synchronous Subscriber

```python
from fastapi import FastAPI
from pydantic import BaseModel
from typing import Any, Optional

app = FastAPI()

class BorrowEvent(BaseModel):
    item: Any
    params: Optional[dict] = None

@app.post("/on-borrow")
def on_borrow(event: BorrowEvent):
    print(f"Item borrowed: {event.item}")
    if event.params:
        print(f"With params: {event.params}")
    # Do your processing here
    return {"status": "ok"}

@app.get("/health")
def health():
    return {"status": "healthy"}
```

### Python (FastAPI) Async Subscriber

```python
import uuid
import asyncio
from fastapi import FastAPI, BackgroundTasks
from pydantic import BaseModel
from typing import Any, Optional

app = FastAPI()
operations: dict[str, str] = {}

class ReturnEvent(BaseModel):
    item: Any
    params: Optional[dict] = None

async def process_return(op_id: str, item: Any):
    # Simulate long-running cleanup
    await asyncio.sleep(10)
    operations[op_id] = "succeeded"

@app.post("/on-return")
async def on_return(event: ReturnEvent, background_tasks: BackgroundTasks):
    op_id = str(uuid.uuid4())
    operations[op_id] = "pending"
    background_tasks.add_task(process_return, op_id, event.item)
    return {"operation_id": op_id}

@app.get("/operations/status")
def get_status(id: str):
    status = operations.get(id, "pending")
    return {"status": status}

@app.get("/health")
def health():
    return {"status": "healthy"}
```

### Node.js (Express) Subscriber

```javascript
const express = require('express');
const { v4: uuidv4 } = require('uuid');

const app = express();
app.use(express.json());

const operations = new Map();

// Synchronous borrow handler
app.post('/on-borrow', (req, res) => {
  const { item, params } = req.body;
  console.log(`Item borrowed: ${JSON.stringify(item)}`);
  if (params) {
    console.log(`With params: ${JSON.stringify(params)}`);
  }
  res.json({ status: 'ok' });
});

// Async return handler
app.post('/on-return', (req, res) => {
  const { item, params } = req.body;
  const opId = uuidv4();
  operations.set(opId, 'pending');

  // Simulate async processing
  setTimeout(() => {
    operations.set(opId, 'succeeded');
  }, 10000);

  res.json({ operation_id: opId });
});

// Status polling endpoint
app.get('/operations/status', (req, res) => {
  const status = operations.get(req.query.id) || 'pending';
  res.json({ status });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.listen(8080, () => {
  console.log('Subscriber listening on port 8080');
});
```

## Testing Your Subscriber

### Local Testing with curl

```bash
# Test synchronous endpoint
curl -X POST http://localhost:8080/on-borrow \
  -H "Content-Type: application/json" \
  -d '{"item": "192.168.1.100", "params": {"region": "us-west"}}'

# Test async endpoint
curl -X POST http://localhost:8080/on-return \
  -H "Content-Type: application/json" \
  -d '{"item": "192.168.1.100"}'

# Poll for status
curl "http://localhost:8080/operations/status?id=<operation_id>"
```

### Integration Testing with Docker Compose

```yaml
# docker-compose.test.yml
version: '3.8'
services:
  redis:
    image: redis:7
    ports:
      - "6379:6379"

  ip-allocator:
    image: wholelottahoopla/ip-allocator-webserver:latest
    ports:
      - "8000:8000"
    environment:
      - REDIS_URL=redis://redis:6379/
      - CONFIG_PATH=/config/config.toml
    volumes:
      - ./config.toml:/config/config.toml
    depends_on:
      - redis
      - my-subscriber

  my-subscriber:
    build: .
    ports:
      - "8080:8080"
```

### End-to-End Test Script

```bash
#!/bin/bash
set -e

# Start services
docker-compose -f docker-compose.test.yml up -d

# Wait for services
sleep 5

# Submit an item
curl -s -X POST http://localhost:8000/submit \
  -H "Content-Type: application/json" \
  -d '{"item": "test-item-1"}'

sleep 1

# Borrow (triggers subscriber)
RESPONSE=$(curl -s http://localhost:8000/borrow)
echo "Borrow response: $RESPONSE"

# Verify subscriber was called (check subscriber logs)
docker-compose -f docker-compose.test.yml logs my-subscriber

# Cleanup
docker-compose -f docker-compose.test.yml down
```

## Deployment

### Docker Deployment

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

### NixOS Deployment

See `nix/examples/subscriber/` for a complete NixOS module example that:
- Deploys the subscriber as a systemd service
- Configures the IP allocator to use it
- Sets up proper networking and dependencies

### Health Checks

Always implement a health check endpoint:

```python
@app.get("/health")
def health():
    # Check any dependencies (database, external services)
    return {"status": "healthy"}
```

Configure in Docker:
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
```

## Error Handling

### Must-Succeed Subscribers

When `mustSucceed = true`, errors cause the operation to fail:

```python
@app.post("/on-borrow")
def on_borrow(event: BorrowEvent):
    try:
        provision_resource(event.item)
        return {"status": "ok"}
    except Exception as e:
        # Return 5xx to indicate failure
        raise HTTPException(status_code=500, detail=str(e))
```

### Async Operation Failures

For async subscribers, report failure via the status endpoint:

```python
async def process_return(op_id: str, item: Any):
    try:
        await cleanup_resource(item)
        operations[op_id] = "succeeded"
    except Exception as e:
        operations[op_id] = "failed"
        operation_errors[op_id] = str(e)

@app.get("/operations/status")
def get_status(id: str):
    status = operations.get(id, "pending")
    response = {"status": status}
    if status == "failed" and id in operation_errors:
        response["message"] = operation_errors[id]
    return response
```

## Next Steps

1. Generate a subscriber project: `./scripts/generate-subscriber.sh`
2. Implement your business logic
3. Test locally with curl
4. Run the NixOS VM test: `nix build .#checks.x86_64-linux.subscriber-tutorial-test`
5. Deploy to production
