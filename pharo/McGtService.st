"
Glamorous Toolkit participant on the NATS process bus.
Part of malleable-control. See docs/nats_local_process_bus_design.md.

Maps gt.* subjects onto GT operations and publishes gt.event.*. This is the
semantics half of the GT participant; NatsClient is the wire half and knows
nothing of what lives here.

Envelopes (parent design sections 7 and 10):
	request   {'v':1,'args':{...}}
	reply ok  {'v':1,'ok':true,'result':{...}}
	reply err {'v':1,'ok':false,'error':{'code':...,'message':...}}
	event     {'v':1,'source':'gt','ts':<unix-ms>,'data':{...}}

DISPLAY AGNOSTIC. Everything here runs identically in the windowed image and
under GlamorousToolkit-cli with --no-quit. The single concession to headless
operation is gt.cmd.inspect, which skips opening an inspector and reports
headless:true in the same result shape.

Chunk format: load with fileIn, reach the class with (Smalltalk at: #McGtService).
"!

Object subclass: #McGtService
	instanceVariableNames: 'client host port startedAt'
	classVariableNames: 'Current StartMutex'
	package: 'MalleableControl'!

!McGtService class methodsFor: 'accessing'!
current
	^ Current!

isRunning
	^ Current notNil and: [ Current client notNil and: [ Current client isConnected ] ]! !

!McGtService class methodsFor: 'lifecycle'!
start
	"Resolve the bus address from, in order: the McNatsHost / McNatsPort globals
	 (set by the generated startup script, which has no environment to read),
	 then MC_NATS_HOST / MC_NATS_PORT (set by bin/gt-participant), then the
	 project defaults."
	| env h p |
	env := [ Smalltalk os environment ] on: Error do: [ :e | nil ].
	h := Smalltalk at: #McNatsHost ifAbsent: [ nil ].
	h ifNil: [ h := env ifNil: [ nil ] ifNotNil: [ env at: 'MC_NATS_HOST' ifAbsent: [ nil ] ] ].
	h ifNil: [ h := '127.0.0.1' ].
	p := Smalltalk at: #McNatsPort ifAbsent: [ nil ].
	p ifNil: [ p := env ifNil: [ nil ] ifNotNil: [ (env at: 'MC_NATS_PORT' ifAbsent: [ nil ]) ] ].
	p ifNil: [ p := 4223 ].
	^ self startOn: h port: p asInteger!

startOn: aHost port: aPort
	"Serialised: the installed startup script forks its own start, so a second
	 start racing it could leave two live services both answering gt.* -- every
	 request would then get two replies."
	StartMutex ifNil: [ StartMutex := Mutex new ].
	^ StartMutex critical: [
		Current ifNotNil: [ Current stop ].
		Current := self new setHost: aHost port: aPort.
		Current connect.
		Current ]!

stop
	Current ifNotNil: [ Current stop. Current := nil ]! !

!McGtService methodsFor: 'initialization'!
setHost: aHost port: aPort
	host := aHost.
	port := aPort.
	startedAt := DateAndTime now! !

!McGtService methodsFor: 'accessing'!
client
	^ client! !

!McGtService methodsFor: 'lifecycle'!
connect
	| natsClass |
	natsClass := Smalltalk at: #NatsClient.
	client := natsClass on: host port: port name: 'gt'.
	"Handlers are registered ONCE, here -- not in the onConnect hook. The client
	 restores its own subscriptions after a reconnect, so registering there
	 would add a second subscription per subject and GT would answer every
	 request twice. onConnect only announces arrival."
	client onConnect: [ :c | self announceConnected ].
	self registerHandlersOn: client.
	client connect.
	^ client waitForConnectionFor: 5!

stop
	"Core NATS has no last-will, so this graceful notice is the only
	 system.event.client.disconnected anyone will ever see -- a crashed image
	 just goes quiet. See the spec's known gap on presence."
	client ifNil: [ ^ self ].
	[ self publishEvent: 'system.event.client.disconnected'
		data: (self dictWith: 'client' -> 'gt') ] on: Error do: [ :e | ].
	(Delay forMilliseconds: 100) wait.
	client disconnect.
	client := nil!

registerHandlersOn: c
	c subscribe: 'gt.query.capabilities' do: [ :s :p :r | self serve: r with: [ self handleCapabilities: (self argsFrom: p) ] ].
	c subscribe: 'gt.query.image.info'   do: [ :s :p :r | self serve: r with: [ self handleImageInfo: (self argsFrom: p) ] ].
	c subscribe: 'gt.cmd.inspect'        do: [ :s :p :r | self serve: r with: [ self handleInspect: (self argsFrom: p) ] ].
	c subscribe: 'gt.cmd.eval'           do: [ :s :p :r | self serve: r with: [ self handleEval: (self argsFrom: p) ] ].
	"The GT-to-Emacs edge of the mesh: GT reacts to an Emacs event by asking
	 Emacs a question of its own."
	c subscribe: 'emacs.event.buffer.opened' do: [ :s :p :r | self onEmacsBufferOpened: p ]!

announceConnected
	"Safe to run on every (re)connect."
	self publishEvent: 'system.event.client.connected'
		data: (self dictWith: 'client' -> 'gt').
	Transcript show: '[mc-gt] connected to ' , host , ':' , port printString; cr! !

!McGtService methodsFor: 'private-envelope'!
dictWith: anAssociation
	| d |
	d := OrderedDictionary new.
	d at: anAssociation key put: anAssociation value.
	^ d!

dictFrom: assocs
	| d |
	d := OrderedDictionary new.
	assocs do: [ :a | d at: a key put: a value ].
	^ d!

argsFrom: payload
	"Answer the args dictionary of a request. Junk in yields an empty
	 dictionary, so a malformed sender gets a clean error rather than silence."
	^ [ (NeoJSONReader fromString: payload) at: 'args' ifAbsent: [ Dictionary new ] ]
		on: Error do: [ :e | Dictionary new ]!

okResult: aDict
	^ NeoJSONWriter toString:
		(self dictFrom: { 'v' -> 1. 'ok' -> true. 'result' -> aDict })!

errorCode: aCode message: aMessage
	^ NeoJSONWriter toString:
		(self dictFrom: {
			'v' -> 1.
			'ok' -> false.
			'error' -> (self dictFrom: { 'code' -> aCode. 'message' -> aMessage }) })!

eventPayload: aDict
	^ NeoJSONWriter toString:
		(self dictFrom: {
			'v' -> 1.
			'source' -> 'gt'.
			'ts' -> (DateAndTime now asUnixTime * 1000).
			'data' -> aDict })!

requestPayload: aDict
	^ NeoJSONWriter toString: (self dictFrom: { 'v' -> 1. 'args' -> aDict })!

publishEvent: aSubject data: aDict
	client ifNotNil: [ client publish: aSubject data: (self eventPayload: aDict) ]!

serve: replyTo with: aBlock
	"Run a handler and answer its result, converting any error into a failure
	 reply rather than letting it escape into the read loop."
	| response |
	response := [ self okResult: aBlock value ]
		on: Error
		do: [ :e | self errorCode: 'handler-error'
				message: (e messageText ifNil: [ e class name asString ]) ].
	client reply: replyTo with: response! !

!McGtService methodsFor: 'private-handlers'!
handleCapabilities: args
	^ self dictFrom: {
		'commands' -> #('gt.cmd.inspect' 'gt.cmd.eval') asOrderedCollection.
		'queries' -> #('gt.query.capabilities' 'gt.query.image.info') asOrderedCollection.
		'events' -> #('gt.event.inspector.opened') asOrderedCollection.
		'headless' -> self isHeadless }!

handleImageInfo: args
	^ self dictFrom: {
		'version' -> ([ Smalltalk version ] on: Error do: [ :e | 'unknown' ]).
		'imagePath' -> ([ Smalltalk imagePath ] on: Error do: [ :e | 'unknown' ]).
		'headless' -> self isHeadless.
		'uptimeSeconds' -> (DateAndTime now - startedAt) asSeconds }!

handleInspect: args
	"The display-agnostic case. With a UI this opens a GT inspector; headless it
	 returns the same result shape with headless:true and opens nothing."
	| expr value headless opened problem data |
	expr := args at: 'expression' ifAbsent: [ nil ].
	expr ifNil: [ self error: 'Missing required argument: expression' ].
	value := Smalltalk compiler evaluate: expr.
	headless := self isHeadless.
	opened := false.
	problem := nil.
	"Report whether the inspector actually opened. Swallowing the error here
	 would let this answer ok:true with headless:false while nothing appeared
	 on screen -- a success message for something that did not happen."
	headless ifFalse: [
		[ value inspect. opened := true ]
			on: Error
			do: [ :e | problem := e messageText printString ] ].
	data := self dictFrom: {
		'expression' -> expr.
		'class' -> value class name asString.
		'printString' -> value printString.
		'headless' -> headless.
		'inspectorOpened' -> opened.
		'inspectorError' -> (problem ifNil: [ '' ]) }.
	self publishEvent: 'gt.event.inspector.opened' data: data.
	^ data!

handleEval: args
	"Escape hatch (parent design section 12). Present for bootstrapping and
	 debugging; semantic subjects are the protocol."
	| expr value |
	expr := args at: 'expression' ifAbsent: [ nil ].
	expr ifNil: [ self error: 'Missing required argument: expression' ].
	value := Smalltalk compiler evaluate: expr.
	^ self dictFrom: {
		'value' -> value printString.
		'class' -> value class name asString }!

onEmacsBufferOpened: payload
	"React to an Emacs event by querying Emacs back, then announcing what we
	 made of it. This is the middle of the parent design's section 23 flow."
	| event data path reply parsed text |
	event := [ NeoJSONReader fromString: payload ] on: Error do: [ :e | ^ self ].
	data := event at: 'data' ifAbsent: [ Dictionary new ].
	path := data at: 'path' ifAbsent: [ 'unknown' ].
	reply := client
		request: 'emacs.query.buffer.contents'
		data: (self requestPayload: (self dictWith: 'buffer' -> (data at: 'name' ifAbsent: [ nil ])))
		timeout: 5.
	reply ifNil: [
		Transcript show: '[mc-gt] emacs did not answer buffer.contents'; cr.
		^ self ].
	parsed := [ NeoJSONReader fromString: reply ] on: Error do: [ :e | ^ self ].
	(parsed at: 'ok' ifAbsent: [ false ]) ifFalse: [ ^ self ].
	text := (parsed at: 'result') at: 'text' ifAbsent: [ '' ].
	self publishEvent: 'gt.event.inspector.opened'
		data: (self dictFrom: {
			'trigger' -> 'emacs.event.buffer.opened'.
			'path' -> path.
			'characters' -> text size.
			'lines' -> (text lines size).
			'firstLine' -> (text lines isEmpty ifTrue: [ '' ] ifFalse: [ text lines first ]).
			'headless' -> self isHeadless })! !

!McGtService methodsFor: 'private-support'!
hasDisplay
	"Whether this image can actually show something to a person.

	 Smalltalk isHeadless is NOT the right question for GT. GT always runs the
	 VM headless and draws through Bloc, so isHeadless answers true even in a
	 fully windowed image -- using it means gt.cmd.inspect never opens an
	 inspector on the desktop, which is precisely backwards. The real question
	 is whether any Bloc universe has an open space."
	| universeClass |
	universeClass := Smalltalk at: #BlParallelUniverse ifAbsent: [ nil ].
	universeClass ifNil: [ ^ false ].
	^ [ universeClass allInstances anySatisfy: [ :each |
			[ each spaces isNotEmpty ] on: Error do: [ :e | false ] ] ]
		on: Error
		do: [ :e | false ]!

isHeadless
	^ self hasDisplay not! !
