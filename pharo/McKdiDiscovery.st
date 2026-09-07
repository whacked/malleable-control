"
McKdiDiscovery -- the derived layer: context blocks and their members.

A context block is the `context block' step of KDI's chain

    revision -> Passage -> context block -> Selection -> prompt packet -> report

and it is the normal slice candidate.  The class is still called McKdiBundle,
because `bundle' is what `kdi discovery bundles' calls it and renaming the class
would break every caller; the SCREENS say context block, which is the word the
public model uses.  It is implemented by the generic EvidenceSet container --
the storage word for what this explorer calls a Selection -- so its id is an
`est-' one and the container name alone never tells you which set type you hold.

The reason this file exists is the walk the Textual workbench lists as
impossible: from a context block down into its passages and their source text.
A member carries an occurrence id, and a passage id IS an occurrence id, so the
walk is one `kdi passage show' away.  The accessor is called passageId for that
reason; occurrenceId remains as a deprecated alias.

Chunk format: load with fileIn.
"!

McKdiObject subclass: #McKdiBundle
	instanceVariableNames: 'store detail members packet packetAnswer'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiBundleMember
	instanceVariableNames: 'bundle passage'
	classVariableNames: ''
	package: 'MalleableControl'!


!McKdiBundle class methodsFor: 'instance creation'!
store: aStore json: aDictionary answer: anAnswer
	^ (self json: aDictionary answer: anAnswer) setStore: aStore!

store: aStore id: anId
	"A context block known only by id -- the usual case when a slice candidate
	 names one."
	^ (self json: (Dictionary new at: 'bundle_id' put: anId; yourself) answer: nil)
		setStore: aStore! !


!McKdiBundle methodsFor: 'initialization'!
setStore: aStore
	store := aStore.
	^ self! !


!McKdiBundle methodsFor: 'accessing'!
store
	^ store!

binding
	^ store binding!

id
	^ (self at: 'bundle_id') ifNil: [ self at: 'id' ]!

policy
	^ self at: 'policy'!

sourceUri
	^ (self at: 'source_uri') ifNil: [ self detailAt: 'source_uri' ]!

memberCount
	^ (self at: 'members') ifNil: [ self loadedMembers size ] ifNotNil: [ :m |
		m isNumber ifTrue: [ m ] ifFalse: [ m size ] ]!

chars
	^ (self at: 'chars') ifNil: [ self metadataAt: 'char_length' ]!

informationMass
	^ (self at: 'information_mass') ifNil: [ self detailAt: 'information_mass' ]!

extent
	^ (self at: 'extent') ifNil: [ #() ]!

extentDescription
	self extent size = 2 ifFalse: [ ^ '--' ].
	^ 'ordinals ', (self extent first) printString, '-', (self extent second) printString! !


!McKdiBundle methodsFor: 'detail'!
load
	"kdi discovery bundles show: the block's text, its members' roles and its
	 exact provenance.  A read, so nothing to confirm."
	| a |
	detail := self binding runJson: { 'discovery'. 'bundles'. 'show'. self id }.
	^ detail!

detailAnswer
	^ detail ifNil: [ self load ]!

detailAt: aKey
	^ self detailAnswer valueAt: aKey!

metadata
	^ (self detailAt: 'metadata') ifNil: [ Dictionary new ]!

metadataAt: aKey
	^ self metadata at: aKey ifAbsent: [ nil ]!

text
	^ (self detailAt: 'text') ifNil: [ '' ]!

sourceRevisionId
	^ self detailAt: 'source_revision_id'!

loadedMembers
	^ members ifNil: [
		members := ((self detailAt: 'members') ifNil: [ #() ])
			collect: [ :each | McKdiBundleMember bundle: self json: each answer: self detailAnswer ] ]!

memberPassageIds
	^ self loadedMembers collect: [ :each | each passageId ]!

source
	"The McKdiSource this bundle was cut from, if the store has it loaded."
	^ store sourceForUri: self sourceUri! !


!McKdiBundle methodsFor: 'deprecated - compatibility'!
memberOccurrenceIds
	"DEPRECATED -- use memberPassageIds.  The two answer the same ids: design 43
	 keeps a passage id and an occurrence id the same id."
	^ self memberPassageIds! !


!McKdiBundle methodsFor: 'packet'!
planPacket
	"kdi infer plan --bundle ID --no-cache: the one crossing into the inference
	 layer that costs nothing.  A packet takes exactly one subject -- a topic, a
	 bundle or a MATERIALIZED slice -- so a write-free slice recipe cannot reach
	 this layer, but a bundle already in hand can."
	| a |
	a := McKdiPacket store: store subjectKind: 'bundle' subjectId: self id.
	(a isKindOf: McKdiPacket)
		ifTrue: [ packet := a. packetAnswer := a answer ]
		ifFalse: [ packet := nil. packetAnswer := a ].
	^ packet ifNil: [ packetAnswer ]!

packet
	^ packet!

packetAnswer
	^ packetAnswer! !


!McKdiBundle methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiBundle(', self id asString, ')'! !


!McKdiBundle methodsFor: 'views'!
gtTextFor: aView
	<gtView>
	^ aView textEditor
		title: 'Text';
		priority: 10;
		text: [ self text ]!

gtMembersFor: aView
	<gtView>
	^ aView columnedList
		title: 'Passages';
		priority: 20;
		items: [ self loadedMembers ];
		column: 'order' text: [ :each | each streamOrdinal asString ] width: 70;
		column: 'role' text: [ :each | each role asString ] width: 90;
		column: 'weight' text: [ :each | each weightDescription ] width: 80;
		column: 'passage' text: [ :each | each passageId asString ];
		send: [ :each | each ]!

summaryRows
	"Shared with McKdiSliceCandidate, whose Context block tab lands on this
	 object rather than forwarding past it."
	^ {
			{ 'id'. self id }.
			{ 'set type'. 'local-topic-bundle (a Selection container)' }.
			{ 'policy'. self policy }.
			{ 'source'. self sourceUri }.
			{ 'revision'. self sourceRevisionId }.
			{ 'members'. self memberCount }.
			{ 'characters'. self chars }.
			{ 'information mass'. self informationMass }.
			{ 'extent'. self extentDescription }.
			{ 'lexical cohesion'. self metadataAt: 'lexical_cohesion' }.
			{ 'embedding cohesion'. (self metadataAt: 'embedding_cohesion')
				ifNil: [ '(unknown -- no embedding coverage)' ] }.
			{ 'core units'. self metadataAt: 'core_units' }.
			{ 'shoulder units'. self metadataAt: 'shoulder_units' } }!

gtBundleFor: aView
	<gtView>
	^ aView columnedList
		title: 'Context block';
		priority: 30;
		items: [ self summaryRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtPacketFor: aView
	<gtView>
	"Clicking any row lands on the packet, which is the object with the views.
	 A forward would put its Excluded table out of reach (finding 15)."
	packet ifNil: [ ^ aView empty ].
	^ aView columnedList
		title: 'Packet';
		priority: 40;
		items: [ packet landingRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ];
		send: [ :each | packet ]!

gtPacketFailureFor: aView
	<gtView>
	"Same title as the success: an empty view means nothing to show, never
	 something went wrong (finding 14)."
	(packet notNil or: [ packetAnswer isNil ]) ifTrue: [ ^ aView empty ].
	^ aView textEditor
		title: 'Packet';
		priority: 40;
		text: [ packetAnswer failureReport: 'The packet was not planned.' ]!

gtMetadataFor: aView
	<gtView>
	^ aView forward
		title: 'Metadata';
		priority: 60;
		object: [ self metadata ];
		view: #gtItemsFor:!

gtSourceFor: aView
	<gtView>
	self source ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Source';
		priority: 70;
		object: [ self source ];
		view: #gtStructureFor:! !


!McKdiBundle methodsFor: 'actions'!
gtPlanPacketActionFor: anAction
	<gtAction>
	^ anAction button
		label: (store actionLabel: 'Plan packet (writes nothing)');
		priority: 10;
		tooltip: 'kdi infer plan --bundle ID --no-cache: what a report would be drafted over, and every candidate it refused';
		action: [ :aButton | store runOffUi: [ self planPacket ] from: aButton labelled: 'Plan packet' ]! !


!McKdiBundleMember class methodsFor: 'instance creation'!
bundle: aBundle json: aDictionary answer: anAnswer
	^ (self json: aDictionary answer: anAnswer) setBundle: aBundle! !


!McKdiBundleMember methodsFor: 'initialization'!
setBundle: aBundle
	bundle := aBundle.
	^ self! !


!McKdiBundleMember methodsFor: 'accessing'!
bundle
	^ bundle!

passageId
	"The public name for what the payload calls occurrence_id: design 43 keeps
	 them the same id so that kdi prov resolves it unchanged."
	^ self at: 'occurrence_id'!

role
	^ self at: 'role'!

weight
	^ self at: 'weight'!

weightDescription
	^ self weight ifNil: [ '--' ] ifNotNil: [ :w | w printShowingDecimalPlaces: 2 ]!

streamOrdinal
	^ self at: 'stream_ordinal'!

selectorType
	^ self at: 'selector_type'!

informationMass
	^ self at: 'information_mass'! !


!McKdiBundleMember methodsFor: 'deprecated - compatibility'!
occurrenceId
	"DEPRECATED -- use passageId.  Occurrence is the storage word for the same
	 id, and both resolve through kdi passage show unchanged."
	^ self passageId! !


!McKdiBundleMember methodsFor: 'passage'!
loadPassage
	"The walk the Textual workbench cannot do: from a context block member down
	 to the exact citable passage and its grounding."
	| a |
	a := bundle binding runJson: { 'passage'. 'show'. self passageId }.
	passage := a hasValue ifTrue: [ McKdiPassage json: a value answer: a ] ifFalse: [ nil ].
	^ passage!

passage
	^ passage ifNil: [ self loadPassage ]! !


!McKdiBundleMember methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiBundleMember(', self role asString, ' ', self passageId asString, ')'! !


!McKdiBundleMember methodsFor: 'views'!
gtPassageGroundingFor: aView
	<gtView>
	"Named for what it shows.  Clicking a member row lands you HERE, not on the
	 passage, so the passage's own views have to be carried across or they cannot
	 be reached at all -- the same trap as the slice plan."
	self passage ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Grounding';
		priority: 10;
		object: [ self passage ];
		view: #gtGroundingFor:!

gtPassageGroundingTextFor: aView
	<gtView>
	self passage ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Grounding (text)';
		priority: 15;
		object: [ self passage ];
		view: #gtGroundingReportFor:!

gtPassageTextFor: aView
	<gtView>
	self passage ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Text';
		priority: 30;
		object: [ self passage ];
		view: #gtTextFor:!

gtPassageFieldsFor: aView
	<gtView>
	self passage ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Passage';
		priority: 35;
		object: [ self passage ];
		view: #gtPassageFor:!

gtPassageSelectorFor: aView
	<gtView>
	self passage ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Selector';
		priority: 40;
		object: [ self passage ];
		view: #gtSelectorFor:!

gtMemberFor: aView
	<gtView>
	^ aView columnedList
		title: 'Member';
		priority: 20;
		items: [ {
			{ 'passage id'. self passageId }.
			{ 'role'. self role }.
			{ 'weight'. self weightDescription }.
			{ 'stream ordinal'. self streamOrdinal }.
			{ 'selector'. self selectorType }.
			{ 'information mass'. self informationMass }.
			{ 'context block'. bundle id } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]! !
