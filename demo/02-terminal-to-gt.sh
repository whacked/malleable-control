#!/usr/bin/env bash
# Terminal -> Glamorous Toolkit, request/reply.
# Proves: GT is a peer, not a special case -- same envelope, same mechanics.
source "$(dirname "$0")/../bin/_common.sh"
require_nats_cli
require_bus
require_participant gt

echo "== ask GT what it can do =="
mc_request gt.query.capabilities || die "gt did not answer"
echo; echo

echo "== ask GT about its image =="
mc_request gt.query.image.info || die "image.info failed"
echo; echo

echo "== ask GT to inspect an expression =="
# Display-agnostic: headless this reports headless:true and opens nothing;
# in the windowed image the same call opens a real GT inspector.
mc_request gt.cmd.inspect '{"v":1,"args":{"expression":"3 + 4"}}' || die "inspect failed"
echo
