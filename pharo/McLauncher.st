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
	| found |
	(aDirectory notNil and: [ aDirectory exists ]) ifFalse: [ ^ #() ].
	found := [ aDirectory files select: [ :each | each extension = 'json' ] ]
		on: Error
		do: [ :e | ^ #() ].
	^ ((found collect: [ :each | self fromFile: each home: aHomeString ])
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
			s nextPutAll: ''' asFileReference fileIn. ' ] ]! !

"There is deliberately no `launchExpression' concatenating loadExpression and
 openExpression.  Pharo resolves variable names when it COMPILES an
 expression, so `... fileIn. McCorkboard open' fails to compile: McCorkboard
 does not exist yet at compile time, and the fileIn that would create it has
 not run.  The error surfaces as an Undeclared variable from inside whatever
 was evaluating it.

 The two halves must therefore be compiled separately, the second only after
 the first has run.  mc-launchers.el does the same thing for the same reason,
 which is also why the old hand-written elisp said
 `(Smalltalk at: #McRichEdit) open' rather than naming the class directly."!

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
	^ BrGlamorousVectorIcons play asElement!

iconFor: aManifest
	"A manifest may name a BrGlamorousVectorIcons class-side selector.  An
	 unknown name falls back rather than raising: a typo in a manifest must
	 not be able to stop the home screen rendering.

	 asElement is not optional.  BrGlamorousVectorIcons answers a stencil,
	 and newToolCardWithTitle:icon:action:description: sends margin: to what
	 it is given, which a stencil does not understand."
	aManifest icon ifNil: [ ^ self defaultIcon ].
	^ [ (BrGlamorousVectorIcons perform: aManifest icon asSymbol) asElement ]
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
	"Re-read launchers/ without going through the bus."
	^ self
		newToolCardWithTitle: 'Reload'
		icon: BrGlamorousVectorIcons refresh asElement
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
	"Every click re-reads the manifest and re-files the sources from disk,
	 then opens.  Editing a .st and pressing the button reloads it, which is
	 what keeps this card and the Emacs command the same thing rather than
	 two things that drift.

	 Re-reading the MANIFEST matters as much as re-reading the sources, and
	 it used not to happen: the card captured its manifest when the panel was
	 built, so a source added to a manifest afterwards was never filed in.
	 The tool loaded its older set of files and the new classes simply did
	 not exist -- with no error anywhere, because every file the stale list
	 named was still there.  That silently cost labeled code its whole
	 evaluator until the panel was rebuilt.

	 A manifest that cannot run says why on the button and stops there: a
	 raise here would open a debugger over the home screen."
	| manifest |
	manifest := self freshManifestFor: aManifest.
	manifest isValid ifFalse: [
		^ self report: manifest parseError on: aButton ].
	manifest isSatisfiable ifFalse: [
		^ self
			report: 'missing: ' , (', ' join: manifest missingFiles)
			on: aButton ].
	self launch: manifest from: aButton showing: (self titleLabelUnder: aButton)!

freshManifestFor: aManifest
	"The manifest as it is on disk now, or the captured one when it cannot be
	 re-read.

	 Its own file, by home and name, rather than a scan of the directory:
	 re-reading one file is what a click needs, and it keeps a card working
	 when it came from somewhere other than the default launchers directory.

	 Falling back rather than failing at every step -- a card whose file has
	 been renamed or deleted should go on doing what it did before, not
	 break the home screen."
	| file fresh |
	file := [ aManifest home asFileReference / 'launchers' / (aManifest name , '.json') ]
		on: Error
		do: [ :e | nil ].
	file ifNil: [ ^ aManifest ].
	([ file exists ] on: Error do: [ :e | false ]) ifFalse: [ ^ aManifest ].
	fresh := [ McLauncherManifest fromFile: file home: aManifest home ]
		on: Error
		do: [ :e | nil ].
	"Valid is not enough.  The JSON reader is lenient, so a half-saved file
	 -- one write into a manifest, caught mid-flight -- parses as a manifest
	 with no files and nothing to open, and that reads as valid.  Loading it
	 would file nothing in and open nothing, silently.  A fresh manifest has
	 to actually carry a tool before it is allowed to replace the one that
	 was working."
	^ (fresh notNil
		and: [ fresh isValid
		and: [ fresh files notEmpty
		and: [ fresh openExpression notNil
		and: [ fresh openExpression trimBoth notEmpty ] ] ] ])
		ifTrue: [ fresh ]
		ifFalse: [ aManifest ]!

launch: aManifest from: aButton showing: aTitleLabel
	"aTitleLabel is the card's visible caption.  It has to be driven
	 separately from McOffUi's busy label, because a tool card puts its
	 DESCRIPTION in the button's label -- that is what the tooltip aptitude
	 renders -- and its title in a child BrLabel.  Marking only the button
	 would put `running: Rich Edit ...' in a tooltip nobody is hovering over,
	 leaving a thirteen-file load with no visible progress at all."
	| previousText |
	previousText := aTitleLabel
		ifNil: [ nil ]
		ifNotNil: [ :l | [ l text ] on: Error do: [ :e | nil ] ].
	aTitleLabel ifNotNil: [ :l |
		[ l text: 'loading...' ] on: Error do: [ :e |  ] ].
	McOffUi
		run: [ [ Smalltalk compiler evaluate: aManifest loadExpression.
			"Compiled separately, and only now: the open expression names a
			 class the fileIn above has just created.  Compiling both at once
			 would fail to resolve it."
			Smalltalk compiler evaluate: aManifest openExpression ]
			ensure: [ self restore: aTitleLabel to: previousText on: aButton ] ]
		from: aButton
		labelled: aManifest title
		onError: [ :err | self report: err messageText asString on: aButton ]!

titleLabelUnder: anElement
	"The first BrLabel under the card -- its visible caption."
	| found visit |
	found := nil.
	visit := nil.
	visit := [ :el |
		(found isNil and: [ el isKindOf: BrLabel ]) ifTrue: [ found := el ].
		found isNil ifTrue: [
			[ el children do: [ :c | visit value: c ] ] on: Error do: [ :e |  ] ] ].
	visit value: anElement.
	^ found!

restore: aTitleLabel to: aText on: aButton
	"Enqueued: this runs on the forked process, which must not touch the
	 element tree directly."
	(aTitleLabel isNil or: [ aText isNil ]) ifTrue: [ ^ self ].
	(aButton respondsTo: #enqueueTask:) ifFalse: [ ^ self ].
	[ aButton enqueueTask: (BlTaskAction new action: [
		[ aTitleLabel text: aText ] on: Error do: [ :e |  ] ]) ]
		on: Error
		do: [ :e |  ]!

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
