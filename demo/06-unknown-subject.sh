#!/usr/bin/env bash
# Capability filtering (parent design section 4), shown deliberately.
#
# Emacs never subscribed to emacs.cmd.make.sandwich, so the bus does not
# deliver it and the request simply times out. There is no error handler
# anywhere for "unsupported operation" -- the subscription set IS the
# capability list, and the bus does the filtering.
source "$(dirname "$0")/../bin/_common.sh"
require_nats_cli
require_bus
require_participant emacs

echo "== a subject Emacs does implement =="
mc_request emacs.query.buffer.current '{"v":1,"args":{}}' 2s && echo || echo "(unexpected: no answer)"
echo

echo "== a subject nobody implements =="
if mc_request emacs.cmd.make.sandwich '{"v":1,"args":{}}' 2s; then
  echo "(unexpected: something answered)"
else
  echo "no responder, request timed out -- correct."
fi
