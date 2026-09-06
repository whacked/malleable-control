"
McCodeEvalResult, McCodeLanguage and McCodeEvaluator -- running a labeled
expression, once.

Org Babel's semantics, not Quarto's.  For most languages the evaluator is a
one-shot subprocess per unique expression.  For `smalltalk' it is this image,
exactly as #+begin_src emacs-lisp evaluates against the running Emacs -- and
that is not new capability here, since McGtService already answers
gt.cmd.eval with Smalltalk compiler evaluate:.  The editor runs inside GT, so
it reaches the same evaluation without going near the bus.

The scheduling below is McSqliteSource's, deliberately, down to the names.  It
solved this exact problem for database views: a styler runs on every keystroke
and must never wait on a subprocess, so it takes whatever is already known and
draws a placeholder for what is not.  A cold expression answers `pending' and
starts a background job; when the job lands it does not touch the rope -- which
by then may be several keystrokes out of date -- it asks the editor to restyle,
and the restyle finds the result in the cache.  Two spans holding the same
expression coalesce onto one job.

Two things are asymmetric between the two kinds of evaluator, and both are
deliberate:

  1. A subprocess runs on a background process and is capped by `timeout'.
     In-image Smalltalk runs synchronously on the caller, because the point of
     it is to reach this process's state, and it CANNOT be capped -- a
     `{smalltalk} [ true ] whileTrue' freezes the editor.  That is the same
     bargain Org Babel makes with elisp.

  2. An interpreter that is not installed answers a failed result, never a
     raise.  A document naming a language you do not have must render as a
     visible `no interpreter', not as a broken document.

Interpreters are located by searching PATH and then a fixed list of the places
a per-user package manager puts things.  A windowed GT is launched by the
window server and inherits almost no PATH, which is the same reason
McTerminal has to go looking for tmux.

Chunk format: load with fileIn.
"!

Object subclass: #McCodeEvalResult
	instanceVariableNames: 'state output message evaluatedAt'
	classVariableNames: ''
	package: 'MalleableControl'!

!McCodeEvalResult class methodsFor: 'instance creation'!
output: aString at: aDateAndTime
	^ self new setState: #ready output: aString message: nil at: aDateAndTime!

failed: aMessage
	^ self new setState: #failed output: nil message: aMessage at: nil!

pending
	^ self new setState: #pending output: nil message: nil at: nil! !

!McCodeEvalResult methodsFor: 'initialization'!
setState: aSymbol output: aString message: aMessage at: aDateAndTime
	state := aSymbol.
	output := aString.
	message := aMessage.
	evaluatedAt := aDateAndTime! !

!McCodeEvalResult methodsFor: 'accessing'!
state
	^ state!

output
	^ output ifNil: [ '' ]!

message
	^ message ifNil: [ '' ]!

evaluatedAt
	^ evaluatedAt!

isReady
	^ state = #ready!

isFailed
	^ state = #failed!

isPending
	^ state = #pending!

displayString
	"What the reader sees in place of the expression."
	self isReady ifTrue: [ ^ self output ].
	self isFailed ifTrue: [ ^ self message ].
	^ 'evaluating...'! !

!McCodeEvalResult methodsFor: 'printing'!
printOn: aStream
	aStream
		nextPutAll: self class name;
		nextPut: $(;
		nextPutAll: state;
		nextPutAll: ' ';
		print: (self isFailed ifTrue: [ self message ] ifFalse: [ self output ]);
		nextPut: $)! !

Object subclass: #McCodeLanguage
	instanceVariableNames: 'name kind command argumentsBlock note'
	classVariableNames: ''
	package: 'MalleableControl'!

!McCodeLanguage class methodsFor: 'instance creation'!
name: aName command: aCommand arguments: aBlock
	"A language evaluated by a one-shot subprocess.  aBlock takes the
	 expression and answers the argument array."
	^ self new setName: aName kind: #subprocess command: aCommand arguments: aBlock note: nil!

inImageNamed: aName
	"A language evaluated by this image, on the calling process."
	^ self new setName: aName kind: #inImage command: nil arguments: nil note: nil!

name: aName unsupported: aNote
	"A language this phase parses and tags but cannot run."
	^ self new setName: aName kind: #none command: nil arguments: nil note: aNote! !

!McCodeLanguage methodsFor: 'initialization'!
setName: aName kind: aKind command: aCommand arguments: aBlock note: aNote
	name := aName.
	kind := aKind.
	command := aCommand.
	argumentsBlock := aBlock.
	note := aNote! !

!McCodeLanguage methodsFor: 'accessing'!
name
	^ name!

kind
	^ kind!

command
	^ command!

note
	^ note!

isSubprocess
	^ kind = #subprocess!

isInImage
	^ kind = #inImage!

isSupported
	^ kind ~= #none!

argumentsFor: anExpression
	^ argumentsBlock
		ifNil: [ #() ]
		ifNotNil: [ :block | block value: anExpression ]! !

Object subclass: #McCodeEvaluator
	instanceVariableNames: ''
	classVariableNames: 'Languages ResultCache PendingJobs AccessLock CacheGeneration JobRunner Executor ExecutionCount CacheLimit TimeoutSeconds'
	package: 'MalleableControl'!

!McCodeEvaluator class methodsFor: 'languages'!
languages
	^ Languages ifNil: [ Languages := self defaultLanguages ]!

defaultLanguages
	"The registry.  A label names a LANGUAGE, never an execution context:
	 that is what lets a highlighter use the same label later, and what lets
	 a subprocess language gain a session evaluator one day without anything
	 in a user's document having to be renamed."
	| all |
	all := Dictionary new.
	all at: 'python' put: (McCodeLanguage
		name: 'python' command: 'python3' arguments: [ :e | { '-c'. self pythonProgramFor: e } ]).
	all at: 'r' put: (McCodeLanguage
		name: 'r' command: 'Rscript' arguments: [ :e | { '-e'. 'cat(format(', e, '))' } ]).
	all at: 'julia' put: (McCodeLanguage
		name: 'julia' command: 'julia' arguments: [ :e | { '-e'. 'print(', e, ')' } ]).
	all at: 'smalltalk' put: (McCodeLanguage inImageNamed: 'smalltalk').
	all at: 'ojs' put: (McCodeLanguage
		name: 'ojs'
		unsupported: 'ojs is a browser dataflow runtime; there is no interpreter to run it here').
	^ all!

aliases
	"gt reads naturally in this image and costs nothing to accept, but the
	 language is Smalltalk and that is what the tag says."
	^ Dictionary new
		at: 'gt' put: 'smalltalk';
		at: 'python3' put: 'python';
		at: 'rscript' put: 'r';
		yourself!

languageNamed: aString
	"The evaluator for aString, or nil when nothing is registered for it."
	| key |
	aString ifNil: [ ^ nil ].
	key := aString asLowercase trimBoth.
	key := self aliases at: key ifAbsent: [ key ].
	^ self languages at: key ifAbsent: [ nil ]!

register: aLanguage
	self languages at: aLanguage name put: aLanguage!

resetLanguages
	Languages := nil!

pythonProgramFor: anExpression
	"Python's -c takes statements, not an expression, so the expression is
	 wrapped in a print.  repr is not used: the reader wants 12.0, not
	 '12.0' with quotes around it."
	^ 'import sys' , (String with: Character lf)
		, 'sys.stdout.write(str(' , anExpression , '))'! !

!McCodeEvaluator class methodsFor: 'configuration'!
cacheLimit
	"How many results are kept.  Bounded because a styler runs on every
	 keystroke; 64 is McBoundedCache's own default and the size every other
	 cache here uses."
	^ CacheLimit ifNil: [ 64 ]!

cacheLimit: anInteger
	CacheLimit := anInteger max: 1.
	ResultCache := nil!

timeoutSeconds
	^ TimeoutSeconds ifNil: [ 10 ]!

timeoutSeconds: anInteger
	TimeoutSeconds := anInteger max: 1! !

!McCodeEvaluator class methodsFor: 'cache'!
resultCache
	"Guarded lookup, like McSqliteSource's: a partial load must still be able
	 to render markdown when McCache has not been filed in yet."
	| cacheClass |
	ResultCache ifNotNil: [ ^ ResultCache ].
	cacheClass := Smalltalk at: #McBoundedCache ifAbsent: [ nil ].
	^ ResultCache := cacheClass
		ifNil: [ Dictionary new ]
		ifNotNil: [ cacheClass limit: self cacheLimit ]!

accessLock
	"One lock over the result cache and the pending-job table, because a
	 background process writes both and the UI process reads both."
	^ AccessLock ifNil: [ AccessLock := Mutex new ]!

cachedAt: aKey
	^ self accessLock critical: [ self resultCache at: aKey ifAbsent: [ nil ] ]!

cacheAt: aKey put: aResult
	^ self accessLock critical: [ self resultCache at: aKey put: aResult ]!

cacheAt: aKey put: aResult ifGeneration: aGeneration
	^ self accessLock critical: [
		self cacheGeneration = aGeneration
			ifTrue: [ self resultCache at: aKey put: aResult ]
			ifFalse: [ aResult ] ]!

cacheGeneration
	^ CacheGeneration ifNil: [ CacheGeneration := 0 ]!

forgetKey: aKey
	"Drop one entry so the next lookup re-runs it.  This is what the re-run
	 keystroke does: results are never invalidated on their own, because a
	 smalltalk expression reads live image state and a subprocess may read a
	 file that has since changed."
	^ self accessLock critical: [
		self resultCache removeKey: aKey ifAbsent: [ nil ] ]!

clearCache
	"Drop every result and invalidate every job in flight.  Listeners of
	 abandoned jobs are notified after the lock is released, so a caller
	 showing a placeholder gets a chance to ask for a restyle."
	| abandoned pending |
	abandoned := self accessLock critical: [
		| listeners |
		listeners := PendingJobs
			ifNil: [ #() ]
			ifNotNil: [ PendingJobs values asArray ].
		ResultCache := nil.
		PendingJobs := nil.
		CacheGeneration := self cacheGeneration + 1.
		listeners ].
	pending := McCodeEvalResult pending.
	abandoned do: [ :listeners |
		listeners valuesDo: [ :each |
			[ each value: pending ] on: Error do: [ :e | nil ] ] ]! !

!McCodeEvaluator class methodsFor: 'pending jobs'!
pendingJobs
	"cacheKey -> IdentityDictionary of token -> completion block.  One block
	 per token, so restyling ten times while an expression runs still
	 schedules one job and still delivers one callback."
	^ PendingJobs ifNil: [ PendingJobs := Dictionary new ]!

isPendingFor: aKey
	^ self accessLock critical: [ self pendingJobs includesKey: aKey ]!

schedule: aCode token: aTokenOrNil onComplete: aBlockOrNil
	"Start a background job for aCode unless one is already running, and
	 register the caller's block against it either way.

	 Claiming the key and registering the block are one critical section:
	 two processes both finding nothing pending would both start a
	 subprocess for the same expression.  Starting the job is outside it,
	 because a job runner that runs the job in hand -- a test -- would
	 otherwise do the whole evaluation while the lock was held."
	| key started listeners generation |
	key := aCode cacheKey.
	started := self accessLock critical: [
		listeners := self pendingJobs at: key ifAbsent: [ nil ].
		listeners
			ifNotNil: [
				self register: aBlockOrNil for: aTokenOrNil in: listeners.
				false ]
			ifNil: [
				listeners := IdentityDictionary new.
				self register: aBlockOrNil for: aTokenOrNil in: listeners.
				self pendingJobs at: key put: listeners.
				generation := self cacheGeneration.
				true ] ].
	started ifFalse: [ ^ self ].
	self runJob: [
		[ | result |
		  result := self runAndCache: aCode ifGeneration: generation.
		  self finish: key listeners: listeners generation: generation with: result ]
			ensure: [
				self abandon: key listeners: listeners generation: generation ] ]!

register: aBlockOrNil for: aTokenOrNil in: aDictionary
	(aTokenOrNil isNil or: [ aBlockOrNil isNil ]) ifTrue: [ ^ self ].
	aDictionary at: aTokenOrNil put: aBlockOrNil!

finish: aKey listeners: expectedListeners generation: aGeneration with: aResult
	"Notify only the listeners of this exact job generation.  One failing
	 listener must not cost the others their callback."
	| listenersToNotify |
	listenersToNotify := self accessLock critical: [
		| current |
		current := self pendingJobs at: aKey ifAbsent: [ nil ].
		(self cacheGeneration = aGeneration and: [ current == expectedListeners ])
			ifTrue: [ self pendingJobs removeKey: aKey. expectedListeners ]
			ifFalse: [ nil ] ].
	listenersToNotify ifNil: [ ^ self ].
	listenersToNotify valuesDo: [ :each |
		[ each value: aResult ] on: Error do: [ :e | nil ] ]!

abandon: aKey listeners: expectedListeners generation: aGeneration
	self accessLock critical: [
		| current |
		current := self pendingJobs at: aKey ifAbsent: [ nil ].
		(self cacheGeneration = aGeneration and: [ current == expectedListeners ])
			ifTrue: [ self pendingJobs removeKey: aKey ] ]! !

!McCodeEvaluator class methodsFor: 'jobs'!
jobRunner
	"How a background job is started, or nil for the real one.  A test sets
	 this to keep the job in hand, which is what makes `the styler did not
	 evaluate anything' an assertion rather than a race."
	^ JobRunner!

jobRunner: aBlockOrNil
	JobRunner := aBlockOrNil!

runJob: aBlock
	"userBackgroundPriority, below the UI process: the job runs in the gaps
	 and the subprocess it waits on suspends only this process."
	self jobRunner
		ifNil: [ aBlock forkAt: Processor userBackgroundPriority ]
		ifNotNil: [ :runner | runner value: aBlock ]! !

!McCodeEvaluator class methodsFor: 'evaluating'!
resultFor: aCode
	"The result for aCode, evaluating on this process if the cache cannot
	 answer.  Never answers pending.  For callers with nowhere to put a
	 callback: a headless render, a test, an inspector."
	^ (self cachedAt: aCode cacheKey) ifNil: [ self runAndCache: aCode ]!

resultFor: aCode token: aTokenOrNil onComplete: aBlockOrNil
	"What is known about aCode right now, without ever running a subprocess
	 on the calling process.

	 In-image Smalltalk is the exception and is evaluated here and now: the
	 whole point of it is to reach this process's state, and a background
	 process would be a surprising place to do that."
	| cached language |
	cached := self cachedAt: aCode cacheKey.
	cached ifNotNil: [ ^ cached ].
	language := self languageNamed: aCode language.
	(language notNil and: [ language isInImage ])
		ifTrue: [ ^ self runAndCache: aCode ].
	self schedule: aCode token: aTokenOrNil onComplete: aBlockOrNil.
	"A job runner that runs the job in hand -- a test -- has finished it by
	 now, so look once more before settling for pending."
	^ (self cachedAt: aCode cacheKey) ifNil: [ McCodeEvalResult pending ]!

runAndCache: aCode
	^ self runAndCache: aCode ifGeneration: self cacheGeneration!

runAndCache: aCode ifGeneration: aGeneration
	"Evaluate and cache whatever came of it, success or failure.  A failure
	 is cached too: an expression naming a language you do not have must not
	 re-run on every keystroke to keep answering the same thing."
	| result |
	result := [ self evaluate: aCode ]
		on: Error
		do: [ :e | McCodeEvalResult failed: (self messageOf: e) ].
	self cacheAt: aCode cacheKey put: result ifGeneration: aGeneration.
	^ result!

evaluate: aCode
	"Run aCode and answer a result.  Raises only for genuinely unexpected
	 failures; everything a user can cause answers a failed result."
	| language |
	language := self languageNamed: aCode language.
	language ifNil: [
		^ McCodeEvalResult failed: 'no evaluator for ' , aCode language ].
	language isSupported ifFalse: [
		^ McCodeEvalResult failed: language note ].
	language isInImage ifTrue: [
		^ self evaluateInImage: aCode ].
	^ self evaluateSubprocess: aCode language: language!

evaluateInImage: aCode
	"Smalltalk, in this image, on this process -- the org-babel emacs-lisp
	 case.  A compile or a doit failure is the user's mistake and answers a
	 failed result, so a typo in a document does not open a debugger."
	| value |
	[ value := Smalltalk compiler evaluate: aCode canonicalExpression ]
		on: Error
		do: [ :e | ^ McCodeEvalResult failed: (self messageOf: e) ].
	self countExecution.
	"displayString, not printString: the Python evaluator uses str() rather
	 than repr(), and a result rendered into prose should read the same way in
	 either language -- Pharo12.0.0SNAPSHOT, not 'Pharo12.0.0SNAPSHOT'."
	^ McCodeEvalResult
		output: ([ value displayString ] on: Error do: [ :e | value class name ])
		at: DateAndTime now!

evaluateSubprocess: aCode language: aLanguage
	| stdout |
	stdout := self runSubprocessFor: aLanguage expression: aCode canonicalExpression.
	^ McCodeEvalResult output: (self trimTrailingNewlineFrom: stdout) at: DateAndTime now!

runSubprocessFor: aLanguage expression: anExpression
	"One process, one expression.  Answers raw stdout and signals an Error
	 with what went wrong otherwise, which runAndCache: turns into a failed
	 result."
	| resolved process exitCode stdout stderr arguments timeoutPath |
	self countExecution.
	self executor ifNotNil: [ :block |
		^ block value: aLanguage name value: anExpression ].
	resolved := self pathFor: aLanguage command.
	resolved ifNil: [
		^ Error signal: 'no interpreter for ' , aLanguage name
			, ' (' , aLanguage command , ' is not on PATH)' ].
	arguments := aLanguage argumentsFor: anExpression.
	timeoutPath := self pathFor: 'timeout'.
	process := GtSubprocessWithInMemoryOutput new.
	timeoutPath
		ifNil: [
			process command: resolved; arguments: arguments ]
		ifNotNil: [ :t |
			process
				command: t;
				arguments: { self timeoutSeconds printString. resolved } , arguments ].
	process runAndWait.
	exitCode := process exitCode.
	stdout := process stdout.
	stderr := process stderr.
	exitCode = 124 ifTrue: [
		^ Error signal: aLanguage name , ' timed out after '
			, self timeoutSeconds printString , 's' ].
	exitCode = 0 ifFalse: [
		| detail |
		detail := self firstLineOf: stderr.
		^ Error signal: (detail isEmpty
			ifTrue: [ aLanguage name , ' exited with code ' , exitCode printString ]
			ifFalse: [ detail ]) ].
	^ stdout!

messageOf: anError
	^ (anError messageText ifNil: [ anError class name ]) asString! !

!McCodeEvaluator class methodsFor: 'private'!
pathFor: aCommand
	"The absolute path of aCommand, or nil.

	 PATH first, then the places a per-user package manager puts things.  A
	 windowed GT is started by the window server and inherits almost no
	 PATH, which is exactly why McTerminal has to go looking for tmux."
	| env pathValue candidates |
	aCommand ifNil: [ ^ nil ].
	candidates := OrderedCollection new.
	env := [ Smalltalk os environment ] on: Error do: [ :e | nil ].
	pathValue := env ifNil: [ nil ] ifNotNil: [ env at: 'PATH' ifAbsent: [ nil ] ].
	pathValue ifNotNil: [
		(pathValue substrings: ':') do: [ :dir |
			dir isEmpty ifFalse: [ candidates add: dir , '/' , aCommand ] ] ].
	candidates add: (FileLocator home / '.nix-profile' / 'bin' / aCommand) fullName.
	#( '/opt/homebrew/bin' '/usr/local/bin' '/usr/bin' '/bin' )
		do: [ :dir | candidates add: dir , '/' , aCommand ].
	candidates do: [ :each |
		([ each asFileReference exists ] on: Error do: [ :e | false ])
			ifTrue: [ ^ each ] ].
	^ nil!

trimTrailingNewlineFrom: aString
	"Interpreters end their output with a newline; a rendered result is one
	 run of text on a line of prose, so the trailing break goes.  Interior
	 breaks are kept -- a multi-line result is a multi-line result."
	| s |
	s := aString ifNil: [ ^ '' ].
	[ s notEmpty and: [ #(10 13) includes: s last asInteger ] ]
		whileTrue: [ s := s allButLast ].
	^ s!

firstLineOf: aString
	"An interpreter's traceback is many lines and the last is the one that
	 says what went wrong, so the message is built from the end."
	| lines |
	aString ifNil: [ ^ '' ].
	lines := (aString lines collect: [ :each | each trimBoth ])
		reject: [ :each | each isEmpty ].
	lines isEmpty ifTrue: [ ^ '' ].
	^ lines last! !

!McCodeEvaluator class methodsFor: 'testing support'!
executor
	"A two-argument block of language name and expression answering raw
	 stdout, or nil to really run an interpreter.  Exists so the caching and
	 scheduling above can be tested without a subprocess."
	^ Executor!

executor: aBlockOrNil
	Executor := aBlockOrNil!

executionCount
	"How many times an interpreter has actually been invoked.  The cache is
	 only worth having if this stops going up, and that is testable."
	^ ExecutionCount ifNil: [ 0 ]!

countExecution
	ExecutionCount := self executionCount + 1!

resetStatistics
	ExecutionCount := 0.
	(self resultCache respondsTo: #resetStatistics) ifTrue: [
		self resultCache resetStatistics ]!

reset
	"Everything back to how a fresh image has it.  A test that changes the
	 registry, the executor or the job runner must undo all of it."
	Languages := nil.
	ResultCache := nil.
	PendingJobs := nil.
	CacheGeneration := nil.
	JobRunner := nil.
	Executor := nil.
	ExecutionCount := 0.
	CacheLimit := nil.
	TimeoutSeconds := nil! !
