#!/usr/bin/env bash
set -euo pipefail

# Scenario: return waits for async completion before IP is re-added to freelist

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
export CONFIG_FILE="$ROOT_DIR/configs/scenario_return_async.toml"
export FAKE_SUB_DELAY_SECS=${FAKE_SUB_DELAY_SECS:-5}

echo "[test] Building images..."
docker compose -f "$ROOT_DIR/docker-compose.yml" build fake-async ip-allocator-webserver >/dev/null

echo "[test] Starting deps..."
docker compose -f "$ROOT_DIR/docker-compose.yml" up -d redis echo fake-async >/dev/null

echo "[test] Seeding Redis freelist..."
docker compose -f "$ROOT_DIR/docker-compose.yml" exec -T redis sh -lc 'redis-cli del ip_freelist >/dev/null 2>&1 || true; redis-cli sadd ip_freelist 10.0.0.1 >/dev/null'

echo "[test] Starting webserver..."
docker compose -f "$ROOT_DIR/docker-compose.yml" up -d ip-allocator-webserver >/dev/null

echo "[test] Waiting for webserver readiness..."
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' localhost:8000/ip/list || true)
  [ "$code" = "200" ] && break
  sleep 1
done

echo "[test] Borrowing IP..."
IP_JSON=$(curl -s localhost:8000/ip/borrow)
IP=$(printf '%s' "$IP_JSON" | sed -n 's/.*"ip":"\([^"]*\)".*/\1/p')
echo "[test] Borrowed: $IP"

echo "[test] Returning IP..."
OP_JSON=$(curl -s -X POST localhost:8000/ip/return -H 'content-type: application/json' -d "{\"ip\":\"$IP\"}")
OP_ID=$(printf '%s' "$OP_JSON" | sed -n 's/.*"operation_id":"\([^"]*\)".*/\1/p')
echo "[test] Operation: $OP_ID"

echo "[test] Immediately checking status, expecting pending..."
STATUS_JSON=$(curl -s "localhost:8000/operations/$OP_ID")
STATUS=$(printf '%s' "$STATUS_JSON" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
test "$STATUS" = "pending" || { echo "expected pending, got $STATUS"; exit 1; }

echo "[test] Checking freelist immediately, expecting empty..."
IPS_JSON=$(curl -s localhost:8000/ip/list)
COUNT=$(printf '%s' "$IPS_JSON" | grep -o '"ips":\[\([^\]]*\)\]' | sed 's/.*\[\(.*\)\].*/\1/' | awk -F, '{print NF==1 && $1=="" ? 0 : NF}')
test "$COUNT" -eq 0 || { echo "expected 0 available IPs, got $COUNT"; exit 1; }

echo "[test] Waiting for async completion ($FAKE_SUB_DELAY_SECS s + buffer)..."
sleep $((FAKE_SUB_DELAY_SECS + 2))

echo "[test] Checking status, expecting succeeded..."
STATUS_JSON=$(curl -s "localhost:8000/operations/$OP_ID")
STATUS=$(printf '%s' "$STATUS_JSON" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
test "$STATUS" = "succeeded" || { echo "expected succeeded, got $STATUS"; exit 1; }

echo "[test] Checking freelist after completion, expecting 1 IP back..."
IPS_JSON=$(curl -s localhost:8000/ip/list)
COUNT=$(printf '%s' "$IPS_JSON" | grep -o '"ips":\[\([^\]]*\)\]' | sed 's/.*\[\(.*\)\].*/\1/' | awk -F, '{print NF==1 && $1=="" ? 0 : NF}')
test "$COUNT" -eq 1 || { echo "expected 1 available IP, got $COUNT"; exit 1; }

echo "[test] PASS: return waits until async completion."


