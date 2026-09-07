"
McKdiGraph -- the entity graph, read only, over the same public CLI JSON.

Nothing in this file writes.  Every command it runs is a read: an entity seed
search, a snapshot BUDGET preview, a neighbourhood, a path, a traversal, and the
relation catalogue with its statistics and its validation report.  There is no
Materialize button here and no argv carrying --run, which is the property that
makes the whole layer safe to click through while you are still working out what
the graph contains.

The chain this layer joins is the one the rest of the explorer already walks:

    revision -> Passage -> context block -> Selection -> prompt packet -> report

A graph node that stands for a passage carries a passage id, and a passage id is
an occurrence id, so a node resolves to an McKdiPassage with its grounding by one
further `kdi passage show'.  That forward walk -- graph node to exact source
characters -- is the reason the graph is worth an explorer rather than a table.

ONE PLACE NAMES THE COMMANDS.  McKdiGraphCommands is the whole vocabulary this
file believes the CLI publishes, as class-side methods returning argv.  Nothing
else in this file builds a graph argv.  If a verb or a flag is spelled
differently in your kdi, the repair is one method, not a search across ten views,
and the Commands tab on McKdiGraph prints the exact argv of every one of them so
a mismatch is visible before you press anything.  A verb this kdi does not have
fails the way every other failure in this explorer does: a non-zero exit, the
backend's own words, and the argv that produced them.

Chunk format: load with fileIn.
"!

Object subclass: #McKdiGraphCommands
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

Object subclass: #McKdiGraph
	instanceVariableNames: 'store seedQuery seedLimit seeds depth maxNodes maxArcs direction relationFilter entityPage entityAnswer snapshot snapshotAnswer result resultAnswer relations pathFrom pathTo'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiEntityPage
	instanceVariableNames: 'graph'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiEntity
	instanceVariableNames: 'graph'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiGraphSnapshot
	instanceVariableNames: 'graph'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiGraphResult
	instanceVariableNames: 'graph kind subject'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiGraphNode
	instanceVariableNames: 'graph passage'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiGraphArc
	instanceVariableNames: 'graph'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiGraphPath
	instanceVariableNames: 'graph'
	classVariableNames: ''
	package: 'MalleableControl'!

Object subclass: #McKdiRelations
	instanceVariableNames: 'store contractsAnswer statsAnswer validationAnswer'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiRelationContract
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiRelationStat
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!


!McKdiGraphCommands class methodsFor: 'documentation'!
writingFlags
	"Flags that would make a command write.  None of them may appear in any
	 argv this class builds."
	^ #('--run' '--write' '--force' '--delete' '--prune' '--rebuild')!

readsOnly
	"Whether every declared verb is a read.  Computed rather than asserted, so
	 the claim in this file's comment is checked by the suite instead of being
	 a sentence someone has to remember to keep true."
	^ McKdiGraphCommands declaredVerbs allSatisfy: [ :row |
		row second noneSatisfy: [ :arg | self writingFlags includes: arg ] ]! !


!McKdiGraphCommands class methodsFor: 'entities'!
entityFind: aQuery
	"Seed search.  The graph is entered by naming something, and the answer is
	 the ranked list of entities that name might mean -- which is a different
	 question from `what is connected to this id', and has to be asked first."
	^ { 'entities'. 'find'. aQuery asString }!

entityShow: anId
	^ { 'entities'. 'show'. anId asString }! !


!McKdiGraphCommands class methodsFor: 'graph'!
snapshotMaxVertices: aVertexBudget maxEdges: anEdgeBudget relations: aRelationCollection
	"The BUDGET preview for the full analytical snapshot.  Seeds and hop depth
	 belong to a traversal over that snapshot and are therefore not accepted by
	 `graph snapshot plan'."
	| args |
	args := OrderedCollection new.
	args add: 'graph'; add: 'snapshot'; add: 'plan'.
	args add: '--max-vertices'; add: aVertexBudget printString.
	args add: '--max-edges'; add: anEdgeBudget printString.
	aRelationCollection do: [ :each | args add: '--relation'; add: each asString ].
	^ args asArray!

neighbors: anId maxHops: aDepth maxVertices: aLimit relations: aRelationCollection direction: aDirection
	| args |
	args := OrderedCollection new.
	args add: 'graph'; add: 'neighbors'; add: anId asString.
	args add: '--max-hops'; add: aDepth printString.
	args add: '--max-vertices'; add: aLimit printString.
	aRelationCollection do: [ :each | args add: '--relation'; add: each asString ].
	aDirection ifNotNil: [ :d | args add: '--direction'; add: d asString ].
	^ args asArray!

pathFrom: aFromId to: aToId maxHops: aDepth maxVertices: aLimit relations: aRelationCollection direction: aDirection
	| args |
	args := OrderedCollection new.
	args add: 'graph'; add: 'path'; add: aFromId asString; add: aToId asString.
	args add: '--max-hops'; add: aDepth printString.
	args add: '--max-vertices'; add: aLimit printString.
	aRelationCollection do: [ :each | args add: '--relation'; add: each asString ].
	aDirection ifNotNil: [ :d | args add: '--direction'; add: d asString ].
	^ args asArray!

traverse: anId maxHops: aDepth limit: aLimit relations: aRelationCollection direction: aDirection
	| args |
	args := OrderedCollection new.
	args add: 'graph'; add: 'traverse'; add: '--root'; add: anId asString.
	args add: '--max-hops'; add: aDepth printString.
	args add: '--limit'; add: aLimit printString.
	aRelationCollection do: [ :each | args add: '--relation'; add: each asString ].
	aDirection ifNotNil: [ :d | args add: '--direction'; add: d asString ].
	^ args asArray! !


!McKdiGraphCommands class methodsFor: 'relations'!
relationContracts
	^ #('graph' 'relation-types')!

relationStats
	^ #('graph' 'stats')!

relationValidate
	"A read: it reports whether the recorded arcs satisfy their contracts, and
	 repairs nothing."
	^ #('graph' 'validate')! !


!McKdiGraphCommands class methodsFor: 'contract'!
declaredVerbs
	"Every command this file will ever run, as { what it answers. argv }.
	 Rendered by McKdiGraph's Commands tab, so the vocabulary can be compared
	 against `kdi --help' without reading any Smalltalk."
	^ {
		{ 'entity seed search'. self entityFind: 'QUERY' }.
		{ 'one entity'. self entityShow: 'ENTITY-ID' }.
		{ 'snapshot budget preview'.
			self snapshotMaxVertices: 200 maxEdges: 400 relations: #() }.
		{ 'neighbours'.
			self neighbors: 'ENTITY-ID' maxHops: 1 maxVertices: 100 relations: #() direction: 'both' }.
		{ 'path between two'.
			self pathFrom: 'FROM-ID' to: 'TO-ID' maxHops: 4 maxVertices: 200 relations: #() direction: 'both' }.
		{ 'traversal'.
			self traverse: 'ENTITY-ID' maxHops: 2 limit: 200 relations: #() direction: 'both' }.
		{ 'relation contracts'. self relationContracts }.
		{ 'relation statistics'. self relationStats }.
		{ 'relation validation'. self relationValidate } }! !


!McKdiGraph class methodsFor: 'instance creation'!
store: aStore
	^ self new setStore: aStore! !


!McKdiGraph methodsFor: 'initialization'!
setStore: aStore
	store := aStore.
	seedQuery := ''.
	seedLimit := 20.
	seeds := OrderedCollection new.
	depth := 2.
	maxNodes := 200.
	maxArcs := 400.
	direction := 'both'.
	relationFilter := OrderedCollection new.
	^ self! !


!McKdiGraph methodsFor: 'accessing'!
store
	^ store!

binding
	^ store binding!

seedQuery
	^ seedQuery ifNil: [ '' ]!

seedQuery: aString
	seedQuery := aString!

seedLimit
	^ seedLimit ifNil: [ 20 ]!

seedLimit: anInteger
	seedLimit := anInteger!

seeds
	"The entity ids every other question in this layer is asked from.  Kept as
	 a list rather than one id because a snapshot budget is a question about a
	 SET of seeds -- one seed and three seeds do not cost the same."
	^ seeds ifNil: [ seeds := OrderedCollection new ]!

seeds: aCollection
	seeds := aCollection asOrderedCollection!

addSeed: anId
	(self seeds includes: anId) ifFalse: [ self seeds add: anId ].
	^ self!

removeSeed: anId
	self seeds remove: anId ifAbsent: [ nil ].
	^ self!

depth
	^ depth ifNil: [ 2 ]!

depth: anInteger
	depth := anInteger!

maxNodes
	^ maxNodes ifNil: [ 200 ]!

maxNodes: anInteger
	maxNodes := anInteger!

maxArcs
	^ maxArcs ifNil: [ 400 ]!

maxArcs: anInteger
	maxArcs := anInteger!

direction
	^ direction ifNil: [ 'both' ]!

direction: aString
	direction := aString!

relationFilter
	"Which relations to follow.  Empty means every relation the store records,
	 which is what makes an unconfigured traversal answer something."
	^ relationFilter ifNil: [ relationFilter := OrderedCollection new ]!

relationFilter: aCollection
	relationFilter := aCollection asOrderedCollection!

pathFrom
	^ pathFrom!

pathFrom: anId
	pathFrom := anId!

pathTo
	^ pathTo!

pathTo: anId
	pathTo := anId!

entityPage
	^ entityPage!

entityAnswer
	^ entityAnswer!

snapshot
	^ snapshot!

snapshotAnswer
	^ snapshotAnswer!

result
	^ result!

resultAnswer
	^ resultAnswer!

firstSeed
	^ self seeds ifEmpty: [ nil ] ifNotEmpty: [ :s | s first ]! !


!McKdiGraph methodsFor: 'entities'!
searchEntities
	"kdi entities find.  A read, and the entry point: you cannot ask what is
	 connected to something until you have said which something."
	| a |
	a := self binding runJson: (McKdiGraphCommands entityFind: self seedQuery).
	entityAnswer := a.
	entityPage := a hasValue
		ifTrue: [ (McKdiEntityPage json: a value answer: a) setGraph: self ]
		ifFalse: [ nil ].
	^ entityPage ifNil: [ a ]!

entities
	^ entityPage ifNil: [ #() ] ifNotNil: [ :p | p entities ]! !


!McKdiGraph methodsFor: 'snapshot'!
previewSnapshot
	"The budget preview.  It estimates the whole analytical snapshot under the
	 selected relation filter and allocation budgets, and builds nothing."
	| a |
	a := self binding runJson: (McKdiGraphCommands
		snapshotMaxVertices: self maxNodes
		maxEdges: self maxArcs
		relations: self relationFilter asArray).
	snapshotAnswer := a.
	snapshot := a hasValue
		ifTrue: [ (McKdiGraphSnapshot json: a value answer: a) setGraph: self ]
		ifFalse: [ nil ].
	^ snapshot ifNil: [ a ]! !


!McKdiGraph methodsFor: 'walking'!
neighborsOf: anId
	^ self
		runResult: (McKdiGraphCommands
			neighbors: anId
			maxHops: self depth
			maxVertices: self maxNodes
			relations: self relationFilter asArray
			direction: self direction)
		kind: 'neighbors'
		subject: anId!

traverseFrom: anId
	^ self
		runResult: (McKdiGraphCommands
			traverse: anId
			maxHops: self depth
			limit: self maxNodes
			relations: self relationFilter asArray
			direction: self direction)
		kind: 'traverse'
		subject: anId!

pathFrom: aFromId to: aToId
	pathFrom := aFromId.
	pathTo := aToId.
	^ self
		runResult: (McKdiGraphCommands
			pathFrom: aFromId
			to: aToId
			maxHops: self depth
			maxVertices: self maxNodes
			relations: self relationFilter asArray
			direction: self direction)
		kind: 'path'
		subject: aFromId asString , ' -> ' , aToId asString!

runResult: anArgv kind: aKind subject: aSubject
	"One place builds every walk result, so the three walks cannot drift into
	 three different failure behaviours."
	| a |
	a := self binding runJson: anArgv.
	resultAnswer := a.
	result := a hasValue
		ifTrue: [ (McKdiGraphResult json: a value answer: a)
			setGraph: self kind: aKind subject: aSubject ]
		ifFalse: [ nil ].
	^ result ifNil: [ a ]!

neighborsOfFirstSeed
	^ self firstSeed ifNil: [ nil ] ifNotNil: [ :id | self neighborsOf: id ]!

traverseFromFirstSeed
	^ self firstSeed ifNil: [ nil ] ifNotNil: [ :id | self traverseFrom: id ]!

pathBetweenSeeds
	"The path between the first two seeds, or between the two explicitly named
	 endpoints when they are set."
	| a b |
	a := pathFrom ifNil: [ self firstSeed ].
	b := pathTo ifNil: [ self seeds size >= 2 ifTrue: [ self seeds second ] ifFalse: [ nil ] ].
	(a isNil or: [ b isNil ]) ifTrue: [ ^ nil ].
	^ self pathFrom: a to: b! !


!McKdiGraph methodsFor: 'relations'!
relations
	^ relations ifNil: [ relations := McKdiRelations store: store ]! !


!McKdiGraph methodsFor: 'passages'!
passageFor: aPassageId
	"The forward walk out of the graph: a node or an arc names a passage id,
	 and a passage id is an occurrence id, so one read resolves it to the exact
	 citable passage with its grounding."
	| a |
	aPassageId ifNil: [ ^ nil ].
	a := self binding runJson: { 'passage'. 'show'. aPassageId asString }.
	^ a hasValue
		ifTrue: [ McKdiPassage json: a value answer: a ]
		ifFalse: [ a ]! !


!McKdiGraph methodsFor: 'rows'!
settingRows
	^ {
		{ 'seed query'. (self seedQuery isEmpty ifTrue: [ '(none)' ] ifFalse: [ self seedQuery ]).
			'LOOKUP -- returns every exact-name candidate' }.
		{ 'seeds'. self seeds ifEmpty: [ '(none -- search first)' ]
			ifNotEmpty: [ :s | ', ' join: (s collect: [ :e | e asString ]) ].
			'where every walk starts' }.
		{ 'depth'. self depth. 'hops, and the path max-depth' }.
		{ 'max nodes'. self maxNodes. 'BUDGET -- also the walk limit' }.
		{ 'max arcs'. self maxArcs. 'BUDGET' }.
		{ 'direction'. self direction. 'out | in | both' }.
		{ 'relations followed'. self relationFilter ifEmpty: [ '(all)' ]
			ifNotEmpty: [ :r | ', ' join: (r collect: [ :e | e asString ]) ].
			'FILTER -- exact' }.
		{ 'writes'. 'nothing -- every command in this layer is a read'. 'guarantee' } }!

formRows
	^ {
		{ 'seed query'. self seedQuery asString.
			[ :s | seedQuery := s trimBoth ] }.
		{ 'seeds -- entity ids, space separated'. ' ' join: self seeds.
			[ :s | self seeds: (s substrings: ' ') ] }.
		{ 'depth'. self depth printString.
			[ :s | depth := s asInteger ifNil: [ depth ] ] }.
		{ 'max nodes'. self maxNodes printString.
			[ :s | maxNodes := s asInteger ifNil: [ maxNodes ] ] }.
		{ 'max arcs'. self maxArcs printString.
			[ :s | maxArcs := s asInteger ifNil: [ maxArcs ] ] }.
		{ 'direction -- out / in / both'. self direction asString.
			[ :s | direction := s trimBoth ifEmpty: [ 'both' ] ] }.
		{ 'relations followed -- space separated, empty means all'.
			' ' join: self relationFilter.
			[ :s | self relationFilter: (s substrings: ' ') ] } }! !


!McKdiGraph methodsFor: 'printing'!
printOn: aStream
	aStream
		nextPutAll: 'McKdiGraph(';
		nextPutAll: self seeds size printString;
		nextPutAll: ' seed(s), depth ';
		nextPutAll: self depth printString;
		nextPut: $)! !


!McKdiGraph methodsFor: 'views'!
gtSettingsFor: aView
	<gtView>
	^ aView columnedList
		title: 'Graph';
		priority: 10;
		items: [ self settingRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ];
		column: 'kind' text: [ :each | each third ] width: 300!

gtEntitiesFor: aView
	<gtView>
	"One tab, three states, for the reason the slice recipe gives: two views
	 claiming one title can both be non-empty, and then the tab appears twice."
	(entityAnswer notNil and: [ entityPage isNil ]) ifTrue: [
		^ aView textEditor
			title: 'Seed entities';
			priority: 20;
			text: [ entityAnswer failureReport: 'The entity search did not run.' ] ].
	entityPage ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Seed entities';
		priority: 20;
		object: [ entityPage ];
		view: #gtEntitiesFor:!

gtSnapshotFor: aView
	<gtView>
	(snapshotAnswer notNil and: [ snapshot isNil ]) ifTrue: [
		^ aView textEditor
			title: 'Snapshot budget';
			priority: 30;
			text: [ snapshotAnswer failureReport: 'The snapshot preview did not run.' ] ].
	snapshot ifNil: [ ^ aView empty ].
	^ aView columnedList
		title: 'Snapshot budget';
		priority: 30;
		items: [ snapshot budgetRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ];
		send: [ :each | snapshot ]!

gtResultFor: aView
	<gtView>
	(resultAnswer notNil and: [ result isNil ]) ifTrue: [
		^ aView textEditor
			title: 'Walk';
			priority: 40;
			text: [ resultAnswer failureReport: 'The walk did not run.' ] ].
	result ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Walk';
		priority: 40;
		object: [ result ];
		view: #gtNodesFor:!

gtRelationsFor: aView
	<gtView>
	^ aView columnedList
		title: 'Relations';
		priority: 50;
		items: [ self relations summaryRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ];
		send: [ :each | self relations ]!

gtCommandsFor: aView
	<gtView>
	"The whole vocabulary, printed.  Comparing this against `kdi --help' is the
	 supported way to find out that a verb moved, and it costs no subprocess."
	^ aView columnedList
		title: 'Commands';
		priority: 90;
		items: [ McKdiGraphCommands declaredVerbs ];
		column: 'answers' text: [ :each | each first ] width: 220;
		column: 'argv (every one a read)' text: [ :each | ' ' join: each second ]! !


!McKdiGraph methodsFor: 'actions'!
gtEditActionFor: anAction
	<gtAction>
	^ anAction dropdown
		label: 'Edit graph query';
		priority: 5;
		tooltip: 'Seed query, seeds, depth, budgets, direction and the relations followed';
		content: [ :anElement |
			"The recipe owns the generic label/editor/apply-button builder.  It
			 uses nothing of the recipe but the store, so borrowing it here is
			 cheaper than a second copy that could drift from it."
			store recipe
				formElementFrom: anElement
				rows: self formRows
				label: 'Apply and search seeds (writes nothing)'
				then: [ self searchEntities ] ]!

gtSearchActionFor: anAction
	<gtAction>
	^ anAction button
		label: (store actionLabel: 'Search seeds (writes nothing)');
		priority: 10;
		tooltip: 'kdi entities find: the stored entities this display name might mean';
		action: [ :aButton |
			store runOffUi: [ self searchEntities ] from: aButton labelled: 'Search seeds' ]!

gtSnapshotActionFor: anAction
	<gtAction>
	^ anAction button
		label: (store actionLabel: 'Preview snapshot budget (writes nothing)');
		priority: 20;
		tooltip: 'kdi graph snapshot plan: estimate the full analytical snapshot before allocation';
		action: [ :aButton |
			store runOffUi: [ self previewSnapshot ] from: aButton labelled: 'Snapshot budget' ]!

gtNeighborsActionFor: anAction
	<gtAction>
	self firstSeed ifNil: [ ^ anAction noAction ].
	^ anAction button
		label: (store actionLabel: 'Neighbours of the first seed');
		priority: 30;
		tooltip: 'kdi graph neighbors: one hop out, under the direction and relation filter';
		action: [ :aButton |
			store runOffUi: [ self neighborsOfFirstSeed ] from: aButton labelled: 'Neighbours' ]!

gtTraverseActionFor: anAction
	<gtAction>
	self firstSeed ifNil: [ ^ anAction noAction ].
	^ anAction button
		label: (store actionLabel: 'Traverse from the first seed');
		priority: 40;
		tooltip: 'kdi graph traverse: every node within depth, bounded by max nodes';
		action: [ :aButton |
			store runOffUi: [ self traverseFromFirstSeed ] from: aButton labelled: 'Traverse' ]!

gtPathActionFor: anAction
	<gtAction>
	"Offered only with two endpoints to join, because a path button that always
	 fails teaches nothing about why."
	self seeds size >= 2 ifFalse: [ ^ anAction noAction ].
	^ anAction button
		label: (store actionLabel: 'Path between the first two seeds');
		priority: 50;
		tooltip: 'kdi graph path: the arcs joining two entities, each one naming the relation that justifies it';
		action: [ :aButton |
			store runOffUi: [ self pathBetweenSeeds ] from: aButton labelled: 'Path' ]!

gtRelationsActionFor: anAction
	<gtAction>
	^ anAction button
		label: (store actionLabel: 'Read the relation catalogue');
		priority: 60;
		tooltip: 'kdi graph relation-types, stats and validate: contracts, coverage and integrity';
		action: [ :aButton |
			store runOffUi: [ self relations loadAll ] from: aButton labelled: 'Relations' ]! !


!McKdiEntityPage methodsFor: 'accessing'!
setGraph: aGraph
	graph := aGraph.
	^ self!

graph
	^ graph!

entityRows
	"Tolerant of the current `entities find' candidates object, older keyed
	 answers, and a bare array.
	 of entities.  Both are answers a search could reasonably give, and losing
	 the table to the difference would be the worst of the two outcomes."
	(json isKindOf: Array) ifTrue: [ ^ json ].
	^ ((self at: 'candidates') ifNil: [
		(self at: 'entities') ifNil: [ (self at: 'results') ifNil: [ #() ] ] ])!

entities
	^ self entityRows collect: [ :each |
		(McKdiEntity json: each answer: answer) setGraph: graph ]!

total
	^ (self at: 'candidate_count') ifNil: [
		(self at: 'total') ifNil: [ self entityRows size ] ]!

limit
	^ self at: 'limit'!

isTruncated
	| budget |
	(self at: 'truncated') = true ifTrue: [ ^ true ].
	(self at: 'exhausted') ifNotNil: [ ^ true ].
	budget := self at: 'budget'.
	^ budget notNil and: [ (budget at: 'exhausted' ifAbsent: [ nil ]) notNil ]!

boundDescription
	^ self entityRows size printString, ' of ', self total printString, ' shown',
		(self isTruncated ifTrue: [ ' (truncated)' ] ifFalse: [ '' ])! !


!McKdiEntityPage methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiEntityPage(', self boundDescription, ')'! !


!McKdiEntityPage methodsFor: 'views'!
gtEntitiesFor: aView
	<gtView>
	^ aView columnedList
		title: 'Seed entities';
		priority: 10;
		items: [ self entities ];
		column: 'rank' text: [ :each | each rankDescription ] width: 60;
		column: 'score' text: [ :each | each scoreDescription ] width: 90;
		column: 'kind' text: [ :each | each kind asString ] width: 130;
		column: 'entity' text: [ :each | each label asString ];
		column: 'passages' text: [ :each | each passageIds size asString ] width: 90;
		send: [ :each | each ]!

gtBoundFor: aView
	<gtView>
	^ aView columnedList
		title: 'Bound';
		priority: 60;
		items: [ {
			{ 'shown'. self boundDescription }.
			{ 'total'. self total }.
			{ 'limit'. self limit } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]! !


!McKdiEntity methodsFor: 'accessing'!
setGraph: aGraph
	graph := aGraph.
	^ self!

graph
	^ graph!

id
	^ (self at: 'id') ifNil: [ self at: 'entity_id' ]!

kind
	^ (self at: 'kind') ifNil: [ (self at: 'entity_type') ifNil: [ '--' ] ]!

name
	^ (self at: 'display_name') ifNil: [
		(self at: 'name') ifNil: [ self at: 'label' ] ]!

label
	^ self name ifNil: [ self id ifNil: [ 'entity' ] ]!

aliases
	^ (self at: 'aliases') ifNil: [ #() ]!

degree
	^ self at: 'degree'!

score
	^ (self at: 'score') ifNil: [ self at: 'relevance' ]!

scoreDescription
	^ self score ifNil: [ '--' ] ifNotNil: [ :s | s asFloat printShowingDecimalPlaces: 4 ]!

rank
	^ self at: 'rank'!

rankDescription
	"1-based, to agree with every other rank column in this explorer.  The
	 payloads are 0-based and a table that showed both would be lying about one."
	^ self rank ifNil: [ '--' ] ifNotNil: [ :r | (r + 1) printString ]!

sourceUris
	^ (self at: 'source_uris') ifNil: [ #() ]!

passageIds
	"The passages this entity was read out of.  Named for the public model:
	 the payload key is still occurrence_ids, because a passage id IS an
	 occurrence id."
	^ (self at: 'passage_ids')
		ifNil: [ (self at: 'occurrence_ids') ifNil: [ #() ] ]!

occurrenceIds
	"Deprecated -- use passageIds.  Kept so nothing that was written against
	 the storage vocabulary breaks."
	^ self passageIds!

passageFor: aPassageId
	"Answers the bare id when there is no graph behind this entity, for the
	 reason McKdiGraphArc gives: a missing walk is worth much less than a
	 walkback."
	^ graph ifNil: [ aPassageId ] ifNotNil: [ :g | g passageFor: aPassageId ]!

passages
	^ self passageIds collect: [ :each | self passageFor: each ]!

entityRows
	^ {
		{ 'id'. self id }.
		{ 'kind'. self kind }.
		{ 'name'. self name }.
		{ 'aliases'. ', ' join: (self aliases collect: [ :e | e asString ]) }.
		{ 'degree'. self degree }.
		{ 'rank'. self rankDescription }.
		{ 'score'. self scoreDescription }.
		{ 'passages'. self passageIds size }.
		{ 'sources'. ', ' join: (self sourceUris collect: [ :e | e asString ]) } }! !


!McKdiEntity methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiEntity(', self kind asString, ' ', self label asString, ')'! !


!McKdiEntity methodsFor: 'views'!
gtEntityFor: aView
	<gtView>
	^ aView columnedList
		title: 'Entity';
		priority: 10;
		items: [ self entityRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtPassagesFor: aView
	<gtView>
	"The forward walk.  Clicking a row runs one `kdi passage show' and lands on
	 the passage, with its grounding -- the same screen a context block member
	 reaches."
	self passageIds ifEmpty: [ ^ aView empty ].
	^ aView columnedList
		title: 'Passages';
		priority: 20;
		items: [ self passageIds ];
		column: 'passage' text: [ :each | each asString ];
		send: [ :each | self passageFor: each ]! !


!McKdiEntity methodsFor: 'actions'!
gtSeedActionFor: anAction
	<gtAction>
	graph ifNil: [ ^ anAction noAction ].
	^ anAction button
		label: 'Use as seed';
		priority: 10;
		tooltip: 'Add this entity to the graph seeds used by neighbours, path, traversal and graph-ranked slices';
		action: [ :aButton | graph addSeed: self id ]!

gtNeighborsActionFor: anAction
	<gtAction>
	graph ifNil: [ ^ anAction noAction ].
	^ anAction button
		label: (graph store actionLabel: 'Neighbours (writes nothing)');
		priority: 20;
		tooltip: 'kdi graph neighbors on this entity';
		action: [ :aButton |
			graph store
				runOffUi: [ graph neighborsOf: self id ]
				from: aButton labelled: 'Neighbours' ]!

gtSliceSeedActionFor: anAction
	<gtAction>
	"The join between the two layers.  Finding the entity is one question and
	 ranking context blocks around it is another, and until this button existed
	 the only way across was to copy an id by eye."
	graph ifNil: [ ^ anAction noAction ].
	^ anAction button
		label: (graph store actionLabel: 'Seed the slice with this (replans)');
		priority: 30;
		tooltip: 'Add this entity to the slice recipe as a --graph-seed and replan. The graph aspect ranks; it excludes nothing';
		action: [ :aButton |
			graph store
				runOffUi: [ graph store recipe addGraphSeed: self id ]
				from: aButton labelled: 'Seed the slice' ]! !


!McKdiGraphSnapshot methodsFor: 'accessing'!
setGraph: aGraph
	graph := aGraph.
	^ self!

graph
	^ graph!

nodeBudget
	| budget |
	budget := self at: 'budget'.
	^ budget
		ifNil: [ graph ifNil: [ nil ] ifNotNil: [ :g | g maxNodes ] ]
		ifNotNil: [ :b | b at: 'max_vertices' ifAbsent: [ nil ] ]!

arcBudget
	| budget |
	budget := self at: 'budget'.
	^ budget
		ifNil: [ graph ifNil: [ nil ] ifNotNil: [ :g | g maxArcs ] ]
		ifNotNil: [ :b | b at: 'max_edges' ifAbsent: [ nil ] ]!

nodesReachable
	| estimate |
	estimate := self at: 'estimate'.
	^ estimate ifNil: [ 0 ] ifNotNil: [ :e | e at: 'vertices' ifAbsent: [ 0 ] ]!

arcsReachable
	| estimate |
	estimate := self at: 'estimate'.
	^ estimate ifNil: [ 0 ] ifNotNil: [ :e | e at: 'edges' ifAbsent: [ 0 ] ]!

nodesAdmitted
	^ self nodeBudget ifNil: [ self nodesReachable ] ifNotNil: [ :n |
		self nodesReachable min: n ]!

arcsAdmitted
	^ self arcBudget ifNil: [ self arcsReachable ] ifNotNil: [ :n |
		self arcsReachable min: n ]!

isTruncated
	"A snapshot plan refuses an over-budget build; it never produces a partial
	 graph.  Keep the old selector because views used it, but report refusal."
	^ (self at: 'within_budget') = false!

seedIds
	^ (self at: 'seeds') ifNil: [ graph ifNil: [ #() ] ifNotNil: [ :g | g seeds asArray ] ]!

depth
	^ self at: 'depth'!

byteEstimate
	| estimate |
	estimate := self at: 'estimate'.
	^ estimate ifNil: [ nil ] ifNotNil: [ :e | e at: 'bytes' ifAbsent: [ nil ] ]!

relationCounts
	"The plan estimates edges by provider.  These are upper-bound inputs to the
	 budget calculation, not relation-level traversal counts."
	| d |
	d := (self at: 'estimate')
		ifNil: [ Dictionary new ]
		ifNotNil: [ :e | e at: 'edges_by_provider' ifAbsent: [ Dictionary new ] ].
	(d isKindOf: Dictionary) ifFalse: [ ^ #() ].
	^ ((d keys asSortedCollection: [ :a :b | a <= b ]) asArray)
		collect: [ :k | { k. d at: k } ]!

notes
	^ ((self at: 'notes') ifNil: [ #() ]),
		((self at: 'refusals') ifNil: [ #() ])!

didWrite
	"Asserted, not assumed.  The preview verb is --plan; a payload claiming
	 otherwise is worth seeing on the screen rather than trusting the flag."
	^ (self at: 'wrote') = true!

verdict
	^ self isTruncated
		ifTrue: [ 'REFUSED -- over budget; no partial snapshot was built' ]
		ifFalse: [ 'FITS -- the snapshot is within budget' ]!

budgetRows
	^ {
		{ 'verdict'. self verdict }.
		{ 'estimated vertices'. self nodesReachable }.
		{ 'vertex budget'. self nodeBudget }.
		{ 'estimated edges'. self arcsReachable }.
		{ 'edge budget'. self arcBudget }.
		{ 'estimated bytes'. self byteEstimate }.
		{ 'wrote'. self didWrite ifTrue: [ 'SOMETHING -- unexpected for a preview' ]
			ifFalse: [ 'nothing -- graph snapshot plan is read-only' ] } }!

summaryLine
	^ self nodesAdmitted printString, ' of ', self nodesReachable printString,
		' nodes, ', self arcsAdmitted printString, ' of ',
		self arcsReachable printString, ' arcs'! !


!McKdiGraphSnapshot methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiGraphSnapshot(', self summaryLine, ')'! !


!McKdiGraphSnapshot methodsFor: 'views'!
gtBudgetFor: aView
	<gtView>
	^ aView columnedList
		title: 'Budget';
		priority: 10;
		items: [ self budgetRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtRelationCountsFor: aView
	<gtView>
	self relationCounts ifEmpty: [ ^ aView empty ].
	^ aView columnedList
		title: 'By relation';
		priority: 20;
		items: [ self relationCounts ];
		column: 'relation' text: [ :each | each first asString ];
		column: 'admitted' text: [ :each | each second asString ] width: 110!

gtNotesFor: aView
	<gtView>
	self notes ifEmpty: [ ^ aView empty ].
	^ aView columnedList
		title: 'Notes';
		priority: 30;
		items: [ self notes ];
		column: 'note' text: [ :each | each asString ]! !


!McKdiGraphResult methodsFor: 'accessing'!
setGraph: aGraph kind: aKind subject: aSubject
	graph := aGraph.
	kind := aKind.
	subject := aSubject.
	^ self!

graph
	^ graph!

kind
	^ kind!

subject
	^ subject!

nodeRows
	^ (self at: 'nodes') ifNil: [ #() ]!

arcRows
	^ ((self at: 'arcs') ifNil: [ (self at: 'edges') ifNil: [ #() ] ])!

nodes
	^ self nodeRows collect: [ :each |
		(McKdiGraphNode json: each answer: answer) setGraph: graph ]!

arcs
	^ self arcRows collect: [ :each |
		(McKdiGraphArc json: each answer: answer) setGraph: graph ]!

paths
	| rows |
	rows := self at: 'paths'.
	(rows isNil and: [ kind = 'path' and: [ (self at: 'found') = true ] ])
		ifTrue: [ rows := { json } ].
	^ (rows ifNil: [ #() ]) collect: [ :each |
		(McKdiGraphPath json: each answer: answer) setGraph: graph ]!

isTruncated
	^ (self at: 'truncated') = true!

summaryLine
	^ kind asString, ' from ', subject asString, ': ',
		self nodeRows size printString, ' node(s), ',
		self arcRows size printString, ' arc(s)',
		(self isTruncated ifTrue: [ ' (truncated)' ] ifFalse: [ '' ])! !


!McKdiGraphResult methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiGraphResult(', self summaryLine, ')'! !


!McKdiGraphResult methodsFor: 'views'!
gtNodesFor: aView
	<gtView>
	^ aView columnedList
		title: 'Nodes';
		priority: 10;
		items: [ self nodes ];
		column: 'hops' text: [ :each | each distanceDescription ] width: 60;
		column: 'kind' text: [ :each | each kind asString ] width: 130;
		column: 'node' text: [ :each | each label asString ];
		column: 'passages' text: [ :each | each passageIds size asString ] width: 90;
		send: [ :each | each ]!

gtArcsFor: aView
	<gtView>
	^ aView columnedList
		title: 'Arcs';
		priority: 20;
		items: [ self arcs ];
		column: 'relation' text: [ :each | each relation asString ] width: 180;
		column: 'from' text: [ :each | each fromId asString ];
		column: 'to' text: [ :each | each toId asString ];
		column: 'weight' text: [ :each | each weightDescription ] width: 80;
		send: [ :each | each ]!

gtPathsFor: aView
	<gtView>
	self paths ifEmpty: [ ^ aView empty ].
	^ aView columnedList
		title: 'Paths';
		priority: 30;
		items: [ self paths ];
		column: 'hops' text: [ :each | each length asString ] width: 60;
		column: 'path' text: [ :each | each description ];
		send: [ :each | each ]!

gtWalkFor: aView
	<gtView>
	^ aView columnedList
		title: 'Walk';
		priority: 40;
		items: [ {
			{ 'kind'. kind }.
			{ 'subject'. subject }.
			{ 'nodes'. self nodeRows size }.
			{ 'arcs'. self arcRows size }.
			{ 'paths'. self paths size }.
			{ 'truncated'. self isTruncated }.
			{ 'wrote'. 'nothing -- a read' } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]! !


!McKdiGraphNode methodsFor: 'accessing'!
setGraph: aGraph
	graph := aGraph.
	^ self!

graph
	^ graph!

id
	^ (self at: 'id') ifNil: [ (self at: 'node_id') ifNil: [ self at: 'entity_id' ] ]!

kind
	^ (self at: 'kind') ifNil: [ (self at: 'node_type') ifNil: [ '--' ] ]!

name
	^ (self at: 'name') ifNil: [ self at: 'label' ]!

label
	^ self name ifNil: [ self id ifNil: [ 'node' ] ]!

distance
	^ (self at: 'hop') ifNil: [
		(self at: 'distance') ifNil: [ self at: 'hops' ] ]!

distanceDescription
	^ self distance ifNil: [ '--' ] ifNotNil: [ :d | d asString ]!

degree
	^ self at: 'degree'!

sourceUri
	^ self at: 'source_uri'!

passageIds
	"A node standing for a passage carries its own id here as well, so the walk
	 out of the graph is the same one line whether the node IS a passage or
	 merely cites some."
	| direct |
	direct := (self at: 'passage_ids') ifNil: [ self at: 'occurrence_ids' ].
	direct ifNotNil: [ ^ direct ].
	^ self isPassageNode
		ifTrue: [ self id ifNil: [ #() ] ifNotNil: [ :i | { i } ] ]
		ifFalse: [ #() ]!

occurrenceIds
	"Deprecated -- use passageIds."
	^ self passageIds!

isPassageNode
	"Occurrence is the storage word and passage is the public one; a payload
	 may use either, and both mean the same node."
	^ #('passage' 'occurrence') includes: self kind asString asLowercase!

passageFor: aPassageId
	^ graph ifNil: [ aPassageId ] ifNotNil: [ :g | g passageFor: aPassageId ]!

passages
	^ self passageIds collect: [ :each | self passageFor: each ]!

nodeRows
	^ {
		{ 'id'. self id }.
		{ 'kind'. self kind }.
		{ 'name'. self name }.
		{ 'hops from the seed'. self distanceDescription }.
		{ 'degree'. self degree }.
		{ 'source'. self sourceUri }.
		{ 'passages'. self passageIds size }.
		{ 'is a passage node'. self isPassageNode } }! !


!McKdiGraphNode methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiGraphNode(', self kind asString, ' ', self label asString, ')'! !


!McKdiGraphNode methodsFor: 'views'!
gtNodeFor: aView
	<gtView>
	^ aView columnedList
		title: 'Node';
		priority: 10;
		items: [ self nodeRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtPassagesFor: aView
	<gtView>
	"Where the graph rejoins the evidence.  A node that stands for a passage
	 resolves to the passage itself, and from there to the exact source
	 characters -- so a claim read off an arc can be checked against what was
	 actually written."
	self passageIds ifEmpty: [ ^ aView empty ].
	^ aView columnedList
		title: 'Passages';
		priority: 20;
		items: [ self passageIds ];
		column: 'passage' text: [ :each | each asString ];
		send: [ :each | self passageFor: each ]!

gtGroundingFor: aView
	<gtView>
	"The first passage inline, because a passage node has exactly one and
	 making it a click away buys nothing."
	self isPassageNode ifFalse: [ ^ aView empty ].
	passage ifNil: [ passage := self passageFor: self id ].
	(passage isKindOf: McKdiPassage) ifFalse: [ ^ aView empty ].
	^ aView forward
		title: 'Grounding';
		priority: 15;
		object: [ passage ];
		view: #gtGroundingFor:! !


!McKdiGraphNode methodsFor: 'actions'!
gtNeighborsActionFor: anAction
	<gtAction>
	graph ifNil: [ ^ anAction noAction ].
	^ anAction button
		label: (graph store actionLabel: 'Neighbours (writes nothing)');
		priority: 10;
		tooltip: 'kdi graph neighbors from this node';
		action: [ :aButton |
			graph store
				runOffUi: [ graph neighborsOf: self id ]
				from: aButton labelled: 'Neighbours' ]! !


!McKdiGraphArc methodsFor: 'accessing'!
setGraph: aGraph
	graph := aGraph.
	^ self!

graph
	^ graph!

relation
	^ (self at: 'relation_type') ifNil: [
		(self at: 'relation') ifNil: [ (self at: 'predicate') ifNil: [ '--' ] ] ]!

endpointAt: aKey legacy: aLegacyKey
	| value kind id |
	value := (self at: aKey) ifNil: [ self at: aLegacyKey ].
	(value isKindOf: Dictionary) ifFalse: [ ^ value ].
	kind := value at: 'kind' ifAbsent: [ nil ].
	id := value at: 'id' ifAbsent: [ nil ].
	^ kind ifNil: [ id ] ifNotNil: [ :k |
		id ifNil: [ k ] ifNotNil: [ :i | k asString, ':', i asString ] ]!

fromId
	^ (self endpointAt: 'source' legacy: 'from') ifNil: [
		(self at: 'from_id') ifNil: [ self at: 'subject_id' ] ]!

toId
	^ (self endpointAt: 'target' legacy: 'to') ifNil: [
		(self at: 'to_id') ifNil: [ self at: 'object_id' ] ]!

direction
	^ self at: 'direction'!

weight
	^ (self at: 'weight') ifNil: [ self at: 'confidence' ]!

weightDescription
	^ self weight ifNil: [ '--' ] ifNotNil: [ :w | w asFloat printShowingDecimalPlaces: 3 ]!

passageIds
	"The evidence for the arc.  An arc with no passage behind it is an
	 assertion, and the difference is worth a column."
	| direct evidence |
	direct := (self at: 'passage_ids') ifNil: [ self at: 'occurrence_ids' ].
	direct ifNotNil: [ ^ direct ].
	evidence := (self at: 'evidence') ifNil: [ #() ].
	^ evidence
		select: [ :each | (each isKindOf: Dictionary)
			and: [ (each at: 'kind' ifAbsent: [ '' ]) = 'occurrence' ] ]
		thenCollect: [ :each | each at: 'id' ]!

occurrenceIds
	"Deprecated -- use passageIds."
	^ self passageIds!

passages
	^ self passageIds collect: [ :each | self passageFor: each ]!

passageFor: aPassageId
	"An arc reached from a slice contribution may have no graph behind it -- the
	 contribution was built from a plan whose recipe has no store in a test, or
	 from a coverage row that never ran.  Answering the bare id is a worse
	 answer than the passage and a much better one than a walkback."
	^ graph ifNil: [ aPassageId ] ifNotNil: [ :g | g passageFor: aPassageId ]!

isGrounded
	^ self passageIds notEmpty!

description
	^ self fromId asString, ' -[', self relation asString, ']-> ', self toId asString!

arcRows
	^ {
		{ 'relation'. self relation }.
		{ 'from'. self fromId }.
		{ 'to'. self toId }.
		{ 'direction'. self direction }.
		{ 'weight'. self weightDescription }.
		{ 'grounded'. self isGrounded
			ifTrue: [ self passageIds size printString, ' passage(s) behind it' ]
			ifFalse: [ 'NO -- no passage is recorded for this arc' ] } }! !


!McKdiGraphArc methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiGraphArc(', self description, ')'! !


!McKdiGraphArc methodsFor: 'views'!
gtArcFor: aView
	<gtView>
	^ aView columnedList
		title: 'Arc';
		priority: 10;
		items: [ self arcRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtPassagesFor: aView
	<gtView>
	self passageIds ifEmpty: [ ^ aView empty ].
	^ aView columnedList
		title: 'Passages';
		priority: 20;
		items: [ self passageIds ];
		column: 'passage' text: [ :each | each asString ];
		send: [ :each | self passageFor: each ]! !


!McKdiGraphPath methodsFor: 'accessing'!
setGraph: aGraph
	graph := aGraph.
	^ self!

graph
	^ graph!

arcRows
	^ ((self at: 'arcs') ifNil: [ (self at: 'edges') ifNil: [ #() ] ])!

arcs
	^ self arcRows collect: [ :each |
		(McKdiGraphArc json: each answer: answer) setGraph: graph ]!

length
	^ (self at: 'length') ifNil: [ self arcRows size ]!

weight
	^ self at: 'weight'!

fromId
	^ (self at: 'from') ifNil: [ self arcs ifEmpty: [ nil ] ifNotEmpty: [ :a | a first fromId ] ]!

toId
	^ (self at: 'to') ifNil: [ self arcs ifEmpty: [ nil ] ifNotEmpty: [ :a | a last toId ] ]!

description
	"The whole chain in one line, each hop naming the relation that justifies
	 it.  A path rendered as endpoints alone says a connection exists without
	 saying what it is, which is the least useful true thing it could say."
	| arcs |
	arcs := self arcs.
	arcs ifEmpty: [ ^ self fromId asString, ' -> ', self toId asString ].
	^ String streamContents: [ :s |
		s nextPutAll: arcs first fromId asString.
		arcs do: [ :each |
			s nextPutAll: ' -['; nextPutAll: each relation asString; nextPutAll: ']-> '.
			s nextPutAll: each toId asString ] ]! !


!McKdiGraphPath methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiGraphPath(', self description, ')'! !


!McKdiGraphPath methodsFor: 'views'!
gtArcsFor: aView
	<gtView>
	^ aView columnedList
		title: 'Arcs';
		priority: 10;
		items: [ self arcs ];
		column: 'relation' text: [ :each | each relation asString ] width: 180;
		column: 'from' text: [ :each | each fromId asString ];
		column: 'to' text: [ :each | each toId asString ];
		column: 'grounded' text: [ :each | each isGrounded asString ] width: 90;
		send: [ :each | each ]!

gtPathFor: aView
	<gtView>
	^ aView columnedList
		title: 'Path';
		priority: 20;
		items: [ {
			{ 'from'. self fromId }.
			{ 'to'. self toId }.
			{ 'hops'. self length }.
			{ 'weight'. self weight }.
			{ 'chain'. self description } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]! !


!McKdiRelations class methodsFor: 'instance creation'!
store: aStore
	^ self new setStore: aStore! !


!McKdiRelations methodsFor: 'initialization'!
setStore: aStore
	store := aStore.
	^ self! !


!McKdiRelations methodsFor: 'accessing'!
store
	^ store!

binding
	^ store binding!

contractsAnswer
	^ contractsAnswer ifNil: [ self loadContracts ]!

statsAnswer
	^ statsAnswer ifNil: [ self loadStats ]!

validationAnswer
	^ validationAnswer ifNil: [ self loadValidation ]! !


!McKdiRelations methodsFor: 'loading'!
loadContracts
	contractsAnswer := self binding runJson: McKdiGraphCommands relationContracts.
	^ contractsAnswer!

loadStats
	statsAnswer := self binding runJson: McKdiGraphCommands relationStats.
	^ statsAnswer!

loadValidation
	validationAnswer := self binding runJson: McKdiGraphCommands relationValidate.
	^ validationAnswer!

loadAll
	"All three in one press.  They answer three different questions about the
	 same thing -- what a relation is allowed to be, how much of it there is,
	 and whether what is recorded satisfies the first -- and reading one without
	 the others invites a conclusion the other two would refuse."
	self loadContracts.
	self loadStats.
	self loadValidation.
	^ self! !


!McKdiRelations methodsFor: 'reading'!
rowsFrom: anAnswer key: aKey
	"Tolerant of both shapes again: a bare array, or an object keyed by aKey."
	anAnswer hasValue ifFalse: [ ^ #() ].
	(anAnswer value isKindOf: Array) ifTrue: [ ^ anAnswer value ].
	^ (anAnswer valueAt: aKey) ifNil: [ #() ]!

contracts
	^ (self rowsFrom: self contractsAnswer key: 'contracts')
		collect: [ :each | McKdiRelationContract json: each answer: contractsAnswer ]!

stats
	| edges |
	self statsAnswer hasValue ifFalse: [ ^ #() ].
	edges := self statsAnswer valueAt: 'edges'.
	(edges isKindOf: Dictionary) ifFalse: [ ^ #() ].
	^ edges associations collect: [ :each |
		| row |
		row := Dictionary new.
		row at: 'name' put: each key.
		row at: 'count' put: each value.
		McKdiRelationStat json: row answer: statsAnswer ]!

issues
	^ (self rowsFrom: self validationAnswer key: 'defects')!

isValid
	^ (self validationAnswer valueAt: 'ok') = true!

verdict
	"Not run is a third answer, and it is not the same as invalid -- the same
	 distinction the QC audit makes."
	self validationAnswer hasValue ifFalse: [ ^ 'NOT RUN' ].
	^ self isValid ifTrue: [ 'VALID' ] ifFalse: [ 'INVALID' ]!

arcTotal
	^ self stats inject: 0 into: [ :sum :each | sum + (each count ifNil: [ 0 ]) ]!

summaryRows
	^ {
		{ 'contracts'. self contracts size }.
		{ 'relations with statistics'. self stats size }.
		{ 'arcs recorded'. self arcTotal }.
		{ 'validation'. self verdict }.
		{ 'issues'. self issues size }.
		{ 'wrote'. 'nothing -- three reads' } }! !


!McKdiRelations methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiRelations(', self contracts size printString,
		' contract(s), ', self verdict, ')'! !


!McKdiRelations methodsFor: 'views'!
gtContractsFor: aView
	<gtView>
	self contractsAnswer hasValue ifFalse: [
		^ aView textEditor
			title: 'Contracts';
			priority: 10;
			text: [ contractsAnswer failureReport: 'The relation contracts were not read.' ] ].
	^ aView columnedList
		title: 'Contracts';
		priority: 10;
		items: [ self contracts ];
		column: 'relation' text: [ :each | each name asString ] width: 200;
		column: 'from' text: [ :each | each domainDescription ] width: 150;
		column: 'to' text: [ :each | each rangeDescription ] width: 150;
		column: 'cardinality' text: [ :each | each cardinality asString ] width: 110;
		column: 'what it asserts' text: [ :each | each description asString ];
		send: [ :each | each ]!

gtStatsFor: aView
	<gtView>
	self statsAnswer hasValue ifFalse: [
		^ aView textEditor
			title: 'Statistics';
			priority: 20;
			text: [ statsAnswer failureReport: 'The relation statistics were not read.' ] ].
	^ aView columnedList
		title: 'Statistics';
		priority: 20;
		items: [ self stats ];
		column: 'relation' text: [ :each | each name asString ] width: 200;
		column: 'arcs' text: [ :each | each count asString ] width: 90;
		column: 'subjects' text: [ :each | each distinctSubjects asString ] width: 100;
		column: 'objects' text: [ :each | each distinctObjects asString ] width: 100;
		column: 'grounded' text: [ :each | each groundedDescription ] width: 130;
		send: [ :each | each ]!

gtValidationFor: aView
	<gtView>
	self validationAnswer hasValue ifFalse: [
		^ aView textEditor
			title: 'Validation';
			priority: 30;
			text: [ validationAnswer failureReport: 'The relation validation did not run.' ] ].
	^ aView columnedList
		title: 'Validation';
		priority: 30;
		items: [ self issues ];
		column: 'defect' text: [ :each | (each at: 'defect' ifAbsent: [ '--' ]) asString ] width: 200;
		column: 'subject' text: [ :each | (each at: 'subject' ifAbsent: [ '--' ]) asString ];
		column: 'detail' text: [ :each | (each at: 'detail' ifAbsent: [ '--' ]) asString ];
		send: [ :each | each ]!

gtSummaryFor: aView
	<gtView>
	^ aView columnedList
		title: 'Relations';
		priority: 5;
		items: [ self summaryRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]! !


!McKdiRelationContract methodsFor: 'accessing'!
spec
	^ (self at: 'spec') ifNil: [ Dictionary new ]!

specAt: aKey
	^ self spec at: aKey ifAbsent: [ self at: aKey ]!

name
	^ (self at: 'relation') ifNil: [ (self at: 'name') ifNil: [ '--' ] ]!

domain
	^ (self specAt: 'source_kinds') ifNil: [
		(self at: 'domain') ifNil: [ (self at: 'subject_kinds') ifNil: [ #() ] ] ]!

range
	^ (self specAt: 'target_kinds') ifNil: [
		(self at: 'range') ifNil: [ (self at: 'object_kinds') ifNil: [ #() ] ] ]!

kindsDescription: aValue
	aValue isNil ifTrue: [ ^ '(any)' ].
	aValue isString ifTrue: [ ^ aValue ].
	(aValue isKindOf: Collection) ifFalse: [ ^ aValue asString ].
	aValue isEmpty ifTrue: [ ^ '(any)' ].
	^ ', ' join: (aValue collect: [ :e | e asString ])!

domainDescription
	^ self kindsDescription: self domain!

rangeDescription
	^ self kindsDescription: self range!

cardinality
	^ (self at: 'cardinality') ifNil: [ '--' ]!

isSymmetric
	^ (self specAt: 'symmetric') = true!

isTransitive
	^ (self specAt: 'transitive') = true!

inverse
	^ self specAt: 'inverse_name'!

requiresEvidence
	"Whether an arc of this relation must name a passage.  This is the field
	 that decides whether an ungrounded arc is a defect or a design."
	^ (self specAt: 'requires_evidence') = true!

description
	^ (self specAt: 'description') ifNil: [ '' ]!

contractRows
	^ {
		{ 'relation'. self name }.
		{ 'from kinds'. self domainDescription }.
		{ 'to kinds'. self rangeDescription }.
		{ 'cardinality'. self cardinality }.
		{ 'symmetric'. self isSymmetric }.
		{ 'transitive'. self isTransitive }.
		{ 'inverse'. self inverse }.
		{ 'requires evidence'. self requiresEvidence
			ifTrue: [ 'yes -- an arc must name a passage' ]
			ifFalse: [ 'no -- an arc may be asserted without one' ] }.
		{ 'description'. self description } }! !


!McKdiRelationContract methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiRelationContract(', self name asString, ')'! !


!McKdiRelationContract methodsFor: 'views'!
gtContractFor: aView
	<gtView>
	^ aView columnedList
		title: 'Contract';
		priority: 10;
		items: [ self contractRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]! !


!McKdiRelationStat methodsFor: 'accessing'!
name
	^ (self at: 'relation') ifNil: [ (self at: 'name') ifNil: [ '--' ] ]!

count
	^ (self at: 'count') ifNil: [ (self at: 'arcs') ifNil: [ 0 ] ]!

distinctSubjects
	^ (self at: 'distinct_subjects') ifNil: [ '--' ]!

distinctObjects
	^ (self at: 'distinct_objects') ifNil: [ '--' ]!

grounded
	^ (self at: 'grounded') ifNil: [ self at: 'with_evidence' ]!

groundedDescription
	"How much of this relation is backed by a passage.  An arc count alone
	 cannot distinguish a well-evidenced relation from an asserted one."
	self grounded ifNil: [ ^ '--' ].
	self count = 0 ifTrue: [ ^ '--' ].
	^ self grounded printString, ' of ', self count printString!

averageConfidence
	^ self at: 'average_confidence'!

statRows
	^ {
		{ 'relation'. self name }.
		{ 'arcs'. self count }.
		{ 'distinct subjects'. self distinctSubjects }.
		{ 'distinct objects'. self distinctObjects }.
		{ 'grounded in a passage'. self groundedDescription }.
		{ 'average confidence'. self averageConfidence } }! !


!McKdiRelationStat methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiRelationStat(', self name asString, ' ',
		self count printString, ')'! !


!McKdiRelationStat methodsFor: 'views'!
gtStatFor: aView
	<gtView>
	^ aView columnedList
		title: 'Statistic';
		priority: 10;
		items: [ self statRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]! !
