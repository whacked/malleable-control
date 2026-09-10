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
	self assert: (board document source includesSubstring: 'f@800x600+123-45').
	self assert: (board document source includesSubstring: 'f@50%x25%+10%+20%')!

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

!McCorkboardTest methodsFor: 'tests - directive blocks'!
floatyEndSource
	^ String lf join: #(
		'<!!-- f@800x600+0+0 -->'
		'# Host'
		''
		'<!!-- f@40%x30%+10%+20% -->'
		'## Child'
		'child body'
		'<!!-- f@end -->'
		'after the end')! !

!McCorkboardTest methodsFor: 'tests - directive blocks'!
testACardDoesNotRepeatItsOwnDirectiveInItsText
	"The directive is the row above the body, so the body starts with the
	 section rather than with the line that configures it."
	| board child body |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	body := (board cardBodyFor: child) text asString.
	self deny: (body includesSubstring: 'f@50%x25%+10%+20%').
	self assert: (body beginsWith: 'child body')! !

!McCorkboardTest methodsFor: 'tests - directive blocks'!
testTheDirectiveRowShowsTheCardsOwnLineAndFollowsADrag
	"Verbatim, because this is the line the author wrote and would edit.  A
	 directive belonging to another card is drawn as a chip instead."
	| board child |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	self assert: (board cardRowFor: child) text asString
		equals: '<!!-- f@50%x25%+10%+20% -->'.
	(board cardViewFor: child) relocate: 88 @ 132.
	board commitDraggedCard: child
		view: (board cardViewFor: child)
		parentExtent: 800 @ 600.
	self assert: (board cardRowFor: child) text asString
		equals: '<!!-- f@50%x25%+11%+22% -->'! !

!McCorkboardTest methodsFor: 'tests - directive blocks'!
testAChildDirectiveInsideTheHostIsReplacedByABlock
	"The characters stay in the text under the replacement, so the body is
	 still a faithful view of its range -- only what is drawn changes."
	| board host text token |
	board := self floatyBoard.
	host := board document roots first.
	text := (board cardBodyFor: host) text.
	token := (board document tokensIn: host contentRange)
		detect: [ :each | each isCard ].
	self assert: (text copyFrom: token range first to: token range last) asString
		equals: token text.
	self assert: ((text attributesAt: token range first) anySatisfy: [ :each |
		each isKindOf: BrTextAdornmentDynamicAttribute ]).
	self assert: (board blockLabelFor: token) equals: 'f@50%x25%+10%+20%'! !

!McCorkboardTest methodsFor: 'tests - directive blocks'!
testAnEndDirectiveIsItsOwnKindOfBlock
	"f@end carries no geometry and only ever closes a region, so it is drawn as
	 a sentinel rather than as a card that happens to have no size."
	| board host token |
	board := McCorkboard new
		buildDocumentViewOn: self floatyEndSource markdown: true.
	host := board document roots first.
	token := (board document tokensIn: host contentRange)
		detect: [ :each | each isEnd ].
	self assert: (board blockLabelFor: token) equals: 'f@end'.
	self assert: (((board cardBodyFor: host) text attributesAt: token range first)
		anySatisfy: [ :each | each isKindOf: BrTextAdornmentDynamicAttribute ])! !

!McCorkboardTest methodsFor: 'tests - directive editing'!
type: aString intoRowOf: aDirective on: aBoard
	"Retype a row the way a caret would, through the editor's own inserter and
	 deleter, so the modification events a real edit raises are the ones the
	 board answers."
	| row |
	row := aBoard cardRowFor: aDirective.
	row editor deleter from: 0 to: row text size; delete.
	aString isEmpty ifFalse: [
		row editor inserter at: 0; string: aString; insert ].
	^ row!

testRetypingTheRowWritesTheLineIntoTheSource
	| board child |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	self type: '<!!-- f@50%x25%+30%+40% -->' intoRowOf: child on: board.
	self assert: (board document source includesSubstring: 'f@50%x25%+30%+40%').
	self deny: (board document source includesSubstring: '+10%+20%')!

testRetypingTheRowMovesTheCardWithoutADrag
	"The same live feedback a drag gives, arriving by the other route."
	| board child |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	self assert: (board cardViewFor: child) constraints position equals: 80 @ 120.
	self type: '<!!-- f@50%x25%+30%+40% -->' intoRowOf: child on: board.
	self assert: (board cardViewFor: child) constraints position equals: 240 @ 240!

testRetypingTheRowReachesTheHostsChip
	"The host's body shows that same line, so it must not still be showing the
	 one the author has just replaced."
	| board child host token |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	host := board document roots first.
	self type: '<!!-- f@50%x25%+30%+40% -->' intoRowOf: child on: board.
	token := (board document tokensIn: host contentRange)
		detect: [ :each | each isCard ].
	self assert: (board blockLabelFor: token) equals: 'f@50%x25%+30%+40%'!

testALineThatStopsBeingADirectiveLeavesTheCardWhereItIs
	"Half-typed text is still text and belongs in the source, but a card cannot
	 follow a line that no longer says where to go.  It waits for Enter."
	| board child |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	self type: 'not a directive at all' intoRowOf: child on: board.
	self assert: (board document source includesSubstring: 'not a directive at all').
	self assert: (board cardViewFor: child) constraints position equals: 80 @ 120!

testCommittingALineThatStoppedBeingADirectiveRemovesTheCard
	| board child |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	self type: 'not a directive at all' intoRowOf: child on: board.
	board commitStructure.
	self assert: (board document directiveLabelled: 'Child') isNil.
	self assert: board document roots size equals: 1!

testAnEmptiedRowCanBeTypedBackIn
	"Selecting the line and retyping it empties the range first.  A range the
	 general rule has emptied cannot grow back, so the line a card owns is
	 anchored to whatever replaced it instead."
	| board child |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	self type: '' intoRowOf: child on: board.
	self type: '<!!-- f@50%x25%+30%+40% -->' intoRowOf: child on: board.
	self assert: (board document renderRange: child range)
		equals: '<!!-- f@50%x25%+30%+40% -->'.
	self assert: (board cardViewFor: child) constraints position equals: 240 @ 240!

testRetypingTheRowKeepsTheRestOfTheDocumentIntact
	"Every other anchor moves with the line, so a shorter directive does not
	 slide the card below it off its own section."
	| board child body |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	self type: '<!!-- f@1x1 -->' intoRowOf: child on: board.
	body := (board cardBodyFor: child) text asString.
	self assert: (body beginsWith: 'child body').
	self assert: (board document source includesSubstring: '## Plain')!

testRetypingTheRowInAnotherCommentStyleIsFollowedNotRewritten
	"The comment style is the author's.  A drag after the change has to write
	 the line back the way it now reads, not the way it was parsed."
	| board host |
	board := McCorkboard new buildDocumentViewOn: (String lf join: #(
		';;; f@900x700+0+0'
		'(defun host ())')) markdown: false.
	host := board document roots first.
	self type: '    ## f@900x700+5+5' intoRowOf: host on: board.
	board
		document writeGeometryOf: host
		as: (host geometry withPosition: 7 @ 9 in: 900 @ 700).
	self assert: (board document source includesSubstring: '    ## f@900x700+7+9').
	self deny: (board document source includesSubstring: ';;;')! !

!McCorkboardTest methodsFor: 'tests - card editing'!
type: aString at: anIndex intoBodyOf: aDirective on: aBoard
	"Type into a card the way a caret would, through the editor's own inserter,
	 so the modification events a real edit raises are the ones the board
	 answers.  anIndex is a cursor position: after that many characters."
	| body |
	body := aBoard cardBodyFor: aDirective.
	body editor inserter at: anIndex; string: aString; insert.
	^ body!

testACardsTextIsEditable
	"The programmatic inserter writes through a read-only editor perfectly
	 happily, so every other test here would pass without this one."
	| board |
	board := self floatyBoard.
	self assert: (board cardBodyFor: board document roots first) isEditable.
	self assert: (board cardRowFor: board document roots first) isEditable!

testTypingIntoACardWritesThroughToTheSource
	| board child |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	self type: 'XY' at: 0 intoBodyOf: child on: board.
	self assert: (board document source includesSubstring: 'XYchild body')!

testTypingIntoACardReachesTheHostShowingTheSameText
	"The host's body covers the child's range, so the two are views onto the
	 same characters.  This is the whole point of the arrangement."
	| board child host |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	host := board document roots first.
	self type: 'XY' at: 0 intoBodyOf: child on: board.
	self assert: ((board cardBodyFor: host) text asString
		includesSubstring: 'XYchild body')!

testTypingIntoACardDoesNotDisturbTheCardBeingTypedIn
	"Handing a card back its own text would take the caret to the end of it."
	| board child before |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	before := (board cardBodyFor: child) text asString.
	self type: 'XY' at: 0 intoBodyOf: child on: board.
	self assert: (board cardBodyFor: child) text asString
		equals: 'XY' , before!

testOnlyTheSpanThatChangedIsSent
	"A card's range is most of the document.  Replacing all of it would move
	 every anchor inside it for the sake of one keystroke, so the edit is
	 narrowed to what actually differs."
	| board |
	board := self floatyBoard.
	self assert: (board replacementFrom: 'abcd' to: 'abXcd' at: 1)
		equals: { 3. 2. 'X' }.
	self assert: (board replacementFrom: 'abXcd' to: 'abcd' at: 1)
		equals: { 3. 3. '' }.
	self assert: (board replacementFrom: 'abXd' to: 'abYd' at: 1)
		equals: { 3. 3. 'Y' }.
	self assert: (board replacementFrom: '' to: 'X' at: 5)
		equals: { 5. 4. 'X' }!

testTypingIntoACardLeavesTheOtherDirectivesWhereTheyAre
	"Anchors after the edit move with it, so the child's own line is still
	 exactly where the board thinks it is."
	| board child |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	self type: 'a longer piece of text ' at: 0 intoBodyOf: board document roots first on: board.
	self assert: (board document renderRange: child range)
		equals: '<!!-- f@50%x25%+10%+20% -->'!

testTypingDoesNotRestructureTheBoardUntilTheCaretLeaves
	"A directive typed into a card's text is not a card until the parse says so,
	 and the parse waits: re-projecting would destroy the editor being typed
	 into.

	 The Plain section has no directive and so is not a card.  Writing one above
	 its heading makes it one -- but not until the caret leaves."
	| board host at |
	board := self floatyBoard.
	host := board document roots first.
	at := ((board cardBodyFor: host) text asString
		indexOfSubCollection: '## Plain') - 1.
	self type: '<!!-- f@10x10+0+0 -->' , String lf
		at: at intoBodyOf: host on: board.
	self assert: (board document directiveLabelled: 'Plain') isNil.
	self assert: board document needsReparse.
	board commitStructure.
	self assert: (board document directiveLabelled: 'Plain') notNil.
	self assert: board document roots first children size equals: 2!

testADragDoesNotMakeTheBoardStale
	"The trusted path rewrites a line that opens the same card over the same
	 region either way, so it leaves the parse standing -- otherwise clicking
	 away after a drag would rebuild the whole board for nothing."
	| board host |
	board := self floatyBoard.
	host := board document roots first.
	(board cardViewFor: host) relocate: 123 @ -45.
	board commitDraggedCard: host
		view: (board cardViewFor: host)
		parentExtent: board viewportExtent.
	self deny: board document needsReparse!

testCommittingNothingLeavesTheCardsAlone
	"Focus moves between cards constantly.  A commit with nothing to commit has
	 to be free, or every click would rebuild the board underneath itself."
	| board child card |
	board := self floatyBoard.
	child := board document directiveLabelled: 'Child'.
	card := board cardViewFor: child.
	board commitStructure.
	self assert: (board cardViewFor: child) == card! !

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

testPanFollowsThePointerAndStopsOnRelease
	"Pan is assembled from raw mouse events because Bloc raises drag events for
	 the primary button only, so this is the whole gesture under test."
	| board before |
	board := self floatyBoard.
	board canvas childrenTranslationFactor: 0 @ 0.
	before := board canvas childrenTranslationFactor.
	board beginPanAt: 100 @ 100.
	board panTo: 140 @ 130.
	self assert: board canvas childrenTranslationFactor equals: before + (40 @ 30).
	board endPan.
	board panTo: 400 @ 400.
	self assert: board canvas childrenTranslationFactor equals: before + (40 @ 30)!

testZoomKeepsTheDocumentPointUnderTheCursorBothWays
	"Zooming out used to drift to the viewport centre, because GT's translation
	 helper hard-codes a factor of 1/2 and so only ever describes a doubling."
	| board cursor before |
	board := self floatyBoard.
	board canvas childrenScaleFactor: 1.
	board canvas childrenTranslationFactor: 0 @ 0.
	cursor := 300 @ 200.
	before := board documentPointAt: cursor.
	board zoomTo: 2 towards: cursor.
	self assert: ((board documentPointAt: cursor) - before) r < 0.001.
	board zoomTo: 0.5 towards: cursor.
	self assert: ((board documentPointAt: cursor) - before) r < 0.001!

testZoomingOffCentreDoesNotDriftToTheMiddle
	| board cursor before |
	board := self floatyBoard.
	board canvas childrenScaleFactor: 1.
	board canvas childrenTranslationFactor: 37 @ -12.
	cursor := 90 @ 640.
	before := board documentPointAt: cursor.
	board zoomTo: 0.25 towards: cursor.
	self assert: ((board documentPointAt: cursor) - before) r < 0.001!

testGridLinesCoverTheViewportOnWholeCells
	| board spacing position |
	board := self floatyBoard.
	board canvas childrenScaleFactor: 1.
	board canvas childrenTranslationFactor: -137 @ -251.
	board rebuildGrid.
	spacing := board gridSpacingAt: 1.
	position := board grid constraints position.
	self assert: position x \\ spacing equals: 0.
	self assert: position y \\ spacing equals: 0.
	self assert: board grid children notEmpty!

testTheGridMovesWithThePan
	| board before |
	board := self floatyBoard.
	board canvas childrenScaleFactor: 1.
	board canvas childrenTranslationFactor: 0 @ 0.
	board rebuildGrid.
	before := board grid constraints position.
	board canvas childrenTranslationFactor: -4000 @ -4000.
	board rebuildGrid.
	self deny: board grid constraints position equals: before!

testGridSpacingWidensAsTheBoardZoomsOut
	"An unbounded grid without an unbounded number of lines: the cell doubles
	 whenever it would render too fine to read."
	| board |
	board := self floatyBoard.
	self assert: (board gridSpacingAt: 1) equals: McCorkboard gridSpacing.
	self assert: (board gridSpacingAt: 0.1) > (board gridSpacingAt: 1).
	self assert: (board gridSpacingAt: 0.1) * 0.1 >= McCorkboard minimumCellPixels!

testGridDrawsOnlyAScreenfulHoweverFarItIsZoomedOut
	"The reason the grid can be unbounded at all."
	| board |
	board := self floatyBoard.
	board canvas childrenScaleFactor: McCorkboard minimumZoom.
	board canvas childrenTranslationFactor: 0 @ 0.
	board rebuildGrid.
	self assert: board grid children size < 200! !
