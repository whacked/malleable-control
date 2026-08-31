"
McSqlite -- execute a read-only SQLite query and answer an McRelation.

Runs sqlite3 -readonly -header -ascii through GtSubprocessWithInMemoryOutput.
The -ascii mode frames columns with 0x1F (Unit Separator) and rows with 0x1E
(Record Separator), so there is no quoting or escaping to parse.  -readonly
makes the read-only decision the driver's rather than our discipline.

The database path is resolved relative to McHome (the project root) when it is
not absolute.

Two things here are about the styler rather than about SQLite.

*Not blocking.*  A styler runs on the UI process on every keystroke and every
cursor move, and shelling out to sqlite3 from inside one freezes the editor
for as long as the query takes.  So the query is asked for with
queryAsync:token:onComplete:, which answers whatever is already known -- a
result, a failure, or `pending' -- and never runs a subprocess itself.  When
it answers pending it has started a job on a background process, and calls
back when that job finishes.  GtSubprocessWithInMemoryOutput>>wait blocks on
a Semaphore, which suspends only the Pharo process that waits on it, so the
subprocess genuinely runs beside the UI rather than in front of it.

*Bounding and invalidating.*  Results and failures alike are cached, because
the styler asks for the same query on every restyle.  The cache is bounded
(McBoundedCache) because it is keyed by text the user is editing, and an
unbounded one grows by one entry per keystroke.  Every entry carries a stamp
of the database file -- its modification time and size, or `missing' when
there is no file -- and an entry whose stamp no longer matches the file is
dropped on the next lookup.  That is what makes a cached failure safe: a
`Database not found' answer invalidates itself the moment the file appears,
without anyone having to remember to clear it.

*Two processes, one cache.*  Running the query off the UI process means the
cache is written by the background process and read by the UI one, and Pharo
preempts a lower-priority process the instant a higher-priority one is ready
-- including in the middle of a Dictionary growing itself.  So every touch of
the cache and of the pending-job table goes through one Mutex.  The critical
sections hold nothing but the collection operations: stamping the database
file is done before the lock is taken, and the subprocess is run and the
listeners are called after it is released, so the UI process never waits on
anything slower than a dictionary store.

Chunk format: load with fileIn.
"!

Object subclass: #McSqliteResult
	instanceVariableNames: 'state relation message stamp'
	classVariableNames: ''
	package: 'MalleableControl'!

Object subclass: #McSqliteSource
	instanceVariableNames: 'dbPath'
	classVariableNames: 'QueryCache PendingQueries CacheGeneration ExecutionCount Executor JobRunner AccessLock'
	package: 'MalleableControl'!

!McSqliteResult class methodsFor: 'instance creation'!
ready: aRelation
	^ self new setState: #ready relation: aRelation message: nil!

failed: aMessage
	^ self new setState: #failed relation: nil message: aMessage!

pending
	"Not an answer yet.  Carries no stamp and is never cached: it says only
	 that a job is running."
	^ self new setState: #pending relation: nil message: nil! !

!McSqliteResult methodsFor: 'initialization'!
setState: aSymbol relation: aRelationOrNil message: aStringOrNil
	state := aSymbol.
	relation := aRelationOrNil.
	message := aStringOrNil! !

!McSqliteResult methodsFor: 'accessing'!
state
	^ state!

relation
	^ relation!

message
	^ message!

stamp
	"The state of the database file when this result was produced.  A lookup
	 that finds a different stamp discards the entry -- see
	 McSqliteSource>>cachedResultFor:."
	^ stamp!

stamp: aString
	stamp := aString!

isReady
	^ state = #ready!

isFailed
	^ state = #failed!

isPending
	^ state = #pending! !

!McSqliteResult methodsFor: 'printing'!
printOn: aStream
	aStream << 'McSqliteResult(' << state asString.
	message ifNotNil: [ aStream << ' ' << message ].
	relation ifNotNil: [ aStream << ' ' << relation rowCount printString << ' rows' ].
	aStream << ')'! !

!McSqliteSource class methodsFor: 'instance creation'!
on: aPath
	^ self new setDbPath: aPath! !

!McSqliteSource class methodsFor: 'cache'!
cacheLimit
	"Bounded because the key holds the SQL text, and the styler asks again
	 on every keystroke: an unbounded cache keeps one entry per prefix of
	 every query ever typed."
	^ 64!

queryCache
	"The cache itself.  Callers that are not this class should read it but
	 not write it -- every write here goes through accessLock."
	^ QueryCache ifNil: [ QueryCache := McBoundedCache limit: self cacheLimit ]!

accessLock
	"One lock over the query cache and the pending-job table, because the
	 background query process writes both and the UI process reads both.
	 Re-entrant, and only ever held around a collection operation."
	^ AccessLock ifNil: [ AccessLock := Mutex new ]!

cachedAt: aKey
	^ self accessLock critical: [ self queryCache at: aKey ifAbsent: [ nil ] ]!

cacheAt: aKey put: aResult
	^ self accessLock critical: [ self queryCache at: aKey put: aResult ]!

uncacheKey: aKey ifIdentical: anEntry
	"Remove only the stale entry the caller inspected.  A background query may
	 have replaced it while the caller was checking the file stamp."
	^ self accessLock critical: [
		(self queryCache at: aKey ifAbsent: [ nil ]) == anEntry
			ifTrue: [ self queryCache removeKey: aKey ifAbsent: [ nil ] ] ]!

clearCache
	"Drop every result and invalidate every job in flight.  Incrementing the
	 generation prevents an older job from populating the fresh cache or from
	 consuming listeners registered by a replacement job for the same key.
	 Abandoned listeners are notified after releasing the lock so callers that
	 currently show a pending placeholder get a chance to request a restyle."
	| abandoned pending |
	abandoned := self accessLock critical: [
		| listeners |
		listeners := PendingQueries
			ifNil: [ #() ]
			ifNotNil: [ PendingQueries values asArray ].
		QueryCache := nil.
		PendingQueries := nil.
		CacheGeneration := self cacheGeneration + 1.
		listeners ].
	pending := McSqliteResult pending.
	abandoned do: [ :listeners |
		listeners valuesDo: [ :each |
			[ each value: pending ] on: Error do: [ :e | nil ] ] ]!

cacheGeneration
	^ CacheGeneration ifNil: [ CacheGeneration := 0 ]!

cacheAt: aKey put: aResult ifGeneration: aGeneration
	"Store aResult only if no clear happened while it was being computed."
	^ self accessLock critical: [
		self cacheGeneration = aGeneration
			ifTrue: [ self queryCache at: aKey put: aResult ]
			ifFalse: [ aResult ] ]! !

!McSqliteSource class methodsFor: 'pending jobs'!
pendingQueries
	"cacheKey -> IdentityDictionary of token -> completion block.  A token
	 -- in practice the editor asking -- may register only one block per
	 job, so restyling ten times while a query runs still schedules one job
	 and still delivers one callback."
	^ PendingQueries ifNil: [ PendingQueries := Dictionary new ]!

isPendingFor: aKey
	^ self accessLock critical: [ self pendingQueries includesKey: aKey ]!

schedule: aKey source: aSource sql: aSqlString token: aTokenOrNil onComplete: aBlockOrNil
	"Start a background job for aKey unless one is already running, and
	 register the caller's completion block against it either way.

	 Claiming the key and registering the block are one critical section,
	 because two processes both finding nothing pending would both fork a
	 subprocess for the same query.  Starting the job is outside it: a job
	 runner that runs the job in hand -- a test -- would otherwise finish
	 the whole query while the lock was held."
	| started listeners generation |
	started := self accessLock critical: [
		listeners := self pendingQueries at: aKey ifAbsent: [ nil ].
		listeners
			ifNotNil: [
				self register: aBlockOrNil for: aTokenOrNil in: listeners.
				false ]
			ifNil: [
				listeners := IdentityDictionary new.
				self register: aBlockOrNil for: aTokenOrNil in: listeners.
				self pendingQueries at: aKey put: listeners.
				generation := self cacheGeneration.
				true ] ].
	started ifFalse: [ ^ self ].
	self runJob: [
		[ | result |
		  result := [ aSource runAndCache: aSqlString ifGeneration: generation ]
			on: Error
			do: [ :e | McSqliteResult failed: (self messageOf: e) ].
		  self finish: aKey listeners: listeners generation: generation with: result ]
			ensure: [
				self abandon: aKey listeners: listeners generation: generation ] ]!

register: aBlockOrNil for: aTokenOrNil in: aDictionary
	(aTokenOrNil isNil or: [ aBlockOrNil isNil ]) ifTrue: [ ^ self ].
	aDictionary at: aTokenOrNil put: aBlockOrNil!

finish: aKey listeners: expectedListeners generation: aGeneration with: aResult
	"Notify only the listeners belonging to this exact job generation.  One
	 failing listener must not cost the others their callback."
	| listenersToNotify |
	listenersToNotify := self accessLock critical: [
		| current |
		current := self pendingQueries at: aKey ifAbsent: [ nil ].
		(self cacheGeneration = aGeneration and: [ current == expectedListeners ])
			ifTrue: [ self pendingQueries removeKey: aKey. expectedListeners ]
			ifFalse: [ nil ] ].
	listenersToNotify ifNil: [ ^ self ].
	listenersToNotify valuesDo: [ :each |
		[ each value: aResult ] on: Error do: [ :e | nil ] ]!

abandon: aKey listeners: expectedListeners generation: aGeneration
	"Remove a failed job's slot without disturbing a newer job for the key."
	self accessLock critical: [
		| current |
		current := self pendingQueries at: aKey ifAbsent: [ nil ].
		(self cacheGeneration = aGeneration and: [ current == expectedListeners ])
			ifTrue: [ self pendingQueries removeKey: aKey ] ]!

messageOf: anError
	^ (anError messageText ifNil: [ anError class name ]) asString! !

!McSqliteSource class methodsFor: 'jobs'!
jobRunner
	"How a background job is started, or nil for the real one.  A test sets
	 this to keep the job in hand -- running it when it chooses, which is
	 what makes `the styler did not run the query' an assertion rather than
	 a race."
	^ JobRunner!

jobRunner: aBlockOrNil
	JobRunner := aBlockOrNil!

runJob: aBlock
	"userBackgroundPriority, below the UI process: the job runs in the gaps,
	 and the subprocess it waits on suspends only this process."
	self jobRunner
		ifNil: [ aBlock forkAt: Processor userBackgroundPriority ]
		ifNotNil: [ :runner | runner value: aBlock ]! !

!McSqliteSource class methodsFor: 'statistics'!
executionCount
	"How many times sqlite3 has actually been invoked.  The cache is only
	 worth having if this stops going up, and that is testable."
	^ ExecutionCount ifNil: [ 0 ]!

countExecution
	ExecutionCount := self executionCount + 1!

resetStatistics
	ExecutionCount := 0.
	self queryCache resetStatistics! !

!McSqliteSource class methodsFor: 'testing support'!
executor
	"A two-argument block of database path and SQL answering sqlite3's raw
	 stdout, or nil to really run sqlite3.  Exists so the caching and
	 scheduling above can be tested without a database or a subprocess."
	^ Executor!

executor: aBlockOrNil
	Executor := aBlockOrNil! !

!McSqliteSource methodsFor: 'initialization'!
setDbPath: aString
	dbPath := aString! !

!McSqliteSource methodsFor: 'accessing'!
dbPath
	^ dbPath!

resolvedDbPath
	"Resolve the database path against the project root when relative."
	| ref root |
	ref := dbPath asFileReference.
	ref isAbsolute ifTrue: [ ^ ref ].
	root := (Smalltalk at: #McHome ifAbsent: [ nil ])
		ifNil: [ FileLocator workingDirectory resolve ]
		ifNotNil: [ :path | path asFileReference ].
	^ root / dbPath! !

!McSqliteSource methodsFor: 'cache'!
cacheKeyFor: aSqlString
	^ dbPath , '|' , aSqlString!

stamp
	"What the cache compares to decide whether an entry still describes the
	 database.  Modification time alone is not enough -- it has one-second
	 resolution on some filesystems, and a write within the same second
	 would go unnoticed -- so the size goes in with it.  A database that is
	 not there stamps as `missing', which is the whole point: a cached
	 `Database not found' failure invalidates itself as soon as the file
	 appears, with nobody having to clear it."
	| ref |
	ref := self resolvedDbPath.
	^ [ ref exists
		ifFalse: [ 'missing' ]
		ifTrue: [ ref modificationTime printString , '|' , ref size printString ] ]
		on: Error
		do: [ :e | 'unstampable' ]!

cachedResultFor: aSqlString
	"The cached result for aSqlString, or nil when there is none that still
	 describes the database as it is now."
	| key entry |
	key := self cacheKeyFor: aSqlString.
	entry := self class cachedAt: key.
	entry ifNil: [ ^ nil ].
	"Stamping touches the filesystem, so it is done outside the lock."
	entry stamp = self stamp ifTrue: [ ^ entry ].
	self class uncacheKey: key ifIdentical: entry.
	^ nil! !

!McSqliteSource methodsFor: 'querying'!
query: aSqlString
	"Execute aSqlString against the database and answer an McRelation,
	 signalling an Error on failure.  Synchronous: it runs the query on the
	 calling process when the cache cannot answer.

	 Kept for callers that have nowhere to put a callback -- a headless
	 render, a test, an inspector.  The editor uses queryAsync:token:onComplete:."
	| result |
	result := self resolveNow: aSqlString.
	result isFailed ifTrue: [ ^ Error signal: result message ].
	^ result relation!

resolveNow: aSqlString
	"The result for aSqlString, running the query on this process if the
	 cache cannot answer.  Never answers pending."
	^ self cachedResultFor: aSqlString ifAbsent: [ self runAndCache: aSqlString ]!

cachedResultFor: aSqlString ifAbsent: aBlock
	^ (self cachedResultFor: aSqlString) ifNil: [ aBlock value ]!

queryAsync: aSqlString token: aTokenOrNil onComplete: aBlockOrNil
	"Answer what is known about aSqlString right now, without ever running a
	 subprocess on the calling process.

	 A cached result -- success or failure -- is answered directly.
	 Otherwise a background job is started (or joined, if one is already
	 running for the same database and SQL), aBlockOrNil is registered to be
	 called with the result when it lands, and `pending' is answered so the
	 caller can draw a placeholder.

	 aTokenOrNil identifies the caller so that restyling repeatedly while a
	 query runs replaces its callback rather than accumulating callbacks."
	| cached |
	cached := self cachedResultFor: aSqlString.
	cached ifNotNil: [ ^ cached ].
	self class
		schedule: (self cacheKeyFor: aSqlString)
		source: self
		sql: aSqlString
		token: aTokenOrNil
		onComplete: aBlockOrNil.
	"A job runner that runs the job in hand -- a test -- has already
	 finished it by now, so look once more before settling for pending."
	^ (self cachedResultFor: aSqlString) ifNil: [ McSqliteResult pending ]!

runAndCache: aSqlString
	"Run the query and cache whatever came of it, success or failure, under
	 the stamp the database had when the run started.  Taking the stamp
	 first is the conservative order: a database written while the query ran
	 leaves an entry stamped with the older state, which the next lookup
	 sees as stale and re-runs."
	| generation |
	generation := self class accessLock critical: [ self class cacheGeneration ].
	^ self runAndCache: aSqlString ifGeneration: generation!

runAndCache: aSqlString ifGeneration: aGeneration
	"Run the query, but publish it only if its cache generation is current."
	| stamp result |
	stamp := self stamp.
	result := [ McSqliteResult ready: (self execute: aSqlString) ]
		on: Error
		do: [ :e | McSqliteResult failed: (self class messageOf: e) ].
	result stamp: stamp.
	self class
		cacheAt: (self cacheKeyFor: aSqlString)
		put: result
		ifGeneration: aGeneration.
	^ result!

execute: aSqlString
	"Signals an Error when the database is missing or sqlite3 fails."
	| resolved |
	resolved := self resolvedDbPath.
	resolved exists ifFalse: [
		Error signal: 'Database not found: ' , resolved pathString ].
	^ self parseAsciiOutput: (self runSqlite: aSqlString on: resolved)!

runSqlite: aSqlString on: aResolvedPath
	"Run the query and answer sqlite3's raw stdout.  Separated from
	 execute: so the cache logic, the parse and the subprocess are three
	 things rather than one."
	| process exitCode stdout stderr |
	self class countExecution.
	self class executor ifNotNil: [ :block |
		^ block value: aResolvedPath pathString value: aSqlString ].
	process := GtSubprocessWithInMemoryOutput new
		command: 'sqlite3';
		arguments: {
			'-readonly'. '-header'. '-ascii'.
			aResolvedPath pathString.
			aSqlString };
		runAndWait.
	exitCode := process exitCode.
	stdout := process stdout.
	stderr := process stderr.
	exitCode = 0 ifFalse: [
		Error signal: (stderr ifEmpty: [ 'sqlite3 exited with code ' , exitCode printString ]) ].
	^ stdout!

parseAsciiOutput: aString
	"Parse the -ascii framed output into an McRelation.  The first record
	 is the header row; subsequent records are data rows."
	| unitSep recordSep records columns rows |
	unitSep := Character value: 16r1F.
	recordSep := Character value: 16r1E.
	aString isEmpty ifTrue: [
		^ McRelation columns: #() rows: #()
			directives: McTableDirectives forQuery ].
	records := aString splitOn: recordSep.
	"A trailing record separator leaves one empty element at the end."
	records := records reject: [ :each | each isEmpty ].
	records isEmpty ifTrue: [
		^ McRelation columns: #() rows: #()
			directives: McTableDirectives forQuery ].
	columns := (records first splitOn: unitSep) collect: [ :name |
		McRelationColumn name: name trimBoth alignment: #left ].
	rows := (2 to: records size) collect: [ :index |
		| fields cells |
		fields := (records at: index) splitOn: unitSep.
		cells := (1 to: columns size) collect: [ :col |
			McRelationCell
				source: ((fields at: col ifAbsent: [ '' ]) trimBoth)
				interval: nil ].
		McRelationRow cells: cells columns: columns interval: nil ].
	"Derive alignment: right-align columns where every non-empty cell is numeric."
	columns doWithIndex: [ :col :idx |
		| allNumeric |
		allNumeric := rows allSatisfy: [ :row |
			| cell |
			cell := row atIndex: idx.
			cell source trimBoth isEmpty or: [ cell number notNil ] ].
		allNumeric ifTrue: [ col alignment: #right ] ].
	^ McRelation columns: columns rows: rows
		directives: McTableDirectives forQuery! !
