#!/usr/bin/env bash
# Fan-out: one publish, every interested participant sees it, nobody replies.
# Proves the third message category (events) alongside commands and queries.
source "$(dirname "$0")/../bin/_common.sh"
require_nats_cli
require_bus

echo "== watching system.event.> in the terminal =="
OUT="$(mktemp)"
nats --server "$MC_NATS_URL" sub "system.event.>" --count=1 >"$OUT" 2>&1 &
SUBPID=$!
sleep 1

echo "== publishing a broadcast =="
nats --server "$MC_NATS_URL" pub system.event.demo.ping \
  '{"v":1,"source":"terminal","data":{"note":"anyone listening"}}'

wait "$SUBPID" 2>/dev/null || true
cat "$OUT"
rm -f "$OUT"
echo
echo "No reply came back, and none was expected -- that is what an event is."
