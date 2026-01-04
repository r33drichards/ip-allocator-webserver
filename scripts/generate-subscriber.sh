#!/usr/bin/env bash
#
# Subscriber Project Generator for IP Allocator Webserver
#
# Usage:
#   ./scripts/generate-subscriber.sh --name <project-name> --type <python|nodejs|rust> --event <borrow|return|submit>
#
# Options:
#   --name, -n     Project name (required)
#   --type, -t     Language/framework: python, nodejs, rust (default: python)
#   --event, -e    Event type: borrow, return, submit (default: borrow)
#   --async, -a    Generate async subscriber (default: sync)
#   --output, -o   Output directory (default: ./subscribers/<name>)
#   --help, -h     Show this help message
#

set -euo pipefail

# Default values
PROJECT_NAME=""
PROJECT_TYPE="python"
EVENT_TYPE="borrow"
ASYNC_MODE=false
OUTPUT_DIR=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
    echo "Usage: $0 --name <project-name> [options]"
    echo ""
    echo "Generate a subscriber project for IP Allocator Webserver"
    echo ""
    echo "Options:"
    echo "  --name, -n     Project name (required)"
    echo "  --type, -t     Language/framework: python, nodejs, rust (default: python)"
    echo "  --event, -e    Event type: borrow, return, submit (default: borrow)"
    echo "  --async, -a    Generate async subscriber (default: sync)"
    echo "  --output, -o   Output directory (default: ./subscribers/<name>)"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --name my-provisioner --type python --event borrow"
    echo "  $0 --name cleanup-service --type nodejs --event return --async"
    echo "  $0 --name validator --type rust --event submit"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --name|-n)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --type|-t)
            PROJECT_TYPE="$2"
            shift 2
            ;;
        --event|-e)
            EVENT_TYPE="$2"
            shift 2
            ;;
        --async|-a)
            ASYNC_MODE=true
            shift
            ;;
        --output|-o)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$PROJECT_NAME" ]]; then
    log_error "Project name is required"
    print_usage
    exit 1
fi

# Validate project type
case $PROJECT_TYPE in
    python|nodejs|rust)
        ;;
    *)
        log_error "Invalid project type: $PROJECT_TYPE. Must be: python, nodejs, rust"
        exit 1
        ;;
esac

# Validate event type
case $EVENT_TYPE in
    borrow|return|submit)
        ;;
    *)
        log_error "Invalid event type: $EVENT_TYPE. Must be: borrow, return, submit"
        exit 1
        ;;
esac

# Set output directory
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="./subscribers/$PROJECT_NAME"
fi

# Check if directory exists
if [[ -d "$OUTPUT_DIR" ]]; then
    log_error "Directory already exists: $OUTPUT_DIR"
    exit 1
fi

log_info "Creating subscriber project..."
log_info "  Name: $PROJECT_NAME"
log_info "  Type: $PROJECT_TYPE"
log_info "  Event: $EVENT_TYPE"
log_info "  Async: $ASYNC_MODE"
log_info "  Output: $OUTPUT_DIR"
echo ""

# Create directory structure
mkdir -p "$OUTPUT_DIR"

# Generate based on type
case $PROJECT_TYPE in
    python)
        generate_python_project
        ;;
    nodejs)
        generate_nodejs_project
        ;;
    rust)
        generate_rust_project
        ;;
esac

# Function definitions (placed here so they can access variables)
generate_python_project() {
    log_info "Generating Python (FastAPI) project..."

    # requirements.txt
    cat > "$OUTPUT_DIR/requirements.txt" << 'EOF'
fastapi>=0.104.0
uvicorn>=0.24.0
pydantic>=2.5.0
httpx>=0.25.0
pytest>=7.4.0
pytest-asyncio>=0.21.0
EOF

    # Main application
    if [[ "$ASYNC_MODE" == true ]]; then
        cat > "$OUTPUT_DIR/main.py" << EOF
"""
Async ${EVENT_TYPE^} Subscriber for IP Allocator

This subscriber handles ${EVENT_TYPE} events asynchronously, supporting
long-running operations with status polling.
"""

import uuid
import asyncio
from typing import Any, Optional
from fastapi import FastAPI, BackgroundTasks, HTTPException
from pydantic import BaseModel

app = FastAPI(
    title="${PROJECT_NAME}",
    description="Async ${EVENT_TYPE} event subscriber for IP Allocator",
    version="1.0.0"
)

# In-memory operation tracking (use Redis/database in production)
operations: dict[str, dict] = {}


class ${EVENT_TYPE^}Event(BaseModel):
    """Event payload for ${EVENT_TYPE} operations"""
    item: Any
$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo "    params: Optional[dict] = None"; fi)


class OperationResponse(BaseModel):
    """Response containing operation ID for async tracking"""
    operation_id: str


class StatusResponse(BaseModel):
    """Operation status response"""
    status: str
    message: Optional[str] = None


async def process_${EVENT_TYPE}(operation_id: str, item: Any$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo ", params: Optional[dict]"; fi)):
    """
    Process the ${EVENT_TYPE} event asynchronously.

    Replace this with your actual business logic:
    - Resource provisioning
    - External API calls
    - Database operations
    - etc.
    """
    try:
        # Simulate long-running operation
        await asyncio.sleep(5)

        # TODO: Add your processing logic here
        print(f"Processing ${EVENT_TYPE} for item: {item}")
$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo "        if params:"; echo "            print(f\"With params: {params}\")"; fi)

        # Mark as succeeded
        operations[operation_id]["status"] = "succeeded"

    except Exception as e:
        operations[operation_id]["status"] = "failed"
        operations[operation_id]["message"] = str(e)


@app.post("/on-${EVENT_TYPE}", response_model=OperationResponse)
async def on_${EVENT_TYPE}(event: ${EVENT_TYPE^}Event, background_tasks: BackgroundTasks):
    """
    Handle ${EVENT_TYPE} event from IP Allocator.

    Returns an operation_id immediately and processes in background.
    IP Allocator will poll /operations/status for completion.
    """
    operation_id = str(uuid.uuid4())
    operations[operation_id] = {"status": "pending", "message": None}

    background_tasks.add_task(
        process_${EVENT_TYPE},
        operation_id,
        event.item$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo ","; echo "        event.params"; fi)
    )

    return OperationResponse(operation_id=operation_id)


@app.get("/operations/status", response_model=StatusResponse)
async def get_status(id: str):
    """
    Get the status of an async operation.

    Returns:
    - pending: Operation still in progress
    - succeeded: Operation completed successfully
    - failed: Operation failed (includes message)
    """
    if id not in operations:
        raise HTTPException(status_code=404, detail="Operation not found")

    op = operations[id]
    return StatusResponse(status=op["status"], message=op.get("message"))


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF
    else
        cat > "$OUTPUT_DIR/main.py" << EOF
"""
Synchronous ${EVENT_TYPE^} Subscriber for IP Allocator

This subscriber handles ${EVENT_TYPE} events synchronously.
The IP Allocator waits for the response before completing the operation.
"""

from typing import Any, Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(
    title="${PROJECT_NAME}",
    description="Synchronous ${EVENT_TYPE} event subscriber for IP Allocator",
    version="1.0.0"
)


class ${EVENT_TYPE^}Event(BaseModel):
    """Event payload for ${EVENT_TYPE} operations"""
    item: Any
$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo "    params: Optional[dict] = None"; fi)


class SuccessResponse(BaseModel):
    """Success response"""
    status: str = "ok"


@app.post("/on-${EVENT_TYPE}", response_model=SuccessResponse)
async def on_${EVENT_TYPE}(event: ${EVENT_TYPE^}Event):
    """
    Handle ${EVENT_TYPE} event from IP Allocator.

    This runs synchronously - the IP Allocator waits for the response.
    Return HTTP 200 to indicate success.
    Return HTTP 4xx/5xx to indicate failure (if mustSucceed=true, operation fails).
    """
    # TODO: Add your processing logic here
    print(f"${EVENT_TYPE^} event for item: {event.item}")
$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo "    if event.params:"; echo "        print(f\"With params: {event.params}\")"; fi)

    # Example validation (uncomment to use)
    # if not validate_item(event.item):
    #     raise HTTPException(status_code=400, detail="Invalid item")

    return SuccessResponse(status="ok")


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF
    fi

    # Test file
    cat > "$OUTPUT_DIR/test_main.py" << EOF
"""Tests for ${PROJECT_NAME}"""

import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_health():
    """Test health check endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_on_${EVENT_TYPE}():
    """Test ${EVENT_TYPE} event handler"""
    payload = {
        "item": "test-item-123"$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo ","; echo "        \"params\": {\"test\": \"value\"}"; fi)
    }
    response = client.post("/on-${EVENT_TYPE}", json=payload)
    assert response.status_code == 200
$(if [[ "$ASYNC_MODE" == true ]]; then
    echo "    data = response.json()"
    echo "    assert \"operation_id\" in data"
else
    echo "    assert response.json() == {\"status\": \"ok\"}"
fi)


$(if [[ "$ASYNC_MODE" == true ]]; then
cat << 'ASYNC_TEST'
def test_operation_status():
    """Test operation status polling"""
    # First trigger an operation
    payload = {"item": "test-item"}
    response = client.post("/on-${EVENT_TYPE}", json=payload)
    operation_id = response.json()["operation_id"]

    # Check status (should be pending initially)
    status_response = client.get(f"/operations/status?id={operation_id}")
    assert status_response.status_code == 200
    assert status_response.json()["status"] in ["pending", "succeeded"]


def test_operation_not_found():
    """Test status for non-existent operation"""
    response = client.get("/operations/status?id=non-existent")
    assert response.status_code == 404
ASYNC_TEST
fi)
EOF

    # Dockerfile
    cat > "$OUTPUT_DIR/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY . .

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
EOF

    # docker-compose.yml
    cat > "$OUTPUT_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  ${PROJECT_NAME}:
    build: .
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped
EOF

    # README.md
    cat > "$OUTPUT_DIR/README.md" << EOF
# ${PROJECT_NAME}

$(if [[ "$ASYNC_MODE" == true ]]; then echo "Async"; else echo "Synchronous"; fi) ${EVENT_TYPE} event subscriber for IP Allocator Webserver.

## Quick Start

### Local Development

\`\`\`bash
# Create virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run the server
uvicorn main:app --reload --port 8080
\`\`\`

### Docker

\`\`\`bash
# Build and run
docker-compose up --build

# Or just build
docker build -t ${PROJECT_NAME} .
docker run -p 8080:8080 ${PROJECT_NAME}
\`\`\`

## Testing

\`\`\`bash
# Run tests
pytest test_main.py -v

# Manual testing
curl -X POST http://localhost:8080/on-${EVENT_TYPE} \\
  -H "Content-Type: application/json" \\
  -d '{"item": "test-item"$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo ", \"params\": {}"; fi)}'
$(if [[ "$ASYNC_MODE" == true ]]; then
echo ""
echo "# Poll for status"
echo "curl \"http://localhost:8080/operations/status?id=<operation_id>\""
fi)
\`\`\`

## Configuration

Configure in IP Allocator config.toml:

\`\`\`toml
[${EVENT_TYPE}.subscribers.${PROJECT_NAME}]
post = "http://localhost:8080/on-${EVENT_TYPE}"
mustSucceed = true
async = $(if [[ "$ASYNC_MODE" == true ]]; then echo "true"; else echo "false"; fi)
\`\`\`

## Endpoints

- \`POST /on-${EVENT_TYPE}\` - Handle ${EVENT_TYPE} events
$(if [[ "$ASYNC_MODE" == true ]]; then echo "- \`GET /operations/status?id=<id>\` - Poll operation status"; fi)
- \`GET /health\` - Health check
EOF

    log_success "Python project created!"
}

generate_nodejs_project() {
    log_info "Generating Node.js (Express) project..."

    # package.json
    cat > "$OUTPUT_DIR/package.json" << EOF
{
  "name": "${PROJECT_NAME}",
  "version": "1.0.0",
  "description": "$(if [[ "$ASYNC_MODE" == true ]]; then echo "Async"; else echo "Synchronous"; fi) ${EVENT_TYPE} subscriber for IP Allocator",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "dev": "nodemon index.js",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.2",
    "uuid": "^9.0.0"
  },
  "devDependencies": {
    "jest": "^29.7.0",
    "nodemon": "^3.0.2",
    "supertest": "^6.3.3"
  }
}
EOF

    # Main application
    cat > "$OUTPUT_DIR/index.js" << EOF
/**
 * $(if [[ "$ASYNC_MODE" == true ]]; then echo "Async"; else echo "Synchronous"; fi) ${EVENT_TYPE^} Subscriber for IP Allocator
 */

const express = require('express');
$(if [[ "$ASYNC_MODE" == true ]]; then echo "const { v4: uuidv4 } = require('uuid');"; fi)

const app = express();
app.use(express.json());

$(if [[ "$ASYNC_MODE" == true ]]; then
cat << 'ASYNC_CODE'
// In-memory operation tracking (use Redis/database in production)
const operations = new Map();

/**
 * Process the event asynchronously
 */
async function processEvent(operationId, item, params) {
  try {
    // Simulate long-running operation
    await new Promise(resolve => setTimeout(resolve, 5000));

    // TODO: Add your processing logic here
    console.log(`Processing event for item: ${JSON.stringify(item)}`);
    if (params) {
      console.log(`With params: ${JSON.stringify(params)}`);
    }

    operations.set(operationId, { status: 'succeeded' });
  } catch (error) {
    operations.set(operationId, {
      status: 'failed',
      message: error.message
    });
  }
}
ASYNC_CODE
fi)

/**
 * Handle ${EVENT_TYPE} event from IP Allocator
 */
app.post('/on-${EVENT_TYPE}', $(if [[ "$ASYNC_MODE" == true ]]; then echo "async "; fi)(req, res) => {
  const { item$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo ", params"; fi) } = req.body;

  console.log(\`${EVENT_TYPE^} event for item: \${JSON.stringify(item)}\`);
$(if [[ "$EVENT_TYPE" != "submit" ]]; then
echo "  if (params) {"
echo "    console.log(\`With params: \${JSON.stringify(params)}\`);"
echo "  }"
fi)

$(if [[ "$ASYNC_MODE" == true ]]; then
cat << 'ASYNC_HANDLER'
  const operationId = uuidv4();
  operations.set(operationId, { status: 'pending' });

  // Process in background
  processEvent(operationId, item, params);

  res.json({ operation_id: operationId });
ASYNC_HANDLER
else
cat << 'SYNC_HANDLER'
  // TODO: Add your processing logic here

  res.json({ status: 'ok' });
SYNC_HANDLER
fi)
});

$(if [[ "$ASYNC_MODE" == true ]]; then
cat << 'STATUS_ENDPOINT'
/**
 * Get operation status for async processing
 */
app.get('/operations/status', (req, res) => {
  const { id } = req.query;

  if (!operations.has(id)) {
    return res.status(404).json({ error: 'Operation not found' });
  }

  const op = operations.get(id);
  res.json({
    status: op.status,
    message: op.message || null
  });
});
STATUS_ENDPOINT
fi)

/**
 * Health check endpoint
 */
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

const PORT = process.env.PORT || 8080;

// Export for testing
module.exports = app;

// Start server if run directly
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(\`${PROJECT_NAME} listening on port \${PORT}\`);
  });
}
EOF

    # Test file
    cat > "$OUTPUT_DIR/index.test.js" << EOF
const request = require('supertest');
const app = require('./index');

describe('${PROJECT_NAME}', () => {
  test('GET /health returns healthy status', async () => {
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body).toEqual({ status: 'healthy' });
  });

  test('POST /on-${EVENT_TYPE} handles event', async () => {
    const payload = {
      item: 'test-item-123'$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo ","; echo "      params: { test: 'value' }"; fi)
    };

    const response = await request(app)
      .post('/on-${EVENT_TYPE}')
      .send(payload);

    expect(response.status).toBe(200);
$(if [[ "$ASYNC_MODE" == true ]]; then
    echo "    expect(response.body).toHaveProperty('operation_id');"
else
    echo "    expect(response.body).toEqual({ status: 'ok' });"
fi)
  });
$(if [[ "$ASYNC_MODE" == true ]]; then
cat << 'ASYNC_TESTS'

  test('GET /operations/status returns status for valid operation', async () => {
    // Create an operation first
    const createResponse = await request(app)
      .post('/on-${EVENT_TYPE}')
      .send({ item: 'test' });

    const operationId = createResponse.body.operation_id;

    const statusResponse = await request(app)
      .get(`/operations/status?id=${operationId}`);

    expect(statusResponse.status).toBe(200);
    expect(['pending', 'succeeded', 'failed']).toContain(statusResponse.body.status);
  });

  test('GET /operations/status returns 404 for unknown operation', async () => {
    const response = await request(app)
      .get('/operations/status?id=unknown-id');

    expect(response.status).toBe(404);
  });
ASYNC_TESTS
fi)
});
EOF

    # Dockerfile
    cat > "$OUTPUT_DIR/Dockerfile" << 'EOF'
FROM node:20-slim

WORKDIR /app

# Install curl for healthcheck
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Install dependencies
COPY package*.json ./
RUN npm install --production

# Copy application
COPY . .

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080

CMD ["node", "index.js"]
EOF

    # docker-compose.yml
    cat > "$OUTPUT_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  ${PROJECT_NAME}:
    build: .
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped
EOF

    # README.md
    cat > "$OUTPUT_DIR/README.md" << EOF
# ${PROJECT_NAME}

$(if [[ "$ASYNC_MODE" == true ]]; then echo "Async"; else echo "Synchronous"; fi) ${EVENT_TYPE} event subscriber for IP Allocator Webserver.

## Quick Start

### Local Development

\`\`\`bash
# Install dependencies
npm install

# Run in development mode
npm run dev

# Run in production mode
npm start
\`\`\`

### Docker

\`\`\`bash
# Build and run
docker-compose up --build

# Or just build
docker build -t ${PROJECT_NAME} .
docker run -p 8080:8080 ${PROJECT_NAME}
\`\`\`

## Testing

\`\`\`bash
# Run tests
npm test

# Manual testing
curl -X POST http://localhost:8080/on-${EVENT_TYPE} \\
  -H "Content-Type: application/json" \\
  -d '{"item": "test-item"$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo ", \"params\": {}"; fi)}'
$(if [[ "$ASYNC_MODE" == true ]]; then
echo ""
echo "# Poll for status"
echo "curl \"http://localhost:8080/operations/status?id=<operation_id>\""
fi)
\`\`\`

## Configuration

Configure in IP Allocator config.toml:

\`\`\`toml
[${EVENT_TYPE}.subscribers.${PROJECT_NAME}]
post = "http://localhost:8080/on-${EVENT_TYPE}"
mustSucceed = true
async = $(if [[ "$ASYNC_MODE" == true ]]; then echo "true"; else echo "false"; fi)
\`\`\`
EOF

    log_success "Node.js project created!"
}

generate_rust_project() {
    log_info "Generating Rust (Rocket) project..."

    # Create src directory
    mkdir -p "$OUTPUT_DIR/src"

    # Cargo.toml
    cat > "$OUTPUT_DIR/Cargo.toml" << EOF
[package]
name = "${PROJECT_NAME//-/_}"
version = "1.0.0"
edition = "2021"
description = "$(if [[ "$ASYNC_MODE" == true ]]; then echo "Async"; else echo "Synchronous"; fi) ${EVENT_TYPE} subscriber for IP Allocator"

[dependencies]
rocket = { version = "0.5.0", features = ["json"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tokio = { version = "1", features = ["full"] }
$(if [[ "$ASYNC_MODE" == true ]]; then echo 'uuid = { version = "1.6", features = ["v4"] }'; fi)

[dev-dependencies]
EOF

    # Main application
    cat > "$OUTPUT_DIR/src/main.rs" << EOF
//! $(if [[ "$ASYNC_MODE" == true ]]; then echo "Async"; else echo "Synchronous"; fi) ${EVENT_TYPE^} Subscriber for IP Allocator

#[macro_use]
extern crate rocket;

use rocket::serde::{Deserialize, Serialize, json::Json};
use serde_json::Value;
$(if [[ "$ASYNC_MODE" == true ]]; then
cat << 'ASYNC_IMPORTS'
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;
use rocket::State;
ASYNC_IMPORTS
fi)

$(if [[ "$ASYNC_MODE" == true ]]; then
cat << 'ASYNC_STATE'
/// Application state for tracking async operations
struct AppState {
    operations: Arc<Mutex<HashMap<String, OperationStatus>>>,
}

#[derive(Clone, Serialize)]
struct OperationStatus {
    status: String,
    message: Option<String>,
}
ASYNC_STATE
fi)

/// Event payload for ${EVENT_TYPE} operations
#[derive(Deserialize)]
#[serde(crate = "rocket::serde")]
struct ${EVENT_TYPE^}Event {
    item: Value,
$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo "    params: Option<Value>,"; fi)
}

$(if [[ "$ASYNC_MODE" == true ]]; then
cat << 'ASYNC_RESPONSE'
/// Response containing operation ID for async tracking
#[derive(Serialize)]
#[serde(crate = "rocket::serde")]
struct OperationResponse {
    operation_id: String,
}

/// Operation status response
#[derive(Serialize)]
#[serde(crate = "rocket::serde")]
struct StatusResponse {
    status: String,
    message: Option<String>,
}
ASYNC_RESPONSE
else
cat << 'SYNC_RESPONSE'
/// Success response
#[derive(Serialize)]
#[serde(crate = "rocket::serde")]
struct SuccessResponse {
    status: String,
}
SYNC_RESPONSE
fi)

/// Health check response
#[derive(Serialize)]
#[serde(crate = "rocket::serde")]
struct HealthResponse {
    status: String,
}

$(if [[ "$ASYNC_MODE" == true ]]; then
cat << 'ASYNC_HANDLER'
/// Handle ${EVENT_TYPE} event from IP Allocator
#[post("/on-${EVENT_TYPE}", data = "<event>")]
async fn on_event(
    state: &State<AppState>,
    event: Json<${EVENT_TYPE^}Event>,
) -> Json<OperationResponse> {
    let operation_id = Uuid::new_v4().to_string();

    println!("${EVENT_TYPE^} event for item: {:?}", event.item);

    // Store initial pending status
    {
        let mut ops = state.operations.lock().await;
        ops.insert(operation_id.clone(), OperationStatus {
            status: "pending".to_string(),
            message: None,
        });
    }

    // Clone for async task
    let op_id = operation_id.clone();
    let operations = state.operations.clone();
    let item = event.item.clone();

    // Process in background
    tokio::spawn(async move {
        // Simulate processing
        tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;

        // TODO: Add your processing logic here
        println!("Completed processing for item: {:?}", item);

        let mut ops = operations.lock().await;
        if let Some(status) = ops.get_mut(&op_id) {
            status.status = "succeeded".to_string();
        }
    });

    Json(OperationResponse { operation_id })
}

/// Get operation status for async processing
#[get("/operations/status?<id>")]
async fn get_status(state: &State<AppState>, id: &str) -> Option<Json<StatusResponse>> {
    let ops = state.operations.lock().await;
    ops.get(id).map(|status| {
        Json(StatusResponse {
            status: status.status.clone(),
            message: status.message.clone(),
        })
    })
}
ASYNC_HANDLER
else
cat << 'SYNC_HANDLER'
/// Handle ${EVENT_TYPE} event from IP Allocator
#[post("/on-${EVENT_TYPE}", data = "<event>")]
async fn on_event(event: Json<${EVENT_TYPE^}Event>) -> Json<SuccessResponse> {
    println!("${EVENT_TYPE^} event for item: {:?}", event.item);

    // TODO: Add your processing logic here

    Json(SuccessResponse {
        status: "ok".to_string(),
    })
}
SYNC_HANDLER
fi)

/// Health check endpoint
#[get("/health")]
fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "healthy".to_string(),
    })
}

#[launch]
fn rocket() -> _ {
    rocket::build()
$(if [[ "$ASYNC_MODE" == true ]]; then
cat << 'ASYNC_LAUNCH'
        .manage(AppState {
            operations: Arc::new(Mutex::new(HashMap::new())),
        })
        .mount("/", routes![on_event, get_status, health])
ASYNC_LAUNCH
else
    echo "        .mount(\"/\", routes![on_event, health])"
fi)
}
EOF

    # Rocket.toml
    cat > "$OUTPUT_DIR/Rocket.toml" << 'EOF'
[default]
address = "0.0.0.0"
port = 8080

[release]
address = "0.0.0.0"
port = 8080
EOF

    # Dockerfile
    cat > "$OUTPUT_DIR/Dockerfile" << 'EOF'
FROM rust:1.74 as builder

WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/$(ls /app/target/release/ | grep -v '\.d' | head -1) /usr/local/bin/subscriber

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080

CMD ["subscriber"]
EOF

    # docker-compose.yml
    cat > "$OUTPUT_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  ${PROJECT_NAME}:
    build: .
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped
EOF

    # README.md
    cat > "$OUTPUT_DIR/README.md" << EOF
# ${PROJECT_NAME}

$(if [[ "$ASYNC_MODE" == true ]]; then echo "Async"; else echo "Synchronous"; fi) ${EVENT_TYPE} event subscriber for IP Allocator Webserver.

## Quick Start

### Local Development

\`\`\`bash
# Build and run
cargo run

# Run in release mode
cargo run --release
\`\`\`

### Docker

\`\`\`bash
# Build and run
docker-compose up --build

# Or just build
docker build -t ${PROJECT_NAME} .
docker run -p 8080:8080 ${PROJECT_NAME}
\`\`\`

## Testing

\`\`\`bash
# Run tests
cargo test

# Manual testing
curl -X POST http://localhost:8080/on-${EVENT_TYPE} \\
  -H "Content-Type: application/json" \\
  -d '{"item": "test-item"$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo ", \"params\": {}"; fi)}'
$(if [[ "$ASYNC_MODE" == true ]]; then
echo ""
echo "# Poll for status"
echo "curl \"http://localhost:8080/operations/status?id=<operation_id>\""
fi)
\`\`\`

## Configuration

Configure in IP Allocator config.toml:

\`\`\`toml
[${EVENT_TYPE}.subscribers.${PROJECT_NAME}]
post = "http://localhost:8080/on-${EVENT_TYPE}"
mustSucceed = true
async = $(if [[ "$ASYNC_MODE" == true ]]; then echo "true"; else echo "false"; fi)
\`\`\`
EOF

    log_success "Rust project created!"
}

# Call the appropriate generator
case $PROJECT_TYPE in
    python)
        generate_python_project
        ;;
    nodejs)
        generate_nodejs_project
        ;;
    rust)
        generate_rust_project
        ;;
esac

# Create example config file
cat > "$OUTPUT_DIR/ip-allocator-config.toml" << EOF
# Example IP Allocator configuration to use this subscriber
# Copy these settings to your IP Allocator config.toml

[${EVENT_TYPE}.subscribers.${PROJECT_NAME}]
post = "http://localhost:8080/on-${EVENT_TYPE}"
mustSucceed = true
async = $(if [[ "$ASYNC_MODE" == true ]]; then echo "true"; else echo "false"; fi)
EOF

echo ""
log_success "Subscriber project created at: $OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "  1. cd $OUTPUT_DIR"
case $PROJECT_TYPE in
    python)
        echo "  2. python -m venv venv && source venv/bin/activate"
        echo "  3. pip install -r requirements.txt"
        echo "  4. uvicorn main:app --reload --port 8080"
        ;;
    nodejs)
        echo "  2. npm install"
        echo "  3. npm run dev"
        ;;
    rust)
        echo "  2. cargo run"
        ;;
esac
echo ""
echo "  Test with:"
echo "    curl -X POST http://localhost:8080/on-${EVENT_TYPE} \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"item\": \"test-item\"$(if [[ "$EVENT_TYPE" != "submit" ]]; then echo ", \"params\": {}"; fi)}'"
echo ""
echo "  Configure in IP Allocator (see ip-allocator-config.toml):"
echo "    [${EVENT_TYPE}.subscribers.${PROJECT_NAME}]"
echo "    post = \"http://localhost:8080/on-${EVENT_TYPE}\""
echo "    mustSucceed = true"
echo "    async = $(if [[ "$ASYNC_MODE" == true ]]; then echo "true"; else echo "false"; fi)"
