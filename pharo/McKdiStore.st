"
McKdiStore -- the root object of the KDI data explorer.

Inspect one of these and everything else is reached by drilling into it:
preflight, the sources, the structural tree of a source, the passages of a node,
the grounding of a passage.  There is no tab to switch to and no id to copy: the
object you selected is the object in the next pane.

The ingestion interface lives here too, as inspector actions and as the methods
the Lepiter page calls.  Phase one runs preflight, store initialization,
write-free planning and canonical ingestion, and stops there: no extraction, no
embeddings, no provider call, so nothing needs a confirmation modal.

Also defined here: McKdiPlan and McKdiStage (what `kdi update` would do), and
McKdiIngestReport and McKdiIngestOutcome (what an ingestion actually did).

Chunk format: load with fileIn.
"!

Object subclass: #McKdiStore
	instanceVariableNames: 'binding statusAnswer sources ingestPaths pipelineProfile lastPlan lastIngest lastJob previousPlan bundles discoveryAnswer recipe runningLabel inspectorPager'
	classVariableNames: 'Session'
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiPlan
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiStage
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiIngestReport
	instanceVariableNames: 'store outcomes'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiIngestOutcome
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!


!McKdiStore class methodsFor: 'instance creation'!
on: aBinding
	^ self new setBinding: aBinding!

default
	"A store on the binding the Emacs launcher last installed."
	^ McKdiBinding default
		ifNil: [ nil ]
		ifNotNil: [ :b | self on: b ]!

session
	"The one store the Emacs launcher bound, so a command typed in Emacs and a
	 window already open are looking at the same object."
	^ Session ifNil: [ Session := self default ]!

session: aStore
	Session := aStore.
	^ aStore!

openSession
	^ self session
		ifNil: [ self error: 'no KDI store bound -- run mc-kdi-bind first' ]
		ifNotNil: [ :s | s open ]!

openLauncherSession
	"openSession for a caller that is not Emacs.

	 `session' answers the store the Emacs launcher bound, and `openSession'
	 raises when nothing has.  A card on GT's home screen cannot require that
	 Emacs ran first -- that dependency is backwards, since GT is the core and
	 Emacs is a client of the bus.  So: reuse an installed binding if there is
	 one, otherwise build one from the KDI_* environment variables, which are
	 the same defaults mc-kdi.el's defcustoms fall back to.

	 With neither available this reports what is missing rather than raising
	 something opaque, so the launcher card can say so."
	self session ifNotNil: [ :s | ^ s open ].
	^ self bindingFromEnvironment
		ifNil: [ self error: 'no KDI store bound, and KDI_STORE_PATH is not set -- run mc-kdi-bind, or set KDI_STORE_PATH and KDI_PROFILE' ]
		ifNotNil: [ :b |
			McKdiBinding default: b.
			(self session: (self on: b)) open ]!

bindingFromEnvironment
	"A binding from KDI_*, or nil when the store path is not set.  The store
	 path is the only setting with no usable default, which is why it alone
	 decides whether this answers a binding at all."
	| env at store |
	env := [ Smalltalk os environment ] on: Error do: [ :e | ^ nil ].
	at := [ :key :default |
		| v |
		v := [ env at: key ifAbsent: [ nil ] ] on: Error do: [ :e | nil ].
		(v isNil or: [ v isEmpty ]) ifTrue: [ default ] ifFalse: [ v ] ].
	store := at value: 'KDI_STORE_PATH' value: nil.
	store ifNil: [ ^ nil ].
	^ McKdiBinding
		root: (at value: 'KDI_ROOT' value: FileSystem workingDirectory fullName)
		store: store
		profile: (at value: 'KDI_PROFILE' value: 'local')
		tier: (at value: 'KDI_TIER' value: 'public')
		configDir: (at value: 'KDI_CONFIG_DIR' value: nil)! !


!McKdiStore methodsFor: 'initialization'!
setBinding: aBinding
	binding := aBinding.
	ingestPaths := #().
	^ self! !


!McKdiStore methodsFor: 'accessing'!
binding
	^ binding!

ingestPaths
	^ ingestPaths ifNil: [ ingestPaths := #() ]!

ingestPaths: aCollectionOfStrings
	ingestPaths := aCollectionOfStrings asArray!

pipelineProfile
	^ pipelineProfile!

pipelineProfile: aString
	pipelineProfile := aString!

lastPlan
	^ lastPlan!

lastIngest
	^ lastIngest!

lastJob
	^ lastJob!

label
	^ binding label! !


!McKdiStore methodsFor: 'preflight'!
refreshStatus
	statusAnswer := binding runJson: #('status').
	^ statusAnswer!

statusAnswer
	^ statusAnswer ifNil: [ self refreshStatus ]!

isBound
	^ self statusAnswer isSuccess!

statusAt: aKey
	^ self statusAnswer valueAt: aKey!

counts
	^ (self statusAt: 'counts') ifNil: [ Dictionary new ]!

countAt: aKey
	^ self counts at: aKey ifAbsent: [ 0 ]!

initializeStore
	"kdi init.  The only phase-one command that creates anything other than
	 canonical evidence."
	| a |
	a := binding runJson: #('init').
	statusAnswer := nil.
	^ a! !


!McKdiStore methodsFor: 'sources'!
refreshSources
	| a rows |
	a := binding runJson: #('sources').
	rows := (a value isKindOf: Array) ifTrue: [ a value ] ifFalse: [ #() ].
	sources := rows collect: [ :each | McKdiSource store: self json: each answer: a ].
	^ sources!

sources
	^ sources ifNil: [ self refreshSources ]!

sourceForUri: aUri
	^ self sources detect: [ :each | each uri = aUri ] ifNone: [ nil ]! !


!McKdiStore methodsFor: 'ingestion'!
planArguments
	| args |
	args := OrderedCollection new.
	args add: 'update'; add: 'plan'.
	self ingestPaths do: [ :each | args add: each ].
	pipelineProfile ifNotNil: [ :p | args add: '--pipeline-profile'; add: p ].
	^ args asArray!

plan
	"kdi update plan.  Writes nothing and makes no external call."
	| a |
	a := binding runJson: self planArguments.
	previousPlan := lastPlan.
	lastPlan := a hasValue ifTrue: [ McKdiPlan json: a value answer: a ] ifFalse: [ nil ].
	^ lastPlan ifNil: [ a ]!

previousPlan
	^ previousPlan!

ingestArguments
	^ (Array with: 'ingest'), self ingestPaths!

ingest
	"kdi ingest PATHS.  Canonical evidence only: no enrichment stage, so no
	 provider is reachable from here."
	| a rows |
	self ingestPaths ifEmpty: [ ^ nil ].
	a := binding runJson: self ingestArguments.
	rows := (a value isKindOf: Array) ifTrue: [ a value ] ifFalse: [ #() ].
	lastIngest := (McKdiIngestReport json: rows answer: a) setStore: self.
	sources := nil.
	statusAnswer := nil.
	^ lastIngest!

ingestInBackground
	"The same command off the UI process, so the image stays usable while a
	 large corpus is read."
	lastJob := (McKdiJob binding: binding argv: self ingestArguments label: 'ingest') start.
	^ lastJob! !


!McKdiStore methodsFor: 'discovery'!
refreshDiscovery
	discoveryAnswer := binding runJson: #('discovery' 'status').
	^ discoveryAnswer!

discoveryAnswer
	^ discoveryAnswer ifNil: [ self refreshDiscovery ]!

discoveryAt: aKey
	^ self discoveryAnswer valueAt: aKey!

hasBundles
	^ ((self discoveryAt: 'bundles') ifNil: [ 0 ]) > 0!

runDiscovery
	"snapshot -> signals -> fields -> bundles.  Topics are left off: `auto'
	 evaluates a recorded grid and this phase deliberately reaches no provider.
	 This writes: bundles are derived artifacts in the store."
	| a |
	a := binding runJson: #('discovery' 'run' '--topics' 'none').
	discoveryAnswer := nil.
	bundles := nil.
	^ a!

refreshBundles
	| a rows |
	a := binding runJson: #('discovery' 'bundles' 'list' '--limit' '200').
	rows := (a value isKindOf: Array) ifTrue: [ a value ] ifFalse: [ #() ].
	bundles := rows collect: [ :each | McKdiBundle store: self json: each answer: a ].
	^ bundles!

bundles
	^ bundles ifNil: [ self refreshBundles ]!

bundleForId: anId
	^ self bundles
		detect: [ :each | each id = anId ]
		ifNone: [ McKdiBundle store: self id: anId ]! !


!McKdiStore methodsFor: 'slicing'!
recipe
	"One slice recipe per store, so the planned matches you were looking at are
	 still there when you come back to the tab."
	^ recipe ifNil: [ recipe := McKdiSliceRecipe store: self ]!

recipe: aRecipe
	recipe := aRecipe! !


!McKdiStore methodsFor: 'opening'!
open
	"Inspect this store.  The inspector is the explorer: there is no separate
	 window to build, and a gtView added later shows up here without one.

	 GtInspector builds a fresh BlSpace on every call, so a second launch would
	 stack a second inspector on the same store.  Reuse the one already up and
	 fire its update wish instead: that re-renders the views from the answers
	 already cached, without spending a subprocess call.  McWindow cannot find
	 this window the way it finds the others -- the space belongs to the pager,
	 not to the store -- so the pager is remembered here."
	self liveInspector ifNotNil: [ :pager |
		[ pager space toFront ] on: Error do: [ :e |  ].
		[ pager phlow fireUpdateWish ] on: Error do: [ :e |  ].
		^ self ].
	inspectorPager := [ GtInspector openOn: self title: 'KDI -- ', self label asString ]
		on: Error
		do: [ :e | nil ].
	^ self!

liveInspector
	"The pager from an earlier open, while its window is still up.  Forgets a
	 pager whose window has gone, so the next open builds a new one."
	| space |
	inspectorPager ifNil: [ ^ nil ].
	space := [ inspectorPager space ] on: Error do: [ :e | nil ].
	^ (space notNil and: [ [ space isOpened ] on: Error do: [ :e | false ] ])
		ifTrue: [ inspectorPager ]
		ifFalse: [ inspectorPager := nil ]!

preflightDescription
	"One line for the Emacs echo area."
	self isBound ifFalse: [ ^ 'not bound: ', self statusAnswer errorMessage asString ].
	^ (self statusAt: 'profile') asString, '/', (self statusAt: 'tier') asString,
		' schema ', (self statusAt: 'schema_version') asString,
		' -- ', (self countAt: 'source') printString, ' sources, ',
		(self countAt: 'structural_node') printString, ' nodes, ',
		(self countAt: 'occurrence') printString, ' passages'! !


!McKdiStore methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiStore(', self label asString, ')'! !


!McKdiStore methodsFor: 'views'!
gtPreflightFor: aView
	<gtView>
	^ aView columnedList
		title: 'Preflight';
		priority: 10;
		items: [ | rows |
			rows := OrderedCollection new.
			self isBound
				ifFalse: [
					rows add: { 'bound'. 'no' }.
					rows add: { 'problem'. self statusAnswer errorMessage } ]
				ifTrue: [
					rows add: { 'store'. self statusAt: 'store' }.
					rows add: { 'profile / tier'.
						(self statusAt: 'profile') asString, ' / ', (self statusAt: 'tier') asString }.
					rows add: { 'schema version'. self statusAt: 'schema_version' }.
					rows add: { 'root'. self statusAt: 'root' }.
					(self counts keys asSortedCollection) do: [ :k |
						rows add: { k. self countAt: k } ] ].
			rows asArray ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtSourcesFor: aView
	<gtView>
	^ aView columnedList
		title: 'Sources';
		priority: 20;
		items: [ self sources ];
		column: 'uri' text: [ :each | each uri asString ];
		column: 'tier' text: [ :each | each tier asString ] width: 90;
		column: 'adapter' text: [ :each | each adapterType asString ] width: 120;
		column: 'revisions' text: [ :each | each revisionCount asString ] width: 100;
		send: [ :each | each ]!

gtIngestionFor: aView
	<gtView>
	^ aView columnedList
		title: 'Ingestion';
		priority: 30;
		items: [ {
			{ 'paths'. self ingestPaths isEmpty
				ifTrue: [ '(none configured)' ]
				ifFalse: [ ', ' join: self ingestPaths ] }.
			{ 'pipeline profile'. pipelineProfile ifNil: [ '(none)' ] }.
			{ 'last plan'. lastPlan ifNil: [ '(not planned)' ] ifNotNil: [ :p | p summaryLine ] }.
			{ 'last ingest'. lastIngest ifNil: [ '(none)' ] ifNotNil: [ :r | r summaryLine ] }.
			{ 'background job'. lastJob ifNil: [ '(none)' ] ifNotNil: [ :j | j printString ] } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ];
		send: [ :each | each second ]!

gtPlanFor: aView
	<gtView>
	lastPlan ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Plan';
		priority: 40;
		object: [ lastPlan ];
		view: #gtStagesFor:!

gtLastIngestFor: aView
	<gtView>
	lastIngest ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Last ingest';
		priority: 50;
		object: [ lastIngest ];
		view: #gtOutcomesFor:!

bundlesTabTitle
	"The count belongs in the title.  A table of ids has nothing to count by eye,
	 and `how many candidates does a slice choose from' is the first question the
	 slice layer asks."
	^ self hasBundles
		ifTrue: [ 'Bundles (', self bundles size printString, ')' ]
		ifFalse: [ 'Bundles' ]!

gtBundlesFor: aView
	<gtView>
	^ aView columnedList
		title: self bundlesTabTitle;
		priority: 55;
		items: [ self hasBundles ifTrue: [ self bundles ] ifFalse: [ #() ] ];
		column: '#' text: [ :each | ((self bundles indexOf: each) ifNil: [ 0 ]) asString ] width: 44;
		column: 'bundle' text: [ :each | each id asString ];
		column: 'source' text: [ :each | each sourceUri asString ];
		column: 'passages' text: [ :each | each memberCount asString ] width: 100;
		column: 'chars' text: [ :each | each chars asString ] width: 90;
		column: 'extent' text: [ :each | each extentDescription ] width: 160;
		send: [ :each | each ]!

gtSliceFor: aView
	<gtView>
	"A list rather than a forward, because GT builds the action bar from the
	 object being inspected: a forwarded view renders the recipe while the
	 toolbar still belongs to the store, so the recipe's own Plan matches button
	 never appears.  Clicking any row here opens the recipe itself, with its
	 buttons and its Planned matches / Masked / Plan diff tabs."
	^ aView columnedList
		title: 'Slice';
		priority: 57;
		items: [ self recipe recipeRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ];
		column: 'kind' text: [ :each | each third ] width: 300;
		send: [ :each | self recipe ]!

gtDiscoveryFor: aView
	<gtView>
	^ aView columnedList
		title: 'Discovery';
		priority: 58;
		items: [ {
			{ 'bundles'. self discoveryAt: 'bundles' }.
			{ 'topics'. self discoveryAt: 'topics' }.
			{ 'boundary fields'. self discoveryAt: 'boundary_fields' }.
			{ 'boundary observations'. self discoveryAt: 'boundary_observations' }.
			{ 'neighborhoods'. self discoveryAt: 'neighborhoods' }.
			{ 'bundle policies'. (self discoveryAt: 'bundle_policies')
				ifNil: [ '--' ] ifNotNil: [ :p | p isEmpty ifTrue: [ '(none)' ]
					ifFalse: [ ', ' join: (p collect: [ :e | e asString ]) ] ] } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtUpdatePlanDiffFor: aView
	<gtView>
	(lastPlan isNil or: [ previousPlan isNil ]) ifTrue: [ ^ aView empty ].
	^ aView columnedList
		title: 'Plan diff';
		priority: 45;
		items: [ lastPlan diffAgainst: previousPlan ];
		column: 'stage' text: [ :each | each first ];
		column: 'field' text: [ :each | each second ] width: 120;
		column: 'was' text: [ :each | each third asString ] width: 90;
		column: 'now' text: [ :each | each fourth asString ] width: 90!

gtTranscriptFor: aView
	<gtView>
	^ aView columnedList
		title: 'Transcript';
		priority: 70;
		items: [ McKdiTranscript entries ];
		column: 'exit' text: [ :each | each exitCode asString ] width: 60;
		column: 'ms' text: [ :each | each durationDescription ] width: 90;
		column: 'command' text: [ :each | each commandString ];
		send: [ :each | each ]!

gtBindingFor: aView
	<gtView>
	^ aView forward
		title: 'Binding';
		priority: 80;
		object: [ binding ];
		view: #gtBindingFor:! !


!McKdiStore methodsFor: 'actions'!
isBusy
	^ runningLabel notNil!

runningLabel
	^ runningLabel!

actionLabel: aString
	"Every toolbar label goes through here.  A forked subprocess used to leave
	 the button looking idle for as long as it took -- `slice create --run' is
	 seconds of provider work -- so the only feedback that anything was happening
	 was the result appearing, and the reasonable thing to do meanwhile is press
	 the button again.  While a job is in flight every label says which."
	^ self isBusy
		ifTrue: [ 'running: ', runningLabel, ' ...' ]
		ifFalse: [ aString ]!

runOffUi: aBlock from: aButton
	^ self runOffUi: aBlock from: aButton labelled: 'a command'!

runOffUi: aBlock from: aButton labelled: aLabel
	"Every button here spawns a subprocess, and a subprocess run on the UI
	 process freezes the whole image.  The mechanics -- fork, mark the button,
	 release it on the UI process, ignore a second press -- live in McOffUi,
	 which documents the two traps involved.

	 What stays here is `runningLabel', which is STORE state rather than button
	 state: it drives actionLabel: across the whole toolbar, so every label says
	 which job is in flight, not just the one that was pressed.  It is cleared
	 before McOffUi releases the button, so the refresh sees an idle store."
	self isBusy ifTrue: [ ^ self ].
	runningLabel := aLabel.
	(Smalltalk at: #McOffUi)
		run: [ [ aBlock value ] ensure: [ runningLabel := nil ] ]
		from: aButton
		labelled: aLabel
		onError: [ :err |
			McKdiTranscript record: (McKdiAnswer
				argv: #('(gt)')
				exitCode: -1
				stdout: ''
				stderr: err messageText asString
				startedAt: DateAndTime now
				duration: 0) ].
	^ self!

gtRefreshActionFor: anAction
	<gtAction>
	^ anAction button
		label: (self actionLabel: 'Refresh');
		priority: 10;
		tooltip: 'Re-run kdi status and re-read the sources';
		action: [ :aButton | self runOffUi: [ self refreshStatus. self refreshSources ] from: aButton labelled: 'Refresh' ]!

gtPlanActionFor: anAction
	<gtAction>
	^ anAction button
		label: (self actionLabel: 'Plan update');
		priority: 20;
		tooltip: 'kdi update plan -- writes nothing, calls nothing external';
		action: [ :aButton | self runOffUi: [ self plan ] from: aButton labelled: 'Plan update' ]!

gtIngestActionFor: anAction
	<gtAction>
	^ anAction button
		label: (self actionLabel: 'Ingest');
		priority: 30;
		tooltip: 'kdi ingest PATHS -- canonical evidence only, no enrichment';
		action: [ :aButton | self runOffUi: [ self ingest ] from: aButton labelled: 'Ingest' ]!

gtSlicePlanActionFor: anAction
	<gtAction>
	^ anAction button
		label: (self actionLabel: 'Plan matches');
		priority: 25;
		tooltip: 'kdi slice create --plan over the Slice tab recipe -- writes nothing';
		action: [ :aButton | self runOffUi: [ self recipe plan ] from: aButton labelled: 'Plan matches' ]!

gtDiscoveryActionFor: anAction
	<gtAction>
	^ anAction button
		label: (self actionLabel: 'Run discovery');
		priority: 35;
		tooltip: 'kdi discovery run --topics none -- derives the bundles a slice selects over; writes';
		action: [ :aButton | self runOffUi: [ self runDiscovery. self refreshBundles ] from: aButton labelled: 'Run discovery' ]!

gtInitActionFor: anAction
	<gtAction>
	^ anAction button
		label: (self actionLabel: 'Initialize store');
		priority: 40;
		tooltip: 'kdi init -- create the store this binding names';
		action: [ :aButton | self runOffUi: [ self initializeStore ] from: aButton labelled: 'Initialize store' ]! !


!McKdiPlan methodsFor: 'accessing'!
stages
	^ ((self at: 'stages') ifNil: [ #() ])
		collect: [ :each | McKdiStage json: each answer: answer ]!

paths
	^ (self at: 'paths') ifNil: [ #() ]!

scope
	^ self at: 'scope'!

universeHash
	^ self at: 'universe_hash'!

notes
	^ (self at: 'notes') ifNil: [ #() ]!

externalCalls
	^ self stages inject: 0 into: [ :sum :each | sum + (each externalCalls ifNil: [ 0 ]) ]!

summaryLine
	^ self stages size printString, ' coverage stages, ',
		self externalCalls printString, ' external call(s) planned'!

diffAgainst: anotherPlan
	"What changed between two consecutive plans, stage by stage.  Nothing else
	 in KDI diffs two plans for you."
	| rows mine theirs |
	rows := OrderedCollection new.
	theirs := Dictionary new.
	anotherPlan stages do: [ :each | theirs at: each stage put: each ].
	mine := self stages.
	mine do: [ :stage |
		(theirs at: stage stage ifAbsent: [ nil ])
			ifNil: [ rows add: { stage stage. 'stage'. '(absent)'. 'present' } ]
			ifNotNil: [ :was |
				#(#eligible #hit #missing #blocked #externalCalls) do: [ :sel |
					| before after |
					before := was perform: sel.
					after := stage perform: sel.
					before = after ifFalse: [
						rows add: { stage stage. sel asString. before. after } ] ] ] ].
	^ rows asArray! !


!McKdiPlan methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiPlan(', self summaryLine, ')'! !


!McKdiPlan methodsFor: 'views'!
gtStagesFor: aView
	<gtView>
	^ aView columnedList
		title: 'Coverage';
		priority: 10;
		items: [ self stages ];
		column: 'stage' text: [ :each | each stage asString ];
		column: 'eligible' text: [ :each | each eligible asString ] width: 90;
		column: 'hit' text: [ :each | each hit asString ] width: 70;
		column: 'missing' text: [ :each | each missing asString ] width: 90;
		column: 'blocked' text: [ :each | each blocked asString ] width: 90;
		column: 'calls' text: [ :each | each externalCalls asString ] width: 70;
		send: [ :each | each ]!

gtNotesFor: aView
	<gtView>
	self notes ifEmpty: [ ^ aView empty ].
	^ aView columnedList
		title: 'Notes';
		priority: 20;
		items: [ self notes ];
		column: 'note' text: [ :each | each asString ]! !


!McKdiStage methodsFor: 'accessing'!
stage
	^ self at: 'stage'!

eligible
	^ (self at: 'eligible') ifNil: [ 0 ]!

hit
	^ (self at: 'hit') ifNil: [ 0 ]!

missing
	^ (self at: 'missing') ifNil: [ 0 ]!

blocked
	^ (self at: 'blocked') ifNil: [ 0 ]!

historical
	^ (self at: 'historical') ifNil: [ 0 ]!

externalCalls
	^ (self at: 'external_calls') ifNil: [ 0 ]!

note
	^ self at: 'note'!

detail
	^ self at: 'detail'! !


!McKdiStage methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiStage(', self stage asString, ')'! !


!McKdiStage methodsFor: 'views'!
gtStageFor: aView
	<gtView>
	^ aView columnedList
		title: 'Stage';
		priority: 10;
		items: [ {
			{ 'stage'. self stage }.
			{ 'eligible'. self eligible }.
			{ 'hit'. self hit }.
			{ 'missing'. self missing }.
			{ 'historical'. self historical }.
			{ 'blocked'. self blocked }.
			{ 'external calls'. self externalCalls }.
			{ 'note'. self note } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtDetailFor: aView
	<gtView>
	self detail ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Detail';
		priority: 20;
		object: [ self detail ];
		view: #gtItemsFor:! !


!McKdiIngestReport methodsFor: 'accessing'!
setStore: aStore
	store := aStore.
	^ self!

outcomes
	^ outcomes ifNil: [
		outcomes := ((json isKindOf: Array) ifTrue: [ json ] ifFalse: [ #() ])
			collect: [ :each | McKdiIngestOutcome json: each answer: answer ] ]!

summaryLine
	"Reuse is success.  A second ingestion of an unchanged source answers
	 cache_hit, which committed nothing because nothing needed committing --
	 counting that as a failure is how a UI teaches an operator the wrong model."
	| ok tally |
	ok := self outcomes count: [ :each | each isCommitted ].
	tally := Bag new.
	self outcomes do: [ :each | tally add: each status asString ].
	^ ok printString, ' of ', self outcomes size printString, ' committed (',
		(', ' join: ((tally asSet asSortedCollection) collect: [ :k |
			(tally occurrencesOf: k) printString, ' ', k ])), ')'! !


!McKdiIngestReport methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiIngestReport(', self summaryLine, ')'! !


!McKdiIngestReport methodsFor: 'views'!
gtOutcomesFor: aView
	<gtView>
	^ aView columnedList
		title: 'Outcomes';
		priority: 10;
		items: [ self outcomes ];
		column: 'source' text: [ :each | each sourceUri asString ];
		column: 'status' text: [ :each | each status asString ] width: 110;
		column: 'nodes' text: [ :each | each nodeCount asString ] width: 80;
		column: 'quality' text: [ :each | each qualityVerdict ] width: 110;
		column: 'committed' text: [ :each | each isCommitted asString ] width: 100;
		send: [ :each | each ]! !


!McKdiIngestOutcome methodsFor: 'accessing'!
sourceUri
	^ self at: 'source_uri'!

status
	^ self at: 'status'!

isCommitted
	"Committed means the revision is in the store: freshly ingested, or already
	 there and unchanged.  Only an error status is a failure."
	^ self error isNil and: [ #('ingested' 'cache_hit' 'unchanged' 'reused')
		includes: self status asString ]!

isIngested
	^ self status = 'ingested'!

revisionId
	^ self at: 'revision_id'!

nodeCount
	^ (self at: 'node_count') ifNil: [ 0 ]!

decoder
	^ self at: 'decoder'!

cacheReused
	^ (self at: 'cache_reused') = true!

qualityVerdict
	"Not checked is a third answer, and it is not the same as invalid."
	(self at: 'quality_checked') = true ifFalse: [ ^ 'not checked' ].
	^ (self at: 'quality_valid') = true ifTrue: [ 'valid' ] ifFalse: [ 'INVALID' ]!

qualityIssueCodes
	^ (self at: 'quality_issue_codes') ifNil: [ #() ]!

error
	^ self at: 'error'! !


!McKdiIngestOutcome methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiIngestOutcome(', self sourceUri asString, ' ', self status asString, ')'! !


!McKdiIngestOutcome methodsFor: 'views'!
gtOutcomeFor: aView
	<gtView>
	^ aView columnedList
		title: 'Outcome';
		priority: 10;
		items: [ {
			{ 'source'. self sourceUri }.
			{ 'status'. self status }.
			{ 'revision'. self revisionId }.
			{ 'nodes'. self nodeCount }.
			{ 'decoder'. self decoder }.
			{ 'cache reused'. self cacheReused }.
			{ 'quality'. self qualityVerdict }.
			{ 'quality issues'. ', ' join: (self qualityIssueCodes collect: [ :e | e asString ]) }.
			{ 'error'. self error } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]! !
