"
McFloatyDesk -- a library beside the corkboard.

The corkboard projects one document.  Opening another one means opening it
instead, which makes a board a view of a file rather than a place you gather
work.  The desk keeps the plane and lets documents come and go on it: a file
browser down the left, the board across the rest, and one McCorkboard sheet
per open document.

Three rules decide where a document goes, and only the first of them is the
desk's own.  A document whose text says where it goes -- a directive comment
on its first non-blank line, or a `floaty:' key in its frontmatter -- is
placed by its text, and the desk opens all of those by itself.  A document
that says nothing is placed by the desk, in the middle of what is on screen
now and stepped clear of what is already drawn, for the session only: nothing
is written to the file, which is the rule the always-present host already
follows.  And a document that stops saying where it goes keeps its place
until it is saved, because breaking a directive mid-keystroke is not a
decision -- saving is.

Its cards are edited with McRichEdit rather than as source.  See
McCardRichEdit, and McCorkboard's rich mode.

Chunk format: load with fileIn.
"!

Object subclass: #McFloatyDesk
	instanceVariableNames: 'space library plane sheets entries tree pathEditor globEditor'
	classVariableNames: ''
	package: 'MalleableControl'!

!McFloatyDesk class methodsFor: 'opening'!
open
	"One window per tool: a desk that is already up comes forward and re-reads
	 its directory rather than opening a second one."
	^ (McWindow front: self) ifNil: [ self new openView ]!

openOn: aFileReference
	^ self new openViewOn: aFileReference! !

!McFloatyDesk class methodsFor: 'placement'!
cascadeStep
	"How far a document steps when the middle of the view is taken.  One grid
	 cell, so a cascaded document lands on the grid rather than beside it."
	^ McCorkboard gridSpacing @ McCorkboard gridSpacing!

cascadeSteps
	^ 16!

placeExtent: anExtent near: aPoint avoiding: aCollection
	"Where a document that says nothing about its position goes: centred on
	 aPoint, then stepped down and to the right until it stops covering
	 something already drawn.

	 The cascade is bounded, and when nothing in it is clear the last step is
	 the answer.  Somewhere overlapped and in sight beats somewhere nobody
	 will ever pan to, and a board can always be tidied by dragging."
	| base candidate |
	base := aPoint - (anExtent / 2).
	candidate := base.
	0 to: self cascadeSteps do: [ :index |
		candidate := base + (self cascadeStep * index).
		(aCollection anySatisfy: [ :each |
			each intersects: (Rectangle origin: candidate extent: anExtent) ])
			ifFalse: [ ^ candidate ] ].
	^ candidate! !

!McFloatyDesk class methodsFor: 'appearance'!
sidebarWidth
	^ 260!

canvasColour
	^ Color fromHexString: '#20232a'!

sidebarColour
	^ Color fromHexString: '#161a20'!

placedColour
	"A document whose own text says where it goes."
	^ Color fromHexString: '#e6edf3'!

unplacedColour
	"A document the board would have to place.  Grey, because grey is what the
	 board not knowing looks like."
	^ Color fromHexString: '#6b7480'!

directoryColour
	^ Color fromHexString: '#9fb3c8'! !

!McFloatyDesk methodsFor: 'opening'!
openView
	^ self openViewOn: McFloatyLibrary defaultRoot!

openViewOn: aFileReference
	self buildViewOn: aFileReference.
	space show.
	^ self!

buildViewOn: aFileReference
	"Build without showing.  Tests drive the desk and its real Bloc children
	 through this seam, the way McCorkboard's own buildView does."
	library := McFloatyLibrary on: aFileReference.
	sheets := OrderedCollection new.
	space := BlSpace new.
	space title: 'Floaty Desk'.
	space extent: 1200 @ 800.
	plane := McCorkboard new buildPlaneIn: space.
	space root addChild: self frameElement.
	self refreshSidebar.
	self openPlacedDocuments.
	^ self!

refreshView
	"What McWindow refreshes on the way to the front.  The directory is
	 re-read; the board is not.  A sheet may be holding text that is not on
	 disk, and re-projecting it would throw that away without asking."
	self refreshSidebar.
	^ self! !

!McFloatyDesk methodsFor: 'accessing'!
space
	^ space!

library
	^ library!

plane
	^ plane!

sheets
	^ sheets asArray!

sidebarEntries
	"The rows the browser is showing.  Held rather than re-read on every ask:
	 an entry remembers whether its file places itself, and that is the answer
	 the row is coloured by."
	^ entries!

sidebarEntryFor: aFileReference
	| wanted |
	wanted := self pathOf: aFileReference.
	^ entries
		detect: [ :each | (self pathOf: each file) = wanted ]
		ifNone: [ nil ]!

sheetForFile: aFileReference
	| wanted |
	wanted := self pathOf: aFileReference.
	^ sheets
		detect: [ :each | (self pathOf: each documentFile) = wanted ]
		ifNone: [ nil ]!

pathOf: aFileReferenceOrNil
	"Two references to the same file compare equal only once both are
	 absolute, and asking can fail on a locator with nothing behind it."
	aFileReferenceOrNil ifNil: [ ^ nil ].
	^ [ aFileReferenceOrNil asFileReference asAbsolute fullName ]
		on: Error
		do: [ :e | nil ]! !

!McFloatyDesk methodsFor: 'the library'!
root: aFileReference
	library root: aFileReference.
	self refreshSidebar.
	^ self!

glob: aString
	library glob: aString.
	self refreshSidebar.
	^ self!

refreshSidebar
	"Read the directory again and redraw the rows.  Every entry is new, so
	 whether a file places itself is asked again -- which is what makes a row
	 go grey the moment a save takes its directive away."
	entries := library entries.
	pathEditor ifNotNil: [ pathEditor text: self pathText ].
	globEditor ifNotNil: [ globEditor text: library glob asRopedText ].
	tree ifNotNil: [
		tree items: entries lazy: [ :each | each children ] ].
	^ entries!

applyTypedPathAndGlob
	"What the Open button and the Return key in either field both do.  One
	 path through, so a typed path and a typed glob cannot be applied in
	 different orders and read the directory twice."
	| typed |
	typed := globEditor text asString trimBoth.
	typed ifNotEmpty: [ library glob: typed ].
	typed := pathEditor text asString trimBoth.
	typed ifNotEmpty: [ library root: typed asFileReference ].
	^ self refreshSidebar!

goUp
	library root parent ifNotNil: [ :each | library root: each ].
	^ self refreshSidebar! !

!McFloatyDesk methodsFor: 'the board'!
openPlacedDocuments
	"Every document in the root directory whose own text says where it goes.

	 The root only, and deliberately not a walk of the tree: a desk pointed at
	 a home directory would otherwise try to put every markdown file under it
	 on one board.  What is deeper is one click away in the browser."
	entries do: [ :each |
		(each isDocument and: [ each hasDirective ]) ifTrue: [ self openEntry: each ] ].
	^ self!

openEntry: anEntryOrNil
	"A row clicked.  A directory is somewhere to look rather than something to
	 open, so clicking one opens nothing -- the tree expands it."
	anEntryOrNil ifNil: [ ^ nil ].
	anEntryOrNil isDocument ifFalse: [ ^ nil ].
	^ self openFile: anEntryOrNil file!

openFile: aFileReference
	"Put a document on the plane, or answer the sheet already showing it.

	 What is already drawn is read before the new sheet exists, so a document
	 cannot be stepped aside from itself."
	| existing sheet taken |
	existing := self sheetForFile: aFileReference.
	existing ifNotNil: [ ^ existing ].
	taken := self occupiedRectangles.
	sheet := McCorkboard new
		beRich;
		buildSheetOnFile: aFileReference
		in: plane addLayer
		space: space.
	sheet afterSaveDo: [ :each | self sheetSaved: each ].
	sheets add: sheet.
	self place: sheet avoiding: taken.
	^ sheet!

closeSheet: aSheet
	"Take a document off the plane: its cards go with the layer they are on."
	(sheets includes: aSheet) ifFalse: [ ^ nil ].
	sheets remove: aSheet.
	[ plane canvas removeChild: aSheet canvas ] on: Error do: [ :e | nil ].
	^ aSheet!

sheetSaved: aSheet
	"Save is the deliberate act, so it is where the desk reconsiders.  The
	 file has been written either way; what changes is whether it still says
	 where it goes.  A document that has stopped saying so is no longer a
	 document this board is showing -- its row goes grey and its card comes
	 off -- and clicking that row puts it back, placed by the desk."
	self refreshSidebar.
	aSheet document host isAnchored ifTrue: [ ^ aSheet ].
	^ self closeSheet: aSheet!

place: aSheet avoiding: aCollection
	"A document whose text does not place it is placed here, for the session.
	 Nothing is written: the geometry goes to the host, which remembers it
	 across a reparse and has no line in the file to rewrite."
	| host geometry extent |
	host := aSheet document host.
	host isAnchored ifTrue: [ ^ aSheet ].
	geometry := McFloatyDocument defaultHostGeometry.
	extent := aSheet cardParentExtentFor: host.
	aSheet document
		writeGeometryOf: host
		as: (geometry
			withPosition: (self class
				placeExtent: (geometry extentIn: extent)
				near: self centreOfView
				avoiding: aCollection)
			in: extent).
	aSheet placeCardFor: host.
	^ aSheet!

centreOfView
	"The document point in the middle of the board as it is panned now, so a
	 document opened after panning arrives in front of you."
	^ plane documentPointAt: plane viewportExtent / 2!

occupiedRectangles
	^ (sheets flatCollect: [ :each | each rootRectangles ]) asArray! !

!McFloatyDesk methodsFor: 'building'!
frameElement
	| frame |
	frame := BlElement new.
	frame layout: BlLinearLayout horizontal.
	frame constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ].
	frame background: self class canvasColour.
	frame addChild: self sidebarElement.
	frame addChild: plane canvas.
	^ frame!

sidebarElement
	| sidebar |
	sidebar := BlElement new.
	sidebar layout: BlLinearLayout vertical.
	sidebar constraintsDo: [ :c |
		c horizontal exact: self class sidebarWidth.
		c vertical matchParent ].
	sidebar background: self class sidebarColour.
	sidebar padding: (BlInsets all: 8).
	pathEditor := self fieldOn: self pathText.
	globEditor := self fieldOn: library glob asRopedText.
	sidebar addChild: (self labelled: 'Path').
	sidebar addChild: pathEditor.
	sidebar addChild: self buttonRow.
	sidebar addChild: (self labelled: 'Filter').
	sidebar addChild: globEditor.
	sidebar addChild: self treeElement.
	^ sidebar!

buttonRow
	| row |
	row := BlElement new.
	row layout: BlLinearLayout horizontal.
	row constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ].
	row margin: (BlInsets bottom: 6).
	row addChild: (self buttonLabelled: 'Open' action: [ self applyTypedPathAndGlob ]).
	row addChild: (self buttonLabelled: 'Up' action: [ self goUp ]).
	^ row!

buttonLabelled: aString action: aBlock
	| button |
	button := BrButton new.
	button aptitude: BrGlamorousButtonWithLabelAptitude new.
	button label: aString.
	button beSmallSize.
	button margin: (BlInsets right: 6).
	button action: aBlock.
	^ button!

labelled: aString
	| label |
	label := BrLabel new.
	label aptitude: BrGlamorousLabelAptitude new.
	label text: (aString asRopedText
		fontSize: 10;
		foreground: self class unplacedColour).
	label constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ].
	^ label!

fieldOn: aText
	"One line, typed into, applied on Return.  The same shape as a card's
	 directive row, and for the same reason: it is a line of text that means
	 something, and the way to change it is to retype it."
	| field |
	field := BrEditor new.
	field aptitude: BrGlamorousCodeEditorAptitude new.
	field text: aText.
	field padding: (BlInsets top: 2 left: 6 bottom: 2 right: 6).
	field background: (Color fromHexString: '#22272e').
	field border: (BlBorder paint: (Color fromHexString: '#3a424d') width: 1).
	field geometry: (BlRoundedRectangleGeometry cornerRadius: 3).
	field margin: (BlInsets bottom: 6).
	field constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ].
	field addEventFilter: (BlEventHandler on: BlKeyDownEvent do: [ :event |
		event key isReturnOrEnter ifTrue: [
			event consumed: true.
			self applyTypedPathAndGlob ] ]).
	^ field!

pathText
	^ (library root fullName) asRopedText
		fontSize: 11;
		foreground: self class placedColour!

treeElement
	"BrSimpleTree, because the browser is a directory and a directory is a
	 tree.  The row is deliberately thin -- a label and a click -- so that the
	 fuzzy search and the rest that are coming replace the widget without
	 touching what a row means."
	tree := BrSimpleTree new.
	tree constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ].
	tree nodeStencil: [ self rowElement ].
	tree nodeDataBinder: [ :aNodeElement :anEntry |
		"The entry goes on the element rather than into the handler: rows are
		 recycled as the tree scrolls, and a handler added per binding would
		 stack up one per row the element had ever shown."
		aNodeElement userData at: #entry put: anEntry.
		aNodeElement text: (self sidebarTextFor: anEntry) ].
	tree items: #() lazy: [ :each | each children ].
	^ tree!

rowElement
	| label |
	label := BrLabel new.
	label aptitude: BrGlamorousLabelAptitude new.
	label addEventHandler: (BlEventHandler on: BlClickEvent do: [ :event |
		self openEntry: (label userData at: #entry ifAbsent: [ nil ]) ]).
	^ label!

sidebarTextFor: anEntry
	"Grey says the board would have to decide where this document goes; the
	 foreground colour says its own text already has."
	^ anEntry basename asRopedText
		fontSize: 12;
		foreground: (anEntry isDirectory
			ifTrue: [ self class directoryColour ]
			ifFalse: [ anEntry hasDirective
				ifTrue: [ self class placedColour ]
				ifFalse: [ self class unplacedColour ] ])! !

!McFloatyDesk methodsFor: 'printing'!
printOn: aStream
	super printOn: aStream.
	aStream nextPut: $(.
	aStream nextPutAll: (library
		ifNil: [ '?' ]
		ifNotNil: [ :each | each root basename ]).
	aStream nextPutAll: ' '.
	aStream print: (sheets ifNil: [ 0 ] ifNotNil: [ :each | each size ]).
	aStream nextPutAll: ' open)'! !
