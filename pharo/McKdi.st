"
McKdi -- the thin transport layer between Glamorous Toolkit and the kdi CLI.

Loose coupling is the whole point.  GT never opens the evidence SQLite database
and never imports a schema.  It spawns `kdi ... --json' as an ordinary
subprocess, reads stdout, and parses it.  The contract between the two sides is
the public JSON answer and nothing else, so a backend change degrades one row of
one view rather than breaking the explorer.

Four objects live here:

  McKdiBinding    which store, profile, tier, root and config directory a
                  command runs against, and how argv is assembled.
  McKdiAnswer     one command's argv, exit code, duration, raw stdout/stderr and
                  parsed value.  Every domain object keeps the answer it was
                  built from, which is what makes every screen reproducible by
                  pasting a command.
  McKdiTranscript every answer this image has produced, newest first.
  McKdiJob        a command running off the UI process, inspectable while it
                  runs.

Chunk format: load with fileIn.
"!

Object subclass: #McKdiBinding
	instanceVariableNames: 'root store profile tier configDir command'
	classVariableNames: 'Default'
	package: 'MalleableControl'!

Object subclass: #McKdiAnswer
	instanceVariableNames: 'argv exitCode stdout stderr startedAt duration value parseError'
	classVariableNames: ''
	package: 'MalleableControl'!

Object subclass: #McKdiTranscript
	instanceVariableNames: ''
	classVariableNames: 'Entries AccessLock'
	package: 'MalleableControl'!

Object subclass: #McKdiJob
	instanceVariableNames: 'binding argv label state answer startedAt finishedAt'
	classVariableNames: ''
	package: 'MalleableControl'!


!McKdiBinding class methodsFor: 'instance creation'!
root: aRootPath store: aStorePath profile: aProfile tier: aTier configDir: aConfigDir
	^ self new
		setRoot: aRootPath store: aStorePath profile: aProfile tier: aTier
		configDir: aConfigDir!

default
	"The binding the Emacs side last installed, if any."
	^ Default!

default: aBinding
	Default := aBinding.
	^ aBinding! !


!McKdiBinding methodsFor: 'initialization'!
setRoot: aRootPath store: aStorePath profile: aProfile tier: aTier configDir: aConfigDir
	root := aRootPath.
	store := aStorePath.
	profile := aProfile.
	tier := aTier.
	configDir := aConfigDir.
	command := self class defaultCommand.
	^ self! !


!McKdiBinding class methodsFor: 'defaults'!
defaultCommand
	"How to invoke kdi.  GT subprocesses do not inherit a login-shell PATH, so
	 the launcher resolves an absolute uv and passes it in; this is the fallback."
	^ #('uv' 'run' 'kdi')! !


!McKdiBinding methodsFor: 'accessing'!
root
	^ root!

store
	^ store!

profile
	^ profile!

tier
	^ tier!

configDir
	^ configDir!

command
	^ command!

command: anArrayOfStrings
	command := anArrayOfStrings!

storeExists
	^ store notNil and: [ store asFileReference exists ]!

label
	^ (store ifNil: [ 'unbound' ] ifNotNil: [ :s | s asFileReference basename ]),
		' (', (profile ifNil: [ '?' ]), '/', (tier ifNil: [ '?' ]), ')'! !


!McKdiBinding methodsFor: 'commands'!
globalArguments
	"The five options that bind a store.  --store, --profile and --tier are
	 required together; --root makes stored source URIs portable; --config-dir
	 supplies backends/tiers/embeddings/extraction/pipeline."
	| args |
	args := OrderedCollection new.
	root ifNotNil: [ :r | args add: '--root'; add: r ].
	store ifNotNil: [ :s | args add: '--store'; add: s ].
	profile ifNotNil: [ :p | args add: '--profile'; add: p ].
	tier ifNotNil: [ :t | args add: '--tier'; add: t ].
	configDir ifNotNil: [ :c | args add: '--config-dir'; add: c ].
	^ args asArray!

argvFor: anArrayOfStrings
	^ command, self globalArguments, anArrayOfStrings!

run: anArrayOfStrings
	"Run one kdi command and answer an McKdiAnswer.  Never raises: a failure is
	 a fact about the answer, because a UI that dies on a non-zero exit cannot
	 tell you what the backend said.

	 GtExternalProcessBuilder rather than GtSubprocessWithInMemoryOutput: the
	 latter fails with GtExternalProcessFailedToStart in this image, for
	 /bin/echo as readily as for anything else.  The builder also starts a child
	 with a bare PATH and no HOME, which uv and python both need, so the parent
	 environment is inherited explicitly."
	| argv builder out started elapsed answer |
	argv := self argvFor: anArrayOfStrings.
	started := DateAndTime now.
	answer := [
		builder := GtExternalProcessBuilder new
			command: argv first;
			arguments: argv allButFirst;
			workingDirectory: (root ifNil: [ FileSystem workingDirectory pathString ]);
			addAllEnvVariablesFromParentWithoutOverride;
			yourself.
		out := builder output.
		elapsed := DateAndTime now - started.
		McKdiAnswer
			argv: argv
			exitCode: (out status hasCode ifTrue: [ out status code ] ifFalse: [ -1 ])
			stdout: out stdoutStringLossy
			stderr: out stderrStringLossy
			startedAt: started
			duration: elapsed ]
		on: Error
		do: [ :err |
			McKdiAnswer
				argv: argv
				exitCode: -1
				stdout: ''
				stderr: 'GT could not spawn the command: ', err messageText asString
				startedAt: started
				duration: (DateAndTime now - started) ].
	McKdiTranscript record: answer.
	^ answer!

runJson: anArrayOfStrings
	"Run a command with --json appended and answer the McKdiAnswer."
	^ self run: (anArrayOfStrings copyWith: '--json')! !


!McKdiBinding methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiBinding('; nextPutAll: self label; nextPut: $)! !


!McKdiBinding methodsFor: 'views'!
gtBindingFor: aView
	<gtView>
	^ aView columnedList
		title: 'Binding';
		priority: 10;
		items: [ {
			{ 'root'. root }.
			{ 'store'. store }.
			{ 'store exists'. self storeExists printString }.
			{ 'profile'. profile }.
			{ 'tier'. tier }.
			{ 'config-dir'. configDir }.
			{ 'command'. ' ' join: command } } ];
		column: 'option' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtArgvFor: aView
	<gtView>
	^ aView textEditor
		title: 'Global argv';
		priority: 20;
		text: [ ' ' join: (self argvFor: #('<command>')) ]! !


!McKdiAnswer class methodsFor: 'instance creation'!
argv: anArgv exitCode: aCode stdout: anOut stderr: anErr startedAt: aTime duration: aDuration
	^ self new
		setArgv: anArgv exitCode: aCode stdout: anOut stderr: anErr
		startedAt: aTime duration: aDuration! !


!McKdiAnswer methodsFor: 'initialization'!
setArgv: anArgv exitCode: aCode stdout: anOut stderr: anErr startedAt: aTime duration: aDuration
	argv := anArgv.
	exitCode := aCode.
	stdout := anOut ifNil: [ '' ].
	stderr := anErr ifNil: [ '' ].
	startedAt := aTime.
	duration := aDuration.
	self parseValue.
	^ self!

parseValue
	"Parse stdout as JSON.  A command that printed no JSON is not an error here:
	 value stays nil and parseError records why, so the raw text remains the
	 authority."
	value := nil.
	parseError := nil.
	stdout trimBoth isEmpty ifTrue: [ parseError := 'no stdout'. ^ self ].
	[ value := STONJSON fromString: stdout ]
		on: Error
		do: [ :err | parseError := err messageText asString ].
	^ self! !


!McKdiAnswer methodsFor: 'accessing'!
argv
	^ argv!

exitCode
	^ exitCode!

stdout
	^ stdout!

stderr
	^ stderr!

startedAt
	^ startedAt!

duration
	^ duration!

value
	^ value!

parseError
	^ parseError!

isSuccess
	^ exitCode = 0!

hasValue
	^ value notNil!

commandString
	^ ' ' join: argv!

errorMessage
	"What went wrong, in the backend's own words where it said anything."
	self isSuccess ifTrue: [ ^ nil ].
	stderr trimBoth isEmpty ifFalse: [ ^ stderr trimBoth ].
	stdout trimBoth isEmpty ifFalse: [ ^ stdout trimBoth ].
	^ 'exit ', exitCode printString!

failureReport: aHeadline
	"One shape for every `it did not run' view.  The three of them said the same
	 thing three ways, and an answer with no output at all -- a child that never
	 started -- rendered as a blank panel, which is finding 14 again: an empty
	 screen must never be how a failure looks."
	^ String streamContents: [ :o |
		o nextPutAll: aHeadline; cr; cr.
		(stdout trimBoth isEmpty and: [ stderr trimBoth isEmpty ])
			ifTrue: [ o
				nextPutAll: 'The command produced no output at all, which normally means the';
				cr;
				nextPutAll: 'child process never started -- most often an executable that is not';
				cr;
				nextPutAll: 'on the bare PATH GT gives its children.  Check the Binding tab.';
				cr; cr ]
			ifFalse: [ o nextPutAll: self errorMessage; cr; cr ].
		o nextPutAll: 'exit '; print: exitCode; cr; cr.
		o nextPutAll: 'command:  '; nextPutAll: self commandString ]!

valueAt: aKey
	"Read one key of a JSON object answer, tolerating absence.  Every accessor
	 in the explorer goes through something like this: a missing key is a fact
	 about the backend, not a walkback."
	(value isKindOf: Dictionary) ifFalse: [ ^ nil ].
	^ value at: aKey ifAbsent: [ nil ]!

durationDescription
	duration ifNil: [ ^ '--' ].
	^ duration asMilliSeconds printString, ' ms'! !


!McKdiAnswer methodsFor: 'printing'!
printOn: aStream
	aStream
		nextPutAll: 'McKdiAnswer(';
		nextPutAll: (self isSuccess ifTrue: [ 'ok' ] ifFalse: [ 'exit ', exitCode printString ]);
		nextPutAll: ' ';
		nextPutAll: self commandString;
		nextPut: $)! !


!McKdiAnswer methodsFor: 'views'!
gtValueFor: aView
	<gtView>
	value ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Value';
		priority: 10;
		object: [ value ];
		view: #gtItemsFor:!

gtRawFor: aView
	<gtView>
	^ aView textEditor
		title: 'Raw JSON';
		priority: 20;
		text: [ stdout ]!

gtCommandFor: aView
	<gtView>
	^ aView columnedList
		title: 'Command';
		priority: 30;
		items: [ {
			{ 'argv'. self commandString }.
			{ 'exit code'. exitCode printString }.
			{ 'classification'. self isSuccess ifTrue: [ 'success' ] ifFalse: [ 'failed' ] }.
			{ 'started'. startedAt printString }.
			{ 'duration'. self durationDescription }.
			{ 'parse'. parseError ifNil: [ 'json parsed' ] } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | each second asString ]!

gtStderrFor: aView
	<gtView>
	stderr trimBoth isEmpty ifTrue: [ ^ aView empty ].
	^ aView textEditor
		title: 'Stderr';
		priority: 40;
		text: [ stderr ]! !


!McKdiTranscript class methodsFor: 'accessing'!
lock
	^ AccessLock ifNil: [ AccessLock := Mutex new ]!

entries
	^ self lock critical: [ (Entries ifNil: [ Entries := OrderedCollection new ]) asArray ]!

record: anAnswer
	self lock critical: [
		Entries ifNil: [ Entries := OrderedCollection new ].
		Entries addFirst: anAnswer.
		"Bounded: an explorer session runs a lot of read-only commands."
		[ Entries size > 500 ] whileTrue: [ Entries removeLast ] ].
	^ anAnswer!

reset
	self lock critical: [ Entries := OrderedCollection new ]! !


!McKdiJob class methodsFor: 'instance creation'!
binding: aBinding argv: anArgv label: aLabel
	^ self new setBinding: aBinding argv: anArgv label: aLabel! !


!McKdiJob methodsFor: 'initialization'!
setBinding: aBinding argv: anArgv label: aLabel
	binding := aBinding.
	argv := anArgv.
	label := aLabel.
	state := #pending.
	^ self! !


!McKdiJob methodsFor: 'running'!
start
	"Run off the UI process.  GtSubprocessWithInMemoryOutput waits on a
	 Semaphore, which suspends only the waiting Pharo process, so the image
	 stays usable while a long ingestion runs."
	state := #running.
	startedAt := DateAndTime now.
	[ [ answer := binding run: argv ]
		on: Error
		do: [ :err | answer := nil. state := #failed ].
	  finishedAt := DateAndTime now.
	  state = #failed ifFalse: [ state := #done ] ] fork.
	^ self!

isRunning
	^ state = #running!

state
	^ state!

label
	^ label!

answer
	^ answer!

wait
	"Block the calling process until the job settles.  For scripted use, not
	 for the UI process."
	[ self isRunning ] whileTrue: [ (Delay forMilliseconds: 50) wait ].
	^ answer! !


!McKdiJob methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiJob(', label asString, ' ', state asString, ')'! !


!McKdiJob methodsFor: 'views'!
gtStatusFor: aView
	<gtView>
	^ aView columnedList
		title: 'Job';
		priority: 5;
		items: [ {
			{ 'label'. label }.
			{ 'state'. state }.
			{ 'started'. startedAt }.
			{ 'finished'. finishedAt }.
			{ 'argv'. ' ' join: (binding argvFor: argv) } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtAnswerFor: aView
	<gtView>
	answer ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Answer';
		priority: 10;
		object: [ answer ];
		view: #gtValueFor:! !
