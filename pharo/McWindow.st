"
McWindow -- one live window per tool.

Every launcher answered a click with `self new openView', which builds a fresh
BlSpace whether or not the tool already had one.  Clicking a card twice
therefore stacked windows -- and where another GT window holds native focus the
new space opens behind it, so the second click looked like it did nothing at
all.  McRichEdit already carried a private fix for exactly that symptom; this
is that fix, generalized, so a tool gets it by asking rather than by
reimplementing it.

A live window is found through the tool's own instances: every panel here keeps
its BlSpace in an instance variable named `space', so a live window is an
instance whose space is open.  Nothing is registered and nothing is cached,
which matters because the launcher re-files sources from disk before every
open -- a registry would go stale across a class redefinition at exactly the
moment the panel is being used to reload code.

`refreshView' is the opt-in half.  A tool that can bring itself up to date
without destroying work implements it and gets refreshed on the way to the
front; a tool that cannot -- an editor holding unsaved text, a terminal holding
a live session -- simply does not implement it, and is only foregrounded.  The
default is therefore the safe one, and adding a tool cannot silently start
discarding a user's work.

Chunk format: load with fileIn.
"!

Object subclass: #McWindow
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McWindow class methodsFor: 'querying'!
spaceOf: anObject
	"The open BlSpace anObject is showing in, or nil.

	 Defensive at every step: an instance caught mid-construction has no
	 space yet, an instance migrated by a class redefinition may no longer
	 have the variable at all, and a space disposed by the window manager can
	 refuse the question."
	| space |
	space := [ anObject instVarNamed: 'space' ] on: Error do: [ :e | nil ].
	space ifNil: [ ^ nil ].
	^ ([ space isOpened ] on: Error do: [ :e | false ])
		ifTrue: [ space ]
		ifFalse: [ nil ]!

liveInstanceOf: aClass
	"The instance of aClass with an open window, or nil.  allInstances rather
	 than a registry: see the class comment."
	^ [ aClass allInstances
		detect: [ :each | (self spaceOf: each) notNil ]
		ifNone: [ nil ] ]
		on: Error
		do: [ :e | nil ]!

isShowing: aClass
	^ (self liveInstanceOf: aClass) notNil! !

!McWindow class methodsFor: 'opening'!
front: aClass
	"Foreground aClass's live window, refresh it if it can be refreshed, and
	 answer the instance -- or nil when there is no live window, which is the
	 caller's signal to open one:

		open
			^ (McWindow front: self) ifNil: [ self new openView ]"
	| existing |
	existing := self liveInstanceOf: aClass.
	existing ifNil: [ ^ nil ].
	self foreground: existing.
	self refresh: existing.
	^ existing!

foreground: anObject
	"Raise anObject's window.  Answers anObject either way: a window manager
	 that refuses to reorder is not a reason to fail the click."
	(self spaceOf: anObject) ifNotNil: [ :space |
		[ space toFront ] on: Error do: [ :e |  ] ].
	^ anObject!

refresh: anObject
	"Send refreshView where it is implemented.  A failure here must not cost
	 the caller its window: the click asked to see the window, and refreshing
	 is the part that can be skipped."
	(anObject respondsTo: #refreshView) ifFalse: [ ^ anObject ].
	[ anObject refreshView ] on: Error do: [ :e |  ].
	^ anObject! !
