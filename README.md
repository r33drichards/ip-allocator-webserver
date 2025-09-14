# IP Allocator Web Server

A RESTful API wrapper around the IP allocator CLI tool, built with Rust and Rocket.

## Features

- Borrow an IP address from the freelist
- Return an IP address to the freelist
- List all available IP addresses
- Swagger UI for easy API testing and documentation

## API Endpoints

- `GET /ip/borrow` - Borrow an IP address
- `POST /ip/return` - Return an IP address to the freelist
- `GET /ip/list` - List all available IP addresses
- `/swagger-ui/` - Swagger UI for API documentation
- `/rapidoc/` - Alternative API documentation

## Getting Started

### Prerequisites

- Rust and Cargo
- Docker and Docker Compose (optional)

### Running with Docker Compose

```bash
docker-compose up
```

### Running Locally

1. Start a Redis server
2. Set the REDIS_URL environment variable (optional, defaults to redis://127.0.0.1/)
3. Run the application:

```bash
cargo run
```

## Building and Running

```bash
# Build
cargo build --release

# Run
./target/release/ip-allocator-webserver
```

## API Documentation

Once the server is running, visit:

- http://localhost:8000/swagger-ui/ for Swagger UI
- http://localhost:8000/rapidoc/ for RapiDoc

## Environment Variables

- `REDIS_URL` - Redis connection URL (default: redis://127.0.0.1/)