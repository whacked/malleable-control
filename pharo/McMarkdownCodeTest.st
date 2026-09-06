"
McMarkdownCodeTest -- the scanner, as a pure function over strings.

No image, no subprocess, no rope.  The scanner owns syntax and nothing else,
so its whole contract can be asserted by handing it a string and looking at
what comes back.  That is the point of keeping it separate from the evaluator.

Chunk format: load with fileIn.
"!

TestCase subclass: #McMarkdownCodeTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownCodeTest methodsFor: 'helpers'!
scan: aString
	^ (McMarkdownCodeScanner scan: aString) asArray!

only: aString
	| spans |
	spans := self scan: aString.
	self assert: spans size equals: 1.
	^ spans first! !

!McMarkdownCodeTest methodsFor: 'tests - recognition'!
testLabeledSpanIsFound
	| code |
	code := self only: '`{python} 1`'.
	self assert: code language equals: 'python'.
	self assert: code expression equals: '1'.
	self assert: code isInline!

testSpanCoversItsDelimiters
	"The styler replaces start..stop, so the backticks and the label have to
	 be inside the span or they would be left showing beside the result."
	| code |
	code := self only: '`{python} 1`'.
	self assert: code start equals: 1.
	self assert: code stop equals: 12.
	self assert: code bodyStart equals: 10.
	self assert: code bodyStop equals: 11.
	self assert: code fence equals: 1!

testSpanIsFoundAfterLeadingProse
	| code |
	code := self only: 'The calculated radius is `{python} 5 * 2` meters.'.
	self assert: code language equals: 'python'.
	self assert: code expression equals: '5 * 2'.
	self assert: ('The calculated radius is ' size + 1) equals: code start!

testLanguageIsLowercased
	"A highlighter and the evaluator registry both key on the language, so
	 Python and python have to be the same language."
	self assert: (self only: '`{PYTHON} 1`') language equals: 'python'!

testExpressionIsTrimmedAtItsEnds
	self assert: (self only: '`{r}    mean(x)   `') expression equals: 'mean(x)'!

testAllFourQuartoNotationsParse
	#( #('`{python} 5 * 2`' 'python' '5 * 2')
	   #('`{r} mean(c(10, 20, 30))`' 'r' 'mean(c(10, 20, 30))')
	   #('`{julia} det([1 2; 3 4])`' 'julia' 'det([1 2; 3 4])')
	   #('`{ojs} Math.PI * 2`' 'ojs' 'Math.PI * 2') )
		do: [ :each |
			| code |
			code := self only: (each at: 1).
			self assert: code language equals: (each at: 2).
			self assert: code expression equals: (each at: 3) ]!

testTwoSpansOnOneLineAreBothFound
	| spans |
	spans := self scan: 'two `{r} 1` and `{julia} 2`'.
	self assert: spans size equals: 2.
	self assert: (spans first) language equals: 'r'.
	self assert: (spans second) language equals: 'julia'.
	self assert: (spans first) stop < (spans second) start! !

!McMarkdownCodeTest methodsFor: 'tests - fence width'!
testDoubleFenceQuotesInnerBackticks
	"The reason this scanner exists rather than a Microdown node: the fence
	 width is data, so a span can contain backticks of its own."
	| code |
	code := self only: '``{python} len("`backticks`")``'.
	self assert: code fence equals: 2.
	self assert: code expression equals: 'len("`backticks`")'.
	self assert: code start equals: 1.
	self assert: code stop equals: 31!

testSingleFenceClosesOnTheFirstBacktick
	self assert: (self only: '`{python} 1` and `x`') expression equals: '1'!

testLongerRunDoesNotCloseAShorterOne
	"A run of three does not close a run of two, so the span runs on to the
	 real closer."
	| code |
	code := self only: '``{python} a ``` b``'.
	self assert: code expression equals: 'a ``` b'!

testUnterminatedDoubleFenceIsLeftAlone
	self assert: (self scan: '``{python} 1`') equals: #()! !

!McMarkdownCodeTest methodsFor: 'tests - tolerance'!
testPlainInlineCodeIsNotALabeledSpan
	"Ordinary code spans must go on rendering exactly as they did."
	self assert: (self scan: 'plain `code` here') equals: #()!

testUnterminatedSpanIsLeftAlone
	"Every keystroke is parsed, so a span still being typed must not swallow
	 the rest of the line."
	self assert: (self scan: 'unterminated `{python} 1 + 1') equals: #()!

testLabelMustFollowTheFenceImmediately
	self assert: (self scan: 'spaced ` {python} 1`') equals: #()!

testLabelWithASeparatorIsNotALabel
	self assert: (self scan: 'bad `{not a label} x`') equals: #()!

testEmptyLabelIsNotALabel
	self assert: (self scan: 'empty `{} x`') equals: #()!

testUnclosedLabelBraceIsLeftAlone
	self assert: (self scan: 'brace `{python 1`') equals: #()!

testEmptyExpressionIsNotALabeledSpan
	"A span with a label and nothing after it is one still being typed."
	self assert: (self scan: '`{python}`') equals: #().
	self assert: (self scan: '`{python}   `') equals: #()!

testEmptySourceScansToNothing
	self assert: (self scan: '') equals: #().
	self assert: (McMarkdownCodeScanner scan: nil) asArray equals: #()!

testBareBackticksScanToNothing
	self assert: (self scan: '``````') equals: #()! !

!McMarkdownCodeTest methodsFor: 'tests - cache keys'!
testCacheKeyCombinesLanguageAndExpression
	| a b |
	a := self only: '`{python} 1`'.
	b := self only: '`{r} 1`'.
	self deny: a cacheKey = b cacheKey!

testCacheKeyIgnoresSurroundingWhitespace
	"Trailing spaces are not a different expression, so they must not cost a
	 second evaluation."
	self
		assert: (self only: '`{python} 1 + 1`') cacheKey
		equals: (self only: '`{python}    1 + 1  `') cacheKey!

testCacheKeyPreservesInteriorWhitespace
	"Indentation is syntax in Python, so the interior is never collapsed --
	 these are two different programs and must not share a cache entry."
	| a b |
	a := McMarkdownCode
		blockLanguage: 'python' expression: 'if x:
    y' start: 1 stop: 2.
	b := McMarkdownCode
		blockLanguage: 'python' expression: 'if x:
        y' start: 1 stop: 2.
	self deny: a cacheKey = b cacheKey! !

!McMarkdownCodeTest methodsFor: 'tests - info strings'!
testBareLanguageInfoNamesALanguage
	self assert: (McMarkdownCode languageFromInfo: 'python') equals: 'python'.
	self assert: (McMarkdownCode languageFromInfo: '  Python  ') equals: 'python'!

testDatabaseViewInfoIsNotALanguage
	"sql&db= has its own renderer and predates this; it must fall through
	 untouched."
	self assert: (McMarkdownCode languageFromInfo: 'sql&db=notes.sqlite') isNil!

testResultsInfoIsNotALanguage
	self
		assert: (McMarkdownCode languageFromInfo: 'results{2026-09-06T14:22:01.123Z}')
		isNil!

testEmptyInfoNamesNoLanguage
	self assert: (McMarkdownCode languageFromInfo: '') isNil.
	self assert: (McMarkdownCode languageFromInfo: nil) isNil!

testResultsInfoIsRecognised
	self assert: (McMarkdownCode isResultsInfo: 'results{2026-09-06T14:22:01.123Z}').
	self deny: (McMarkdownCode isResultsInfo: 'python').
	self deny: (McMarkdownCode isResultsInfo: 'results')!

testResultsTimestampRoundTrips
	| stamp info |
	stamp := DateAndTime
		year: 2026 month: 9 day: 6
		hour: 14 minute: 22 second: 1
		nanoSecond: 123000000
		offset: (Duration seconds: 0).
	info := McMarkdownCode resultsInfoAt: stamp.
	self assert: info equals: 'results{2026-09-06T14:22:01.123Z}'.
	self
		assert: (McMarkdownCode resultsTimestampFrom: info)
		equals: '2026-09-06T14:22:01.123Z'!

testResultsTimestampOfANonResultsInfoIsNil
	"This runs over half-typed documents, so it answers nil rather than
	 raising."
	self assert: (McMarkdownCode resultsTimestampFrom: 'python') isNil! !

!McMarkdownCodeTest methodsFor: 'running'!
setUp
	super setUp.
	McCodeEvaluator reset!

tearDown
	"The evaluator's state is global to the image, so it goes back whether
	 the test passed or not."
	McCodeEvaluator reset.
	super tearDown! !

!McMarkdownCodeTest methodsFor: 'helpers - rendering'!
style: aString cursor: anInteger trusted: aBoolean
	"Style aString as a standalone fragment, the way a table cell is styled.
	 owner: nil means the evaluation resolves on this process, so one pass
	 produces the finished result and the test needs no callback."
	| text styler |
	text := aString asRopedText.
	styler := McMarkdownInlineStyler
		source: aString
		targetMap: (McMarkdownInlineStyler identityMapOfSize: aString size)
		documentMap: (McMarkdownInlineStyler identityMapOfSize: aString size)
		text: text
		cursor: anInteger
		palette: McRichEdit new palette
		owner: nil.
	styler trusted: aBoolean.
	styler styleAll.
	^ text!

styleTrusted: aString
	^ self style: aString cursor: -1 trusted: true!

styleUntrusted: aString
	^ self style: aString cursor: -1 trusted: false!

adornmentsIn: aText
	| found |
	found := OrderedCollection new.
	1 to: aText size do: [ :index |
		(aText attributesAt: index) do: [ :each |
			((each isKindOf: BrTextAdornmentDynamicAttribute)
				and: [ (found includes: each) not ])
				ifTrue: [ found add: each ] ] ].
	^ found!

renderedTextOf: anElement
	"Every string an element and its children show, joined -- the tag and
	 the body, in that order."
	| out |
	out := WriteStream on: String new.
	self collectTextOf: anElement into: out.
	^ out contents!

collectTextOf: anElement into: aStream
	(anElement isKindOf: BlTextElement)
		ifTrue: [ aStream nextPutAll: anElement text asString; nextPut: $  ].
	anElement children do: [ :each | self collectTextOf: each into: aStream ]!

in: aText hasAttributeKind: aClass
	1 to: aText size do: [ :index |
		((aText attributesAt: index) anySatisfy: [ :each | each isKindOf: aClass ])
			ifTrue: [ ^ true ] ].
	^ false!

renderedSpanOf: aString trusted: aBoolean
	| text adornments |
	text := self style: aString cursor: -1 trusted: aBoolean.
	adornments := self adornmentsIn: text.
	self assert: adornments size equals: 1.
	^ self renderedTextOf: adornments first stencil build! !

!McMarkdownCodeTest methodsFor: 'tests - inline rendering'!
testTrustedSpanRendersTheTagAndTheResult
	| rendered |
	McCodeEvaluator executor: [ :language :expression | '10' ].
	rendered := self renderedSpanOf: 'radius `{python} 5 * 2` m' trusted: true.
	self assert: (rendered includesSubstring: 'python').
	self assert: (rendered includesSubstring: '10')!

testUntrustedSpanRunsNothingAndShowsItsSource
	"Opening a document must never be the same thing as running it."
	| rendered |
	McCodeEvaluator executor: [ :language :expression | '10' ].
	rendered := self renderedSpanOf: 'radius `{python} 5 * 2` m' trusted: false.
	self
		assert: McCodeEvaluator executionCount = 0
		description: 'an untrusted document must not evaluate anything'.
	self assert: (rendered includesSubstring: 'python').
	self assert: (rendered includesSubstring: '5 * 2').
	self deny: (rendered includesSubstring: '10')!

testUntrustedSpanIsStillTagged
	"Tagged source, not a blank and not plain code: the reader should be able
	 to see there is something here to run."
	| rendered |
	rendered := self renderedSpanOf: '`{r} mean(x)`' trusted: false.
	self assert: (rendered includesSubstring: 'r')!

testFailedEvaluationRendersItsMessage
	| rendered |
	rendered := self renderedSpanOf: '`{cobol} 1`' trusted: true.
	self assert: (rendered includesSubstring: 'cobol')!

testCursorOnTheSpanRevealsTheSource
	"The same rule links and images follow: the cursor on a token shows the
	 token, so it can be edited."
	| text |
	McCodeEvaluator executor: [ :language :expression | '10' ].
	text := self style: '`{python} 5 * 2`' cursor: 4 trusted: true.
	self
		assert: (self adornmentsIn: text) isEmpty
		description: 'no widget should cover a span the cursor is on'!

testPlainInlineCodeProducesNoWidget
	self assert: (self adornmentsIn: (self styleTrusted: 'a `code` b')) isEmpty! !

!McMarkdownCodeTest methodsFor: 'tests - inline precedence'!
testALinkInsideAnExpressionStaysLiteral
	"First claim wins, and styleAll runs code before links.  Without that,
	 the link pass would put a second adornment inside the expression's."
	| text |
	McCodeEvaluator executor: [ :language :expression | 'ok' ].
	text := self styleTrusted: '`{python} f("[a](b)")`'.
	self assert: (self adornmentsIn: text) size equals: 1!

testACheckboxInsideAnExpressionStaysLiteral
	| text |
	McCodeEvaluator executor: [ :language :expression | 'ok' ].
	text := self styleTrusted: '`{python} g("[ ]")`'.
	self assert: (self adornmentsIn: text) size equals: 1!

testALinkOutsideAnExpressionStillRenders
	"The precedence must not cost links their own rendering."
	| text |
	McCodeEvaluator executor: [ :language :expression | 'ok' ].
	text := self styleTrusted: '`{python} 1` and [a](b)'.
	self assert: (self adornmentsIn: text) size equals: 1.
	self
		assert: (self in: text hasAttributeKind: BrTextTooltipAttribute)
		description: 'the link beside the expression should still be projected'!

testEmphasisDoesNotReachInsideAnExpression
	"Underscores in an expression are Python, not italics.  The span is
	 masked before Microdown's inline parser sees the line."
	| text |
	McCodeEvaluator executor: [ :language :expression | 'ok' ].
	text := self styleTrusted: '`{python} _a_ + _b_`'.
	self assert: (self adornmentsIn: text) size equals: 1! !

!McMarkdownCodeTest methodsFor: 'helpers - blocks'!
blockSource
	"A document with one python block between two paragraphs, so the
	 write-back has something on both sides of it to get wrong."
	^ 'Intro para.

```python
6 * 2
```

Tail para.'!

blockStop
	"The last character of the block in blockSource -- the closing fence."
	^ self blockSource indexOfSubCollection: '```
' startingAt: 14!

styleDocument: aString trusted: aBoolean owner: anOwner
	| text parser visitor |
	text := aString asRopedText.
	parser := McMarkdownParser parseSource: aString.
	visitor := McMarkdownStylerVisitor
		parser: parser
		text: text
		cursor: -1
		palette: McRichEdit new palette
		owner: anOwner.
	visitor trusted: aBoolean.
	visitor visit: parser root.
	^ text!

buttonIn: anElement
	(anElement isKindOf: BrButton) ifTrue: [ ^ anElement ].
	anElement children do: [ :each |
		(self buttonIn: each) ifNotNil: [ :found | ^ found ] ].
	^ nil!

runButtonIn: aText
	(self adornmentsIn: aText) do: [ :each |
		(self buttonIn: each stencil build) ifNotNil: [ :found | ^ found ] ].
	^ nil!

evaluateInline: aBlock
	"Keep the background job in hand and run it at once, so a test asserts
	 what a run produced rather than racing it."
	McCodeEvaluator executor: aBlock.
	McCodeEvaluator jobRunner: [ :job | job value ]!

documentAfterRunning: aSource
	"Press the block's Run button and answer the document it wrote."
	| owner text button |
	owner := McRecordingOwner new.
	text := self styleDocument: aSource trusted: true owner: owner.
	button := self runButtonIn: text.
	self assert: button notNil description: 'a trusted block should carry a Run button'.
	button action value.
	owner replaceCalls isEmpty ifTrue: [ ^ aSource ].
	self assert: owner replaceCalls size equals: 1.
	^ self apply: owner replaceCalls first to: aSource!

apply: aCall to: aSource
	^ aSource copyReplaceFrom: (aCall at: 1) to: (aCall at: 2) with: (aCall at: 3)!

count: aSubstring in: aString
	| count index found |
	count := 0.
	index := 1.
	[ index <= aString size ] whileTrue: [
		found := aString indexOfSubCollection: aSubstring startingAt: index.
		found = 0 ifTrue: [ ^ count ].
		count := count + 1.
		index := found + aSubstring size ].
	^ count! !

!McMarkdownCodeTest methodsFor: 'tests - results fence location'!
testABlockWithNoResultsFenceHasNoRange
	self
		assert: (McMarkdownCode resultsRangeIn: self blockSource after: self blockStop + 2)
		isNil!

testResultsFenceOnTheNextLineIsFound
	| source |
	source := '```python
1
```
```results{2026-09-06T14:22:01.123Z}
2
```'.
	self assert: (McMarkdownCode resultsRangeIn: source after: 15) notNil!

testResultsFenceAfterOneBlankLineIsFound
	| source |
	source := '```python
1
```

```results{2026-09-06T14:22:01.123Z}
2
```'.
	self assert: (McMarkdownCode resultsRangeIn: source after: 15) notNil!

testResultsFenceAfterTwoBlankLinesIsNotOurs
	"Two blank lines put it far enough away that it belongs to something
	 else, and rewriting it would destroy a result that is not this block's."
	| source |
	source := '```python
1
```


```results{2026-09-06T14:22:01.123Z}
2
```'.
	self assert: (McMarkdownCode resultsRangeIn: source after: 15) isNil!

testProseBetweenMeansNoResultsFence
	| source |
	source := '```python
1
```

Some prose.

```results{2026-09-06T14:22:01.123Z}
2
```'.
	self assert: (McMarkdownCode resultsRangeIn: source after: 15) isNil!

testAnOrdinaryFenceAfterTheBlockIsNotAResultsFence
	| source |
	source := '```python
1
```

```python
2
```'.
	self assert: (McMarkdownCode resultsRangeIn: source after: 15) isNil!

testUnterminatedResultsFenceAnswersNil
	"Better to leave a broken document alone than to rewrite the wrong range
	 of it."
	| source |
	source := '```python
1
```

```results{2026-09-06T14:22:01.123Z}
2'.
	self assert: (McMarkdownCode resultsRangeIn: source after: 15) isNil!

testResultsRangeStartsAtTheBlockEndSoClearingRemovesTheBlankLine
	| source range cleared |
	source := '```python
1
```

```results{2026-09-06T14:22:01.123Z}
2
```'.
	range := McMarkdownCode resultsRangeIn: source after: 15.
	self assert: range first equals: 16.
	self assert: range last equals: source size.
	cleared := source copyReplaceFrom: range first to: range last with: ''.
	self assert: cleared equals: '```python
1
```'! !

!McMarkdownCodeTest methodsFor: 'tests - results fence text'!
testResultsFenceCarriesTheTimestampAndTheOutput
	| stamp fence |
	stamp := DateAndTime
		year: 2026 month: 9 day: 6
		hour: 14 minute: 22 second: 1
		nanoSecond: 123000000
		offset: (Duration seconds: 0).
	fence := McMarkdownCode resultsFenceFor: '12.0' at: stamp.
	self assert: (fence includesSubstring: 'results{2026-09-06T14:22:01.123Z}').
	self assert: (fence includesSubstring: '12.0')!

testOutputContainingBackticksGetsALongerFence
	"An interpreter that prints markdown must not be able to close the fence
	 that is quoting it."
	| fence |
	fence := McMarkdownCode resultsFenceFor: 'a ``` b' at: DateAndTime now.
	self assert: (fence includesSubstring: '````results{').
	self assert: (fence includesSubstring: 'a ``` b')!

testFenceWidthIsThreeForOrdinaryOutput
	self assert: (McMarkdownCode fenceWidthFor: '12.0') equals: 3!

testAWrittenResultsFenceParsesBackAsAResultsBlock
	"The round trip that matters: what a run writes has to be recognised as
	 output the next time the document is parsed, or the result renders as
	 an ordinary code block forever."
	| document parser info |
	document := self blockSource ,
		(McMarkdownCode resultsFenceFor: '12.0' at: DateAndTime now).
	parser := McMarkdownParser parseSource: document.
	info := nil.
	parser root children do: [ :each |
		(each class name asString = 'MicCodeBlock') ifTrue: [
			(McMarkdownCode isResultsInfo: (each firstLine ifNil: [ '' ]))
				ifTrue: [ info := each firstLine ] ] ].
	self assert: info notNil description: 'the written fence should parse as a results block'! !

!McMarkdownCodeTest methodsFor: 'tests - block running'!
testUntrustedDocumentHasNoRunButton
	"No button at all, rather than a disabled one: an untrusted document
	 should not advertise a control it will not honour."
	| text |
	self evaluateInline: [ :language :expression | '12.0' ].
	text := self styleDocument: self blockSource trusted: false owner: McRecordingOwner new.
	self assert: (self runButtonIn: text) isNil!

testTrustedDocumentHasARunButton
	| text |
	self evaluateInline: [ :language :expression | '12.0' ].
	text := self styleDocument: self blockSource trusted: true owner: McRecordingOwner new.
	self assert: (self runButtonIn: text) notNil!

testABlockNeverEvaluatesUntilItsButtonIsPressed
	"Unlike an inline expression, a fenced block is never run by rendering.
	 That is Org Babel's rule and it is what makes a block safe to look at."
	self evaluateInline: [ :language :expression | '12.0' ].
	self styleDocument: self blockSource trusted: true owner: McRecordingOwner new.
	self assert: McCodeEvaluator executionCount equals: 0!

testRunWritesAResultsFenceAfterTheBlock
	| document |
	self evaluateInline: [ :language :expression | '12.0' ].
	document := self documentAfterRunning: self blockSource.
	self assert: (document includesSubstring: '```results{').
	self assert: (document includesSubstring: '12.0').
	self
		assert: (document indexOfSubCollection: '```results{')
			> (document indexOfSubCollection: '6 * 2')
		description: 'the result belongs after the block that produced it'.
	self
		assert: (document indexOfSubCollection: '```results{')
			< (document indexOfSubCollection: 'Tail para.')
		description: 'and before whatever followed it'!

testTheBlockItselfIsUntouched
	| document |
	self evaluateInline: [ :language :expression | '12.0' ].
	document := self documentAfterRunning: self blockSource.
	self assert: (document includesSubstring: '```python
6 * 2
```').
	self assert: (document includesSubstring: 'Intro para.').
	self assert: (document includesSubstring: 'Tail para.')!

testRunningAgainReplacesTheFenceRatherThanAppendingASecond
	"Otherwise a block accumulates one results fence per run."
	| once twice |
	self evaluateInline: [ :language :expression | '12.0' ].
	once := self documentAfterRunning: self blockSource.
	McCodeEvaluator clearCache.
	self evaluateInline: [ :language :expression | '99.9' ].
	twice := self documentAfterRunning: once.
	self assert: (self count: '```results{' in: twice) equals: 1.
	self assert: (twice includesSubstring: '99.9').
	self deny: (twice includesSubstring: '12.0')!

testFailedRunWritesNothing
	| document |
	self evaluateInline: [ :language :expression | self error: 'boom' ].
	document := self documentAfterRunning: self blockSource.
	self assert: document equals: self blockSource!

testFailedRunRemovesAStaleResultsFence
	"A stale success must not outlive the code that produced it."
	| once after |
	self evaluateInline: [ :language :expression | '12.0' ].
	once := self documentAfterRunning: self blockSource.
	self assert: (once includesSubstring: '```results{').
	McCodeEvaluator clearCache.
	self evaluateInline: [ :language :expression | self error: 'boom' ].
	after := self documentAfterRunning: once.
	self deny: (after includesSubstring: '```results{').
	self assert: after equals: self blockSource!

testFailureIsShownBesideTheButton
	| text button |
	self evaluateInline: [ :language :expression | self error: 'boom' ].
	self documentAfterRunning: self blockSource.
	"The failure is cached, so the next render shows it without re-running."
	text := self styleDocument: self blockSource trusted: true owner: McRecordingOwner new.
	button := self runButtonIn: text.
	self assert: button notNil description: 'the button survives a failed run'.
	self
		assert: ((self adornmentsIn: text) anySatisfy: [ :each |
			(self renderedTextOf: each stencil build) includesSubstring: 'boom' ])
		description: 'the error should be visible beside the button'! !

!McMarkdownCodeTest methodsFor: 'tests - re-run binding'!
testTheRerunCommandIsRegisteredAndBound
	"The tooltip on every rendered expression names this binding, so it has
	 to exist -- a tooltip that names a keystroke nothing implements is worse
	 than no tooltip."
	| keymap |
	keymap := McCommandKeymap richEditDefaults.
	self assert: (keymap commandNames includes: #rerunAtCursor).
	self assert: (keymap bindingFor: #rerunAtCursor in: #editor) notNil!

testRerunFindsTheInlineExpressionUnderTheCursor
	| editor source code |
	source := 'radius `{python} 5 * 2` m'.
	editor := McRichEdit new.
	code := editor codeAt: ('radius `{python}' size) in: source.
	self assert: code notNil.
	self assert: code language equals: 'python'.
	self assert: code isInline!

testRerunFindsTheBlockUnderTheCursor
	| editor code |
	editor := McRichEdit new.
	code := editor codeAt: (self blockSource indexOfSubCollection: '6 * 2') in: self blockSource.
	self assert: code notNil.
	self assert: code language equals: 'python'.
	self assert: code isBlock!

testRerunFindsNothingInOrdinaryProse
	self
		assert: (McRichEdit new codeAt: 3 in: 'just some prose') isNil! !
