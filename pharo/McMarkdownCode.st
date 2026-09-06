"
McMarkdownCode and McMarkdownCodeScanner -- language-labeled code.

Markdown's inline code span carries no language, so a renderer can do nothing
with it but pick a monospace font.  Quarto extends the syntax with a leading
label -- `{python} 5 * 2` -- and that label is what makes the span more than
decoration: it names a highlighter, and it names an evaluator.

This file owns syntax and nothing else.  It never looks at $PATH, never starts
a process, never evaluates anything, and never touches the rope -- the same
rule McMarkdownLinkScanner states for itself, and for the same reason: every
intermediate keystroke is parsed, so parsing must stay cheap and total.

Why not Microdown's MicMonospaceFormatBlock: its delimiter width is derived by
halving the difference between the raw span and the inner text, which assumes
a symmetric fixed-width delimiter.  Here the fence width is data.  The scanner
counts the opening run of backticks and closes only on a run of exactly that
length, which is what lets a span quote backticks of its own:

	``{python} len(""`backticks`"")``

The scanner is deliberately tolerant.  An unterminated span, an empty label, a
label with a space in it, or a label with no expression after it is not a
labeled span -- it is left entirely alone, so ordinary inline code goes on
rendering exactly as it did.  Half-typed syntax must not swallow the rest of
the line.

Chunk format: load with fileIn.
"!

Object subclass: #McMarkdownCode
	instanceVariableNames: 'language expression start stop bodyStart bodyStop fence isInline'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownCode class methodsFor: 'instance creation'!
language: aLanguage expression: anExpression start: aStart stop: aStop bodyStart: aBodyStart bodyStop: aBodyStop fence: aFence
	^ self new
		setLanguage: aLanguage
		expression: anExpression
		start: aStart
		stop: aStop
		bodyStart: aBodyStart
		bodyStop: aBodyStop
		fence: aFence
		isInline: true!

blockLanguage: aLanguage expression: anExpression start: aStart stop: aStop
	"A fenced block.  Its span comes from the parser's range for the code
	 node rather than from the scanner, so there is no fence width to carry."
	^ self new
		setLanguage: aLanguage
		expression: anExpression
		start: aStart
		stop: aStop
		bodyStart: aStart
		bodyStop: aStop
		fence: 3
		isInline: false! !

!McMarkdownCode class methodsFor: 'info strings'!
languageFromInfo: anInfoString
	"The language named by a fence's info string, or nil when the info string
	 is not a bare language.

	 Two infos are deliberately not languages: a sql&db= database view, which
	 has its own renderer and predates this, and a results{...} fence, which
	 is output rather than input.  Anything carrying = or & is treated as a
	 structured info string and left alone."
	| trimmed |
	anInfoString ifNil: [ ^ nil ].
	trimmed := anInfoString trimBoth.
	trimmed isEmpty ifTrue: [ ^ nil ].
	(trimmed includesSubstring: '=') ifTrue: [ ^ nil ].
	(trimmed includesSubstring: '&') ifTrue: [ ^ nil ].
	(self isResultsInfo: trimmed) ifTrue: [ ^ nil ].
	(trimmed anySatisfy: [ :each | each isSeparator ]) ifTrue: [ ^ nil ].
	^ trimmed asLowercase!

isResultsInfo: anInfoString
	"A results fence is written by an evaluation, not by hand:
	 results{2026-09-06T14:22:01.123Z}"
	| trimmed |
	anInfoString ifNil: [ ^ false ].
	trimmed := anInfoString trimBoth.
	^ (trimmed beginsWith: 'results{') and: [ trimmed endsWith: '}' ]!

resultsTimestampFrom: anInfoString
	"The timestamp inside a results fence's info string, as written.  Answers
	 nil rather than raising for anything that is not a results fence, because
	 this runs on the styling path over half-typed documents."
	| trimmed |
	(self isResultsInfo: anInfoString) ifFalse: [ ^ nil ].
	trimmed := anInfoString trimBoth.
	^ trimmed copyFrom: 'results{' size + 1 to: trimmed size - 1!

resultsInfoAt: aDateAndTime
	"The info string for a results fence stamped at aDateAndTime, in UTC."
	^ 'results{' , (self timestampStringFor: aDateAndTime) , '}'!

timestampStringFor: aDateAndTime
	"ISO-8601 with milliseconds, in UTC -- 2026-09-06T14:22:01.123Z.

	 Built by hand rather than through a printer because the result is
	 written into the user's document, so its shape is part of the file
	 format and must not drift with an image's locale or printing policy."
	| utc pad millis |
	utc := [ aDateAndTime asUTC ] on: Error do: [ :e | aDateAndTime ].
	pad := [ :n :width | n printString padLeftTo: width with: $0 ].
	millis := [ utc nanoSecond // 1000000 ] on: Error do: [ :e | 0 ].
	^ String streamContents: [ :out |
		out
			nextPutAll: (pad value: utc year value: 4);
			nextPut: $-;
			nextPutAll: (pad value: utc monthIndex value: 2);
			nextPut: $-;
			nextPutAll: (pad value: utc dayOfMonth value: 2);
			nextPut: $T;
			nextPutAll: (pad value: utc hour24 value: 2);
			nextPut: $:;
			nextPutAll: (pad value: utc minute value: 2);
			nextPut: $:;
			nextPutAll: (pad value: utc second value: 2);
			nextPut: $.;
			nextPutAll: (pad value: millis value: 3);
			nextPut: $Z ]! !

!McMarkdownCode class methodsFor: 'results fences'!
resultsRangeIn: aSource after: aStop
	"The range of the results fence belonging to a block ending at aStop,
	 INCLUDING the newlines that separate it from the block -- or nil when
	 the block has no results fence.

	 The separator is inside the range on purpose, so that writing and
	 clearing are the same operation over the same interval: replace it with
	 the fence text to record a result, replace it with nothing to remove
	 both the fence and the blank line that led to it.  That is what keeps a
	 block from accumulating a second results fence every time it is run.

	 At most one blank line may stand between the two.  Anything else -- a
	 paragraph, a second blank line, another block -- means the fence found
	 belongs to something else and must be left alone."
	| size index lineStart lineEnd line blanks closeEnd |
	aSource ifNil: [ ^ nil ].
	size := aSource size.
	index := aStop + 1.
	blanks := 0.
	[ index <= size ] whileTrue: [
		lineStart := index.
		lineEnd := self endOfLineIn: aSource from: lineStart.
		line := (aSource copyFrom: lineStart to: (lineEnd max: lineStart - 1)) trimBoth.
		line isEmpty
			ifTrue: [
				"Two of these: the line break ending the block, and one blank
				 line the writer is allowed to leave in between."
				blanks := blanks + 1.
				blanks > 2 ifTrue: [ ^ nil ].
				index := lineEnd + 2 ]
			ifFalse: [
				(line beginsWith: '```') ifFalse: [ ^ nil ].
				(self isResultsInfo: (line allButFirst: 3)) ifFalse: [ ^ nil ].
				closeEnd := self endOfFenceIn: aSource from: lineEnd + 2.
				^ closeEnd ifNil: [ nil ] ifNotNil: [ aStop + 1 to: closeEnd ] ] ].
	^ nil!

endOfLineIn: aSource from: anIndex
	"The index of the last character of the line beginning at anIndex.  For
	 an empty line that is anIndex - 1, which is what makes the caller's
	 lineEnd + 2 land on the line after."
	| i |
	i := anIndex.
	[ i <= aSource size and: [ (aSource at: i) ~= Character lf ] ]
		whileTrue: [ i := i + 1 ].
	^ i - 1!

endOfFenceIn: aSource from: anIndex
	"The index of the last character of the line that closes a fence opened
	 before anIndex, or nil when nothing closes it.  An unterminated results
	 fence answers nil rather than a guess: better to leave a broken document
	 alone than to rewrite the wrong range of it."
	| size index lineStart lineEnd |
	size := aSource size.
	index := anIndex.
	[ index <= size ] whileTrue: [
		lineStart := index.
		lineEnd := self endOfLineIn: aSource from: lineStart.
		((aSource copyFrom: lineStart to: (lineEnd max: lineStart - 1)) trimBoth
			beginsWith: '```') ifTrue: [ ^ lineEnd ].
		index := lineEnd + 2 ].
	^ nil!

resultsFenceFor: anOutput at: aDateAndTime
	"The text a successful run writes into the document, separator included.

	 A results fence is real markdown, so the result survives outside this
	 editor: another tool shows it as a code block with an unfamiliar
	 language, which is a fair degradation of `this is output'."
	| fence |
	fence := String new: (self fenceWidthFor: anOutput) withAll: $`.
	^ String streamContents: [ :out |
		out
			nextPut: Character lf;
			nextPut: Character lf;
			nextPutAll: fence;
			nextPutAll: (self resultsInfoAt: aDateAndTime);
			nextPut: Character lf;
			nextPutAll: (anOutput ifNil: [ '' ]);
			nextPut: Character lf;
			nextPutAll: fence ]!

fenceWidthFor: anOutput
	"Three backticks, unless the output itself contains a run that long --
	 an interpreter that prints markdown must not be able to close the fence
	 that is quoting it."
	| longest run |
	longest := 0.
	run := 0.
	(anOutput ifNil: [ '' ]) do: [ :each |
		each = $`
			ifTrue: [ run := run + 1. longest := longest max: run ]
			ifFalse: [ run := 0 ] ].
	^ 3 max: longest + 1! !

!McMarkdownCode methodsFor: 'initialization'!
setLanguage: aLanguage expression: anExpression start: aStart stop: aStop bodyStart: aBodyStart bodyStop: aBodyStop fence: aFence isInline: aBoolean
	language := aLanguage.
	expression := anExpression.
	start := aStart.
	stop := aStop.
	bodyStart := aBodyStart.
	bodyStop := aBodyStop.
	fence := aFence.
	isInline := aBoolean! !

!McMarkdownCode methodsFor: 'accessing'!
language
	^ language!

expression
	^ expression!

start
	^ start!

stop
	^ stop!

bodyStart
	^ bodyStart!

bodyStop
	^ bodyStop!

fence
	^ fence!

isInline
	^ isInline!

isBlock
	^ isInline not! !

!McMarkdownCode methodsFor: 'evaluation'!
canonicalExpression
	"What the cache is keyed on.  Trimmed at the ends and left exactly alone
	 in the middle: collapsing interior whitespace would silently corrupt
	 Python, where indentation is syntax."
	^ expression trimBoth!

cacheKey
	"Language and canonical source.  A line feed separates them because a
	 language name can never contain one, so no two distinct pairs can
	 collide on one key."
	^ language , (String with: Character lf) , self canonicalExpression! !

!McMarkdownCode methodsFor: 'printing'!
printOn: aStream
	aStream
		nextPutAll: self class name;
		nextPut: $(;
		nextPutAll: language;
		nextPutAll: ' ';
		print: expression;
		nextPutAll: ' ';
		print: start;
		nextPutAll: '..';
		print: stop;
		nextPut: $)! !

Object subclass: #McMarkdownCodeScanner
	instanceVariableNames: 'source size index spans'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownCodeScanner class methodsFor: 'scanning'!
scan: aString
	"The labeled code spans in one inline block, in source order."
	^ self new setSource: aString; scan! !

!McMarkdownCodeScanner methodsFor: 'initialization'!
setSource: aString
	source := aString ifNil: [ '' ].
	size := source size.
	index := 1.
	spans := OrderedCollection new! !

!McMarkdownCodeScanner methodsFor: 'scanning'!
scan
	[ index <= size ] whileTrue: [
		(source at: index) = $`
			ifTrue: [ self scanFenceAt: index ]
			ifFalse: [ index := index + 1 ] ].
	^ spans!

scanFenceAt: aStart
	"Try to read one labeled span starting at aStart.

	 Every failure advances past the opening run and returns, which is what
	 keeps the scan total: an unlabeled or unterminated span costs one run and
	 is then left for whatever else styles it."
	| runStop run labelStop language bodyStart closeStart body |
	runStop := self runEndFrom: aStart.
	run := runStop - aStart + 1.
	labelStop := self labelStopAfter: runStop.
	labelStop ifNil: [ index := runStop + 1. ^ self ].
	language := (source copyFrom: runStop + 2 to: labelStop - 1) asLowercase.
	bodyStart := labelStop + 1.
	closeStart := self closingRunFrom: bodyStart width: run.
	closeStart ifNil: [ index := runStop + 1. ^ self ].
	body := source copyFrom: bodyStart to: closeStart - 1.
	"An empty expression is a span still being typed, not a span to evaluate."
	body trimBoth isEmpty ifTrue: [ index := runStop + 1. ^ self ].
	spans add: (McMarkdownCode
		language: language
		expression: body trimBoth
		start: aStart
		stop: closeStart + run - 1
		bodyStart: bodyStart
		bodyStop: closeStart - 1
		fence: run).
	index := closeStart + run!

runEndFrom: aStart
	"The last index of the run of backticks beginning at aStart."
	| i |
	i := aStart.
	[ i < size and: [ (source at: i + 1) = $` ] ] whileTrue: [ i := i + 1 ].
	^ i!

labelStopAfter: aRunStop
	"The index of the $} closing a {label} that begins immediately after the
	 opening run, or nil when there is no such label.

	 The label must start at once -- a space between the backticks and the
	 brace makes it ordinary code -- and must be non-empty and free of
	 separators, braces and backticks."
	| i char seen |
	aRunStop + 1 > size ifTrue: [ ^ nil ].
	(source at: aRunStop + 1) = ${ ifFalse: [ ^ nil ].
	i := aRunStop + 2.
	seen := 0.
	[ i <= size ] whileTrue: [
		char := source at: i.
		char = $} ifTrue: [ ^ seen > 0 ifTrue: [ i ] ifFalse: [ nil ] ].
		(char isSeparator or: [ char = $` or: [ char = ${ ] ])
			ifTrue: [ ^ nil ].
		seen := seen + 1.
		i := i + 1 ].
	^ nil!

closingRunFrom: aStart width: aWidth
	"The index at which a run of exactly aWidth backticks begins, at or after
	 aStart, or nil.

	 Exactly: a longer run does not close a shorter one, which is what lets
	 a double-fenced span contain single backticks."
	| i runStop |
	i := aStart.
	[ i <= size ] whileTrue: [
		(source at: i) = $`
			ifTrue: [
				runStop := self runEndFrom: i.
				runStop - i + 1 = aWidth ifTrue: [ ^ i ].
				i := runStop + 1 ]
			ifFalse: [ i := i + 1 ] ].
	^ nil! !
