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

Rule 1 turns on knowing what did not exist before, and the obvious way to decide
that is to collect the whole tree before the line and again after it.  That is
quadratic: every line walks every block parsed so far, so a document twice as
long costs four times as much, and a few hundred lines is already seconds.
Microdown only grows the tree in two places, though -- a line's node is appended
to the node that consumed it or to one of that node's ancestors, and closing a
node rebuilds its children out of its inline elements -- and both places are
open before the line or after it.  So the search is confined to those nodes,
and within each of them to the children not looked at yet, which makes a line
cost what it added rather than what the document already holds.  #probeCount
counts exactly that work, so the scaling can be asserted on without a clock.

Inline nodes are a different matter: MicBoldFormatBlock and friends DO carry
start/end, but relative to the string Microdown inline-parsed, which for a
multi-line paragraph is the lines concatenated with the newlines dropped.
sourceMapFor:content: rebuilds the index-by-index mapping back to the document
by aligning each source line against the content it contributed.

Chunk format: load with fileIn.
"!

MicrodownParser subclass: #McMarkdownParser
	instanceVariableNames: 'source ranges lineIntervals inlineSources knownBlocks scannedChildren probeCount'
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

probeCount
	"How many candidate slots the parser has had to look at: one per child of
	 an open node considered for being new, and one per line interval visited
	 while answering #lineIntervalsWithin:.  Both loops were once proportional
	 to the whole document and are now proportional to what is actually being
	 asked about, and this counter is what lets a test say so without a clock."
	^ probeCount!

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
	 intervals so that each line's offsets are known while it is handled.

	 The nodes a line created are found by looking only at the nodes that were
	 open across it, never by walking the whole tree; see
	 #discoverBlocksOpenBefore:stampingWith:."
	source := aString.
	ranges := IdentityDictionary new.
	inlineSources := IdentityDictionary new.
	knownBlocks := IdentitySet new.
	scannedChildren := IdentityDictionary new.
	probeCount := 0.
	lineIntervals := self computeLineIntervals: aString.
	current := root := self newRootBlock
		setParser: self;
		yourself.
	knownBlocks add: root.
	lineIntervals do: [ :each |
		| openBefore |
		openBefore := self openPath.
		self handleLine: (self lineAt: each).
		self discoverBlocksOpenBefore: openBefore stampingWith: each.
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

discoverBlocksOpenBefore: aPath stampingWith: anInterval
	"Stamp every node the line just handled created, aPath being the nodes
	 that were open before it ran, innermost first.

	 Only nodes that were open before the line or are open after it can have
	 gained a child.  Microdown appends a new node to the node that consumed
	 the line or to one of its ancestors -- MicElement>>parent: is what does
	 the appending -- and rebuilds a node's children from its inline elements
	 in #closeMe, which the line loop only ever calls on the node it is
	 closing and that node's ancestors.  Everything else in the tree was
	 finished by an earlier line and cannot change again.

	 The closed nodes are those open before the line and not after it.  For
	 them the count of children already examined means nothing -- header,
	 quote and paragraph blocks replace their children outright in #closeMe
	 and a list item prepends to them -- so their child list is examined from
	 the start again.  Nodes that stayed open only ever appended, so for those
	 the examination resumes where it left off."
	| openAfter stillOpen |
	openAfter := self openPath.
	stillOpen := IdentitySet new.
	openAfter do: [ :node | stillOpen add: node ].
	aPath do: [ :node |
		(stillOpen includes: node)
			ifFalse: [ scannedChildren removeKey: node ifAbsent: [ nil ] ] ].
	aPath do: [ :node | self discoverChildrenOf: node stampingWith: anInterval ].
	openAfter do: [ :node | self discoverChildrenOf: node stampingWith: anInterval ]!

discoverChildrenOf: aBlock stampingWith: anInterval
	"Examine the children of aBlock not examined yet, stamping the ones that
	 are new to us."
	| children size scanned |
	children := self childBlocksOf: aBlock.
	size := children size.
	scanned := scannedChildren at: aBlock ifAbsent: [ 0 ].
	scanned >= size ifTrue: [ ^ self ].
	scanned + 1 to: size do: [ :index |
		probeCount := probeCount + 1.
		self discoverBlock: (children at: index) stampingWith: anInterval ].
	scannedChildren at: aBlock put: size!

discoverBlock: aBlock stampingWith: anInterval
	"Record aBlock, and everything below it, as created by anInterval's line.
	 A node we already know keeps the range it was first given: closing a
	 block reorders and re-parents children without creating them."
	| children |
	(knownBlocks includes: aBlock) ifTrue: [ ^ self ].
	knownBlocks add: aBlock.
	self stamp: aBlock with: anInterval.
	children := self childBlocksOf: aBlock.
	children do: [ :each | self discoverBlock: each stampingWith: anInterval ].
	scannedChildren at: aBlock put: children size!

childBlocksOf: aBlock
	"aBlock's children as a sequence, empty when it has none.

	 MicHeaderBlock parks its raw text in `children' until #closeMe replaces
	 it with the inline parse, so there the child list is a String.  Answering
	 empty for that keeps single Characters out of the range table, where they
	 could only ever be noise: Characters are shared image-wide, so one range
	 per character is one range shared by every header that uses it."
	| children |
	(aBlock respondsTo: #children) ifFalse: [ ^ #() ].
	children := aBlock children.
	(children isNil or: [ children isString ]) ifTrue: [ ^ #() ].
	^ children!

openPath
	"The nodes still open, from `current' up to and including the root."
	| result node |
	result := OrderedCollection new.
	node := current.
	[ node isNil ] whileFalse: [
		result add: node.
		node == root ifTrue: [ ^ result ].
		node := node parent ].
	^ result!

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
	 whole lines, so a line is in when its start is.

	 #computeLineIntervals: emits the lines in order and each one starts after
	 the previous one ends, so the starts strictly increase and the lines of a
	 range are a contiguous run.  Finding it by binary search rather than by
	 filtering the whole document matters because the styler asks this
	 question once per block, and per line of a quote or a table on top of
	 that: filtering made styling cost the document squared."
	| low high mid first last size |
	aRange ifNil: [ ^ #() ].
	size := lineIntervals size.
	low := 1.
	high := size.
	first := size + 1.
	[ low <= high ] whileTrue: [
		probeCount := probeCount + 1.
		mid := low + high // 2.
		((lineIntervals at: mid) first >= aRange first)
			ifTrue: [ first := mid. high := mid - 1 ]
			ifFalse: [ low := mid + 1 ] ].
	last := first - 1.
	[ last < size
		and: [ (lineIntervals at: last + 1) first <= aRange last ] ]
			whileTrue: [
				probeCount := probeCount + 1.
				last := last + 1 ].
	^ lineIntervals copyFrom: first to: last!

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
	instanceVariableNames: 'parser text cursor palette owner trusted'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownStylerVisitor commentStamp: '' prior: 0!
Walks a Microdown AST and decorates a BlText with the attributes that project
it, choosing between raw source and rendered form per node by cursor locality.

The visitor never touches the source rope -- it only adds attributes, so the
document text stays the single source of truth and every projection is
reversible by moving the cursor.

Inline decoration -- emphasis and this editor's own tokens alike -- is not
done here.  Each block visit hands its inline source and index map to
McMarkdownInlineStyler, which is the same component a table cell uses to style
its own private rope.!

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
	owner := anOwner! !

!McMarkdownStylerVisitor methodsFor: 'accessing'!
paletteAt: aKey
	^ palette at: aKey ifAbsent: [ Color gray ]!

trusted: aBoolean
	"Force the trust decision instead of taking it from the owner.  For a
	 headless render and for tests, which have no editor to ask."
	trusted := aBoolean!

isTrustedDocument
	"Whether this document's blocks may be run.  Untrusted is the default
	 and the answer whenever there is nobody to ask, so no Run button is
	 drawn at all until the reader asks for one."
	trusted ifNotNil: [ ^ trusted ].
	owner ifNil: [ ^ false ].
	^ [ owner isTrustedDocument = true ] on: Error do: [ :e | false ]!

codeClass
	"Dynamic, so an incremental reload of this file does not disable older
	 widgets when McMarkdownCode has not been filed in yet."
	^ Smalltalk at: #McMarkdownCode ifAbsent: [ nil ]!

evaluatorClass
	^ Smalltalk at: #McCodeEvaluator ifAbsent: [ nil ]! !

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
		to: stop!

append: aStencil from: start to: stop
	self
		apply: (BrTextAdornmentDynamicAttribute new beAppend; stencil: aStencil)
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
	"Hand the block's inline source to the shared styler.  The block's inline
	 string is not its document substring -- Microdown joins the lines with a
	 CR and strips the markup prefix -- so the parser's index map is what
	 relates the two, and it serves as both the target and the document map
	 because the rope being decorated is the document."
	| inlineSource blockMap |
	inlineSource := parser inlineSourceOf: aBlock.
	blockMap := parser inlineMapOf: aBlock.
	(inlineSource isNil or: [ blockMap isNil ]) ifTrue: [ ^ self ].
	(McMarkdownInlineStyler
		source: inlineSource
		targetMap: blockMap
		documentMap: blockMap
		text: text
		cursor: cursor
		palette: palette
		owner: owner) styleAll! !

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
	 fence lines when the cursor is elsewhere.

	 The info string decides what a fence is.  sql&db= is a database view and
	 has its own renderer.  results{...} is output written by a previous run.
	 A bare language name is code that can be evaluated, and in a document
	 that has been trusted it gets a Run button.  Anything else is an
	 ordinary code block, styled exactly as it always was."
	| range lines info language |
	range := parser rangeOf: aCodeBlock.
	range ifNil: [ ^ self ].
	lines := parser lineIntervalsWithin: range.
	lines isEmpty ifTrue: [ ^ self ].
	info := aCodeBlock firstLine ifNil: [ '' ].
	((info beginsWith: 'sql&db=') and: [ (self isNear: range) not ])
		ifTrue: [ ^ self visitDatabaseView: aCodeBlock range: range info: info ].
	language := self codeClass
		ifNil: [ nil ]
		ifNotNil: [ :c |
			(c isResultsInfo: info)
				ifTrue: [ #results ]
				ifFalse: [ c languageFromInfo: info ] ].
	(language == #results and: [ (self isNear: range) not ])
		ifTrue: [ ^ self visitResultsBlock: aCodeBlock range: range info: info ].
	language == #results ifTrue: [ language := nil ].
	self
		styleCodeBlockIn: range
		lines: lines
		closingFenceReplaced: (language notNil
			and: [ self isTrustedDocument
			and: [ (self isNear: range) not
			and: [ lines size > 1 ] ] ]).
	(language notNil and: [ self isTrustedDocument ]) ifTrue: [
		self runButtonFor: aCodeBlock range: range lines: lines language: language ]!

styleCodeBlockIn: aRange lines: lines closingFenceReplaced: aBoolean
	"The ordinary code-block projection.  aBoolean says the closing fence is
	 about to be replaced by a Run button, so it must not also be hidden --
	 a hide attribute and an adornment over the same characters render
	 unpredictably."
	self monospaceFrom: aRange first to: aRange last.
	self fontSize: 14 from: aRange first to: aRange last.
	self background: (self paletteAt: 'codeBg') from: aRange first to: aRange last.
	self foreground: (self paletteAt: 'codeText') from: aRange first to: aRange last.
	(self isNear: aRange) ifTrue: [
		self dimFrom: lines first first to: lines first last.
		lines size > 1 ifTrue: [ self dimFrom: lines last first to: lines last last ].
		^ self ].
	"Cursor away: hide each fence together with the line break it owns, so the
	 block closes up instead of leaving two blank lines behind."
	self hideFrom: lines first first to: lines first last + 1.
	(lines size > 1 and: [ aBoolean not ]) ifTrue: [
		self hideFrom: lines last first - 1 to: lines last last ]!

visitUnorderedList: aList
	aList children doWithIndex: [ :item :index |
		self styleListItem: item marker: nil ]!

visitOrderedList: aList
	aList children doWithIndex: [ :item :index |
		self styleListItem: item marker: index ]! !

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
	 pipe rows is replaced by one grid element built from the relation.  The
	 reader is captured by the sort action, which turns a header click into
	 an ordinary document edit."
	| range reader |
	range := parser rangeOf: aTable.
	range ifNil: [ ^ self ].
	(self isNear: range) ifTrue: [ ^ self styleTableSourceIn: range ].
	reader := McMarkdownTableReader
		forSource: parser source
		range: range
		lineIntervals: (parser lineIntervalsWithin: range).
	"columnCount, not rowCount: a header and separator with no data rows yet
	 is the state every table passes through while it is being typed, and it
	 has a header worth drawing.  Guarding on rowCount showed raw pipes
	 there."
	reader relation columnCount = 0 ifTrue: [ ^ self ].
	"But a separator row is what makes a run of pipes a table at all.
	 Microdown answers a MicTableBlock for any line holding pipes, so on
	 columnCount alone a lone '| a | b |' -- an ordinary sentence with pipes
	 in it, or the header line of a table one keystroke before its separator
	 exists -- became a bordered grid of empty cells with its own text
	 hidden underneath.  A table with a separator and no rows still renders
	 its header; one without a separator only renders once it has rows, as
	 it did before."
	(reader relation rowCount = 0 and: [ reader hasSeparatorRow not ])
		ifTrue: [ ^ self ].
	self
		replace: [
			| element |
			element := McMarkdownTableElement
				relation: reader relation
				palette: palette
				owner: owner.
			owner ifNotNil: [
				element sortAction: [ :columnIndex :ascending |
					self applySortFrom: reader column: columnIndex ascending: ascending ] ].
			element build ]
		from: range first
		to: range last!

applySortFrom: aReader column: aColumnIndex ascending: aBoolean
	"Sorting is an edit to the document, not a property of the view."
	| edit |
	owner ifNil: [ ^ self ].
	edit := aReader sortEditBy: aColumnIndex ascending: aBoolean.
	edit ifNil: [ ^ self ].
	owner replaceFrom: edit key first to: edit key last with: edit value!

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

isDelimiterLine: aString
	| trimmed |
	trimmed := aString trimBoth.
	trimmed isEmpty ifTrue: [ ^ false ].
	(trimmed includes: $-) ifFalse: [ ^ false ].
	^ (trimmed reject: [ :char |
		char = $- or: [ char = $: or: [ char = $| or: [ char = $  ] ] ] ]) isEmpty! !

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

!McMarkdownStylerVisitor methodsFor: 'visiting - code blocks'!
visitResultsBlock: aCodeBlock range: aRange info: anInfoString
	"Output written into the document by a previous run.

	 Rendered with the moment it was produced along its top edge, because a
	 result with no timestamp cannot be told apart from a result that is no
	 longer true -- which is the complaint org-babel's bare #+RESULTS earns."
	| stamp body pal |
	stamp := self codeClass resultsTimestampFrom: anInfoString.
	body := aCodeBlock body ifNil: [ '' ].
	"Captured for the stencil closure, which Bloc evaluates at render time."
	pal := palette.
	self
		replace: [ self resultsElementFor: body stamp: stamp palette: pal ]
		from: aRange first
		to: aRange first.
	aRange first + 1 <= aRange last ifTrue: [
		self hideFrom: aRange first + 1 to: aRange last ]!

runButtonFor: aCodeBlock range: aRange lines: lines language: aLanguage
	"A Run button under the block, in a trusted document, always.

	 Always: it does not vanish after a successful run and it does not vanish
	 after a failed one.  An org-babel block is re-evaluatable whenever you
	 are looking at it, for better or worse, and this copies that.  In an
	 untrusted document no button is drawn at all.

	 Where it goes depends on the cursor.  Away from the block the closing
	 fence is replaced by the button, so the block reads as code followed by
	 its control; on the block the source is showing and the button is
	 appended after it, so editing the block never takes the button away."
	| code stencil documentSource |
	"The source as it stands at this render.  The write-back computes offsets
	 against it rather than against whatever the document later becomes; the
	 editor restyles after every edit, so it is current as of the last render
	 -- the same bargain a checkbox in a table cell already makes with the
	 document index it captures."
	documentSource := parser source.
	code := self codeClass
		blockLanguage: aLanguage
		expression: (aCodeBlock body ifNil: [ '' ])
		start: aRange first
		stop: aRange last.
	stencil := [ self runElementFor: code source: documentSource ].
	(self isNear: aRange)
		ifTrue: [ self append: stencil from: aRange last to: aRange last ]
		ifFalse: [
			lines size > 1
				ifTrue: [ self replace: stencil from: lines last first - 1 to: lines last last ]
				ifFalse: [ self append: stencil from: aRange last to: aRange last ] ]!

runBlock: aCode source: aSource
	"Evaluate one block because the reader asked.

	 The result is applied on whichever process learns it: at once when the
	 cache or an in-image evaluator can answer, and otherwise from the
	 background job through the editor's task queue.  The completion block
	 closes over the owner, the node and the source string and nothing else
	 -- capturing the visitor would hold a rope and a parser alive for as
	 long as the evaluation ran, and both are stale the moment the document
	 changes."
	| evaluator anOwner result |
	evaluator := self evaluatorClass.
	evaluator ifNil: [ ^ self ].
	anOwner := owner.
	anOwner ifNil: [ ^ self ].
	result := evaluator
		resultFor: aCode
		token: aCode cacheKey
		onComplete: [ :landed |
			self class applyLater: landed for: aCode source: aSource owner: anOwner ].
	result isPending
		ifTrue: [ self class requestRestyleFor: anOwner ]
		ifFalse: [ self class apply: result for: aCode source: aSource owner: anOwner ]! !

!McMarkdownStylerVisitor class methodsFor: 'running blocks'!
apply: aResult for: aCode source: aSource owner: anOwner
	"Record what a run produced.

	 On success a results fence is written into the document, so the result
	 outlives the session and is legible to every other markdown tool.  On
	 failure nothing is written, and any results fence left by an earlier
	 successful run is removed -- a stale success must not outlive the code
	 that produced it.  The failure itself is shown beside the button, out of
	 the evaluator's cache, so it costs the document nothing."
	| codeClass range replacement |
	codeClass := Smalltalk at: #McMarkdownCode ifAbsent: [ nil ].
	codeClass ifNil: [ ^ self ].
	range := [ codeClass resultsRangeIn: aSource after: aCode stop ]
		on: Error
		do: [ :e | nil ].
	aResult isReady ifFalse: [
		"Nothing to write and nothing stale to clear: just show the error."
		range ifNil: [ ^ self requestRestyleFor: anOwner ].
		^ self write: '' over: range for: anOwner ].
	replacement := codeClass resultsFenceFor: aResult output at: aResult evaluatedAt.
	range
		ifNil: [ self insert: replacement at: aCode stop for: anOwner ]
		ifNotNil: [ self write: replacement over: range for: anOwner ]!

write: aString over: aRange for: anOwner
	[ anOwner replaceFrom: aRange first to: aRange last with: aString ]
		on: Error
		do: [ :e | nil ]!

insert: aString at: anIndex for: anOwner
	"An empty range is an insertion: replaceFrom:to:with: deletes nothing
	 when its stop precedes its start."
	[ anOwner replaceFrom: anIndex + 1 to: anIndex with: aString ]
		on: Error
		do: [ :e | nil ]!

applyLater: aResult for: aCode source: aSource owner: anOwner
	"Called from the background job.  Hops to the UI process before touching
	 the document, because the rope may only be edited there."
	| element |
	element := [ anOwner editorElement ] on: Error do: [ :e | nil ].
	element ifNil: [ ^ self ].
	element enqueueTask: (BlTaskAction new action: [
		[ self apply: aResult for: aCode source: aSource owner: anOwner ]
			on: Error
			do: [ :e | nil ] ])!

requestRestyleFor: anOwner
	"Ask for a re-render without touching the rope.  A write does not need
	 this -- replaceFrom:to:with: restyles on its own -- but showing a
	 failure beside the button does, because nothing in the document changed."
	| element |
	element := [ anOwner editorElement ] on: Error do: [ :e | nil ].
	element ifNil: [ ^ self ].
	element enqueueTask: (BlTaskAction new action: [
		[ element editor styleText ] on: Error do: [ :e | nil ] ])! !

!McMarkdownStylerVisitor methodsFor: 'stencils - code blocks'!
runElementFor: aCode source: aSource
	"The Run button, and beside it whatever the last run left behind.

	 A success leaves nothing here: it is written into the document as a
	 results fence and rendered as one.  A failure leaves its message, taken
	 from the evaluator's cache, so it costs the document nothing and
	 disappears of its own accord when the next run succeeds."
	| row button evaluator cached |
	row := BlElement new.
	row layout: BlLinearLayout horizontal.
	row constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
	row margin: (BlInsets top: 2 bottom: 2).
	button := BrButton new.
	button label: 'Run ' , aCode language.
	button aptitude: BrGlamorousButtonWithLabelAptitude new.
	button beSmallSize.
	button action: [ self runBlock: aCode source: aSource ].
	row addChild: button.
	evaluator := self evaluatorClass.
	evaluator ifNil: [ ^ row ].
	([ evaluator isPendingFor: aCode cacheKey ] on: Error do: [ :e | false ])
		ifTrue: [
			row addChild: (self runNote: 'running...' colour: (self paletteAt: 'status')).
			^ row ].
	cached := [ evaluator cachedAt: aCode cacheKey ] on: Error do: [ :e | nil ].
	(cached notNil and: [ cached isFailed ]) ifTrue: [
		row addChild: (self runNote: cached message colour: (self paletteAt: 'deadLink')) ].
	^ row!

runNote: aString colour: aColor
	| label |
	label := BlTextElement new.
	label text: (aString asRopedText foreground: aColor; fontSize: 12).
	label margin: (BlInsets left: 8).
	label constraintsDo: [ :c | c linear vertical alignCenter ].
	^ label!

resultsElementFor: aBody stamp: aStampOrNil palette: aPalette
	"A results fence, rendered.  The timestamp sits along the top edge in
	 small dim text: it is not the content, but without it a result cannot be
	 told apart from one that stopped being true some time ago."
	| container header body |
	container := BlElement new.
	container layout: BlLinearLayout vertical.
	container constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
	container padding: (BlInsets all: 8).
	container margin: (BlInsets top: 2 bottom: 2).
	container border: (BlBorder
		paint: (aPalette at: 'tableBorder' ifAbsent: [ Color gray ])
		width: 1).
	container background: (aPalette at: 'codeBg' ifAbsent: [ Color veryLightGray ]).
	header := BlTextElement new.
	header text: (('result  ' , (aStampOrNil ifNil: [ 'unstamped' ])) asRopedText
		foreground: (aPalette at: 'dimDelimiter' ifAbsent: [ Color gray ]);
		fontSize: 10).
	header margin: (BlInsets bottom: 4).
	container addChild: header.
	body := BlTextElement new.
	body text: (aBody asRopedText
		foreground: (aPalette at: 'codeText' ifAbsent: [ Color black ]);
		fontSize: 13).
	container addChild: body.
	^ container! !

!McMarkdownStylerVisitor methodsFor: 'visiting - database views'!
visitDatabaseView: aCodeBlock range: aRange info: anInfoString
	"Replace the whole fence with a table widget when the query has
	 succeeded, an error box with a retry button when it has failed, and a
	 placeholder while it is still running.

	 The styler is asked for the result rather than for the query: it takes
	 whatever McSqliteSource already knows and never waits.  A cold query
	 answers `pending' and starts a job on a background process, and this
	 pass draws the placeholder and returns.  When the job lands it does not
	 touch this rope -- which by then may be several keystrokes out of date,
	 or gone -- it asks the editor to restyle, and the restyle reparses
	 whatever the document has become and finds the result waiting in the
	 cache.  That is the whole of the version safety: nothing computed
	 against the old document is ever applied to the new one.

	 With no owner -- a headless render, a test -- there is nowhere to send
	 a restyle request to, so the query is resolved on this process instead
	 and the fence renders its result in one pass."
	| dbPath sql source result pal |
	dbPath := anInfoString copyFrom: 'sql&db=' size + 1 to: anInfoString size.
	sql := aCodeBlock body ifNil: [ '' ].
	sql := sql trimBoth.
	source := McSqliteSource on: dbPath.
	result := owner
		ifNil: [ source resolveNow: sql ]
		ifNotNil: [ :anOwner |
			source
				queryAsync: sql
				token: anOwner
				onComplete: (self restyleRequestFor: anOwner) ].
	"Captured for the stencil closure, which Bloc evaluates at render time."
	pal := palette.
	self
		replace: [ self dbElementFor: result dbPath: dbPath sql: sql palette: pal ]
		from: aRange first
		to: aRange first.
	aRange first + 1 <= aRange last ifTrue: [
		self hideFrom: aRange first + 1 to: aRange last ]!

restyleRequestFor: anOwner
	"A one-argument block for McSqliteSource to call when a query finishes.

	 It runs on the background query process, so it does two things and no
	 more: it hops to the UI process through the editor's task queue, and
	 there it asks for a restyle.  It never reads or writes the rope, so
	 there is no stale document to get wrong -- if the fence has been edited
	 or deleted in the meantime the restyle simply does not ask for that
	 query again.

	 Closed over anOwner alone, deliberately: capturing the visitor would
	 hold its rope and its parser alive for as long as the query ran."
	^ [ :ignoredResult |
		| element |
		element := [ anOwner editorElement ] on: Error do: [ :e | nil ].
		element ifNotNil: [
			element enqueueTask: (BlTaskAction new action: [
				[ element editor styleText ] on: Error do: [ :e | nil ] ]) ] ]!

dbElementFor: aResult dbPath: aDbPath sql: aSql palette: aPalette
	aResult isReady ifTrue: [
		^ (McMarkdownTableElement
			relation: aResult relation palette: aPalette owner: nil) build ].
	aResult isFailed ifTrue: [
		^ self dbErrorElementFor: aResult message dbPath: aDbPath sql: aSql ].
	^ self dbPendingElementFor: aDbPath sql: aSql!

dbPendingElementFor: aDbPath sql: aSql
	"What stands in for the table while the query runs.

	 Sized and bordered like the error box so that the fence does not jump
	 when the real answer arrives, and worded so that a query which never
	 answers is visibly a query that never answered rather than a blank."
	| container label detail |
	container := BlElement new.
	container layout: BlLinearLayout vertical.
	container constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
	container padding: (BlInsets all: 10).
	container margin: (BlInsets top: 2 bottom: 2).
	container border: (BlBorder paint: (self paletteAt: 'tableBorder') width: 1).
	container background: (self paletteAt: 'codeBg').
	label := BlTextElement new.
	label text: ('Running query...' asRopedText
		foreground: (self paletteAt: 'status');
		fontSize: 13).
	label margin: (BlInsets bottom: 4).
	detail := BlTextElement new.
	detail text: (('db=' , aDbPath , '  sql=' , aSql) asRopedText
		foreground: (self paletteAt: 'dimDelimiter');
		fontSize: 12).
	container addChild: label.
	container addChild: detail.
	^ container!

dbErrorElementFor: aMessage dbPath: aDbPath sql: aSql
	"A bordered box showing the error, the query that caused it, and a retry
	 button.  Retry drops every cached answer and restyles, which asks for
	 the query afresh; if it succeeds this time -- because the database has
	 appeared, or been fixed -- the box is replaced by the table.

	 A cached failure does not normally need the button: it is stamped with
	 the state of the database file, so it invalidates itself the moment the
	 file appears or changes.  The button is for the failure that stamping
	 cannot see, such as a database that is there and readable but was busy."
	| container label detail button |
	container := BlElement new.
	container layout: BlLinearLayout vertical.
	container constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
	container padding: (BlInsets all: 10).
	container margin: (BlInsets top: 2 bottom: 2).
	container border: (BlBorder paint: (Color red alpha: 0.5) width: 1).
	container background: ((self paletteAt: 'codeBg') mixed: 0.1 with: Color red).
	label := BlTextElement new.
	label text: (aMessage asRopedText
		foreground: (Color red darker);
		fontSize: 13;
		bold).
	label margin: (BlInsets bottom: 4).
	detail := BlTextElement new.
	detail text: (('db=' , aDbPath , '  sql=' , aSql) asRopedText
		foreground: (self paletteAt: 'dimDelimiter');
		fontSize: 12).
	detail margin: (BlInsets bottom: 6).
	button := BrButton new.
	button aptitude: BrGlamorousButtonWithLabelAptitude new.
	button label: 'Retry'.
	button beSmallSize.
	button action: [ :btn |
		McSqliteSource clearCache.
		owner ifNotNil: [ owner editorElement editor styleText ] ].
	container addChild: label.
	container addChild: detail.
	container addChild: button.
	^ container! !
