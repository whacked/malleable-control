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
