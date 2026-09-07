"
McBusStatusTest -- the bus status model behind the home-screen lights.

Pure model tests: no bus, no socket, no window.  The client is injected, so
every case here is a shape the real bus can be in -- absent, connected but
alone, connected with a participant answering -- without needing any of them
to actually happen.

The case that matters most is the third state.  A light that only knows UP
and DOWN reports DOWN for a participant it has not asked about yet, and
bin/bus-status exists partly to document that this lie is expensive: GT takes
around fifteen seconds from launch to connected, and a snapshot taken in that
window says DOWN for something that is merely not ready.  So `unknown' is a
value here, and it is the value a fresh model starts at.
"!

Object subclass: #McBusStatusFakeClient
	instanceVariableNames: 'connected answers asked duringRequest'
	classVariableNames: ''
	package: 'MalleableControl'!

"A stand-in for NatsClient carrying only what McBusStatus is allowed to use.
 Keeping it here rather than in the production class is deliberate: a test
 hook on McBusStatus would be a second, untested way for the panel to get its
 answers."!

!McBusStatusFakeClient class methodsFor: 'instance creation'!
connected: aBoolean
	^ self new setConnected: aBoolean! !

!McBusStatusFakeClient methodsFor: 'initialization'!
setConnected: aBoolean
	connected := aBoolean.
	answers := Dictionary new.
	asked := OrderedCollection new! !

!McBusStatusFakeClient methodsFor: 'configuring'!
answer: aSubject with: aString
	answers at: aSubject put: aString!

whileAsking: aBlock
	"Evaluated at the moment a request goes out, which is the only way to
	 observe the model from inside a probe that has not finished."
	duringRequest := aBlock! !

!McBusStatusFakeClient methodsFor: 'accessing'!
asked
	^ asked!

host
	^ '127.0.0.1'!

port
	^ 4223! !

!McBusStatusFakeClient methodsFor: 'nats protocol'!
isConnected
	^ connected!

request: aSubject data: aString timeout: seconds
	"nil is what NatsClient answers on timeout -- that is the whole signal a
	 down participant gives."
	asked add: aSubject.
	duringRequest ifNotNil: [ duringRequest value ].
	^ answers at: aSubject ifAbsent: [ nil ]! !


TestCase subclass: #McBusStatusTest
	instanceVariableNames: 'status'
	classVariableNames: ''
	package: 'MalleableControl'!

!McBusStatusTest methodsFor: 'running'!
setUp
	super setUp.
	status := (Smalltalk at: #McBusStatus) new! !

!McBusStatusTest methodsFor: 'helpers'!
liveClient
	"Connected, and answering for gt only -- the ordinary case where GT is on
	 the bus and Emacs is not."
	| c |
	c := (Smalltalk at: #McBusStatusFakeClient) connected: true.
	c answer: 'gt.query.capabilities' with: '{"v":1,"ok":true,"result":{}}'.
	^ c! !

!McBusStatusTest methodsFor: 'tests-initial state'!
testFreshModelKnowsNothing
	self assert: status busStatus equals: #unknown.
	self assert: (status statusOf: 'gt') equals: #unknown.
	self assert: (status statusOf: 'emacs') equals: #unknown.
	self assert: (status statusOf: 'bb') equals: #unknown!

testFreshModelHasNotBeenChecked
	self assert: status checkedAt isNil!

testUnknownParticipantIsUnknown
	status probeWith: self liveClient.
	self assert: (status statusOf: 'nobody') equals: #unknown! !

!McBusStatusTest methodsFor: 'tests-probing'!
testNoClientIsDownEverywhere
	"No McGtService at all. Every light goes red, and nothing raises -- the
	 home screen must render before the bus does."
	status probeWith: nil.
	self assert: status busStatus equals: #down.
	self assert: (status statusOf: 'gt') equals: #down.
	self assert: (status statusOf: 'emacs') equals: #down.
	self assert: (status statusOf: 'bb') equals: #down!

testDisconnectedClientIsDownEverywhere
	"A client object exists but its socket is gone. It must not be asked
	 anything: a request on a dead socket answers nil after a full timeout
	 each, which would freeze the probe for as many seconds as there are
	 participants."
	| c |
	c := (Smalltalk at: #McBusStatusFakeClient) connected: false.
	status probeWith: c.
	self assert: status busStatus equals: #down.
	self assert: (status statusOf: 'gt') equals: #down.
	self assert: c asked isEmpty!

testConnectedClientMakesTheBusUp
	status probeWith: self liveClient.
	self assert: status busStatus equals: #up!

testAnsweringParticipantIsUp
	status probeWith: self liveClient.
	self assert: (status statusOf: 'gt') equals: #up!

testSilentParticipantIsDown
	status probeWith: self liveClient.
	self assert: (status statusOf: 'emacs') equals: #down!

testProbeAsksEachParticipantForItsCapabilities
	"The subject convention is shared with bin/bus-status, which defines a
	 participant as up exactly when it answers <who>.query.capabilities.
	 Spelling it differently here would make the panel and the CLI disagree
	 about the same bus."
	| c |
	c := self liveClient.
	status probeWith: c.
	self
		assertCollection: c asked asArray
		hasSameElements: #('bb.query.capabilities' 'emacs.query.capabilities' 'gt.query.capabilities')!

testProbeRecordsWhenItRan
	status probeWith: self liveClient.
	self deny: status checkedAt isNil! !

!McBusStatusTest methodsFor: 'tests-participants'!
testParticipantsAreTheOnesBusStatusWalks
	"bin/bus-status walks bb, emacs and gt. A panel that knew about fewer
	 would quietly stop reporting a participant that the CLI still checks --
	 and the whole point of the lights is that you do not have to run the CLI
	 to find out."
	self
		assertCollection: status participants asArray
		hasSameElements: #('bb' 'emacs' 'gt')! !

!McBusStatusTest methodsFor: 'tests-staleness'!
testNeverCheckedIsStale
	"The panel probes on render. Something never asked is always worth
	 asking about."
	self assert: status isStale!

testJustProbedIsNotStale
	"This is what stops a render from looping. A probe refreshes the home
	 screen when it lands, which rebuilds the panel, which would probe
	 again -- forever -- if a just-answered model still read as stale."
	status probeWith: self liveClient.
	self deny: status isStale!

testAnOldAnswerIsStaleAgain
	"Re-rendering the home screen a while later should ask again rather than
	 show whatever was true the last time anyone looked."
	status probeWith: self liveClient.
	status instVarNamed: 'checkedAt' put: DateAndTime now - 1 hour.
	self assert: status isStale! !

!McBusStatusTest methodsFor: 'tests-lights'!
testAProbeInFlightStillShowsTheLastAnswers
	"A probe refreshes the home screen when it lands, and the panel probes
	 again on render, so renders and probes overlap by design. Emptying the
	 answers before asking makes every one of those renders show grey for
	 participants whose state is perfectly well known -- the lights blink out
	 for the second or three the probe takes."
	| c seen |
	status probeWith: self liveClient.
	seen := OrderedCollection new.
	c := (Smalltalk at: #McBusStatusFakeClient) connected: true.
	c answer: 'gt.query.capabilities' with: '{"v":1,"ok":true}'.
	c whileAsking: [ seen add: (status statusOf: 'gt') ].
	status probeWith: c.
	self deny: seen isEmpty.
	self deny: (seen includes: #unknown).
	self assert: (status statusOf: 'gt') equals: #up!

testLightsLeadWithTheBus
	| lights |
	status probeWith: self liveClient.
	lights := status lights.
	self assert: lights size equals: 4.
	self assert: (lights first key beginsWith: 'bus').
	self assert: lights first value equals: #up!

testLightsCarryEachParticipantInOrder
	| lights |
	status probeWith: self liveClient.
	lights := status lights.
	self assert: (lights collect: [ :each | each key ]) asArray
		equals: #('bus 127.0.0.1:4223' 'bb' 'emacs' 'gt').
	self assert: (lights collect: [ :each | each value ]) asArray
		equals: #(#up #down #down #up)!

testBusLightNamesTheServerItAsked
	status probeWith: self liveClient.
	self assert: status busLabel equals: '127.0.0.1:4223'!

testBusLightSaysSoWhenThereIsNoClient
	status probeWith: nil.
	self assert: status busLabel equals: 'not connected'! !

!McBusStatusTest methodsFor: 'tests-singleton'!
testCurrentIsOneSharedModel
	| cls |
	cls := Smalltalk at: #McBusStatus.
	self assert: cls current identicalTo: cls current! !
