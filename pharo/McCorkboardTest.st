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
	self assert: controls third text asString equals: '0'! !
