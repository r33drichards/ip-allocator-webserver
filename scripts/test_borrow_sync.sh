#!/usr/bin/env bash
set -euo pipefail

# Scenario: borrow requires sync must-succeed (echo) and returns an IP

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
export CONFIG_FILE="$ROOT_DIR/configs/scenario_borrow_sync.toml"

echo "[test] Building images..."
docker compose -f "$ROOT_DIR/docker-compose.yml" build ip-allocator-webserver >/dev/null

echo "[test] Starting deps..."
docker compose -f "$ROOT_DIR/docker-compose.yml" up -d redis echo >/dev/null

echo "[test] Seeding Redis freelist..."
docker compose -f "$ROOT_DIR/docker-compose.yml" exec -T redis sh -lc 'redis-cli del freelist >/dev/null 2>&1 || true; redis-cli sadd freelist "{\"ip\":\"10.0.0.3\"}" >/dev/null'

echo "[test] Starting webserver..."
docker compose -f "$ROOT_DIR/docker-compose.yml" up -d ip-allocator-webserver >/dev/null

echo "[test] Waiting for webserver readiness..."
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' localhost:8000/swagger-ui/ || true)
  [ "$code" = "200" ] && break
  sleep 1
done

echo "[test] Borrowing item should succeed..."
code=$(curl -s -o /dev/null -w '%{http_code}' localhost:8000/borrow)
test "$code" = "200" || { echo "expected 200 on borrow, got $code"; exit 1; }


echo "[test] PASS: borrow with sync must-succeed subscriber."


