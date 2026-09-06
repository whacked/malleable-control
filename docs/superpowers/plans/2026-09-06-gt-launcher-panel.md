# GT Launcher Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A fourth panel on GT's home screen whose launcher buttons are built by reading `launchers/*.json`, so adding a tool means adding one file that GT, Emacs and the test runner all read.

**Architecture:** One JSON manifest per tool records the ordered `.st` load list and one `open` expression — the facts currently triplicated across elisp and `test/run-pharo-tests.sh`. `McLauncherManifest` reads them in the image; `McLauncherSection` (a `GtHomeSection`) builds one card per manifest and enters `GtHome` through a `<gtHomeSection>` package extension method; `elisp/mc-launchers.el` generates `mc-<name>-open` from the same files; `test/run-pharo-tests.sh` files in and runs from them too.

**Tech Stack:** Pharo 12 / Glamorous Toolkit (Bloc, Brick, GtHome/Phlow), `NeoJSONReader`, SUnit; Emacs Lisp with built-in `json-parse-string`; bash; NATS bus via `bin/gt-eval`.

**Spec:** `docs/superpowers/specs/2026-09-06-gt-launcher-panel-design.md`

## Global Constraints

- All work happens in `$CLOUDSYNC/main/devsync/malleable-control`. Nothing is written to the knowledge-base-collector repo.
- Pharo source is **chunk format**, matching `pharo/McSrtEntry.st`: a `"…"!` file comment, `Object subclass: #Name … package: 'MalleableControl'!`, then `!Name methodsFor: 'protocol'!` blocks, methods separated by `!`, block terminated by `! !`.
- Every new Pharo class uses `package: 'MalleableControl'`.
- Evaluating a string in the image is `Smalltalk compiler evaluate:` — the idiom already used in `pharo/McGtService.st:190`.
- JSON in Pharo is `NeoJSONReader fromString:`, which answers a `Dictionary` with **String** keys, JSON arrays as `Array`, and raises `NeoJSONParseError` on malformed input.
- `aFileReference base` answers the basename without extension (`corkboard.json` → `'corkboard'`); `basename` keeps the extension.
- The repo root inside the image is `Smalltalk at: #McHome`, set by the generated startup script. Manifest `files` paths are relative to it.
- Section ordering: `GtPhlowUtility class >> hasHigherPriority:than:` compares with `<`, so **lower priority sorts earlier**. `GtHomeMultiCardGetStartedSection` is 30; the launcher panel is 40.
- Headless Pharo tests run with `test/run-pharo-tests.sh`. It needs no bus. `bin/_common.sh` exports `MC_HOME`, `GT_CLI`, `GT_IMAGE`.
- Live checks against the running image run through `nix-shell --run "bin/gt-eval '…'"` — the `nats` CLI is only on PATH inside `nix-shell`.
- No emoji anywhere in code, comments, commit messages or docs.
- Comments explain **why**, matching the density and voice of the surrounding files. Every non-obvious guard says what breaks without it.

---

### Task 1: `McLauncherManifest` — read one launcher file

**Files:**
- Create: `pharo/McLauncher.st`
- Create: `pharo/McLauncherTest.st`
- Modify: `test/run-pharo-tests.sh` (add the two fileIns and `#McLauncherManifestTest` to the suite list)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `McLauncherManifest class >> fromFile: aFileReference home: aHomeString` → a manifest, valid or invalid, never nil, never raising
  - `McLauncherManifest class >> allIn: aDirectoryReference home: aHomeString` → `Array` of manifests, sorted
  - `McLauncherManifest class >> all` → `self allIn: self defaultDirectory home: self defaultHome`
  - `McLauncherManifest class >> defaultHome` → `Smalltalk at: #McHome ifAbsent: [ nil ]`
  - `McLauncherManifest class >> defaultDirectory` → `(self defaultHome , '/launchers') asFileReference`
  - Instance: `name`, `title`, `blurb`, `files`, `openExpression`, `tests`, `priority`, `icon`, `isValid`, `parseError`, `missingFiles`, `isSatisfiable`, `tooltip`, `loadExpression`, `launchExpression`, `sortsBefore:`

**Design note for the implementer:** `home` is an instance variable passed in, not read from the `McHome` global inside the object. That is what makes `missingFiles` testable against a temp directory without touching image globals.

- [ ] **Step 1: Write the failing tests**

Create `pharo/McLauncherTest.st`:

```smalltalk
"
McLauncherTest -- the launcher manifest reader.

These are pure model tests: they build .json files in a temp directory and
read them back.  Nothing here opens a window, which matches the rest of this
repo -- McCorkboardTest tests McCorkboardPanelModel, not the Bloc canvas.

The behaviour under test that matters most is the refusal to fail silently.
A manifest that would not parse must still appear in the listing, carrying
its error, because a launcher that vanishes when you typo its JSON is the
exact failure this whole mechanism exists to prevent.
"!

TestCase subclass: #McLauncherManifestTest
	instanceVariableNames: 'home dir'
	classVariableNames: ''
	package: 'MalleableControl'!

!McLauncherManifestTest methodsFor: 'running'!
setUp
	super setUp.
	home := FileLocator temp / ('mc-launcher-test-' , UUID new asString36).
	dir := home / 'launchers'.
	dir ensureCreateDirectory.
	(home / 'pharo') ensureCreateDirectory!

tearDown
	[ home ensureDeleteAll ] on: Error do: [ :e |  ].
	super tearDown! !

!McLauncherManifestTest methodsFor: 'helpers'!
write: aName contents: aString
	| ref |
	ref := dir / aName.
	ref writeStreamDo: [ :s | s nextPutAll: aString ].
	^ ref!

touchSource: aRelativePath
	| ref |
	ref := home resolve: aRelativePath.
	ref parent ensureCreateDirectory.
	ref writeStreamDo: [ :s | s nextPutAll: '"stub"!' ].
	^ ref!

goodJson
	^ '{ "title": "Corkboard",
	     "blurb": "Coordinate-addressable canvas",
	     "files": ["pharo/McCorkboardDocument.st", "pharo/McCorkboard.st"],
	     "open": "McCorkboard open",
	     "tests": ["McCorkboardTest"],
	     "priority": 30 }'!

readOne: aName
	^ McLauncherManifest fromFile: dir / aName home: home fullName! !

!McLauncherManifestTest methodsFor: 'tests'!
testWellFormedManifestParsesEveryField
	| m |
	self write: 'corkboard.json' contents: self goodJson.
	m := self readOne: 'corkboard.json'.
	self assert: m isValid.
	self assert: m parseError isNil.
	self assert: m title equals: 'Corkboard'.
	self assert: m blurb equals: 'Coordinate-addressable canvas'.
	self assert: m files asArray
		equals: #('pharo/McCorkboardDocument.st' 'pharo/McCorkboard.st').
	self assert: m openExpression equals: 'McCorkboard open'.
	self assert: m tests asArray equals: #('McCorkboardTest').
	self assert: m priority equals: 30!

testNameComesFromFilenameNotFromAField
	"The Emacs command name is derived, so two launchers cannot collide and
	 mc-corkboard-open is predictable without opening the file."
	| m |
	self write: 'corkboard.json' contents: self goodJson.
	m := self readOne: 'corkboard.json'.
	self assert: m name equals: 'corkboard'!

testMalformedJsonAnswersInvalidManifestCarryingTheError
	| m |
	self write: 'broken.json' contents: '{ not json'.
	m := self readOne: 'broken.json'.
	self deny: m isValid.
	self assert: m name equals: 'broken'.
	self deny: m parseError isNil.
	self assert: m title equals: 'broken'!

testMissingRequiredKeyAnswersInvalidNamingTheKey
	| m |
	self write: 'nofiles.json'
		contents: '{ "title": "X", "blurb": "y", "open": "X open" }'.
	m := self readOne: 'nofiles.json'.
	self deny: m isValid.
	self assert: (m parseError includesSubstring: 'files')!

testTopLevelArrayIsInvalidRatherThanRaising
	| m |
	self write: 'array.json' contents: '[1, 2, 3]'.
	m := self readOne: 'array.json'.
	self deny: m isValid!

testMissingFilesAreNamedAndTheManifestStaysValid
	"A manifest pointing at a source that is not there is valid but
	 unsatisfiable: the card still renders, and says which path is missing."
	| m |
	self touchSource: 'pharo/McCorkboard.st'.
	self write: 'corkboard.json' contents: self goodJson.
	m := self readOne: 'corkboard.json'.
	self assert: m isValid.
	self deny: m isSatisfiable.
	self assert: m missingFiles asArray
		equals: #('pharo/McCorkboardDocument.st')!

testSatisfiableWhenEverySourceExists
	| m |
	self touchSource: 'pharo/McCorkboard.st'.
	self touchSource: 'pharo/McCorkboardDocument.st'.
	self write: 'corkboard.json' contents: self goodJson.
	m := self readOne: 'corkboard.json'.
	self assert: m isSatisfiable.
	self assert: m missingFiles isEmpty!

testUnknownKeysAreIgnoredSoTheFormatCanGrow
	| m |
	self write: 'future.json'
		contents: '{ "title": "X", "blurb": "y", "files": [], "open": "X open",
		             "somethingAddedLater": 42, "note": "a comment" }'.
	m := self readOne: 'future.json'.
	self assert: m isValid.
	self assert: m title equals: 'X'!

testOrderingIsByPriorityThenTitle
	| names |
	self write: 'b.json'
		contents: '{ "title": "Bravo", "blurb": "b", "files": [], "open": "B", "priority": 10 }'.
	self write: 'a.json'
		contents: '{ "title": "Alpha", "blurb": "a", "files": [], "open": "A", "priority": 20 }'.
	self write: 'c.json'
		contents: '{ "title": "Charlie", "blurb": "c", "files": [], "open": "C", "priority": 10 }'.
	names := (McLauncherManifest allIn: dir home: home fullName)
		collect: [ :each | each title ].
	self assert: names asArray equals: #('Bravo' 'Charlie' 'Alpha')!

testManifestWithoutPrioritySortsLast
	| names |
	self write: 'a.json'
		contents: '{ "title": "Alpha", "blurb": "a", "files": [], "open": "A" }'.
	self write: 'b.json'
		contents: '{ "title": "Bravo", "blurb": "b", "files": [], "open": "B", "priority": 99 }'.
	names := (McLauncherManifest allIn: dir home: home fullName)
		collect: [ :each | each title ].
	self assert: names asArray equals: #('Bravo' 'Alpha')!

testNonJsonFilesInTheDirectoryAreIgnored
	| all |
	self write: 'a.json'
		contents: '{ "title": "Alpha", "blurb": "a", "files": [], "open": "A" }'.
	self write: 'README.md' contents: 'not a launcher'.
	all := McLauncherManifest allIn: dir home: home fullName.
	self assert: all size equals: 1!

testMissingDirectoryAnswersEmptyRatherThanRaising
	| all |
	all := McLauncherManifest
		allIn: home / 'no-such-dir'
		home: home fullName.
	self assert: all isEmpty!

testLaunchExpressionFilesInEverySourceThenOpens
	| m expr |
	self write: 'corkboard.json' contents: self goodJson.
	m := self readOne: 'corkboard.json'.
	expr := m launchExpression.
	self assert: (expr includesSubstring: 'pharo/McCorkboardDocument.st').
	self assert: (expr includesSubstring: 'pharo/McCorkboard.st').
	self assert: (expr includesSubstring: 'fileIn').
	self assert: (expr endsWith: 'McCorkboard open').
	"Load order is the whole point: the document must be filed in first."
	self assert: (expr indexOfSubCollection: 'McCorkboardDocument.st')
		< (expr indexOfSubCollection: 'pharo/McCorkboard.st')! !
```

- [ ] **Step 2: Add the new files to the test runner**

In `test/run-pharo-tests.sh`, add after the `McWorkbench.st` fileIn line:

```bash
  '$MC_HOME/pharo/McLauncher.st' asFileReference fileIn.
```

add after the `McSrtEditorTest.st` fileIn line:

```bash
  '$MC_HOME/pharo/McLauncherTest.st' asFileReference fileIn.
```

and append `#McLauncherManifestTest` to the `#( … )` suite list.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd $CLOUDSYNC/main/devsync/malleable-control && test/run-pharo-tests.sh 2>&1 | tail -30`

Expected: FAIL — the run aborts because `pharo/McLauncher.st` does not exist, or `McLauncherManifest` is not in the image.

- [ ] **Step 4: Write `pharo/McLauncher.st`**

```smalltalk
"
McLauncherManifest -- one launchers/*.json file, read.

A launcher is two facts: an ordered list of .st files to file in, and one
expression to evaluate once they are in.  Until this class existed neither
fact was written anywhere the image could read.  Both lived in elisp, and a
third copy lived in test/run-pharo-tests.sh -- which had already drifted,
knowing nothing about KDI's seven classes.  This is the single reader.

Nothing here fails silently, because silent failure is the disease being
treated.  A file that will not parse answers an INVALID manifest carrying the
error, so the panel renders a card saying so.  A manifest that disappeared
from the listing when you typo'd its JSON would reproduce the original
problem in a new place.

`home' is an instance variable rather than a read of the McHome global, so
the reader can be tested against a temp directory.
"!

Object subclass: #McLauncherManifest
	instanceVariableNames: 'home name title blurb files openExpression tests priority icon parseError'
	classVariableNames: ''
	package: 'MalleableControl'!

!McLauncherManifest class methodsFor: 'accessing'!
defaultHome
	"The repo root, set into the image by the generated startup script."
	^ Smalltalk at: #McHome ifAbsent: [ nil ]!

defaultDirectory
	^ self defaultHome
		ifNil: [ nil ]
		ifNotNil: [ :h | (h , '/launchers') asFileReference ]!

requiredKeys
	^ #('title' 'blurb' 'files' 'open')!

noPriority
	"Sorts last.  A manifest that declines to say where it goes goes last,
	 rather than jumping the queue by defaulting to zero."
	^ SmallInteger maxVal! !

!McLauncherManifest class methodsFor: 'instance creation'!
all
	| directory |
	directory := self defaultDirectory.
	directory ifNil: [ ^ #() ].
	^ self allIn: directory home: self defaultHome!

allIn: aDirectory home: aHomeString
	"Every *.json in aDirectory, sorted.  A directory that is not there
	 answers empty rather than raising: an image with no launchers/ is a
	 legitimate state, and the home screen must still render."
	| files |
	(aDirectory notNil and: [ aDirectory exists ]) ifFalse: [ ^ #() ].
	files := [ aDirectory files select: [ :each | each extension = 'json' ] ]
		on: Error
		do: [ :e | ^ #() ].
	^ ((files collect: [ :each | self fromFile: each home: aHomeString ])
		asSortedCollection: [ :a :b | a sortsBefore: b ]) asArray!

fromFile: aFileReference home: aHomeString
	"Read one manifest.  Never raises and never answers nil: a file that
	 cannot be read becomes an invalid manifest that says why."
	| json |
	json := [ NeoJSONReader fromString: aFileReference contents ]
		on: Error
		do: [ :e |
			^ self
				invalid: aFileReference base
				home: aHomeString
				error: e messageText asString ].
	(json isKindOf: Dictionary) ifFalse: [
		^ self
			invalid: aFileReference base
			home: aHomeString
			error: 'top level is not a JSON object' ].
	self requiredKeys do: [ :key |
		(json includesKey: key) ifFalse: [
			^ self
				invalid: aFileReference base
				home: aHomeString
				error: 'missing required key: ' , key ] ].
	^ self new
		setName: aFileReference base home: aHomeString json: json;
		yourself!

invalid: aName home: aHomeString error: aMessage
	^ self new
		setInvalidName: aName home: aHomeString error: aMessage;
		yourself! !

!McLauncherManifest methodsFor: 'initialization'!
setName: aName home: aHomeString json: aDictionary
	name := aName.
	home := aHomeString.
	title := aDictionary at: 'title'.
	blurb := aDictionary at: 'blurb'.
	files := (aDictionary at: 'files') asArray.
	openExpression := aDictionary at: 'open'.
	tests := (aDictionary at: 'tests' ifAbsent: [ #() ]) asArray.
	priority := aDictionary at: 'priority' ifAbsent: [ self class noPriority ].
	icon := aDictionary at: 'icon' ifAbsent: [ nil ].
	parseError := nil!

setInvalidName: aName home: aHomeString error: aMessage
	"An invalid manifest still answers a title and a priority, so it can sit
	 in the same sorted listing as the others instead of needing a special
	 case at every call site."
	name := aName.
	home := aHomeString.
	parseError := aMessage.
	title := aName.
	blurb := aMessage.
	files := #().
	openExpression := nil.
	tests := #().
	priority := self class noPriority.
	icon := nil! !

!McLauncherManifest methodsFor: 'accessing'!
name
	"Derived from the filename, not from a field: two launchers cannot
	 collide, and the Emacs command mc-<name>-open is predictable."
	^ name!

home
	^ home!

title
	^ title!

blurb
	^ blurb!

files
	^ files!

openExpression
	^ openExpression!

tests
	^ tests!

priority
	^ priority!

icon
	^ icon!

parseError
	^ parseError! !

!McLauncherManifest methodsFor: 'testing'!
isValid
	^ parseError isNil!

isSatisfiable
	^ self isValid and: [ self missingFiles isEmpty ]! !

!McLauncherManifest methodsFor: 'querying'!
missingFiles
	"The entries of `files' that are not on disk.  Checked at render time so
	 the card can say which source is missing before you click it."
	self isValid ifFalse: [ ^ #() ].
	home ifNil: [ ^ #() ].
	^ (files reject: [ :each | (self absolutePathFor: each) asFileReference exists ])
		asArray!

absolutePathFor: aRelativePath
	^ home , '/' , aRelativePath!

tooltip
	"What the card says on hover.  An unsatisfiable launcher says so here
	 rather than only when clicked."
	| missing |
	self isValid ifFalse: [ ^ name , '.json: ' , parseError ].
	missing := self missingFiles.
	missing isEmpty ifTrue: [ ^ blurb ].
	^ blurb , String cr , 'missing: ' , (', ' join: missing)! !

!McLauncherManifest methodsFor: 'expressions'!
loadExpression
	"The fileIn chain, in the manifest's order.  Order is the whole content
	 of `files': McKdiEvidence defines McKdiObject, which every other KDI
	 class subclasses, so a set filed in the wrong order leaves the rest
	 stale rather than failing outright."
	^ String streamContents: [ :s |
		files do: [ :each |
			s nextPut: $'.
			s nextPutAll: (self absolutePathFor: each).
			s nextPutAll: ''' asFileReference fileIn. ' ] ]!

launchExpression
	"File everything in, then open.  Every click re-files from disk, so
	 editing a .st and pressing the button reloads it."
	^ self loadExpression , openExpression! !

!McLauncherManifest methodsFor: 'sorting'!
sortsBefore: another
	priority = another priority ifTrue: [ ^ title < another title ].
	^ priority < another priority! !

!McLauncherManifest methodsFor: 'printing'!
printOn: aStream
	super printOn: aStream.
	aStream nextPut: $(.
	aStream nextPutAll: (name ifNil: [ '?' ]).
	self isValid ifFalse: [ aStream nextPutAll: ' INVALID' ].
	aStream nextPut: $)! !
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd $CLOUDSYNC/main/devsync/malleable-control && test/run-pharo-tests.sh 2>&1 | tail -30`

Expected: `PHARO-TESTS McLauncherManifestTest 13 ran, 13 passed` and `PHARO_TESTS_OK`.

- [ ] **Step 6: Commit**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
git add pharo/McLauncher.st pharo/McLauncherTest.st test/run-pharo-tests.sh
git commit -m "Read a launcher manifest in the image

A launcher is an ordered .st load list plus one open expression, and
neither fact was written anywhere GT could read. McLauncherManifest is
the single reader.

An unparseable file answers an invalid manifest carrying its error
rather than raising or vanishing, because a launcher that disappears
when you typo its JSON reproduces the original problem."
```

---

### Task 2: The five manifests and KDI's launcher entry point

**Files:**
- Create: `launchers/corkboard.json`, `launchers/workbench.json`, `launchers/rich-edit.json`, `launchers/kdi.json`, `launchers/weather.json`
- Modify: `pharo/McKdiStore.st` (add `McKdiStore class >> openLauncherSession`)

**Interfaces:**
- Consumes: nothing from Task 1 at runtime; the manifests must satisfy the schema Task 1 reads.
- Produces: `McKdiStore class >> openLauncherSession`, referenced by `launchers/kdi.json`.

**Why KDI needs a new selector:** `McKdiStore class >> openSession` raises `'no KDI store bound -- run mc-kdi-bind first'`, and `McKdiStore class >> default` is commented "a store on the binding **the Emacs launcher** last installed". A card on GT's home screen cannot require that Emacs ran first — that is the backwards dependency this whole change exists to remove.

- [ ] **Step 1: Write the five manifests**

`launchers/corkboard.json`:

```json
{
  "title": "Corkboard",
  "blurb": "Coordinate-addressable canvas, independent of the rich editor",
  "files": [
    "pharo/McCorkboardPanelModel.st",
    "pharo/McCorkboardDocument.st",
    "pharo/McCorkboard.st"
  ],
  "open": "McCorkboard open",
  "tests": ["McCorkboardTest"],
  "priority": 30,
  "note": "McCorkboard projects a McCorkboardDocument, which holds McCorkboardPanelModel instances."
}
```

`launchers/workbench.json`:

```json
{
  "title": "Workbench",
  "blurb": "SRT subtitle editor beside a tmux-backed terminal",
  "files": [
    "pharo/McSrtEntry.st",
    "pharo/McSrtEditor.st",
    "pharo/McTerminal.st",
    "pharo/McWorkbench.st"
  ],
  "open": "McWorkbench open",
  "tests": ["McSrtEditorTest"],
  "priority": 40,
  "note": "McSrtEditor depends on McSrtEntry; McWorkbench depends on both editors."
}
```

`launchers/rich-edit.json`:

```json
{
  "title": "Rich Edit",
  "blurb": "Live-styled Markdown editor with search, links and tables",
  "files": [
    "pharo/McCache.st",
    "pharo/McRelation.st",
    "pharo/McMarkdownLink.st",
    "pharo/McMarkdownInline.st",
    "pharo/McMarkdownTable.st",
    "pharo/McSqlite.st",
    "pharo/McMarkdown.st",
    "pharo/McMarkdownSnapshot.st",
    "pharo/McMarkdownReconciler.st",
    "pharo/McKeymap.st",
    "pharo/McSearch.st",
    "pharo/McRichEdit.st",
    "pharo/McRichEditLinks.st"
  ],
  "open": "McRichEdit open",
  "tests": [
    "McRelationTest",
    "McCacheTest",
    "McMarkdownTest",
    "McMarkdownSnapshotTest",
    "McMarkdownReconcilerTest",
    "McRichEditPerfTest",
    "McMarkdownLinkTest",
    "McSearchMatcherTest",
    "McSearchSessionTest",
    "McSearchResultTest",
    "McSearchPresentationTest",
    "McCommandKeymapTest"
  ],
  "priority": 20,
  "note": "Order matters: McBoundedCache is used by McMarkdownInline, McMarkdownTable and McSqlite; McMarkdownTable's cell reader and McSqlite depend on McRelation; McMarkdown's visitor calls into McMarkdownInline, McMarkdownTable and McSqlite; McRichEdit's styler calls into McMarkdown."
}
```

`launchers/kdi.json`:

```json
{
  "title": "KDI Explorer",
  "blurb": "Moldable alternative to kdi tui; drill down from source to grounding",
  "files": [
    "pharo/McKdi.st",
    "pharo/McKdiEvidence.st",
    "pharo/McKdiStore.st",
    "pharo/McKdiDiscovery.st",
    "pharo/McKdiInfer.st",
    "pharo/McKdiSlice.st",
    "pharo/McKdiReport.st"
  ],
  "open": "McKdiStore openLauncherSession",
  "priority": 10,
  "note": "McKdiEvidence defines McKdiObject, which every other class subclasses, so reloading it alone leaves the rest stale. Always file these in as a set. No tests key: the KDI classes have no suite yet."
}
```

`launchers/weather.json`:

```json
{
  "title": "Weather",
  "blurb": "Fetches Open-Meteo, renders vector icons, publishes back over the bus",
  "files": ["pharo/McWeatherView.st"],
  "open": "McWeatherView open",
  "priority": 50
}
```

- [ ] **Step 2: Write the failing check for the KDI entry point**

There is no SUnit suite for the KDI classes, so this is checked live rather than in the headless runner. Run against the running image:

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
nix-shell --run "bin/gt-eval '(McKdiStore respondsTo: #openLauncherSession) printString'"
```

Expected: `false`.

- [ ] **Step 3: Add `openLauncherSession` to `pharo/McKdiStore.st`**

The existing block currently reads `… ifNotNil: [ :s | s open ]! !` — a single `!` ending `openSession`, then the space-`!` that closes the whole `methodsFor:` block. Change that line to end with one `!`, then append the two methods below, with the final one ending `! !`:

```smalltalk
openLauncherSession
	"openSession for a caller that is not Emacs.

	 `session' answers the store the Emacs launcher bound, and `openSession'
	 raises when nothing has.  A card on GT's home screen cannot require that
	 Emacs ran first -- that dependency is backwards, since GT is the core and
	 Emacs is a client of the bus.  So: reuse an installed binding if there is
	 one, otherwise build one from the KDI_* environment variables, which are
	 the same defaults mc-kdi.el's defcustoms fall back to.

	 With neither available this reports what is missing rather than raising,
	 so the launcher card can say so."
	self session ifNotNil: [ :s | ^ s open ].
	^ self bindingFromEnvironment
		ifNil: [ self error: 'no KDI store bound, and KDI_STORE_PATH is not set -- run mc-kdi-bind, or set KDI_STORE_PATH and KDI_PROFILE' ]
		ifNotNil: [ :b |
			McKdiBinding default: b.
			(self session: (self on: b)) open ]!

bindingFromEnvironment
	"A binding from KDI_*, or nil when the store path is not set.  The store
	 path is the only setting with no usable default, which is why it alone
	 decides whether this answers a binding at all."
	| env at store |
	env := [ Smalltalk os environment ] on: Error do: [ :e | ^ nil ].
	at := [ :key :default |
		| v | v := [ env at: key ifAbsent: [ nil ] ] on: Error do: [ :e | nil ].
		(v isNil or: [ v isEmpty ]) ifTrue: [ default ] ifFalse: [ v ] ].
	store := at value: 'KDI_STORE_PATH' value: nil.
	store ifNil: [ ^ nil ].
	^ McKdiBinding
		root: (at value: 'KDI_ROOT' value: FileSystem workingDirectory fullName)
		store: store
		profile: (at value: 'KDI_PROFILE' value: 'local')
		tier: (at value: 'KDI_TIER' value: 'public')
		configDir: (at value: 'KDI_CONFIG_DIR' value: nil)! !
```

- [ ] **Step 4: Verify the entry point exists and the manifests parse**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
nix-shell --run "bin/gt-eval \"'\$PWD/pharo/McKdi.st' asFileReference fileIn. '\$PWD/pharo/McKdiEvidence.st' asFileReference fileIn. '\$PWD/pharo/McKdiStore.st' asFileReference fileIn. (McKdiStore respondsTo: #openLauncherSession) printString\""
```

Expected: `true`.

Then check every manifest reads, and that no manifest points at a file that is not there:

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
nix-shell --run "bin/gt-eval \"'\$PWD/pharo/McLauncher.st' asFileReference fileIn. String streamContents: [ :s | (McLauncherManifest allIn: '\$PWD/launchers' asFileReference home: '\$PWD') do: [ :m | s << m name << ' valid=' << m isValid printString << ' satisfiable=' << m isSatisfiable printString << ' missing=' << m missingFiles printString; cr ] ]\""
```

Expected: five lines, every one `valid=true satisfiable=true missing=#()`.

- [ ] **Step 5: Commit**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
git add launchers/ pharo/McKdiStore.st
git commit -m "Record every launcher as a manifest

One JSON file per tool, holding the ordered .st load list and the open
expression. These are the lists that were duplicated across elisp and
test/run-pharo-tests.sh.

McKdiStore openLauncherSession is new because openSession raises unless
Emacs bound a store first, and a card on GT's home screen cannot depend
on Emacs having run."
```

---

### Task 3: `McOffUi` — the shared off-the-UI-process runner

**Files:**
- Create: `pharo/McOffUi.st`
- Modify: `pharo/McKdiStore.st` (`runOffUi:from:labelled:` delegates)
- Modify: `test/run-pharo-tests.sh` (fileIn `McOffUi.st` before `McLauncher.st`)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `McOffUi class >> run: aBlock from: aButton labelled: aString onError: anErrorBlock`
  - `McOffUi class >> run: aBlock from: aButton labelled: aString`

**Why this exists:** `McKdiStore >> runOffUi:from:labelled:` documents two traps that were paid for in debugging: a subprocess or a long fileIn on the UI process is "not a spinner, it is a hang", and refreshing through a phlow update wish **replaces the button element**, so the completion callback is enqueued on a detached element and the label sticks at "running" for a job that finished. Filing in Rich Edit's thirteen sources is the same shape of work. Copying the method would mean a second copy of a comment whose entire content is "here is what we got wrong last time".

**Care required:** `McKdiStore`'s version also maintains a `runningLabel` instance variable that drives `actionLabel:` across the whole toolbar. That is store state, not button state, and it must stay in `McKdiStore`. Only the mechanics move.

- [ ] **Step 1: Write `pharo/McOffUi.st`**

```smalltalk
"
McOffUi -- run work off the UI process, with the pressed button as its
progress indicator.

Lifted out of McKdiStore, where it was written the hard way.  Two traps are
encoded here, and both cost real debugging time:

  1. Work run on the UI process freezes the whole image until it finishes.
     For a corpus ingestion, or thirteen fileIns, that is not a spinner, it
     is a hang -- and the reasonable thing to do while looking at a frozen
     window is press the button again.

  2. The busy state is written STRAIGHT ONTO the pressed button, not through
     a phlow update wish.  A wish rebuilds every open pane and REPLACES the
     button element, so the completion refresh was being enqueued on a
     detached element and never ran.  The label stuck at `running' for a job
     that had already finished.

A second press while the first is in flight is IGNORED rather than queued.
Two runs of the same job race, and the second one loses in a way that reads
as a refusal of the first.
"!

Object subclass: #McOffUi
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McOffUi class methodsFor: 'running'!
run: aBlock from: aButton labelled: aLabel
	^ self run: aBlock from: aButton labelled: aLabel onError: [ :err |  ]!

run: aBlock from: aButton labelled: aLabel onError: anErrorBlock
	"Fork aBlock, marking aButton busy for its duration.  anErrorBlock is
	 evaluated with the frozen error, on the forked process, before the
	 button is released."
	(self isBusy: aButton) ifTrue: [ ^ self ].
	self markBusy: aButton labelled: aLabel.
	[ [ [ aBlock value ]
		on: Error
		do: [ :err |
			err freeze.
			[ anErrorBlock value: err ] on: Error do: [ :ignored |  ] ] ]
	  ensure: [ self markIdle: aButton ] ] fork.
	^ self! !

!McOffUi class methodsFor: 'button state'!
isBusy: aButton
	^ (aButton respondsTo: #isEnabled)
		and: [ [ aButton isEnabled not ] on: Error do: [ :e | false ] ]!

markBusy: aButton labelled: aLabel
	(aButton respondsTo: #label:) ifFalse: [ ^ self ].
	[ aButton label: 'running: ' , aLabel , ' ...'; disable ]
		on: Error
		do: [ :e |  ]!

markIdle: aButton
	"Enqueued back onto the UI process: the forked process must not touch
	 the element tree directly."
	(aButton respondsTo: #enqueueTask:) ifFalse: [ ^ self ].
	[ aButton enqueueTask: (BlTaskAction new action: [
		(aButton respondsTo: #enable) ifTrue: [
			[ aButton enable ] on: Error do: [ :e |  ] ].
		(aButton respondsTo: #phlow) ifTrue: [
			[ aButton phlow fireUpdateWish ] on: Error do: [ :e |  ] ] ]) ]
		on: Error
		do: [ :e |  ]! !
```

- [ ] **Step 2: Make `McKdiStore` delegate**

In `pharo/McKdiStore.st`, replace the body of `runOffUi: aBlock from: aButton labelled: aLabel` (keeping the method's existing comment, with the two trap paragraphs replaced by a pointer) with:

```smalltalk
runOffUi: aBlock from: aButton labelled: aLabel
	"Every button here spawns a subprocess, and a subprocess run on the UI
	 process freezes the whole image.  The mechanics -- fork, mark the button,
	 release it on the UI process, ignore a second press -- live in McOffUi,
	 which documents the two traps involved.

	 What stays here is `runningLabel', which is STORE state rather than button
	 state: it drives actionLabel: across the whole toolbar, so every label says
	 which job is in flight, not just the one that was pressed.  It is cleared
	 before McOffUi releases the button, so the refresh sees an idle store."
	self isBusy ifTrue: [ ^ self ].
	runningLabel := aLabel.
	McOffUi
		run: [ [ aBlock value ] ensure: [ runningLabel := nil ] ]
		from: aButton
		labelled: aLabel
		onError: [ :err |
			McKdiTranscript record: (McKdiAnswer
				argv: #('(gt)')
				exitCode: -1
				stdout: ''
				stderr: err messageText asString
				startedAt: DateAndTime now
				duration: 0) ].
	^ self!
```

- [ ] **Step 3: Add `McOffUi.st` to the test runner**

In `test/run-pharo-tests.sh`, add before the `McLauncher.st` fileIn:

```bash
  '$MC_HOME/pharo/McOffUi.st' asFileReference fileIn.
```

- [ ] **Step 4: Verify the headless suite still passes**

Run: `cd $CLOUDSYNC/main/devsync/malleable-control && test/run-pharo-tests.sh 2>&1 | tail -25`

Expected: `PHARO_TESTS_OK`.

- [ ] **Step 5: Verify KDI's buttons still work in the live image**

This is the step that matters — `runOffUi:` is hard-won working code and the refactor must not have broken it. With GT running and a KDI store bound:

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
nix-shell --run "bin/gt-eval \"'\$PWD/pharo/McOffUi.st' asFileReference fileIn. '\$PWD/pharo/McKdiStore.st' asFileReference fileIn. 'reloaded'\""
```

Then in the open KDI inspector, press **Refresh**. Expected: the label changes to `running: Refresh ...`, the window stays responsive, and the label returns to `Refresh` when it finishes. If the label sticks at `running`, the `markIdle:` enqueue is landing on a detached element — trap 2 — and must be fixed before committing.

- [ ] **Step 6: Commit**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
git add pharo/McOffUi.st pharo/McKdiStore.st test/run-pharo-tests.sh
git commit -m "Lift the off-UI-process runner out of McKdiStore

Filing in Rich Edit's thirteen sources is the same shape of work as a
kdi subprocess, and the comment on runOffUi: is entirely a record of
what went wrong the first time. Copying it would mean two copies of
that record.

runningLabel stays in McKdiStore: it is store state driving every
toolbar label, not the state of the pressed button."
```

---

### Task 4: `McLauncherSection` — the panel, and its way into `GtHome`

**Files:**
- Modify: `pharo/McLauncher.st` (append the section class and the `GtHome` extension method)
- Modify: `pharo/mc-bootstrap.st` (file `McOffUi.st` and `McLauncher.st` in at startup)

**Interfaces:**
- Consumes: `McLauncherManifest class >> all`, `McLauncherManifest >> title / tooltip / isValid / isSatisfiable / launchExpression / icon` (Task 1); `McOffUi class >> run:from:labelled:onError:` (Task 3).
- Produces: `McLauncherSection`, and `GtHome >> mcLauncherSection` carrying `<gtHomeSection>`.

**Why not a `GtHomeMultiCardSection`:** that class collects its cards from `<gtSectionCard>` pragma methods — one method per card, fixed at compile time. These cards come from a directory.

**Why an extension method and not a `McGtPatches` patch:** every existing patch *replaces* an upstream method body, which is why `McGtPatches` holds bodies as strings and recompiles them, and why each must be re-pasted when upstream edits that method. This is purely additive, so it is an ordinary method with ordinary source.

- [ ] **Step 1: Append the section to `pharo/McLauncher.st`**

```smalltalk
"
McLauncherSection -- the launcher panel on GT's home screen.

Not a GtHomeMultiCardSection: that class collects its cards from
<gtSectionCard> pragma methods, one method per card, fixed when the class is
compiled.  These cards come from a directory, so this subclasses GtHomeSection
directly -- it is a BrStencil, and `create' is the hook -- and builds cards in
a loop with the inherited newToolCardWithTitle:icon:action:description:.

`create' re-globs launchers/ every time it runs, so a manifest added while GT
is up appears at the next render with nothing cached to invalidate.
"!

GtHomeSection subclass: #McLauncherSection
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McLauncherSection methodsFor: 'accessing'!
sectionTitle
	^ 'Malleable Control'!

defaultIcon
	^ BrGlamorousVectorIcons play!

iconFor: aManifest
	"A manifest may name a BrGlamorousVectorIcons class-side selector.  An
	 unknown name falls back rather than raising: a typo in a manifest must
	 not be able to stop the home screen rendering."
	aManifest icon ifNil: [ ^ self defaultIcon ].
	^ [ BrGlamorousVectorIcons perform: aManifest icon asSymbol ]
		on: Error
		do: [ :e | self defaultIcon ]! !

!McLauncherSection methodsFor: 'building'!
create
	| container cards manifests |
	container := self newSectionContainer.
	container addChild: (self newSectionTitle: self sectionTitle).
	cards := self newCardsContainer.
	manifests := [ McLauncherManifest all ] on: Error do: [ :e | #() ].
	manifests do: [ :each | cards addChild: (self cardFor: each) ].
	cards addChild: self reloadCard.
	container addChild: cards.
	^ container!

cardFor: aManifest
	^ self
		newToolCardWithTitle: aManifest title
		icon: (self iconFor: aManifest)
		action: [ :aButton | self launch: aManifest from: aButton ]
		description: aManifest tooltip!

reloadCard
	"Re-read launchers/ without going through the bus.  requestWidgetUpdate is
	 GtHome's own re-render, the same one McGtPatches refreshHome enqueues."
	^ self
		newToolCardWithTitle: 'Reload'
		icon: BrGlamorousVectorIcons refresh
		action: [ :aButton | self reloadFrom: aButton ]
		description: 'Re-read launchers/ and rebuild these cards'!

reloadFrom: aButton
	"Walk up to the GtHome this card is sitting in and ask it to re-render.
	 requestWidgetUpdate is GtHome's own re-render, the same one
	 McGtPatches refreshHome enqueues."
	| each |
	each := aButton.
	[ each notNil ] whileTrue: [
		(each isKindOf: GtHome) ifTrue: [
			^ [ each requestWidgetUpdate ] on: Error do: [ :e |  ] ].
		each := [ each parent ] on: Error do: [ :e | nil ] ].
	^ nil! !

!McLauncherSection methodsFor: 'launching'!
launch: aManifest from: aButton
	"Every click re-files the sources from disk, then opens.  Editing a .st
	 and pressing the button reloads it, which is what keeps this card and the
	 Emacs command the same thing rather than two things that drift.

	 A manifest that cannot run says why on the button and stops there: a
	 raise here would open a debugger over the home screen."
	aManifest isValid ifFalse: [
		^ self report: aManifest parseError on: aButton ].
	aManifest isSatisfiable ifFalse: [
		^ self
			report: 'missing: ' , (', ' join: aManifest missingFiles)
			on: aButton ].
	McOffUi
		run: [ Smalltalk compiler evaluate: aManifest launchExpression ]
		from: aButton
		labelled: aManifest title
		onError: [ :err | self report: err messageText asString on: aButton ]!

report: aMessage on: aButton
	"Say it on the button and in the Transcript.  The button is where the
	 person is looking; the Transcript is where the whole message survives
	 being truncated to a label."
	Transcript show: '[mc-launcher] ' , aMessage; cr.
	(aButton respondsTo: #enqueueTask:) ifFalse: [ ^ self ].
	[ aButton enqueueTask: (BlTaskAction new action: [
		(aButton respondsTo: #label:) ifTrue: [
			[ aButton label: aMessage ] on: Error do: [ :e |  ] ] ]) ]
		on: Error
		do: [ :e |  ]! !

"GtHome extension.  This is an ADDITION to upstream, not an override, so it is
 an ordinary method in our own package rather than a McGtPatches recompile.
 The <gtHomeSection> pragma is what GtHomeSectionsCollector looks for.

 Priority 40 puts it directly below Get Started, which is 30:
 GtPhlowUtility class >> hasHigherPriority:than: compares with <, so lower
 sorts earlier."!

!GtHome methodsFor: '*MalleableControl'!
mcLauncherSection
	<gtHomeSection>
	^ McLauncherSection new priority: 40! !
```

- [ ] **Step 2: Verify it fails before the bootstrap change**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
nix-shell --run "bin/gt-eval '(GtHome includesSelector: #mcLauncherSection) printString'"
```

Expected: `false`.

- [ ] **Step 3: Wire it into `pharo/mc-bootstrap.st`**

In the `ifNotNil:` branch, after the `McLlm.st` fileIn and **before** the `McGtPatches apply` block, add:

```smalltalk
      "The launcher panel.  Guarded on its own: a headless image has no
       GtHome, so the extension method fails to compile there -- and a home
       screen that will not build must never stop the bus connection below."
      [ (home , '/pharo/McOffUi.st') asFileReference fileIn.
        (home , '/pharo/McLauncher.st') asFileReference fileIn.
        note value: 'launcher panel loaded' ]
        on: Error
        do: [ :e | note value: 'launcher panel not loaded: ' , e messageText printString ].
```

- [ ] **Step 4: Verify the panel appears in the live image**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
nix-shell --run "bin/gt-eval \"'\$PWD/pharo/McOffUi.st' asFileReference fileIn. '\$PWD/pharo/McLauncher.st' asFileReference fileIn. (GtHome includesSelector: #mcLauncherSection) printString, ' sections=', (GtHome new collectHomeSectionStencils size) printString\""
```

Expected: `true sections=2`.

Then re-render the open window:

```bash
nix-shell --run "bin/gt-eval 'McGtPatches refreshHome'"
```

Expected on screen: a fourth panel titled **Malleable Control**, below Get Started, with six cards — KDI Explorer, Rich Edit, Corkboard, Workbench, Weather, Reload — in that order (priorities 10, 20, 30, 40, 50, then Reload last).

- [ ] **Step 5: Verify a click works and does not freeze the window**

Click **Corkboard**. Expected: the label reads `running: Corkboard ...`, the window stays responsive (scroll the home page while it loads), the corkboard window opens, and the label returns to `Corkboard`.

Then click **Rich Edit**, the thirteen-file case. Expected: same, over a longer interval.

- [ ] **Step 6: Verify a broken manifest renders rather than vanishing**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
cp launchers/weather.json /tmp/weather.json.bak
printf '{ broken' > launchers/weather.json
nix-shell --run "bin/gt-eval 'McGtPatches refreshHome'"
```

Expected: the Weather card is replaced by a card titled `weather` whose tooltip names the parse error. The other five cards still work.

Restore, and check a missing source:

```bash
cp /tmp/weather.json.bak launchers/weather.json
python3 - <<'PY'
import json, pathlib
p = pathlib.Path("launchers/weather.json")
d = json.loads(p.read_text())
d["files"] = ["pharo/NoSuchFile.st"]
p.write_text(json.dumps(d, indent=2) + "\n")
PY
nix-shell --run "bin/gt-eval 'McGtPatches refreshHome'"
```

Expected: the Weather card renders, its tooltip says `missing: pharo/NoSuchFile.st`, and clicking it puts that message on the button without opening a debugger.

Restore: `cp /tmp/weather.json.bak launchers/weather.json`

- [ ] **Step 7: Commit**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
git add pharo/McLauncher.st pharo/mc-bootstrap.st
git commit -m "Add the launcher panel to GT's home screen

GtHome collects its content from <gtHomeSection> pragma methods, so the
panel enters as one extension method in our own package. Unlike every
McGtPatches patch this adds rather than overrides, so it does not need
to carry a copy of upstream's method body.

Cards are built by re-globbing launchers/ on every render. A manifest
that will not parse renders as a card carrying its error; one whose
sources are missing says which."
```

---

### Task 5: `elisp/mc-launchers.el` — Emacs reads the same directory

**Files:**
- Create: `elisp/mc-launchers.el`
- Modify: `elisp/mc-corkboard.el`, `elisp/mc-workbench.el`, `elisp/mc-rich-edit.el`, `elisp/mc-kdi.el`, `elisp/mc-weather.el`

**Interfaces:**
- Consumes: `launchers/*.json` (Task 2); `mc-st-filein-sync` and `mc-st-eval-sync` from `elisp/mc-smalltalk.el`.
- Produces: `mc-launchers-load`, `mc-launcher-open`, `mc-launcher-open-from`, `mc-launcher-<name>-hook` (one per manifest), and a generated `mc-<name>-open` command per manifest.

**The hook exists for one reason:** `mc-weather-open` also subscribes to `gt.event.weather` so the reading reaches the minibuffer when you press Fetch Weather in GT. That subscription is meaningless to the GT card and must not be lost. Emacs-specific behaviour stays in Emacs; only the load list is shared.

- [ ] **Step 1: Write `elisp/mc-launchers.el`**

```elisp
;;; mc-launchers.el --- Generate launcher commands from launchers/*.json -*- lexical-binding: t; -*-

;; Part of malleable-control.
;;
;; A launcher is two facts: an ordered list of .st files to file in, and one
;; expression to evaluate once they are in.  Those facts used to live here, in
;; elisp, duplicated into test/run-pharo-tests.sh and invisible to GT -- which
;; is backwards, since GT is the core and Emacs is a client of the bus.
;;
;; They now live in launchers/*.json, which GT reads to build its home-screen
;; panel and the test runner reads to know what to file in.  This file is the
;; third reader: it defines one `mc-NAME-open' command per manifest.
;;
;; Adding a tool is adding one JSON file.  No elisp changes.

;;; Code:

(require 'seq)
(require 'mc-smalltalk)

(defvar mc-launchers-home
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name
                             (locate-library "mc-launchers")
                             (buffer-file-name)))))
  "Root of the malleable-control project.")

(defvar mc-launchers nil
  "Alist of (NAME . MANIFEST-PLIST), populated by `mc-launchers-load'.")

(defun mc-launchers--directory (&optional root)
  (expand-file-name "launchers" (or root mc-launchers-home)))

(defun mc-launchers--read-file (file)
  "Parse FILE as a launcher manifest.
Answers a plist with at least :name, or nil if FILE will not parse.
A broken manifest is reported and skipped rather than signalling, so one
bad file cannot stop the rest of the launchers being defined."
  (condition-case err
      (let ((json (json-parse-string
                   (with-temp-buffer
                     (insert-file-contents file)
                     (buffer-string))
                   :object-type 'plist :array-type 'list
                   :null-object nil :false-object nil)))
        (dolist (key '(:title :blurb :files :open))
          (unless (plist-member json key)
            (error "missing required key %s" key)))
        (plist-put json :name (file-name-base file)))
    (error (message "mc-launchers: %s: %s" (file-name-nondirectory file)
                    (error-message-string err))
           nil)))

(defun mc-launchers--manifests (&optional root)
  "Every readable manifest under ROOT, sorted by priority then title."
  (let* ((dir (mc-launchers--directory root))
         (files (and (file-directory-p dir)
                     (directory-files dir t "\\.json\\'")))
         (manifests (delq nil (mapcar #'mc-launchers--read-file files))))
    (sort manifests
          (lambda (a b)
            (let ((pa (or (plist-get a :priority) most-positive-fixnum))
                  (pb (or (plist-get b :priority) most-positive-fixnum)))
              (if (= pa pb)
                  (string< (plist-get a :title) (plist-get b :title))
                (< pa pb)))))))

(defun mc-launcher--hook-symbol (name)
  (intern (format "mc-launcher-%s-hook" name)))

(defun mc-launcher--ensure-hook (name)
  "Make sure `mc-launcher-NAME-hook' exists as a special variable.
Defined here rather than with `defvar' because the set of launchers is
not known until launchers/ has been read."
  (let ((symbol (mc-launcher--hook-symbol name)))
    (unless (boundp symbol)
      (set-default symbol nil))
    (put symbol 'variable-documentation
         (format "Run before the %s launcher opens.  See `mc-launcher-open'."
                 name))
    symbol))

(defun mc-launcher-open (name &optional root)
  "File in the sources for launcher NAME and evaluate its open expression.
ROOT overrides the project root for one invocation, which is how a
worktree is opened without changing the global.  Runs
`mc-launcher-NAME-hook' first, which is where Emacs-side setup that GT
knows nothing about -- a bus subscription, say -- attaches itself."
  (let* ((root (or root mc-launchers-home))
         (manifest (or (seq-find (lambda (m) (equal (plist-get m :name) name))
                                 (mc-launchers--manifests root))
                       (user-error "No launcher named %s in %s"
                                   name (mc-launchers--directory root)))))
    (run-hooks (mc-launcher--hook-symbol name))
    (dolist (file (plist-get manifest :files))
      (let ((path (expand-file-name file root)))
        (unless (file-exists-p path)
          (user-error "%s: missing source %s" name file))
        (mc-st-filein-sync path)))
    (mc-st-eval-sync (plist-get manifest :open))
    (message "%s opened in GT" (plist-get manifest :title))))

;;;###autoload
(defun mc-launcher-open-from (name root)
  "Open launcher NAME from the checkout at ROOT.
The override lasts one invocation, which is the worktree workflow in
docs/worktrees.md."
  (interactive
   (list (completing-read "Launcher: "
                          (mapcar (lambda (m) (plist-get m :name))
                                  (mc-launchers--manifests))
                          nil t)
         (read-directory-name "Project/worktree root: ")))
  (mc-launcher-open name (file-name-as-directory (expand-file-name root))))

;;;###autoload
(defun mc-launchers-load ()
  "Read launchers/ and define one `mc-NAME-open' command per manifest.
Called at load time.  Re-run it after adding a manifest."
  (interactive)
  (setq mc-launchers nil)
  (dolist (manifest (mc-launchers--manifests))
    (let* ((name (plist-get manifest :name))
           (title (plist-get manifest :title))
           (blurb (plist-get manifest :blurb))
           (command (intern (format "mc-%s-open" name))))
      (push (cons name manifest) mc-launchers)
      (mc-launcher--ensure-hook name)
      (defalias command
        (lambda ()
          (interactive)
          (mc-launcher-open name))
        (format "Load and open %s in GT.\n\n%s\n\nGenerated from launchers/%s.json."
                title blurb name))))
  (setq mc-launchers (nreverse mc-launchers))
  (when (called-interactively-p 'interactive)
    (message "mc-launchers: %d launcher(s)" (length mc-launchers)))
  mc-launchers)

(mc-launchers-load)

(provide 'mc-launchers)

;;; mc-launchers.el ends here
```

- [ ] **Step 2: Verify the commands are generated**

With the Emacs participant running:

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
nix-shell --run "bin/emacs-participant start" || true
emacsclient --eval "(progn (add-to-list 'load-path \"$PWD/elisp\") (require 'mc-launchers) (list (length mc-launchers) (fboundp 'mc-corkboard-open) (fboundp 'mc-kdi-open) (fboundp 'mc-rich-edit-open)))"
```

Expected: `(5 t t t)`.

- [ ] **Step 3: Delete the duplicated lists from the five launcher files**

`elisp/mc-corkboard.el` — delete `mc-corkboard-files`, `mc-corkboard-open` and `mc-corkboard-open-from`. The file now only requires `mc-launchers`; if nothing else is left in it, delete the file and remove it from any `require` list.

`elisp/mc-workbench.el` — same: delete `mc-workbench-files`, `mc-workbench-open`, `mc-workbench-open-from`, and the file if nothing remains.

`elisp/mc-rich-edit.el` — delete `mc-rich-edit-open` (with its thirteen-path `format` string) and `mc-rich-edit-open-from`. **Keep** `mc-rich-edit--unquote-smalltalk-string`, `mc-rich-edit-search` and `mc-rich-edit-render`, and add `(require 'mc-launchers)` at the top.

`elisp/mc-kdi.el` — delete `mc-kdi-files` and `mc-kdi-load`. **Keep** every defcustom and every other command. Since `mc-kdi-open` is now generated, and the old one also called `mc-kdi-bind`, add the binding to the hook instead:

```elisp
(require 'mc-launchers)

(add-hook 'mc-launcher-kdi-hook
          (lambda ()
            "Install the Emacs-side binding before the explorer opens.
GT's own card falls back to KDI_* via McKdiStore openLauncherSession, but
when the launcher is invoked from Emacs the defcustoms are the better
source -- they are what the operator actually set."
            (when mc-kdi-store (mc-kdi-bind))))
```

`elisp/mc-weather.el` — delete `mc-weather-open`. **Keep** `mc-weather--ensure-subscription`, `mc-weather--last` and the subscription machinery, and attach:

```elisp
(require 'mc-launchers)

(add-hook 'mc-launcher-weather-hook #'mc-weather--ensure-subscription)
```

- [ ] **Step 4: Verify every launcher still opens from Emacs**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
emacsclient --eval "(progn (require 'mc-corkboard) (mc-corkboard-open))"
emacsclient --eval "(progn (require 'mc-weather) (mc-weather-open))"
```

Expected: both windows open in GT, and `mc-weather--last` is populated after pressing Fetch Weather — proving the hook preserved the subscription.

- [ ] **Step 5: Commit**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
git add elisp/
git commit -m "Generate the Emacs launcher commands from launchers/

mc-corkboard-files, mc-workbench-files, mc-kdi-files and rich-edit's
inlined thirteen-path format string are gone; each was a second copy of
what launchers/*.json now holds.

mc-launcher-NAME-hook keeps the Emacs-only behaviour that GT knows
nothing about: weather's bus subscription, and KDI's binding from the
defcustoms the operator actually set."
```

---

### Task 6: `test/run-pharo-tests.sh` reads the manifests

**Files:**
- Modify: `test/run-pharo-tests.sh`

**Interfaces:**
- Consumes: `launchers/*.json` (Task 2), `McLauncherManifest` (Task 1).
- Produces: nothing other tasks depend on.

**Why:** the runner currently hand-maintains its own fileIn sequence — the third copy — and it has already drifted, knowing nothing about KDI's seven classes. Making it a reader turns a broken manifest into a loud test failure, which is what stops the shared file rotting.

- [ ] **Step 1: Rewrite the runner's load section**

Replace the block of per-tool `fileIn` lines (everything from `'$MC_HOME/pharo/McCache.st'` through `'$MC_HOME/pharo/McWorkbench.st'`) with a manifest-driven load. Keep the bus/infrastructure fileIns (`NatsClient.st`, `NatsClientTest.st`, `McGtPatches.st`) and the `*Test.st` fileIns, which belong to no launcher:

```bash
out="$("$GT_CLI" "$GT_IMAGE" eval "
  | suites result failed manifests launcherTests |
  '$MC_HOME/pharo/NatsClient.st' asFileReference fileIn.
  '$MC_HOME/pharo/NatsClientTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McGtPatches.st' asFileReference fileIn.
  '$MC_HOME/pharo/McOffUi.st' asFileReference fileIn.
  '$MC_HOME/pharo/McLauncher.st' asFileReference fileIn.

  \"Every tool's sources come from its manifest, in its declared order.  The
   runner used to keep its own copy of these lists and had already drifted --
   it knew nothing about KDI's seven classes.  A manifest with a bad path or a
   bad order now fails the run loudly, which is what keeps the file the panel
   and Emacs also read from rotting.\"
  manifests := McLauncherManifest
    allIn: '$MC_HOME/launchers' asFileReference
    home: '$MC_HOME'.
  manifests do: [ :each |
    each isValid ifFalse: [
      Error signal: 'launcher manifest ' , each name , ': ' , each parseError ].
    each missingFiles ifNotEmpty: [ :missing |
      Error signal: 'launcher manifest ' , each name , ' names missing sources: '
        , missing printString ].
    Smalltalk compiler evaluate: each loadExpression ].
  launcherTests := (manifests flatCollect: [ :each | each tests ]) asOrderedCollection.

  '$MC_HOME/pharo/McLauncherTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McCorkboardTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McSrtEditorTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McRelationTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McCacheTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McMarkdownTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McMarkdownSnapshotTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McMarkdownReconcilerTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McRichEditPerfTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McMarkdownLinkTest.st' asFileReference fileIn.
  '$MC_HOME/pharo/McSearchTest.st' asFileReference fileIn.
  (Smalltalk at: #McGtPatches) apply.
  failed := false.
  suites := OrderedCollection new.

  \"Suites that belong to no launcher -- the bus client, and the manifest
   reader itself -- plus the union of every launcher's declared tests.\"
  ((OrderedCollection withAll: #('NatsClientTest' 'McLauncherManifestTest'))
     addAll: launcherTests; yourself) asSet asSortedCollection do: [ :eachName |
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
      (each value isString) ifFalse: [
        each value failures do: [ :t | s << '  FAIL ' << t selector; cr ].
        each value errors do: [ :t | s << '  ERROR ' << t selector; cr ] ] ].
    s << (failed ifTrue: [ 'PHARO_TESTS_FAILED' ] ifFalse: [ 'PHARO_TESTS_OK' ]) ]
" 2>&1)" || true
```

- [ ] **Step 2: Run the suite**

Run: `cd $CLOUDSYNC/main/devsync/malleable-control && test/run-pharo-tests.sh 2>&1 | tail -30`

Expected: `PHARO_TESTS_OK`, with the same suites as before plus `McLauncherManifestTest`, and no `NO SUCH TEST CLASS` lines.

- [ ] **Step 3: Verify a broken manifest fails the run loudly**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
cp launchers/corkboard.json /tmp/corkboard.json.bak
python3 - <<'PY'
import json, pathlib
p = pathlib.Path("launchers/corkboard.json")
d = json.loads(p.read_text())
d["files"] = ["pharo/NoSuchFile.st"] + d["files"]
p.write_text(json.dumps(d, indent=2) + "\n")
PY
test/run-pharo-tests.sh 2>&1 | tail -10
cp /tmp/corkboard.json.bak launchers/corkboard.json
```

Expected: the run fails, naming `pharo/NoSuchFile.st`. This is the check with teeth — confirm it before committing.

- [ ] **Step 4: Commit**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
git add test/run-pharo-tests.sh
git commit -m "Make the test runner a manifest reader

It kept its own copy of every tool's fileIn sequence and had already
drifted: it filed in the corkboard, rich-edit, SRT and workbench sources
and knew nothing about KDI's seven classes, so those suites silently did
not exist.

Reading the manifests turns a bad path or a bad load order into a failed
run, which is what keeps the file GT and Emacs also read from rotting."
```

---

### Task 7: Integration check and documentation

**Files:**
- Modify: `test/integration.sh`
- Modify: `emacs-work.md`
- Modify: `RUN.md`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing.

- [ ] **Step 1: Add the Emacs check to `test/integration.sh`**

After the existing `emacs serves emacs.query.capabilities` check, add:

```bash
printf '\n== launchers are generated from launchers/ ==\n'
LAUNCHERS="$(mc_emacsclient --eval "(progn (require 'mc-launchers) (mc-launchers-load) (format \"%d %s %s\" (length mc-launchers) (fboundp 'mc-corkboard-open) (fboundp 'mc-kdi-open)))" 2>&1 || echo NOREPLY)"
check_contains "emacs defines a command per manifest" "$LAUNCHERS" '5 t t'
```

- [ ] **Step 2: Run the integration suite**

Run: `cd $CLOUDSYNC/main/devsync/malleable-control && nix-shell --run "test/integration.sh" 2>&1 | tail -30`

Expected: all checks pass, including the new one.

- [ ] **Step 3: Document the panel in `emacs-work.md`**

Replace the per-tool "load these files then open" bootstrapping in the Corkboard, Workbench and Rich Edit sections with a reference to the generated commands, and add a new section after **Bootstrap**:

```markdown
## Launchers

Every tool is described by one file in `launchers/`, holding its ordered
`.st` load list and the expression that opens it. Three things read that
directory: GT's home screen, which grows one button per manifest; this file's
Emacs commands, which are generated from it; and `test/run-pharo-tests.sh`,
which files in and runs from it.

Adding a tool is adding one JSON file. Nothing else changes.

```emacs-lisp
(require 'mc-launchers)
(mc-launchers-load)    ; re-read after adding a manifest
```

That defines `mc-corkboard-open`, `mc-rich-edit-open`, `mc-kdi-open`,
`mc-workbench-open` and `mc-weather-open`. Each files its sources in from disk
every time, so editing a `.st` and re-running the command reloads it.

To open one from a worktree instead of this checkout:

```emacs-lisp
(mc-launcher-open-from "rich-edit" "/path/to/worktree")
```

The same launchers are on GT's home screen, in a **Malleable Control** panel
below Get Started. The buttons there do exactly what these commands do. After
adding a manifest while GT is up:

```emacs-lisp
(mc-llm--eval "McGtPatches refreshHome")
```

or press **Reload** in the panel itself.
```

- [ ] **Step 4: Document the manifest format in `RUN.md`**

Add a section describing the schema, copying the table from the spec
(`title`, `blurb`, `files`, `open`, `tests`, `priority`, `icon`, `note`), and
noting that the launcher's name comes from the filename.

- [ ] **Step 5: Full verification**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
test/run-pharo-tests.sh 2>&1 | tail -20
nix-shell --run "test/integration.sh" 2>&1 | tail -20
```

Expected: `PHARO_TESTS_OK` and all integration checks passing.

- [ ] **Step 6: Commit**

```bash
cd $CLOUDSYNC/main/devsync/malleable-control
git add test/integration.sh emacs-work.md RUN.md
git commit -m "Document the launcher manifests

One directory, three readers: the GT home panel, the Emacs commands and
the test runner. Adding a tool is adding one JSON file."
```

---

## Notes for the executor

- **The KDI sources are untracked in this repo.** `pharo/McKdi*.st` (seven files), `elisp/mc-kdi.el` and two design documents are not in git. `launchers/kdi.json` will reference files git does not know about. Do not commit the KDI sources as part of this work unless asked; just be aware the manifest points at them.
- **`_env` and `run/` are working state**, not part of this change.
- **Live checks need GT running and the bus up.** `bin/bus-status` reports both. The `nats` CLI is only on PATH inside `nix-shell`, so every `bin/gt-eval` call goes through `nix-shell --run`.
- **If `runOffUi:` misbehaves after Task 3**, the fault is almost certainly trap 2 from the `McOffUi` comment: the completion task landing on a button element that a phlow update wish already replaced. Check whether the button is still in the element tree when `markIdle:` runs.
