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

"
McInstantScrollListener -- mouse-wheel scrolling without the glide.

BrEditor is a BlInfiniteElement, and every BlInfiniteElement installs a
BlInfiniteMouseScrollListener whose last act on a wheel event is
`smoothScrollBy:'.  That routes through BlScrollFlinger, which turns the
notch into an animation: with no drag velocity the duration is
((|delta| / height) + 1) * 300 ms, eased by a BlQuinticInterpolator and
capped at two seconds.  A second notch arriving mid-animation restarts the
task from wherever the first had reached, so a run of notches reads as
momentum that keeps travelling after the fingers stop.  The effect is
hardcoded in that handler -- there is no preference behind it.

This subclass keeps the wheel arithmetic and the nested-scrolling
negotiation of its superclass, which is where the interesting behaviour
lives, and changes only the final move to `scrollBy:' so the delta is
applied in the same frame.
"!

BlInfiniteMouseScrollListener subclass: #McInstantScrollListener
	instanceVariableNames: ''
	classVariableNames: 'ScrollFactor'
	package: 'MalleableControl'!

!McInstantScrollListener class methodsFor: 'installing'!
attachTo: anElement
	"Swap the inertial wheel handler BlInfiniteElement installs for this one.
	 Removal is by kind, so re-running this on an element already converted
	 replaces rather than stacks."
	anElement removeEventHandlersSuchThat: [ :each |
		each isKindOf: BlInfiniteMouseScrollListener ].
	anElement addEventHandler: self new.
	^ anElement! !

!McInstantScrollListener methodsFor: 'event handling'!
mouseWheelEvent: anEvent
	"As BlInfiniteMouseScrollListener>>mouseWheelEvent:, but applied at once and
	 with the delta recalibrated -- see scrollDeltaY:of: for why the stock
	 factor of ten cannot survive the move off the animation.

	 doScrollUp:/doScrollDown: are the superclass's: they may rewrite the event
	 vector to hand a parent its share of the scroll, and they mark the event
	 consumed, so both must run before the delta is read."
	| dX dY element isVertical |
	anEvent vector isZero ifTrue: [ ^ self ].
	element := anEvent currentTarget.
	isVertical := anEvent isPrimarilyHorizontal not.
	dX := isVertical
		ifTrue: [ 0 ]
		ifFalse: [ anEvent vector length * anEvent vector x sign ].
	dY := isVertical
		ifTrue: [ (anEvent isScrollDown and: [ element canScrollDown ])
				ifTrue: [ self doScrollDown: anEvent ]
				ifFalse: [ (anEvent isScrollUp and: [ element canScrollUp ])
						ifTrue: [ self doScrollUp: anEvent ]
						ifFalse: [ 0 ] ] ]
		ifFalse: [ 0 ].
	self
		applyScroll: (self scrollDeltaX: dX of: anEvent)
			@ (self scrollDeltaY: dY of: anEvent)
		to: element!

applyScroll: aPoint to: anElement
	"Not `anElement scrollBy:'.  BrEditor overrides that, and despite a comment
	 promising pixels it dispatches a BrScrollByWish whose handler reads the
	 delta as a COUNT OF SEGMENTS:

		position := aWish delta y.
		position := position positive
			ifTrue: [ self lastVisibleSegment ... aSegment index + position ceiling ]
			ifFalse: [ self firstVisibleSegment ... aSegment index + position floor ].
		self scrollToPosition: position

	 -- so a pixel distance becomes a line count, and scrollToPosition: then
	 snaps the viewport to that segment's boundary.  Over uniform text the snap
	 is a line high and passes for smooth scrolling; over a segment carrying an
	 image it is the whole image in one step.

	 The animated path never went through it: BlScrollFlinger reaches
	 scrollVerticallyBy: and scrolls in pixels.  scrollByInternal:from: is that
	 same pixel path with the layout bookkeeping BlInfiniteElement>>scrollBy:
	 would have done, and neither BrEditor nor BrEditorElement overrides it."
	| dX dY |
	dX := anElement layout canScrollHorizontally ifTrue: [ aPoint x ] ifFalse: [ 0 ].
	dY := anElement layout canScrollVertically ifTrue: [ aPoint y ] ifFalse: [ 0 ].
	(dX isZero and: [ dY isZero ]) ifTrue: [ ^ self ].
	anElement scrollByInternal: dX @ dY from: nil! !

!McInstantScrollListener class methodsFor: 'scaling'!
scrollFactor
	"Multiplier applied to the distance the host layer already computed.
	 One means: scroll exactly as far as the OS asked.  Adjustable live --
	 McInstantScrollListener scrollFactor: 1.5 -- so the feel can be tuned
	 without a reload."
	^ ScrollFactor ifNil: [ 1 ]!

scrollFactor: aNumber
	ScrollFactor := aNumber! !

!McInstantScrollListener methodsFor: 'scaling'!
scrollDeltaX: aDelta of: anEvent
	"The shift modifier's slower horizontal step is the stock handler's and is
	 kept; the tenfold is not, for the reason scrollDeltaY:of: gives."
	^ (anEvent isPixelBased not and: [ anEvent modifiers isShift ])
		ifTrue: [ aDelta * self class shiftWheelScrollSpeed * self class scrollFactor ]
		ifFalse: [ aDelta * self class scrollFactor ]!

scrollDeltaY: aDelta of: anEvent
	"The distance arrives already computed.  BlRustWindowingHostSpace>>
	 visitMouseWheelEvent: divides a PixelDelta by the scale factor, and
	 multiplies a LineDelta by the scale factor and by
	 RustWindowingLibrary mouseWheelScrollSpeed, 15 here.  Either way what
	 reaches this handler is the distance the OS wants scrolled, so the
	 factor is one.

	 The stock handler multiplies by ten on top of that.  It survives only
	 because smoothScrollBy:during:with: calls `scroller startScrollAt: 0@0
	 by: aDeltaPoint', REPLACING the scroll in flight rather than accumulating
	 onto it, so each event in a burst discards most of what the previous had
	 left to travel and the tenfold is never realised in full.  Applied in one
	 frame there is nothing to truncate it.

	 Measured on this machine, wheel events arrive as line deltas ramping with
	 the OS's own acceleration: 3.0 for the smallest nudge, up to 198.0 mid
	 gesture, a firm flick totalling about 468 across five events in 135ms.
	 Against a 421px viewport that is a screen and a tenth per flick at a
	 factor of one -- and eleven screens at the stock ten."
	^ aDelta * self class scrollFactor! !

"
McPixelScrollEditor -- an editor whose scrollbar is measured in pixels.

BrEditor answers the three scrollbar metrics in SEGMENTS:

	computeVerticalScrollRange   ^ self lineCount
	computeVerticalScrollExtent  ^ lastVisibleSegment index - firstVisibleSegment index + 1
	computeVerticalScrollOffset  ^ firstVisibleSegment index - 1

The thumb is drawn extent/range of the track, so its length is the fraction
of the document's LINES that are on screen.  While every line is the same
height that fraction tracks the fraction of the document's height, and the
bar behaves.  Put an image in one segment and it stops: the viewport now
holds one segment instead of eighteen, the extent collapses, and the thumb
shrinks -- then grows again on the way back to text.  The document never
changed size; the number of lines that fit did.

So the metrics are answered here in pixels instead.  The extent is the
viewport's height, and the range is the document's height -- which the
recycling layout is built precisely to avoid computing, since only the
laid-out segments have ever been measured.  The estimate stands in: every
segment that has been laid out contributes its measured height, and every
segment that has not contributes the median of those that have.

The median, not the mean, because one image among two hundred text lines
drags a mean upward and would make the bar wrong everywhere.  And the cache
only ever grows, so a tall segment keeps counting toward the total after it
is recycled out of view -- which is what stops the bar resizing as it
scrolls past.  The estimate is therefore wrong only for segments never yet
seen, converges as they are, and then holds still.
"!

BrEditor subclass: #McPixelScrollEditor
	instanceVariableNames: 'segmentHeights typicalHeight totalHeight'
	classVariableNames: ''
	package: 'MalleableControl'!

!McPixelScrollEditor methodsFor: 'initialization'!
initialize
	super initialize.
	segmentHeights := Dictionary new.
	"BrEditor clears its own lineCount on both of these; the measurements are
	 keyed by segment index, so they are stale for the same reason."
	self viewModel when: BrEditorTextChanged do: [ :anEvent |
		self forgetSegmentHeights ].
	self editor when: BrTextEditorModifiedEvent do: [ :anEvent |
		self forgetSegmentHeights ]! !

!McPixelScrollEditor methodsFor: 'measuring'!
forgetSegmentHeights
	segmentHeights := Dictionary new.
	self invalidateHeightEstimates!

heightAboveSegment: anIndex
	| typical sum |
	typical := self typicalSegmentHeight.
	sum := 0.
	1 to: anIndex - 1 do: [ :each |
		sum := sum + (segmentHeights at: each ifAbsent: [ typical ]) ].
	^ sum!

invalidateHeightEstimates
	typicalHeight := nil.
	totalHeight := nil!

recordHeight: aHeight forSegment: anIndex
	"Kept apart from recordLaidOutHeights so the estimate can be exercised
	 without a laid-out editor."
	(segmentHeights at: anIndex ifAbsent: [ nil ]) = aHeight ifTrue: [ ^ self ].
	segmentHeights at: anIndex put: aHeight.
	self invalidateHeightEstimates!

recordLaidOutHeights
	"Only the children the layout is currently holding can be measured, which
	 is the whole premise of a recycling layout.  Their heights are kept."
	| layout |
	layout := self layout.
	layout ifNil: [ ^ self ].
	1 to: layout childrenCount do: [ :each |
		| child |
		child := layout childAt: each.
		((child respondsTo: #segment) and: [ child height > 0 ])
			ifTrue: [
				child segment ifNotNil: [ :segment |
					self recordHeight: child height forSegment: segment index ] ] ]!

segmentHeights
	^ segmentHeights!

totalContentHeight
	^ totalHeight ifNil: [ totalHeight := self computeTotalContentHeight ]!

typicalSegmentHeight
	"The median of what has been measured.  A mean would be dragged upward by
	 a single image and make the estimate wrong for every text line."
	^ typicalHeight ifNil: [ typicalHeight := self computeTypicalSegmentHeight ]! !

!McPixelScrollEditor methodsFor: 'measuring - private'!
computeTotalContentHeight
	| typical sum |
	typical := self typicalSegmentHeight.
	sum := 0.
	1 to: self lineCount do: [ :each |
		sum := sum + (segmentHeights at: each ifAbsent: [ typical ]) ].
	^ sum!

computeTypicalSegmentHeight
	| sorted |
	segmentHeights isEmpty ifTrue: [ ^ 0 ].
	sorted := segmentHeights values asSortedCollection asArray.
	^ sorted at: sorted size + 1 // 2! !

!McPixelScrollEditor methodsFor: 'scrolling'!
computeVerticalScrollExtent
	"Pixels of document on screen."
	^ self height!

computeVerticalScrollOffset
	"Pixels of document above the viewport: the segments before the first
	 visible one, plus however far into that one we have scrolled.  A child
	 whose top has passed above the viewport has a negative position."
	| child segment |
	self recordLaidOutHeights.
	segmentHeights isEmpty ifTrue: [ ^ 0 ].
	child := self layout
		findFirstVisibleChildClosestToStartCompletelyVisible: true
		acceptPartiallyVisible: true.
	child ifNil: [ ^ 0 ].
	segment := child segment.
	segment ifNil: [ ^ 0 ].
	^ 0 max: (self heightAboveSegment: segment index) - child position y!

computeVerticalScrollRange
	"Pixels of document in total.  Never less than the extent, so the thumb
	 cannot be asked to be longer than its track."
	self recordLaidOutHeights.
	segmentHeights isEmpty ifTrue: [ ^ self computeVerticalScrollExtent ].
	^ self totalContentHeight max: self computeVerticalScrollExtent! !

Object subclass: #McRichEdit
	instanceVariableNames: 'space editorElement editorFrame container titleLabel statusLabel toggleLabel trustLabel trustCheckbox pathLabel pathTooltip searchBar searchInput searchCountLabel searchHighlightCheckbox searchWrapCheckbox commandKeymap darkMode buttonHandlers paletteCache cachedSource cachedParser lastStyledSource lastStyledCursor lastStyledBoundaries stylingSuspensionDepth pendingEditDescriptor renderSnapshot reconciler lastRenderWasPartial documentFile lastDocumentStamp watchProcess watchGeneration imageAdornmentCache imageCacheSource searchSession'
	classVariableNames: ''
	package: 'MalleableControl'!

!McRichEdit class methodsFor: 'opening'!
activeInstance
	"The editor whose window is open, or nil.

	 Kept as a selector because elisp/mc-rich-edit.el reaches the live editor
	 through it.  It used to memoize into a CurrentInstance class variable that
	 nothing ever cleared, so once the window was closed it went on answering a
	 dead editor and the Emacs search and render commands aimed at a window
	 that no longer existed."
	^ McWindow liveInstanceOf: self!

open
	"A remote caller (notably Emacs over NATS) can successfully create a Bloc
	 space while another GT window retains native focus.  Reuse and foreground
	 the live editor so the command has an observable result instead of quietly
	 stacking invisible prototype windows behind the current space.

	 Deliberately no refreshView: the editor may be holding unsaved text, and
	 reloading it from disk on a second click would discard that without
	 asking.  Reload is a deliberate act -- the file watcher and the reload
	 command already offer it."
	^ (McWindow front: self) ifNil: [ self new openView; yourself ]! !

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
	stylingSuspensionDepth := 0.
	pendingEditDescriptor := nil.
	renderSnapshot := nil.
	reconciler := McMarkdownReconciler new.
	lastRenderWasPartial := false.
	watchGeneration := 0.
	self invalidateStyleState.
	self resetImageAdornmentCache.
	searchSession := nil.
	commandKeymap := McCommandKeymap richEditDefaults.
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
	"Source edits no longer rotate the pool.  A retained owner supplies a
	 lineage/local-occurrence key, so an edit before the Images block still
	 addresses the same live element.  Explicit document/theme resets retain
	 the lifecycle boundary for reclamation and stale-resource correctness."
	imageCacheSource := aString!

imageAdornmentCacheKeyFor: aLink documentPosition: aDocumentPosition
	"A resource belongs to its structural owner, not an absolute document
	 offset.  The local offset distinguishes duplicate images in one owner;
	 the lineage survives an unrelated insertion before that owner."
	| ownerNode localOffset |
	renderSnapshot ifNil: [ ^ nil ].
	ownerNode := renderSnapshot rootChildContainingPosition: aDocumentPosition.
	ownerNode ifNil: [ ^ nil ].
	ownerNode lineageId ifNil: [ ^ nil ].
	localOffset := aDocumentPosition - ownerNode sourceRange first.
	^ Array
		with: ownerNode lineageId
		with: localOffset
		with: aLink target
		with: aLink caption! !

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
			at: 'searchMatch' put: ((Color fromHexString: '#f9c74f') alpha: 0.35);
			at: 'searchActiveMatch' put: (Color fromHexString: '#f9c74f');
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
			at: 'evalTagText' put: (Color fromHexString: '#ffffff');
			at: 'langPython' put: (Color fromHexString: '#3572a5');
			at: 'langR' put: (Color fromHexString: '#1f65b7');
			at: 'langJulia' put: (Color fromHexString: '#9558b2');
			at: 'langSmalltalk' put: (Color fromHexString: '#c05621');
			at: 'langOjs' put: (Color fromHexString: '#5f6b7a');
			at: 'langDefault' put: (Color fromHexString: '#7f5af0');
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
			at: 'searchMatch' put: ((Color fromHexString: '#f9c74f') alpha: 0.35);
			at: 'searchActiveMatch' put: (Color fromHexString: '#f9c74f');
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
			at: 'evalTagText' put: (Color fromHexString: '#ffffff');
			at: 'langPython' put: (Color fromHexString: '#3572a5');
			at: 'langR' put: (Color fromHexString: '#1f65b7');
			at: 'langJulia' put: (Color fromHexString: '#9558b2');
			at: 'langSmalltalk' put: (Color fromHexString: '#c05621');
			at: 'langOjs' put: (Color fromHexString: '#5f6b7a');
			at: 'langDefault' put: (Color fromHexString: '#7f5af0');
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

	"Trust gates every evaluation in this document -- the inline expressions
	 and the Run buttons under fenced blocks alike.  It sits beside Dark Mode
	 because it is the other thing about the view that is set per document,
	 and it carries a visible label for the same reason Dark Mode does: an
	 unlabelled checkbox beside a labelled one reads as a second, nameless
	 setting."
	trustLabel := BrLabel new.
	trustLabel aptitude: BrGlamorousLabelAptitude new.
	trustLabel text: ('Trust' asRopedText fontSize: 13).
	trustLabel margin: (BlInsets right: 8).
	trustLabel constraintsDo: [:c | c linear vertical alignCenter].

	trustCheckbox := BrCheckbox new.
	trustCheckbox aptitude: BrGlamorousCheckboxAptitude new.
	trustCheckbox beNormalSize.
	trustCheckbox checked: self isTrustedDocument.
	trustCheckbox margin: (BlInsets right: 14).
	trustCheckbox constraintsDo: [:c | c linear vertical alignCenter].
	trustCheckbox whenCheckedDo: [ self trustDocument: true ].
	trustCheckbox whenUncheckedDo: [ self trustDocument: false ].

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
	headerRow addChild: trustLabel.
	headerRow addChild: trustCheckbox.
	headerRow addChild: toggleLabel.
	headerRow addChild: toggleButton.

	"Editor inside a bordered frame."
	editorFrame := BlElement new.
	editorFrame layout: BlFrameLayout new.
	editorFrame constraintsDo: [:c | c horizontal matchParent. c vertical matchParent].
	editorFrame geometry: (BlRoundedRectangleGeometry cornerRadius: 6).
	editorFrame clipChildren: true.

	editorElement := McPixelScrollEditor new.
	editorElement aptitude: (BrGlamorousRegularEditorAptitude new
		foreground: (self palette at: 'text');
		fontSize: 16;
		background: (self palette at: 'editorBg')).
	editorElement text: self documentContent asRopedText.
	editorElement constraintsDo: [:c |
		c horizontal matchParent.
		c vertical matchParent].
	editorElement padding: (BlInsets all: 16).
	McInstantScrollListener attachTo: editorElement.

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
	commandKeymap installContext: #editor on: editorElement owner: self.
	searchBar := self buildSearchBar.

	"Status bar for button feedback."
	statusLabel := BlTextElement new.
	statusLabel text: ('Ready' asRopedText fontSize: 13; foreground: (self palette at: 'status')).
	statusLabel constraintsDo: [:c | c horizontal matchParent. c vertical exact: 20].
	statusLabel margin: (BlInsets top: 10).

	"Button handler table."
	self registerDefaultButtons.

	container addChild: headerRow.
	container addChild: searchBar.
	container addChild: editorFrame.
	container addChild: statusLabel.

	space root addChild: container.
	self applyPalette.
	space show.
	self startWatchingDocument.
	^ self!

buildSearchBar
	| bar previous next close highlightLabel wrapLabel |
	bar := BlElement new.
	bar layout: BlLinearLayout horizontal.
	bar visibility: BlVisibility gone.
	bar margin: (BlInsets bottom: 10).
	bar padding: (BlInsets all: 6).
	bar background: (self palette at: 'codeBg').
	bar border: (BlBorder paint: (self palette at: 'tableBorder') width: 1).
	bar geometry: (BlRoundedRectangleGeometry cornerRadius: 5).
	bar constraintsDo: [ :c | c horizontal matchParent. c vertical exact: 42 ].

	searchInput := BrEditor new.
	searchInput aptitude: BrGlamorousRegularEditorAptitude new.
	searchInput constraintsDo: [ :c | c horizontal matchParent. c vertical exact: 30 ].
	searchInput editor when: BrTextEditorModifiedEvent do: [ :event |
		self searchFor: searchInput text asString ].
	commandKeymap installContext: #searchInput on: searchInput owner: self.

	searchCountLabel := BrLabel new.
	searchCountLabel constraintsDo: [ :c | c horizontal exact: 72. c linear vertical alignCenter ].
	previous := BrButton new
		label: 'Previous';
		aptitude: BrGlamorousButtonWithLabelAptitude new;
		action: [ self previousSearch ];
		yourself.
	next := BrButton new
		label: 'Next';
		aptitude: BrGlamorousButtonWithLabelAptitude new;
		action: [ self nextSearch ];
		yourself.
	searchHighlightCheckbox := BrCheckbox new.
	searchHighlightCheckbox aptitude: BrGlamorousCheckboxAptitude new.
	searchHighlightCheckbox checked: true.
	searchHighlightCheckbox whenCheckedDo: [ self highlightAllSearchMatches: true ].
	searchHighlightCheckbox whenUncheckedDo: [ self highlightAllSearchMatches: false ].

  highlightLabel := BrLabel new
      aptitude: BrGlamorousLabelAptitude new;
      text: ('highlight' asRopedText fontSize: 13);
      margin: (BlInsets right: 8);
      constraintsDo: [ :c | c linear vertical alignCenter ];
      yourself.

	searchWrapCheckbox := BrCheckbox new.
	searchWrapCheckbox aptitude: BrGlamorousCheckboxAptitude new.
	searchWrapCheckbox checked: true.
	searchWrapCheckbox whenCheckedDo: [ self wrapSearch: true ].
	searchWrapCheckbox whenUncheckedDo: [ self wrapSearch: false ].
	wrapLabel := BrLabel new
      aptitude: BrGlamorousLabelAptitude new;
      text: ('wrap' asRopedText fontSize: 13);
      margin: (BlInsets right: 8);
      constraintsDo: [ :c | c linear vertical alignCenter ];
      yourself.

	close := BrButton new
		label: 'Close';
		aptitude: BrGlamorousButtonWithLabelAptitude new;
		action: [ self closeSearch ];
		yourself.
	bar addChild: searchInput.
	bar addChild: searchCountLabel.
	bar addChild: previous.
	bar addChild: next.
	bar addChild: searchHighlightCheckbox.
	bar addChild: highlightLabel.
	bar addChild: searchWrapCheckbox.
	bar addChild: wrapLabel.
	bar addChild: close.
	^ bar!

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
		searchBar ifNotNil: [
			searchBar
				background: (p at: 'codeBg');
				border: (BlBorder paint: (p at: 'tableBorder') width: 1) ].
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

documentKey
	"What trust is recorded against: the document's full path, or nil for a
	 document that has never been saved.  A buffer with no name cannot be
	 trusted, because there is nothing stable to record the decision against."
	^ [ self documentFile ifNotNil: [ :f | f fullName ] ]
		on: Error
		do: [ :e | nil ]!

isTrustedDocument
	"Asked by the styler, once per inline block per restyle."
	^ [ (Smalltalk at: #McCodeEvaluator) isTrusted: self documentKey ]
		on: Error
		do: [ :e | false ]!

trustDocument: aBoolean
	"Turn evaluation on or off for this document and re-render.

	 Untrusting does not drop cached results: turning trust back on should
	 not cost a second run of everything.  It does re-render, so the results
	 stop being shown at once."
	| evaluator |
	evaluator := Smalltalk at: #McCodeEvaluator ifAbsent: [ nil ].
	evaluator ifNil: [ ^ self ].
	aBoolean
		ifTrue: [ evaluator trust: self documentKey ]
		ifFalse: [ evaluator untrust: self documentKey ].
	editorElement ifNotNil: [
		[ editorElement editor styleText ] on: Error do: [ :e | nil ] ]!

updateTrustComponent
	"Trust is per document, so switching documents must re-read it rather
	 than carry the previous document's answer across."
	trustCheckbox ifNil: [ ^ self ].
	trustCheckbox checked: self isTrustedDocument!

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
	self updateTrustComponent.
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

!McRichEdit methodsFor: 'initialization - editor attachment'!
attachToEditor: anEditorElement
	"Attach an existing editor without creating window chrome; tests and the
	 retained-rendering state can use the same initialization seam."
	editorElement := anEditorElement.
	space := anEditorElement space.
	self invalidateStyleState.
	^ self! !

!McRichEdit methodsFor: 'styling'!
styleText: aText
	"Main styling entry point.  The document is parsed into a Microdown AST
	 and projected by McMarkdownStylerVisitor, which reaches inline
	 decoration -- emphasis and this editor's own tokens alike -- through
	 McMarkdownInlineStyler, per block.  Nothing scans the flat document any
	 more: a range a widget has claimed is simply never descended into."
	self consumePendingEditDescriptorFor: aText.
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
	| parser probe snapshot reconciliation |
	probe := McCursorProbe on: cursorPos.
	[ searchSession ifNotNil: [ searchSession source: str ].
	  parser := self parserFor: str.
	  "Cursor-only passes retain the established full visitor and its complete
	 boundary proof.  Source changes take the reconciler path below."
	  (renderSnapshot notNil and: [ renderSnapshot source = str ]) ifTrue: [
		self styleWholeText: aText parser: parser cursor: probe.
		lastRenderWasPartial := false.
		^ self noteStyledSource: str cursor: cursorPos boundaries: probe boundaries ].
	  snapshot := McMarkdownDocumentSnapshot forParser: parser.
	  reconciliation := reconciler reconcileFrom: renderSnapshot to: snapshot.
	  "Make the newly reconciled lineage visible to image styling in this pass."
	  renderSnapshot := snapshot.
	  "Brick's generation handed to a pluggable styler does not preserve the
	 unaffected adornments.  Until the dedicated retained-text transaction is
	 in place, a local visitor would leave sibling owners as raw source.  Keep
	 reconciliation for stable resource identity, but project every owner."
	  self styleWholeText: aText parser: parser cursor: probe.
	  lastRenderWasPartial := false.
	  self noteStyledSource: str cursor: cursorPos
		boundaries: probe boundaries ]
		on: Error
		do: [ :e |
			renderSnapshot := nil.
			self invalidateStyleState.
			self showStatus: 'markdown: ' , e messageText asString ]!

styleWholeText: aText parser: aParser cursor: aCursor
	(McMarkdownStylerVisitor
		parser: aParser
		text: aText
		cursor: aCursor
		palette: self palette
		owner: self) visit: aParser root.
	McSearchPresentation applyTo: aText session: searchSession palette: self palette! !

!McRichEdit methodsFor: 'search'!
beginSearch
	searchSession ifNil: [ searchSession := McSearchSession on: editorElement editor text asString ].
	^ searchSession!

searchFor: aString
	self beginSearch queryText: aString.
	editorElement editor styleText.
	self updateSearchStatus.
	^ self searchResult asDictionary!

openSearch
	self beginSearch.
	searchBar ifNotNil: [ searchBar visibility: BlVisibility visible ].
	searchInput ifNotNil: [
		searchInput requestFocus.
		searchInput text asString isEmpty ifFalse: [ self searchFor: searchInput text asString ] ].
	self updateSearchStatus.
	^ self searchResult asDictionary!

nextSearch
	self beginSearch next.
	self presentActiveSearchMatch.
	^ self searchResult asDictionary!

previousSearch
	self beginSearch previous.
	self presentActiveSearchMatch.
	^ self searchResult asDictionary!

presentActiveSearchMatch
	| range source lineIndex scroller |
	range := searchSession activeMatch.
	editorElement editor styleText.
	range ifNil: [ ^ self updateSearchStatus ].
	editorElement editor navigator moveTo: range first - 1; apply.
	source := editorElement editor text asString.
	lineIndex := range first = 1
		ifTrue: [ 1 ]
		ifFalse: [ 1 + ((source copyFrom: 1 to: range first - 1) occurrencesOf: Character lf) ].
	scroller := BrEditorSearchTextScroller new
		editorElement: editorElement;
		lineIndex: lineIndex;
		characterStartPosition: range first;
		characterStopPosition: range last;
		yourself.
	scroller scroll.
	self updateSearchStatus!

highlightAllSearchMatches: aBoolean
	self beginSearch highlightAll: aBoolean.
	editorElement editor styleText.
	self updateSearchStatus!

wrapSearch: aBoolean
	self beginSearch wrapAround: aBoolean.
	self updateSearchStatus!

searchResult
	| identifier session |
	identifier := documentFile
		ifNil: [ '<memory>' ]
		ifNotNil: [ documentFile fullName ].
	session := searchSession ifNil: [ McSearchSession on: editorElement editor text asString ].
	^ McSearchResult
		document: identifier
		sourceSize: editorElement editor text size
		session: session!

cancelSearch
	searchSession := nil.
	editorElement editor styleText.
	self updateSearchStatus!

closeSearch
	self cancelSearch.
	searchBar ifNotNil: [ searchBar visibility: BlVisibility gone ].
	editorElement ifNotNil: [ editorElement requestFocus ].
	^ self searchResult asDictionary!

updateSearchStatus
	searchCountLabel ifNil: [ ^ self ].
	searchSession
		ifNil: [ searchCountLabel text: 'No search' ]
		ifNotNil: [
			searchCountLabel text: (searchSession hasMatches
				ifTrue: [ searchSession activeIndex printString , '/' , searchSession matchCount printString ]
				ifFalse: [ '0/0' ]) ]!

searchSession
	^ searchSession!

commandKeymap
	^ commandKeymap! !

!McRichEdit methodsFor: 'styling'!
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
	self isStylingSuspended ifTrue: [ ^ false ].
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

!McRichEdit methodsFor: 'styling - suspension'!
beginStylingSuspension
	stylingSuspensionDepth := (stylingSuspensionDepth ifNil: [ 0 ]) + 1!

endStylingSuspension
	stylingSuspensionDepth := ((stylingSuspensionDepth ifNil: [ 0 ]) - 1) max: 0!

isStylingSuspended
	^ (stylingSuspensionDepth ifNil: [ 0 ]) > 0! !

!McRichEdit methodsFor: 'text mutation - descriptors'!
pendingEditDescriptor
	^ pendingEditDescriptor!

notePendingEditFrom: start to: stop replacement: aString expectedSize: anInteger
	"The descriptor is advisory until reconciliation consumes it.  A source
	 size stamp prevents an unrelated later styler callback from using it."
	pendingEditDescriptor := Dictionary new
		at: #start put: start;
		at: #stop put: stop;
		at: #replacementLength put: aString size;
		at: #delta put: aString size - ((stop - start + 1) max: 0);
		at: #expectedSize put: anInteger;
		yourself!

consumePendingEditDescriptorFor: aText
	| descriptor |
	descriptor := pendingEditDescriptor.
	pendingEditDescriptor := nil.
	descriptor ifNil: [ ^ nil ].
	(descriptor at: #expectedSize) = aText size ifFalse: [ ^ nil ].
	^ descriptor! !

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
	self beginStylingSuspension.
	[ editor disableStyleTextWhenModifiedDuring: [
		to > from ifTrue: [ editor deleter from: from to: to; delete ].
		aString isEmpty ifFalse: [
			editor inserter
				withoutSelectionDelete;
				at: from;
				string: aString;
				insert ] ] ]
		ensure: [ self endStylingSuspension ].
	self notePendingEditFrom: start to: stop replacement: aString expectedSize: editor text size.
	self invalidateStyleState.
	editor styleText!

performButtonNamed: aLabel
	| handler |
	handler := buttonHandlers at: aLabel ifAbsent: [ nil ].
	handler
		ifNil: [ self showStatus: 'No handler for: ' , aLabel ]
		ifNotNil: [ handler value ]! !
