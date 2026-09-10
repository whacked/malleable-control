"
McCorkboard -- a deliberately small, model-first floating-panel prototype.

The canvas position is a document coordinate, never a Bloc position.  Bloc is
only a projection of McCorkboardPanelModel.  This keeps persistence, address
resolution and future pan/zoom independent from the component tree.
"!

Object subclass: #McCorkboard
	instanceVariableNames: 'model space canvas panelViews document documentFile cardViews grid gridKey panOrigin panStart settleGeneration caretPosition'
	classVariableNames: 'SettleMilliseconds'
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
	self clearCanvas.
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
	self installCanvasInteractions.
	self clearCanvas.
	space root addChild: canvas.
	^ canvas!

clearCanvas
	"Every re-projection starts from an empty plane carrying only its grid."
	canvas removeChildren.
	grid := self gridElement.
	canvas addChild: grid.
	gridKey := nil.
	self rebuildGrid!

gridElement
	"A bare container.  The grid is a child of the canvas rather than its
	 background so that it pans and zooms with the cards; a background would sit
	 still and say nothing about where the origin went."
	| element |
	element := BlElement new.
	element constraintsDo: [ :c | c ignoreByLayout ].
	^ element!

documentPointAt: aLocalPoint
	"The document coordinate currently under a point of the viewport.  The
	 children transformation is origin 0@0, then translate, then scale, so this
	 inverts it directly."
	^ (aLocalPoint - canvas childrenTranslationFactor) / canvas childrenScaleFactor!

gridSpacingAt: aScale
	"Widen the cell as the board shrinks, so the grid stays a cue rather than a
	 fog of lines.  This is what lets the grid be unbounded without ever drawing
	 more than a screenful of it."
	| spacing |
	spacing := self class gridSpacing.
	[ spacing * aScale < self class minimumCellPixels ]
		whileTrue: [ spacing := spacing * 2 ].
	^ spacing!

rebuildGrid
	"Draw only the lines the viewport can actually see.

	 Lines rather than dots, and rebuilt rather than tiled.  Bloc has no
	 repeating paint to tile with: BlImagePatternPaint paints its form once at
	 the element's origin, and #matchExtent: is a stub that says as much.  The
	 repeat Cairo does have is not reachable from any Bloc or Sparta API.
	 Redrawing a screenful is about fifty elements, which is cheaper than
	 carrying an image big enough to pretend the plane is endless.

	 The rebuild is skipped unless the covered region or the spacing actually
	 changed, so a drag costs one rebuild per cell crossed rather than one per
	 mouse move."
	| scale extent spacing topLeft bottomRight first last key thickness |
	(grid isNil or: [ canvas isNil ]) ifTrue: [ ^ self ].
	scale := canvas childrenScaleFactor.
	(scale isNil or: [ scale <= 0 ]) ifTrue: [ ^ self ].
	"Canvas extent is known only once a layout has run; before that -- a board
	 built headless, or the first projection -- fall back to the space."
	extent := canvas extent.
	(extent x = 0 or: [ extent y = 0 ]) ifTrue: [ extent := self viewportExtent ].
	(extent x = 0 or: [ extent y = 0 ]) ifTrue: [ ^ self ].
	spacing := self gridSpacingAt: scale.
	topLeft := self documentPointAt: 0 @ 0.
	bottomRight := self documentPointAt: extent.
	first := (((topLeft x / spacing) floor - 1) * spacing)
		@ (((topLeft y / spacing) floor - 1) * spacing).
	last := (((bottomRight x / spacing) ceiling + 1) * spacing)
		@ (((bottomRight y / spacing) ceiling + 1) * spacing).
	key := { spacing. first. last }.
	key = gridKey ifTrue: [ ^ self ].
	gridKey := key.
	grid removeChildren.
	grid relocate: first.
	grid size: last - first.
	"About one screen pixel however far the board is zoomed."
	thickness := (1 / scale) max: 0.2.
	first x to: last x by: spacing do: [ :x |
		grid addChild: (self
			gridLineAt: (x - first x) @ 0
			extent: thickness @ (last y - first y)
			axis: x = 0) ].
	first y to: last y by: spacing do: [ :y |
		grid addChild: (self
			gridLineAt: 0 @ (y - first y)
			extent: (last x - first x) @ thickness
			axis: y = 0) ]!

gridLineAt: aPoint extent: anExtent axis: aBoolean
	"The lines through the document origin are brighter: on a plane with signed
	 coordinates, knowing where zero is matters more than the rest of the grid."
	| line |
	line := BlElement new.
	line background: (aBoolean
		ifTrue: [ Color fromHexString: '#4a5364' ]
		ifFalse: [ Color fromHexString: '#2f3542' ]).
	line constraintsDo: [ :c | c ignoreByLayout ].
	line size: anExtent.
	line relocate: aPoint.
	^ line!

installCanvasInteractions
	"The wheel zooms and a middle or right drag pans; the left button does
	 nothing on the background.

	 BlCanvassableElement installs two gestures of its own in #initialize, and
	 both are wrong here, so both come off first.  Its
	 BlCanvassableElementSlideHandler pans on a LEFT drag, and its
	 #withZoomOnScrollWheel zooms only while the primary modifier is held and
	 translates on a bare wheel.  Leaving them on does not merely add
	 behaviour: the stock wheel handler and ours would both answer the same
	 event, scrolling and zooming at once.

	 TODO: trackpad pinch-to-zoom and two-finger pan.  This image has no
	 BlPinchEvent or BlZoomEvent, so a trackpad arrives as ordinary wheel
	 events and cannot be told from a mouse; doing it properly needs host-level
	 gesture events first.  Mouse is fine for now."
	canvas removeEventHandlersSuchThat: [ :each |
		each class = BlCanvassableElementSlideHandler
			or: [ (each respondsTo: #eventClass)
				and: [ each eventClass = BlMouseWheelEvent ] ] ].

	canvas addEventHandlerOn: BlMouseWheelEvent do: [ :event |
		(event isPrimarilyVertical and: [ self isBackgroundEvent: event ]) ifTrue: [
			event consumed: true.
			self zoomOnWheel: event ] ].

	"Assembled from raw mouse events, not from drag events: Bloc raises a drag
	 for the primary button only.  BlMouseProcessor>>canStartDrag: opens with
	 (pressedButtons includes: BlMouseButton primary), so a middle or right
	 drag never produces a BlDragStartEvent at all and a drag-based pan cannot
	 fire however it is written."
	canvas addEventHandlerOn: BlMouseDownEvent do: [ :event |
		((self isPanButton: event button) and: [ self isBackgroundEvent: event ])
			ifTrue: [
				event consumed: true.
				self beginPanAt: event position ] ].
	canvas addEventHandlerOn: BlMouseMoveEvent do: [ :event |
		self isPanning ifTrue: [
			event consumed: true.
			self panTo: event position ] ].
	canvas addEventHandlerOn: BlMouseUpEvent do: [ :event | self endPan ]!

isBackgroundEvent: anEvent
	"True only when the pointer is over bare canvas or the grid drawn on it.
	 A card swallows its own wheel events this way: the editor inside it
	 scrolls, and the board does not also zoom underneath it."
	| target |
	target := anEvent target.
	^ target == canvas
		or: [ target == grid or: [ target parent == grid ] ]!

isPanButton: aButton
	"Compared by class: the button objects are not identical across events."
	^ aButton class = BlMouseMiddleButton
		or: [ aButton class = BlMouseSecondaryButton ]!

isPanning
	^ panOrigin notNil!

beginPanAt: aPoint
	panOrigin := aPoint.
	panStart := canvas childrenTranslationFactor!

panTo: aPoint
	panOrigin ifNil: [ ^ self ].
	canvas childrenTranslationFactor: panStart + (aPoint - panOrigin).
	self rebuildGrid!

endPan
	panOrigin := nil!

zoomOnWheel: anEvent
	| current target |
	current := canvas childrenScaleFactor.
	current <= 0 ifTrue: [ ^ self ].
	target := anEvent vector y positive
		ifTrue: [ current * canvas zoomStep ]
		ifFalse: [ current / canvas zoomStep ].
	target := (target min: self class maximumZoom) max: self class minimumZoom.
	self zoomTo: target towards: (canvas globalPointToLocal: anEvent position)!

zoomTo: aScale towards: aLocalPoint
	"Keep the document point under the cursor where it is, zooming in AND out.

	 GT's calculateTranslationFactorOnMouseWheelZoom: cannot do this: its
	 translateScalingFactor is hard-coded to 1/2, so it only ever describes a
	 doubling, and zooming out drifted towards the viewport centre instead.

	 Written against childrenScaleFactor: and childrenTranslationFactor: rather
	 than zoomLevel:, because zoomLevel:, zoomLevel:withTranslate: and
	 translate: each move childrenTransformationOrigin to the element's centre
	 as a side effect.  Left alone it keeps the 0@0 it was initialised with,
	 which is what makes the arithmetic here a plain inverse."
	| current start actual |
	current := canvas childrenScaleFactor.
	current <= 0 ifTrue: [ ^ self ].
	start := canvas childrenTranslationFactor.
	"Set the scale first and read it back: childrenScaleFactor: snaps a nearly
	 whole factor to the integer, and the translation must answer to what the
	 canvas actually took."
	canvas childrenScaleFactor: aScale.
	actual := canvas childrenScaleFactor.
	canvas childrenTranslationFactor:
		aLocalPoint - ((aLocalPoint - start) * actual / current).
	self rebuildGrid!

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

grid
	^ grid!

viewportExtent
	"The parent box a root card's percentages resolve against.  Space extent
	 rather than canvas extent: the canvas matches its parent, but only once a
	 layout has run, and a board built headless has not had one."
	^ space ifNil: [ 1000 @ 700 ] ifNotNil: [ :each | each extent ]!

projectDocument
	self clearCanvas.
	cardViews := IdentityDictionary new.
	document roots do: [ :each |
		self addCardViewFor: each in: canvas parentExtent: self viewportExtent ].
	^ self!

saveDocument
	documentFile ifNil: [ ^ self ].
	documentFile ensureDelete.
	documentFile writeStreamDo: [ :stream |
		stream nextPutAll: document source ].
	^ self! !

!McCorkboard methodsFor: 'floaty projection'!
addCardViewFor: aDirective in: aParentElement parentExtent: anExtent
	"A card is a Bloc child of the card it nests in, which is what makes the
	 three things the document asks for cost nothing: a child's constraints
	 position is already relative to its host, dragging the host carries its
	 children along with their relative positions intact, and a child painted
	 after its parent is painted above it."
	| card body row extent |
	extent := aDirective geometry extentIn: anExtent.
	card := BlElement new.
	card layout: BlLinearLayout vertical.
	card size: extent.
	card padding: (BlInsets all: 8).
	"The frame is grey and the text area below is white, so the title bar stops
	 somewhere visible instead of bleeding into the body."
	card background: (Color fromHexString: '#dfe3e8').
	card border: (BlBorder paint: (Color fromHexString: '#6c7280') width: 1).
	card geometry: (BlRoundedRectangleGeometry cornerRadius: 6).
	card constraintsDo: [ :c | c ignoreByLayout ].
	card relocate: (aDirective geometry positionIn: anExtent).
	card when: BlPullEvent do: [ :event |
		self commitDraggedCard: aDirective view: card parentExtent: anExtent ].
	body := self bodyFor: aDirective.
	row := self directiveRowFor: aDirective.
	card addChild: (self headerFor: aDirective card: card).
	card addChild: row.
	card addChild: body.
	aParentElement addChild: card.
	"The box the card's percentages resolve against travels with the views: a
	 card that follows a retyped directive has to place itself, and by then the
	 drag that used to supply this is not the one asking."
	cardViews at: aDirective put: { card. body. row. anExtent }.
	"After the body, so every descendant paints over it."
	aDirective children do: [ :each |
		self addCardViewFor: each in: card parentExtent: extent ].
	^ card!

headerFor: aDirective card: aCardElement
	| header title |
	header := BlElement new layout: BlLinearLayout horizontal.
	header constraintsDo: [ :c | c horizontal matchParent. c vertical exact: 26 ].
	title := BrLabel new.
	title aptitude: BrGlamorousLabelAptitude new.
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
	"The code aptitude rather than the regular one: it carries the system
	 monospace font, which is what a directive full of digits wants."
	body aptitude: BrGlamorousCodeEditorAptitude new.
	body background: Color white.
	body padding: (BlInsets all: 4).
	"The projection is applied to the rope the editor already holds rather than
	 assigned as a new one.  Handing an editor a fresh rope takes the caret with
	 it, and the caret is exactly what decides which directives are shown as
	 blocks and which as the source they came from -- so a projection that
	 destroyed it could never depend on it."
	body editor useSyncStylerStrategy.
	body editor styler: (BlPluggableStyler new block: [ :aText |
		self styleBody: aText for: aDirective in: body ]).
	body text: (self bodyTextFor: aDirective).
	"A card's text is a window onto a range of the one source, and typing into
	 it writes through to that range.  Nothing here owns a copy, so nothing has
	 to be reconciled with anything: the other cards showing that range read it
	 again."
	body editor when: BrTextEditorModifiedEvent do: [ :event |
		self cardBodyEdited: aDirective ].
	"A caret arriving on a directive reveals its source; one leaving puts the
	 block back."
	body editor when: BrTextEditorCursorMovedEvent do: [ :event |
		body editor styleText ].
	"The caret leaving is itself a deliberate moment, so it settles the
	 structure without waiting out the timer.  It also forgets where the caret
	 was: the author has gone somewhere else, and a rebuild that pulled the
	 focus back would be taking the click off whatever they clicked on."
	body addEventFilter: (BlEventHandler on: BlFocusOutEvent do: [ :event |
		caretPosition := nil.
		self enqueue: [ self commitStructure ] ]).
	body constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ].
	^ body!

bodyTextFor: aDirective
	"The characters a card shows: its region without the directive line that
	 opens it, which is drawn in the row above instead.  What those characters
	 look like is the styler's business, not this one's."
	^ (document renderRange: aDirective contentRange) asRopedText!

styleBody: aText for: aDirective in: anEditor
	"Draw every directive line inside the card as the block it is, except the
	 one the caret is on, which stays the source the author is editing.  The
	 characters stay in the text underneath a block, so the body is still a
	 faithful view of its range and the source mapping is untouched.

	 A styler runs on every keystroke and is handed the text in whatever state
	 the edit left it, an empty one included, so a range that does not fit is
	 skipped and anything unexpected degrades to plain source rather than
	 taking the card down."
	| cursor |
	[ cursor := self cursorIn: anEditor.
	  (document tokensIn: aDirective contentRange) do: [ :token |
		((token range first >= 1 and: [ token range last <= aText size ])
			and: [ (self cursor: cursor isNear: token range) not ])
			ifTrue: [ aText
				attribute: (BrTextAdornmentDynamicAttribute new
					beReplace;
					stencil: [ :anIndex | self blockFor: token ];
					yourself)
				from: token range first
				to: token range last ] ] ]
		on: Error do: [ :e | "leave the source showing" ].
	^ aText!

cursorIn: anEditor
	"The caret's position in anEditor, counted as characters before it, or -1
	 when there is none.  A card nobody is typing in has no caret, and so shows
	 every one of its directives as a block -- which is exactly how a passive
	 card should look."
	| position |
	position := -1.
	[ anEditor ifNotNil: [ anEditor editor cursors do: [ :each |
		position := each position ] ] ]
		on: Error do: [ :e | position := -1 ].
	^ position!

cursor: aPosition isNear: aRange
	"Whether the caret is on this line.  The rule McRichEdit uses, so a
	 directive and a piece of markdown reveal themselves the same way: the
	 caret is 0-based and ranges are 1-based, and the two of slack lets it sit
	 just before a line and still count as being on it."
	aPosition < 0 ifTrue: [ ^ false ].
	^ aPosition >= (aRange first - 2) and: [ aPosition <= aRange last ]!

directiveRowFor: aDirective
	"A card's own directive, in a row above its text instead of as the first
	 line of it.  Floaty wants the directive in sight; a row cannot be scrolled
	 out of view, and it holds still while the text below it moves.

	 It is an editor over exactly that line's range in the source, so a card can
	 be retyped as readily as it can be dragged.  The two are the same edit
	 arriving by different routes, and they end in the same place."
	| row |
	row := BrEditor new.
	row aptitude: BrGlamorousCodeEditorAptitude new.
	row text: (self directiveTextFor: aDirective).
	row editor when: BrTextEditorModifiedEvent do: [ :event |
		self directiveRowEdited: aDirective ].
	"Enter is the deliberate act, so it is what pays for a reparse."
	row addEventFilter: (BlEventHandler on: BlKeyDownEvent do: [ :event |
		event key isReturnOrEnter ifTrue: [
			event consumed: true.
			self enqueue: [ self commitStructure ] ] ]).
	row padding: (BlInsets top: 2 left: 6 bottom: 2 right: 6).
	row background: (Color fromHexString: '#e8eef4').
	row border: (BlBorder paint: (Color fromHexString: '#adbccc') width: 1).
	row geometry: (BlRoundedRectangleGeometry cornerRadius: 3).
	row margin: (BlInsets bottom: 4).
	row constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ].
	^ row!

directiveTextFor: aDirective
	"The line as the source has it, indentation and all: the row edits that
	 range, so anything it hides is something a keystroke would silently
	 destroy.

	 The family is named rather than asked for by #monospace: the code aptitude
	 installs a default family that wins over it."
	^ (document renderRange: aDirective range) asRopedText
		fontName: self class codeFontName;
		fontSize: 11;
		foreground: (Color fromHexString: '#2f4a66')!

blockFor: aToken
	"A directive inside a card's text, drawn as the block it is: a band across
	 the width of the text, because a band is what the line is.  A chip sitting
	 in the run of prose read as a word in the sentence; the line is a thing
	 the document is made of, and it should look like one.

	 An f@end carries no geometry and only ever closes a region, so it is a
	 sentinel and is coloured as one rather than pretending to be a card."
	| block sentinel |
	sentinel := aToken isEnd.
	block := BrLabel new.
	block aptitude: BrGlamorousLabelAptitude new.
	block text: (self blockTextFor: aToken).
	block constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ].
	block padding: (BlInsets top: 1 left: 6 bottom: 1 right: 6).
	block background: (Color fromHexString: (sentinel ifTrue: [ '#f6ecdc' ] ifFalse: [ '#e2edf7' ])).
	block border: (BlBorder paint: (Color fromHexString: (sentinel
		ifTrue: [ '#d8bf95' ]
		ifFalse: [ '#a9c8e4' ])) width: 1).
	block geometry: (BlRoundedRectangleGeometry cornerRadius: 3).
	^ block!

blockTextFor: aToken
	"The geometry, and after it the card the line opens.  There is room for the
	 name now that the block is a band rather than a chip, and the name is what
	 tells you which card you are looking at without going to find it."
	| text label suffix |
	text := (self blockLabelFor: aToken) asRopedText
		fontName: self class codeFontName;
		fontSize: 10;
		foreground: (Color fromHexString: (aToken isEnd
			ifTrue: [ '#7a5230' ]
			ifFalse: [ '#2f5d8a' ])).
	label := aToken isEnd
		ifTrue: [ '' ]
		ifFalse: [ aToken directive
			ifNil: [ '' ]
			ifNotNil: [ :each | each label ] ].
	label isEmpty ifTrue: [ ^ text ].
	"Built apart and then joined: a cascade after the comma would apply to the
	 concatenation, and the geometry would come out in the name's colour."
	suffix := ('   ' , label) asRopedText
		fontSize: 10;
		foreground: (Color fromHexString: '#6b7b8c');
		yourself.
	^ text , suffix!

blockLabelFor: aToken
	"The geometry alone, not the comment that carries it: the block exists to
	 show the structure where the source shows syntax."
	^ aToken isEnd
		ifTrue: [ 'f@end' ]
		ifFalse: [ aToken directive
			ifNil: [ aToken text trimBoth ]
			ifNotNil: [ :each | each geometry asDirectiveString ] ]!

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
	 into the unit the author wrote.

	 The drop goes to the document rather than to the directive: a geometry that
	 lived beside the source and was replayed over it on the way out would be a
	 second source of truth the moment a card's text could be typed into."
	document
		writeGeometryOf: aDirective
		as: (aDirective geometry
			withPosition: aCardElement constraints position
			in: anExtent).
	self refreshCardViews.
	^ aDirective!

directiveRowEdited: aDirective
	"A directive line retyped in its own row.  It goes into the source whatever
	 it now says, and the card follows it as far as it can: a line that still
	 reads as a directive moves the card on the keystroke that finishes it,
	 which is the same live feedback a drag gives.

	 A line that has stopped reading as one leaves the card where it is.  That
	 is not a refusal -- the text is in the source either way -- it is the card
	 waiting for the reparse that Enter asks for."
	| typed |
	typed := self singleLine: (self cardRowFor: aDirective) text asString.
	typed = (document renderRange: aDirective range) ifTrue: [ ^ self ].
	(document writeLineOf: aDirective as: typed)
		ifTrue: [ self placeCardFor: aDirective ].
	caretPosition := nil.
	self refreshCardViewsExcept: aDirective.
	self scheduleSettle.
	^ self!

cardBodyEdited: aDirective
	"A card's text, typed into.  The body is a window onto a range of the one
	 source, so what was typed goes back into that range and every other view of
	 it is read again -- including the host's, which is showing these same
	 characters further down its own body.

	 Only the span that actually changed is sent.  A card's range is most of the
	 document, and replacing all of it would move every anchor in it for the
	 sake of one keystroke."
	| range typed current edit |
	range := aDirective contentRange.
	typed := (self cardBodyFor: aDirective) text asString.
	current := document renderRange: range.
	typed = current ifTrue: [ ^ self ].
	edit := self replacementFrom: current to: typed at: range first.
	document
		replaceFrom: (edit at: 1)
		to: (edit at: 2)
		with: (edit at: 3).
	self noteCaretIn: aDirective.
	self refreshCardViewsExcept: aDirective.
	self scheduleSettle.
	^ self!

replacementFrom: anOldString to: aNewString at: anOffset
	"The one span that differs between the two, as a source range and the text
	 that belongs in it.  A keystroke changes one place, so the common prefix
	 and the common suffix bracket exactly what the author did.

	 anOffset is where the old string starts in the source, so the answer is in
	 the document's coordinates rather than the card's."
	| prefix suffix limit |
	prefix := 0.
	limit := anOldString size min: aNewString size.
	[ prefix < limit
		and: [ (anOldString at: prefix + 1) = (aNewString at: prefix + 1) ] ]
		whileTrue: [ prefix := prefix + 1 ].
	suffix := 0.
	limit := limit - prefix.
	[ suffix < limit
		and: [ (anOldString at: anOldString size - suffix)
			= (aNewString at: aNewString size - suffix) ] ]
		whileTrue: [ suffix := suffix + 1 ].
	^ { anOffset + prefix.
		anOffset + anOldString size - suffix - 1.
		aNewString copyFrom: prefix + 1 to: aNewString size - suffix }!

commitStructure
	"Read the document again, when an edit has moved the source on from the
	 parse the board is projecting.

	 A line may have stopped being a directive, started being one, or come to
	 govern a different heading, and none of that is something the live path can
	 answer -- it moves a card, it does not restructure the board.  So the board
	 is projected again, and the caret is carried across by where it was in the
	 document rather than by which card was holding it: the card that was
	 holding it may not exist any more, and if the author has just broken a
	 directive it should not.  It lands in the innermost card that still covers
	 that position, which is the one now showing those characters.

	 A drag does not reach here.  It says the parse it left standing is still
	 good, and it is entitled to: it rewrote a line that opens the same card
	 over the same region either way."
	| position |
	document needsReparse ifFalse: [ ^ self ].
	position := caretPosition.
	document reparse.
	self projectDocument.
	self restoreCaretTo: position.
	^ self!

noteCaretIn: aDirective
	"Where the caret is in the document, taken after the edit that moved it, so
	 that a rebuild can put it back somewhere that still exists.

	 An edit can arrive with no caret behind it -- a test drives the editor
	 directly, and so could anything else that edits a card without a person in
	 front of it.  There is nothing to put back then, and a position worked out
	 from the absence of one would be a fabrication."
	| cursor |
	cursor := self cursorIn: (self cardBodyFor: aDirective).
	caretPosition := cursor < 0
		ifTrue: [ nil ]
		ifFalse: [ aDirective contentRange first - 1 + cursor ].
	^ caretPosition!

restoreCaretTo: aPositionOrNil
	"Put the caret back at a document position in whichever card now shows it.
	 The innermost such card: a broken directive takes its own card away, and
	 the text it was showing is then the host's, which is where the author is
	 still typing.

	 Nothing to restore when the position is gone from the document entirely --
	 the author deleted the text the caret was in, and there is nowhere honest
	 to put it."
	| best |
	aPositionOrNil ifNil: [ ^ self ].
	best := nil.
	cardViews keysAndValuesDo: [ :directive :views |
		| range |
		range := directive contentRange.
		((aPositionOrNil >= (range first - 1) and: [ aPositionOrNil <= range last ])
			and: [ best isNil or: [ range first > best contentRange first ] ])
			ifTrue: [ best := directive ] ].
	best ifNil: [ ^ self ].
	self caretIn: best to: aPositionOrNil - (best contentRange first - 1).
	^ best!

caretIn: aDirective to: aLocalPosition
	"Move a card's caret to a position of its own, and ask for the focus that
	 makes it the card being typed in.  A rebuild the author did not ask for
	 should leave them where they were."
	| body |
	body := self cardBodyFor: aDirective.
	[ body editor moveCursorTo: (aLocalPosition max: 0).
	  body requestFocus.
	  body editor styleText ]
		on: Error do: [ :e | nil ].
	^ body!

scheduleSettle
	"Answer a structural change once typing has paused, not on the keystroke
	 that made it.  Every prefix of a directive being typed is a line that is
	 not one yet, and rebuilding on each of them would flash a card out of
	 existence and back on nearly every character.

	 Each keystroke supersedes the last one's pending answer, so a run of them
	 costs one rebuild at the end rather than one apiece."
	| generation |
	settleGeneration := (settleGeneration ifNil: [ 0 ]) + 1.
	generation := settleGeneration.
	space ifNil: [ ^ self ].
	space enqueueTask: (BlDelayedTaskAction new
		delay: self class settleMilliseconds milliSeconds;
		action: [ generation = settleGeneration ifTrue: [ self commitStructure ] ];
		yourself).
	^ self!

enqueue: aBlock
	"Run aBlock on the next pulse instead of inside the event being dispatched.
	 Re-projecting destroys the element the event is on, which is not something
	 to do while that element is still handling it.  With no space -- headless,
	 in a test -- there is no pulse to wait for and nothing dispatching."
	space
		ifNil: [ aBlock value ]
		ifNotNil: [ :each | each enqueueTask: (BlTaskAction new action: aBlock) ].
	^ self!

singleLine: aString
	"A directive is one line by definition, so a newline typed into a row is
	 not part of one: the row writes the line it would be without it rather
	 than breaking the source in two."
	^ (aString copyWithout: Character lf) copyWithout: Character cr!

placeCardFor: aDirective
	"The card follows its directive, whichever way the directive changed --
	 dragged into a new position or retyped into one."
	| views extent card |
	views := cardViews at: aDirective ifAbsent: [ ^ self ].
	extent := views fourth.
	card := views first.
	card size: (aDirective geometry extentIn: extent).
	card relocate: (aDirective geometry positionIn: extent).
	^ card!

refreshCardViews
	^ self refreshCardViewsExcept: nil!

refreshCardViewsExcept: aDirectiveOrNil
	"Re-read every card from the source the edit just made.  Each body is a
	 view onto a range of the one document, so a line that changed must reappear
	 in every card whose region covers it, the host included.

	 The card that originated the edit is left alone.  It already holds what the
	 author typed, and handing it back its own text would take the caret to the
	 end of it -- which is the whole difference between a card you can type in
	 and one that fights you."
	cardViews keysAndValuesDo: [ :directive :views |
		directive == aDirectiveOrNil ifFalse: [
			(views at: 2) text: (self bodyTextFor: directive).
			(views at: 3) text: (self directiveTextFor: directive) ] ]!

cardViewFor: aDirective
	^ (cardViews at: aDirective) first!

cardBodyFor: aDirective
	^ (cardViews at: aDirective) second!

cardRowFor: aDirective
	^ (cardViews at: aDirective) third!

cardParentExtentFor: aDirective
	"The box this card's percentages resolve against -- its host's extent, or
	 the viewport's when it is a root."
	^ (cardViews at: aDirective) fourth! !

!McCorkboard class methodsFor: 'settling'!
settleMilliseconds
	"How long typing has to pause before the board answers a structural change.

	 Typing a directive walks through many broken states -- every prefix of
	 `<!!-- f@45x30 -->` is a line that is not one yet -- and answering each of
	 them would flash a card out of existence and back on nearly every
	 character.  The source is right the whole time regardless; only the cards
	 wait.

	 Set for the image with #settleMilliseconds:, or for the session with
	 MC_CORKBOARD_SETTLE_MS in the environment."
	SettleMilliseconds ifNotNil: [ :each | ^ each ].
	^ self settleMillisecondsFromEnvironment ifNil: [ 500 ]!

settleMilliseconds: anIntegerOrNil
	"Override the settle for this image; nil restores the environment or the
	 default.  A live board picks this up on its next keystroke."
	SettleMilliseconds := anIntegerOrNil!

settleMillisecondsFromEnvironment
	"MC_CORKBOARD_SETTLE_MS, when it is set and reads as a whole number of
	 milliseconds.  Anything else is ignored rather than argued with: a
	 mistyped variable should not stop the board from opening."
	| raw |
	raw := [ Smalltalk os environment at: 'MC_CORKBOARD_SETTLE_MS' ifAbsent: [ nil ] ]
		on: Error do: [ :e | nil ].
	raw ifNil: [ ^ nil ].
	raw isEmpty ifTrue: [ ^ nil ].
	^ ((1 to: raw size) allSatisfy: [ :index | (raw at: index) isDigit ])
		ifTrue: [ raw asInteger ]
		ifFalse: [ nil ]! !

!McCorkboard class methodsFor: 'grid'!
codeFontName
	"What the code aptitude in the card bodies uses, so a directive drawn as a
	 block lines up with the text it was lifted out of."
	^ 'Source Code Pro'!

gridSpacing
	"Document pixels between grid lines at 1:1."
	^ 40!

minimumCellPixels
	"A cell finer than this on screen reads as noise, so the spacing doubles
	 instead."
	^ 16!

minimumZoom
	^ 0.15!

maximumZoom
	^ 6! !
