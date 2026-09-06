"
McMarkdownInlineStyler -- every inline decoration, over any source range.

One component serves two callers.  The visitor styles a block of the document
with it, and a table cell styles its own private rope with it.  That is what
makes cell contents recursive: a cell is just a smaller document.

It carries two index maps because the string it reasons about is not always
the rope it decorates.  For a document block, Microdown's inline string is the
block's lines joined with a CR and its markup prefix stripped, so source index
i lands at documentMap[i] in the rope -- and the rope is the document, so the
target map is that same array.  For a cell the rope holds exactly the cell
source, so the target map is the identity while the document map carries the
cell's interval, which is what a widget writes back through.

Custom tokens live here rather than in McRichEdit because scanning the flat
document was the cause of two defects: a checkbox rendered inside a code
fence, and a checkbox inside a table added a second beReplace adornment on top
of the table's own, which made the cell render a copy of the table.  Scoping
every pass to a range removes the possibility rather than guarding against it.

Scoping alone is not the whole of it, though, because the four passes run over
the same range knowing nothing of each other: '<<[ ] go>>' would put the
checkbox's beReplace inside the button's.  So a widget claims the source
characters it covers, in `claims', and a later pass skips any range that
intersects a claim -- so at most one widget ever covers a character.  The
first claim wins, which makes styleAll's order the precedence: emphasis (which
claims nothing, being plain attributes), then checkboxes, then colour
swatches, then buttons.  A checkbox inside a button therefore renders as a
checkbox, and the button's angle brackets stay literal.

One widget is not rebuilt per pass: an image.  A checkbox or a swatch is a
handful of BlElements, but an image element wraps a BrAsyncFileWidget, and a
new one per restyle means decoding the file again on every caret step.  So
image adornments draw their element from a pool the owner keeps, keyed by
occurrence -- see imageCacheKeyFor: for what an occurrence is and why the key
is what it is.

Chunk format: load with fileIn.
"!

Object subclass: #McMarkdownInlineStyler
	instanceVariableNames: 'source targetMap documentMap text cursor palette owner claims producedAdornment links ropeIsDocument imageOrdinals trusted codeSpans'
	classVariableNames: 'ImageOrdinalCache RegexCache'
	package: 'MalleableControl'!

!McMarkdownInlineStyler class methodsFor: 'instance creation'!
source: aString targetMap: aTargetMap documentMap: aDocumentMap text: aText cursor: anInteger palette: aPalette owner: anOwner
	^ self new
		setSource: aString
		targetMap: aTargetMap
		documentMap: aDocumentMap
		text: aText
		cursor: anInteger
		palette: aPalette
		owner: anOwner!

identityMapOfSize: anInteger
	^ (1 to: anInteger) asArray!

mapForInterval: anInterval
	^ (anInterval first to: anInterval last) asArray! !

!McMarkdownInlineStyler class methodsFor: 'patterns'!
regexFor: aPatternString
	"A compiled matcher for aPatternString, kept.

	 String>>asRegex compiles the pattern afresh every time it is sent, and
	 the four passes below send it four times for every cell of every table
	 on every restyle.  Measured in this image at about five microseconds a
	 compile against roughly a hundred and forty microseconds for a whole
	 cell -- so a seventh of the cost of building a table was recompiling
	 four constant patterns.

	 A matcher carries the state of its last match, so a shared one is safe
	 only while its users run one at a time on one process.  They do:
	 everything that reaches here is styling, and styling -- the document
	 styler and a table cell's stencil alike -- runs on the UI process.  The
	 background query process in McSqlite never gets here."
	^ self regexCache at: aPatternString ifAbsentPut: [ aPatternString asRegex ]!

regexCache
	^ RegexCache ifNil: [ RegexCache := self newCacheWithLimit: 32 ]!

newCacheWithLimit: anInteger
	"The cache is a performance aid, not a rendering dependency.  In a live
	 image these files are often re-filed independently; if McCache has not
	 been loaded yet, keep styling with an ordinary dictionary instead of
	 aborting the whole projection with an undeclared-global error."
	| cacheClass |
	cacheClass := Smalltalk at: #McBoundedCache ifAbsent: [ nil ].
	^ cacheClass
		ifNil: [ Dictionary new ]
		ifNotNil: [ cacheClass limit: anInteger ]!

clearRegexCache
	RegexCache := nil!

markupCharacters
	"Every character that can begin something styleAll would decorate: the
	 three emphasis delimiters Microdown recognises here, the bracket that
	 opens a checkbox or a link, the hash that opens a colour, and the angle
	 that opens a button."
	^ '*_`[#<'!

mayHaveMarkup: aString
	"Whether styleAll could put a single attribute on aString.

	 Conservative and cheap: one scan for the characters the four passes can
	 act on, and none of them produces an attribute without one.  A cell
	 holding a plain value -- which is nearly every cell of nearly every
	 table -- answers false here and skips an inline parse and four regex
	 passes it was only ever going to learn nothing from."
	| markers index char |
	markers := self markupCharacters.
	index := 1.
	[ index <= aString size ] whileTrue: [
		char := aString at: index.
		(markers includes: char) ifTrue: [ ^ true ].
		char = $h ifTrue: [
			((self token: 'http://' beginsIn: aString at: index)
				or: [ self token: 'https://' beginsIn: aString at: index ])
				ifTrue: [ ^ true ] ].
		index := index + 1 ].
	^ false!

token: aToken beginsIn: aString at: anIndex
	| last |
	last := anIndex + aToken size - 1.
	last > aString size ifTrue: [ ^ false ].
	1 to: aToken size do: [ :offset |
		(aString at: anIndex + offset - 1) = (aToken at: offset)
			ifFalse: [ ^ false ] ].
	^ true! !

!McMarkdownInlineStyler class methodsFor: 'image occurrences'!
imageOrdinalsIn: aString
	"For every image token in aString, how many images with that same target
	 and caption start at or before it: 1 for the first `!![a](x.png)', 2 for
	 the next identical one.  Keyed by the token's start index in aString.

	 Memoised on the string itself because every block of one restyle asks the
	 same question of the same document, and answering it is a whole scan of
	 that document.  The key is the text, not the rope, so an edit answers
	 afresh and a caret move does not."
	| cache |
	cache := self imageOrdinalCache.
	"With McCache absent the fallback is a plain Dictionary, and these keys are
	 whole documents rather than short patterns, so bound it here instead."
	((cache isKindOf: Dictionary) and: [ cache size >= 8 ])
		ifTrue: [ cache removeAll ].
	^ cache at: aString ifAbsentPut: [ self computeImageOrdinalsIn: aString ]!

computeImageOrdinalsIn: aString
	"Dynamic lookup of the scanner for the same reason linkSpans does it: an
	 incremental re-file of this file alone must not break styling.  With no
	 scanner there are no occurrences, and imageCacheKeyFor: falls back."
	| scannerClass ordinals tallies |
	ordinals := Dictionary new.
	tallies := Dictionary new.
	scannerClass := Smalltalk at: #McMarkdownLinkScanner ifAbsent: [ nil ].
	scannerClass ifNil: [ ^ ordinals ].
	((scannerClass scan: aString) select: [ :each | each isImage ]) do: [ :each |
		| identity tally |
		identity := Array with: each target with: each caption.
		tally := (tallies at: identity ifAbsent: [ 0 ]) + 1.
		tallies at: identity put: tally.
		ordinals at: each start put: tally ].
	^ ordinals!

imageOrdinalCache
	^ ImageOrdinalCache ifNil: [ ImageOrdinalCache := self newCacheWithLimit: 4 ]!

clearImageOrdinalCache
	ImageOrdinalCache := nil! !

!McMarkdownInlineStyler methodsFor: 'initialization'!
setSource: aString targetMap: aTargetMap documentMap: aDocumentMap text: aText cursor: anInteger palette: aPalette owner: anOwner
	source := aString.
	targetMap := aTargetMap asArray.
	documentMap := aDocumentMap asArray.
	text := aText.
	cursor := anInteger.
	palette := aPalette.
	owner := anOwner.
	claims := OrderedCollection new.
	producedAdornment := false.
	links := nil.
	codeSpans := nil.
	trusted := nil.
	imageOrdinals := nil.
	"Captured before asArray so it is the caller's intent that is recorded and
	 not whatever copying asArray happens to do: handing one map object twice
	 is how a caller says `the rope I am decorating is the document'."
	ropeIsDocument := aTargetMap == aDocumentMap! !

!McMarkdownInlineStyler methodsFor: 'accessing'!
paletteAt: aKey
	^ palette at: aKey ifAbsent: [ Color gray ]!

targetAt: anIndex
	^ targetMap at: anIndex ifAbsent: [ nil ]!

documentAt: anIndex
	^ documentMap at: anIndex ifAbsent: [ nil ]!

trusted: aBoolean
	"Force the trust decision instead of taking it from the owner.  For a
	 headless render and for tests, which have no editor to ask."
	trusted := aBoolean!

isTrusted
	"Whether labeled expressions in this block may be evaluated.

	 Taken from the editor showing the document, so a table cell gets the
	 same answer as the prose around it.  Untrusted is the default and the
	 answer whenever there is nobody to ask: opening a document must never be
	 the same thing as running it."
	trusted ifNotNil: [ ^ trusted ].
	owner ifNil: [ ^ false ].
	^ [ owner isTrustedDocument = true ] on: Error do: [ :e | false ]!

producedAdornment
	"Whether styleAll actually put an adornment -- a widget, or a collapsed
	 delimiter -- on the rope.

	 Answered by the styler because it is the styler that applies them.  The
	 alternative, and what the table used to do, is to walk every character
	 of the finished rope asking it for its attributes; this is the same
	 fact for no work.  It is exact rather than approximate:
	 apply:fromSource:toSource: sets it only once an attribute has survived
	 the bounds checks and reached the rope, so a range that fell outside
	 the text does not count."
	^ producedAdornment! !

!McMarkdownInlineStyler methodsFor: 'styling'!
styleAll
	"Emphasis first, then labeled code, then links and the tokens Microdown does
	 not know about.  This order is also the precedence when two tokens overlap:
	 the first pass to claim a source range keeps it -- see
	 claimFromSource:toSource:.

	 Code claims before links and checkboxes so that a link or a checkbox
	 written INSIDE an expression stays literal text: `{python} f(""[a](b)"")'
	 is one expression, not an expression containing a link."
	self styleEmphasis.
	self styleCode.
	self styleLinks.
	self styleCheckboxes.
	self styleColours.
	self styleButtons!

apply: anAttribute fromSource: start toSource: stop
	"Map a source range onto the rope and apply one attribute, ignoring
	 anything that falls outside.  A styler that raises mid-pass leaves the
	 editor half-decorated, so this is bounds-checked once here."
	| targetStart targetStop |
	(start isNil or: [ stop isNil ]) ifTrue: [ ^ self ].
	start > stop ifTrue: [ ^ self ].
	targetStart := self targetAt: start.
	targetStop := self targetAt: stop.
	(targetStart isNil or: [ targetStop isNil ]) ifTrue: [ ^ self ].
	(targetStart < 1 or: [ targetStop > text size ]) ifTrue: [ ^ self ].
	targetStart > targetStop ifTrue: [ ^ self ].
	text attribute: anAttribute from: targetStart to: targetStop.
	(anAttribute isKindOf: BrTextAdornmentAttribute)
		ifTrue: [ producedAdornment := true ]!

hideFromSource: start toSource: stop
	self apply: BrTextHideAttribute new fromSource: start toSource: stop!

highlightFromSource: start toSource: stop
	self
		apply: (BlTextForegroundAttribute new paint: (self paletteAt: 'highlight'))
		fromSource: start
		toSource: stop!

dimFromSource: start toSource: stop
	self
		apply: (BlTextForegroundAttribute new paint: (self paletteAt: 'dimDelimiter'))
		fromSource: start
		toSource: stop!

claimFromSource: start toSource: stop
	"Answer whether the source range start..stop is free of widgets, and
	 record it when it is.  Two adornments over the same character render
	 unpredictably -- that is the defect this class exists to remove -- and
	 the passes cannot see each other's work in the rope, because a hide
	 attribute and an adornment are indistinguishable there.  First claim
	 wins: see the class comment for why the order in styleAll is the
	 precedence.  Adjacency is not intersection, so two tokens that merely
	 touch both render."
	(start isNil or: [ stop isNil ]) ifTrue: [ ^ false ].
	start > stop ifTrue: [ ^ false ].
	(claims anySatisfy: [ :each | start <= each last and: [ stop >= each first ] ])
		ifTrue: [ ^ false ].
	claims add: (start to: stop).
	^ true!

replace: aStencil fromSource: start toSource: stop
	self replace: aStencil cache: nil key: nil fromSource: start toSource: stop!

replace: aStencil cache: aCacheOrNil key: aKeyOrNil fromSource: start toSource: stop
	"A replacement adornment that may draw its element from a pool.

	 Brick's own hook is withCache:key:, which lets the attribute answer a
	 previously built element without evaluating the stencil at all -- GT's
	 LeSnippetStylerVisitor attaches external images that way."
	| attribute |
	(self claimFromSource: start toSource: stop) ifFalse: [ ^ self ].
	attribute := BrTextAdornmentDynamicAttribute new
		beReplace;
		stencil: aStencil;
		yourself.
	(aCacheOrNil notNil and: [ aKeyOrNil notNil ])
			ifTrue: [ attribute withCache: aCacheOrNil key: aKeyOrNil ].
	self apply: attribute fromSource: start toSource: stop!

append: aStencil fromSource: start toSource: stop
	(self claimFromSource: start toSource: stop) ifFalse: [ ^ self ].
	self
		apply: (BrTextAdornmentDynamicAttribute new beAppend; stencil: aStencil)
		fromSource: start
		toSource: stop! !

!McMarkdownInlineStyler methodsFor: 'cursor locality'!
isNearSource: start to: stop
	"The cursor is 0-based and document positions are 1-based, which is where
	 the offset of two comes from: it lets the cursor sit just before a token
	 and still count as on it."
	| documentStart documentStop |
	cursor < 0 ifTrue: [ ^ false ].
	documentStart := self documentAt: start.
	documentStop := self documentAt: stop.
	(documentStart isNil or: [ documentStop isNil ]) ifTrue: [ ^ false ].
	^ cursor >= (documentStart - 2) and: [ cursor <= documentStop ]! !

!McMarkdownInlineStyler methodsFor: 'styling - emphasis'!
styleEmphasis
	"Microdown's inline parser gives start/end for each formatted run,
	 relative to the string it was handed -- which is exactly our source,
	 with the checkbox brackets masked out first (see maskedForEmphasis).
	 Measured: MicInlineParser new parse: '[ ] **fig**' answers a single
	 opaque MicTextBlock and no MicBoldFormatBlock at all -- an unresolved
	 open bracket reads to Microdown as the start of a link, and once it
	 cannot complete one it swallows the rest of the line as plain text,
	 hiding every run of emphasis after it.  The mask is
	 character-for-character the same length as the checkbox token, so
	 every start/end the parser reports still indexes correctly into the
	 real source."
	| nodes |
	nodes := [ MicInlineParser new parse: self maskedForEmphasis ] on: Error do: [ :e | #() ].
	nodes do: [ :each | self styleEmphasisNode: each ]!

maskedForEmphasis
	"A same-size copy with syntax that confuses Microdown blanked out.  Link
	 labels remain so emphasis inside a label still renders; destinations and
	 bare URLs are masked so underscores in a URL cannot become italics."
	| masked |
	masked := source copy.
	((self class regexFor: '\[[ xX]\]') matchingRangesIn: source) do: [ :range |
		range first to: range last do: [ :index | masked at: index put: $  ] ].
	self linkSpans do: [ :link |
		link start to: link stop do: [ :index | masked at: index put: $  ].
		(link isImage not and: [ #(link wiki) includes: link kind ]) ifTrue: [
			link labelStart to: link labelStop do: [ :index |
				masked at: index put: (source at: index) ] ] ].
	"Last, so a link written inside an expression cannot unmask part of it:
	 a labeled span is opaque to Microdown, which would otherwise style the
	 label and the backticks underneath the adornment that replaces them."
	self codeSpans do: [ :code |
		code start to: code stop do: [ :index | masked at: index put: $  ] ].
	^ masked!

styleEmphasisNode: aNode
	"The width heuristic below only makes sense for symmetric delimiters --
	 ** for bold, _ for italic, ` for monospace -- so anything else, notably
	 MicLinkBlock and MicFigureBlock, is left alone before any of it runs.
	 Links and images are handled by the tolerant source scanner after this
	 emphasis pass; all this method owes them is to not mangle them."
	| name start stop width inner |
	name := aNode class name asString.
	(#('MicBoldFormatBlock' 'MicItalicFormatBlock' 'MicMonospaceFormatBlock')
		includes: name) ifFalse: [ ^ self ].
	start := [ aNode start ] on: Error do: [ :e | nil ].
	stop := [ aNode end ] on: Error do: [ :e | nil ].
	(start isNil or: [ stop isNil ]) ifTrue: [ ^ self ].
	width := self delimiterWidthOf: aNode from: start to: stop.
	width < 1 ifTrue: [ ^ self ].
	inner := (start + width) to: (stop - width).
	inner first > inner last ifTrue: [ ^ self ].
	(self isNearSource: start to: stop) ifTrue: [
		self dimFromSource: start toSource: inner first - 1.
		self dimFromSource: inner last + 1 toSource: stop.
		^ self ].
	self hideFromSource: start toSource: inner first - 1.
	self hideFromSource: inner last + 1 toSource: stop.
	name = 'MicBoldFormatBlock' ifTrue: [
		self
			apply: (BlFontWeightAttribute new weight: BlFontWeight bold)
			fromSource: inner first toSource: inner last.
		self
			apply: (BlTextForegroundAttribute new paint: (self paletteAt: 'boldText'))
			fromSource: inner first toSource: inner last ].
	name = 'MicItalicFormatBlock' ifTrue: [
		self apply: BlFontEmphasisAttribute italic fromSource: inner first toSource: inner last ].
	name = 'MicMonospaceFormatBlock' ifTrue: [
		self
			apply: (BlFontFamilyAttribute new name: 'Source Code Pro')
			fromSource: inner first toSource: inner last.
		self
			apply: (BlTextUnderlayAttribute paint: (self paletteAt: 'codeBg'))
			fromSource: inner first toSource: inner last.
		self
			apply: (BlTextForegroundAttribute new paint: (self paletteAt: 'codeText'))
			fromSource: inner first toSource: inner last ]!

delimiterWidthOf: aNode from: start to: stop
	"Half the difference between the raw span and the inner text is one
	 delimiter's width: ** for bold, _ for italic, ` for monospace."
	| innerSize |
	innerSize := [ aNode substring size ] on: Error do: [ :e | 0 ].
	^ (stop - start + 1 - innerSize) // 2! !

!McMarkdownInlineStyler methodsFor: 'styling - tokens'!
linkSpans
	"Computed once because both emphasis masking and link projection need the
	 exact same spans.  The scan is scoped to this inline block, never the flat
	 document.  Dynamic lookup keeps an incremental reload of this file from
	 disabling older widgets when McMarkdownLink has not been filed in yet."
	| scannerClass |
	links ifNotNil: [ ^ links ].
	scannerClass := Smalltalk at: #McMarkdownLinkScanner ifAbsent: [ nil ].
	^ links := scannerClass
		ifNil: [ #() ]
		ifNotNil: [ scannerClass scan: source ]!

styleLinks
	self linkSpans do: [ :link |
		link isImage
			ifTrue: [ self styleImage: link ]
			ifFalse: [ self styleLink: link ] ]!

styleLink: aLink
	| state colour decoration click tooltip |
	(self claimFromSource: aLink start toSource: aLink stop) ifFalse: [ ^ self ].
	(self isNearSource: aLink start to: aLink stop) ifTrue: [
		^ self highlightFromSource: aLink start toSource: aLink stop ].
	aLink start < aLink labelStart ifTrue: [
		self hideFromSource: aLink start toSource: aLink labelStart - 1 ].
	aLink labelStop < aLink stop ifTrue: [
		self hideFromSource: aLink labelStop + 1 toSource: aLink stop ].
	state := owner
		ifNil: [ #available ]
		ifNotNil: [ [ owner linkStateFor: aLink ] on: Error do: [ :e | #dead ] ].
	colour := self paletteAt: (state = #dead ifTrue: [ 'deadLink' ] ifFalse: [ 'link' ]).
	self
		apply: (BlTextForegroundAttribute new paint: colour)
		fromSource: aLink labelStart
		toSource: aLink labelStop.
	decoration := BlTextDecorationAttribute new underline; color: colour; yourself.
	state = #dead ifTrue: [ decoration dashed ].
	self apply: decoration fromSource: aLink labelStart toSource: aLink labelStop.
	click := BrTextClickAttribute new
		action: [ :piece :element :editor :event |
			owner ifNotNil: [ owner activateLink: aLink ] ];
		yourself.
	self apply: click fromSource: aLink labelStart toSource: aLink labelStop.
	tooltip := BrTextTooltipAttribute new text: aLink target; yourself.
	self apply: tooltip fromSource: aLink labelStart toSource: aLink labelStop!

styleImage: aLink
	| key |
	(self isNearSource: aLink start to: aLink stop) ifTrue: [
		(self claimFromSource: aLink start toSource: aLink stop) ifTrue: [
			self highlightFromSource: aLink start toSource: aLink stop ].
		^ self ].
	key := self imageCacheKeyFor: aLink.
	self
		replace: [ self imageElementFor: aLink ]
		cache: self imageAdornmentCache
		key: key
		fromSource: aLink start
		toSource: aLink stop!

imageAdornmentCache
	"The owner's pool of already-built image elements, or nil.

	 Owned by the editor rather than by the styler because a styler lives for
	 exactly one pass over one range: a new one is built for every block of
	 every restyle, so anything it holds is thrown away before the next
	 restyle could reuse it.  Looked up defensively so an owner that predates
	 the pool -- and the no-owner case below -- keeps rendering images the way
	 it always did, one fresh element per pass."
	owner ifNil: [ ^ nil ].
	(owner respondsTo: #imageAdornmentCache) ifFalse: [ ^ nil ].
	^ owner imageAdornmentCache!

imageCacheKeyFor: aLink
	"What distinguishes one image occurrence from another, for pooling.

	 Three answers, in descending order of how much the asker knows.

	 An owner that retains a reconciled render tree knows best, so it is asked
	 first: it answers a lineage for the block the image sits in plus the
	 offset within that block, which survives an insertion anywhere above the
	 block.  See McRichEdit>>imageAdornmentCacheKeyFor:documentPosition:.

	 Failing that -- no snapshot yet, an unreconciled block, a table cell, or
	 any other owner -- the styler answers for itself, and it answers with an
	 occurrence rather than a position: the target, the caption, and how many
	 images with that same target and caption start at or before this one.  A
	 document position moves whenever anything above it is typed, so a key
	 built from one retires every image below an edit even though none of them
	 changed; an ordinal does not move when unrelated text grows or shrinks
	 above it, which is the property the pool needs to survive an edit at all.

	 The ordinal is counted over the whole rope being decorated rather than
	 over this block, because the pool belongs to the editor and two separate
	 blocks each holding `!![a](x.png)' must still get two elements: a
	 BlElement has one parent, so one shared between them would let the second
	 occurrence steal it from the first.  Counting over the rope makes those
	 two ordinals 1 and 2, and the two keys distinct.  A cell decorates its own
	 private rope, so a rope-wide count there is only cell-wide; its key also
	 carries the cell's document start, from imageCacheScope.

	 Last, when the occurrence cannot be found in that count -- no scanner in
	 the image, or a token that does not appear verbatim in the rope -- the key
	 falls back to the document position it always used.  That pools exactly as
	 it did before rather than not at all, and it can never alias, a position
	 being unique by construction.  The three shapes differ in size and in
	 their first element, so no two of them are ever equal."
	| documentStart retainedKey ordinal |
	owner ifNil: [ ^ nil ].
	documentStart := self documentAt: aLink start.
	documentStart ifNil: [ ^ nil ].
	(owner respondsTo: #imageAdornmentCacheKeyFor:documentPosition:) ifTrue: [
		retainedKey := owner imageAdornmentCacheKeyFor: aLink documentPosition: documentStart.
		retainedKey ifNotNil: [ ^ retainedKey ] ].
	ordinal := self imageOrdinalFor: aLink.
	ordinal ifNil: [
		^ Array with: documentStart with: aLink target with: aLink caption ].
	^ Array
		with: #imageOccurrence
		with: self imageCacheScope
		with: aLink target
		with: aLink caption
		with: ordinal!

imageCacheScope
	"Which rope the occurrence ordinal was counted in.

	 Nil when that rope is the document, because then the count is already
	 document-wide and nothing further is needed to tell two occurrences apart.
	 For a cell it is the cell's document start, which is what separates two
	 cells whose source is character-for-character the same.  A cell's images
	 therefore stay position-bound -- no worse than they were, and never
	 ambiguous -- until a cell can be addressed by lineage too."
	ropeIsDocument ifTrue: [ ^ nil ].
	documentMap isEmpty ifTrue: [ ^ nil ].
	^ documentMap first!

imageOrdinalFor: aLink
	"This occurrence's number among the images sharing its target and caption,
	 or nil when the scan found no token starting exactly where this one does."
	| index |
	index := ropeIsDocument
		ifTrue: [ self documentAt: aLink start ]
		ifFalse: [ aLink start ].
	index ifNil: [ ^ nil ].
	^ self imageOrdinals at: index ifAbsent: [ nil ]!

imageOrdinals
	"The occurrence numbers of every image in the rope this styler decorates,
	 computed once per styler and memoised class-side per text, so a document
	 holding several images is scanned once a revision rather than once a
	 block.  Reached only from styleImage:, so a block with no image away from
	 the cursor never pays for it."
	imageOrdinals ifNotNil: [ ^ imageOrdinals ].
	^ imageOrdinals := self class imageOrdinalsIn: self imageOrdinalScopeSource!

imageOrdinalScopeSource
	"The text the ordinals are counted in: the document when the rope is the
	 document, and this styler's own source when the rope is a cell's private
	 one -- which is the same string, and cheaper than rebuilding it."
	^ ropeIsDocument
		ifTrue: [ text asString ]
		ifFalse: [ source ]!

imageElementFor: aLink
	owner ifNotNil: [
		^ [ owner imageElementFor: aLink ] on: Error do: [ :e |
			self imagePlaceholderFor: aLink ] ].
	^ self imagePlaceholderFor: aLink!

imagePlaceholderFor: aLink
	| label |
	label := BlTextElement new.
	label text: (aLink caption asRopedText
		foreground: (self paletteAt: 'status');
		fontSize: 12).
	label padding: (BlInsets top: 3 right: 6 bottom: 3 left: 6).
	label border: (BlBorder paint: (self paletteAt: 'tableBorder') width: 1).
	^ label!

styleCheckboxes
	"Replace [ ] and [x] with a live checkbox that writes back through the
	 document map."
	((self class regexFor: '\[[ xX]\]') matchingRangesIn: source) do: [ :range |
		| start stop checked documentIndex |
		start := range first.
		stop := range last.
		checked := ((source at: start + 1) = $x) or: [ (source at: start + 1) = $X ].
		documentIndex := self documentAt: start + 1.
		(self isNearSource: start to: stop)
			ifTrue: [ self highlightFromSource: start toSource: stop ]
			ifFalse: [
				self
					replace: [
						| box |
						box := BrCheckbox new.
						box aptitude: BrGlamorousCheckboxAptitude new.
						box beNormalSize.
						box checked: checked.
						box margin: (BlInsets right: 4).
						box whenCheckedDo: [ self write: 'x' at: documentIndex ].
						box whenUncheckedDo: [ self write: ' ' at: documentIndex ].
						box ]
					fromSource: start
					toSource: stop ] ]!

styleColours
	((self class regexFor: '#[0-9A-Fa-f]{6}') matchingRangesIn: source) do: [ :range |
		| start stop hex |
		start := range first.
		stop := range last.
		hex := source copyFrom: start + 1 to: stop.
		(self isNearSource: start to: stop)
			ifTrue: [ self highlightFromSource: start toSource: stop ]
			ifFalse: [
				self
					append: [
						| swatch |
						swatch := BlElement new.
						swatch size: 14 @ 14.
						swatch geometry: (BlRoundedRectangleGeometry cornerRadius: 3).
						swatch background: ([ Color fromHexString: hex ] on: Error do: [ :e | Color gray ]).
						swatch margin: (BlInsets left: 4).
						swatch ]
					fromSource: start
					toSource: stop ] ]!

styleButtons
	"The handler is looked up fresh on every restyle, so toggling between raw
	 text and the widget never loses the binding: it is by name, not by
	 reference."
	((self class regexFor: '<<[^>]+>>') matchingRangesIn: source) do: [ :range |
		| start stop label |
		start := range first.
		stop := range last.
		label := source copyFrom: start + 2 to: stop - 2.
		(self isNearSource: start to: stop)
			ifTrue: [ self highlightFromSource: start toSource: stop ]
			ifFalse: [
				self
					replace: [
						| button |
						button := BrButton new.
						button label: label.
						button aptitude: BrGlamorousButtonWithLabelAptitude new.
						button beSmallSize.
						button margin: (BlInsets left: 2 right: 2).
						button action: [ self performButton: label ].
						button ]
					fromSource: start
					toSource: stop ] ]! !

!McMarkdownInlineStyler methodsFor: 'styling - code'!
codeSpans
	"The labeled code spans in this inline block, computed once because both
	 the emphasis mask and the code pass need exactly the same spans.

	 Dynamic lookup keeps an incremental reload of this file from disabling
	 older widgets when McMarkdownCode has not been filed in yet -- the same
	 reason linkSpans does it."
	| scannerClass |
	codeSpans ifNotNil: [ ^ codeSpans ].
	scannerClass := Smalltalk at: #McMarkdownCodeScanner ifAbsent: [ nil ].
	^ codeSpans := scannerClass
		ifNil: [ #() ]
		ifNotNil: [ scannerClass scan: source ]!

styleCode
	self codeSpans do: [ :each | self styleCodeSpan: each ]!

styleCodeSpan: aCode
	"Three states, and the cursor decides the first of them.

	 Cursor on the span: the raw source, so it can be edited -- the same
	 rule links and images follow.  Cursor away: the language tag, and
	 beside it either the result or, in a document that has not been
	 trusted, the expression itself."
	| result |
	(self isNearSource: aCode start to: aCode stop) ifTrue: [
		^ self highlightFromSource: aCode start toSource: aCode stop ].
	result := self resultFor: aCode.
	self
		replace: [ self codeElementFor: aCode result: result ]
		fromSource: aCode start
		toSource: aCode stop!

resultFor: aCode
	"What is known about aCode right now, or nil when this document has not
	 been trusted -- which is what makes an untrusted document render as
	 inert tagged source.

	 Never waits.  With an owner the evaluation goes to a background process
	 and this pass draws a placeholder, exactly as a database view does;
	 without one -- a headless render, a test -- it resolves on this process
	 so that a single pass produces the finished result."
	| evaluator |
	self isTrusted ifFalse: [ ^ nil ].
	evaluator := Smalltalk at: #McCodeEvaluator ifAbsent: [ nil ].
	evaluator ifNil: [ ^ nil ].
	^ [ owner
		ifNil: [ evaluator resultFor: aCode ]
		ifNotNil: [ :anOwner |
			evaluator
				resultFor: aCode
				token: anOwner
				onComplete: (self restyleRequestFor: anOwner) ] ]
		on: Error
		do: [ :e | nil ]!

restyleRequestFor: anOwner
	"A one-argument block for the evaluator to call when an expression
	 finishes.

	 It runs on the background process, so it does two things and no more:
	 it hops to the UI process through the editor's task queue, and there it
	 asks for a restyle.  It never reads or writes the rope, so there is no
	 stale document to get wrong -- if the span has been edited or deleted
	 meanwhile, the restyle simply does not ask for that expression again.

	 Closed over anOwner alone, deliberately: capturing the styler would
	 hold its rope alive for as long as the evaluation ran."
	^ [ :ignoredResult |
		| element |
		element := [ anOwner editorElement ] on: Error do: [ :e | nil ].
		element ifNotNil: [
			element enqueueTask: (BlTaskAction new action: [
				[ element editor styleText ] on: Error do: [ :e | nil ] ]) ] ]! !

!McMarkdownInlineStyler methodsFor: 'stencils - code'!
codeElementFor: aCode result: aResultOrNil
	"A coloured language tag and, beside it, whatever there is to show.

	 The tag is the label doing its second job: it tells the reader which
	 evaluator produced the number they are looking at, which matters most
	 exactly when the result is a bare 12.0 that could have come from
	 anywhere."
	| row tip |
	row := BlElement new.
	row layout: BlLinearLayout horizontal.
	row constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
	row addChild: (self codeTagElementFor: aCode).
	row addChild: (self codeBodyElementFor: aCode result: aResultOrNil).
	tip := BrGlamorousWithExplicitTooltipAptitude new.
	tip content: [ self codeTooltipFor: aCode result: aResultOrNil ].
	row addAptitude: tip.
	^ row!

codeTagElementFor: aCode
	| tag |
	tag := BlTextElement new.
	tag text: (aCode language asRopedText
		foreground: (self paletteAt: 'evalTagText');
		fontSize: 10).
	tag padding: (BlInsets top: 1 right: 5 bottom: 1 left: 5).
	tag geometry: (BlRoundedRectangleGeometry cornerRadius: 3).
	tag background: (self languageColourFor: aCode language).
	tag margin: (BlInsets right: 4).
	^ tag!

codeBodyElementFor: aCode result: aResultOrNil
	| body |
	body := BlTextElement new.
	body text: ((self codeBodyStringFor: aCode result: aResultOrNil) asRopedText
		foreground: (self codeBodyColourFor: aResultOrNil);
		fontSize: 13).
	^ body!

codeBodyStringFor: aCode result: aResultOrNil
	"Untrusted shows the expression rather than a result, so the document
	 reads as what it is -- code that has not been run -- instead of as a
	 blank."
	aResultOrNil ifNil: [ ^ aCode expression ].
	^ aResultOrNil displayString!

codeBodyColourFor: aResultOrNil
	aResultOrNil ifNil: [ ^ self paletteAt: 'codeText' ].
	aResultOrNil isFailed ifTrue: [ ^ self paletteAt: 'deadLink' ].
	aResultOrNil isPending ifTrue: [ ^ self paletteAt: 'status' ].
	^ self paletteAt: 'text'!

languageColourFor: aLanguage
	"Palette-keyed rather than hard-coded so the tag survives the dark-mode
	 toggle and can be rethemed with everything else."
	| key |
	aLanguage isEmpty ifTrue: [ ^ self paletteAt: 'langDefault' ].
	key := 'lang' , aLanguage first asUppercase asString , aLanguage allButFirst.
	^ palette at: key ifAbsent: [ self paletteAt: 'langDefault' ]!

codeTooltipFor: aCode result: aResultOrNil
	"The source, when it ran, and how to run it again.

	 The re-run binding is named here on purpose: results are cached and
	 never invalidate themselves, so a reader who does not know how to ask
	 for a fresh one has no way to find out."
	| container |
	container := BlElement new.
	container layout: BlLinearLayout vertical.
	container constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
	container padding: (BlInsets top: 7 right: 9 bottom: 7 left: 9).
	container background: (self paletteAt: 'codeBg').
	container geometry: (BlRoundedRectangleGeometry cornerRadius: 4).
	container border: (BlBorder paint: (self paletteAt: 'tableBorder') width: 1).
	(self codeTooltipLinesFor: aCode result: aResultOrNil) do: [ :each |
		| line |
		line := BlTextElement new.
		line text: (each value asRopedText
			foreground: (self paletteAt: each key);
			fontSize: 12).
		container addChild: line ].
	^ container!

codeTooltipLinesFor: aCode result: aResultOrNil
	"Palette key -> text, in the order they are shown."
	| lines |
	lines := OrderedCollection new.
	lines add: 'text' -> (aCode language , '  ' , aCode expression).
	aResultOrNil
		ifNil: [
			lines add: 'status' -> 'not evaluated: this document is not trusted' ]
		ifNotNil: [ :result |
			result isFailed ifTrue: [ lines add: 'deadLink' -> result message ].
			result evaluatedAt ifNotNil: [ :stamp |
				lines add: 'dimDelimiter'
					-> ('evaluated ' , (self stampStringFor: stamp)) ].
			lines add: 'dimDelimiter' -> 'Cmd-Shift-E re-runs the expression at the cursor' ].
	^ lines!

stampStringFor: aDateAndTime
	| codeClass |
	codeClass := Smalltalk at: #McMarkdownCode ifAbsent: [ nil ].
	codeClass ifNil: [ ^ aDateAndTime printString ].
	^ [ codeClass timestampStringFor: aDateAndTime ]
		on: Error
		do: [ :e | aDateAndTime printString ]! !

!McMarkdownInlineStyler methodsFor: 'actions'!
write: aString at: aDocumentIndex
	"Widgets mutate the document, never the relation or the rope's
	 attributes.  With no owner -- under test -- there is nothing to write to."
	owner ifNil: [ ^ self ].
	aDocumentIndex ifNil: [ ^ self ].
	owner replaceFrom: aDocumentIndex to: aDocumentIndex with: aString!

performButton: aLabel
	owner ifNil: [ ^ self ].
	owner performButtonNamed: aLabel! !
