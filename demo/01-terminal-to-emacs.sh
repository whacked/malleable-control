#!/usr/bin/env bash
# Terminal -> Emacs, request/reply.
# Proves: the terminal can ask Emacs a question and get an answer back.
source "$(dirname "$0")/../bin/_common.sh"
require_bus

echo "== ask Emacs what it can do =="
mc_request emacs.query.capabilities || die "emacs did not answer"
echo; echo

echo "== tell Emacs to open a file =="
printf 'hello from the terminal\nsecond line\n' > /tmp/mc-demo-01.txt
mc_request emacs.cmd.buffer.open '{"v":1,"args":{"path":"/tmp/mc-demo-01.txt"}}' || die "open failed"
echo; echo

echo "== ask Emacs to read it back =="
mc_request emacs.query.buffer.contents '{"v":1,"args":{"buffer":"mc-demo-01.txt"}}' || die "read failed"
echo
