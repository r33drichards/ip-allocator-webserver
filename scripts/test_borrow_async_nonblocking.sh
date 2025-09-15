#!/usr/bin/env bash
set -euo pipefail

# Scenario: borrow should succeed even with an async non-must-succeed subscriber

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
export CONFIG_FILE="$ROOT_DIR/configs/scenario_borrow_async_nonblocking.toml"
export FAKE_SUB_DELAY_SECS=${FAKE_SUB_DELAY_SECS:-5}

echo "[test] Building images..."
docker compose -f "$ROOT_DIR/docker-compose.yml" build fake-async ip-allocator-webserver >/dev/null

echo "[test] Starting deps..."
docker compose -f "$ROOT_DIR/docker-compose.yml" up -d redis echo fake-async >/dev/null

echo "[test] Seeding Redis freelist..."
docker compose -f "$ROOT_DIR/docker-compose.yml" exec -T redis sh -lc 'redis-cli del ip_freelist >/dev/null 2>&1 || true; redis-cli sadd ip_freelist 10.0.0.2 >/dev/null'

echo "[test] Starting webserver..."
docker compose -f "$ROOT_DIR/docker-compose.yml" up -d ip-allocator-webserver >/dev/null

echo "[test] Waiting for webserver readiness..."
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' localhost:8000/ip/list || true)
  [ "$code" = "200" ] && break
  sleep 1
done

echo "[test] Borrowing IP should succeed immediately..."
code=$(curl -s -o /dev/null -w '%{http_code}' localhost:8000/ip/borrow)
test "$code" = "200" || { echo "expected 200 on borrow, got $code"; exit 1; }

echo "[test] PASS: borrow works with non-must async subscriber."


