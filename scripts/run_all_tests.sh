#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

chmod +x "$ROOT_DIR/scripts"/*.sh || true

echo "== Running: test_borrow_sync.sh =="
"$ROOT_DIR/scripts/test_borrow_sync.sh"

echo "== Running: test_borrow_async_nonblocking.sh =="
"$ROOT_DIR/scripts/test_borrow_async_nonblocking.sh"

echo "== Running: test_return_async.sh =="
"$ROOT_DIR/scripts/test_return_async.sh"

echo "All integration tests passed."


