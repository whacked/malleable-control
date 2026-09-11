"
McFloatyLibrary -- a directory, a glob, and what is under them.

The model half of the desk's sidebar.  It knows nothing about Bloc, which is
the point: the tree that draws it is expected to be replaced -- fuzzy search,
recent files, whatever comes -- and none of that should have to move the
reading of the directory or the question the rows are coloured by.

That question has exactly one right answer already.  A document carries a
top-level floaty directive when its host is anchored: true for a directive
comment on the first non-blank line and for a `floaty:' key in Obsidian
frontmatter, false otherwise.  Asking McFloatyDocument rather than pattern
matching here is what keeps the sidebar and the board agreeing about which
files are placed by their own text.

Chunk format: load with fileIn.
"!

Object subclass: #McFloatyLibrary
	instanceVariableNames: 'root glob'
	classVariableNames: ''
	package: 'MalleableControl'!

Object subclass: #McFloatyLibraryEntry
	instanceVariableNames: 'file library directive probed'
	classVariableNames: ''
	package: 'MalleableControl'!

!McFloatyLibrary class methodsFor: 'instance creation'!
on: aFileReference
	^ self new setRoot: aFileReference glob: self defaultGlob; yourself!

default
	^ self on: self defaultRoot! !

!McFloatyLibrary class methodsFor: 'defaults'!
defaultRoot
	^ self rootFor: (self environmentAt: 'MC_FLOATY_ROOT') home: self projectRoot fullName!

defaultGlob
	^ self globFor: (self environmentAt: 'MC_FLOATY_GLOB')!

rootFor: aStringOrNil home: aHomeString
	"Where the browser starts.  The environment names it; failing that it is
	 the repo's samples directory, which is what there is to look at right
	 now.  An empty variable is not an answer -- an exported-but-unset
	 MC_FLOATY_ROOT would otherwise browse the filesystem root."
	(aStringOrNil notNil and: [ aStringOrNil trimBoth notEmpty ])
		ifTrue: [ ^ aStringOrNil trimBoth asFileReference ].
	^ aHomeString asFileReference / 'samples'!

globFor: aStringOrNil
	(aStringOrNil notNil and: [ aStringOrNil trimBoth notEmpty ])
		ifTrue: [ ^ aStringOrNil trimBoth ].
	^ '*.md'!

environmentAt: aKey
	"Never raises.  An image with no OS environment at all -- or one that
	 refuses the question -- should still open the browser."
	^ [ Smalltalk os environment at: aKey ifAbsent: [ nil ] ]
		on: Error
		do: [ :e | nil ]!

projectRoot
	"The McHome global the startup script sets, falling back to the working
	 directory the way McCorkboard and McRichEdit do."
	^ ((Smalltalk at: #McHome ifAbsent: [ nil ])
		ifNil: [ FileLocator workingDirectory resolve ]
		ifNotNil: [ :path | path asFileReference ]) asAbsolute! !

!McFloatyLibrary methodsFor: 'initialization'!
setRoot: aFileReference glob: aString
	root := aFileReference.
	glob := aString! !

!McFloatyLibrary methodsFor: 'accessing'!
root
	^ root!

root: aFileReference
	root := aFileReference!

glob
	^ glob!

glob: aString
	glob := aString! !

!McFloatyLibrary methodsFor: 'reading'!
entries
	^ self entriesIn: root!

entriesIn: aFileReference
	"Directories first, then the files the glob matches, each sorted by name.

	 A directory is listed whatever the glob says.  The glob picks documents,
	 not the places to look for them, and a *.md filter that hid every folder
	 would make a tree browser useless the moment the documents were not all
	 in one directory.

	 A directory that has gone, or that cannot be read, answers empty rather
	 than raising: a browser is pointed at a path by hand, and a bad one
	 should show nothing rather than take the window down."
	| directories files |
	(aFileReference notNil
		and: [ ([ aFileReference exists and: [ aFileReference isDirectory ] ]
			on: Error do: [ :e | false ]) ])
		ifFalse: [ ^ #() ].
	directories := [ aFileReference directories ] on: Error do: [ :e | #() ].
	files := [ aFileReference files select: [ :each | self matches: each ] ]
		on: Error do: [ :e | #() ].
	^ ((self sortedByName: directories) , (self sortedByName: files))
		collect: [ :each | McFloatyLibraryEntry file: each in: self ]!

documentEntries
	"The documents directly in the root.  What the desk opens by itself, and
	 deliberately not a walk of the whole tree: pointing the browser at a home
	 directory would otherwise try to put every markdown file on one board."
	^ (self entries select: [ :each | each isDocument ]) asArray!

matches: aFileReference
	"Pharo's own String>>match: is already a glob -- * for any run, # for one
	 character -- and it is case-insensitive, which is what a person typing
	 *.md at a directory holding README.MD means."
	^ [ glob match: aFileReference basename ] on: Error do: [ :e | false ]!

sortedByName: aCollection
	^ ((aCollection asSortedCollection: [ :a :b |
		a basename asLowercase <= b basename asLowercase ]) asArray)! !

!McFloatyLibrary methodsFor: 'printing'!
printOn: aStream
	super printOn: aStream.
	aStream nextPut: $(.
	aStream nextPutAll: (root ifNil: [ '?' ] ifNotNil: [ :each | each basename ]).
	aStream nextPutAll: ' '.
	aStream nextPutAll: (glob ifNil: [ '?' ]).
	aStream nextPut: $)! !


"
McFloatyLibraryEntry -- one row of the browser.

Whether the file carries a top-level directive is read once and remembered.
The row is redrawn on every scroll, and parsing a document per repaint would
make a directory of any size unusable; #forget is how something that changed
the file -- a save from the board -- says so.
"!

!McFloatyLibraryEntry class methodsFor: 'instance creation'!
file: aFileReference in: aLibrary
	^ self new setFile: aFileReference library: aLibrary; yourself! !

!McFloatyLibraryEntry methodsFor: 'initialization'!
setFile: aFileReference library: aLibrary
	file := aFileReference.
	library := aLibrary.
	directive := false.
	probed := false! !

!McFloatyLibraryEntry methodsFor: 'accessing'!
file
	^ file!

basename
	^ file basename!

children
	^ self isDirectory
		ifTrue: [ library entriesIn: file ]
		ifFalse: [ #() ]! !

!McFloatyLibraryEntry methodsFor: 'testing'!
isDirectory
	^ [ file isDirectory ] on: Error do: [ :e | false ]!

isDocument
	^ self isDirectory not!

hasDirective
	"Whether this file places itself.  A directory never does, and a file that
	 cannot be read is treated as one that does not: the row goes grey, which
	 says `the board will have to decide where this goes' -- and so it will."
	self isDocument ifFalse: [ ^ false ].
	probed ifFalse: [
		directive := [ (McFloatyDocument onFile: file) host isAnchored ]
			on: Error do: [ :e | false ].
		probed := true ].
	^ directive!

forget
	"Read the file again next time.  Saving a document can change the answer."
	probed := false.
	directive := false! !

!McFloatyLibraryEntry methodsFor: 'printing'!
printOn: aStream
	super printOn: aStream.
	aStream nextPut: $(.
	aStream nextPutAll: self basename.
	self isDirectory ifTrue: [ aStream nextPutAll: '/' ].
	aStream nextPut: $)! !
