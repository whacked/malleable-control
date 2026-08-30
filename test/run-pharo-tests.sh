#!/usr/bin/env bash
# Run the Pharo tests headless. No bus required.
source "$(dirname "$0")/../bin/_common.sh"

[ -x "$GT_CLI" ] || die "GT cli not found at $GT_CLI (set GT_HOME)"

# Temp declarations must come FIRST in a Smalltalk expression, before any
# statement -- putting "| result |" after the fileIn calls is a syntax error.
# Also || true: set -e would otherwise abort on a non-zero image exit before
# we get a chance to show why.
#
# McGtPatches is applied because McMarkdownTest covers a Microdown defect the
# patch repairs; without it that test fails for the reason it documents.
out="$("$GT_CLI" "$GT_IMAGE" eval "
  | suites result failed |
  '$MC_HOME/pharo/NatsClient.st' asFileReference fileIn.
  '$MC_HOME/pharo/NatsClientTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McGtPatches.st' asFileReference fileIn.
  '$MC_HOME/pharo/McMarkdown.st' asFileReference fileIn.
  '$MC_HOME/pharo/McRichEdit.st' asFileReference fileIn.
  '$MC_HOME/pharo/McRelation.st' asFileReference fileIn.
  '$MC_HOME/pharo/McRelationTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McMarkdownTest.st' asFileReference fileIn.
  (Smalltalk at: #McGtPatches) apply.
  failed := false.
  suites := OrderedCollection new.
  #( #NatsClientTest #McRelationTest #McMarkdownTest ) do: [ :each |
    result := (Smalltalk at: each) suite run.
    (result hasFailures or: [ result hasErrors ]) ifTrue: [ failed := true ].
    suites add: each -> result ].
  String streamContents: [ :s |
    suites do: [ :each |
      s << 'PHARO-TESTS ' << each key << ' ' << each value printString; cr.
      each value failures do: [ :t | s << '  FAIL ' << t selector; cr ].
      each value errors do: [ :t | s << '  ERROR ' << t selector; cr ] ].
    s << (failed ifTrue: [ 'PHARO_TESTS_FAILED' ] ifFalse: [ 'PHARO_TESTS_OK' ]) ]
" 2>&1)" || true

echo "$out"
grep -q PHARO_TESTS_OK <<<"$out" || die "pharo tests failed"
