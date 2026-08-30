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
tableModelOf: aSource
	| parser table visitor |
	parser := McMarkdownParser parseSource: aSource.
	table := parser root children first.
	visitor := McMarkdownStylerVisitor
		parser: parser
		text: aSource asRopedText
		cursor: -1
		palette: self palette
		owner: nil.
	^ visitor tableModelFor: table!

testTableModelDropsTheSeparatorRow
	"Whichever way the separator is spelled, it must not show up as data."
	#('|---|---|' '|:---|---:|' '| --- | --- |') do: [ :separator |
		| model |
		model := self tableModelOf: '| a | b |
' , separator , '
| 1 | 2 |'.
		self
			assert: ((model at: 'rows') collect: [ :row | row asArray ]) asArray
				= (Array with: #('a' 'b') with: #('1' '2'))
			description: separator , ' left a stray row: '
				, (model at: 'rows') printString ]!

testTableModelMarksOneHeaderRow
	#('|---|---|' '|:---|---:|') do: [ :separator |
		| model |
		model := self tableModelOf: '| a | b |
' , separator , '
| 1 | 2 |'.
		self
			assert: (model at: 'headerRows') = 1
			description: separator , ' lost the header' ]!

testTableModelReadsAlignmentColons
	| model |
	model := self tableModelOf: '| a | b | c | d |
|:---|---:|:--:|---|
| 1 | 2 | 3 | 4 |'.
	self
		assert: (model at: 'alignments') asArray
		equals: #(#left #right #center #left)!

testTableModelWithoutASeparatorHasNoHeader
	| model |
	model := self tableModelOf: '| a | b |'.
	self assert: (model at: 'headerRows') equals: 0!

testTableWidgetHasACellPerColumnAndRow
	| parser table visitor element |
	parser := McMarkdownParser parseSource: '| a | b |
|---|---|
| 1 | 2 |
| 3 | 4 |'.
	table := parser root children first.
	visitor := McMarkdownStylerVisitor
		parser: parser
		text: '' asRopedText
		cursor: -1
		palette: self palette
		owner: nil.
	element := visitor tableElementFor: table.
	"Three rows survive the separator, two columns each."
	self assert: element children size equals: 6!

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
	self assert: (self in: text hasAttribute: BrTextAdornmentDynamicAttribute at: 1)! !
