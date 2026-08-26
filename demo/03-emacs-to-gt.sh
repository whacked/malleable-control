#!/usr/bin/env bash
# Emacs -> GT, request/reply, driven from inside Emacs.
# Proves: Emacs is a CLIENT of the bus, not only a service on it.
source "$(dirname "$0")/../bin/_common.sh"
require_nats_cli
require_bus
require_participant emacs
require_participant gt

command -v emacsclient >/dev/null || die "emacsclient not found"

echo "== M-x mc-demo-ask-gt, evaluated inside the Emacs participant =="
mc_emacsclient --eval '(mc-demo-ask-gt)' \
  || die "emacsclient failed -- is the emacs participant running?"
echo
echo "(that JSON was fetched by Emacs from GT, over the bus)"
