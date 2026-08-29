"
McMarkdown -- parse/AST layer for McRichEdit.

Microdown parses markdown but throws the source offsets away: MicAbstractBlock
carries parent, properties, children and parser, and nothing that says where in
the document the block came from.  A projectional editor needs exactly that, so
McMarkdownParser drives Microdown's own line loop and records a 1-based source
character range for every node as the lines are consumed.

Two rules govern the range stamping, applied after each line:

  1. Any node that did not exist before the line was handled was created by it,
     so its range starts on that line.
  2. Any node still open (on the path from `current' up to the root) consumed
     the line, so its range extends to it.

Together those cover every block Microdown builds, including multi-line ones
(paragraphs, tables, code blocks, lists) that grow a line at a time.

Inline nodes are a different matter: MicBoldFormatBlock and friends DO carry
start/end, but relative to the string Microdown inline-parsed, which for a
multi-line paragraph is the lines concatenated with the newlines dropped.
sourceMapFor:content: rebuilds the index-by-index mapping back to the document
by aligning each source line against the content it contributed.

Chunk format: load with fileIn.
"!

MicrodownParser subclass: #McMarkdownParser
	instanceVariableNames: 'source ranges lineIntervals inlineSources'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownParser class methodsFor: 'parsing'!
parseSource: aString
	"Parse aString and answer the parser, which holds both the AST root
	 and the source ranges.  Callers want the parser, not just the root."
	^ self new parseSource: aString; yourself! !

!McMarkdownParser methodsFor: 'accessing'!
source
	^ source!

root
	^ root!

ranges
	^ ranges!

lineIntervals
	^ lineIntervals!

rangeOf: aBlock
	"The 1-based source character range of aBlock, or nil when unknown."
	^ ranges at: aBlock ifAbsent: [ nil ]!

sourceOf: aBlock
	"The raw source text aBlock was parsed from, or '' when unknown."
	| range |
	range := self rangeOf: aBlock.
	range ifNil: [ ^ '' ].
	^ source copyFrom: range first to: range last! !

!McMarkdownParser methodsFor: 'parsing'!
parseSource: aString
	"Parse aString, recording a source range for every node.  This mirrors
	 MicrodownParser>>parse:, but drives the line loop from precomputed line
	 intervals so that each line's offsets are known while it is handled."
	source := aString.
	ranges := IdentityDictionary new.
	inlineSources := IdentityDictionary new.
	lineIntervals := self computeLineIntervals: aString.
	current := root := self newRootBlock
		setParser: self;
		yourself.
	lineIntervals do: [ :each |
		| seen |
		seen := self allBlocks.
		self handleLine: (self lineAt: each).
		self allBlocks do: [ :block |
			(seen includes: block) ifFalse: [ self stamp: block with: each ] ].
		self openBlocksDo: [ :block | self stamp: block with: each ] ].
	[ current == root ] whileFalse: [
		current closeMe.
		current := current parent ].
	^ root!

lineAt: anInterval
	"The text of one line.  Empty lines have last = first - 1, which
	 copyFrom:to: answers as the empty string."
	anInterval last < anInterval first ifTrue: [ ^ '' ].
	^ source copyFrom: anInterval first to: anInterval last! !

!McMarkdownParser methodsFor: 'parsing - private'!
computeLineIntervals: aString
	"Split aString into 1-based character intervals, one per line, each
	 excluding its terminator.  Handles LF, CR and CRLF, because text typed
	 into a Bloc editor does not necessarily use the same terminator as text
	 filed in from a chunk file."
	| result start index size char |
	result := OrderedCollection new.
	size := aString size.
	start := 1.
	index := 1.
	[ index <= size ] whileTrue: [
		char := aString at: index.
		(char = Character lf or: [ char = Character cr ])
			ifTrue: [
				result add: (start to: index - 1).
				(char = Character cr
					and: [ index < size
					and: [ (aString at: index + 1) = Character lf ] ])
						ifTrue: [ index := index + 1 ].
				start := index + 1 ].
		index := index + 1 ].
	"A trailing terminator ends the last line; anything after it is one more."
	start <= size ifTrue: [ result add: (start to: size) ].
	^ result asArray!

allBlocks
	"Every node currently in the tree, root included."
	| set |
	set := IdentitySet new.
	self collectBlocksFrom: root into: set.
	^ set!

collectBlocksFrom: aBlock into: aSet
	aBlock ifNil: [ ^ self ].
	aSet add: aBlock.
	(aBlock respondsTo: #children) ifFalse: [ ^ self ].
	(aBlock children ifNil: [ #() ]) do: [ :each |
		self collectBlocksFrom: each into: aSet ]!

openBlocksDo: aBlockClosure
	"Evaluate aBlockClosure for each open node between current and the root,
	 exclusive of the root -- the root spans the whole document and needs no
	 range of its own."
	| node |
	node := current.
	[ node isNil or: [ node == root ] ] whileFalse: [
		aBlockClosure value: node.
		node := node parent ]!

stamp: aBlock with: anInterval
	"Widen aBlock's recorded range to cover anInterval."
	| existing first last |
	aBlock == root ifTrue: [ ^ self ].
	anInterval last < anInterval first ifTrue: [ ^ self ].
	existing := ranges at: aBlock ifAbsent: [ nil ].
	existing
		ifNil: [ first := anInterval first. last := anInterval last ]
		ifNotNil: [
			first := existing first min: anInterval first.
			last := existing last max: anInterval last ].
	ranges at: aBlock put: (first to: last)! !

!McMarkdownParser methodsFor: 'source mapping'!
lineIntervalsWithin: aRange
	"The line intervals belonging to aRange.  Ranges are always built out of
	 whole lines, so a line is in when its start is."
	aRange ifNil: [ ^ #() ].
	^ lineIntervals select: [ :each |
		each first >= aRange first and: [ each first <= aRange last ] ]!

inlineSourceOf: aBlock
	"The raw text Microdown inline-parsed for aBlock -- what its inline
	 children's start/end offsets are relative to."
	^ (self inlineSourceAndMapOf: aBlock) first!

inlineMapOf: aBlock
	"An Array as long as aBlock's inline source, mapping each of its indices
	 to the 1-based document index that character came from."
	^ (self inlineSourceAndMapOf: aBlock) second!

sourceRangeOf: anInlineNode within: aMap
	"The 1-based source range of an inline node, or nil when its offsets fall
	 outside aMap."
	| first last |
	(anInlineNode respondsTo: #start) ifFalse: [ ^ nil ].
	anInlineNode start ifNil: [ ^ nil ].
	anInlineNode end ifNil: [ ^ nil ].
	(anInlineNode start between: 1 and: aMap size) ifFalse: [ ^ nil ].
	(anInlineNode end between: 1 and: aMap size) ifFalse: [ ^ nil ].
	first := aMap at: anInlineNode start.
	last := aMap at: anInlineNode end.
	(first > 0 and: [ last >= first ]) ifFalse: [ ^ nil ].
	^ first to: last! !

!McMarkdownParser methodsFor: 'source mapping - private'!
inlineSourceAndMapOf: aBlock
	"Answer { inline source string. index map } for aBlock, computed once and
	 cached.

	 Microdown's own #text cannot serve as the inline source: it answers the
	 raw text for paragraphs and quotes, but for headers and list items it
	 answers the text with the inline delimiters already stripped.  So the
	 string is rebuilt from the document, one line at a time with the block
	 markup removed, and each character is recorded against the document
	 index it came from -- which makes the map exact rather than inferred.

	 Multi-line blocks are joined with a single CR, because that is what
	 Microdown does when it accumulates a continuous block's lines, and the
	 inline offsets are relative to that joined string."
	^ inlineSources at: aBlock ifAbsentPut: [
		| content map first |
		content := WriteStream on: String new.
		map := OrderedCollection new.
		first := true.
		(self lineIntervalsWithin: (self rangeOf: aBlock)) do: [ :interval |
			| line stripped prefixSize |
			line := self lineAt: interval.
			stripped := self stripMarkupFrom: line for: aBlock.
			prefixSize := line size - stripped size.
			first
				ifTrue: [ first := false ]
				ifFalse: [
					content nextPut: Character cr.
					map add: interval first - 1 ].
			1 to: stripped size do: [ :index |
				content nextPut: (stripped at: index).
				map add: interval first + prefixSize + index - 1 ] ].
		{ content contents. map asArray } ]!

stripMarkupFrom: aLine for: aBlock
	"aLine without the block markup that opens it.  The patterns are kept per
	 block class rather than as one combined regex on purpose: a paragraph
	 line may legitimately open with `*' (an italic run), and a combined
	 pattern would eat it."
	| name |
	name := aBlock class name asString.
	name = 'MicHeaderBlock'
		ifTrue: [ ^ self stripPrefix: '\s*#+\s*' from: aLine ].
	name = 'MicQuoteBlock'
		ifTrue: [ ^ self stripPrefix: '\s*>\s*' from: aLine ].
	name = 'MicListItemBlock'
		ifTrue: [ ^ self stripPrefix: '\s*([-*+]|[0-9]+\.)\s*' from: aLine ].
	^ aLine!

stripPrefix: aPattern from: aLine
	"aLine without a leading match of aPattern.  matchingRangesIn: is not
	 anchored, so an interior match is rejected explicitly."
	| found |
	found := aPattern asRegex matchingRangesIn: aLine.
	(found notEmpty and: [ found first first = 1 ])
		ifFalse: [ ^ aLine ].
	^ aLine copyFrom: found first last + 1 to: aLine size! !

MicrodownVisitor subclass: #McMarkdownStylerVisitor
	instanceVariableNames: 'parser text cursor palette owner map'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownStylerVisitor commentStamp: '' prior: 0!
Walks a Microdown AST and decorates a BlText with the attributes that project
it, choosing between raw source and rendered form per node by cursor locality.

The visitor never touches the source rope -- it only adds attributes, so the
document text stays the single source of truth and every projection is
reversible by moving the cursor.

`map' holds the inline index map of the block currently being visited, so that
the inline visits (bold, italic, monospace) can turn a node's block-relative
start/end into document offsets.  Block visits set it before descending.!

!McMarkdownStylerVisitor class methodsFor: 'instance creation'!
parser: aParser text: aText cursor: anInteger palette: aPalette owner: anOwner
	^ self new
		setParser: aParser
		text: aText
		cursor: anInteger
		palette: aPalette
		owner: anOwner! !

!McMarkdownStylerVisitor methodsFor: 'initialization'!
setParser: aParser text: aText cursor: anInteger palette: aPalette owner: anOwner
	parser := aParser.
	text := aText.
	cursor := anInteger.
	palette := aPalette.
	owner := anOwner.
	map := #()! !

!McMarkdownStylerVisitor methodsFor: 'accessing'!
paletteAt: aKey
	^ palette at: aKey ifAbsent: [ Color gray ]! !

!McMarkdownStylerVisitor methodsFor: 'styling - primitives'!
apply: anAttribute from: start to: stop
	"Add one attribute over a document range, ignoring ranges that fall
	 outside the text.  A styler that raises mid-pass leaves the editor
	 half-decorated, so every application is bounds-checked here rather than
	 at each of the several dozen call sites."
	| size |
	size := text size.
	(start isNil or: [ stop isNil ]) ifTrue: [ ^ self ].
	start > stop ifTrue: [ ^ self ].
	start < 1 ifTrue: [ ^ self ].
	stop > size ifTrue: [ ^ self ].
	text attribute: anAttribute from: start to: stop!

hideFrom: start to: stop
	self apply: BrTextHideAttribute new from: start to: stop!

foreground: aColor from: start to: stop
	self apply: (BlTextForegroundAttribute new paint: aColor) from: start to: stop!

background: aColor from: start to: stop
	"BlTextBackgroundAttribute compiles and applies but draws nothing in a
	 BrEditor.  BlTextUnderlayAttribute is what GT's own #highlight: uses and
	 what actually paints behind the glyphs."
	self apply: (BlTextUnderlayAttribute paint: aColor) from: start to: stop!

dimFrom: start to: stop
	self foreground: (self paletteAt: 'dimDelimiter') from: start to: stop!

boldFrom: start to: stop
	self apply: (BlFontWeightAttribute new weight: BlFontWeight bold) from: start to: stop!

italicFrom: start to: stop
	self apply: BlFontEmphasisAttribute italic from: start to: stop!

fontSize: aNumber from: start to: stop
	self apply: (BlFontSizeAttribute new size: aNumber) from: start to: stop!

monospaceFrom: start to: stop
	self apply: (BlFontFamilyAttribute new name: 'Source Code Pro') from: start to: stop!

replace: aStencil from: start to: stop
	self
		apply: (BrTextAdornmentDynamicAttribute new beReplace; stencil: aStencil)
		from: start
		to: stop! !



!McMarkdownStylerVisitor methodsFor: 'cursor locality'!
isNear: aRange
	"True when the cursor is within or adjacent to a source range.  The
	 cursor is 0-based and ranges are 1-based, which is where the offset of
	 two comes from -- it lets the cursor sit just before a token and still
	 count as being on it."
	aRange ifNil: [ ^ false ].
	cursor < 0 ifTrue: [ ^ false ].
	^ cursor >= (aRange first - 2) and: [ cursor <= aRange last ]! !



!McMarkdownStylerVisitor methodsFor: 'visiting - entry'!
visitRoot: aRoot
	^ self visitChildrenOf: aRoot!

visitInlineChildrenOf: aBlock
	"Descend into a block's inline nodes with its index map installed, then
	 restore the caller's map so nested blocks do not corrupt each other."
	| saved |
	saved := map.
	map := parser inlineMapOf: aBlock.
	[ (aBlock children ifNil: [ #() ]) do: [ :each | each accept: self ] ]
		ensure: [ map := saved ]! !

!McMarkdownStylerVisitor methodsFor: 'visiting - blocks'!
visitHeader: aHeader
	"Scale the header text and project its # prefix: hidden when the cursor is
	 away, dimmed when it is near."
	| range contentStart size |
	range := parser rangeOf: aHeader.
	range ifNil: [ ^ self ].
	size := self fontSizeForLevel: aHeader level.
	contentStart := self contentStartOf: aHeader default: range first + aHeader level + 1.
	self fontSize: size from: contentStart to: range last.
	self boldFrom: contentStart to: range last.
	self foreground: (self paletteAt: 'title') from: contentStart to: range last.
	(self isNear: range)
		ifTrue: [ self dimFrom: range first to: contentStart - 1 ]
		ifFalse: [ self hideFrom: range first to: contentStart - 1 ].
	self visitInlineChildrenOf: aHeader!

visitParagraph: aParagraph
	"Microdown only recognises *** as a horizontal rule, so a --- or ___ line
	 reaches us as a paragraph.  Both are ordinary GFM, so they are recognised
	 here rather than left to render as literal text."
	(self isHorizontalRuleSource: (parser sourceOf: aParagraph))
		ifTrue: [ ^ self styleHorizontalRuleIn: (parser rangeOf: aParagraph) ].
	self visitInlineChildrenOf: aParagraph!

visitQuote: aQuote
	"Dim the > markers and tint the quoted text."
	| range |
	range := parser rangeOf: aQuote.
	range ifNil: [ ^ self ].
	self foreground: (self paletteAt: 'quoteText') from: range first to: range last.
	self italicFrom: range first to: range last.
	(parser lineIntervalsWithin: range) do: [ :interval |
		| contentStart |
		contentStart := self markerEndIn: interval pattern: '\s*>\s*'.
		contentStart ifNotNil: [
			(self isNear: range)
				ifTrue: [ self dimFrom: interval first to: contentStart ]
				ifFalse: [
					self replace: [ self quoteBarElement ] from: interval first to: contentStart ] ] ].
	self visitInlineChildrenOf: aQuote!

visitHorizontalLine: aLine
	self styleHorizontalRuleIn: (parser rangeOf: aLine)!

visitCode: aCodeBlock
	"Monospace the whole block over a tinted background, and collapse the
	 fence lines when the cursor is elsewhere."
	| range lines |
	range := parser rangeOf: aCodeBlock.
	range ifNil: [ ^ self ].
	lines := parser lineIntervalsWithin: range.
	lines isEmpty ifTrue: [ ^ self ].
	self monospaceFrom: range first to: range last.
	self fontSize: 14 from: range first to: range last.
	self background: (self paletteAt: 'codeBg') from: range first to: range last.
	self foreground: (self paletteAt: 'codeText') from: range first to: range last.
	(self isNear: range) ifTrue: [
		self dimFrom: lines first first to: lines first last.
		lines size > 1 ifTrue: [ self dimFrom: lines last first to: lines last last ].
		^ self ].
	"Cursor away: hide each fence together with the line break it owns, so the
	 block closes up instead of leaving two blank lines behind."
	self hideFrom: lines first first to: lines first last + 1.
	lines size > 1 ifTrue: [
		self hideFrom: lines last first - 1 to: lines last last ]!

visitUnorderedList: aList
	aList children doWithIndex: [ :item :index |
		self styleListItem: item marker: nil ]!

visitOrderedList: aList
	aList children doWithIndex: [ :item :index |
		self styleListItem: item marker: index ]! !

!McMarkdownStylerVisitor methodsFor: 'visiting - inline'!
visitBold: aNode
	self
		styleInline: aNode
		near: [ :range :inner | self dimDelimitersOf: range inner: inner ]
		away: [ :range :inner |
			self hideDelimitersOf: range inner: inner.
			self boldFrom: inner first to: inner last.
			self foreground: (self paletteAt: 'boldText') from: inner first to: inner last ]!

visitItalic: aNode
	self
		styleInline: aNode
		near: [ :range :inner | self dimDelimitersOf: range inner: inner ]
		away: [ :range :inner |
			self hideDelimitersOf: range inner: inner.
			self italicFrom: inner first to: inner last ]!

visitMonospace: aNode
	self
		styleInline: aNode
		near: [ :range :inner | self dimDelimitersOf: range inner: inner ]
		away: [ :range :inner |
			self hideDelimitersOf: range inner: inner.
			self monospaceFrom: inner first to: inner last.
			self background: (self paletteAt: 'codeBg') from: inner first to: inner last.
			self foreground: (self paletteAt: 'codeText') from: inner first to: inner last ]! !

!McMarkdownStylerVisitor methodsFor: 'visiting - inline private'!
styleInline: aNode near: aNearBlock away: anAwayBlock
	"Shared shape for every delimited inline run.  The delimiter width is
	 derived from the node rather than hardcoded, because it differs per
	 markup (** for bold, _ for italic, ` for monospace) and Microdown
	 already knows the inner text."
	| range inner width |
	range := parser sourceRangeOf: aNode within: map.
	range ifNil: [ ^ self ].
	width := self delimiterWidthOf: aNode range: range.
	width < 1 ifTrue: [ ^ self ].
	inner := (range first + width) to: (range last - width).
	inner first > inner last ifTrue: [ ^ self ].
	(self isNear: range)
		ifTrue: [ aNearBlock value: range value: inner ]
		ifFalse: [ anAwayBlock value: range value: inner ]!

delimiterWidthOf: aNode range: aRange
	"Half the difference between the raw span and the inner text is the width
	 of one delimiter."
	| innerSize |
	innerSize := ([ aNode substring size ] on: Error do: [ :e | 0 ]).
	^ (aRange size - innerSize) // 2!

dimDelimitersOf: aRange inner: anInner
	self dimFrom: aRange first to: anInner first - 1.
	self dimFrom: anInner last + 1 to: aRange last!

hideDelimitersOf: aRange inner: anInner
	self hideFrom: aRange first to: anInner first - 1.
	self hideFrom: anInner last + 1 to: aRange last! !

!McMarkdownStylerVisitor methodsFor: 'visiting - lists'!
styleListItem: anItem marker: anIndexOrNil
	"Project a list item's marker: a bullet element for unordered items,
	 a highlighted number for ordered ones.  anIndexOrNil is nil for
	 unordered lists."
	| range lines interval markerEnd |
	range := parser rangeOf: anItem.
	range ifNil: [ ^ self ].
	lines := parser lineIntervalsWithin: range.
	lines isEmpty ifTrue: [ ^ self ].
	interval := lines first.
	markerEnd := self markerEndIn: interval pattern: '\s*([-*+]|[0-9]+\.)\s*'.
	markerEnd ifNotNil: [
		anIndexOrNil
			ifNil: [
				(self isNear: range)
					ifTrue: [ self dimFrom: interval first to: markerEnd ]
					ifFalse: [
						self replace: [ self bulletElement ] from: interval first to: markerEnd ] ]
			ifNotNil: [
				self foreground: (self paletteAt: 'listMarker') from: interval first to: markerEnd.
				self boldFrom: interval first to: markerEnd ] ].
	self visitInlineChildrenOf: anItem! !

!McMarkdownStylerVisitor methodsFor: 'visiting - tables'!
visitTable: aTable
	"A table is a multi-line block, so away from the cursor the whole run of
	 pipe rows is replaced by one grid element."
	| range |
	range := parser rangeOf: aTable.
	range ifNil: [ ^ self ].
	(aTable rows isNil or: [ aTable rows isEmpty ]) ifTrue: [ ^ self ].
	(self isNear: range)
		ifTrue: [ ^ self styleTableSourceIn: range ].
	self replace: [ self tableElementFor: aTable ] from: range first to: range last!

styleTableSourceIn: aRange
	"Cursor on the table: leave the pipe syntax legible, with the separators
	 picked out so the columns still read as columns while being edited."
	| source |
	source := parser source.
	aRange first to: aRange last do: [ :index |
		(source at: index) = $|
			ifTrue: [
				self foreground: (self paletteAt: 'tableBorder') from: index to: index ] ].
	(parser lineIntervalsWithin: aRange) do: [ :interval |
		(self isDelimiterLine: (parser lineAt: interval))
			ifTrue: [ self dimFrom: interval first to: interval last ] ]!

tableModelFor: aTable
	"Normalise a Microdown table into what the widget needs: the rows to
	 show, the column alignments, and how many leading rows are header.

	 This is separated from building the element because it is where all the
	 judgement lives.  Microdown handles the GFM separator row inconsistently
	 -- it drops a plain |---|---| but hands back |:---|---:| as if it were
	 data -- so neither its rows nor its hasHeader flag can be trusted alone.

	 Answers a Dictionary keyed `rows', `alignments' and `headerRows'."
	| rows delimiterIndex alignments headerRows |
	rows := aTable rows collect: [ :row |
		row collect: [ :cell | self textOfCell: cell ] ].
	delimiterIndex := 0.
	rows doWithIndex: [ :row :index |
		(delimiterIndex = 0 and: [ self isDelimiterRow: row ])
			ifTrue: [ delimiterIndex := index ] ].
	alignments := delimiterIndex = 0
		ifTrue: [ Array new: 0 ]
		ifFalse: [ (rows at: delimiterIndex) collect: [ :each | self alignmentFor: each ] ].
	headerRows := delimiterIndex = 0
		ifTrue: [ (aTable hasHeader and: [ rows size > 1 ]) ifTrue: [ 1 ] ifFalse: [ 0 ] ]
		ifFalse: [ delimiterIndex - 1 ].
	delimiterIndex = 0 ifFalse: [
		rows := (rows copyFrom: 1 to: delimiterIndex - 1)
			, (rows copyFrom: delimiterIndex + 1 to: rows size) ].
	^ Dictionary new
		at: 'rows' put: rows;
		at: 'alignments' put: alignments;
		at: 'headerRows' put: headerRows;
		yourself!

tableElementFor: aTable
	"The grid widget shown in place of the pipe rows."
	| model rows alignments headerRows columnCount grid |
	model := self tableModelFor: aTable.
	rows := model at: 'rows'.
	alignments := model at: 'alignments'.
	headerRows := model at: 'headerRows'.
	columnCount := rows inject: 1 into: [ :best :row | best max: row size ].
	grid := BlElement new.
	grid layout: (BlGridLayout horizontal columnCount: columnCount).
	grid constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
	grid background: (self paletteAt: 'editorBg').
	grid border: (BlBorder paint: (self paletteAt: 'tableBorder') width: 1).
	grid margin: (BlInsets top: 2 bottom: 2).
	rows doWithIndex: [ :row :rowIndex |
		1 to: columnCount do: [ :columnIndex |
			grid addChild: (self
				tableCellFor: (row at: columnIndex ifAbsent: [ '' ])
				alignment: (alignments at: columnIndex ifAbsent: [ #left ])
				isHeader: rowIndex <= headerRows) ] ].
	^ grid!

tableCellFor: aString alignment: aSymbol isHeader: aBoolean
	| cell content |
	content := aString asRopedText.
	content
		foreground: (self paletteAt: (aBoolean ifTrue: [ 'boldText' ] ifFalse: [ 'text' ]));
		fontSize: 14.
	aBoolean ifTrue: [ content bold ].
	cell := BlTextElement new.
	cell text: content.
	cell padding: (BlInsets top: 3 right: 10 bottom: 3 left: 10).
	aBoolean ifTrue: [ cell background: (self paletteAt: 'tableHeaderBg') ].
	cell constraintsDo: [ :c |
		c horizontal fitContent.
		c vertical fitContent.
		aSymbol = #right ifTrue: [ c grid horizontal alignRight ].
		aSymbol = #center ifTrue: [ c grid horizontal alignCenter ].
		aSymbol = #left ifTrue: [ c grid horizontal alignLeft ] ].
	^ cell!

textOfCell: aCell
	"A Microdown table cell is a collection of inline nodes."
	aCell isString ifTrue: [ ^ aCell ].
	^ String streamContents: [ :stream |
		aCell do: [ :node |
			stream nextPutAll: ([ node text ] on: Error do: [ :e | '' ]) ] ]!

isDelimiterRow: aRow
	"True for a GFM alignment row: every cell is dashes with optional colons."
	aRow isEmpty ifTrue: [ ^ false ].
	^ aRow allSatisfy: [ :each | self isDelimiterCell: each ]!

isDelimiterCell: aString
	| trimmed |
	trimmed := aString trimBoth.
	trimmed isEmpty ifTrue: [ ^ false ].
	(trimmed includes: $-) ifFalse: [ ^ false ].
	^ (trimmed reject: [ :char | char = $- or: [ char = $: ] ]) isEmpty!

isDelimiterLine: aString
	| trimmed |
	trimmed := aString trimBoth.
	trimmed isEmpty ifTrue: [ ^ false ].
	(trimmed includes: $-) ifFalse: [ ^ false ].
	^ (trimmed reject: [ :char |
		char = $- or: [ char = $: or: [ char = $| or: [ char = $  ] ] ] ]) isEmpty!

alignmentFor: aString
	| trimmed |
	trimmed := aString trimBoth.
	(trimmed beginsWith: ':')
		ifTrue: [ ^ (trimmed endsWith: ':') ifTrue: [ #center ] ifFalse: [ #left ] ].
	(trimmed endsWith: ':') ifTrue: [ ^ #right ].
	^ #left! !

!McMarkdownStylerVisitor methodsFor: 'helpers'!
fontSizeForLevel: aLevel
	^ #(28 24 20 18 16 14) at: (aLevel max: 1) ifAbsent: [ 14 ]!

contentStartOf: aBlock default: anInteger
	"The document index of a block's first content character, taken from its
	 inline map so that the markup prefix does not have to be guessed."
	| blockMap |
	blockMap := parser inlineMapOf: aBlock.
	blockMap isEmpty ifTrue: [ ^ anInteger ].
	^ blockMap first!

markerEndIn: anInterval pattern: aPattern
	"The document index of the last character of a line's leading marker, or
	 nil when the line does not open with one."
	| line found |
	line := parser lineAt: anInterval.
	found := aPattern asRegex matchingRangesIn: line.
	(found notEmpty
		and: [ found first first = 1 and: [ found first last > 0 ] ])
			ifFalse: [ ^ nil ].
	^ anInterval first + found first last - 1!

isHorizontalRuleSource: aString
	"GFM accepts ---, *** and ___ as rules.  Microdown only dispatches on
	 ***, so the other two arrive here as paragraph text."
	| trimmed |
	trimmed := aString trimBoth.
	trimmed size < 3 ifTrue: [ ^ false ].
	((trimmed reject: [ :char | char = $- ]) isEmpty) ifTrue: [ ^ true ].
	^ (trimmed reject: [ :char | char = $_ ]) isEmpty!

styleHorizontalRuleIn: aRange
	aRange ifNil: [ ^ self ].
	(self isNear: aRange)
		ifTrue: [ self dimFrom: aRange first to: aRange last ]
		ifFalse: [
			self replace: [ self horizontalRuleElement ] from: aRange first to: aRange last ]! !

!McMarkdownStylerVisitor methodsFor: 'stencils'!
horizontalRuleElement
	| rule |
	rule := BlElement new.
	rule size: 480 @ 1.
	rule background: (self paletteAt: 'rule').
	rule margin: (BlInsets top: 8 bottom: 8).
	^ rule!

bulletElement
	| bullet |
	bullet := BlTextElement new.
	bullet text: ((String with: (Character value: 8226)) asRopedText
		foreground: (self paletteAt: 'listMarker');
		fontSize: 16;
		yourself).
	bullet padding: (BlInsets left: 8 right: 8).
	^ bullet!

quoteBarElement
	| bar |
	bar := BlElement new.
	bar size: 3 @ 18.
	bar background: (self paletteAt: 'quoteBar').
	bar margin: (BlInsets left: 2 right: 10).
	^ bar! !
