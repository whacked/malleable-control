"
McCacheTest -- tests for McBoundedCache and for McSqliteSource's caching and
scheduling.

None of these tests times anything.  A performance assertion made with a
clock is a test that fails on a busy machine and passes on a quiet one; the
properties worth pinning here are countable instead.  Did the second call to
the same query run sqlite3 again?  Did the cache stop growing at its limit?
Did styling the document run a subprocess on the calling process?  Every one
of those is a number, and every one of them is what the change was for.

McSqliteSource is exercised through its executor hook -- a block standing in
for sqlite3 -- and its job runner hook -- a block that keeps the background
job in hand rather than forking it.  That second one is what makes `the
styler did not block' an assertion: the job is never run unless the test runs
it, so an execution count of zero after styling means the query really did
not happen on the styling process.

Chunk format: load with fileIn.
"!

TestCase subclass: #McCacheTest
	instanceVariableNames: 'tempDir savedExecutor savedJobRunner deferredJobs'
	classVariableNames: ''
	package: 'MalleableControl'!

!McCacheTest methodsFor: 'running'!
setUp
	super setUp.
	savedExecutor := McSqliteSource executor.
	savedJobRunner := McSqliteSource jobRunner.
	deferredJobs := OrderedCollection new.
	McSqliteSource clearCache.
	McSqliteSource resetStatistics!

tearDown
	"Everything touched here is class-side state shared with the live editor,
	 so it is all put back -- the suite is run repeatedly against one image."
	McSqliteSource executor: savedExecutor.
	McSqliteSource jobRunner: savedJobRunner.
	McSqliteSource clearCache.
	McSqliteSource resetStatistics.
	tempDir ifNotNil: [
		[ tempDir ensureDeleteAll ] on: Error do: [ :e | nil ].
		tempDir := nil ].
	super tearDown! !

!McCacheTest methodsFor: 'helpers'!
tempDir
	^ tempDir ifNil: [
		tempDir := (FileLocator temp / ('mc-cache-test-' , UUID new asString)) asFileReference.
		tempDir ensureCreateDirectory.
		tempDir ]!

dbFileWith: aString
	"A stand-in database.  Nothing here opens it -- the executor hook takes
	 the place of sqlite3 -- but McSqliteSource stamps it and refuses to run
	 against a file that is not there, so it has to exist and its bytes have
	 to be able to change."
	| ref |
	ref := self tempDir / 'tasks.sqlite'.
	ref exists ifTrue: [ ref delete ].
	ref writeStreamDo: [ :stream | stream nextPutAll: aString ].
	^ ref!

asciiRowsOf: aCollectionOfRows
	"sqlite3's -ascii framing: 0x1F between fields, 0x1E between records."
	| unit record |
	unit := Character value: 16r1F.
	record := Character value: 16r1E.
	^ String streamContents: [ :stream |
		aCollectionOfRows do: [ :row |
			row do: [ :field | stream nextPutAll: field ]
				separatedBy: [ stream nextPut: unit ].
			stream nextPut: record ] ]!

answering: aString
	"Install an executor that answers aString however it is called."
	McSqliteSource executor: [ :path :sql | aString ]!

failingWith: aMessage
	McSqliteSource executor: [ :path :sql | Error signal: aMessage ]!

deferJobs
	"Keep every background job in hand instead of forking it."
	McSqliteSource jobRunner: [ :job | deferredJobs add: job ]!

runDeferredJobs
	| jobs |
	jobs := deferredJobs.
	deferredJobs := OrderedCollection new.
	jobs do: [ :each | each value ].
	^ jobs size! !

!McCacheTest methodsFor: 'tests - bounded cache'!
testAbsentKeyAnswersTheDefaultAndCountsAMiss
	| cache |
	cache := McBoundedCache limit: 4.
	self assert: (cache at: 'a' ifAbsent: [ #none ]) equals: #none.
	self assert: cache misses equals: 1.
	self assert: cache hits equals: 0!

testStoredKeyAnswersItsValueAndCountsAHit
	| cache |
	cache := McBoundedCache limit: 4.
	cache at: 'a' put: 1.
	self assert: (cache at: 'a' ifAbsent: [ #none ]) equals: 1.
	self assert: cache hits equals: 1!

testStoringTheSameKeyTwiceDoesNotGrowTheCache
	| cache |
	cache := McBoundedCache limit: 4.
	cache at: 'a' put: 1.
	cache at: 'a' put: 2.
	self assert: cache size equals: 1.
	self assert: cache keysInOrder size equals: 1.
	self assert: (cache at: 'a' ifAbsent: [ nil ]) equals: 2!

testEvictsTheLeastRecentlyUsedKey
	| cache |
	cache := McBoundedCache limit: 2.
	cache at: 'a' put: 1.
	cache at: 'b' put: 2.
	cache at: 'c' put: 3.
	self assert: cache size equals: 2.
	self deny: (cache includesKey: 'a').
	self assert: (cache includesKey: 'b').
	self assert: (cache includesKey: 'c').
	self assert: cache evictions equals: 1!

testALookupPromotesItsKeyPastEviction
	"The point of recency: the entry being asked for is the one kept."
	| cache |
	cache := McBoundedCache limit: 2.
	cache at: 'a' put: 1.
	cache at: 'b' put: 2.
	cache at: 'a' ifAbsent: [ nil ].
	cache at: 'c' put: 3.
	self assert: (cache includesKey: 'a').
	self deny: (cache includesKey: 'b')!

testMembershipDoesNotPromoteOrCount
	| cache |
	cache := McBoundedCache limit: 2.
	cache at: 'a' put: 1.
	cache at: 'b' put: 2.
	cache includesKey: 'a'.
	self assert: cache hits equals: 0.
	self assert: cache misses equals: 0.
	cache at: 'c' put: 3.
	self deny: (cache includesKey: 'a')!

testAtIfAbsentPutComputesOnceAndReuses
	| cache calls |
	cache := McBoundedCache limit: 4.
	calls := 0.
	2 timesRepeat: [ cache at: 'a' ifAbsentPut: [ calls := calls + 1. 99 ] ].
	self assert: calls equals: 1.
	self assert: (cache at: 'a' ifAbsent: [ nil ]) equals: 99!

testRemoveKeyForgetsTheEntryAndItsPlaceInTheOrder
	| cache |
	cache := McBoundedCache limit: 4.
	cache at: 'a' put: 1.
	self assert: (cache removeKey: 'a' ifAbsent: [ #none ]) equals: 1.
	self assert: cache size equals: 0.
	self assert: cache keysInOrder isEmpty.
	self assert: (cache removeKey: 'a' ifAbsent: [ #none ]) equals: #none!

testKeysAreAnsweredInEvictionOrder
	| cache |
	cache := McBoundedCache limit: 4.
	cache at: 'a' put: 1.
	cache at: 'b' put: 2.
	cache at: 'c' put: 3.
	cache at: 'a' ifAbsent: [ nil ].
	self assert: cache keysInOrder equals: #('b' 'c' 'a')!

testLimitIsNeverLessThanOne
	self assert: (McBoundedCache limit: 0) limit equals: 1!

testResetStatisticsLeavesTheEntriesAlone
	| cache |
	cache := McBoundedCache limit: 4.
	cache at: 'a' put: 1.
	cache at: 'a' ifAbsent: [ nil ].
	cache resetStatistics.
	self assert: cache hits equals: 0.
	self assert: cache size equals: 1! !

!McCacheTest methodsFor: 'tests - query caching'!
testQueryRunsOnceAndIsThenAnsweredFromTheCache
	| db source |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('name') #('write'))).
	source := McSqliteSource on: db fullName.
	self assert: (source query: 'SELECT name FROM tasks') rowCount equals: 1.
	self assert: (source query: 'SELECT name FROM tasks') rowCount equals: 1.
	self assert: McSqliteSource executionCount equals: 1!

testADifferentQueryIsNotACacheHit
	| db source |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('name') #('write'))).
	source := McSqliteSource on: db fullName.
	source query: 'SELECT 1'.
	source query: 'SELECT 2'.
	self assert: McSqliteSource executionCount equals: 2!

testTheCacheInvalidatesWhenTheDatabaseChanges
	"The stamp carries the file's size as well as its modification time,
	 because modification time has one-second resolution on some
	 filesystems and a write inside the same second would go unseen."
	| db source |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('name') #('write'))).
	source := McSqliteSource on: db fullName.
	source query: 'SELECT name FROM tasks'.
	self dbFileWith: 'one and a bit more'.
	source query: 'SELECT name FROM tasks'.
	self assert: McSqliteSource executionCount equals: 2!

testAFailureIsCachedWhileTheDatabaseIsUnchanged
	"A query that fails on every keystroke must not shell out on every
	 keystroke -- that was the reason for caching errors at all."
	| db source failures |
	db := self dbFileWith: 'one'.
	self failingWith: 'near "SELCT": syntax error'.
	source := McSqliteSource on: db fullName.
	failures := 0.
	2 timesRepeat: [
		[ source query: 'SELCT' ] on: Error do: [ :e | failures := failures + 1 ] ].
	self assert: failures equals: 2.
	self assert: McSqliteSource executionCount equals: 1!

testACachedFailureInvalidatesWhenTheDatabaseChanges
	| db source |
	db := self dbFileWith: 'one'.
	self failingWith: 'database is locked'.
	source := McSqliteSource on: db fullName.
	[ source query: 'SELECT 1' ] on: Error do: [ :e | nil ].
	self dbFileWith: 'one and a bit more'.
	[ source query: 'SELECT 1' ] on: Error do: [ :e | nil ].
	self assert: McSqliteSource executionCount equals: 2!

testAMissingDatabaseIsReportedWithoutRunningSqlite
	| source result |
	source := McSqliteSource on: (self tempDir / 'absent.sqlite') fullName.
	result := source resolveNow: 'SELECT 1'.
	self assert: result isFailed.
	self assert: (result message includesSubstring: 'Database not found').
	self assert: McSqliteSource executionCount equals: 0!

testAMissingDatabaseErrorDoesNotSurviveTheDatabaseAppearing
	"The defect this stamping fixes: the old cache keyed a `Database not
	 found' answer under the literal string `error', so it outlived the
	 database appearing and only a manual clear could dislodge it."
	| path source |
	path := (self tempDir / 'tasks.sqlite') fullName.
	source := McSqliteSource on: path.
	self answering: (self asciiRowsOf: #(#('name') #('write'))).
	self assert: (source resolveNow: 'SELECT 1') isFailed.
	self dbFileWith: 'now it exists'.
	self assert: (source resolveNow: 'SELECT 1') isReady.
	self assert: McSqliteSource executionCount equals: 1!

testTheQueryCacheIsBounded
	"Keyed by the SQL text, which the user is editing: unbounded, this grew
	 by one entry for every keystroke in the fence and never shrank."
	| db source |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('n') #('1'))).
	source := McSqliteSource on: db fullName.
	1 to: McSqliteSource cacheLimit + 20 do: [ :index |
		source query: 'SELECT ' , index printString ].
	self assert: McSqliteSource queryCache size equals: McSqliteSource cacheLimit!

testClearCacheForcesTheQueryToRunAgain
	| db source |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('n') #('1'))).
	source := McSqliteSource on: db fullName.
	source query: 'SELECT 1'.
	McSqliteSource clearCache.
	source query: 'SELECT 1'.
	self assert: McSqliteSource executionCount equals: 2! !

!McCacheTest methodsFor: 'tests - asynchronous queries'!
testAsyncAnswersPendingWithoutRunningTheQuery
	"The whole point: asking for a cold query must not run a subprocess on
	 the process that asked."
	| db source result |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('n') #('1'))).
	self deferJobs.
	source := McSqliteSource on: db fullName.
	result := source queryAsync: 'SELECT 1' token: self onComplete: [ :r | nil ].
	self assert: result isPending.
	self assert: McSqliteSource executionCount equals: 0!

testAsyncDeliversTheResultWhenTheJobRuns
	| db source delivered |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('name') #('write'))).
	self deferJobs.
	source := McSqliteSource on: db fullName.
	delivered := OrderedCollection new.
	source queryAsync: 'SELECT 1' token: self onComplete: [ :r | delivered add: r ].
	self assert: (self runDeferredJobs) equals: 1.
	self assert: delivered size equals: 1.
	self assert: delivered first isReady.
	self assert: delivered first relation rowCount equals: 1.
	self assert: McSqliteSource executionCount equals: 1!

testAsyncAnswersTheResultDirectlyOnceItIsCached
	| db source |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('name') #('write'))).
	self deferJobs.
	source := McSqliteSource on: db fullName.
	source queryAsync: 'SELECT 1' token: self onComplete: [ :r | nil ].
	self runDeferredJobs.
	self assert: (source queryAsync: 'SELECT 1' token: self onComplete: [ :r | nil ]) isReady.
	self assert: McSqliteSource executionCount equals: 1!

testAsyncSchedulesOneJobHoweverOftenItIsAsked
	"A styler asks again on every keystroke, and a query in flight must not
	 collect a subprocess per keystroke."
	| db source |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('n') #('1'))).
	self deferJobs.
	source := McSqliteSource on: db fullName.
	5 timesRepeat: [
		self assert: (source queryAsync: 'SELECT 1' token: self onComplete: [ :r | nil ]) isPending ].
	self assert: (self runDeferredJobs) equals: 1.
	self assert: McSqliteSource executionCount equals: 1!

testAsyncDeliversOneCallbackPerTokenHoweverOftenItRegisters
	| db source calls |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('n') #('1'))).
	self deferJobs.
	source := McSqliteSource on: db fullName.
	calls := 0.
	5 timesRepeat: [
		source queryAsync: 'SELECT 1' token: self onComplete: [ :r | calls := calls + 1 ] ].
	self runDeferredJobs.
	self assert: calls equals: 1!

testAsyncDeliversAFailureAsAResultRatherThanRaising
	| db source delivered |
	db := self dbFileWith: 'one'.
	self failingWith: 'no such table: tasks'.
	self deferJobs.
	source := McSqliteSource on: db fullName.
	delivered := OrderedCollection new.
	source queryAsync: 'SELECT 1' token: self onComplete: [ :r | delivered add: r ].
	self runDeferredJobs.
	self assert: delivered first isFailed.
	self assert: delivered first message equals: 'no such table: tasks'!

testAJobThatFinishesLeavesNothingPending
	| db source key |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('n') #('1'))).
	self deferJobs.
	source := McSqliteSource on: db fullName.
	key := source cacheKeyFor: 'SELECT 1'.
	source queryAsync: 'SELECT 1' token: self onComplete: [ :r | nil ].
	self assert: (McSqliteSource isPendingFor: key).
	self runDeferredJobs.
	self deny: (McSqliteSource isPendingFor: key)!

testAFailingListenerDoesNotCostTheOthersTheirCallback
	| db source calls |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('n') #('1'))).
	self deferJobs.
	source := McSqliteSource on: db fullName.
	calls := 0.
	source queryAsync: 'SELECT 1' token: Object new onComplete: [ :r | Error signal: 'listener' ].
	source queryAsync: 'SELECT 1' token: Object new onComplete: [ :r | calls := calls + 1 ].
	self runDeferredJobs.
	self assert: calls equals: 1!

testARealBackgroundJobDeliversItsResultWithoutBlockingTheAsker
	"The one test that forks for real rather than deferring, because the
	 claim being made is about a process boundary.  The asker gets pending
	 back before the job has run at all -- the job is at a priority below
	 this process and cannot start until this process waits -- and the
	 result is there afterwards."
	| db source delivered result |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('name') #('write'))).
	McSqliteSource jobRunner: nil.
	source := McSqliteSource on: db fullName.
	delivered := Semaphore new.
	result := source
		queryAsync: 'SELECT 1'
		token: self
		onComplete: [ :r | delivered signal ].
	self assert: result isPending.
	self assert: McSqliteSource executionCount equals: 0.
	"waitTimeoutSeconds: answers true when the deadline expired."
	self
		deny: (delivered waitTimeoutSeconds: 10)
		description: 'the background job never finished'.
	self assert: (source queryAsync: 'SELECT 1' token: self onComplete: nil) isReady.
	self assert: McSqliteSource executionCount equals: 1!

testTheCacheSurvivesTwoProcessesUsingItAtOnce
	"The background process writes the cache and the UI process reads it,
	 and Pharo preempts the lower-priority one wherever it happens to be --
	 including inside a Dictionary growing itself.  This drives both sides
	 hard enough to find an unguarded one."
	| db source readers done errors |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('n') #('1'))).
	McSqliteSource jobRunner: nil.
	source := McSqliteSource on: db fullName.
	errors := OrderedCollection new.
	done := Semaphore new.
	readers := 4.
	readers timesRepeat: [
		[ [ 200 timesRepeat: [
			source cachedResultFor: 'SELECT ' , 200 atRandom printString ] ]
			on: Error do: [ :e | errors add: e messageText asString ].
		  done signal ] forkAt: Processor userBackgroundPriority ].
	1 to: 200 do: [ :index |
		source
			queryAsync: 'SELECT ' , index printString
			token: self
			onComplete: nil ].
	readers timesRepeat: [
		self deny: (done waitTimeoutSeconds: 30) description: 'a reader never finished' ].
	self assert: errors asArray equals: #().
	self assert: McSqliteSource queryCache size <= McSqliteSource cacheLimit!

testClearCacheAbandonsPendingJobs
	| db source key |
	db := self dbFileWith: 'one'.
	self answering: (self asciiRowsOf: #(#('n') #('1'))).
	self deferJobs.
	source := McSqliteSource on: db fullName.
	key := source cacheKeyFor: 'SELECT 1'.
	source queryAsync: 'SELECT 1' token: self onComplete: [ :r | nil ].
	McSqliteSource clearCache.
	self deny: (McSqliteSource isPendingFor: key)! !

!McCacheTest methodsFor: 'tests - ascii parsing'!
testAsciiOutputBecomesColumnsAndRows
	| relation |
	relation := (McSqliteSource on: 'unused') parseAsciiOutput:
		(self asciiRowsOf: #(#('name' 'done') #('write' '1') #('ship' '0'))).
	self assert: relation columnCount equals: 2.
	self assert: relation rowCount equals: 2.
	self assert: (relation columns first name) equals: 'name'.
	self assert: (relation at: 1 column: 1) source equals: 'write'.
	self assert: (relation at: 2 column: 2) source equals: '0'!

testEmptyOutputBecomesAnEmptyRelation
	| relation |
	relation := (McSqliteSource on: 'unused') parseAsciiOutput: ''.
	self assert: relation rowCount equals: 0.
	self assert: relation columnCount equals: 0!

testANumericColumnIsRightAlignedAndATextualOneIsNot
	"The alignment pass reached its cells through McRelationRow>>at:, which
	 takes a column *name* -- so an integer index found no column, every
	 cell read as empty, and every column came out right-aligned."
	| relation |
	relation := (McSqliteSource on: 'unused') parseAsciiOutput:
		(self asciiRowsOf: #(#('name' 'prio') #('write' '1') #('ship' '2'))).
	self assert: relation columns first alignment equals: #left.
	self assert: relation columns second alignment equals: #right!

testQueryResultCellsAreDataRatherThanMarkdown
	| relation |
	relation := (McSqliteSource on: 'unused') parseAsciiOutput:
		(self asciiRowsOf: #(#('n') #('**not bold**'))).
	self deny: relation directives cellsAreMarkdown.
	self deny: relation directives isSortable! !
