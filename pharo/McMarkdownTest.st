"
McMarkdownTest -- tests for the parse/AST/style pipeline in McMarkdown.st.

Two things are worth testing here and they are quite different.

The parser tests pin down source offsets, because everything else depends on
them: Microdown discards offsets, McMarkdownParser reconstructs them, and a
silent off-by-one there shows up as a delimiter hidden one character to the
left rather than as a crash.  Each test asserts on the substring a range picks
out, not on the numbers, so a failure says what was selected.

The styler tests assert on which attributes land where, for a cursor that is
away from an element and again for a cursor on it.  That pair is the whole
point of the projection: away renders, near reveals the source.

A third kind came in with the incremental range tracking.  The parser no
longer rediscovers the whole tree after every line, and the way to be sure
that shortcut costs nothing is to keep the version it replaced --
McMarkdownReferenceParser, at the foot of this file -- and assert the two
agree node for node over a corpus that is mostly malformed markup, and over
every prefix of a document besides.  The scaling is asserted the same way:
McMarkdownParser>>probeCount counts the work the parser does, so a return to
quadratic fails a test rather than a stopwatch, and fails it the same way on
every machine.

Chunk format: load with fileIn.
"!

TestCase subclass: #McMarkdownTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownTest methodsFor: 'helpers'!
palette
	"A palette holding every key the visitor asks for.  Built here rather than
	 taken from McRichEdit so the pipeline can be tested without the UI."
	^ Dictionary new
		at: 'text' put: (Color fromHexString: '#333333');
		at: 'title' put: (Color fromHexString: '#222222');
		at: 'boldText' put: (Color fromHexString: '#111111');
		at: 'dimDelimiter' put: (Color fromHexString: '#bbbbbb');
		at: 'highlight' put: (Color fromHexString: '#7f5af0');
		at: 'editorBg' put: Color white;
		at: 'codeBg' put: (Color fromHexString: '#f2f2f5');
		at: 'codeText' put: (Color fromHexString: '#2d2d2d');
		at: 'rule' put: (Color fromHexString: '#d0d0d0');
		at: 'tableBorder' put: (Color fromHexString: '#d5d5dd');
		at: 'tableHeaderBg' put: (Color fromHexString: '#eeeef2');
		at: 'quoteBar' put: (Color fromHexString: '#7f5af0');
		at: 'quoteText' put: (Color fromHexString: '#555555');
		at: 'listMarker' put: (Color fromHexString: '#7f5af0');
		yourself!

parse: aString
	^ McMarkdownParser parseSource: aString!

style: aString cursor: anInteger
	"Style aString as the editor would and answer the decorated text."
	| text parser |
	text := aString asRopedText.
	parser := McMarkdownParser parseSource: aString.
	(McMarkdownStylerVisitor
		parser: parser
		text: text
		cursor: anInteger
		palette: self palette
		owner: nil) visit: parser root.
	^ text!

styleAway: aString
	"Style with the cursor nowhere near, so every element renders."
	^ self style: aString cursor: -1!

in: aText hasAttribute: aClass at: anIndex
	^ (aText attributesAt: anIndex) anySatisfy: [ :each | each isKindOf: aClass ]!

sourceOf: aBlock in: aParser
	^ aParser sourceOf: aBlock!

blocksOf: aString
	^ (self parse: aString) root children! !

!McMarkdownTest methodsFor: 'tests - block ranges'!
testHeaderRange
	| parser |
	parser := self parse: '# Title
body'.
	self assert: (parser sourceOf: parser root children first) equals: '# Title'!

testParagraphRangeSpansItsLines
	| parser |
	parser := self parse: 'one line
two line

after'.
	self
		assert: (parser sourceOf: parser root children first)
		equals: 'one line
two line'!

testTableRangeSpansEveryRow
	| parser source |
	source := '| a | b |
|---|---|
| 1 | 2 |

after'.
	parser := self parse: source.
	self
		assert: (parser sourceOf: parser root children first)
		equals: '| a | b |
|---|---|
| 1 | 2 |'!

testCodeBlockRangeIncludesBothFences
	| parser source |
	source := '```st
1 + 2
```'.
	parser := self parse: source.
	self assert: (parser sourceOf: parser root children first) equals: source!

testListItemRangesAreSeparate
	| parser items |
	parser := self parse: '- one
- two'.
	items := parser root children first children.
	self assert: items size equals: 2.
	self assert: (parser sourceOf: items first) equals: '- one'.
	self assert: (parser sourceOf: items second) equals: '- two'!

testRangesSurviveCarriageReturnLineEndings
	"Text typed into a Bloc editor need not use the same terminator as text
	 filed in from disk, so both have to work."
	| parser source |
	source := String streamContents: [ :stream |
		stream nextPutAll: '# Title'; cr; cr; nextPutAll: 'body' ].
	parser := self parse: source.
	self assert: (parser sourceOf: parser root children first) equals: '# Title'.
	self assert: (parser sourceOf: parser root children second) equals: 'body'!

testEmptySourceParsesToNoBlocks
	self assert: (self parse: '') root children isEmpty! !

!McMarkdownTest methodsFor: 'tests - inline offsets'!
assertInlineOf: aBlock in: aParser source: aSource picksOut: aCollection
	"Check that the inline children carrying a source range select exactly
	 aCollection, in order."
	| map found |
	map := aParser inlineMapOf: aBlock.
	found := OrderedCollection new.
	aBlock children do: [ :node |
		| range |
		range := aParser sourceRangeOf: node within: map.
		range ifNotNil: [
			found add: (aSource copyFrom: range first to: range last) ] ].
	self assert: found asArray equals: aCollection!

testBoldOffsetsInParagraph
	| source parser |
	source := 'a **bold** z'.
	parser := self parse: source.
	self
		assertInlineOf: parser root children first
		in: parser
		source: source
		picksOut: #('a ' '**bold**' ' z')!

testInlineOffsetsSurviveALineBreak
	"Microdown joins a paragraph's lines with a single CR before inline
	 parsing, so offsets past the first line are shifted relative to the
	 document.  This is the case the naive mapping gets wrong."
	| source parser |
	source := 'first line here
second with **more bold** in it'.
	parser := self parse: source.
	self
		assertInlineOf: parser root children first
		in: parser
		source: source
		picksOut: (Array
			with: 'first line here
second with '
			with: '**more bold**'
			with: ' in it')!

testInlineOffsetsSkipTheHeaderPrefix
	| source parser |
	source := '## A **big** head'.
	parser := self parse: source.
	self
		assertInlineOf: parser root children first
		in: parser
		source: source
		picksOut: #('A ' '**big**' ' head')!

testInlineOffsetsSkipTheQuotePrefixOnEveryLine
	| source parser |
	source := '> plain here
> and **quoted bold**'.
	parser := self parse: source.
	self
		assertInlineOf: parser root children first
		in: parser
		source: source
		picksOut: (Array
			with: 'plain here
> and '
			with: '**quoted bold**')!

testInlineOffsetsSkipTheListMarker
	| source parser |
	source := '- item with **listed bold**'.
	parser := self parse: source.
	self
		assertInlineOf: parser root children first children first
		in: parser
		source: source
		picksOut: #('item with ' '**listed bold**')!

testItalicOffsets
	| source parser |
	source := 'a _it_ z'.
	parser := self parse: source.
	self
		assertInlineOf: parser root children first
		in: parser
		source: source
		picksOut: #('a ' '_it_' ' z')! !

!McMarkdownTest methodsFor: 'tests - styling emphasis'!
testBoldHidesDelimitersAndBoldsInnerWhenCursorAway
	| text |
	text := self styleAway: 'a **bold** z'.
	"** at 3-4 and 9-10, inner at 5-8."
	self assert: (self in: text hasAttribute: BrTextHideAttribute at: 3).
	self assert: (self in: text hasAttribute: BrTextHideAttribute at: 10).
	self deny: (self in: text hasAttribute: BrTextHideAttribute at: 5).
	self assert: (self in: text hasAttribute: BlFontWeightAttribute at: 5)!

testBoldRevealsDelimitersWhenCursorIsOnIt
	| text |
	text := self style: 'a **bold** z' cursor: 5.
	self deny: (self in: text hasAttribute: BrTextHideAttribute at: 3).
	self deny: (self in: text hasAttribute: BrTextHideAttribute at: 10)!

testItalicHidesDelimitersWhenCursorAway
	| text |
	text := self styleAway: 'a _it_ z'.
	self assert: (self in: text hasAttribute: BrTextHideAttribute at: 3).
	self assert: (self in: text hasAttribute: BrTextHideAttribute at: 6).
	self deny: (self in: text hasAttribute: BrTextHideAttribute at: 4)!

testMonospaceHidesBackticksWhenCursorAway
	| text |
	text := self styleAway: 'a `code` z'.
	self assert: (self in: text hasAttribute: BrTextHideAttribute at: 3).
	self assert: (self in: text hasAttribute: BrTextHideAttribute at: 8).
	self assert: (self in: text hasAttribute: BlFontFamilyAttribute at: 4)! !

!McMarkdownTest methodsFor: 'tests - styling blocks'!
testHeaderHidesItsPrefixWhenCursorAway
	| text |
	text := self styleAway: '## Head'.
	self assert: (self in: text hasAttribute: BrTextHideAttribute at: 1).
	self assert: (self in: text hasAttribute: BrTextHideAttribute at: 3).
	self deny: (self in: text hasAttribute: BrTextHideAttribute at: 4).
	self assert: (self in: text hasAttribute: BlFontSizeAttribute at: 4)!

testHeaderRevealsItsPrefixWhenCursorIsOnIt
	| text |
	text := self style: '## Head' cursor: 4.
	self deny: (self in: text hasAttribute: BrTextHideAttribute at: 1)!

testHeaderLevelsScaleDown
	"Each level must be strictly smaller than the one above it."
	| sizes |
	sizes := (1 to: 6) collect: [ :level |
		| source text attribute |
		source := (String new: level withAll: $#) , ' Head'.
		text := self styleAway: source.
		attribute := (text attributesAt: level + 2)
			detect: [ :each | each isKindOf: BlFontSizeAttribute ].
		attribute size ].
	self assert: sizes asArray equals: sizes asArray asSortedCollection asArray reversed!

testCodeBlockIsMonospacedAndTinted
	| text |
	text := self styleAway: '```st
1 + 2
```'.
	"Position 8 is inside the body."
	self assert: (self in: text hasAttribute: BlFontFamilyAttribute at: 8).
	self assert: (self in: text hasAttribute: BlTextUnderlayAttribute at: 8)!

testCodeBlockFencesCollapseWhenCursorAway
	| text |
	text := self styleAway: '```st
1 + 2
```'.
	self assert: (self in: text hasAttribute: BrTextHideAttribute at: 1).
	self deny: (self in: text hasAttribute: BrTextHideAttribute at: 8)!

testCodeBlockFencesStayWhenCursorIsOnIt
	| text |
	text := self style: '```st
1 + 2
```' cursor: 8.
	self deny: (self in: text hasAttribute: BrTextHideAttribute at: 1)!

testTableRendersAsOneAdornmentWhenCursorAway
	| text |
	text := self styleAway: '| a | b |
|---|---|
| 1 | 2 |'.
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 1)!

testTableShowsItsPipesWhenCursorIsOnIt
	| text |
	text := self style: '| a | b |
|---|---|
| 1 | 2 |' cursor: 3.
	self deny: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 1)!

testHorizontalRuleRendersForEveryGfmSpelling
	"GFM accepts ---, *** and ___.  Microdown only dispatches on ***, so the
	 other two have to be recognised by the styler."
	#('---' '***' '___') do: [ :each |
		| text |
		text := self styleAway: each.
		self
			assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 1)
			description: each , ' should render as a rule' ]!

testHorizontalRuleShowsItsSourceWhenCursorIsOnIt
	| text |
	text := self style: '---' cursor: 1.
	self deny: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 1)!

testDashesAreOnlyARuleWhenAloneOnTheLine
	| text |
	text := self styleAway: 'a -- b'.
	self deny: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 1)!

testUnorderedListMarkerBecomesABullet
	| text |
	text := self styleAway: '- one'.
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 1).
	self deny: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 3)!

testOrderedListKeepsItsNumber
	| text |
	text := self styleAway: '1. one'.
	self deny: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 1).
	self assert: (self in: text hasAttribute: BlTextForegroundAttribute at: 1)!

testQuoteMarkerBecomesABar
	| text |
	text := self styleAway: '> quoted'.
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 1).
	self assert: (self in: text hasAttribute: BlFontEmphasisAttribute at: 3)! !

!McMarkdownTest methodsFor: 'tests - robustness'!
testStylingSurvivesEveryCursorPositionOfTheDemoDocument
	"The styler runs on every keystroke and every cursor move.  An element
	 that raises only when the cursor sits at one particular offset would be
	 invisible in casual use and fatal in real use."
	| source |
	source := McRichEdit new demoContent.
	-1 to: source size do: [ :cursor |
		[ self style: source cursor: cursor ]
			on: Error
			do: [ :error |
				self fail: 'styling raised at cursor ' , cursor printString
					, ': ' , error messageText asString ] ]!

testStylingSurvivesPartialAndMalformedMarkup
	"Half-typed markup is the normal state of a document being edited."
	#( '**' '*' '_' '`' '#' '# ' '|' '| a' '| a |' '```' '```st' '- ' '1. '
	   '> ' '---' '**bold' 'bold**' '| a |
|--' '``` ' '#### ' ) do: [ :each |
		[ self styleAway: each ]
			on: Error
			do: [ :error |
				self fail: each printString , ' raised: '
					, error messageText asString ] ]!

testStylingAnEmptyDocumentDoesNothing
	self assert: (self styleAway: '') asString equals: ''! !

!McMarkdownTest methodsFor: 'tests - tables'!
testALoneTableRowDoesNotBreakParsing
	"MicTableBlock >> closeMe raised SubscriptOutOfBounds on a table that
	 contributed no rows, which is the state of every table the moment its
	 first pipe is typed.  McGtPatches patchMicrodownEmptyTable repairs it."
	self shouldnt: [ self styleAway: '|' ] raise: Error.
	self shouldnt: [ self styleAway: '|---|' ] raise: Error.
	self shouldnt: [ self parse: '|' ] raise: Error! !

!McMarkdownTest methodsFor: 'helpers - tables'!
readerFor: aString
	"Build a reader over the first table in aString."
	| parser table |
	parser := self parse: aString.
	table := parser root children
		detect: [ :each | each class name asString = 'MicTableBlock' ].
	^ McMarkdownTableReader
		source: parser source
		lineIntervals: (parser lineIntervalsWithin: (parser rangeOf: table))!

sourceOfCell: aCell in: aString
	"What a cell's interval actually selects, so failures name the text."
	aCell interval ifNil: [ ^ nil ].
	^ aString copyFrom: aCell interval first to: aCell interval last! !

!McMarkdownTest methodsFor: 'tests - table reader'!
testReaderFindsColumnsAndRows
	| source relation |
	source := '| name | qty |
|------|-----|
| fig  | 11  |
| pear | 3   |'.
	relation := (self readerFor: source) relation.
	self assert: (relation columns collect: [ :each | each name ]) asArray equals: #('name' 'qty').
	self assert: relation rowCount equals: 2.
	self assert: (relation at: 1 column: 1) text equals: 'fig'.
	self assert: (relation at: 2 column: 2) text equals: '3'!

testReaderRecordsCellIntervals
	"The interval is what lets a widget inside a cell write back."
	| source relation |
	source := '| name | qty |
|------|-----|
| fig  | 11  |'.
	relation := (self readerFor: source) relation.
	self
		assert: (self sourceOfCell: (relation at: 1 column: 1) in: source)
		equals: ' fig  '.
	self
		assert: (self sourceOfCell: (relation at: 1 column: 2) in: source)
		equals: ' 11  '!

testReaderRecordsRowIntervals
	| source relation |
	source := '| a |
|---|
| 1 |
| 2 |'.
	relation := (self readerFor: source) relation.
	self
		assert: (source copyFrom: (relation rowAt: 2) interval first to: (relation rowAt: 2) interval last)
		equals: '| 2 |'!

testReaderReadsPlainSeparatorRow
	"Microdown drops |---|---| and sets hasHeader; the reader must not
	 depend on which of the two spellings was used."
	| relation |
	relation := (self readerFor: '| a | b |
|---|---|
| 1 | 2 |') relation.
	self assert: relation rowCount equals: 1.
	self assert: (relation columns collect: [ :each | each alignment ]) asArray equals: #(#left #left)!

testReaderReadsAlignedSeparatorRow
	"Microdown keeps |:--|--:| as data with hasHeader false."
	| relation |
	relation := (self readerFor: '| a | b | c |
|:--|:-:|--:|
| 1 | 2 | 3 |') relation.
	self assert: relation rowCount equals: 1.
	self
		assert: (relation columns collect: [ :each | each alignment ]) asArray
		equals: #(#left #center #right)!

testReaderTreatsEscapedPipeAsContent
	| relation |
	relation := (self readerFor: '| a | b |
|---|---|
| x \| y | z |') relation.
	self assert: relation columnCount equals: 2.
	self assert: (relation at: 1 column: 1) text equals: 'x \| y'!

testReaderPadsRaggedRows
	| relation |
	relation := (self readerFor: '| a | b | c |
|---|---|---|
| 1 |
| 1 | 2 | 3 | 4 |') relation.
	self assert: (relation rowAt: 1) size equals: 3.
	self assert: (relation rowAt: 2) size equals: 3.
	self assert: (relation at: 1 column: 3) source equals: ''!

testReaderDefaultsToMarkdownCells
	self assert: (self readerFor: '| a |
|---|
| 1 |') relation directives cellsAreMarkdown! !

!McMarkdownTest methodsFor: 'tests - table sorting'!
testSortEditReordersRowLines
	| source edit |
	source := '| name | qty |
|------|-----|
| pear | 3   |
| fig  | 11  |'.
	edit := (self readerFor: source) sortEditBy: 1 ascending: true.
	self
		assert: edit value
		equals: '| fig  | 11  |
| pear | 3   |'!

testSortEditCoversOnlyTheDataRows
	"The header and separator must stay where they are."
	| source edit |
	source := '| name |
|------|
| b    |
| a    |'.
	edit := (self readerFor: source) sortEditBy: 1 ascending: true.
	self assert: (source copyFrom: edit key first to: edit key last) equals: '| b    |
| a    |'!

testSortEditSortsNumericallyByNumericColumn
	| source edit |
	source := '| n |
|---|
| 3 |
| 11 |
| 7 |'.
	edit := (self readerFor: source) sortEditBy: 1 ascending: true.
	self assert: edit value equals: '| 3 |
| 7 |
| 11 |'!

testSortEditDescending
	| source edit |
	source := '| n |
|---|
| 1 |
| 2 |'.
	edit := (self readerFor: source) sortEditBy: 1 ascending: false.
	self assert: edit value equals: '| 2 |
| 1 |'!

testSortEditIsNilWithNothingToReorder
	self
		assert: ((self readerFor: '| a |
|---|
| 1 |') sortEditBy: 1 ascending: true) isNil! !

!McMarkdownTest methodsFor: 'helpers - inline'!
styleFragment: aString cursor: anInteger
	"Style aString as a standalone fragment, the way a table cell is styled."
	| text |
	text := aString asRopedText.
	(McMarkdownInlineStyler
		source: aString
		targetMap: (McMarkdownInlineStyler identityMapOfSize: aString size)
		documentMap: (McMarkdownInlineStyler identityMapOfSize: aString size)
		text: text
		cursor: anInteger
		palette: self palette
		owner: nil) styleAll.
	^ text!

styleFragmentAway: aString
	^ self styleFragment: aString cursor: -1!

adornmentCountIn: aText
	"Counts widget replacements/appends (checkboxes, swatches, buttons), not
	 the plain BrTextHideAttribute used to collapse delimiters and fences --
	 which is itself, perhaps surprisingly, a kind of BrTextAdornmentAttribute."
	| count |
	count := 0.
	1 to: aText size do: [ :index |
		((aText attributesAt: index) anySatisfy: [ :each |
			each isKindOf: BrTextAdornmentDynamicAttribute ]) ifTrue: [ count := count + 1 ] ].
	^ count! !

!McMarkdownTest methodsFor: 'tests - inline styler'!
testFragmentStylesBold
	| text |
	text := self styleFragmentAway: 'a **b** c'.
	self assert: (self in: text hasAttribute: BlFontWeightAttribute at: 5).
	self assert: (self in: text hasAttribute: BrTextHideAttribute at: 3)!

testFragmentStylesItalic
	| text |
	text := self styleFragmentAway: 'a _b_ c'.
	self assert: (self in: text hasAttribute: BlFontEmphasisAttribute at: 4)!

testFragmentRevealsMarkupNearTheCursor
	| text |
	text := self styleFragment: 'a **b** c' cursor: 4.
	self deny: (self in: text hasAttribute: BrTextHideAttribute at: 3)!

testFragmentRendersACheckbox
	| text |
	text := self styleFragmentAway: '[ ] todo'.
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 1)!

testFragmentRendersAColourSwatch
	| text |
	text := self styleFragmentAway: 'pick #ff0000 now'.
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 6)!

testFragmentRendersAButton
	| text |
	text := self styleFragmentAway: 'press <<Go>> now'.
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 7)!

testFragmentLeavesLinksAlone
	"The emphasis width heuristic is only valid for symmetric delimiters.
	 Applied to a link it would hide the wrong halves of the source."
	| text |
	text := self styleFragmentAway: 'see [label](http://x) end'.
	1 to: text size do: [ :index |
		self deny: (self in: text hasAttribute: BrTextHideAttribute at: index) ]!

testFragmentLeavesImagesAlone
	| text |
	text := self styleFragmentAway: 'a !![alt](u.png) b'.
	1 to: text size do: [ :index |
		self deny: (self in: text hasAttribute: BrTextHideAttribute at: index) ]! !

!McMarkdownTest methodsFor: 'tests - inline scoping'!
testCustomTokensDoNotApplyInsideACodeFence
	"visitCode: never calls visitInlineChildrenOf:, so a fenced code block's
	 content is never handed to McMarkdownInlineStyler at all -- no custom
	 token can render inside one."
	| text |
	text := self styleAway: '```
[ ] not a checkbox
```'.
	self assert: (self adornmentCountIn: text) equals: 0!

testDocumentStillRendersCheckboxesInParagraphs
	| text |
	text := self styleAway: '[ ] a real one'.
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 1)!

testOverlappingTokensNeverNestTwoAdornments
	"Scoping the passes to one range stopped a widget from landing inside a
	 table's own adornment, but inside a single range the four passes still
	 ran over the same source knowing nothing of each other: measured, this
	 string put a checkbox beReplace inside a button beReplace, and a swatch
	 beAppend inside another, which is the same configuration as the
	 reported defect.  No character may carry two dynamic adornments."
	| text |
	text := self styleFragmentAway: '<<[ ] go>> and #ff0000 <<x #00ff00 y>>'.
	1 to: text size do: [ :index |
		self
			assert: ((text attributesAt: index)
				select: [ :each | each isKindOf: BrTextAdornmentDynamicAttribute ]) size <= 1
			description: 'two adornments at index ' , index printString ]!

testTheFirstPassToClaimARangeKeepsIt
	"styleAll's order is the precedence: emphasis, checkboxes, colours,
	 buttons.  The checkbox claims 3 to 5 first, so the button spanning the
	 whole token is skipped and its angle brackets stay literal text."
	| text |
	text := self styleFragmentAway: '<<[ ] go>>'.
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 3).
	self deny: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 1)!

testAdjacentTokensBothStillRender
	"The claim must reject only an intersection, not mere adjacency: two
	 tokens that touch are not nested."
	| text |
	text := self styleFragmentAway: '[ ]<<Go>>'.
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 1).
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 4)! !

!McMarkdownTest methodsFor: 'helpers - cells'!
elementForTable: aString
	| reader |
	reader := self readerFor: aString.
	^ McMarkdownTableElement
		relation: reader relation
		palette: self palette
		owner: nil!

cellTextIn: aString at: aRowIndex column: aColumnIndex
	| reader element |
	reader := self readerFor: aString.
	element := McMarkdownTableElement
		relation: reader relation
		palette: self palette
		owner: nil.
	^ element cellTextFor: (reader relation at: aRowIndex column: aColumnIndex)! !

!McMarkdownTest methodsFor: 'tests - cell rendering'!
testCellRendersBold
	"The reported defect: emphasis was flattened to a plain string one call
	 before it could be styled."
	| text |
	text := self cellTextIn: '| a |
|---|
| **fig** |' at: 1 column: 1.
	self assert: (self in: text hasAttribute: BlFontWeightAttribute at: 5)!

testCellRendersACheckboxAsAnAdornment
	| text |
	text := self cellTextIn: '| a |
|---|
| [ ] todo |' at: 1 column: 1.
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 3)!

testPlainCellHasNoAdornment
	| element text |
	element := self elementForTable: '| a |
|---|
| plain |'.
	text := element cellTextFor: ((self readerFor: '| a |
|---|
| plain |') relation at: 1 column: 1).
	self deny: (element hasAdornment: text)!

testPlainCellUsesTheCheapElement
	| element cell |
	element := self elementForTable: '| a |
|---|
| plain |'.
	cell := element
		cellElementFor: ((self readerFor: '| a |
|---|
| plain |') relation at: 1 column: 1)
		alignment: #left
		isHeader: false.
	self assert: cell class equals: BlTextElement!

testWidgetCellUsesAnEmbeddedEditor
	"Only the editor's segment machinery realises adornments."
	| element cell |
	element := self elementForTable: '| a |
|---|
| [ ] todo |'.
	cell := element
		cellElementFor: ((self readerFor: '| a |
|---|
| [ ] todo |') relation at: 1 column: 1)
		alignment: #left
		isHeader: false.
	self assert: cell class equals: BrEditorElement!

testBoldCellUsesAnEmbeddedEditor
	"BlTextElement honours neither adornments nor hide, so a cell holding
	 only bold text -- no widget -- still needs the embedded editor, or its
	 ** delimiters render visibly instead of collapsing."
	| element cell |
	element := self elementForTable: '| a |
|---|
| **fig** |'.
	cell := element
		cellElementFor: ((self readerFor: '| a |
|---|
| **fig** |') relation at: 1 column: 1)
		alignment: #left
		isHeader: false.
	self assert: cell class equals: BrEditorElement!

testTextCellsSkipTheStylerEntirely
	"cells=text means the source is data, not markup."
	| relation element text |
	relation := McRelation
		columns: (Array with: (McRelationColumn name: 'a' alignment: #left))
		rows: (Array with: (McRelationRow
			cells: (Array with: (McRelationCell source: '**not bold**' interval: nil))
			columns: (Array with: (McRelationColumn name: 'a' alignment: #left))
			interval: nil))
		directives: McTableDirectives forQuery.
	element := McMarkdownTableElement relation: relation palette: self palette owner: nil.
	text := element cellTextFor: (relation at: 1 column: 1).
	self deny: (self in: text hasAttribute: BlFontWeightAttribute at: 5)! !

!McMarkdownTest methodsFor: 'tests - table element'!
testGridHasOneChildPerCellPlusHeaders
	| element |
	element := (self elementForTable: '| a | b |
|---|---|
| 1 | 2 |
| 3 | 4 |') build.
	self assert: element children size equals: 6!

testHeaderShowsAscendingArrowWhenAlreadySorted
	| element |
	element := self elementForTable: '| n |
|---|
| 1 |
| 2 |'.
	self assert: (element arrowFor: 1) equals: element ascendingArrow!

testHeaderShowsDescendingArrowWhenReversed
	| element |
	element := self elementForTable: '| n |
|---|
| 2 |
| 1 |'.
	self assert: (element arrowFor: 1) equals: element descendingArrow!

testHeaderShowsNoArrowWhenUnsorted
	| element |
	element := self elementForTable: '| n |
|---|
| 2 |
| 1 |
| 3 |'.
	self assert: (element arrowFor: 1) equals: ''!

testClickingASortedColumnAsksForTheOppositeDirection
	"Direction toggles without being remembered: it is read off the data."
	| element |
	element := self elementForTable: '| n |
|---|
| 1 |
| 2 |'.
	self deny: (element nextAscendingFor: 1)!

testClickingAnUnsortedColumnAsksForAscending
	| element |
	element := self elementForTable: '| n |
|---|
| 2 |
| 1 |
| 3 |'.
	self assert: (element nextAscendingFor: 1)! !

!McMarkdownTest methodsFor: 'tests - table regression'!
testCheckboxInACellDoesNotNestTheTable
	"The reported defect: the custom-token pass added a second beReplace
	 adornment inside the table's own, so the checkbox slot rendered a copy
	 of the table.  Exactly one adornment may cover the table's range."
	| source text parser range count |
	source := '| a | b |
|---|---|
| [ ] x | y |'.
	text := self styleAway: source.
	parser := self parse: source.
	range := parser rangeOf: (parser root children
		detect: [ :each | each class name asString = 'MicTableBlock' ]).
	count := 0.
	range first to: range last do: [ :index |
		count := count max: ((text attributesAt: index)
			select: [ :each | each isKindOf: BrTextAdornmentDynamicAttribute ]) size ].
	self assert: count equals: 1!

testHeaderOnlyTableStillRenders
	"A header and a separator with no data rows yet is the state every table
	 passes through while it is being typed.  Guarding visitTable: on
	 rowCount rendered nothing at all there -- raw pipes -- where the
	 pre-relational path drew the header.  The guard belongs on columnCount:
	 the header renders as soon as the separator lands."
	| source text parser range attribute element |
	source := '| a | b |
|---|---|'.
	text := self styleAway: source.
	parser := self parse: source.
	range := parser rangeOf: (parser root children
		detect: [ :each | each class name asString = 'MicTableBlock' ]).
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: range first).
	attribute := (text attributesAt: range first)
		detect: [ :each | each isKindOf: BrTextAdornmentDynamicAttribute ].
	element := attribute stencil build.
	self assert: element children size equals: 2!

testPipeLineWithNoSeparatorIsNotRenderedAsATable
	"Microdown makes a MicTableBlock out of any line holding pipes, so
	 rendering every zero-row one replaced an ordinary sentence with pipes
	 in it -- and the header line of a table a keystroke before its
	 separator exists -- with a bordered grid of empty cells, hiding the
	 text.  Without a separator row and without data rows, leave the source
	 alone."
	| text |
	text := self styleAway: '| a | b |'.
	self assert: (self adornmentCountIn: text) equals: 0!

testReaderReportsWhetherThereIsASeparatorRow
	"What tells a table from a sentence that happens to hold pipes."
	self assert: (self readerFor: '| a |
|---|
| 1 |') hasSeparatorRow.
	self deny: (self readerFor: '| a | b |') hasSeparatorRow!

testTableStillRendersWithTheCursorAway
	| source text parser range |
	source := '| a | b |
|---|---|
| 1 | 2 |'.
	text := self styleAway: source.
	parser := self parse: source.
	range := parser rangeOf: (parser root children
		detect: [ :each | each class name asString = 'MicTableBlock' ]).
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: range first)! !

Object subclass: #McRecordingOwner
	instanceVariableNames: 'replaceCalls buttonCalls'
	classVariableNames: ''
	package: 'MalleableControl'!

!McRecordingOwner methodsFor: 'initialization'!
initialize
	super initialize.
	replaceCalls := OrderedCollection new.
	buttonCalls := OrderedCollection new! !

!McRecordingOwner methodsFor: 'writing'!
replaceFrom: start to: stop with: aString
	"Recorded rather than applied: the test asserts on the range and text a
	 widget asked to write, not on any document it was applied to."
	replaceCalls add: {start. stop. aString}!

performButtonNamed: aLabel
	buttonCalls add: aLabel! !

!McRecordingOwner methodsFor: 'accessing'!
replaceCalls
	^ replaceCalls!

buttonCalls
	^ buttonCalls! !

!McMarkdownTest methodsFor: 'helpers - table write-back'!
recordingOwner
	^ McRecordingOwner new! !

!McMarkdownTest methodsFor: 'tests - table write-back'!
testCheckboxInACellWritesBackToTheDocumentIndex
	"Every other helper passes owner: nil, so nothing exercises write-back
	 from a widget rendered inside a table cell.  Writing to the wrong
	 offset is exactly the defect class this phase exists to fix."
	| source reader owner element cell text index attribute box call result |
	source := '| task |
|------|
| [ ] go |'.
	reader := self readerFor: source.
	owner := self recordingOwner.
	element := McMarkdownTableElement
		relation: reader relation
		palette: self palette
		owner: owner.
	cell := reader relation at: 1 column: 1.
	text := element cellTextFor: cell.
	index := (1 to: text size) detect: [ :each |
		self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: each ].
	attribute := (text attributesAt: index)
		detect: [ :each | each isKindOf: BrTextAdornmentDynamicAttribute ].
	box := attribute stencil build.
	box check.
	self assert: owner replaceCalls size equals: 1.
	call := owner replaceCalls first.
	result := source
		copyReplaceFrom: (call at: 1)
		to: (call at: 2)
		with: (call at: 3).
	self
		assert: result
		equals: '| task |
|------|
| [x] go |'! !

!McMarkdownTest methodsFor: 'tests - robustness'!
testStylingSurvivesEveryCursorPositionOfATableWithWidgets
	"A table whose cells hold every custom token, swept at every cursor
	 position.  This is where the two reported defects showed up, and where a
	 range-mapping mistake would raise."
	| source |
	source := '| task | colour | go |
|:-----|:------:|---:|
| [ ] **write** | #ff0000 | <<Run>> |
| [x] `ship`    | #00ff00 | <<Stop>> |'.
	-1 to: source size do: [ :cursor |
		self
			assert: (self style: source cursor: cursor) notNil
			description: 'raised at cursor ' , cursor printString ]! !

!McMarkdownTest methodsFor: 'tests - table element'!
testTableWithNoOwnerHasAnInertHeader
	"visitTable: used to install the sort action unconditionally, before it
	 knew whether owner was nil, so isSortable's owner gate never fired: a
	 table with no owner still invited a click it would silently ignore.
	 Goes through the real visitor path (style:cursor: always passes
	 owner: nil), not the elementForTable: helper, because the defect lived
	 in visitTable: itself, not in isSortable."
	| source text parser range attribute element |
	source := '| n |
|---|
| 2 |
| 1 |'.
	text := self styleAway: source.
	parser := self parse: source.
	range := parser rangeOf: (parser root children
		detect: [ :each | each class name asString = 'MicTableBlock' ]).
	attribute := (text attributesAt: range first)
		detect: [ :each | each isKindOf: BrTextAdornmentDynamicAttribute ].
	element := attribute stencil build.
	self deny: element isSortable!

testNextAscendingForARowCountUnderTwoAgreesWithNoArrow
	"nextAscendingFor: lacked arrowFor:'s guard: for fewer than two rows,
	 isSortedBy:ascending:true is vacuously true, so a header showing no
	 arrow would still ask for descending on the next click."
	| element |
	element := self elementForTable: '| n |
|---|
| 1 |'.
	self assert: (element arrowFor: 1) equals: ''.
	self assert: (element nextAscendingFor: 1)!

testArrowGlyphsAreDistinctCodePoints
	"testHeaderShowsAscendingArrowWhenAlreadySorted and
	 testHeaderShowsDescendingArrowWhenReversed each compare arrowFor:
	 against the accessor for that same direction, so either would still
	 pass if descendingArrow answered the ascending code point.  Pin the
	 two apart directly."
	| element |
	element := self elementForTable: '| n |
|---|
| 1 |
| 2 |'.
	self deny: element ascendingArrow = element descendingArrow.
	self assert: (element ascendingArrow includes: (Character value: 9650)).
	self assert: (element descendingArrow includes: (Character value: 9660))! !

!McMarkdownTest methodsFor: 'tests - table header'!
testHeaderElementCarriesTheColumnName
	"headerElementFor:index: is one of this phase's mandated interfaces and
	 had no test of its own: a header cell must show the column's name."
	| element header |
	element := self elementForTable: '| task |
|------|
| a |'.
	header := element headerElementFor: (element relation columns at: 1) index: 1.
	self assert: header text asString equals: 'task'!

testHeaderElementWithACustomTokenNameStaysInert
	"A column literally named like a custom token is built from an
	 interval-free McRelationCell, so even though it renders the checkbox
	 stencil, cellTextFor:isHeader: gives the styler no owner to write back
	 to -- checking it must be a silent no-op, not an edit landing on the
	 wrong characters of the document."
	| reader owner element column header text index attribute box |
	reader := self readerFor: '| a |
|------|
| 1 |'.
	owner := self recordingOwner.
	element := McMarkdownTableElement
		relation: reader relation
		palette: self palette
		owner: owner.
	column := McRelationColumn name: '[ ] x' alignment: #left.
	header := element headerElementFor: column index: 1.
	self assert: header class equals: BrEditorElement.
	text := header editor text.
	index := (1 to: text size)
		detect: [ :each | self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: each ].
	attribute := (text attributesAt: index)
		detect: [ :each | each isKindOf: BrTextAdornmentDynamicAttribute ].
	box := attribute stencil build.
	box check.
	self assert: owner replaceCalls isEmpty! !

!McMarkdownTest methodsFor: 'tests - cell rendering'!
testEmphasisActuallyCollapsesInACellThatAlsoHoldsAWidget
	"Every other cell-rendering test asserts on attributes, which all kept
	 passing while the live table rendered raw, uncollapsed markdown: for a
	 cell mixing a checkbox with emphasis, MicInlineParser reads the
	 unresolved '[' as the start of a link, and once '[ ] **fig**' cannot
	 complete one it swallows the rest of the line into one opaque text
	 node -- no MicBoldFormatBlock, so no BrTextHideAttribute or
	 BlFontWeightAttribute, ever reaches the rope.  A bare '**fig**' cell
	 with no checkbox already collapsed correctly before this fix, so it
	 would not have caught the defect; this measures the actual rendered
	 extent instead of an attribute, comparing the real styled cell against
	 the identical cell with only the hide/weight attributes stripped --
	 same checkbox widget, same base text, same element class -- so extent
	 is the one thing left free to vary."
	| relation element cell styled deEmphasized styledElement comparator space |
	relation := McRelation
		columns: (Array with: (McRelationColumn name: 'a' alignment: #left))
		rows: (Array with: (McRelationRow
			cells: (Array with: (McRelationCell source: '[ ] **fig**' interval: nil))
			columns: (Array with: (McRelationColumn name: 'a' alignment: #left))
			interval: nil))
		directives: McTableDirectives forMarkdownTable.
	element := McMarkdownTableElement relation: relation palette: self palette owner: nil.
	cell := relation at: 1 column: 1.
	styled := element cellTextFor: cell.
	deEmphasized := styled copy.
	deEmphasized clearAttributesOfClass: BrTextHideAttribute.
	deEmphasized clearAttributesOfClass: BlFontWeightAttribute.
	styledElement := element editorElementFor: styled copy.
	comparator := element editorElementFor: deEmphasized.
	styledElement padding: (BlInsets top: 3 right: 10 bottom: 3 left: 10).
	comparator padding: (BlInsets top: 3 right: 10 bottom: 3 left: 10).
	styledElement constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
	comparator constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
	space := BlSpace new.
	space extent: 400 @ 100.
	space root addChild: styledElement.
	space root addChild: comparator.
	"ensure:, because a shown BlSpace left behind by a failing assertion
	 outlives the test: the suite is re-run against the same image, and the
	 next run would inherit it."
	[ space show.
	  space pulse.
	  self assert: styledElement extent x < comparator extent x ]
		ensure: [ space close ]!

testEmphasisCollapsesInACellInsideABuiltGrid
	"Same defect, checked in the configuration that actually failed in the
	 live image: a cell reached through McMarkdownTableElement>>build --
	 the real header-plus-rows grid -- not a hand-assembled standalone
	 cell."
	| relation element cell gridCell styled deEmphasized comparator space |
	relation := McRelation
		columns: (Array with: (McRelationColumn name: 'a' alignment: #left))
		rows: (Array with: (McRelationRow
			cells: (Array with: (McRelationCell source: '[ ] **fig**' interval: nil))
			columns: (Array with: (McRelationColumn name: 'a' alignment: #left))
			interval: nil))
		directives: McTableDirectives forMarkdownTable.
	element := McMarkdownTableElement relation: relation palette: self palette owner: nil.
	element build.
	gridCell := element children at: 2.
	cell := relation at: 1 column: 1.
	styled := element cellTextFor: cell.
	deEmphasized := styled copy.
	deEmphasized clearAttributesOfClass: BrTextHideAttribute.
	deEmphasized clearAttributesOfClass: BlFontWeightAttribute.
	comparator := element editorElementFor: deEmphasized.
	comparator padding: (BlInsets top: 3 right: 10 bottom: 3 left: 10).
	comparator constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
	space := BlSpace new.
	space extent: 400 @ 100.
	space root addChild: element.
	space root addChild: comparator.
	"ensure:, for the same reason as the test above."
	[ space show.
	  space pulse.
	  self assert: gridCell extent x < comparator extent x ]
		ensure: [ space close ]! !

McMarkdownParser subclass: #McMarkdownReferenceParser
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownReferenceParser commentStamp: '' prior: 0!
The parser as it was before the incremental range tracking went in: it
rediscovers the whole tree after every line, and filters every line interval of
the document on every lookup.  Both are quadratic, which is the point -- this
class exists so that the fast parser can be held against a definition of
correct that is not itself, over documents nobody thought to write an
assertion for.

Only the two methods that changed are overridden, so everything downstream of
them -- stamping, inline sources, markup stripping -- stays shared, and a
parity failure can only mean the incremental discovery found a different set of
nodes, or the binary search a different set of lines.

Two deliberate differences are not defects and are documented at
McMarkdownParser>>childBlocksOf:.  A header parks its raw text in `children'
until it is closed, so this parser walks into a String and records a range
against each of its Characters; Characters are shared image-wide, so those
ranges say nothing about any header in particular.  The parity assertions
compare AST nodes, which is what the styler ever asks about, so those entries
are simply not compared.!

!McMarkdownReferenceParser methodsFor: 'parsing'!
parseSource: aString
	"The original line loop: collect every node before the line and again
	 after it, and stamp the difference."
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
	^ root! !

!McMarkdownReferenceParser methodsFor: 'parsing - private'!
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
		self collectBlocksFrom: each into: aSet ]! !

!McMarkdownReferenceParser methodsFor: 'source mapping'!
lineIntervalsWithin: aRange
	"The original filter over every line of the document."
	aRange ifNil: [ ^ #() ].
	^ lineIntervals select: [ :each |
		each first >= aRange first and: [ each first <= aRange last ] ]! !

!McMarkdownTest methodsFor: 'helpers - parity'!
parityDocuments
	"The documents the two parsers are held against each other on.  Malformed
	 and half-typed markup is over-represented on purpose: it is what a
	 document being edited looks like most of the time, and it is where a
	 shortcut in deciding which nodes a line created would show first."
	^ self wellFormedDocuments
		, self malformedDocuments
		, self lineTerminatorDocuments
		, (Array with: McRichEdit new demoContent)!

wellFormedDocuments
	^ {
'' .
'plain text with no markup in it at all' .
'# Title
body text

## Second level
more *body* text with `code` and **bold**' .
'- one
- two
  - nested a
  - nested b
    - deeper
- three

1. first
2. second
   1. inner' .
'> a quote
> running over
> three lines

not the quote' .
'```st
1 + 2
```

```sql&db=/tmp/nowhere.db
select 1
```

```
unterminated fence' .
'| a | b |
|---|---|
| 1 | 2 |
| 3 | 4 |

| header only |' .
'***
---
___

after the rules' .
'# h1

para one
para one line two

para two

- item

> quote

```
code
```

| t | u |
|---|---|
| 1 | 2 |

end' }!

malformedDocuments
	"The fragments the robustness tests already cover for styling, plus the
	 ones that specifically exercise a block being opened and closed by the
	 same line, or never closed at all."
	^ #( '**' '*' '_' '`' '#' '# ' '|' '| a' '| a |' '```' '```st' '- ' '1. '
	     '> ' '---' '**bold' 'bold**' '``` ' '#### ' '>' '>>' '- - -' '1.'
	     '10.' '     deeply indented' '#no space' '####### seven hashes' )
		, { '| a |
|--' .
'```st
never closed' .
'- a
    - b
        - c' .
'> q

> q again' .
'#

##

###' }!

lineTerminatorDocuments
	"The same document under each of the three terminators the parser copes
	 with.  Built rather than written out, because a chunk reader is free to
	 normalise the terminators inside a literal and then the CR cases would
	 quietly stop being tested."
	| lines |
	lines := #( '# Title' '' 'a paragraph' 'onto two lines' '' '- one' '- two'
		'' '> quoted' '' '| a | b |' '|---|---|' '| 1 | 2 |' '' 'tail' ).
	^ { String with: Character lf.
	    String with: Character cr.
	    String with: Character cr with: Character lf }
		collect: [ :terminator |
			String streamContents: [ :stream |
				lines do: [ :each | stream << each; << terminator ] ] ]!

blocksInOrderOf: aParser
	"Every node of a parsed tree, root first, each parent before its
	 children.  Two parses of the same source build the same shape, so this
	 order is what lets them be compared node against node."
	| result visit |
	result := OrderedCollection new.
	visit := nil.
	visit := [ :block |
		result add: block.
		(aParser childBlocksOf: block) do: [ :each | visit value: each ] ].
	visit value: aParser root.
	^ result!

parityDescriptionOf: aBlock in: aParser
	"What a node claims about itself: its class, the range it was stamped
	 with, and the text that range picks out.  Asserting on the three
	 together makes a parity failure name the node and show what it
	 selected, rather than reporting that two numbers differ."
	^ String streamContents: [ :stream |
		stream
			<< aBlock class name
			<< ' '
			<< (aParser rangeOf: aBlock) printString
			<< ' -> '
			<< (aParser sourceOf: aBlock) printString ]!

assertParityFor: aString
	"Parse aString both ways and assert the two agree about every node."
	| fast slow fastBlocks slowBlocks |
	fast := McMarkdownParser parseSource: aString.
	slow := McMarkdownReferenceParser parseSource: aString.
	fastBlocks := self blocksInOrderOf: fast.
	slowBlocks := self blocksInOrderOf: slow.
	self
		assert: (fastBlocks collect: [ :each | each class name ]) asArray
		equals: (slowBlocks collect: [ :each | each class name ]) asArray.
	fastBlocks doWithIndex: [ :block :index |
		| other |
		other := slowBlocks at: index.
		self
			assert: (self parityDescriptionOf: block in: fast)
			equals: (self parityDescriptionOf: other in: slow).
		self
			assert: (fast lineIntervalsWithin: (fast rangeOf: block)) asArray
			equals: (slow lineIntervalsWithin: (slow rangeOf: other)) asArray.
		self
			assert: (fast inlineSourceOf: block)
			equals: (slow inlineSourceOf: other).
		self
			assert: (fast inlineMapOf: block)
			equals: (slow inlineMapOf: other) ]! !

!McMarkdownTest methodsFor: 'tests - parser parity'!
testEveryNodeGetsTheRangeTheWholeTreeDiffGaveIt
	"The incremental discovery is only worth having if it stamps exactly what
	 rediscovering the whole tree after every line stamped.  Rather than
	 restate the expected offsets -- which would only pin down the documents
	 someone thought to write out -- each corpus document is parsed both ways
	 and the two trees are compared node by node, ranges, selected source,
	 line intervals and inline maps alike."
	self parityDocuments do: [ :each | self assertParityFor: each ]!

testParityHoldsForEveryPrefixOfADocument
	"A document is not only parsed whole: the editor reparses after every
	 keystroke, so every prefix of a document is a document the parser sees,
	 and a prefix is exactly where a block is left open and half-built."
	| source |
	source := '# Title

para one
para two

- a
- b

> q

| x | y |
|---|---|
| 1 | 2 |
'.
	1 to: source size do: [ :size |
		self assertParityFor: (source copyFrom: 1 to: size) ]!

testLineIntervalsWithinAgreesWithTheFilterForEveryInterval
	"The styler asks about intervals it has widened and narrowed itself, not
	 only about the ones the parser stamped, so the binary search is checked
	 against the filter it replaced over every interval of a small document
	 -- empty, inverted and out-of-bounds ones included."
	| source fast slow |
	source := '# t

aa
bbb

cc'.
	fast := McMarkdownParser parseSource: source.
	slow := McMarkdownReferenceParser parseSource: source.
	0 to: source size + 2 do: [ :first |
		first - 2 to: source size + 2 do: [ :last |
			self
				assert: (fast lineIntervalsWithin: (first to: last)) asArray
				equals: (slow lineIntervalsWithin: (first to: last)) asArray ] ].
	self assert: (fast lineIntervalsWithin: nil) asArray equals: #()! !

!McMarkdownTest methodsFor: 'helpers - scaling'!
scalingDocumentOf: aNumber
	"aNumber copies of a section holding one of every block kind, so that the
	 document grows in lines and in nodes at a fixed rate and nothing else
	 about it changes."
	^ String streamContents: [ :stream |
		1 to: aNumber do: [ :index |
			stream
				<< '# Header '; << index printString; cr; cr;
				<< 'A paragraph with *emphasis* and `code` in it,'; cr;
				<< 'running onto a second line.'; cr; cr;
				<< '- item one'; cr;
				<< '- item two'; cr; cr;
				<< '> a quoted line'; cr; cr;
				<< '| a | b |'; cr;
				<< '|---|---|'; cr;
				<< '| 1 | 2 |'; cr; cr ] ]!

probesToParse: aNumber
	^ (McMarkdownParser parseSource: (self scalingDocumentOf: aNumber)) probeCount!

probesToStyle: aNumber
	"Parse and style, and answer what both cost together.  Styling is where
	 the line-interval lookups happen -- one per block, and one more per line
	 of every quote and table -- so a lookup that walked the whole document
	 would show up here rather than in the parse."
	| source parser |
	source := self scalingDocumentOf: aNumber.
	parser := McMarkdownParser parseSource: source.
	(McMarkdownStylerVisitor
		parser: parser
		text: source asRopedText
		cursor: -1
		palette: self palette
		owner: nil) visit: parser root.
	^ parser probeCount! !

!McMarkdownTest methodsFor: 'tests - parser scaling'!
testParsingWorkGrowsWithTheDocumentAndNotWithItsSquare
	"The counter rather than the clock.  #probeCount is how many candidate
	 slots the parser had to look at, so a linear parser roughly doubles it
	 when the document doubles and the whole-tree diff this replaced roughly
	 quadrupled it.  Asserting well inside the gap -- under 2.5x for a 2x
	 document -- catches a return to quadratic without ever depending on how
	 fast the machine is."
	| small medium large |
	small := self probesToParse: 20.
	medium := self probesToParse: 40.
	large := self probesToParse: 80.
	self assert: small > 0.
	self assert: medium * 2 < (small * 5).
	self assert: large * 2 < (medium * 5)!

testParsingWorkIsBoundedByTheNumberOfLines
	"The ratio test says the growth is linear; this says what the line costs.
	 A handful of probes per line is what looking at the children of the
	 nodes open across it comes to, and it holds whatever the document is."
	| parser |
	parser := McMarkdownParser parseSource: (self scalingDocumentOf: 40).
	self assert: parser lineIntervals size > 500.
	self assert: parser probeCount < (parser lineIntervals size * 4)!

testStylingWorkGrowsWithTheDocumentAndNotWithItsSquare
	"Same claim for the styler, which is the caller that asks for line
	 intervals over and over: once per block, and again per line for every
	 quote and table."
	| small medium large |
	small := self probesToStyle: 20.
	medium := self probesToStyle: 40.
	large := self probesToStyle: 80.
	self assert: small > 0.
	self assert: medium * 2 < (small * 5).
	self assert: large * 2 < (medium * 5)!

testALineIntervalLookupDoesNotWalkTheDocument
	"A three-line block in a thousand-line document costs a binary search and
	 a short walk off its end, not a filter over the thousand lines.  The
	 bound is generous -- a binary search over 1400 lines is eleven probes --
	 and still an order of magnitude below what filtering would spend."
	| parser table before after |
	parser := McMarkdownParser parseSource: (self scalingDocumentOf: 100).
	self assert: parser lineIntervals size > 1000.
	table := parser root children last.
	before := parser probeCount.
	parser lineIntervalsWithin: (parser rangeOf: table).
	after := parser probeCount.
	self assert: after - before < 25!

testProbeCountStartsFreshWithEachParse
	"The counter belongs to one parse, not to the class: two parsers over the
	 same source must report the same work, or the scaling assertions would
	 drift with the order the tests happen to run in."
	| source |
	source := self scalingDocumentOf: 5.
	self
		assert: (McMarkdownParser parseSource: source) probeCount
		equals: (McMarkdownParser parseSource: source) probeCount! !
