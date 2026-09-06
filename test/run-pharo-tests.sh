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
#
# Every tool's sources come from its launcher manifest rather than from a list
# kept here. This file used to hold its own copy and had already drifted: it
# filed in the corkboard, rich-edit, SRT and workbench sets and knew nothing
# about KDI's seven classes, so any KDI suite would silently not have existed.
# Reading launchers/ makes a bad path or a bad load order fail the run, which
# is what keeps the file GT's panel and Emacs also read from rotting.
#
# Classes are reached through `Smalltalk at:' rather than by name, because
# Pharo resolves variable names when it COMPILES this expression -- before any
# of the fileIns below have run.
out="$("$GT_CLI" "$GT_IMAGE" eval "
  | suites result failed manifests launcherTests names |
  '$MC_HOME/pharo/NatsClient.st' asFileReference fileIn.
  '$MC_HOME/pharo/NatsClientTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McGtPatches.st' asFileReference fileIn.
  '$MC_HOME/pharo/McOffUi.st' asFileReference fileIn.
  '$MC_HOME/pharo/McLauncher.st' asFileReference fileIn.

  manifests := (Smalltalk at: #McLauncherManifest)
    allIn: '$MC_HOME/launchers' asFileReference
    home: '$MC_HOME'.
  manifests isEmpty ifTrue: [ Error signal: 'no launcher manifests found' ].
  manifests do: [ :each |
    each isValid ifFalse: [
      Error signal: 'launcher manifest ' , each name , ': ' , each parseError ].
    each missingFiles ifNotEmpty: [ :missing |
      Error signal: 'launcher manifest ' , each name
        , ' names missing sources: ' , missing printString ].
    Smalltalk compiler evaluate: each loadExpression ].
  launcherTests := manifests flatCollect: [ :each | each tests ].

  '$MC_HOME/pharo/McLauncherTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McRelationTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McCacheTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McMarkdownTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McMarkdownSnapshotTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McMarkdownReconcilerTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McRichEditPerfTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McMarkdownLinkTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McSearchTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McCorkboardTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McSrtEditorTest.st' asFileReference fileIn.
  (Smalltalk at: #McGtPatches) apply.

  \"The suites that belong to no launcher -- the bus client and the manifest
   reader itself -- plus the union of what every launcher declares.\"
  names := (OrderedCollection new
    add: 'NatsClientTest';
    add: 'McLauncherManifestTest';
    addAll: launcherTests;
    yourself) asSet asSortedCollection.

  failed := false.
  suites := OrderedCollection new.
  names do: [ :eachName |
    (Smalltalk at: eachName asSymbol ifAbsent: [ nil ])
      ifNil: [
        failed := true.
        suites add: eachName -> 'NO SUCH TEST CLASS' ]
      ifNotNil: [ :cls |
        result := cls suite run.
        (result hasFailures or: [ result hasErrors ]) ifTrue: [ failed := true ].
        suites add: eachName -> result ] ].
  String streamContents: [ :s |
    suites do: [ :each |
      s << 'PHARO-TESTS ' << each key << ' ' << each value printString; cr.
      each value isString ifFalse: [
        each value failures do: [ :t | s << '  FAIL ' << t selector; cr ].
        each value errors do: [ :t | s << '  ERROR ' << t selector; cr ] ] ].
    s << (failed ifTrue: [ 'PHARO_TESTS_FAILED' ] ifFalse: [ 'PHARO_TESTS_OK' ]) ]
" 2>&1)" || true

echo "$out"
grep -q PHARO_TESTS_OK <<<"$out" || die "pharo tests failed"
