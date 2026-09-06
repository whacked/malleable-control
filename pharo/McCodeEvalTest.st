"
McCodeEvalTest -- the registry, the cache and the job scheduling, without a
subprocess.

Two seams make this headless and deterministic, both borrowed from
McSqliteSource, which had the same problem: `executor:' replaces the
interpreter with a block, and `jobRunner:' keeps a background job in hand so
the test decides when it runs.  Between them, `the styler did not evaluate
anything' becomes an assertion instead of a race.

The in-image Smalltalk tests use no seam at all -- there is nothing to stub,
because the evaluator under test is this image.

Chunk format: load with fileIn.
"!

TestCase subclass: #McCodeEvalTest
	instanceVariableNames: 'held'
	classVariableNames: ''
	package: 'MalleableControl'!

!McCodeEvalTest methodsFor: 'running'!
setUp
	super setUp.
	McCodeEvaluator reset.
	held := OrderedCollection new!

tearDown
	"Every class variable this suite touches is global to the image, so it is
	 put back whether the test passed or not."
	McCodeEvaluator reset.
	super tearDown! !

!McCodeEvalTest methodsFor: 'helpers'!
codeFor: aString
	^ (McMarkdownCodeScanner scan: aString) first!

python: anExpression
	^ McMarkdownCode
		blockLanguage: 'python'
		expression: anExpression
		start: 1
		stop: 2!

echoExecutor
	"Stands in for every interpreter, answering the expression it was given
	 so a test can tell one evaluation from another."
	^ [ :language :expression | language , ':' , expression ]!

runJobsInHand
	"Run every job the scheduler handed over, in order."
	| jobs |
	jobs := held asArray.
	held := OrderedCollection new.
	jobs do: [ :each | each value ]! !

!McCodeEvalTest methodsFor: 'tests - registry'!
testTheFourQuartoLanguagesAreRegistered
	#( 'python' 'r' 'julia' 'ojs' ) do: [ :each |
		self
			assert: (McCodeEvaluator languageNamed: each) notNil
			description: each , ' should be registered' ]!

testSmalltalkIsEvaluatedInThisImage
	self assert: (McCodeEvaluator languageNamed: 'smalltalk') isInImage!

testGtIsAnAliasForSmalltalk
	"gt reads naturally in this image, but the language is Smalltalk and the
	 tag says so."
	self
		assert: (McCodeEvaluator languageNamed: 'gt') name
		equals: 'smalltalk'!

testLanguageLookupIsCaseInsensitive
	self assert: (McCodeEvaluator languageNamed: 'PYTHON') notNil!

testUnknownLanguageHasNoEvaluator
	self assert: (McCodeEvaluator languageNamed: 'cobol') isNil! !

!McCodeEvalTest methodsFor: 'tests - failure is not a raise'!
testUnknownLanguageAnswersAFailedResult
	"A document naming a language you do not have must render as a visible
	 failure, never as a broken document or an open debugger."
	| result |
	result := McCodeEvaluator resultFor: (self codeFor: '`{cobol} 1`').
	self assert: result isFailed.
	self assert: (result message includesSubstring: 'cobol')!

testOjsIsParsedAndTaggedButNotEvaluated
	| result |
	result := McCodeEvaluator resultFor: (self codeFor: '`{ojs} Math.PI * 2`').
	self assert: result isFailed.
	self assert: (result message includesSubstring: 'ojs')!

testAnInterpreterThatRaisesAnswersAFailedResult
	McCodeEvaluator executor: [ :language :expression | self error: 'boom' ].
	self assert: (McCodeEvaluator resultFor: (self python: '1')) isFailed!

testFailedResultsAreCachedToo
	"Otherwise an expression naming a missing interpreter re-runs on every
	 keystroke to keep answering the same thing."
	| code |
	McCodeEvaluator executor: [ :language :expression | self error: 'boom' ].
	code := self python: '1'.
	McCodeEvaluator resultFor: code.
	McCodeEvaluator resultFor: code.
	self assert: McCodeEvaluator executionCount equals: 1! !

!McCodeEvalTest methodsFor: 'tests - caching'!
testResultIsCachedAfterTheFirstEvaluation
	| code |
	McCodeEvaluator executor: self echoExecutor.
	code := self python: '5 * 2'.
	self assert: (McCodeEvaluator resultFor: code) output equals: 'python:5 * 2'.
	self assert: McCodeEvaluator executionCount equals: 1.
	self assert: (McCodeEvaluator resultFor: code) output equals: 'python:5 * 2'.
	self
		assert: McCodeEvaluator executionCount = 1
		description: 'the second lookup must not re-run the interpreter'!

testTrailingWhitespaceDoesNotSplitTheCache
	McCodeEvaluator executor: self echoExecutor.
	McCodeEvaluator resultFor: (self python: '1 + 1').
	McCodeEvaluator resultFor: (self python: '  1 + 1  ').
	self assert: McCodeEvaluator executionCount equals: 1!

testInteriorWhitespaceDoesSplitTheCache
	"Indentation is syntax in Python: these are two different programs."
	McCodeEvaluator executor: self echoExecutor.
	McCodeEvaluator resultFor: (self python: 'if x:
    y').
	McCodeEvaluator resultFor: (self python: 'if x:
        y').
	self assert: McCodeEvaluator executionCount equals: 2!

testDifferentLanguagesDoNotShareAnEntry
	McCodeEvaluator executor: self echoExecutor.
	McCodeEvaluator resultFor: (self codeFor: '`{python} 1`').
	McCodeEvaluator resultFor: (self codeFor: '`{r} 1`').
	self assert: McCodeEvaluator executionCount equals: 2!

testForgetKeyForcesOneReEvaluation
	"The re-run keystroke.  Results are never invalidated on their own,
	 because a smalltalk expression reads live image state and a subprocess
	 may read a file that has changed since."
	| code |
	McCodeEvaluator executor: self echoExecutor.
	code := self python: '1'.
	McCodeEvaluator resultFor: code.
	McCodeEvaluator forgetKey: code cacheKey.
	McCodeEvaluator resultFor: code.
	self assert: McCodeEvaluator executionCount equals: 2!

testClearCacheDropsEveryEntry
	McCodeEvaluator executor: self echoExecutor.
	McCodeEvaluator resultFor: (self python: '1').
	McCodeEvaluator resultFor: (self python: '2').
	McCodeEvaluator clearCache.
	McCodeEvaluator resultFor: (self python: '1').
	self assert: McCodeEvaluator executionCount equals: 3!

testCacheIsBoundedAndEvictsTheLeastRecentlyUsed
	"A styler runs on every keystroke, so an unbounded cache grows once per
	 keystroke.  This is the bound doing its job."
	McCodeEvaluator executor: self echoExecutor.
	McCodeEvaluator cacheLimit: 2.
	McCodeEvaluator resultFor: (self python: '1').
	McCodeEvaluator resultFor: (self python: '2').
	McCodeEvaluator resultFor: (self python: '3').
	self assert: McCodeEvaluator executionCount equals: 3.
	"1 was evicted by 3, so it has to run again; 3 is still resident."
	McCodeEvaluator resultFor: (self python: '3').
	self assert: McCodeEvaluator executionCount equals: 3.
	McCodeEvaluator resultFor: (self python: '1').
	self assert: McCodeEvaluator executionCount equals: 4!

testCacheLimitDefaultsToSixtyFour
	self assert: McCodeEvaluator cacheLimit equals: 64! !

!McCodeEvalTest methodsFor: 'tests - scheduling'!
testColdExpressionAnswersPendingAndRunsNothingOnThisProcess
	| result |
	McCodeEvaluator executor: self echoExecutor.
	McCodeEvaluator jobRunner: [ :job | held add: job ].
	result := McCodeEvaluator
		resultFor: (self python: '1')
		token: self
		onComplete: nil.
	self assert: result isPending.
	self
		assert: McCodeEvaluator executionCount = 0
		description: 'the styling path must never wait on an interpreter'.
	self assert: held size equals: 1!

testCompletionBlockReceivesTheResultAndTheCacheIsWarm
	| delivered code |
	McCodeEvaluator executor: self echoExecutor.
	McCodeEvaluator jobRunner: [ :job | held add: job ].
	code := self python: '1'.
	McCodeEvaluator
		resultFor: code
		token: self
		onComplete: [ :result | delivered := result ].
	self runJobsInHand.
	self assert: delivered notNil.
	self assert: delivered isReady.
	self assert: (McCodeEvaluator cachedAt: code cacheKey) notNil.
	self assert: (McCodeEvaluator resultFor: code) isReady.
	self assert: McCodeEvaluator executionCount equals: 1!

testTwoSpansWithTheSameExpressionShareOneJob
	"Two spans holding the same expression must cost one process, not two."
	| code |
	McCodeEvaluator executor: self echoExecutor.
	McCodeEvaluator jobRunner: [ :job | held add: job ].
	code := self python: '1'.
	McCodeEvaluator resultFor: code token: self onComplete: nil.
	McCodeEvaluator resultFor: code token: self class onComplete: nil.
	self assert: held size equals: 1!

testRestylingWhileAJobRunsDoesNotStackJobs
	"A token registers one block, so restyling ten times while an expression
	 runs still schedules one job and still delivers one callback."
	| code count |
	McCodeEvaluator executor: self echoExecutor.
	McCodeEvaluator jobRunner: [ :job | held add: job ].
	code := self python: '1'.
	count := 0.
	10 timesRepeat: [
		McCodeEvaluator
			resultFor: code
			token: self
			onComplete: [ :result | count := count + 1 ] ].
	self assert: held size equals: 1.
	self runJobsInHand.
	self assert: count equals: 1.
	self assert: McCodeEvaluator executionCount equals: 1!

testAWarmExpressionNeverSchedulesAJob
	| code |
	McCodeEvaluator executor: self echoExecutor.
	code := self python: '1'.
	McCodeEvaluator resultFor: code.
	McCodeEvaluator jobRunner: [ :job | held add: job ].
	self
		assert: (McCodeEvaluator resultFor: code token: self onComplete: nil) isReady.
	self assert: held size equals: 0! !

!McCodeEvalTest methodsFor: 'tests - in-image smalltalk'!
testSmalltalkEvaluatesAgainstThisImage
	"The org-babel emacs-lisp case: the evaluator is the running process."
	| code |
	code := self codeFor: '`{smalltalk} 3 + 4`'.
	self assert: (McCodeEvaluator resultFor: code) output equals: '7'!

testSmalltalkReachesThisImagesState
	"Not a general-purpose Smalltalk: this image's own globals are in scope,
	 which is the whole point of evaluating in-process."
	| code result |
	code := self codeFor: '`{smalltalk} Smalltalk at: #McCodeEvaluator`'.
	result := McCodeEvaluator resultFor: code.
	self assert: result isReady.
	self assert: result output equals: 'McCodeEvaluator'!

testSmalltalkResultReadsAsAValueNotAsALiteral
	"displayString, not printString: Python's evaluator uses str() rather
	 than repr(), and a result rendered into prose should read the same way
	 in either language."
	self
		assert: (McCodeEvaluator resultFor: (self codeFor: '`{smalltalk} ''abc''`')) output
		equals: 'abc'!

testSmalltalkFailureIsAFailedResultNotADebugger
	"A typo in a document must not open a debugger over the editor."
	| result |
	result := McCodeEvaluator resultFor: (self codeFor: '`{smalltalk} 1 zork`').
	self assert: result isFailed.
	self deny: result message isEmpty!

testSmalltalkIsEvaluatedOnTheCallingProcessEvenWhenAsked
	"In-image evaluation never goes to a background process: the point of it
	 is to reach THIS process's state.  So it answers ready, not pending,
	 and schedules nothing."
	| result |
	McCodeEvaluator jobRunner: [ :job | held add: job ].
	result := McCodeEvaluator
		resultFor: (self codeFor: '`{smalltalk} 3 + 4`')
		token: self
		onComplete: nil.
	self assert: result isReady.
	self assert: held size equals: 0!

testSmalltalkResultIsCachedLikeAnyOther
	| code |
	code := self codeFor: '`{smalltalk} 3 + 4`'.
	McCodeEvaluator resultFor: code.
	McCodeEvaluator resultFor: code.
	self assert: McCodeEvaluator executionCount equals: 1! !

!McCodeEvalTest methodsFor: 'tests - results'!
testSuccessCarriesTheEvaluationTimestamp
	"The timestamp is written into the document's results fence, so it has
	 to exist on the result."
	| result |
	McCodeEvaluator executor: self echoExecutor.
	result := McCodeEvaluator resultFor: (self python: '1').
	self assert: result isReady.
	self assert: result evaluatedAt notNil!

testFailureCarriesNoTimestamp
	"Nothing is written to the document on failure, so there is nothing to
	 stamp."
	McCodeEvaluator executor: [ :language :expression | self error: 'boom' ].
	self assert: (McCodeEvaluator resultFor: (self python: '1')) evaluatedAt isNil!

testTrailingNewlineIsTrimmedButInteriorBreaksAreKept
	"An interpreter ends its output with a newline and a rendered result sits
	 on a line of prose; a genuinely multi-line result stays multi-line."
	McCodeEvaluator executor: [ :language :expression | 'one
two
' ].
	self
		assert: (McCodeEvaluator resultFor: (self python: '1')) output
		equals: 'one
two'!

testPendingResultDisplaysAsProgressNotAsEmptiness
	self assert: McCodeEvalResult pending displayString isEmpty not! !
