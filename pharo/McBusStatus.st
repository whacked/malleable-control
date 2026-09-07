"
McBusStatus -- what the bus looks like from inside GT.

The model behind the home-screen lights.  It holds one status per participant
plus one for the bus itself, and knows how to refresh them by asking.

`Up' means the same thing here as it does in bin/bus-status: a participant is
up exactly when it ANSWERS <who>.query.capabilities.  That is deliberately
stronger than finding a process -- a running Emacs with a wedged client is not
a participant -- and keeping the definition identical is what stops the panel
and the CLI from disagreeing about the same bus.

Three states, not two.  A light that only knows up and down has to call a
participant DOWN before anyone has asked it anything, and GT itself takes
around fifteen seconds from launch to connected: for that whole window the
honest answer is `unknown', which is what a fresh model reports.

The client is a parameter, not a lookup, so every state the bus can be in is
reachable from a test without a socket.  Only `probe' reaches for the live one.

Chunk format: load with fileIn, reach the class with
	(Smalltalk at: #McBusStatus).
"!

Object subclass: #McBusStatus
	instanceVariableNames: 'results busStatus busLabel checkedAt'
	classVariableNames: 'Current'
	package: 'MalleableControl'!

!McBusStatus class methodsFor: 'accessing'!
current
	"One model per image: the panel is rebuilt on every render, so the last
	 probe's answers have to outlive the elements that displayed them."
	^ Current ifNil: [ Current := self new ]!

reset
	Current := nil!

participants
	"Who is expected on this bus, in the order bin/bus-status walks them.
	 Kept identical to that list on purpose: a name here that is not there
	 (or the reverse) makes the panel and the CLI report different buses."
	^ #('bb' 'emacs' 'gt')!

probeTimeout
	"Seconds. Short on purpose: every participant is on loopback, so a reply
	 that has not arrived in a second is not slow, it is absent."
	^ 1!

stalenessSeconds
	"How long an answer is allowed to stand before a render asks again.
	 Long enough that the re-render a probe itself triggers does not probe
	 again, short enough that opening the home screen tells you about the
	 bus as it is now."
	^ 5! !

!McBusStatus methodsFor: 'initialization'!
initialize
	super initialize.
	results := Dictionary new.
	busStatus := #unknown.
	busLabel := 'not checked'.
	checkedAt := nil! !

!McBusStatus methodsFor: 'accessing'!
participants
	^ self class participants!

statusOf: aName
	"#up, #down, or #unknown for anything never probed."
	^ results at: aName ifAbsent: [ #unknown ]!

busStatus
	^ busStatus!

busLabel
	^ busLabel!

checkedAt
	^ checkedAt!

isStale
	"Whether a render should ask again. Never-checked counts as stale."
	checkedAt ifNil: [ ^ true ].
	^ (DateAndTime now - checkedAt) asSeconds > self class stalenessSeconds!

lights
	"The view model: an ordered list of label -> status, bus first. The panel
	 renders this and needs to know nothing else."
	| out |
	out := OrderedCollection new.
	out add: ('bus ' , busLabel) -> busStatus.
	self participants do: [ :each | out add: each -> (self statusOf: each) ].
	^ out! !

!McBusStatus methodsFor: 'probing'!
probeWith: aClient
	"Ask the bus about everyone and record what came back. Synchronous: the
	 caller decides what process to spend."
	| live fresh |
	live := aClient notNil
		and: [ [ aClient isConnected ] on: Error do: [ :e | false ] ].
	"Answers are gathered into a fresh dictionary and swapped in at the end,
	 rather than written into the live one as they arrive.

	 Renders and probes overlap by design -- the panel probes on render, and a
	 probe refreshes the home screen when it lands -- so the model is read
	 while this method is part-way through. Filling it in place means every
	 such render catches it half empty and draws grey lights for participants
	 whose state is perfectly well known, for the second or three the asking
	 takes. Swapping keeps the previous answers on screen until there is a
	 complete set to replace them with."
	fresh := Dictionary new.
	"Nobody is asked anything once the socket is known to be gone. A request
	 on a dead socket answers nil only after its full timeout, so asking would
	 cost one timeout per participant to learn what the bus light already
	 said."
	self participants do: [ :each |
		fresh
			at: each
			put: (live ifTrue: [ self ask: aClient about: each ] ifFalse: [ #down ]) ].
	results := fresh.
	busStatus := live ifTrue: [ #up ] ifFalse: [ #down ].
	busLabel := live
		ifTrue: [ [ aClient host , ':' , aClient port printString ]
			on: Error do: [ :e | 'unknown server' ] ]
		ifFalse: [ 'not connected' ].
	checkedAt := DateAndTime now.
	^ self!

ask: aClient about: aName
	"Answer #up when aName replies to its capabilities query. NatsClient
	 answers nil on timeout, which is the whole signal a down participant
	 gives -- core NATS has no last-will, so a crashed client simply goes
	 quiet."
	| reply |
	reply := [ aClient
		request: aName , '.query.capabilities'
		data: '{"v":1,"args":{}}'
		timeout: self class probeTimeout ]
		on: Error
		do: [ :e | nil ].
	^ (reply notNil and: [ reply isEmpty not ])
		ifTrue: [ #up ]
		ifFalse: [ #down ]! !

!McBusStatus methodsFor: 'probing-live'!
probe
	"Ask the live bus, off whatever process called this, then redraw.

	 Forked without exception: a probe costs one timeout per silent
	 participant, and run on the UI process that is the window frozen for as
	 many seconds. It is started from a render, so that would be a home
	 screen that hangs on the way up."
	[ [ self probeWith: self serviceClient.
		self refreshHome ]
		on: Error
		do: [ :e |  ] ] fork.
	^ self!

probeIfStale
	"What a render calls. Guarded by staleness so that the redraw a probe
	 triggers on completion does not start another one."
	self isStale ifTrue: [ self probe ].
	^ self!

serviceClient
	"GT's own bus client, or nil when there is no service -- which is the
	 ordinary state of a headless image, and of any image whose bus never
	 came up. Nil is a value probeWith: understands."
	| svc |
	svc := Smalltalk at: #McGtService ifAbsent: [ nil ].
	svc ifNil: [ ^ nil ].
	^ [ svc current ifNotNil: [ :each | each client ] ] on: Error do: [ :e | nil ]!

refreshHome
	"McGtPatches walks every open main window and enqueues the re-render.
	 Reached through Smalltalk at: and guarded, because the panel must still
	 work in an image where the patches were not loaded."
	^ [ (Smalltalk at: #McGtPatches ifAbsent: [ nil ])
		ifNotNil: [ :patches | patches refreshHome ] ]
		on: Error
		do: [ :e | nil ]! !

"
McBusStatusSection -- the bus lights on GT's home screen.

A GtHomeSection, like McLauncherSection: a BrStencil whose `create' is the
hook.  It renders McBusStatus current and holds no state of its own, because
a section is rebuilt from scratch on every render -- anything remembered here
would be thrown away with the elements that showed it.

`create' probes, but only if the model is stale.  That guard is load-bearing
rather than an optimisation: a probe refreshes the home screen when it lands,
which rebuilds this section, which would probe again -- forever.

The reading of the lights is deliberately literal.  Green means something
answered just now, red means it did not, grey means nobody has asked yet.
The time of the last answer is on the row for the same reason: core NATS has
no last-will, so a participant that CRASHED goes quiet without a word and its
light stays whatever it was until someone presses Check.  A panel that shows
green with no way to see how old the green is would be lying with confidence.
"!

GtHomeSection subclass: #McBusStatusSection
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McBusStatusSection methodsFor: 'accessing'!
sectionTitle
	^ 'Bus'!

model
	^ McBusStatus current!

colorFor: aStatus
	aStatus = #up ifTrue: [ ^ Color r: 0.16 g: 0.68 b: 0.34 ].
	aStatus = #down ifTrue: [ ^ Color r: 0.84 g: 0.22 b: 0.22 ].
	^ Color veryLightGray! !

!McBusStatusSection methodsFor: 'building'!
create
	| container row |
	self model probeIfStale.
	container := self newSectionContainer.
	container addChild: (self newSectionTitle: self sectionTitle).
	row := self newLightsRow.
	self model lights do: [ :each | row addChild: (self lightFor: each) ].
	row addChild: self checkButton.
	row addChild: self checkedAtLabel.
	container addChild: row.
	^ container!

newLightsRow
	^ BlElement new
		layout: BlLinearLayout horizontal alignCenterLeft;
		padding: (BlInsets top: 4 left: self sectionPaddingLeftInsets bottom: 8 right: 0);
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical fitContent ]!

lightFor: anAssociation
	"anAssociation is label -> status, straight out of McBusStatus lights."
	| holder |
	holder := BlElement new
		layout: BlLinearLayout horizontal alignCenterLeft;
		margin: (BlInsets right: 18);
		constraintsDo: [ :c |
			c horizontal fitContent.
			c vertical fitContent.
			c linear vertical alignCenter ].
	holder addChild: (self dotFor: anAssociation value).
	holder addChild: (self labelFor: anAssociation key).
	^ holder!

dotFor: aStatus
	^ BlElement new
		size: 11 @ 11;
		geometry: BlCircleGeometry new;
		background: (self colorFor: aStatus);
		margin: (BlInsets right: 6);
		constraintsDo: [ :c | c linear vertical alignCenter ]!

labelFor: aString
	^ BrLabel new
		aptitude: (BrGlamorousLabelAptitude new
			foreground: Color darkGray;
			fontSize: 13);
		text: aString;
		constraintsDo: [ :c | c linear vertical alignCenter ]!

checkButton
	"Re-asks now. The only way to notice a participant that crashed rather
	 than stopped, since a crash sends nothing."
	^ (self newSectionButtonWithIcon: BrGlamorousVectorIcons refresh)
		label: 'Check the bus now';
		action: [ :aButton | self model probe ];
		constraintsDo: [ :c | c linear vertical alignCenter ]!

checkedAtLabel
	| text |
	text := self model checkedAt
		ifNil: [ 'not checked yet' ]
		ifNotNil: [ :when |
			[ 'checked ' , when asTime print24 ]
				on: Error
				do: [ :e | 'checked' ] ].
	^ BrLabel new
		aptitude: (BrGlamorousLabelAptitude new
			foreground: Color veryLightGray;
			fontSize: 11);
		text: text;
		margin: (BlInsets left: 4);
		constraintsDo: [ :c | c linear vertical alignCenter ]! !


"GtHome extension. An ADDITION to upstream rather than an override, so it is
 an ordinary method in our own package -- the same arrangement McLauncher uses,
 and for the same reason. <gtHomeSection> is what GtHomeSectionsCollector looks
 for.

 Priority 45 puts the lights directly below the launcher panel, which is 40:
 GtPhlowUtility class >> hasHigherPriority:than: compares with <, so lower
 sorts earlier."!

!GtHome methodsFor: '*MalleableControl'!
mcBusStatusSection
	<gtHomeSection>
	^ McBusStatusSection new priority: 45! !
