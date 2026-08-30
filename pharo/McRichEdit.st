"
McRichEdit -- Prototype proving three theses about hybrid text editing in GT:

  1. BrTextAdornmentDynamicAttribute can inject live BlElement widgets
     inline in a text editor (checkboxes, color swatches, buttons).
  2. BrTextHideAttribute can collapse syntax delimiters (like ** for bold)
     to zero width while preserving the source text.
  3. Cursor-driven restyling can toggle between raw source view and
     rendered widget view based on cursor locality.

The document is parsed by McMarkdownParser and projected by
McMarkdownStylerVisitor (see pharo/McMarkdown.st).  Inline decoration --
emphasis and this editor's own tokens (checkboxes, colour swatches, buttons)
alike -- is reached per block through McMarkdownInlineStyler (see
pharo/McMarkdownInline.st), scoped to that block's own range.  Nothing scans
the flat document: a range a widget has claimed is simply never descended
into.

Button model: text is parsed for <<label>> tokens.  A handler table maps
labels to actions.  The stencil block looks up the handler fresh on every
restyle, so toggling between raw/widget never loses the association.

Requires McRelation.st, McMarkdownInline.st, McMarkdownTable.st and
McMarkdown.st to be filed in first, in that order -- see test/run-pharo-tests.sh
and elisp/mc-rich-edit.el, which both file in that chain.

Chunk format: load with fileIn.
"!

Object subclass: #McRichEdit
	instanceVariableNames: 'space editorElement container titleLabel statusLabel darkMode buttonHandlers'
	classVariableNames: ''
	package: 'MalleableControl'!

!McRichEdit class methodsFor: 'opening'!
open
	^ self new openView! !

!McRichEdit methodsFor: 'initialization'!
initialize
	"A fresh instance must be usable before openView runs -- palette
	 branches on darkMode, and a nil there is not a boolean."
	super initialize.
	darkMode := false.
	buttonHandlers := Dictionary new! !

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
			at: 'codeBg' put: (Color fromHexString: '#24243a');
			at: 'codeText' put: (Color fromHexString: '#c7c9d9');
			at: 'rule' put: (Color fromHexString: '#3a3a4e');
			at: 'tableBorder' put: (Color fromHexString: '#3a3a4e');
			at: 'tableHeaderBg' put: (Color fromHexString: '#24243a');
			at: 'quoteBar' put: (Color fromHexString: '#7f5af0');
			at: 'quoteText' put: (Color fromHexString: '#8f91a8');
			at: 'listMarker' put: (Color fromHexString: '#7f5af0');
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
			at: 'codeBg' put: (Color fromHexString: '#e9ebf2');
			at: 'codeText' put: (Color fromHexString: '#2d2d2d');
			at: 'rule' put: (Color fromHexString: '#d0d0d0');
			at: 'tableBorder' put: (Color fromHexString: '#d5d5dd');
			at: 'tableHeaderBg' put: (Color fromHexString: '#eeeef2');
			at: 'quoteBar' put: (Color fromHexString: '#7f5af0');
			at: 'quoteText' put: (Color fromHexString: '#555555');
			at: 'listMarker' put: (Color fromHexString: '#7f5af0');
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

"Live edit requires running this after a reload:
   McRichEdit allInstances do: [:each | each registerDefaultButtons]
 and to display the registered source code:
   (McRichEdit >> #registerDefaultButtons) sourceCode

 The bang that closes this comment is load-bearing. Without it the chunk runs
 on and swallows the bang that opens the next protocol, which is then evaluated
 as an expression rather than read as a protocol header, and the whole file
 fails to load with a doesNotUnderstand on methodsFor:."!

!McRichEdit methodsFor: 'button handlers'!
registerDefaultButtons
	"Populate the handler table with demo actions."
	buttonHandlers := Dictionary new.
	buttonHandlers at: 'hello' put: [
		self showStatus: 'NEW Hello from a rich-edit button' ].
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
	"Demo document exercising every element the styler projects."
	^ '# Rich Edit

A **bold** phrase, some _italic_, and `inline code` in one paragraph
that runs across two source lines to prove offsets survive the break.

## Tasks

[ ] Buy groceries
[x] Write the parser
[x] Prove thesis one
[ ] Prove thesis two

## Table

| task | colour | qty |
|:-----|:------:|----:|
| [ ] **write the reader** | #7f5af0 | 11 |
| [x] `ship the styler`    | #2cb67d | 3  |
| [ ] _sort the rows_      | #ff8906 | 7  |

Click a column header to sort -- the rows are rewritten in the document.

## Code

```smalltalk
McMarkdownParser parseSource: aString
```

## Lists

- unordered one
- unordered two

1. ordered one
2. ordered two

> A quote with **bold** inside it.

---

Colors: #FF0000 red, #00FF00 green, #3498DB blue.

Buttons: <<hello>>  <<time>>  <<count>>

Move your cursor into any element to reveal its raw source.'! !

!McRichEdit methodsFor: 'styling'!
styleText: aText
	"Main styling entry point.  The document is parsed into a Microdown AST
	 and projected by McMarkdownStylerVisitor, which reaches inline
	 decoration -- emphasis and this editor's own tokens alike -- through
	 McMarkdownInlineStyler, per block.  Nothing scans the flat document any
	 more: a range a widget has claimed is simply never descended into."
	self styleMarkdown: aText source: aText asString cursor: self cursorPosition!

styleMarkdown: aText source: str cursor: cursorPos
	"Parse and project the standard markdown elements.  A styler runs on
	 every keystroke, so a parse failure must degrade to unstyled text rather
	 than take the editor down with it."
	| parser |
	[ parser := McMarkdownParser parseSource: str.
	  (McMarkdownStylerVisitor
		parser: parser
		text: aText
		cursor: cursorPos
		palette: self palette
		owner: self) visit: parser root ]
		on: Error
		do: [ :e |
			self showStatus: 'markdown: ' , e messageText asString ]!

cursorPosition
	"Return the 0-based cursor position, or -1 if no cursor."
	| pos |
	pos := -1.
	editorElement editor cursors do: [:c | pos := c position].
	^ pos! !

!McRichEdit methodsFor: 'text mutation'!
replaceFrom: start to: stop with: aString
	"Replace a range of the underlying editor text.
	 This triggers re-styling automatically."
	| text str newStr |
	text := editorElement editor text.
	str := text asString.
	newStr := (str copyFrom: 1 to: start - 1) , aString , (str copyFrom: stop + 1 to: str size).
	editorElement editor text: newStr asRopedText!

performButtonNamed: aLabel
	| handler |
	handler := buttonHandlers at: aLabel ifAbsent: [ nil ].
	handler
		ifNil: [ self showStatus: 'No handler for: ' , aLabel ]
		ifNotNil: [ handler value ]! !
