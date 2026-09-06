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
