"
McOffUi -- run work off the UI process, with the pressed button as its
progress indicator.

Lifted out of McKdiStore, where it was written the hard way.  Two traps are
encoded here, and both cost real debugging time:

  1. Work run on the UI process freezes the whole image until it finishes.
     For a corpus ingestion, or thirteen fileIns, that is not a spinner, it
     is a hang -- and the reasonable thing to do while looking at a frozen
     window is press the button again.

  2. The busy state is written STRAIGHT ONTO the pressed button, not through
     a phlow update wish.  A wish rebuilds every open pane and REPLACES the
     button element, so the completion refresh was being enqueued on a
     detached element and never ran.  The label stuck at `running' for a job
     that had already finished.

  3. The original label must be captured and put back.  McKdiStore got away
     without this because its labels are recomputed by actionLabel: when the
     phlow update wish rebuilds the toolbar.  A plain button -- a launcher
     card, say -- has nothing that would restore it, so it read
     `running: Corkboard ...' forever after one press.

A second press while the first is in flight is IGNORED rather than queued.
Two runs of the same job race, and the second one loses in a way that reads
as a refusal of the first.
"!

Object subclass: #McOffUi
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McOffUi class methodsFor: 'running'!
run: aBlock from: aButton labelled: aLabel
	^ self run: aBlock from: aButton labelled: aLabel onError: [ :err |  ]!

run: aBlock from: aButton labelled: aLabel onError: anErrorBlock
	"Fork aBlock, marking aButton busy for its duration.  anErrorBlock is
	 evaluated with the frozen error, on the forked process, before the
	 button is released."
	| previousLabel |
	(self isBusy: aButton) ifTrue: [ ^ self ].
	previousLabel := self labelOf: aButton.
	self markBusy: aButton labelled: aLabel.
	[ [ [ aBlock value ]
		on: Error
		do: [ :err |
			err freeze.
			[ anErrorBlock value: err ] on: Error do: [ :ignored |  ] ] ]
	  ensure: [ self markIdle: aButton restoring: previousLabel ] ] fork.
	^ self! !

!McOffUi class methodsFor: 'button state'!
isBusy: aButton
	^ (aButton respondsTo: #isEnabled)
		and: [ [ aButton isEnabled not ] on: Error do: [ :e | false ] ]!

labelOf: aButton
	"The label to put back when the job finishes, or nil if this button has
	 none to speak of."
	(aButton respondsTo: #label) ifFalse: [ ^ nil ].
	^ [ aButton label ] on: Error do: [ :e | nil ]!

markBusy: aButton labelled: aLabel
	(aButton respondsTo: #label:) ifFalse: [ ^ self ].
	[ aButton label: 'running: ' , aLabel , ' ...'; disable ]
		on: Error
		do: [ :e |  ]!

markIdle: aButton restoring: aPreviousLabel
	"Enqueued back onto the UI process: the forked process must not touch
	 the element tree directly.

	 The label is restored before the update wish, not after.  For a button
	 inside a phlow view the wish rebuilds it anyway and the restore is
	 redundant; for a plain button the restore is the only thing that puts
	 the label back."
	(aButton respondsTo: #enqueueTask:) ifFalse: [ ^ self ].
	[ aButton enqueueTask: (BlTaskAction new action: [
		(aPreviousLabel notNil and: [ aButton respondsTo: #label: ]) ifTrue: [
			[ aButton label: aPreviousLabel ] on: Error do: [ :e |  ] ].
		(aButton respondsTo: #enable) ifTrue: [
			[ aButton enable ] on: Error do: [ :e |  ] ].
		(aButton respondsTo: #phlow) ifTrue: [
			[ aButton phlow fireUpdateWish ] on: Error do: [ :e |  ] ] ]) ]
		on: Error
		do: [ :e |  ]! !
