#!/usr/bin/env bash
# End-to-end proof that the three participants interoperate over NATS.
#
# Hermetic: its own port, its own run directory, its own Emacs daemon. It never
# touches a bus or participant you started by hand, and it tears down what it
# started. Exits non-zero if any check fails.
#
# Run inside nix-shell:  bash test/integration.sh

MC_HOME="${MC_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Distinct from the everyday bus so a running session is left alone.
export MC_NATS_PORT="${MC_TEST_PORT:-4299}"
export MC_NATS_HOST=127.0.0.1
export MC_NATS_URL="nats://127.0.0.1:$MC_NATS_PORT"
export MC_RUN_DIR="${MC_RUN_DIR_OVERRIDE:-$(mktemp -d "${TMPDIR:-/tmp}/mc-itest.XXXXXX")}"
export MC_EMACS_DAEMON="mc-bus-test"

source "$MC_HOME/bin/_common.sh"

PASSED=0
FAILED=0
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/mc-itest-work.XXXXXX")"

pass() { PASSED=$((PASSED+1)); printf '  ok   %s\n' "$1"; }
fail() { FAILED=$((FAILED+1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

check_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then pass "$label"
  else fail "$label" "expected to contain: $needle
       got: $haystack"; fi
}

teardown() {
  printf '\n-- teardown --\n' >&2
  "$MC_HOME/bin/gt-participant" stop  >/dev/null 2>&1 || true
  "$MC_HOME/bin/emacs-participant" stop >/dev/null 2>&1 || true
  "$MC_HOME/bin/bus-stop" >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
}
trap teardown EXIT

# Count how many replies come back for one request. More than one means a
# participant subscribed to the same subject twice -- the failure mode that
# looks completely healthy from a single `nats request`.
count_replies() {
  # The subscriber is killed after a fixed window rather than left to exit on
  # its own: `nats sub --timeout` bounds how long it waits to CONNECT, not how
  # long it stays subscribed, so waiting on it hangs forever. A --count would
  # exit early on the first reply and hide the duplicate we are looking for.
  local subject="$1" inbox="mc.itest.inbox.$$.$RANDOM" out
  out="$(mktemp "$WORKDIR/replies.XXXXXX")"
  nats --server "$MC_NATS_URL" sub "$inbox" >"$out" 2>&1 &
  local subpid=$!
  sleep 1
  nats --server "$MC_NATS_URL" pub "$subject" '{"v":1,"args":{}}' --reply "$inbox" \
    >/dev/null 2>&1
  sleep 2
  kill "$subpid" 2>/dev/null || true
  wait "$subpid" 2>/dev/null || true
  grep -c "Received on" "$out" 2>/dev/null || echo 0
}

printf '== bringing up an isolated bus on %s ==\n' "$MC_NATS_URL"
command -v nats-server >/dev/null || { echo "nats-server not on PATH -- run inside nix-shell"; exit 1; }
command -v nats        >/dev/null || { echo "nats CLI not on PATH -- run inside nix-shell"; exit 1; }

"$MC_HOME/bin/bus-start"          >/dev/null || { echo "bus failed to start"; exit 1; }
"$MC_HOME/bin/emacs-participant" start >/dev/null || { echo "emacs failed to start"; exit 1; }
"$MC_HOME/bin/gt-participant" start    >/dev/null || { echo "gt failed to start"; exit 1; }

printf '\n== participants answer for themselves ==\n'
check_contains "emacs serves emacs.query.capabilities" \
  "$(mc_request emacs.query.capabilities || echo NOREPLY)" '"ok":true'
check_contains "gt serves gt.query.capabilities" \
  "$(mc_request gt.query.capabilities || echo NOREPLY)" '"ok":true'

printf '\n== launchers come from launchers/, on both sides ==\n'
# The point of the manifests is that GT and Emacs cannot disagree about what
# is launchable. So assert the two counts against each other, not against a
# number written here -- a hardcoded 5 would go stale the first time a
# launcher is added, which is the exact failure being designed out.
LAUNCH_N="$(ls "$MC_HOME"/launchers/*.json 2>/dev/null | wc -l | tr -d ' ')"
EMACS_LAUNCHERS="$(mc_emacsclient --eval "(progn (add-to-list 'load-path \"$MC_HOME/elisp\") (require 'mc-launchers) (length (mc-launchers-load)))" 2>&1 || echo NOREPLY)"
check_contains "emacs defines a command per manifest ($LAUNCH_N)" \
  "$EMACS_LAUNCHERS" "$LAUNCH_N"
check_contains "emacs generated mc-corkboard-open" \
  "$(mc_emacsclient --eval "(fboundp 'mc-corkboard-open)" 2>&1 || echo NOREPLY)" 't'
GT_LAUNCHERS="$(mc_request gt.cmd.eval "$(printf '{"v":1,"args":{"expression":"((Smalltalk at: #McLauncherManifest) all) size printString"}}')" || echo NOREPLY)"
check_contains "gt reads the same manifests ($LAUNCH_N)" "$GT_LAUNCHERS" "$LAUNCH_N"

printf '\n== terminal -> emacs ==\n'
TESTFILE="$WORKDIR/hello.txt"
printf 'first line\nsecond line\nthird line\n' > "$TESTFILE"
check_contains "emacs.cmd.buffer.open succeeds" \
  "$(mc_request emacs.cmd.buffer.open "{\"v\":1,\"args\":{\"path\":\"$TESTFILE\"}}" || echo NOREPLY)" \
  '"ok":true'
check_contains "emacs.query.buffer.contents returns the file" \
  "$(mc_request emacs.query.buffer.contents "{\"v\":1,\"args\":{\"buffer\":\"hello.txt\"}}" || echo NOREPLY)" \
  'second line'

printf '\n== non-ASCII payload survives both clients ==\n'
UTF8FILE="$WORKDIR/utf8.txt"
printf 'h\xc3\xa9llo \xe2\x98\x83 world\n' > "$UTF8FILE"
mc_request emacs.cmd.buffer.open "{\"v\":1,\"args\":{\"path\":\"$UTF8FILE\"}}" >/dev/null || true
check_contains "utf-8 text round-trips (byte-count framing)" \
  "$(mc_request emacs.query.buffer.contents '{"v":1,"args":{"buffer":"utf8.txt"}}' || echo NOREPLY)" \
  'héllo ☃ world'

printf '\n== terminal -> gt ==\n'
check_contains "gt.query.image.info succeeds" \
  "$(mc_request gt.query.image.info || echo NOREPLY)" '"ok":true'
check_contains "gt.cmd.inspect evaluates and reports" \
  "$(mc_request gt.cmd.inspect '{"v":1,"args":{"expression":"3 + 4"}}' || echo NOREPLY)" \
  '"printString":"7"'

printf '\n== emacs -> gt (emacs as a client of the bus) ==\n'
check_contains "mc-demo-ask-gt fetches from GT" \
  "$(mc_emacsclient --eval '(mc-demo-ask-gt)' 2>&1 || echo NOREPLY)" '\"ok\":true'

printf '\n== the full mesh flow (parent design section 23) ==\n'
FLOWFILE="$WORKDIR/flow.txt"
printf 'the quick brown fox\njumps over\nthe lazy dog\n' > "$FLOWFILE"
FLOWOUT="$WORKDIR/flow-observed.txt"
nats --server "$MC_NATS_URL" sub "gt.event.>" --count=1 --timeout=15s >"$FLOWOUT" 2>&1 &
FLOWPID=$!
sleep 1
nats --server "$MC_NATS_URL" pub emacs.cmd.buffer.open \
  "{\"v\":1,\"args\":{\"path\":\"$FLOWFILE\"}}" >/dev/null 2>&1
wait "$FLOWPID" 2>/dev/null || true
FLOW="$(cat "$FLOWOUT")"
check_contains "gt announced on gt.event.inspector.opened" "$FLOW" 'gt.event.inspector.opened'
check_contains "gt was triggered by the emacs event"       "$FLOW" '"trigger":"emacs.event.buffer.opened"'
check_contains "gt had queried emacs for the contents"     "$FLOW" '"firstLine":"the quick brown fox"'
check_contains "gt counted the lines it was told about"    "$FLOW" '"lines":3'

printf '\n== failure paths ==\n'
check_contains "missing argument becomes a clean error reply" \
  "$(mc_request emacs.cmd.buffer.open '{"v":1,"args":{}}' || echo NOREPLY)" '"ok":false'
if mc_request emacs.cmd.make.sandwich '{"v":1,"args":{}}' 2s >/dev/null 2>&1; then
  fail "unimplemented subject has no responder" "something replied"
else
  pass "unimplemented subject has no responder"
fi

printf '\n== each request gets exactly one reply ==\n'
N_EMACS="$(count_replies emacs.query.capabilities)"
N_GT="$(count_replies gt.query.capabilities)"
[ "$N_EMACS" = "1" ] && pass "emacs replies exactly once" || fail "emacs replies exactly once" "got $N_EMACS replies"
[ "$N_GT"    = "1" ] && pass "gt replies exactly once"    || fail "gt replies exactly once"    "got $N_GT replies"

printf '\n== participants survive a bus restart ==\n'
"$MC_HOME/bin/bus-stop" >/dev/null 2>&1
sleep 1
"$MC_HOME/bin/bus-start" >/dev/null 2>&1
# Both clients reconnect on their own backoff; give them room to do it.
reconnected=0
for _ in $(seq 1 40); do
  if mc_responds emacs.query.capabilities 1s && mc_responds gt.query.capabilities 1s; then
    reconnected=1; break
  fi
  sleep 1
done
if [ "$reconnected" = 1 ]; then
  pass "emacs and gt reconnected without being restarted"
else
  fail "emacs and gt reconnected without being restarted" "still silent after 40s"
fi
N_EMACS2="$(count_replies emacs.query.capabilities)"
N_GT2="$(count_replies gt.query.capabilities)"
[ "$N_EMACS2" = "1" ] && pass "emacs still replies exactly once after reconnect" \
  || fail "emacs still replies exactly once after reconnect" "got $N_EMACS2 replies (duplicate subscriptions?)"
[ "$N_GT2" = "1" ] && pass "gt still replies exactly once after reconnect" \
  || fail "gt still replies exactly once after reconnect" "got $N_GT2 replies (duplicate subscriptions?)"

printf '\n===============================\n'
printf 'passed: %d   failed: %d\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
printf 'INTEGRATION OK\n'
