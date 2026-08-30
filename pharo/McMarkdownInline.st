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

Chunk format: load with fileIn.
"!

Object subclass: #McMarkdownInlineStyler
	instanceVariableNames: 'source targetMap documentMap text cursor palette owner'
	classVariableNames: ''
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

!McMarkdownInlineStyler methodsFor: 'initialization'!
setSource: aString targetMap: aTargetMap documentMap: aDocumentMap text: aText cursor: anInteger palette: aPalette owner: anOwner
	source := aString.
	targetMap := aTargetMap asArray.
	documentMap := aDocumentMap asArray.
	text := aText.
	cursor := anInteger.
	palette := aPalette.
	owner := anOwner! !

!McMarkdownInlineStyler methodsFor: 'accessing'!
paletteAt: aKey
	^ palette at: aKey ifAbsent: [ Color gray ]!

targetAt: anIndex
	^ targetMap at: anIndex ifAbsent: [ nil ]!

documentAt: anIndex
	^ documentMap at: anIndex ifAbsent: [ nil ]! !

!McMarkdownInlineStyler methodsFor: 'styling'!
styleAll
	"Emphasis first, then the tokens Microdown does not know about."
	self styleEmphasis.
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
	text attribute: anAttribute from: targetStart to: targetStop!

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

replace: aStencil fromSource: start toSource: stop
	self
		apply: (BrTextAdornmentDynamicAttribute new beReplace; stencil: aStencil)
		fromSource: start
		toSource: stop!

append: aStencil fromSource: start toSource: stop
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
	"A copy of source with '[ ]'/'[x]' checkbox tokens blanked out to the
	 same length, so styleEmphasis's parse does not choke on them; see
	 styleEmphasis for why."
	| masked |
	masked := source copy.
	('\[[ xX]\]' asRegex matchingRangesIn: source) do: [ :range |
		range first to: range last do: [ :index | masked at: index put: $  ] ].
	^ masked!

styleEmphasisNode: aNode
	"The width heuristic below only makes sense for symmetric delimiters --
	 ** for bold, _ for italic, ` for monospace -- so anything else, notably
	 MicLinkBlock and MicFigureBlock, is left alone before any of it runs.
	 Link and image rendering is a later phase; all this owes them is to not
	 mangle them."
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
styleCheckboxes
	"Replace [ ] and [x] with a live checkbox that writes back through the
	 document map."
	('\[[ xX]\]' asRegex matchingRangesIn: source) do: [ :range |
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
	('#[0-9A-Fa-f]{6}' asRegex matchingRangesIn: source) do: [ :range |
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
	('<<[^>]+>>' asRegex matchingRangesIn: source) do: [ :range |
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
