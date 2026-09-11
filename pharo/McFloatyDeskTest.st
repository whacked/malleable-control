TestCase subclass: #McFloatyDeskTest
	instanceVariableNames: 'root'
	classVariableNames: ''
	package: 'MalleableControl'!

!McFloatyDeskTest methodsFor: 'running'!
setUp
	super setUp.
	root := (FileLocator temp / ('mc-floaty-desk-' , UUID new asString36))
		ensureCreateDirectory.
	self write: (String lf join: #(
		'<!!-- f@300x200+500+400 -->'
		'# Placed'
		''
		'Its own text says where it goes.')) to: 'placed.md'.
	self write: (String lf join: #(
		'---'
		'title: Also placed'
		'floaty: f@300x200+900+40'
		'---'
		'# Also placed')) to: 'also-placed.md'.
	self write: (String lf join: #(
		'# Loose'
		''
		'Nothing here says where this goes.')) to: 'loose.md'.
	self write: '# Loose too' to: 'loose-too.md'!

tearDown
	[ root ensureDeleteAll ] on: Error do: [ :e | nil ].
	super tearDown! !

!McFloatyDeskTest methodsFor: 'building'!
write: aString to: aName
	| file |
	file := root / aName.
	file writeStreamDo: [ :stream | stream nextPutAll: aString ].
	^ file!

desk
	^ McFloatyDesk new buildViewOn: root!

basenamesOf: aCollection
	^ (aCollection collect: [ :each | each basename ]) asArray!

sheetNamesOf: aDesk
	^ (aDesk sheets collect: [ :each | each documentFile basename ]) asArray!

break: aSheet
	"Retype the host's directive line into something that is not one, and let
	 the board answer the structural change the way Enter does."
	aSheet document writeLineOf: aSheet document host as: 'not a directive any more'.
	aSheet commitStructure.
	^ aSheet! !

!McFloatyDeskTest methodsFor: 'tests - the library beside the board'!
testTheSidebarListsWhatTheGlobMatches
	self
		assert: (self basenamesOf: self desk sidebarEntries)
		equals: #('also-placed.md' 'loose-too.md' 'loose.md' 'placed.md')!

testChangingTheGlobChangesWhatTheSidebarLists
	| desk |
	self write: 'plain' to: 'notes.txt'.
	desk := self desk.
	desk glob: '*.txt'.
	self assert: (self basenamesOf: desk sidebarEntries) equals: #('notes.txt')!

testChangingTheRootChangesWhatTheSidebarLists
	| desk |
	(root / 'deeper') ensureCreateDirectory.
	self write: '# Deep' to: 'deeper/deep.md'.
	desk := self desk.
	desk root: root / 'deeper'.
	self assert: (self basenamesOf: desk sidebarEntries) equals: #('deep.md')!

testTheSidebarKnowsWhichDocumentsPlaceThemselves
	| desk |
	desk := self desk.
	self assert: (desk sidebarEntryFor: root / 'placed.md') hasDirective.
	self deny: (desk sidebarEntryFor: root / 'loose.md') hasDirective! !

!McFloatyDeskTest methodsFor: 'tests - what is on the board'!
testOpeningTheDeskPutsEveryPlacedDocumentOnTheBoard
	self
		assert: (self sheetNamesOf: self desk) asSortedCollection asArray
		equals: #('also-placed.md' 'placed.md')!

testADocumentThatDoesNotPlaceItselfWaitsToBeAskedFor
	self deny: ((self sheetNamesOf: self desk) includes: 'loose.md')!

testClickingADocumentPutsItOnTheBoard
	| desk |
	desk := self desk.
	desk openEntry: (desk sidebarEntryFor: root / 'loose.md').
	self assert: ((self sheetNamesOf: desk) includes: 'loose.md')!

testClickingADocumentThatIsAlreadyThereDoesNotAddItTwice
	| desk |
	desk := self desk.
	desk openEntry: (desk sidebarEntryFor: root / 'placed.md').
	self assert: desk sheets size equals: 2!

testClickingADirectoryOpensNothing
	| desk |
	(root / 'deeper') ensureCreateDirectory.
	desk := self desk.
	desk openEntry: (McFloatyLibraryEntry file: root / 'deeper' in: desk library).
	self assert: desk sheets size equals: 2!

testEachDocumentGetsALayerOfItsOwn
	"Grid, then one layer per document: a sheet re-projecting itself must not
	 be able to take another document's cards off the board."
	| desk |
	desk := self desk.
	self assert: desk plane canvas children size equals: 3!

testTheDeskEditsItsCardsWithRichEdit
	self assert: (self desk sheets allSatisfy: [ :each | each isRich ])! !

!McFloatyDeskTest methodsFor: 'tests - where a document lands'!
testADocumentThatPlacesItselfKeepsThePositionItsTextGives
	| desk sheet |
	desk := self desk.
	sheet := desk sheetForFile: root / 'placed.md'.
	self
		assert: (sheet cardViewFor: sheet document host) constraints position
		equals: 500 @ 400!

emptyBoardDesk
	"A desk whose directory holds nothing that places itself, so the middle of
	 the view is free and a placement can be asserted exactly."
	(root / 'placed.md') ensureDelete.
	(root / 'also-placed.md') ensureDelete.
	^ self desk!

testADocumentThatDoesNotPlaceItselfLandsInTheMiddleOfTheView
	| desk sheet |
	desk := self emptyBoardDesk.
	desk openEntry: (desk sidebarEntryFor: root / 'loose.md').
	sheet := desk sheetForFile: root / 'loose.md'.
	self
		assert: (sheet cardViewFor: sheet document host) constraints position
		equals: 200 @ 100!

testPanningMovesWhereTheNextDocumentLands
	"The centre is the centre of what is on screen now, so panning away and
	 opening a document puts it in front of you rather than back at the start."
	| desk sheet |
	desk := self emptyBoardDesk.
	desk plane canvas childrenTranslationFactor: -300 @ -200.
	desk openEntry: (desk sidebarEntryFor: root / 'loose.md').
	sheet := desk sheetForFile: root / 'loose.md'.
	self
		assert: (sheet cardViewFor: sheet document host) constraints position
		equals: 500 @ 300!

testTheSecondLooseDocumentDoesNotLandOnTheFirst
	| desk first second |
	desk := self desk.
	desk openEntry: (desk sidebarEntryFor: root / 'loose.md').
	desk openEntry: (desk sidebarEntryFor: root / 'loose-too.md').
	first := desk sheetForFile: root / 'loose.md'.
	second := desk sheetForFile: root / 'loose-too.md'.
	self
		deny: (second cardViewFor: second document host) constraints position
		equals: (first cardViewFor: first document host) constraints position!

testADocumentLandsClearOfWhatIsAlreadyOnTheBoard
	"The middle of the view is where it wants to go; not on top of another
	 document is the condition it has to meet."
	| desk sheet loose |
	desk := self desk.
	desk openEntry: (desk sidebarEntryFor: root / 'loose.md').
	sheet := desk sheetForFile: root / 'loose.md'.
	loose := sheet rootRectangles first.
	(desk sheets reject: [ :each | each == sheet ]) do: [ :other |
		other rootRectangles do: [ :each |
			self deny: (loose intersects: each) ] ]!

testLandingSomewhereWritesNothingToTheFile
	"A document with no directive is placed for the session only.  Inventing a
	 line for it would be the board editing a file nobody asked it to edit."
	| desk before |
	desk := self desk.
	before := (root / 'loose.md') contents.
	desk openEntry: (desk sidebarEntryFor: root / 'loose.md').
	self assert: (root / 'loose.md') contents equals: before! !

!McFloatyDeskTest methodsFor: 'tests - placement arithmetic'!
testAPlacementWithNothingInTheWayIsCentredOnThePointAsked
	self
		assert: (McFloatyDesk placeExtent: 200 @ 100 near: 500 @ 400 avoiding: #())
		equals: 400 @ 350!

testAPlacementStepsAsideFromWhatIsAlreadyThere
	| taken placed |
	taken := { Rectangle origin: 400 @ 350 extent: 200 @ 100 }.
	placed := McFloatyDesk placeExtent: 200 @ 100 near: 500 @ 400 avoiding: taken.
	self deny: ((Rectangle origin: placed extent: 200 @ 100) intersects: taken first)!

testAPlacementStopsCascadingRatherThanRunningOffTheBoard
	"Somewhere overlapped is better than somewhere nobody will ever pan to."
	| taken placed |
	taken := (0 to: 200) collect: [ :index |
		Rectangle
			origin: (400 + (index * 4)) @ (350 + (index * 4))
			extent: 200 @ 100 ].
	placed := McFloatyDesk placeExtent: 200 @ 100 near: 500 @ 400 avoiding: taken.
	self assert: placed x <= (400 + (McFloatyDesk cascadeSteps * McFloatyDesk cascadeStep x))! !

!McFloatyDeskTest methodsFor: 'tests - breaking and saving'!
testBreakingAHostDirectiveLeavesTheCardWhereItIs
	"Settled behaviour, and the desk does not get to change it: the card holds
	 still and keeps its place for the session."
	| desk sheet |
	desk := self desk.
	sheet := desk sheetForFile: root / 'placed.md'.
	self break: sheet.
	self assert: desk sheets size equals: 2.
	self
		assert: (sheet cardViewFor: sheet document host) constraints position
		equals: 500 @ 400!

testSavingADocumentWhoseDirectiveIsGoneTakesItOffTheBoard
	"Save is the deliberate act.  The file no longer says where the document
	 goes, so the board stops saying it either."
	| desk sheet |
	desk := self desk.
	sheet := desk sheetForFile: root / 'placed.md'.
	self break: sheet.
	sheet saveDocument.
	self assert: (self sheetNamesOf: desk) equals: #('also-placed.md').
	self assert: desk plane canvas children size equals: 2!

testSavingADocumentThatStillPlacesItselfLeavesItOnTheBoard
	| desk sheet |
	desk := self desk.
	sheet := desk sheetForFile: root / 'placed.md'.
	sheet saveDocument.
	self assert: desk sheets size equals: 2!

testTheSidebarGoesGreyForADocumentWhoseDirectiveWasSavedAway
	| desk sheet |
	desk := self desk.
	sheet := desk sheetForFile: root / 'placed.md'.
	self assert: (desk sidebarEntryFor: root / 'placed.md') hasDirective.
	self break: sheet.
	sheet saveDocument.
	self deny: (desk sidebarEntryFor: root / 'placed.md') hasDirective!

testADocumentTakenOffTheBoardCanBeOpenedAgainByClickingIt
	| desk sheet |
	desk := self desk.
	sheet := desk sheetForFile: root / 'placed.md'.
	self break: sheet.
	sheet saveDocument.
	desk openEntry: (desk sidebarEntryFor: root / 'placed.md').
	self assert: ((self sheetNamesOf: desk) includes: 'placed.md')! !

"
McFloatyDeskAttachProbe -- a desk that records what had been built by the time
its view joined the window.  Test-only: the ordering it watches cannot be seen
any other way headless, because the error it guards against needs a windowing
host to be raised at all.
"!

McFloatyDesk subclass: #McFloatyDeskAttachProbe
	instanceVariableNames: 'sheetsWhenAttached entriesWhenAttached'
	classVariableNames: ''
	package: 'MalleableControl'!

!McFloatyDeskAttachProbe methodsFor: 'probing'!
attach: anElement to: aSpace
	sheetsWhenAttached := self sheets size.
	entriesWhenAttached := (self sidebarEntries ifNil: [ #() ]) size.
	^ super attach: anElement to: aSpace!

sheetsWhenAttached
	^ sheetsWhenAttached!

entriesWhenAttached
	^ entriesWhenAttached! !

!McFloatyDeskTest methodsFor: 'tests - building in the right order'!
testTheViewIsBuiltBeforeItJoinsTheWindow
	"Bloc refuses a write into an editor that is already in a space's scene
	 graph unless the write is made on the UI process, and the launcher builds
	 every tool on a forked one.  So the sidebar has to be filled in and the
	 documents opened while the frame is still detached -- otherwise the desk
	 dies with BrEditorWrongThreadError somewhere nobody is looking and the
	 window simply never appears.

	 Headless there is no windowing host to raise it, so what can be checked
	 is the order: by the time the frame joins the window there is nothing
	 left to write."
	| desk |
	desk := McFloatyDeskAttachProbe new buildViewOn: root.
	self assert: desk entriesWhenAttached equals: 4.
	self assert: desk sheetsWhenAttached equals: 2! !
