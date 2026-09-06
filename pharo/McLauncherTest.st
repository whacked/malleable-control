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
	"Deleted first: writeStreamDo: does not truncate, so rewriting a file
	 with shorter contents leaves the tail of the old one behind -- which
	 reads back as a manifest that is a blend of both."
	| ref |
	ref := dir / aName.
	ref ensureDelete.
	ref writeStreamDo: [ :s | s nextPutAll: aString ].
	^ ref!

touchSource: aRelativePath
	| ref |
	ref := home resolve: aRelativePath.
	ref parent ensureCreateDirectory.
	ref writeStreamDo: [ :s | s nextPutAll: '"stub"' ].
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

testLoadExpressionFilesInEverySourceInOrder
	| m expr |
	self write: 'corkboard.json' contents: self goodJson.
	m := self readOne: 'corkboard.json'.
	expr := m loadExpression.
	self assert: (expr includesSubstring: 'pharo/McCorkboardDocument.st').
	self assert: (expr includesSubstring: 'pharo/McCorkboard.st').
	self assert: (expr includesSubstring: 'fileIn').
	"Load order is the whole point: the document must be filed in first."
	self assert: (expr indexOfSubCollection: 'McCorkboardDocument.st')
		< (expr indexOfSubCollection: 'pharo/McCorkboard.st')!

testLoadAndOpenStaySeparateExpressions
	"They must be compiled separately.  Pharo resolves variable names at
	 COMPILE time, so a single `... fileIn. McCorkboard open' does not
	 compile -- McCorkboard does not exist until the fileIn has run."
	| m |
	self write: 'corkboard.json' contents: self goodJson.
	m := self readOne: 'corkboard.json'.
	self deny: (m loadExpression includesSubstring: 'McCorkboard open').
	self assert: m openExpression equals: 'McCorkboard open'.
	self deny: (m respondsTo: #launchExpression)! !

!McLauncherManifestTest methodsFor: 'tests - reload freshness'!
testLaunchingRereadsTheManifestFromDisk
	"The card captures its manifest when the panel is built.  A source added
	 to that manifest afterwards was never filed in, and nothing said so --
	 every file the stale list named still existed, so there was no error
	 anywhere; the tool just loaded an older set of sources and the new
	 classes did not exist.  That silently cost labeled code its evaluator."
	| captured fresh |
	self touchSource: 'pharo/McCorkboardDocument.st'.
	self touchSource: 'pharo/McCorkboard.st'.
	self write: 'corkboard.json' contents: self goodJson.
	captured := self readOne: 'corkboard.json'.
	self assert: captured files size equals: 2.
	"The manifest gains a source after the card was built."
	self touchSource: 'pharo/McLate.st'.
	self write: 'corkboard.json' contents: '{ "title": "Corkboard",
	     "blurb": "Coordinate-addressable canvas",
	     "files": ["pharo/McCorkboardDocument.st", "pharo/McCorkboard.st", "pharo/McLate.st"],
	     "open": "McCorkboard open",
	     "tests": ["McCorkboardTest"],
	     "priority": 30 }'.
	fresh := McLauncherSection new freshManifestFor: captured.
	self assert: fresh files size equals: 3.
	self assert: (fresh files includes: 'pharo/McLate.st').
	self
		assert: captured files size = 2
		description: 'the captured manifest is left as it was'!

testAMissingManifestFileFallsBackToTheCapturedOne
	"A card whose file has been renamed or deleted goes on doing what it did
	 before rather than breaking the home screen."
	| captured fresh |
	self touchSource: 'pharo/McCorkboardDocument.st'.
	self touchSource: 'pharo/McCorkboard.st'.
	self write: 'corkboard.json' contents: self goodJson.
	captured := self readOne: 'corkboard.json'.
	(dir / 'corkboard.json') ensureDelete.
	fresh := McLauncherSection new freshManifestFor: captured.
	self assert: fresh == captured!

testAManifestBrokenSinceTheCardWasBuiltFallsBackToTheCapturedOne
	"Half-saved JSON on disk must not disarm a card that was working.

	 Note what makes this necessary: the JSON reader is lenient enough that
	 a truncated file still parses, producing a manifest that reports itself
	 valid while carrying no files and nothing to open."
	| captured fresh |
	self touchSource: 'pharo/McCorkboardDocument.st'.
	self touchSource: 'pharo/McCorkboard.st'.
	self write: 'corkboard.json' contents: self goodJson.
	captured := self readOne: 'corkboard.json'.
	self write: 'corkboard.json' contents: '{ "title": "Corkboard",'.
	fresh := McLauncherSection new freshManifestFor: captured.
	self assert: fresh == captured.
	self assert: fresh isValid! !
