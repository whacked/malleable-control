"
McCorkboard -- a deliberately small, model-first floating-panel prototype.

The canvas position is a document coordinate, never a Bloc position.  Bloc is
only a projection of McCorkboardPanelModel.  This keeps persistence, address
resolution and future pan/zoom independent from the component tree.
"!

Object subclass: #McCorkboard
	instanceVariableNames: 'model space canvas panelViews document documentFile cardViews'
	classVariableNames: ''
	package: 'MalleableControl'!

!McCorkboard class methodsFor: 'opening'!
open
	"The demo board is a document board: its cards come from floaty directives
	 in samples/floaty.md rather than from anything hard coded here, so what the
	 launcher card shows is editable in a text file.

	 The example board is the fallback rather than an error, because a missing
	 sample should not turn the launcher card into a stack trace."
	| sample |
	sample := self sampleDocument.
	^ (sample exists and: [ sample isFile ])
		ifTrue: [ self openDocument: sample ]
		ifFalse: [ self openExample ]!

openExample
	"The free-coordinate prototype: cards placed by typed x and y rather than by
	 a document.  Not on the launcher, but one expression away.

	 One window per tool: a corkboard that is already up comes forward and is
	 re-projected rather than duplicated.  See McWindow."
	^ (McWindow front: self) ifNil: [ self new openView ]!

sampleDocument
	^ self projectRoot / 'samples' / 'floaty.md'!

projectRoot
	"The project root.  Uses the McHome global set by gt-install-startup,
	 falling back to the working directory, as McRichEdit does."
	^ ((Smalltalk at: #McHome ifAbsent: [ nil ])
		ifNil: [ FileLocator workingDirectory resolve ]
		ifNotNil: [ :path | path asFileReference ]) asAbsolute!

exampleModel
	^ McCorkboardDocument new
		addPanel: (McCorkboardPanelModel id: #noteOne x: 0 y: 0 text: '# Floating note');
		addPanel: (McCorkboardPanelModel id: #noteTwo x: 420 y: -120 text: 'Signed coordinates work.');
		yourself! !

!McCorkboard methodsFor: 'opening'!
openView
	self buildView.
	space show.
	^ self!

refreshView
	"Re-project the document onto the canvas.  The model is the source of
	 truth here, so this rebuilds the panel views from it rather than
	 reloading anything: committed coordinates survive and drafts still in
	 flight are dropped, which is what Escape already does."
	canvas ifNil: [ ^ self ].
	document ifNotNil: [ ^ self projectDocument ].
	self discardAllDrafts.
	canvas removeChildren.
	panelViews := Dictionary new.
	model panels do: [ :each | self addPanelViewFor: each ].
	^ self!

buildView
	"Build without showing. Tests use this seam to exercise the controller and
	 its real Bloc children without a window-manager dependency."
	model := self class exampleModel.
	panelViews := Dictionary new.
	self buildCanvasTitled: 'Corkboard — coordinate canvas prototype'.
	"Editors consume Escape. Capture it at the canvas so discard is reliable
	 even while a numeric field has focus."
	canvas addEventFilter: (BlEventHandler on: BlKeyDownEvent do: [ :event |
		event key isEscape ifTrue: [ self discardAllDrafts. event consumed: true ] ]).
	model panels do: [ :each | self addPanelViewFor: each ].
	^ self!

buildCanvasTitled: aString
	space := BlSpace new.
	space title: aString.
	space extent: 1000 @ 700.
	canvas := BlCanvassableElement new.
	"Without this, the first layout zooms to fit the cards and document
	 coordinates cease to mean the values shown in the fields."
	canvas disableAutoScale.
	canvas constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ].
	canvas background: (Color fromHexString: '#20232a').
	space root addChild: canvas.
	^ canvas!

model
	^ model!

canvas
	^ canvas! !

!McCorkboard methodsFor: 'testing'!
panelViewFor: anId
	^ (panelViews at: anId) first!

panelControlsFor: anId
	^ panelViews at: anId! !

!McCorkboard methodsFor: 'projection'!
addPanelViewFor: aPanelModel
	| panel header title editor coordinates xEditor yEditor apply dirty |
	panel := BlElement new.
	panel layout: BlLinearLayout vertical.
	panel size: 330 @ 230.
	panel padding: (BlInsets all: 10).
	panel background: (Color fromHexString: '#f8f9fb').
	panel border: (BlBorder paint: (Color fromHexString: '#6c7280') width: 1).
	panel geometry: (BlRoundedRectangleGeometry cornerRadius: 6).
	panel constraintsDo: [ :c | c ignoreByLayout ].
	"The pull listener must be on the header, not the card. targetElement:
	 makes that header gesture relocate the card while body drags remain text
	 selection inside the editor."
	panel when: BlPullEvent do: [ :event | self commitDraggedPanel: aPanelModel view: panel ].

	header := BlElement new layout: BlLinearLayout horizontal.
	header constraintsDo: [ :c | c horizontal matchParent. c vertical exact: 30 ].
	title := BrLabel new.
	title text: (aPanelModel id asString asRopedText fontSize: 14; bold).
	title constraintsDo: [ :c | c horizontal matchParent ].
	header addChild: title.
	header addEventHandler: (BlPullHandler new
		targetElement: panel;
		allowOutOfBounds).
	"Only the header receives pull gestures: the body retains normal editor
	 selection semantics. The pull handler lives on the card, so it relocates
	 the card in canvas coordinates."
	panel addChild: header.

	editor := BrEditor new.
	editor aptitude: BrGlamorousRegularEditorAptitude new.
	editor text: aPanelModel text asRopedText.
	editor constraintsDo: [ :c | c horizontal matchParent. c vertical exact: 120 ].
	panel addChild: editor.

	coordinates := BlElement new layout: BlLinearLayout horizontal.
	coordinates constraintsDo: [ :c | c horizontal matchParent. c vertical exact: 32 ].
	xEditor := self coordinateEditorFor: aPanelModel draftX.
	yEditor := self coordinateEditorFor: aPanelModel draftY.
	dirty := BrLabel new.
	dirty constraintsDo: [ :c | c horizontal exact: 42 ].
	apply := BrButton new.
	apply label: 'Apply'.
	apply aptitude: BrGlamorousButtonWithLabelAptitude new.
	apply action: [ self commitPanel: aPanelModel xEditor: xEditor yEditor: yEditor dirty: dirty view: panel ].
	self wireCoordinateEditor: xEditor peer: yEditor model: aPanelModel dirty: dirty view: panel.
	self wireCoordinateEditor: yEditor peer: xEditor model: aPanelModel dirty: dirty view: panel.
	coordinates addChild: xEditor; addChild: yEditor; addChild: dirty; addChild: apply.
	panel addChild: coordinates.
	panelViews at: aPanelModel id put: { panel. xEditor. yEditor. dirty }.
	self updatePanel: aPanelModel view: panel xEditor: xEditor yEditor: yEditor dirty: dirty.
	canvas addChild: panel!

coordinateEditorFor: aString
	| editor |
	editor := BrEditor new.
	editor aptitude: BrGlamorousRegularEditorAptitude new.
	editor text: aString asRopedText.
	editor constraintsDo: [ :c | c horizontal exact: 62. c vertical matchParent ].
	^ editor!

wireCoordinateEditor: anEditor peer: anotherEditor model: aPanelModel dirty: dirty view: panel
	anEditor editor when: BrTextEditorModifiedEvent do: [ :event |
		self refreshDraftOf: aPanelModel xEditor: anEditor peer: anotherEditor dirty: dirty ]!

refreshDraftOf: aPanelModel xEditor: anEditor peer: anotherEditor dirty: dirty
	"Either field may have fired.  Both are read by role below; the labels do
	 not cause a position update until Apply succeeds."
	| views xEditor yEditor |
	views := panelViews at: aPanelModel id.
	xEditor := views second.
	yEditor := views third.
	aPanelModel draftX: xEditor text asString draftY: yEditor text asString.
	dirty text: ((aPanelModel isDirty ifTrue: [ 'DIRTY' ] ifFalse: [ 'saved' ]) asRopedText
		fontSize: 11;
		foreground: (aPanelModel isDirty ifTrue: [ Color orange ] ifFalse: [ Color gray ]))!

commitPanel: aPanelModel xEditor: xEditor yEditor: yEditor dirty: dirty view: panel
	aPanelModel draftX: xEditor text asString draftY: yEditor text asString.
	aPanelModel commitDraft
		ifTrue: [ self updatePanel: aPanelModel view: panel xEditor: xEditor yEditor: yEditor dirty: dirty ]
		ifFalse: [ dirty text: ('invalid' asRopedText foreground: Color red; fontSize: 12) ]!

updatePanel: aPanelModel view: panel xEditor: xEditor yEditor: yEditor dirty: dirty
	panel relocate: aPanelModel x @ aPanelModel y.
	xEditor text: aPanelModel draftX asRopedText.
	yEditor text: aPanelModel draftY asRopedText.
	dirty text: ((aPanelModel isDirty ifTrue: [ 'DIRTY' ] ifFalse: [ 'saved' ]) asRopedText fontSize: 11; foreground: (aPanelModel isDirty ifTrue: [ Color orange ] ifFalse: [ Color gray ]))! !

!McCorkboard methodsFor: 'dragging and drafts'!
commitDraggedPanel: aPanelModel view: aPanelElement
	"BlCanvassableElement keeps position in child/document coordinates even
	 when zoomed. Drag therefore shares the exact model commit path as Apply."
	aPanelModel moveToX: aPanelElement constraints position x rounded y: aPanelElement constraints position y rounded.
	self updatePanel: aPanelModel
		view: aPanelElement
		xEditor: (panelViews at: aPanelModel id) second
		yEditor: (panelViews at: aPanelModel id) third
		dirty: (panelViews at: aPanelModel id) fourth!

discardAllDrafts
	model panels do: [ :aPanelModel |
		| views |
		aPanelModel discardDraft.
		views := panelViews at: aPanelModel id.
		self updatePanel: aPanelModel view: views first xEditor: views second yEditor: views third dirty: views fourth ]! !

!McCorkboard class methodsFor: 'opening'!
openDocument: aFileReference
	"Project a floaty document onto the board.  A board that is already up
	 takes the new document rather than opening a second window."
	^ (McWindow front: self)
		ifNil: [ self new openDocumentView: aFileReference ]
		ifNotNil: [ :board | board loadDocument: aFileReference ]! !

!McCorkboard methodsFor: 'floaty document'!
openDocumentView: aFileReference
	self buildDocumentView: aFileReference.
	space show.
	^ self!

buildDocumentView: aFileReference
	"The document counterpart of #buildView, and the same test seam."
	documentFile := aFileReference asFileReference asAbsolute.
	self buildCanvasTitled: 'Corkboard — ' , documentFile basename.
	document := McFloatyDocument onFile: documentFile.
	self projectDocument.
	^ self!

buildDocumentViewOn: aString markdown: aBoolean
	"Build a document board from source text, with no file behind it."
	self buildCanvasTitled: 'Corkboard — floaty'.
	document := McFloatyDocument on: aString markdown: aBoolean.
	self projectDocument.
	^ self!

loadDocument: aFileReference
	documentFile := aFileReference asFileReference asAbsolute.
	document := McFloatyDocument onFile: documentFile.
	self projectDocument.
	^ self!

document
	^ document!

viewportExtent
	"The parent box a root card's percentages resolve against.  Space extent
	 rather than canvas extent: the canvas matches its parent, but only once a
	 layout has run, and a board built headless has not had one."
	^ space ifNil: [ 1000 @ 700 ] ifNotNil: [ :each | each extent ]!

projectDocument
	canvas removeChildren.
	cardViews := IdentityDictionary new.
	document roots do: [ :each |
		self addCardViewFor: each in: canvas parentExtent: self viewportExtent ].
	^ self!

saveDocument
	documentFile ifNil: [ ^ self ].
	documentFile ensureDelete.
	documentFile writeStreamDo: [ :stream |
		stream nextPutAll: document renderedSource ].
	^ self! !

!McCorkboard methodsFor: 'floaty projection'!
addCardViewFor: aDirective in: aParentElement parentExtent: anExtent
	"A card is a Bloc child of the card it nests in, which is what makes the
	 three things the document asks for cost nothing: a child's constraints
	 position is already relative to its host, dragging the host carries its
	 children along with their relative positions intact, and a child painted
	 after its parent is painted above it."
	| card body extent |
	extent := aDirective geometry extentIn: anExtent.
	card := BlElement new.
	card layout: BlLinearLayout vertical.
	card size: extent.
	card padding: (BlInsets all: 8).
	card background: (Color fromHexString: '#f8f9fb').
	card border: (BlBorder paint: (Color fromHexString: '#6c7280') width: 1).
	card geometry: (BlRoundedRectangleGeometry cornerRadius: 6).
	card constraintsDo: [ :c | c ignoreByLayout ].
	card relocate: (aDirective geometry positionIn: anExtent).
	card when: BlPullEvent do: [ :event |
		self commitDraggedCard: aDirective view: card parentExtent: anExtent ].
	body := self bodyFor: aDirective.
	card addChild: (self headerFor: aDirective card: card).
	card addChild: body.
	aParentElement addChild: card.
	cardViews at: aDirective put: { card. body }.
	"After the body, so every descendant paints over it."
	aDirective children do: [ :each |
		self addCardViewFor: each in: card parentExtent: extent ].
	^ card!

headerFor: aDirective card: aCardElement
	| header title |
	header := BlElement new layout: BlLinearLayout horizontal.
	header constraintsDo: [ :c | c horizontal matchParent. c vertical exact: 26 ].
	title := BrLabel new.
	title text: (aDirective label asRopedText fontSize: 13; bold).
	title constraintsDo: [ :c | c horizontal fitContent ].
	header addChild: title.
	(aDirective isRoot and: [ documentFile notNil ])
		ifTrue: [ header addChild: self saveButton ].
	"Only the header pulls, so the body keeps ordinary selection semantics."
	header addEventHandler: (BlPullHandler new
		targetElement: aCardElement;
		allowOutOfBounds).
	^ header!

bodyFor: aDirective
	| body |
	body := BrEditor new.
	body aptitude: BrGlamorousRegularEditorAptitude new.
	"Read-only for now: this iteration projects the text and owns the geometry.
	 Editing a card back into the host rope is the next piece of work."
	body beReadOnlyWithSelection.
	body text: (document renderRange: aDirective regionRange) asRopedText.
	body constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ].
	^ body!

saveButton
	| button |
	button := BrButton new.
	button label: 'Save'.
	button aptitude: BrGlamorousButtonWithLabelAptitude new.
	button constraintsDo: [ :c | c horizontal exact: 58 ].
	button action: [ self saveDocument ].
	^ button! !

!McCorkboard methodsFor: 'floaty interaction'!
commitDraggedCard: aDirective view: aCardElement parentExtent: anExtent
	"A dropped card keeps constraints position in its parent's coordinates,
	 which is exactly what the directive means, so the only conversion is back
	 into the unit the author wrote."
	aDirective geometry: (aDirective geometry
		withPosition: aCardElement constraints position
		in: anExtent).
	self refreshCardTexts.
	^ aDirective!

refreshCardTexts
	"Every body is a view onto a range of the one document, so a directive a
	 drag has just rewritten must reappear in each card whose region covers it,
	 the host included."
	cardViews keysAndValuesDo: [ :directive :views |
		views second text: (document renderRange: directive regionRange) asRopedText ]!

cardViewFor: aDirective
	^ (cardViews at: aDirective) first!

cardBodyFor: aDirective
	^ (cardViews at: aDirective) second! !
