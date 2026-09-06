"
McWindowTest -- window reuse, tested without a window manager.

The stubs below stand in for a tool and its BlSpace.  McWindow only ever asks
a space whether it isOpened and tells it toFront, so a stub answering those two
is a faithful stand-in -- and the suite stays headless, which is what lets it
run in the same CLI image as everything else.

tearDown clears the space out of every stub instance rather than trusting the
garbage collector, because the lookup is allInstances-based: an instance from
an earlier test that has not been collected yet would otherwise still count as
a live window.

Chunk format: load with fileIn.
"!

Object subclass: #McWindowTestSpace
	instanceVariableNames: 'opened frontCount'
	classVariableNames: ''
	package: 'MalleableControl'!

!McWindowTestSpace class methodsFor: 'instance creation'!
opened
	^ self new setOpened: true!

closed
	^ self new setOpened: false! !

!McWindowTestSpace methodsFor: 'initialization'!
setOpened: aBoolean
	opened := aBoolean.
	frontCount := 0! !

!McWindowTestSpace methodsFor: 'accessing'!
isOpened
	^ opened!

toFront
	frontCount := frontCount + 1!

frontCount
	^ frontCount! !

"A space that has been disposed and refuses every question, which is what a
 window closed underneath the image looks like."!

Object subclass: #McWindowTestDeadSpace
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McWindowTestDeadSpace methodsFor: 'accessing'!
isOpened
	^ self error: 'space disposed'! !

"A tool that can refresh itself."!

Object subclass: #McWindowTestPanel
	instanceVariableNames: 'space refreshCount'
	classVariableNames: ''
	package: 'MalleableControl'!

!McWindowTestPanel methodsFor: 'accessing'!
space: aSpace
	space := aSpace!

space
	^ space!

refreshCount
	^ refreshCount ifNil: [ 0 ]!

refreshView
	refreshCount := self refreshCount + 1! !

"A tool that cannot refresh itself without losing work, so it does not
 implement refreshView -- the editor and the terminal are the real examples."!

Object subclass: #McWindowTestPlainPanel
	instanceVariableNames: 'space'
	classVariableNames: ''
	package: 'MalleableControl'!

!McWindowTestPlainPanel methodsFor: 'accessing'!
space: aSpace
	space := aSpace! !

"A tool whose refresh raises."!

Object subclass: #McWindowTestBrokenPanel
	instanceVariableNames: 'space'
	classVariableNames: ''
	package: 'MalleableControl'!

!McWindowTestBrokenPanel methodsFor: 'accessing'!
space: aSpace
	space := aSpace!

refreshView
	^ self error: 'refresh blew up'! !

"An object with no space variable at all."!

Object subclass: #McWindowTestSpacelessPanel
	instanceVariableNames: 'other'
	classVariableNames: ''
	package: 'MalleableControl'!

TestCase subclass: #McWindowTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McWindowTest methodsFor: 'running'!
tearDown
	"See the class comment: allInstances would otherwise still see the stubs
	 built by earlier tests."
	self stubClasses do: [ :cls |
		[ cls allInstances do: [ :each |
			[ each instVarNamed: 'space' put: nil ] on: Error do: [ :e | nil ] ] ]
			on: Error
			do: [ :e | nil ] ].
	super tearDown! !

!McWindowTest methodsFor: 'helpers'!
stubClasses
	^ { McWindowTestPanel. McWindowTestPlainPanel. McWindowTestBrokenPanel }! !

!McWindowTest methodsFor: 'tests - liveness'!
testNoInstanceMeansNoLiveWindow
	self assert: (McWindow liveInstanceOf: McWindowTestPanel) isNil.
	self deny: (McWindow isShowing: McWindowTestPanel)!

testInstanceWithoutASpaceIsNotLive
	| panel |
	panel := McWindowTestPanel new.
	self assert: (McWindow liveInstanceOf: McWindowTestPanel) isNil.
	self assert: panel space isNil!

testClosedSpaceIsNotLive
	| panel |
	panel := McWindowTestPanel new space: McWindowTestSpace closed; yourself.
	self assert: (McWindow liveInstanceOf: McWindowTestPanel) isNil.
	self assert: panel refreshCount equals: 0!

testDisposedSpaceIsNotLive
	"A space that raises when asked is treated as gone, not propagated: the
	 caller opens a fresh window instead of failing the click."
	McWindowTestPanel new space: McWindowTestDeadSpace new; yourself.
	self assert: (McWindow liveInstanceOf: McWindowTestPanel) isNil!

testOpenSpaceIsLive
	| panel |
	panel := McWindowTestPanel new space: McWindowTestSpace opened; yourself.
	self assert: (McWindow liveInstanceOf: McWindowTestPanel) == panel.
	self assert: (McWindow isShowing: McWindowTestPanel)!

testObjectWithoutASpaceVariableIsIgnored
	"instVarNamed: raises for a missing variable.  The lookup must answer nil
	 rather than let that reach the caller."
	McWindowTestSpacelessPanel new.
	self assert: (McWindow liveInstanceOf: McWindowTestSpacelessPanel) isNil! !

!McWindowTest methodsFor: 'tests - fronting'!
testFrontRaisesAndAnswersTheLiveInstance
	| space panel |
	space := McWindowTestSpace opened.
	panel := McWindowTestPanel new space: space; yourself.
	self assert: (McWindow front: McWindowTestPanel) == panel.
	self assert: space frontCount equals: 1!

testFrontAnswersNilWithNoLiveWindow
	"The whole contract with a caller: nil is the signal to open one."
	self assert: (McWindow front: McWindowTestPanel) isNil!

testFrontRefreshesAToolThatCan
	| panel |
	panel := McWindowTestPanel new space: McWindowTestSpace opened; yourself.
	McWindow front: McWindowTestPanel.
	McWindow front: McWindowTestPanel.
	self assert: panel refreshCount equals: 2!

testFrontLeavesAToolThatCannotRefreshAlone
	"A tool holding unsaved work does not implement refreshView, and must be
	 foregrounded without being touched."
	| space panel |
	space := McWindowTestSpace opened.
	panel := McWindowTestPlainPanel new space: space; yourself.
	self deny: (panel respondsTo: #refreshView).
	self assert: (McWindow front: McWindowTestPlainPanel) == panel.
	self assert: space frontCount equals: 1!

testFailingRefreshStillYieldsTheWindow
	"Showing the window was the point of the click; refreshing is the part
	 that may be skipped."
	| space panel |
	space := McWindowTestSpace opened.
	panel := McWindowTestBrokenPanel new space: space; yourself.
	self assert: (McWindow front: McWindowTestBrokenPanel) == panel.
	self assert: space frontCount equals: 1! !
