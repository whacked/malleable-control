"
McRichEdit -- Prototype proving three theses about hybrid text editing in GT:

  1. BrTextAdornmentDynamicAttribute can inject live BlElement widgets
     inline in a text editor (checkboxes, color swatches, buttons).
  2. BrTextHideAttribute can collapse syntax delimiters (like ** for bold)
     to zero width while preserving the source text.
  3. Cursor-driven restyling can toggle between raw source view and
     rendered widget view based on cursor locality.

Button model: text is parsed for <<label>> tokens.  A handler table maps
labels to actions.  The stencil block looks up the handler fresh on every
restyle, so toggling between raw/widget never loses the association.

Chunk format: load with fileIn.
"!

Object subclass: #McRichEdit
	instanceVariableNames: 'space editorElement container titleLabel statusLabel darkMode buttonHandlers'
	classVariableNames: ''
	package: 'MalleableControl'!

!McRichEdit class methodsFor: 'opening'!
open
	^ self new openView! !

!McRichEdit methodsFor: 'palette'!
palette
	"Return a dictionary of named colors for the current mode."
	^ darkMode
		ifTrue: [Dictionary new
			at: 'containerBg' put: (Color fromHexString: '#0f0e17');
			at: 'editorBg' put: (Color fromHexString: '#1a1a2e');
			at: 'editorBorder' put: (Color fromHexString: '#2e2e3e');
			at: 'text' put: (Color fromHexString: '#a7a9be');
			at: 'title' put: (Color fromHexString: '#fffffe');
			at: 'boldText' put: (Color fromHexString: '#fffffe');
			at: 'dimDelimiter' put: (Color fromHexString: '#555555');
			at: 'highlight' put: (Color fromHexString: '#7f5af0');
			at: 'status' put: (Color fromHexString: '#a7a9be');
			yourself]
		ifFalse: [Dictionary new
			at: 'containerBg' put: (Color fromHexString: '#f0f0f0');
			at: 'editorBg' put: Color white;
			at: 'editorBorder' put: (Color fromHexString: '#cccccc');
			at: 'text' put: (Color fromHexString: '#333333');
			at: 'title' put: (Color fromHexString: '#222222');
			at: 'boldText' put: (Color fromHexString: '#111111');
			at: 'dimDelimiter' put: (Color fromHexString: '#bbbbbb');
			at: 'highlight' put: (Color fromHexString: '#7f5af0');
			at: 'status' put: (Color fromHexString: '#888888');
			yourself]! !

!McRichEdit methodsFor: 'opening'!
openView
	"Create the editor with demo content, wire up the styler
	 and cursor-driven restyling, and open in a new window."
	| editorModel styler headerRow toggleButton toggleLabel editorFrame |
	darkMode := false.

	space := BlSpace new.
	space title: 'Rich Edit — Prototype'.
	space extent: 700@540.

	container := BlElement new.
	container layout: BlLinearLayout vertical.
	container constraintsDo: [:c | c horizontal matchParent. c vertical matchParent].
	container padding: (BlInsets all: 24).

	"Header row: title + toggle."
	headerRow := BlElement new.
	headerRow layout: BlLinearLayout horizontal.
	headerRow constraintsDo: [:c | c horizontal matchParent. c vertical fitContent].
	headerRow margin: (BlInsets bottom: 16).

	titleLabel := BrLabel new.
	titleLabel constraintsDo: [:c | c horizontal matchParent].

	toggleLabel := BrLabel new.
	toggleLabel text: ('Dark Mode' asRopedText fontSize: 13).
	toggleLabel margin: (BlInsets right: 8).
	toggleLabel constraintsDo: [:c | c linear vertical alignCenter].

	toggleButton := BrCheckbox new.
	toggleButton aptitude: BrGlamorousCheckboxAptitude new.
	toggleButton beNormalSize.
	toggleButton checked: false.
	toggleButton constraintsDo: [:c | c linear vertical alignCenter].
	toggleButton whenCheckedDo: [
		darkMode := true. self applyPalette].
	toggleButton whenUncheckedDo: [
		darkMode := false. self applyPalette].

	headerRow addChild: titleLabel.
	headerRow addChild: toggleLabel.
	headerRow addChild: toggleButton.

	"Editor inside a bordered frame."
	editorFrame := BlElement new.
	editorFrame layout: BlFrameLayout new.
	editorFrame constraintsDo: [:c | c horizontal matchParent. c vertical matchParent].
	editorFrame geometry: (BlRoundedRectangleGeometry cornerRadius: 6).
	editorFrame clipChildren: true.

	editorElement := BrEditor new.
	editorElement text: self demoContent asRopedText.
	editorElement constraintsDo: [:c |
		c horizontal matchParent.
		c vertical matchParent].
	editorElement padding: (BlInsets all: 16).

	editorFrame addChild: editorElement.

	editorModel := editorElement editor.
	editorModel useSyncStylerStrategy.

	"Cursor-driven restyling."
	editorModel when: BrTextEditorCursorMovedEvent do: [:e |
		editorModel styleText].

	"Projection styler."
	styler := BlPluggableStyler new block: [:aText |
		self styleText: aText].
	editorElement styler: styler.

	"Status bar for button feedback."
	statusLabel := BlTextElement new.
	statusLabel text: ('Ready' asRopedText fontSize: 13; foreground: (self palette at: 'status')).
	statusLabel constraintsDo: [:c | c horizontal matchParent. c vertical exact: 20].
	statusLabel margin: (BlInsets top: 10).

	"Button handler table."
	self registerDefaultButtons.

	container addChild: headerRow.
	container addChild: editorFrame.
	container addChild: statusLabel.

	space root addChild: container.
	self applyPalette.
	space show.
	^ self!

applyPalette
	"Update all chrome from the current palette, then restyle editor text."
	| p |
	p := self palette.
	space enqueueTask: (BlTaskAction new action: [
		container background: (p at: 'containerBg').
		editorElement parent
			background: (p at: 'editorBg');
			border: (BlBorder paint: (p at: 'editorBorder') width: 1).
		editorElement aptitude: (BrGlamorousRegularEditorAptitude new
			foreground: (p at: 'text');
			fontSize: 16;
			background: (p at: 'editorBg')).
		titleLabel text: ('Rich Edit Prototype' asRopedText
			foreground: (p at: 'title');
			fontSize: 22;
			bold).
		statusLabel text: (statusLabel text asString asRopedText
			foreground: (p at: 'status');
			fontSize: 13).
		editorElement editor styleText])! !

!McRichEdit methodsFor: 'button handlers'!
registerDefaultButtons
	"Populate the handler table with demo actions."
	buttonHandlers := Dictionary new.
	buttonHandlers at: 'hello' put: [
		self showStatus: 'Hello from a rich-edit button' ].
	buttonHandlers at: 'time' put: [
		self showStatus: 'Current time: ' , DateAndTime now printString ].
	buttonHandlers at: 'count' put: [ | n |
		n := (buttonHandlers at: 'count-state' ifAbsent: [ 0 ]) + 1.
		buttonHandlers at: 'count-state' put: n.
		self showStatus: 'Count: ' , n printString ]!

showStatus: aString
	"Display feedback in the status bar."
	| p |
	p := self palette.
	space enqueueTask: (BlTaskAction new action: [
		statusLabel text: (aString asRopedText
			foreground: (p at: 'status');
			fontSize: 13)])! !

!McRichEdit methodsFor: 'content'!
demoContent
	^ '[ ] Buy groceries
[x] Write prototype
[x] Prove thesis one
[ ] Prove thesis two

**Hello World** is bold text.
So is **this phrase** here.

Colors: #FF0000 red, #00FF00 green, #3498DB blue.

Buttons: <<hello>>  <<time>>  <<count>>

Move your cursor into any token to reveal its raw source.'! !

!McRichEdit methodsFor: 'styling'!
styleText: aText
	"Main styling entry point. Scan for tokens and apply
	 projection rules based on cursor locality."
	| str cursorPos |
	str := aText asString.
	cursorPos := self cursorPosition.

	self styleCheckboxes: aText source: str cursor: cursorPos.
	self styleBold: aText source: str cursor: cursorPos.
	self styleColors: aText source: str cursor: cursorPos.
	self styleButtons: aText source: str cursor: cursorPos!

cursorPosition
	"Return the 0-based cursor position, or -1 if no cursor."
	| pos |
	pos := -1.
	editorElement editor cursors do: [:c | pos := c position].
	^ pos! !

!McRichEdit methodsFor: 'styling - checkboxes'!
styleCheckboxes: aText source: str cursor: cursorPos
	"Thesis 1: Replace [ ]/[x] with live checkbox widgets."
	| rx p |
	p := self palette.
	rx := '\[[ xX]\]' asRegex.
	(rx matchingRangesIn: str) do: [:range |
		| start stop |
		start := range first.
		stop := range last.
		(self cursor: cursorPos isNear: start to: stop)
			ifTrue: [
				aText
					attribute: (BlTextForegroundAttribute new paint: (p at: 'highlight'))
					from: start
					to: stop]
			ifFalse: [
				| checked |
				checked := (str at: start + 1) = $x or: [(str at: start + 1) = $X].
				aText
					attribute: (BrTextAdornmentDynamicAttribute new
						beReplace;
						stencil: [
							| cb |
							cb := BrCheckbox new.
							cb aptitude: BrGlamorousCheckboxAptitude new.
							cb checked: checked.
							cb beNormalSize.
							cb margin: (BlInsets right: 4).
							cb whenCheckedDo: [
								self replaceFrom: start + 1 to: start + 1 with: 'x'].
							cb whenUncheckedDo: [
								self replaceFrom: start + 1 to: start + 1 with: ' '].
							cb])
					from: start
					to: stop]]! !

!McRichEdit methodsFor: 'styling - bold'!
styleBold: aText source: str cursor: cursorPos
	"Thesis 2: Hide ** delimiters and bold inner text."
	| rx p |
	p := self palette.
	rx := '\*\*[^*]+\*\*' asRegex.
	(rx matchingRangesIn: str) do: [:range |
		| start stop |
		start := range first.
		stop := range last.
		(self cursor: cursorPos isNear: start to: stop)
			ifTrue: [
				aText
					attribute: (BlTextForegroundAttribute new paint: (p at: 'dimDelimiter'))
					from: start
					to: start + 1.
				aText
					attribute: (BlTextForegroundAttribute new paint: (p at: 'dimDelimiter'))
					from: stop - 1
					to: stop.
				aText
					attribute: (BlTextForegroundAttribute new paint: (p at: 'text'))
					from: start + 2
					to: stop - 2]
			ifFalse: [
				aText
					attribute: BrTextHideAttribute new
					from: start
					to: start + 1.
				aText
					attribute: BrTextHideAttribute new
					from: stop - 1
					to: stop.
				aText
					attribute: (BlFontWeightAttribute new weight: BlFontWeight bold)
					from: start + 2
					to: stop - 2.
				aText
					attribute: (BlTextForegroundAttribute new paint: (p at: 'boldText'))
					from: start + 2
					to: stop - 2]]! !

!McRichEdit methodsFor: 'styling - colors'!
styleColors: aText source: str cursor: cursorPos
	"Thesis 1+2: Append a color swatch after hex codes."
	| rx p |
	p := self palette.
	rx := '#[0-9A-Fa-f]{6}' asRegex.
	(rx matchingRangesIn: str) do: [:range |
		| start stop hex |
		start := range first.
		stop := range last.
		hex := str copyFrom: start + 1 to: stop.
		(self cursor: cursorPos isNear: start to: stop)
			ifTrue: [
				aText
					attribute: (BlTextForegroundAttribute new paint: (p at: 'highlight'))
					from: start
					to: stop]
			ifFalse: [
				aText
					attribute: (BrTextAdornmentDynamicAttribute new
						beAppend;
						stencil: [
							| swatch |
							swatch := BlElement new.
							swatch size: 14@14.
							swatch geometry: (BlRoundedRectangleGeometry cornerRadius: 3).
							swatch background: (Color fromHexString: hex).
							swatch margin: (BlInsets left: 4).
							swatch])
					from: start
					to: stop]]! !

!McRichEdit methodsFor: 'styling - buttons'!
styleButtons: aText source: str cursor: cursorPos
	"Replace <<label>> with a live button wired to the handler table.
	 The handler is looked up fresh on every restyle — no stale refs."
	| rx p |
	p := self palette.
	rx := '<<[^>]+>>' asRegex.
	(rx matchingRangesIn: str) do: [:range |
		| start stop label |
		start := range first.
		stop := range last.
		label := str copyFrom: start + 2 to: stop - 2.
		(self cursor: cursorPos isNear: start to: stop)
			ifTrue: [
				"Cursor nearby — show raw <<label>> syntax"
				aText
					attribute: (BlTextForegroundAttribute new paint: (p at: 'highlight'))
					from: start
					to: stop]
			ifFalse: [
				"Cursor away — render as a clickable button"
				aText
					attribute: (BrTextAdornmentDynamicAttribute new
						beReplace;
						stencil: [
							| btn handler |
							handler := buttonHandlers at: label ifAbsent: [ nil ].
							btn := BrButton new.
							btn label: label.
							btn aptitude: BrGlamorousButtonWithLabelAptitude new.
							btn beSmallSize.
							btn margin: (BlInsets left: 2 right: 2).
							btn action: [
								handler
									ifNil: [ self showStatus: 'No handler for: ' , label ]
									ifNotNil: [ handler value ] ].
							btn])
					from: start
					to: stop]]! !

!McRichEdit methodsFor: 'cursor locality'!
cursor: cursorPos isNear: start to: stop
	"True when the cursor is within or adjacent to the token range.
	 Cursor is 0-based; text ranges are 1-based."
	cursorPos < 0 ifTrue: [^ false].
	^ cursorPos >= (start - 2) and: [cursorPos <= stop]! !

!McRichEdit methodsFor: 'text mutation'!
replaceFrom: start to: stop with: aString
	"Replace a range of the underlying editor text.
	 This triggers re-styling automatically."
	| text str newStr |
	text := editorElement editor text.
	str := text asString.
	newStr := (str copyFrom: 1 to: start - 1) , aString , (str copyFrom: stop + 1 to: str size).
	editorElement editor text: newStr asRopedText! !
