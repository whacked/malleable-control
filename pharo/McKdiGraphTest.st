"
McKdiGraphTest -- the graph layer, the graph slice flags and the passage
vocabulary, against a fake binding.

No subprocess and no network.  McKdiFakeBinding is an McKdiBinding whose `run:'
answers a scripted McKdiAnswer instead of spawning kdi, so these tests exercise
the argv this explorer BUILDS and the objects it builds from an answer -- which
is the whole of what this image is responsible for.  Whether a live kdi accepts
that argv is the backend's half of the contract and cannot be settled here; what
can be settled here is that the argv is the one this file says it is, that it
carries no writing flag, and that a refused command becomes a visible answer
rather than a walkback.

The suites:

  McKdiGraphCommandsTest    the declared verb table -- every graph command in
                            one place, and none of them a write.
  McKdiGraphTest            seed search, budget preview, walks, relations, and
                            the forward walk from a passage node to McKdiPassage.
  McKdiSliceGraphTest       the --graph-* block on a slice recipe, and the
                            per-arc path provenance in a contribution.
  McKdiPassageVocabularyTest  passageId / passageIds / passageCount, and that
                            each deprecated alias answers the same thing.
"!

McKdiBinding subclass: #McKdiFakeBinding
	instanceVariableNames: 'scripts calls'
	classVariableNames: ''
	package: 'MalleableControl'!

TestCase subclass: #McKdiGraphCommandsTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

TestCase subclass: #McKdiGraphTest
	instanceVariableNames: 'binding store graph'
	classVariableNames: ''
	package: 'MalleableControl'!

TestCase subclass: #McKdiSliceGraphTest
	instanceVariableNames: 'binding store recipe'
	classVariableNames: ''
	package: 'MalleableControl'!

TestCase subclass: #McKdiPassageVocabularyTest
	instanceVariableNames: 'binding store'
	classVariableNames: ''
	package: 'MalleableControl'!


!McKdiFakeBinding class methodsFor: 'instance creation'!
forTests
	"A binding that names a store nobody has to create.  The paths only ever
	 reach argv."
	^ self
		root: '/tmp/kdi-fake'
		store: '/tmp/kdi-fake/evidence.sqlite'
		profile: 'local'
		tier: 'public'
		configDir: nil! !


!McKdiFakeBinding methodsFor: 'scripting'!
scripts
	^ scripts ifNil: [ scripts := OrderedCollection new ]!

calls
	"Every argv this binding was asked to run, in order, INCLUDING the global
	 options -- because a test that only saw the subcommand could not tell a
	 recipe that dropped --store from one that did not."
	^ calls ifNil: [ calls := OrderedCollection new ]!

lastCall
	^ self calls ifEmpty: [ nil ] ifNotEmpty: [ :c | c last ]!

callsMatching: anArrayOfWords
	^ (self calls select: [ :each | self argv: each matches: anArrayOfWords ]) asArray!

script: anArrayOfWords answering: aJsonString
	"Answer aJsonString for any command whose argv contains every word in
	 anArrayOfWords.  Containment rather than equality, because what a test
	 wants to say is `the passage show command', not the whole global-option
	 prefix that goes in front of it."
	self scripts add: anArrayOfWords asArray -> aJsonString.
	^ self!

argv: anArgv matches: anArrayOfWords
	^ anArrayOfWords allSatisfy: [ :word | anArgv includes: word ]! !


!McKdiFakeBinding methodsFor: 'running'!
run: anArrayOfStrings
	"The whole point of the double.  Everything above this method -- argv
	 assembly, JSON parsing, the answer's success and failure reporting -- is
	 the real code."
	| argv match answer |
	argv := self argvFor: anArrayOfStrings.
	self calls add: argv.
	match := self scripts
		detect: [ :each | self argv: argv matches: each key ]
		ifNone: [ nil ].
	answer := McKdiAnswer
		argv: argv
		exitCode: (match ifNil: [ 2 ] ifNotNil: [ :m | 0 ])
		stdout: (match ifNil: [ '' ] ifNotNil: [ :m | m value ])
		stderr: (match
			ifNil: [ 'kdi: no such command in this fake binding' ]
			ifNotNil: [ :m | '' ])
		startedAt: DateAndTime now
		duration: (Duration seconds: 0).
	McKdiTranscript record: answer.
	^ answer! !


!McKdiGraphCommandsTest methodsFor: 'tests'!
testEveryDeclaredCommandIsARead
	"The claim this whole layer rests on, checked rather than asserted in a
	 comment: no verb may carry a flag that would make kdi write."
	self assert: McKdiGraphCommands readsOnly!

testTheDeclaredTableCoversEveryVerbTheFileUses
	"One place names the commands.  If a verb is added without being declared
	 here, the Commands tab stops being the whole vocabulary and the tab is the
	 only way anyone can compare it against kdi --help."
	| verbs |
	verbs := McKdiGraphCommands declaredVerbs collect: [ :each | each second first ].
	self assert: (verbs asSet includesAll: #('entities' 'graph')).
	self assert: McKdiGraphCommands declaredVerbs size equals: 9!

testEverySnapshotArgvAsksForAPreview
	"The budget preview must never be able to become a build by omission."
	| argv |
	argv := McKdiGraphCommands
		snapshotMaxVertices: 10 maxEdges: 20 relations: #().
	self assert: argv first equals: 'graph'.
	self assert: argv second equals: 'snapshot'.
	self assert: argv third equals: 'plan'!

testSnapshotRelationsRepeatTheirFlagAndUseTheActualBudgetNames
	| argv |
	argv := McKdiGraphCommands
		snapshotMaxVertices: 10 maxEdges: 20
		relations: #('cites' 'defines').
	self assert: (argv occurrencesOf: '--relation') equals: 2.
	self assert: (argv includes: '--max-vertices').
	self assert: (argv includes: '--max-edges').
	self assert: (argv includes: 'defines')! !


!McKdiGraphTest methodsFor: 'running'!
setUp
	super setUp.
	binding := McKdiFakeBinding forTests.
	store := McKdiStore on: binding.
	graph := store graph! !


!McKdiGraphTest methodsFor: 'fixtures'!
entitiesJson
	^ '{"query": "grounding", "candidate_count": 2, "candidates": [
	     {"entity_id": "ent-1", "entity_type": "concept",
	      "display_name": "grounding", "aliases": [], "evidence_count": 2},
	     {"entity_id": "ent-2", "entity_type": "concept",
	      "display_name": "selector", "aliases": [], "evidence_count": 1}]}'!

neighborsJson
	^ '{"roots": ["semantic_entity:ent-1"],
	    "nodes": [
	      {"ref": "semantic_entity:ent-1", "id": "ent-1",
	       "kind": "semantic_entity", "label": "grounding", "hop": 0},
	      {"ref": "occurrence:occ-9", "id": "occ-9",
	       "kind": "occurrence", "label": "the normalized text", "hop": 1}],
	    "edges": [
	      {"edge_ref": "entity-relations:evidenced_by:erl-1",
	       "relation_type": "evidenced_by",
	       "source": {"kind": "semantic_entity", "id": "ent-1"},
	       "target": {"kind": "occurrence", "id": "occ-9"},
	       "weight": 0.75,
	       "evidence": [{"kind": "occurrence", "id": "occ-9"}]}],
	    "budget": {"max_hops": 1, "max_vertices": 1000,
	               "exhausted": null}}'!

pathJson
	^ '{"found": true, "from": "semantic_entity:ent-1",
	     "to": "semantic_entity:ent-2", "hops": 2,
	     "nodes": [], "edges": [
	       {"edge_ref": "edg-1", "relation_type": "cites",
	        "source": {"kind": "semantic_entity", "id": "ent-1"},
	        "target": {"kind": "semantic_entity", "id": "ent-3"},
	        "evidence": []},
	       {"edge_ref": "edg-2", "relation_type": "defines",
	        "source": {"kind": "semantic_entity", "id": "ent-3"},
	        "target": {"kind": "semantic_entity", "id": "ent-2"},
	        "evidence": []}]}'!

snapshotJson
	^ '{"within_budget": false,
	    "estimate": {"vertices": 900, "edges": 1800, "bytes": 41000,
	      "edges_by_provider": {"entity-relations": 120, "structural": 280}},
	    "budget": {"max_vertices": 200, "max_edges": 400,
	               "max_bytes": 1000000},
	    "refusals": ["max_vertices 900 > 200"],
	    "notes": [{"code": "budget", "detail": "raise max_vertices"}]}'!

passageJson
	^ '{"id": "occ-9", "text": "the normalized text",
	    "exact_quote": "the normalized text", "content_type": "paragraph",
	    "tier": "public", "selector_type": "text_quote",
	    "resolution_status": "resolved"}'!

scriptEntities
	binding script: #('entities' 'find') answering: self entitiesJson.
	^ binding! !


!McKdiGraphTest methodsFor: 'tests - seed search'!
testSearchArgvCarriesTheQueryAndUsesThePublishedPluralCommand
	self scriptEntities.
	graph seedQuery: 'grounding'.
	graph searchEntities.
	self assert: (binding lastCall includes: 'grounding').
	self assert: (binding lastCall includes: 'entities').
	self assert: (binding lastCall includes: 'find').
	self deny: (binding lastCall includes: '--limit')!

testSearchBuildsEntitiesFromTheAnswer
	| entities |
	self scriptEntities.
	graph seedQuery: 'grounding'.
	graph searchEntities.
	entities := graph entities.
	self assert: entities size equals: 2.
	self assert: entities first id equals: 'ent-1'.
	self assert: entities first label equals: 'grounding'!

testFindDoesNotInventARankingTheBackendDidNotReturn
	self scriptEntities.
	graph searchEntities.
	self assert: graph entities first rankDescription equals: '--'.
	self assert: graph entities second scoreDescription equals: '--'!

testTheDeprecatedOccurrenceAliasAgreesWithPassageIds
	self scriptEntities.
	graph searchEntities.
	self
		assert: graph entities first occurrenceIds asArray
		equals: graph entities first passageIds asArray!

testARefusedSearchIsAVisibleAnswerRatherThanARaise
	"Nothing is scripted, so the fake refuses.  The page must be nil and the
	 ANSWER must survive, because that is what the failure view renders."
	graph seedQuery: 'grounding'.
	graph searchEntities.
	self assert: graph entityPage isNil.
	self deny: graph entityAnswer isNil.
	self deny: graph entityAnswer isSuccess.
	self assert: (graph entityAnswer failureReport: 'x') isString! !


!McKdiGraphTest methodsFor: 'tests - snapshot budget'!
testPreviewDoesNotRequireSeedsBecauseItBudgetsTheWholeSnapshot
	binding script: #('graph' 'snapshot' 'plan') answering: self snapshotJson.
	self deny: graph previewSnapshot isNil.
	self assert: (binding lastCall includes: 'plan')!

testPreviewArgvIsWriteFree
	binding script: #('graph' 'snapshot') answering: self snapshotJson.
	graph previewSnapshot.
	self assert: (binding lastCall includes: 'graph').
	self assert: (binding lastCall includes: 'snapshot').
	self assert: (binding lastCall includes: 'plan').
	McKdiGraphCommands writingFlags do: [ :flag |
		self deny: (binding lastCall includes: flag) ]!

testPreviewReportsAnOverBudgetRefusalAndBuildsNothing
	| snapshot |
	binding script: #('graph' 'snapshot') answering: self snapshotJson.
	snapshot := graph previewSnapshot.
	self assert: snapshot isTruncated.
	self assert: (snapshot verdict beginsWith: 'REFUSED').
	self assert: snapshot nodesReachable equals: 900.
	self assert: snapshot nodesAdmitted equals: 200!

testAFittingBudgetSaysSo
	| snapshot |
	binding
		script: #('graph' 'snapshot')
		answering: '{"within_budget": true,
		             "estimate": {"vertices": 12, "edges": 20,
		              "edges_by_provider": {}},
		             "budget": {"max_vertices": 200, "max_edges": 400},
		             "refusals": [], "notes": []}'.
	snapshot := graph previewSnapshot.
	self deny: snapshot isTruncated.
	self assert: (snapshot verdict beginsWith: 'FITS')!

testPerRelationCountsAreRowsSoAZeroStaysVisible
	| snapshot |
	binding script: #('graph' 'snapshot') answering: self snapshotJson.
	graph addSeed: 'ent-1'.
	snapshot := graph previewSnapshot.
	self assert: snapshot relationCounts size equals: 2.
	self assert: snapshot relationCounts first first equals: 'entity-relations'! !


!McKdiGraphTest methodsFor: 'tests - walks'!
testNeighborsBuildsNodesAndArcs
	| result |
	binding script: #('graph' 'neighbors') answering: self neighborsJson.
	result := graph neighborsOf: 'ent-1'.
	self assert: result kind equals: 'neighbors'.
	self assert: result nodes size equals: 2.
	self assert: result arcs size equals: 1.
	self assert: result arcs first relation equals: 'evidenced_by'!

testWalkArgvCarriesTheDirectionAndTheRelationFilter
	binding script: #('graph' 'traverse') answering: '{"nodes": [], "edges": []}'.
	graph direction: 'out'; relationFilter: #('cites'); depth: 3.
	graph traverseFrom: 'ent-1'.
	self assert: (binding lastCall includes: '--direction').
	self assert: (binding lastCall includes: 'out').
	self assert: (binding lastCall includes: '--relation').
	self assert: (binding lastCall includes: 'cites').
	self assert: (binding lastCall includes: '--root').
	self assert: (binding lastCall includes: '--max-hops').
	self assert: (binding lastCall includes: '3')!

testAPathNamesTheRelationAtEveryHop
	"A path rendered as endpoints alone says a connection exists without saying
	 what it is, which is the least useful true thing it could say."
	| result path |
	binding script: #('graph' 'path') answering: self pathJson.
	result := graph pathFrom: 'ent-1' to: 'ent-2'.
	self assert: result paths size equals: 1.
	path := result paths first.
	self assert: path length equals: 2.
	self assert: (path description includesSubstring: 'cites').
	self assert: (path description includesSubstring: 'defines').
	self assert: path fromId equals: 'semantic_entity:ent-1'.
	self assert: path toId equals: 'semantic_entity:ent-2'!

testARefusedWalkIsAVisibleAnswer
	graph neighborsOf: 'ent-1'.
	self assert: graph result isNil.
	self deny: graph resultAnswer isSuccess! !


!McKdiGraphTest methodsFor: 'tests - forward walk to a passage'!
testAnOccurrenceNodeIsRecognisedAsAPassageNode
	"Occurrence is the storage word and passage the public one.  A payload may
	 use either, and both name the same node."
	| result |
	binding script: #('graph' 'neighbors') answering: self neighborsJson.
	result := graph neighborsOf: 'ent-1'.
	self assert: (result nodes second) isPassageNode.
	self deny: (result nodes first) isPassageNode!

testAPassageNodeCarriesItsOwnIdAsItsPassageId
	| result |
	binding script: #('graph' 'neighbors') answering: self neighborsJson.
	result := graph neighborsOf: 'ent-1'.
	self assert: result nodes second passageIds asArray equals: #('occ-9')!

testAPassageNodeWalksForwardToMcKdiPassage
	"The walk this whole layer exists to make possible: out of the graph, into
	 the exact citable passage and its grounding."
	| result passage |
	binding
		script: #('graph' 'neighbors') answering: self neighborsJson;
		script: #('passage' 'show') answering: self passageJson.
	result := graph neighborsOf: 'ent-1'.
	passage := result nodes second passages first.
	self assert: (passage isKindOf: McKdiPassage).
	self assert: passage id equals: 'occ-9'.
	self assert: passage groundingVerdict equals: #identical!

testAnArcWalksForwardToThePassagesThatJustifyIt
	| result arc |
	binding
		script: #('graph' 'neighbors') answering: self neighborsJson;
		script: #('passage' 'show') answering: self passageJson.
	result := graph neighborsOf: 'ent-1'.
	arc := result arcs first.
	self assert: arc isGrounded.
	self assert: (arc passages first isKindOf: McKdiPassage)!

testAnUngroundedArcSaysSoRatherThanShowingAnEmptyColumn
	| arc |
	arc := McKdiGraphArc
		json: (STONJSON fromString: '{"relation": "asserts", "from": "a", "to": "b"}')
		answer: nil.
	self deny: arc isGrounded.
	self assert: ((arc arcRows detect: [ :each | each first = 'grounded' ]) second
		beginsWith: 'NO')! !


!McKdiGraphTest methodsFor: 'tests - relations'!
testTheCatalogueReadsContractsStatisticsAndValidationTogether
	| relations |
	binding
		script: #('graph' 'relation-types')
			answering: '[{"id": "grt-1", "name": "cites", "version": "1",
			              "spec": {"source_kinds": ["semantic_entity"],
			              "target_kinds": ["semantic_entity"],
			              "requires_evidence": true,
			              "description": "one concept cites another"}}]';
		script: #('graph' 'stats')
			answering: '{"edges": {"cites/1": 42}, "edge_total": 42}';
		script: #('graph' 'validate')
			answering: '{"ok": false, "defects": [{"defect": "missing-evidence",
			              "subject": "edg-7", "detail": "no support row"}]}'.
	relations := graph relations loadAll.
	self assert: relations contracts size equals: 1.
	self assert: relations contracts first name equals: 'cites'.
	self assert: relations contracts first requiresEvidence.
	self assert: relations contracts first domainDescription equals: 'semantic_entity'.
	self assert: relations stats first count equals: 42.
	self assert: relations verdict equals: 'INVALID'.
	self assert: relations issues size equals: 1!

testNotRunIsADifferentAnswerFromInvalid
	"The same distinction the QC audit makes.  Reporting a validation that
	 never ran as INVALID would be a claim nobody made."
	self assert: graph relations verdict equals: 'NOT RUN'!

testAnArrayShapedCatalogueIsReadToo
	"A bare array and an object with a key are both answers `relation
	 contracts' could reasonably give; losing the table to the difference would
	 be worse than reading both."
	binding
		script: #('graph' 'relation-types')
		answering: '[{"name": "defines", "spec": {"source_kinds": ["morsel"],
		             "target_kinds": ["morsel"]}}]'.
	self assert: graph relations contracts size equals: 1.
	self assert: graph relations contracts first name equals: 'defines'! !


!McKdiSliceGraphTest methodsFor: 'running'!
setUp
	super setUp.
	binding := McKdiFakeBinding forTests.
	store := McKdiStore on: binding.
	recipe := store recipe! !


!McKdiSliceGraphTest methodsFor: 'fixtures'!
contributionWith: aJsonString
	^ McKdiSliceContribution
		json: (STONJSON fromString: aJsonString)
		answer: nil! !


!McKdiSliceGraphTest methodsFor: 'tests - graph flags'!
testNoGraphBlockWithoutSeeds
	"A graph aspect with nothing to start from would only add a flag the
	 backend has to refuse."
	self deny: recipe hasGraphAspect.
	self assert: recipe graphArguments isEmpty.
	self deny: (recipe baseArguments includes: '--graph-seed')!

testSeedingTheRecipeAddsTheWholeGraphBlock
	recipe graphSeeds: #('ent-1' 'ent-2').
	self assert: recipe hasGraphAspect.
	self assert: (recipe baseArguments occurrencesOf: '--graph-seed') equals: 2.
	self assert: (recipe baseArguments includes: 'ent-1').
	self assert: (recipe baseArguments includes: '--graph-max-hops').
	self assert: (recipe baseArguments includes: '--graph-direction').
	self assert: (recipe baseArguments includes: '--graph-max-vertices').
	self assert: (recipe baseArguments includes: '--graph-traversal-limit')!

testRelationsAndMinimumWeightAreCarriedWhenSet
	recipe graphSeeds: #('ent-1'); graphRelations: #('cites' 'defines');
		graphMinWeight: 0.4; graphDirection: 'out'; graphDepth: 3.
	self assert: (recipe graphArguments occurrencesOf: '--graph-relation') equals: 2.
	self assert: (recipe graphArguments includes: '--graph-minimum-score').
	self assert: (recipe graphArguments includes: 'out').
	self assert: (recipe graphArguments includes: '3')!

testMinimumWeightIsOmittedWhenUnset
	"An unset threshold must not become a zero one: --graph-minimum-score 0 is a
	 different query from no threshold at all."
	recipe graphSeeds: #('ent-1').
	self deny: (recipe graphArguments includes: '--graph-minimum-score')!

testBothPlanAndMaterializeCarryTheGraphBlock
	"They are two argvs off one base because --plan and --run are refused
	 together.  A graph aspect that reached only one of them would make the
	 preview and the write mean different things."
	recipe graphSeeds: #('ent-1').
	self assert: (recipe planArguments includes: '--graph-seed').
	self assert: (recipe planArguments includes: '--plan').
	self assert: (recipe materializeArguments includes: '--graph-seed').
	self assert: (recipe materializeArguments includes: '--run')!

testTheRecipeRowsNameTheGraphAspectAsAnAspect
	"The kind column is the one that matters: a filter removes candidates, an
	 aspect only orders them, and the graph aspect is an aspect."
	| row |
	recipe graphSeeds: #('ent-1').
	row := recipe recipeRows detect: [ :each | each first = 'graph seeds' ].
	self assert: (row third includesSubstring: 'ASPECT').
	self assert: (row second includesSubstring: 'ent-1')!

testTheEditFormCanSetEveryGraphField
	"The form and the Recipe tab must not be able to describe different
	 recipes, so every graph setting is reachable from the same row list."
	| labels |
	labels := recipe formRows collect: [ :each | each first ].
	self assert: (labels anySatisfy: [ :each | each includesSubstring: 'graph seeds' ]).
	self assert: (labels anySatisfy: [ :each | each includesSubstring: 'graph max hops' ]).
	self assert: (labels anySatisfy: [ :each | each includesSubstring: 'graph direction' ]).
	self assert: (labels anySatisfy: [ :each | each includesSubstring: 'graph relations' ])! !


!McKdiSliceGraphTest methodsFor: 'tests - path provenance'!
testAContributionRendersItsArcsInTheOrderTravelled
	| contribution arcs |
	contribution := self contributionWith: '{"provider": "graph",
	    "availability": "available", "rank": 0,
	    "path": [{"relation": "cites", "from": "ent-1", "to": "ent-3"},
	             {"relation": "defines", "from": "ent-3", "to": "blk-9"}]}'.
	self assert: contribution hasPath.
	self assert: contribution pathLength equals: 2.
	arcs := contribution pathArcs.
	self assert: arcs first relation equals: 'cites'.
	self assert: arcs second toId equals: 'blk-9'.
	self assert: (arcs first isKindOf: McKdiGraphArc)!

testThePathDescriptionNamesTheRelationAtEveryHop
	| contribution |
	contribution := self contributionWith: '{"provider": "graph",
	    "path": [{"relation": "cites", "from": "ent-1", "to": "ent-3"},
	             {"relation": "defines", "from": "ent-3", "to": "blk-9"}]}'.
	self assert: (contribution pathDescription includesSubstring: 'cites').
	self assert: (contribution pathDescription includesSubstring: 'defines').
	self assert: (contribution pathDescription beginsWith: 'ent-1')!

testTheSeedIsTheFirstArcsOriginWhenThePayloadDoesNotNameOne
	| contribution |
	contribution := self contributionWith: '{"provider": "graph",
	    "path": [{"relation": "cites", "from": "ent-1", "to": "blk-9"}]}'.
	self assert: contribution seedId equals: 'ent-1'!

testAnAlternativeKeyForThePathIsReadToo
	| contribution |
	contribution := self contributionWith: '{"provider": "graph",
	    "graph_path": [{"relation": "cites", "from": "a", "to": "b"}]}'.
	self assert: contribution hasPath.
	self assert: contribution pathArcs first relation equals: 'cites'!

testAProviderThatTravelledNoArcsSaysSoRatherThanShowingBlank
	| contribution |
	contribution := self contributionWith:
		'{"provider": "lexical", "availability": "available", "rank": 0}'.
	self deny: contribution hasPath.
	self assert: contribution pathDescription equals: '--'.
	self assert: contribution seedId isNil!

testAnUnmeasuredContributionStillRenders
	"It is built from a coverage row rather than from a payload, so it has no
	 graph and no arcs.  Rendering it is the point: an absent row would read as
	 `never ran'."
	| row contribution |
	row := McKdiCoverageRow
		json: (STONJSON fromString: '{"provider": "graph"}')
		answer: nil.
	contribution := McKdiSliceContribution unmeasuredFor: row.
	self assert: contribution availability equals: 'unrepresented'.
	self assert: contribution pathDescription equals: '--'.
	self assert: contribution contributionRows isArray! !


!McKdiPassageVocabularyTest methodsFor: 'running'!
setUp
	super setUp.
	binding := McKdiFakeBinding forTests.
	store := McKdiStore on: binding! !


!McKdiPassageVocabularyTest methodsFor: 'fixtures'!
treeJson
	^ '{"source_revision_id": "rev-1", "nodes": [
	     {"id": "n-1", "parent_id": null, "ordinal": 0, "depth": 0,
	      "node_type": "document", "title": "A", "occurrence_count": 0},
	     {"id": "n-2", "parent_id": "n-1", "ordinal": 0, "depth": 1,
	      "node_type": "block", "stable_key": "b1", "occurrence_count": 3},
	     {"id": "n-3", "parent_id": "n-1", "ordinal": 1, "depth": 1,
	      "node_type": "block", "stable_key": "b2", "occurrence_count": 4}]}'!

bundleDetailJson
	^ '{"source_uri": "docs/a.md", "source_revision_id": "rev-1",
	    "text": "some text", "members": [
	      {"occurrence_id": "occ-1", "role": "core", "weight": 1.0,
	       "stream_ordinal": 0},
	      {"occurrence_id": "occ-2", "role": "shoulder", "weight": 0.5,
	       "stream_ordinal": 1}]}'!

source
	binding script: #('tree') answering: self treeJson.
	^ McKdiSource
		store: store
		json: (STONJSON fromString: '{"uri": "docs/a.md", "id": "src-1"}')
		answer: nil! !


!McKdiPassageVocabularyTest methodsFor: 'tests'!
testANodeCountsItsOwnPassagesAndItsSubtrees
	| source root |
	source := self source.
	root := source rootNodes first.
	self assert: root passageCount equals: 0.
	self assert: root subtreePassageCount equals: 7!

testTheDeprecatedNodeAliasesAnswerTheSameNumbers
	| source root |
	source := self source.
	root := source rootNodes first.
	self assert: root occurrenceCount equals: root passageCount.
	self assert: root subtreeOccurrenceCount equals: root subtreePassageCount!

testABlockMemberAnswersAPassageId
	| bundle member |
	binding script: #('discovery' 'bundles' 'show') answering: self bundleDetailJson.
	bundle := McKdiBundle store: store id: 'est-1'.
	member := bundle loadedMembers first.
	self assert: member passageId equals: 'occ-1'.
	self assert: member occurrenceId equals: member passageId!

testABlockAnswersItsMemberPassageIds
	| bundle |
	binding script: #('discovery' 'bundles' 'show') answering: self bundleDetailJson.
	bundle := McKdiBundle store: store id: 'est-1'.
	self assert: bundle memberPassageIds asArray equals: #('occ-1' 'occ-2').
	self assert: bundle memberOccurrenceIds asArray equals: bundle memberPassageIds asArray!

testAPacketItemAnswersPassageIds
	| item |
	item := McKdiPacketItem
		json: (STONJSON fromString: '{"handle": "E001", "bundle_id": "est-1",
		        "occurrence_ids": ["occ-1", "occ-2"]}')
		answer: nil.
	self assert: item passageIds asArray equals: #('occ-1' 'occ-2').
	self assert: item occurrenceIds asArray equals: item passageIds asArray!

testTheStoreCallsThemContextBlocksOnTheScreen
	"The class is still McKdiBundle -- renaming it would break every caller --
	 but nothing user-facing says bundle."
	self assert: (store bundlesTabTitle includesSubstring: 'Context block').
	self deny: (store bundlesTabTitle includesSubstring: 'Bundle')!

testNothingInTheRecipeRowsSaysEvidenceSet
	"EvidenceSet is the storage word for what the screens call a Selection, and
	 bundle is the storage word for a context block.  Neither belongs on a
	 surface someone is reading to learn the model."
	| text |
	text := String streamContents: [ :s |
		store recipe recipeRows do: [ :row |
			row do: [ :cell | s nextPutAll: cell asString; nextPutAll: ' ' ] ] ].
	self deny: (text includesSubstring: 'EvidenceSet').
	self assert: (text includesSubstring: 'context block')! !
