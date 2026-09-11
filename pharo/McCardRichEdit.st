"
McCardRichEdit -- McRichEdit with no window around it.

A corkboard card is a BrEditor over a range of a floaty document.  McRichEdit
is a window with an editor in it.  The two meet at #attachToEditor:, which is
the seam McRichEdit already carries for exactly this: it takes an editor that
somebody else built and initialises the styling state against it, without
building any chrome.

Only two things then have to give.  #showStatus: writes into a status label
through a space, and a card has neither -- a parse that degrades would raise
inside the styler that was already degrading.  And the document file has to be
settable, because a card's text came from whichever file the sheet is showing,
and relative image paths and the trust that gates evaluation both resolve
against it.

This is the first place the two prototypes share a text surface.  The floaty
logic is untouched: the card is still a window onto a range of one source, and
McCorkboard still draws the directive lines as bands over whatever this leaves
behind.

Chunk format: load with fileIn.
"!

McRichEdit subclass: #McCardRichEdit
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McCardRichEdit class methodsFor: 'instance creation'!
on: anEditorElement file: aFileReferenceOrNil
	^ self new
		attachToEditor: anEditorElement;
		documentFile: aFileReferenceOrNil;
		yourself! !

!McCardRichEdit methodsFor: 'accessing'!
documentFile: aFileReferenceOrNil
	"Which file the card's text came from.  Nil leaves McRichEdit's own
	 fallback in place -- a board built from a string has no file, and the
	 demo document is as good a thing to resolve against as any."
	aFileReferenceOrNil ifNil: [ ^ self ].
	documentFile := aFileReferenceOrNil asFileReference! !

!McCardRichEdit methodsFor: 'feedback'!
showStatus: aString
	"There is no status bar here and no space to enqueue onto.  The one caller
	 is the styler's own error handler, so this has to say what happened
	 somewhere it can be found and then get out of the way."
	Transcript show: '[mc-card] ' , aString; cr! !
