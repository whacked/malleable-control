# Sourced by every bin/ script. Not executable on its own.

set -euo pipefail

MC_HOME="${MC_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export MC_HOME

MC_RUN_DIR="${MC_RUN_DIR:-$MC_HOME/run}"
MC_NATS_PORT="${MC_NATS_PORT:-4223}"
MC_NATS_HOST="${MC_NATS_HOST:-127.0.0.1}"
MC_NATS_URL="${MC_NATS_URL:-nats://$MC_NATS_HOST:$MC_NATS_PORT}"
export MC_RUN_DIR MC_NATS_PORT MC_NATS_HOST MC_NATS_URL

MC_PID_FILE="$MC_RUN_DIR/nats-server.pid"
MC_LOG_FILE="$MC_RUN_DIR/nats-server.log"

GT_HOME="${GT_HOME:-/Applications/GlamorousToolkit-MacOS-aarch64-v1.1.564}"
GT_CLI="$GT_HOME/GlamorousToolkit.app/Contents/MacOS/GlamorousToolkit-cli"
GT_IMAGE="$GT_HOME/GlamorousToolkit.image"
export GT_HOME GT_CLI GT_IMAGE

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*" >&2; }

# True when a live nats-server is listening on our port.
bus_is_up() {
  [ -f "$MC_PID_FILE" ] || return 1
  local pid; pid="$(cat "$MC_PID_FILE" 2>/dev/null || true)"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null
}

require_bus() {
  bus_is_up || die "bus is not running on $MC_NATS_URL -- run: bin/bus-start"
}

# Issue a request and print the reply payload.
#
# `nats request` exits 0 even when nobody answered -- it prints "No responders
# are available" and calls that success. Relying on its exit status makes every
# liveness check a false positive. So: --raw (payload only, nothing on failure)
# plus an explicit empty-output test.
mc_request() {
  # NB: the default payload is built on its own line. Inlining it as
  # ${2:-{"v":1,"args":{}}} looks fine but is mis-parsed -- bash ends the
  # expansion at the first inner "}" and appends the rest as literal text,
  # silently corrupting every payload passed in. That produced JSON that
  # parsed to empty args, so handlers reported missing arguments for requests
  # that plainly had them.
  local subject="$1" payload="${2-}" timeout="${3:-5s}"
  local empty_args='{"v":1,"args":{}}'
  [ -n "$payload" ] || payload="$empty_args"
  local out
  out="$(nats --server "$MC_NATS_URL" request "$subject" "$payload" \
           --timeout="$timeout" --raw 2>/dev/null)" || return 1
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

# True when SUBJECT has a live responder.
mc_responds() { mc_request "$1" '{"v":1,"args":{}}' "${2:-1s}" >/dev/null 2>&1; }

# Emacs participant socket.
#
# Emacs puts daemon sockets in $TMPDIR/emacs<uid>/<name>, and nix-shell NESTS
# $TMPDIR -- so a daemon started in one shell is invisible to emacsclient in
# another. Pinning TMPDIR to one resolved location fixes that for both sides.
#
# Two things this must not be:
#   - an absolute --daemon=<path>: Emacs caps the daemon name length, and this
#     repo's path already exceeds it ("daemon: child name too long").
#   - /tmp on macOS: it is a symlink, and Emacs refuses to put a socket under
#     one ("is not a safe directory because it is a symlink").
# Hence pwd -P, which resolves to /private/tmp on macOS and /tmp on Linux.
MC_EMACS_TMPDIR="${MC_EMACS_TMPDIR:-$(cd /tmp && pwd -P)}"
MC_EMACS_DAEMON="${MC_EMACS_DAEMON:-mc-bus}"
export MC_EMACS_TMPDIR MC_EMACS_DAEMON

# Run emacs / emacsclient with the pinned TMPDIR so both agree on the socket.
mc_emacs()        { TMPDIR="$MC_EMACS_TMPDIR" emacs "$@"; }
mc_emacsclient()  { TMPDIR="$MC_EMACS_TMPDIR" emacsclient --socket-name="$MC_EMACS_DAEMON" "$@"; }
