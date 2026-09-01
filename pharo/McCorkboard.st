"
McCorkboard -- a deliberately small, model-first floating-panel prototype.

The canvas position is a document coordinate, never a Bloc position.  Bloc is
only a projection of McCorkboardPanelModel.  This keeps persistence, address
resolution and future pan/zoom independent from the component tree.
"!

Object subclass: #McCorkboard
	instanceVariableNames: 'model space canvas panelViews'
	classVariableNames: ''
	package: 'MalleableControl'!

!McCorkboard class methodsFor: 'opening'!
open
	^ self new openView!

exampleModel
	^ McCorkboardDocument new
		addPanel: (McCorkboardPanelModel id: #noteOne x: 0 y: 0 text: '# Floating note');
		addPanel: (McCorkboardPanelModel id: #noteTwo x: 420 y: -120 text: 'Signed coordinates work.');
		yourself! !

!McCorkboard methodsFor: 'opening'!
openView
	model := self class exampleModel.
	panelViews := Dictionary new.
	space := BlSpace new.
	space title: 'Corkboard — coordinate canvas prototype'.
	space extent: 1000 @ 700.
	canvas := BlCanvassableElement new.
	"Without this, the first layout zooms to fit the cards and document
	 coordinates cease to mean the values shown in the fields."
	canvas disableAutoScale.
	canvas constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ].
	canvas background: (Color fromHexString: '#20232a').
	"Editors consume Escape. Capture it at the canvas so discard is reliable
	 even while a numeric field has focus."
	canvas addEventFilter: (BlEventHandler on: BlKeyDownEvent do: [ :event |
		event key isEscape ifTrue: [ self discardAllDrafts. event consumed: true ] ]).
	space root addChild: canvas.
	model panels do: [ :each | self addPanelViewFor: each ].
	space show.
	^ self!

model
	^ model!

canvas
	^ canvas! !

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
	panel addEventHandler: (BlPullHandler new allowOutOfBounds).
	panel when: BlPullEvent do: [ :event | self commitDraggedPanel: aPanelModel view: panel ].

	header := BlElement new layout: BlLinearLayout horizontal.
	header constraintsDo: [ :c | c horizontal matchParent. c vertical exact: 30 ].
	title := BrLabel new.
	title text: (aPanelModel id asString asRopedText fontSize: 14; bold).
	title constraintsDo: [ :c | c horizontal matchParent ].
	header addChild: title.
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
	aPanelModel moveToX: aPanelElement position x rounded y: aPanelElement position y rounded.
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
