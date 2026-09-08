TestCase subclass: #McCorkboardTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McCorkboardTest methodsFor: 'tests'!
testPanelKeepsSignedCoordinatesAndIndependentDraft
	| panel |
	panel := McCorkboardPanelModel id: #one x: -120 y: 45 text: 'note'.
	self assert: panel x equals: -120.
	self assert: panel y equals: 45.
	panel draftX: '1000' draftY: '-3'.
	self assert: panel isDirty.
	self assert: panel commitDraft.
	self assert: panel x equals: 1000.
	self assert: panel y equals: -3.
	self deny: panel isDirty!

testDiscardDraftDoesNotMovePanel
	| panel |
	panel := McCorkboardPanelModel id: #one x: 12 y: -8 text: 'note'.
	panel draftX: '99' draftY: '100'.
	panel discardDraft.
	self assert: panel x equals: 12.
	self assert: panel y equals: -8.
	self assert: panel draftX equals: '12'.
	self assert: panel draftY equals: '-8'!

testInvalidCoordinateCannotCommit
	| panel |
	panel := McCorkboardPanelModel id: #one x: 12 y: -8 text: 'note'.
	panel draftX: 'not a number' draftY: '10'.
	self deny: panel commitDraft.
	self assert: panel x equals: 12.
	self assert: panel y equals: -8!

testCoordinateParserRejectsPartialAndWhitespaceInput
	| panel |
	panel := McCorkboardPanelModel id: #one x: 12 y: -8 text: 'note'.
	#('12px' ' 12' '12 ' '--2' '+' '-') do: [ :invalid |
		panel draftX: invalid draftY: '3'.
		self deny: panel commitDraft.
		self assert: panel x equals: 12 ].
	panel draftX: '+12' draftY: '-3'.
	self assert: panel commitDraft.
	self assert: panel x equals: 12!

testCanvasAddressesPanelByStableId
	| board panel |
	board := McCorkboardDocument new.
	panel := McCorkboardPanelModel id: #a x: -400 y: 800 text: 'note'.
	board addPanel: panel.
	self assert: (board panelAt: #a) equals: panel.
	self assert: (board coordinateOf: #a) equals: -400 @ 800! !

!McCorkboardTest methodsFor: 'tests - controller'!
testApplyMovesOnlyWhenControllerCommitsDraft
	| board controls panel |
	board := McCorkboard new buildView.
	controls := board panelControlsFor: #noteOne.
	controls second text: '1000' asRopedText.
	controls third text: '-250' asRopedText.
	panel := controls first.
	board commitPanel: (board model panelAt: #noteOne)
		xEditor: controls second yEditor: controls third dirty: controls fourth view: panel.
	self assert: (board model coordinateOf: #noteOne) equals: 1000 @ -250.
	self assert: panel constraints position equals: 1000 @ -250!

testDragCommitUpdatesModelAndCoordinateControls
	| board controls panel model |
	board := McCorkboard new buildView.
	controls := board panelControlsFor: #noteTwo.
	panel := controls first.
	model := board model panelAt: #noteTwo.
	panel relocate: -90 @ 240.
	board commitDraggedPanel: model view: panel.
	self assert: (board model coordinateOf: #noteTwo) equals: -90 @ 240.
	self assert: controls second text asString equals: '-90'.
	self assert: controls third text asString equals: '240'!

testDiscardRestoresControllerDraftsWithoutMovingCard
	| board controls panel |
	board := McCorkboard new buildView.
	controls := board panelControlsFor: #noteOne.
	panel := controls first.
	controls second text: '700' asRopedText.
	controls third text: '800' asRopedText.
	(board model panelAt: #noteOne) draftX: '700' draftY: '800'.
	board discardAllDrafts.
	self assert: (board model coordinateOf: #noteOne) equals: 0 @ 0.
	self assert: panel constraints position equals: 0 @ 0.
	self assert: controls second text asString equals: '0'.
	self assert: controls third text asString equals: '0'!

testRefreshViewReprojectsTheDocumentWithoutDuplicatingCards
	"The launcher calls refreshView when its button finds this window already
	 open.  It must rebuild the projection from the model rather than add a
	 second copy of every card on top of the first."
	| board first |
	board := McCorkboard new buildView.
	first := board canvas children size.
	(board model panelAt: #noteOne) draftX: '700' draftY: '800'.
	board refreshView.
	self assert: board canvas children size equals: first.
	self assert: (board panelControlsFor: #noteOne) notNil.
	self assert: (board panelControlsFor: #noteTwo) notNil!

testRefreshViewKeepsCommittedCoordinatesAndDropsDrafts
	"Committed positions live in the model, so they survive.  A draft in flight
	 does not -- refreshView discards it, the same as Escape."
	| board controls |
	board := McCorkboard new buildView.
	controls := board panelControlsFor: #noteTwo.
	controls second text: '-90' asRopedText.
	controls third text: '240' asRopedText.
	(board model panelAt: #noteTwo) draftX: '-90' draftY: '240'.
	board commitPanel: (board model panelAt: #noteTwo)
		xEditor: controls second
		yEditor: controls third
		dirty: controls fourth
		view: controls first.
	(board model panelAt: #noteOne) draftX: '111' draftY: '222'.
	board refreshView.
	self assert: (board model coordinateOf: #noteTwo) equals: -90 @ 240.
	self assert: (board panelControlsFor: #noteTwo) first constraints position equals: -90 @ 240.
	self assert: (board model coordinateOf: #noteOne) equals: 0 @ 0.
	self deny: (board model panelAt: #noteOne) isDirty! !

!McCorkboardTest methodsFor: 'tests - floaty document'!
floatySource
	^ String lf join: #(
		'# Host'
		'<!!-- f@800x600+40-60 -->'
		'host body'
		''
		'## Child'
		'<!!-- f@50%x25%+10%+20% -->'
		'child body'
		''
		'## Plain'
		'plain body')!

floatyBoard
	^ McCorkboard new buildDocumentViewOn: self floatySource markdown: true!

testDocumentBoardNestsEachCardInsideItsHost
	"Bloc nesting mirrors the document, which is what makes relative placement
	 and move-together fall out of the projection rather than be maintained."
	| board host child |
	board := self floatyBoard.
	host := board document roots first.
	child := board document directiveLabelled: 'Child'.
	self assert: (board cardViewFor: child) parent == (board cardViewFor: host).
	self assert: (board cardViewFor: host) parent == board canvas!

testChildSitsAtItsPercentageOfTheHostBox
	| board host child |
	board := self floatyBoard.
	host := board document roots first.
	child := board document directiveLabelled: 'Child'.
	self assert: (board cardViewFor: host) constraints position equals: 40 @ -60.
	"10% of 800 and 20% of 600, in the host's own coordinates."
	self assert: (board cardViewFor: child) constraints position equals: 80 @ 120!

testChildPaintsAboveItsHost
	"Children are added after the body, so the paint order needs no elevation."
	| board child hostCard |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	hostCard := board cardViewFor: board document roots first.
	self assert: hostCard children last == (board cardViewFor: child)!

testSectionWithoutADirectiveIsNotProjected
	| board |
	board := self floatyBoard.
	self assert: (board document directiveLabelled: 'Plain') isNil.
	"The dot grid, plus the one root card."
	self assert: board canvas children size equals: 2!

testDraggingTheHostRewritesItsOwnDirectiveOnly
	| board host child |
	board := self floatyBoard.
	host := board document roots first.
	child := board document directiveLabelled: 'Child'.
	(board cardViewFor: host) relocate: 123 @ -45.
	board commitDraggedCard: host
		view: (board cardViewFor: host)
		parentExtent: board viewportExtent.
	self assert: (board document renderedSource includesSubstring: 'f@800x600+123-45').
	self assert: (board document renderedSource includesSubstring: 'f@50%x25%+10%+20%')!

testDraggingTheHostLeavesChildrenWhereTheyWereRelativeToIt
	"The child is a Bloc child, so the host carries it; its own coordinates --
	 and so its own directive -- must not move."
	| board host child |
	board := self floatyBoard.
	host := board document roots first.
	child := board document directiveLabelled: 'Child'.
	(board cardViewFor: host) relocate: 300 @ 200.
	board commitDraggedCard: host
		view: (board cardViewFor: host)
		parentExtent: board viewportExtent.
	self assert: (board cardViewFor: child) constraints position equals: 80 @ 120.
	self assert: child geometry asDirectiveString equals: 'f@50%x25%+10%+20%'!

testDraggingAChildRewritesItInThePercentItWasWrittenIn
	| board child |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	(board cardViewFor: child) relocate: 88 @ 132.
	board commitDraggedCard: child
		view: (board cardViewFor: child)
		parentExtent: 800 @ 600.
	self assert: child geometry asDirectiveString equals: 'f@50%x25%+11%+22%'!

testHostBodyShowsTheDirectiveADragJustRewrote
	"Each body is a view onto a range of the one document, so the host -- which
	 shows the whole of it -- has to reflect a child's new directive too."
	| board child |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	(board cardViewFor: child) relocate: 88 @ 132.
	board commitDraggedCard: child
		view: (board cardViewFor: child)
		parentExtent: 800 @ 600.
	self assert: ((board cardBodyFor: board document roots first) text asString
		includesSubstring: 'f@50%x25%+11%+22%')! !

!McCorkboardTest methodsFor: 'tests - demo'!
testTheDemoBoardLoadsItsCardsFromTheSampleFile
	"The launcher card opens this file, so a rename that leaves it dangling
	 must fail here rather than in front of whoever clicked."
	| sample |
	sample := McCorkboard sampleDocument.
	self assert: sample basename equals: 'floaty.md'.
	self assert: sample parent basename equals: 'samples'.
	self assert: sample exists!

testTheSampleFileProjectsAsANestedBoard
	| board |
	board := McCorkboard new buildDocumentView: McCorkboard sampleDocument.
	self assert: board document roots size equals: 1.
	self assert: board document roots first children size equals: 2.
	"The dot grid, plus the one root card."
	self assert: board canvas children size equals: 2! !

!McCorkboardTest methodsFor: 'tests - canvas gestures'!
testTheStockLeftDragPanIsRemoved
	"BlCanvassableElement installs a slide handler that pans on a LEFT drag.
	 The background must ignore the left button entirely, so it comes off."
	| board |
	board := self floatyBoard.
	self assert: (board canvas eventDispatcher handlers
		noneSatisfy: [ :each | each class = BlCanvassableElementSlideHandler ])!

testExactlyOneWheelHandlerSurvives
	"The stock one zooms only on a modifier and translates on a bare wheel, so
	 leaving it alongside ours would scroll and zoom on the same event."
	| board wheel |
	board := self floatyBoard.
	wheel := board canvas eventDispatcher handlers select: [ :each |
		(each respondsTo: #eventClass)
			and: [ each eventClass = BlMouseWheelEvent ] ].
	self assert: wheel size equals: 1!

testOnlyTheMiddleAndRightButtonsPan
	| board |
	board := self floatyBoard.
	self assert: (board isPanButton: BlMouseButton middle).
	self assert: (board isPanButton: BlMouseButton secondary).
	self deny: (board isPanButton: BlMouseButton primary)!

testTheGridFollowsTheViewportOnWholeCells
	"The grid covers a bounded plane and is moved to stay under the viewport.
	 Snapping to a whole cell is what hides the move: a dot keeps landing on the
	 document coordinate it would have had on an endless plane."
	| board spacing position |
	board := self floatyBoard.
	spacing := McCorkboard gridSpacing.
	board canvas childrenTranslationFactor: -137 @ -251.
	board repositionGrid.
	position := board grid constraints position.
	self assert: position x \\ spacing equals: 0.
	self assert: position y \\ spacing equals: 0!

testTheGridMovesWithThePan
	| board before |
	board := self floatyBoard.
	board canvas childrenTranslationFactor: 0 @ 0.
	board repositionGrid.
	before := board grid constraints position.
	board canvas childrenTranslationFactor: -400 @ -400.
	board repositionGrid.
	self deny: board grid constraints position equals: before! !
