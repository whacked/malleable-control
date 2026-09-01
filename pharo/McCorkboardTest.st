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

testCanvasAddressesPanelByStableId
	| board panel |
	board := McCorkboardDocument new.
	panel := McCorkboardPanelModel id: #a x: -400 y: 800 text: 'note'.
	board addPanel: panel.
	self assert: (board panelAt: #a) equals: panel.
	self assert: (board coordinateOf: #a) equals: -400 @ 800! !
