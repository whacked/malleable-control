"
McKdiInfer -- the evidence packet, the step between a selection and a report.

    revision -> passage -> context block -> selection -> PROMPT PACKET -> report

`kdi infer plan' answers the packet a report would be drafted over: every item
it holds, every candidate it REFUSED and why, the source distribution, the
overlap suppression, the tier and the token budget -- before anything could be
sent to a model.

Two things make it worth a screen of its own.  It writes nothing when asked not
to (`--no-cache'), and it takes exactly one subject: a topic, a bundle, or a
materialized slice.  A recipe is not a subject, so the write-free slice loop
cannot reach a packet without first materializing something -- except through a
bundle, which the explorer is already holding.  That is why the packet is
reachable from McKdiBundle: it is the one crossing into this layer that costs
nothing.

The exclusions table is the point.  A packet that quietly dropped a bundle is a
report with a hole in it, and `reason' plus `detail' name the rule that dropped
it.

Chunk format: load with fileIn.
"!

McKdiObject subclass: #McKdiPacket
	instanceVariableNames: 'store subjectKind subjectId'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiPacketItem
	instanceVariableNames: 'packet'
	classVariableNames: ''
	package: 'MalleableControl'!


!McKdiPacket class methodsFor: 'instance creation'!
store: aStore subjectKind: aKind subjectId: anId
	"Plan a packet.  --no-cache, so this reaches the inference layer and writes
	 nothing at all -- not even the run cache."
	| a argv |
	argv := OrderedCollection new.
	argv add: 'infer'; add: 'plan'.
	argv add: (aKind = 'bundle'
		ifTrue: [ '--bundle' ]
		ifFalse: [ aKind = 'topic' ifTrue: [ '--topic' ] ifFalse: [ '--evidence-set' ] ]).
	argv add: anId.
	argv add: '--no-cache'.
	a := aStore binding runJson: argv asArray.
	a hasValue ifFalse: [ ^ a ].
	^ (self json: a value answer: a)
		setStore: aStore kind: aKind id: anId! !


!McKdiPacket methodsFor: 'initialization'!
setStore: aStore kind: aKind id: anId
	store := aStore.
	subjectKind := aKind.
	subjectId := anId.
	^ self! !


!McKdiPacket methodsFor: 'accessing'!
store
	^ store!

binding
	^ store binding!

packetId
	^ self at: 'packet_id'!

tier
	^ self at: 'tier'!

items
	^ ((self at: 'items') ifNil: [ #() ])
		collect: [ :each | (McKdiPacketItem json: each answer: answer) setPacket: self ]!

exclusions
	^ (self at: 'exclusions') ifNil: [ #() ]!

coverage
	^ (self at: 'coverage') ifNil: [ Dictionary new ]!

coverageAt: aKey
	^ self coverage at: aKey ifAbsent: [ nil ]!

limitations
	^ (self at: 'limitations') ifNil: [ #() ]!

bundleIds
	"Distinct, in packet order.  Landing on the bundle keeps the packet item and
	 the bundle as two separate addresses rather than forwarding past one."
	| seen out |
	seen := Set new.
	out := OrderedCollection new.
	self items do: [ :each |
		(seen includes: each bundleId) ifFalse: [
			seen add: each bundleId.
			out add: each bundleId ] ].
	^ out asArray!

landingRows
	"What the BUNDLE shows under Packet: enough to say a packet exists and to
	 click through, and no more.  Repeating summaryRows there made the two tabs
	 identical and the click pointless."
	^ {
		{ 'packet'. self packetId }.
		{ 'holds'. self summaryLine } }!

summaryLine
	^ (self coverageAt: 'items_selected') asString, ' of ',
		(self coverageAt: 'candidates_considered') asString,
		' candidates, ', (self coverageAt: 'tokens_selected') asString, ' of ',
		(self coverageAt: 'tokens_budget') asString, ' tokens, ',
		self exclusions size printString, ' excluded, wrote nothing'!

summaryRows
	^ {
		{ 'packet'. self packetId }.
		{ 'subject'. subjectKind, ' ', subjectId asString }.
		{ 'tier'. self tier }.
		{ 'items'. self items size }.
		{ 'excluded'. self exclusions size }.
		{ 'occurrences'. self coverageAt: 'occurrences' }.
		{ 'tokens'. (self coverageAt: 'tokens_selected') asString, ' of ',
			(self coverageAt: 'tokens_budget') asString }.
		{ 'sources'. (self coverageAt: 'sources_represented') asString, ' of ',
			(self coverageAt: 'sources_available') asString }.
		{ 'content hash'. self at: 'content_hash' }.
		{ 'wrote'. 'nothing -- planned with --no-cache' } }! !


!McKdiPacket methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiPacket(', self summaryLine, ')'! !


!McKdiPacket methodsFor: 'views'!
gtItemsFor: aView
	<gtView>
	^ aView columnedList
		title: 'Items';
		priority: 10;
		items: [ self items ];
		column: 'handle' text: [ :each | each handle asString ] width: 70;
		column: 'role' text: [ :each | each role asString ] width: 90;
		column: 'relevance' text: [ :each | each relevanceDescription ] width: 90;
		column: 'tokens' text: [ :each | each tokenEstimate asString ] width: 80;
		column: 'passages' text: [ :each | each occurrenceIds size asString ] width: 90;
		column: 'overlap' text: [ :each | each overlapDescription ] width: 110;
		column: 'why it is in the packet' text: [ :each | each entryReason asString ];
		send: [ :each | each ]!

gtExcludedFor: aView
	<gtView>
	"Always present, even at zero rows.  `nothing was excluded' and `no view was
	 written' must not look the same -- an empty table says the first."
	^ aView columnedList
		title: 'Excluded';
		priority: 15;
		items: [ self exclusions ];
		column: 'candidate' text: [ :each | (each at: 'bundle_id' ifAbsent: [ '--' ]) asString ];
		column: 'rule' text: [ :each | (each at: 'reason' ifAbsent: [ '--' ]) asString ] width: 190;
		column: 'why it was dropped' text: [ :each | (each at: 'detail' ifAbsent: [ '--' ]) asString ];
		send: [ :each | McKdiBundle store: store id: (each at: 'bundle_id' ifAbsent: [ nil ]) ]!

gtPacketFor: aView
	<gtView>
	^ aView columnedList
		title: 'Packet';
		priority: 20;
		items: [ self summaryRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtCoverageFor: aView
	<gtView>
	^ aView forward
		title: 'Coverage';
		priority: 25;
		object: [ self coverage ];
		view: #gtItemsFor:!

gtBundlesFor: aView
	<gtView>
	^ aView columnedList
		title: 'Bundles';
		priority: 30;
		items: [ self bundleIds ];
		column: 'bundle (EvidenceSet)' text: [ :each | each asString ];
		send: [ :each | McKdiBundle store: store id: each ]!

gtLimitationsFor: aView
	<gtView>
	self limitations ifEmpty: [ ^ aView empty ].
	^ aView columnedList
		title: 'Limitations';
		priority: 35;
		items: [ self limitations ];
		column: 'what this packet cannot claim' text: [ :each | each asString ]!

gtUniverseFor: aView
	<gtView>
	^ aView forward
		title: 'Universe';
		priority: 40;
		object: [ (self at: 'universe') ifNil: [ Dictionary new ] ];
		view: #gtItemsFor:!

gtSpecFor: aView
	<gtView>
	^ aView forward
		title: 'Specification';
		priority: 45;
		object: [ (self at: 'spec') ifNil: [ Dictionary new ] ];
		view: #gtItemsFor:! !


!McKdiPacketItem methodsFor: 'initialization'!
setPacket: aPacket
	packet := aPacket.
	^ self! !


!McKdiPacketItem methodsFor: 'accessing'!
packet
	^ packet!

handle
	"E001, E002 -- what the drafted report cites.  The one identifier in this
	 whole model that was invented for a human to read."
	^ self at: 'handle'!

bundleId
	^ self at: 'bundle_id'!

role
	^ self at: 'role'!

relevance
	^ self at: 'relevance'!

relevanceDescription
	^ self relevance ifNil: [ '--' ] ifNotNil: [ :r | r printShowingDecimalPlaces: 3 ]!

tokenEstimate
	^ self at: 'token_estimate'!

entryReason
	^ self at: 'entry_reason'!

occurrenceIds
	^ (self at: 'occurrence_ids') ifNil: [ #() ]!

overlapDescription
	| o |
	o := self at: 'member_overlap'.
	(o isNil or: [ o = 0 ]) ifTrue: [ ^ '--' ].
	^ (o printShowingDecimalPlaces: 3), ' with ',
		((self at: 'member_overlap_with') ifNil: [ '?' ]) asString!

text
	^ (self at: 'text') ifNil: [ '' ]!

passageFor: anOccurrenceId
	| a |
	a := packet binding runJson: { 'passage'. 'show'. anOccurrenceId }.
	^ a hasValue ifTrue: [ McKdiPassage json: a value answer: a ] ifFalse: [ a ]!

itemRows
	^ {
		{ 'handle'. self handle }.
		{ 'role'. self role }.
		{ 'relevance'. self relevanceDescription }.
		{ 'tokens'. self tokenEstimate }.
		{ 'passages'. self occurrenceIds size }.
		{ 'bundle'. self bundleId }.
		{ 'source'. self at: 'source_uri' }.
		{ 'revision'. self at: 'source_revision_id' }.
		{ 'tier'. self at: 'tier' }.
		{ 'bundle policy'. self at: 'bundle_policy' }.
		{ 'has vector'. self at: 'has_vector' }.
		{ 'member overlap'. self overlapDescription }.
		{ 'entry reason'. self entryReason } }! !


!McKdiPacketItem methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiPacketItem(', self handle asString, ' ', self role asString, ')'! !


!McKdiPacketItem methodsFor: 'views'!
gtTextFor: aView
	<gtView>
	^ aView textEditor
		title: 'Text';
		priority: 10;
		text: [ self text ]!

gtPassagesFor: aView
	<gtView>
	"The walk continues here: a packet item is passages, and each one still
	 resolves to its exact source characters."
	^ aView columnedList
		title: 'Passages';
		priority: 20;
		items: [ self occurrenceIds ];
		column: 'passage' text: [ :each | each asString ];
		send: [ :each | self passageFor: each ]!

gtItemFor: aView
	<gtView>
	^ aView columnedList
		title: 'Item';
		priority: 30;
		items: [ self itemRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtBundleFor: aView
	<gtView>
	^ aView columnedList
		title: 'Bundle';
		priority: 40;
		items: [ { self bundleId } ];
		column: 'bundle (EvidenceSet)' text: [ :each | each asString ];
		send: [ :each | McKdiBundle store: packet store id: each ]! !
