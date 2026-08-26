#!/usr/bin/env bash
# Run the Pharo framing tests headless. No bus required.
source "$(dirname "$0")/../bin/_common.sh"

[ -x "$GT_CLI" ] || die "GT cli not found at $GT_CLI (set GT_HOME)"

# Temp declarations must come FIRST in a Smalltalk expression, before any
# statement -- putting "| result |" after the fileIn calls is a syntax error.
# Also || true: set -e would otherwise abort on a non-zero image exit before
# we get a chance to show why.
out="$("$GT_CLI" "$GT_IMAGE" eval "
  | result |
  '$MC_HOME/pharo/NatsClient.st' asFileReference fileIn.
  '$MC_HOME/pharo/NatsClientTest.st' asFileReference fileIn.
  result := (Smalltalk at: #NatsClientTest) suite run.
  String streamContents: [ :s |
    s << 'PHARO-TESTS ' << result printString; cr;
      << ((result hasFailures or: [ result hasErrors ])
            ifTrue: [ 'PHARO_TESTS_FAILED' ]
            ifFalse: [ 'PHARO_TESTS_OK' ]) ]
" 2>&1)" || true

echo "$out"
grep -q PHARO_TESTS_OK <<<"$out" || die "pharo tests failed"
