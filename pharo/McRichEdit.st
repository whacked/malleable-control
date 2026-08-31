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

Requires McRelation.st, McMarkdownLink.st, McMarkdownInline.st,
McMarkdownTable.st, McSqlite.st and McMarkdown.st to be filed in first, in that
order; McRichEditLinks.st extends this class after it is loaded.  McCache.st
should be filed in before that chain to enable bounded caches; rendering
remains correct without it so an incremental live-image reload cannot disable
every widget.  See test/run-pharo-tests.sh and elisp/mc-rich-edit.el, which both
load the full optimized chain.

This file also holds McCursorProbe, the stand-in for the caret that lets a
cursor move be answered out of the previous styling pass instead of provoking a
new one.  It is defined first because McRichEdit names it.

Chunk format: load with fileIn.
"!

"
McCursorProbe -- an integer that remembers what was asked of it.

The projection McRichEdit draws is a function of two things: the document
source and the caret position.  It depends on the caret only through tests of
the form `is the cursor near this range' -- McMarkdownStylerVisitor>>isNear:
and McMarkdownInlineStyler>>isNearSource:to: are the whole of it, and both are
built from >=, <= and < against document positions.

A probe stands in for the cursor during a styling pass and answers each of
those comparisons exactly as the integer would, while recording the position at
which the answer would have flipped: `cursor >= k' changes between k - 1 and k,
so k is a boundary; `cursor <= m' changes between m and m + 1, so m + 1 is.

Two caret positions with no recorded boundary strictly between them therefore
give every comparison on the path the pass actually took the same answer -- and
since the path is chosen by those same comparisons, the pass takes the same
path and produces the same attributes.  That is what lets McRichEdit skip a
restyle rather than guess at one.

Anything outside the comparison protocol reaches doesNotUnderstand:, which
forwards to the wrapped integer and marks the record untrustworthy, so a future
change to the styling pipeline costs the optimisation rather than correctness.

Chunk format: load with fileIn.
"!

Object subclass: #McCursorProbe
	instanceVariableNames: 'value boundaries trusted'
	classVariableNames: ''
	package: 'MalleableControl'!

!McCursorProbe class methodsFor: 'instance creation'!
on: anInteger
	^ self new setValue: anInteger! !

!McCursorProbe methodsFor: 'initialization'!
setValue: anInteger
	value := anInteger.
	boundaries := Set new.
	trusted := true! !

!McCursorProbe methodsFor: 'accessing'!
value
	"The cursor position being stood in for."
	^ value!

isTrusted
	^ trusted!

boundaries
	"The positions at which some comparison made during the pass changes its
	 answer, or nil when the record cannot be trusted."
	^ trusted ifTrue: [ boundaries ] ifFalse: [ nil ]! !

!McCursorProbe methodsFor: 'comparing'!
< aNumber
	"True below aNumber, so the answer changes on reaching it."
	boundaries add: aNumber.
	^ value < aNumber!

<= aNumber
	"True up to and including aNumber, so the answer changes one past it."
	boundaries add: aNumber + 1.
	^ value <= aNumber!

> aNumber
	boundaries add: aNumber + 1.
	^ value > aNumber!

>= aNumber
	boundaries add: aNumber.
	^ value >= aNumber!

between: min and: max
	"Written out rather than inherited so both bounds are recorded."
	^ (self >= min) and: [ self <= max ]!

= anObject
	"Equality against a position is true at exactly one point, so it changes
	 on reaching that point and again on leaving it.  Anything else falls back
	 to identity, which is what an unwrapped comparison would have meant."
	anObject isNumber ifFalse: [ ^ super = anObject ].
	boundaries add: anObject.
	boundaries add: anObject + 1.
	^ value = anObject!

hash
	^ value hash! !

!McCursorProbe methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McCursorProbe on: '.
	value printOn: aStream! !

!McCursorProbe methodsFor: 'forwarding'!
adaptToNumber: aNumber andSend: aSelector
	"A comparison written the other way round -- `position <= cursor' -- or
	 any arithmetic mixing a number with the probe.  Pharo funnels every such
	 case through the adaptTo* family, which Object already answers, so it
	 would never reach doesNotUnderstand:; this is the one hook that catches
	 them all.  Where the answer would flip is not something the recording
	 protocol above covers, so the record is given up and the number is sent
	 the message against the plain position."
	trusted := false.
	^ aNumber perform: aSelector with: value!

doesNotUnderstand: aMessage
	"Something outside the comparison protocol is something the boundary
	 record cannot account for.  Forward it so behaviour is unchanged, and
	 give up the record so the editor restyles on every cursor move, as it did
	 before this class existed -- slower, never wrong."
	trusted := false.
	^ aMessage sendTo: value! !

Object subclass: #McRichEdit
	instanceVariableNames: 'space editorElement editorFrame container titleLabel statusLabel toggleLabel pathLabel pathTooltip darkMode buttonHandlers paletteCache cachedSource cachedParser lastStyledSource lastStyledCursor lastStyledBoundaries suspendCursorRestyle documentFile lastDocumentStamp watchProcess watchGeneration imageAdornmentCache imageCacheSource'
	classVariableNames: ''
	package: 'MalleableControl'!

!McRichEdit class methodsFor: 'opening'!
open
	^ self new openView! !

!McRichEdit class methodsFor: 'live reload'!
restartAllFileWatchers
	self allInstances do: [ :each |
		[ each startWatchingDocument ] on: Error do: [ :e | nil ] ]!

stopAllFileWatchers
	self allInstances do: [ :each |
		[ each stopWatchingDocument ] on: Error do: [ :e | nil ] ]! !

!McRichEdit class methodsFor: 'rendering'!
renderElement: anElement toFile: aPathString
	"Render anElement off-screen into a PNG at aPathString and answer its
	 extent.  The element is placed alone in a hidden space so it lays out
	 exactly as it would on screen."
	^ self renderElement: anElement toFile: aPathString extent: nil!

renderElement: anElement toFile: aPathString extent: anExtentOrNil
	"Render anElement into a PNG at aPathString.  When anExtentOrNil is nil
	 the space sizes to the element; otherwise the space is forced to that
	 extent and the element fills it."
	| sp form |
	sp := BlSpace new.
	anExtentOrNil
		ifNil: [
			sp root layout: BlLinearLayout horizontal.
			sp root constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
			anElement constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ] ]
		ifNotNil: [
			sp extent: anExtentOrNil.
			anElement constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ] ].
	sp root addChild: anElement.
	sp pulse. sp pulse. sp pulse.
	form := sp root exportAsForm.
	PNGReadWriter putForm: form onFileNamed: aPathString.
	^ anElement extent!

renderMarkdown: aString toFile: aPathString
	"Render a markdown string as it would appear in the editor and write it
	 to aPathString as a PNG.  Useful for quickly checking what a fragment
	 looks like without opening the full editor."
	| inst pal ed model styler |
	inst := self new.
	pal := inst palette.
	ed := BrEditor new.
	ed text: aString asRopedText.
	ed aptitude: (BrGlamorousRegularEditorAptitude new
		foreground: (pal at: 'text');
		fontSize: 14;
		background: (pal at: 'editorBg')).
	ed constraintsDo: [ :c | c horizontal exact: 600. c vertical fitContent ].
	ed padding: (BlInsets all: 16).
	model := ed editor.
	model useSyncStylerStrategy.
	styler := BlPluggableStyler new block: [ :aText |
		"Drive the parser and visitor directly rather than through
		 styleText:, which dereferences the instance's editorElement for
		 cursor position.  Here there is no live cursor -- force it to -1
		 so every element renders."
		[ | parser |
		  parser := McMarkdownParser parseSource: aText asString.
		  (McMarkdownStylerVisitor
			parser: parser text: aText cursor: -1
			palette: pal owner: nil) visit: parser root ]
			on: Error do: [ :e | "degrade to unstyled" ] ].
	ed styler: styler.
	^ self renderElement: ed toFile: aPathString extent: 620@400! !

!McRichEdit methodsFor: 'initialization'!
initialize
	"A fresh instance must be usable before openView runs -- palette
	 branches on darkMode, and a nil there is not a boolean."
	super initialize.
	darkMode := false.
	paletteCache := nil.
	suspendCursorRestyle := false.
	watchGeneration := 0.
	self invalidateStyleState.
	self resetImageAdornmentCache.
	buttonHandlers := Dictionary new! !

!McRichEdit methodsFor: 'images - adornment pool'!
imageAdornmentCache
	"Brick's pooled caches for image elements in the current document, keyed
	 per image occurrence by McMarkdownInlineStyler>>imageCacheKeyFor:.

	 It lives here rather than in the styler because a styler is built and
	 discarded once per block per restyle; only the editor is around long
	 enough for a caret step to find the previous pass's elements still there.
	 Nothing in it is shared between occurrences -- the key carries the
	 document position -- so no BlElement is ever asked for two parents."
	^ imageAdornmentCache ifNil: [ imageAdornmentCache := Dictionary new ]!

resetImageAdornmentCache
	"Drop every pooled element.

	 A fresh dictionary rather than removeAll:, because an adornment attribute
	 from the previous pass may still hold the old one through Brick's
	 withCache:key:.  Rotating leaves that attribute reading its own dead pool
	 until it is replaced, which is harmless; emptying in place would let it
	 refill the live pool with elements the reset was meant to retire."
	imageAdornmentCache := Dictionary new.
	imageCacheSource := nil!

noteImageCacheSource: aString
	"Rotate the pool when the document text has changed.

	 An edit moves every image after it, and a key carries the position, so
	 stale entries would simply never be hit again -- rotating is what keeps
	 the pool the size of the document's images rather than the size of the
	 edit history.  A cursor-only restyle passes the same source and keeps the
	 pool, which is the case the pool exists for."
	(imageCacheSource notNil and: [ imageCacheSource = aString ]) ifTrue: [ ^ self ].
	imageAdornmentCache := Dictionary new.
	imageCacheSource := aString! !

!McRichEdit methodsFor: 'palette'!
palette
	"The named colours of the current mode, built once and then handed out
	 unchanged.  The styler asks for the palette on every restyle, and
	 rebuilding eighteen Colors from hex strings per keystroke is pure
	 waste.  Sharing one instance is safe because nothing writes to it:
	 every consumer reads it through a paletteAt: that answers a default
	 for a missing key."
	^ paletteCache ifNil: [ paletteCache := self buildPalette ]!

darkMode: aBoolean
	"Switch modes, dropping the palette that was built for the old one."
	darkMode = aBoolean ifTrue: [ ^ self ].
	darkMode := aBoolean.
	paletteCache := nil.
	"A pooled image element carries the old mode's frame and caption colours
	 baked in, and the switch does not touch the source, so nothing else would
	 retire them."
	self resetImageAdornmentCache!

buildPalette
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
			at: 'link' put: (Color fromHexString: '#7fbdff');
			at: 'deadLink' put: (Color fromHexString: '#ff6b6b');
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
			at: 'link' put: (Color fromHexString: '#315fbd');
			at: 'deadLink' put: (Color fromHexString: '#b42318');
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
	| editorModel styler headerRow toggleButton scrollbar |
	self stopWatchingDocument.
	darkMode := false.
	paletteCache := nil.
	documentFile := self demoFile.
	lastDocumentStamp := self documentStamp.
	self invalidateStyleState.
	self resetImageAdornmentCache.

	space := BlSpace new.
	space title: 'Rich Edit — Prototype'.
	space extent: 700@540.

	container := BlElement new.
	container layout: BlLinearLayout vertical.
	container constraintsDo: [:c | c horizontal matchParent. c vertical matchParent].
	container padding: (BlInsets all: 24).

	"Header row: path badge + title + toggle.  Keeping the badge first gives
	 its tooltip the largest useful placement area to the right."
	headerRow := BlElement new.
	headerRow layout: BlLinearLayout horizontal.
	headerRow constraintsDo: [:c | c horizontal matchParent. c vertical fitContent].
	headerRow margin: (BlInsets bottom: 16).

	titleLabel := BrLabel new.
	titleLabel constraintsDo: [:c | c horizontal matchParent].

	"The path is boxed so it reads as inspectable UI rather than header copy."
	pathLabel := BrLabel new.
	pathLabel aptitude: BrGlamorousLabelAptitude new.
	pathLabel padding: (BlInsets top: 4 right: 8 bottom: 4 left: 8).
	pathLabel margin: (BlInsets right: 14).
	pathLabel geometry: (BlRoundedRectangleGeometry cornerRadius: 4).
	pathLabel constraintsDo: [ :c |
		c horizontal fitContent.
		c vertical fitContent.
		c linear vertical alignCenter ].
	pathTooltip := BrGlamorousWithExplicitTooltipAptitude new.
	pathTooltip content: [ self pathTooltipContent ].
	pathLabel addAptitude: pathTooltip.
	self updatePathComponent.

	toggleLabel := BrLabel new.
	toggleLabel aptitude: BrGlamorousLabelAptitude new.
	toggleLabel text: ('Dark Mode' asRopedText fontSize: 13).
	toggleLabel margin: (BlInsets right: 8).
	toggleLabel constraintsDo: [:c | c linear vertical alignCenter].

	toggleButton := BrCheckbox new.
	toggleButton aptitude: BrGlamorousCheckboxAptitude new.
	toggleButton beNormalSize.
	toggleButton checked: false.
	toggleButton constraintsDo: [:c | c linear vertical alignCenter].
	toggleButton whenCheckedDo: [
		self darkMode: true. self applyPalette].
	toggleButton whenUncheckedDo: [
		self darkMode: false. self applyPalette].

	headerRow addChild: pathLabel.
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
	editorElement aptitude: (BrGlamorousRegularEditorAptitude new
		foreground: (self palette at: 'text');
		fontSize: 16;
		background: (self palette at: 'editorBg')).
	editorElement text: self documentContent asRopedText.
	editorElement constraintsDo: [:c |
		c horizontal matchParent.
		c vertical matchParent].
	editorElement padding: (BlInsets all: 16).

	scrollbar := BlVerticalScrollbarElement new beAlwaysVisible.
	scrollbar thumb: (BlElement new
		background: (Color gray alpha: 0.4);
		geometry: (BlRoundedRectangleGeometry cornerRadius: 3);
		constraintsDo: [:c | c horizontal exact: 6. c vertical matchParent]).
	scrollbar track: (BlElement new
		background: Color transparent;
		constraintsDo: [:c | c horizontal exact: 6. c vertical matchParent]).
	scrollbar constraintsDo: [:c |
		c ignoreByLayout.
		c horizontal exact: 10.
		c ignored horizontal alignRight.
		c ignored vertical alignBottom].
	scrollbar attachTo: editorElement.

	editorFrame addChild: editorElement.
	editorFrame addChild: scrollbar.

	editorModel := editorElement editor.
	editorModel useSyncStylerStrategy.

	"Cursor-driven restyling.  The handler does not restyle unconditionally:
	 see onCursorMoved for which moves can be answered from the last pass."
	editorModel when: BrTextEditorCursorMovedEvent do: [:e |
		self onCursorMoved].

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
	self startWatchingDocument.
	^ self!

applyPalette
	"Update all chrome from the current palette, then restyle editor text."
	| p |
	p := self palette.
	space enqueueTask: (BlTaskAction new action: [
		container background: (p at: 'containerBg').
		editorFrame
			background: (p at: 'editorBg');
			border: (BlBorder paint: (p at: 'editorBorder') width: 1).
		editorElement background: (p at: 'editorBg').
		titleLabel text: ('Rich Edit Prototype' asRopedText
			foreground: (p at: 'title');
			fontSize: 22;
			bold).
		toggleLabel text: ('Dark Mode' asRopedText
			foreground: (p at: 'status');
			fontSize: 13).
		pathLabel
			background: (p at: 'codeBg');
			border: (BlBorder paint: (p at: 'tableBorder') width: 1).
		pathLabel text: (self relativeDocumentPath asRopedText
			foreground: (p at: 'link');
			fontSize: 12).
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

!McRichEdit methodsFor: 'config'!
projectRoot
	"The project root directory.  Uses the McHome global set by
	 gt-install-startup, falling back to the working directory."
	^ ((Smalltalk at: #McHome ifAbsent: [ nil ])
		ifNil: [ FileLocator workingDirectory resolve ]
		ifNotNil: [ :path | path asFileReference ]) asAbsolute!

config
	"Answer a Dictionary of configuration values.  Evaluates mc-config.st
	 from the project root, falling back to mc-config.default.st.  The
	 file must answer a Dictionary whose keys and values are all strings;
	 anything else is rejected and the next candidate is tried."
	| root candidates |
	root := self projectRoot.
	candidates := #( 'mc-config.st' 'mc-config.default.st' ).
	candidates do: [ :name |
		| ref |
		ref := root / name.
		ref exists ifTrue: [
			[ | raw |
			  raw := OpalCompiler new source: ref contents; evaluate.
			  (self validateConfig: raw) ifTrue: [ ^ raw ] ]
				on: Error do: [ :e | "skip malformed config" ] ] ].
	^ Dictionary new!

validateConfig: anObject
	"Answer true only when anObject is a Dictionary mapping strings to
	 strings.  The config file is arbitrary Smalltalk, so the result must
	 be checked before it is trusted."
	(anObject isKindOf: Dictionary) ifFalse: [ ^ false ].
	anObject keysAndValuesDo: [ :key :value |
		(key isString and: [ value isString ]) ifFalse: [ ^ false ] ].
	^ true!

demoFile
	"The path of the markdown file to load, resolved from the config.
	 Relative paths are resolved against the project root."
	| raw ref |
	raw := self config at: 'demoFile' ifAbsent: [ 'samples/demo.md' ].
	ref := raw asFileReference.
	ref isAbsolute ifFalse: [ ref := self projectRoot / raw ].
	^ ref! !

!McRichEdit methodsFor: 'content'!
documentFile
	^ documentFile ifNil: [ documentFile := self demoFile ]!

documentContent
	| ref |
	ref := self documentFile.
	ref exists ifTrue: [ ^ ref contents ].
	^ '# Rich Edit

_No document found.  Expected: ' , ref pathString , '_
'!

demoContent
	"Load the demo document from the configured file.  Falls back to a
	 minimal placeholder if the file does not exist."
	| ref |
	ref := self demoFile.
	ref exists ifTrue: [ ^ ref contents ].
	^ '# Rich Edit

_No demo file found.  Expected: ' , ref pathString , '_
'! !

!McRichEdit methodsFor: 'document path'!
relativeDocumentPath
	^ [ (self documentFile relativeTo: self projectRoot) pathString ]
		on: Error
		do: [ :e | self documentFile basename ]!

updatePathComponent
	pathLabel ifNil: [ ^ self ].
	pathLabel text: (self relativeDocumentPath asRopedText
		foreground: (self palette at: 'link');
		fontSize: 12)!

pathTooltipContent
	"Use explicit content instead of the tooltip's text: convenience API.
	 The latter creates a menu item whose label is shortened to the available
	 anchor width; a fit-content text element retains the complete path."
	| label |
	label := BlTextElement new.
	label text: (self documentFile fullName asRopedText
		foreground: (self palette at: 'text');
		fontSize: 12).
	label constraintsDo: [ :c |
		c horizontal fitContent.
		c vertical fitContent ].
	label padding: (BlInsets top: 7 right: 9 bottom: 7 left: 9).
	label background: (self palette at: 'codeBg').
	label geometry: (BlRoundedRectangleGeometry cornerRadius: 4).
	label border: (BlBorder paint: (self palette at: 'tableBorder') width: 1).
	^ label!

openDocument: aFileReference
	"Switch documents deliberately.  Unlike an edit within one document, a
	 document switch should replace the rope and its undo history."
	| ref contents |
	ref := aFileReference asFileReference asAbsolute.
	(ref exists and: [ ref isFile ]) ifFalse: [
		^ self showStatus: 'File not found: ' , ref pathString ].
	contents := [ ref contents ] on: Error do: [ :e |
		^ self showStatus: 'Cannot read ' , ref pathString , ': ' , e messageText ].
	self stopWatchingDocument.
	documentFile := ref.
	lastDocumentStamp := self documentStamp.
	cachedSource := nil.
	cachedParser := nil.
	self invalidateStyleState.
	"Relative image targets resolve against the document's directory, so the
	 same key can mean a different file once the document changes."
	self resetImageAdornmentCache.
	editorElement text: contents asRopedText.
	self updatePathComponent.
	editorElement editor styleText.
	self showStatus: 'Opened ' , self relativeDocumentPath.
	self startWatchingDocument! !

!McRichEdit methodsFor: 'file watching'!
watchDelay
	^ Delay forMilliseconds: 500!

documentStamp
	| ref |
	ref := self documentFile.
	^ [ ref exists
		ifFalse: [ 'missing' ]
		ifTrue: [ ref modificationTime printString , '|' , ref size printString ] ]
		on: Error
		do: [ :e | 'unstampable' ]!

startWatchingDocument
	| generation |
	self stopWatchingDocument.
	watchGeneration := watchGeneration + 1.
	generation := watchGeneration.
	lastDocumentStamp := self documentStamp.
	watchProcess := [
		[ generation = watchGeneration
			and: [ space notNil and: [ space isOpened ] ] ] whileTrue: [
			self watchDelay wait.
			generation = watchGeneration ifTrue: [
				[ self checkDocumentForChanges ] on: Error do: [ :e | nil ] ] ] ]
		forkAt: Processor userBackgroundPriority!

stopWatchingDocument
	watchGeneration := (watchGeneration ifNil: [ 0 ]) + 1.
	watchProcess ifNotNil: [
		watchProcess terminate.
		watchProcess := nil ]!

checkDocumentForChanges
	| stamp expectedFile |
	stamp := self documentStamp.
	stamp = lastDocumentStamp ifTrue: [ ^ self ].
	lastDocumentStamp := stamp.
	expectedFile := self documentFile.
	space ifNotNil: [
		space enqueueTask: (BlTaskAction new action: [
			documentFile = expectedFile ifTrue: [ self reloadDocumentFromDisk ] ]) ]!

reloadDocumentFromDisk
	| contents size |
	self documentFile exists ifFalse: [
		^ self showStatus: 'File removed: ' , self documentFile pathString ].
	contents := [ self documentFile contents ] on: Error do: [ :e |
		^ self showStatus: 'Cannot reload ' , self documentFile pathString ].
	contents = editorElement editor text asString ifTrue: [ ^ self ].
	size := editorElement editor text size.
	self replaceFrom: 1 to: size with: contents.
	self showStatus: 'Reloaded ' , self relativeDocumentPath! !

!McRichEdit methodsFor: 'accessing'!
editorElement
	^ editorElement! !

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
	 than take the editor down with it.

	 The cursor is handed to the visitor wrapped in an McCursorProbe, which
	 answers every comparison exactly as the plain integer would while
	 recording the positions at which the answer would have flipped.  That
	 record is what onCursorMoved later consults to decide whether a move
	 can change the projection at all."
	| parser probe |
	probe := McCursorProbe on: cursorPos.
	[ parser := self parserFor: str.
	  (McMarkdownStylerVisitor
		parser: parser
		text: aText
		cursor: probe
		palette: self palette
		owner: self) visit: parser root.
	  self noteStyledSource: str cursor: cursorPos boundaries: probe boundaries ]
		on: Error
		do: [ :e |
			self invalidateStyleState.
			self showStatus: 'markdown: ' , e messageText asString ]!

parserFor: aString
	"The parser for aString, reusing the last one when the source has not
	 changed.  Two full restyles run for every keystroke -- one from the text
	 modification, one from the cursor move it causes -- and a cursor move on
	 its own restyles too, so the same string is parsed over and over.

	 Reuse is safe because styling changes no parsing result or AST node.  The
	 visitor reads ranges, line intervals and inline maps; line-interval lookup
	 increments only the parser's probeCount diagnostic.  The rope it decorates
	 is the only rendering state it mutates.  Holding on
	 to the parser also keeps its memoised inline sources and index maps,
	 which is the larger half of the saving.

	 The assignment order matters: a parse that raises leaves both variables
	 on the previous source rather than pairing a stale parser with a new key."
	(cachedSource notNil and: [ cachedSource == aString or: [ cachedSource = aString ] ])
		ifTrue: [ ^ cachedParser ].
	"This is also the exact point at which image occurrence keys may have
	 changed.  Sharing the cache-miss decision avoids another whole-document
	 string comparison on cursor-only restyles."
	self noteImageCacheSource: aString.
	cachedParser := McMarkdownParser parseSource: aString.
	cachedSource := aString.
	^ cachedParser!

cursorPosition
	"Return the 0-based cursor position, or -1 if no cursor."
	| pos |
	pos := -1.
	editorElement editor cursors do: [:c | pos := c position].
	^ pos! !

!McRichEdit methodsFor: 'styling - restyle gating'!
onCursorMoved
	"A cursor move restyles only when it can change what is drawn.

	 Every projection decision in the pipeline is one of `cursor is near this
	 range' -- McMarkdownStylerVisitor>>isNear: and
	 McMarkdownInlineStyler>>isNearSource:to: are the only places the cursor
	 is read at all.  Each such test flips its answer at one or two known
	 positions, and McCursorProbe collected exactly those positions during the
	 last pass.  If the cursor has moved without crossing one of them, every
	 test on the path taken last time answers the same way, so the same path
	 is taken and the same attributes are produced -- the restyle would be a
	 full reparse and a full relayout for an identical result.

	 This is what removes the second restyle per keystroke.  Typing runs the
	 styler once from the text modification and once from the cursor move that
	 follows it; the second one is dropped here unless the caret has just
	 crossed a delimiter boundary."
	self cursorRestyleNeeded ifFalse: [ ^ self ].
	editorElement editor styleText!

cursorRestyleNeeded
	"Whether the cursor's current position needs a fresh styling pass; see
	 onCursorMoved for why the boundary set answers this exactly."
	| position currentText low high |
	suspendCursorRestyle ifTrue: [ ^ false ].
	lastStyledSource ifNil: [ ^ true ].
	lastStyledCursor ifNil: [ ^ true ].
	lastStyledBoundaries ifNil: [ ^ true ].
	position := self cursorPosition.
	position = lastStyledCursor ifTrue: [ ^ false ].
	"A cursor event can arrive before the modification that caused it has been
	 applied -- a backspace moves the caret first and deletes afterwards -- so
	 the source is compared, not assumed.  The size check keeps the common
	 navigation case off the string comparison."
	currentText := editorElement editor text.
	lastStyledSource size = currentText size ifFalse: [ ^ true ].
	lastStyledSource = currentText asString ifFalse: [ ^ true ].
	low := position min: lastStyledCursor.
	high := position max: lastStyledCursor.
	^ lastStyledBoundaries anySatisfy: [ :each | each > low and: [ each <= high ] ]!

noteStyledSource: aString cursor: anInteger boundaries: aSetOrNil
	"Record what the last completed pass was a projection of.  A nil boundary
	 set means the probe saw something it could not account for, and every
	 later cursor move restyles."
	lastStyledSource := aString.
	lastStyledCursor := anInteger.
	lastStyledBoundaries := aSetOrNil!

invalidateStyleState
	"Forget the last pass, so the next cursor move restyles unconditionally."
	lastStyledSource := nil.
	lastStyledCursor := nil.
	lastStyledBoundaries := nil! !

!McRichEdit methodsFor: 'text mutation'!
replaceFrom: start to: stop with: aString
	"Replace the 1-based, inclusive document range start..stop with aString.

	 The range is mutated in place through the editor's own deleter and
	 inserter rather than by handing the editor a whole new rope.  Assigning
	 through text: reaches restoreText:, which throws the segment collector
	 away and rebuilds every segment of the document -- for a checkbox toggle
	 that is one character of edit paid for with a full reconstruction, and it
	 takes the undo history and the caret's relationship to the text with it.
	 The deleter and inserter edit the rope, move the cursors that sit after
	 the edit by the right amount, and leave the rest of the model standing.

	 Both operations are cursor coordinates: index n means `after n
	 characters', so the 1-based range start..stop is start - 1 to stop.

	 The two halves run with styling suspended so the intermediate state --
	 the document with the old text gone and the new text not yet in -- is
	 never parsed, and the cursor moves they cause are not answered either.
	 One restyle at the end covers the whole edit."
	| editor size from to |
	editor := editorElement editor.
	size := editor text size.
	from := ((start - 1) max: 0) min: size.
	to := (stop max: from) min: size.
	suspendCursorRestyle := true.
	[ editor disableStyleTextWhenModifiedDuring: [
		to > from ifTrue: [ editor deleter from: from to: to; delete ].
		aString isEmpty ifFalse: [
			editor inserter
				withoutSelectionDelete;
				at: from;
				string: aString;
				insert ] ] ]
		ensure: [ suspendCursorRestyle := false ].
	self invalidateStyleState.
	editor styleText!

performButtonNamed: aLabel
	| handler |
	handler := buttonHandlers at: aLabel ifAbsent: [ nil ].
	handler
		ifNil: [ self showStatus: 'No handler for: ' , aLabel ]
		ifNotNil: [ handler value ]! !
