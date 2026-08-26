#!/usr/bin/env bash
# The parent design's section 23 flow, end to end:
#
#   terminal  PUB emacs.cmd.buffer.open
#     Emacs   opens the file, PUB emacs.event.buffer.opened
#     GT      (subscribed to emacs.event.>) REQ emacs.query.buffer.contents
#     Emacs   replies with the contents
#     GT      PUB gt.event.inspector.opened
#   terminal  SUB gt.event.> observes it
#
# Every edge of the mesh is exercised, and nobody is the router.
source "$(dirname "$0")/../bin/_common.sh"
require_bus

FILE=/tmp/mc-demo-04.txt
printf 'the quick brown fox\njumps over\nthe lazy dog\n' > "$FILE"

echo "== watching gt.event.> =="
OUT="$(mktemp)"
nats --server "$MC_NATS_URL" sub "gt.event.>" --count=1 >"$OUT" 2>&1 &
SUBPID=$!
sleep 1

echo "== terminal publishes emacs.cmd.buffer.open =="
nats --server "$MC_NATS_URL" pub emacs.cmd.buffer.open \
  "{\"v\":1,\"args\":{\"path\":\"$FILE\"}}"

wait "$SUBPID" 2>/dev/null || true
echo
echo "== what GT announced, having asked Emacs about the file itself =="
cat "$OUT"
rm -f "$OUT"
