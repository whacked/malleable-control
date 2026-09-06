"
McKdiSlice -- authoring a cutting plane, and reading what it would select.

The refinement loop here is deliberately write-free.  `Plan matches' runs
`kdi slice create ... --plan', which resolves exact prospective members and
saves nothing: no definition version, no materialized result.  Masking a
candidate adds an --exclude and replans, so it too writes nothing, and the
masked candidate stays visible as a masked row rather than vanishing.

Two distinctions this file makes visible, because the Textual form does not:

  A filter is exact and conjunctive.  Entity, attributes, roles, since/until,
  tier ceiling, source URI, set type and the manual mask all REMOVE candidates.

  An aspect only RANKS.  Lexical, semantic and graph aspects order the
  survivors and are fused by reciprocal rank fusion.  An aspect never excludes
  anything, so a query is not a `must contain these words' boundary.

A candidate is an EvidenceSet, normally a context bundle.  Slices do not select
passages directly -- but a candidate can be walked down into its passages, which
is what McKdiSliceCandidate>>bundle is for.

Chunk format: load with fileIn.
"!

Object subclass: #McKdiSliceRecipe
	instanceVariableNames: 'store name query limit setType sourceUris tierCeiling excludes excludeReason lastPlan previousPlan keywords keywordMode keywordMatch keywordNegate planAnswer lastRun runAnswer lastBuild buildAnswer maxTokens maxBundles maxPerSource interpret'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiSlicePlan
	instanceVariableNames: 'recipe'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiSliceRun
	instanceVariableNames: 'recipe'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiSliceCandidate
	instanceVariableNames: 'plan bundle isMasked'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiSliceContribution
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiCoverageRow
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!


!McKdiSliceRecipe class methodsFor: 'instance creation'!
store: aStore
	^ self new setStore: aStore! !


!McKdiSliceRecipe methodsFor: 'initialization'!
setStore: aStore
	store := aStore.
	name := 'gt-explorer'.
	query := ''.
	limit := 20.
	excludes := OrderedCollection new.
	excludeReason := 'masked in the GT explorer'.
	sourceUris := #().
	keywords := OrderedCollection new.
	keywordMode := 'all'.
	keywordMatch := 'token'.
	keywordNegate := false.
	^ self! !


!McKdiSliceRecipe methodsFor: 'accessing'!
store
	^ store!

binding
	^ store binding!

name
	^ name!

name: aString
	name := aString!

query
	^ query!

query: aString
	"Ranks; never excludes.  A candidate no aspect ranked is appended after the
	 ranked ones in stable id order, so an unranked candidate can still fill the
	 result."
	query := aString.
	^ self!

limit
	^ limit!

limit: anInteger
	limit := anInteger!

setType
	^ setType!

setType: aString
	setType := aString!

sourceUris
	^ sourceUris ifNil: [ #() ]!

sourceUris: aCollection
	sourceUris := aCollection asArray!

tierCeiling
	^ tierCeiling!

tierCeiling: aString
	tierCeiling := aString!

excludes
	^ excludes ifNil: [ excludes := OrderedCollection new ]!

keywords
	"Terms of the exact text filter.  Unlike the query, these REMOVE candidates
	 whose text does not match, and each removal is recorded with its reason."
	^ keywords ifNil: [ keywords := OrderedCollection new ]!

keywords: aCollection
	keywords := aCollection asOrderedCollection!

addKeyword: aTerm
	(self keywords includes: aTerm) ifFalse: [ self keywords add: aTerm ].
	^ self plan!

removeKeyword: aTerm
	self keywords remove: aTerm ifAbsent: [ nil ].
	^ self plan!

clearKeywords
	keywords := OrderedCollection new.
	^ self plan!

keywordMode
	^ keywordMode ifNil: [ keywordMode := 'all' ]!

keywordMode: aString
	keywordMode := aString!

keywordMatch
	^ keywordMatch ifNil: [ keywordMatch := 'token' ]!

keywordMatch: aString
	keywordMatch := aString!

keywordNegate
	^ keywordNegate = true!

keywordNegate: aBoolean
	keywordNegate := aBoolean!

keywordDescription
	self keywords ifEmpty: [ ^ '(none)' ].
	^ (self keywordNegate ifTrue: [ 'NOT ' ] ifFalse: [ '' ]),
		(' ', self keywordMode asUppercase, ' ') join: self keywords!

lastPlan
	^ lastPlan!

planAnswer
	"The raw answer from the last plan attempt, kept so a FAILED plan is still a
	 visible fact rather than a tab that quietly does not appear."
	^ planAnswer!

previousPlan
	^ previousPlan!

lastAttemptFailed
	^ planAnswer notNil and: [ planAnswer hasValue not ]!

failureText
	"A refused plan no longer discards the one before it, so the other tabs may
	 still be showing a plan -- an older one.  Saying which is the difference
	 between a stale screen and a stale screen you were warned about."
	^ (planAnswer failureReport: 'The plan did not run.'),
		(lastPlan
			ifNil: [ '' ]
			ifNotNil: [ :p | String cr, String cr,
				'The other tabs still show the previous plan (', p summaryLine,
				'), which is what Plan diff compares against.' ])!

lastRun
	^ lastRun!

lastBuild
	^ lastBuild!

maxTokens
	"The packet's token budget.  NOT a slice parameter: the slice chooses which
	 bundles, this chooses how many of them the packet can afford.  A slice of
	 five bundles under a budget that fits one produces a one-source packet, and
	 the interpretation then rejects it for being one source."
	^ maxTokens ifNil: [ 6000 ]!

maxTokens: anInteger
	maxTokens := anInteger!

maxBundles
	^ maxBundles ifNil: [ 24 ]!

maxBundles: anInteger
	maxBundles := anInteger!

maxPerSource
	^ maxPerSource ifNil: [ 4 ]!

maxPerSource: anInteger
	maxPerSource := anInteger!

interpret
	"Whether the facet interpretation runs before the draft.  It is a judgement
	 about whether the packet is worth a dossier at all, and it can fail in two
	 different ways: it can REJECT the candidate, which is a durable result, or
	 it can answer something its own schema refuses -- a `useful' verdict naming
	 no evidence -- which is a model that satisfied the grammar and missed the
	 contract.  Turning it off drafts straight over the packet."
	^ interpret ~= false!

interpret: aBoolean
	interpret := aBoolean!

reportArguments
	| args |
	args := OrderedCollection new.
	args add: '--max-tokens'; add: self maxTokens printString.
	args add: '--max-bundles'; add: self maxBundles printString.
	args add: '--max-per-source'; add: self maxPerSource printString.
	self interpret ifFalse: [ args add: '--no-interpret' ].
	^ args asArray!

plannedTokenTotal
	"What the planned candidates would cost if the packet could take them all.
	 The estimator is char-quarter-1, which is what the backend uses."
	lastPlan ifNil: [ ^ nil ].
	^ (lastPlan candidates inject: 0 into: [ :sum :each |
		sum + ((each bundle chars ifNil: [ 0 ]) // 4) ])!

reportFormRows
	^ {
		{ 'max tokens -- the packet budget'. self maxTokens printString.
			[ :s | maxTokens := s asInteger ifNil: [ maxTokens ] ] }.
		{ 'max bundles'. self maxBundles printString.
			[ :s | maxBundles := s asInteger ifNil: [ maxBundles ] ] }.
		{ 'max per source'. self maxPerSource printString.
			[ :s | maxPerSource := s asInteger ifNil: [ maxPerSource ] ] }.
		{ 'interpret before drafting -- yes / no'.
			(self interpret ifTrue: [ 'yes' ] ifFalse: [ 'no' ]).
			[ :s | interpret := (s trimBoth asLowercase beginsWith: 'y') ] } }!

isMaterialized
	"A report can only be built from a slice that exists.  The plan's `exists'
	 answers exactly that, and a run of this session answers it too."
	^ lastRun notNil or: [ lastPlan notNil and: [ lastPlan exists ] ]!

runAnswer
	"Kept for the same reason planAnswer is: a refused write is a fact, and a
	 tab that quietly fails to appear reads as a dead button."
	^ runAnswer!

sliceId
	"The id the materialized slice has, or -- before the write -- the id it would
	 have.  The plan computes it either way, which is what makes the write
	 previewable: `exists' says whether pressing Materialize is new work."
	^ lastRun
		ifNil: [ lastPlan ifNotNil: [ :p | p sliceId ] ]
		ifNotNil: [ :r | r sliceId ]! !


!McKdiSliceRecipe methodsFor: 'planning'!
baseArguments
	"Everything both modes share.  --plan and --run are refused together by the
	 CLI, so they are two argvs off one base rather than one argv with a flag."
	| args |
	args := OrderedCollection new.
	args add: 'slice'; add: 'create'; add: '--name'; add: name.
	(query isNil or: [ query isEmpty ]) ifFalse: [ args add: '--query'; add: query ].
	self keywords do: [ :each | args add: '--keyword'; add: each ].
	self keywords ifNotEmpty: [
		args add: '--keyword-mode'; add: self keywordMode.
		args add: '--keyword-match'; add: self keywordMatch.
		self keywordNegate ifTrue: [ args add: '--keyword-negate' ] ].
	setType ifNotNil: [ :s | args add: '--set-type'; add: s ].
	tierCeiling ifNotNil: [ :t | args add: '--tier-ceiling'; add: t ].
	self sourceUris do: [ :each | args add: '--source'; add: each ].
	self excludes do: [ :each | args add: '--exclude'; add: each ].
	self excludes ifNotEmpty: [ args add: '--exclude-reason'; add: excludeReason ].
	args add: '--limit'; add: limit printString.
	^ args asArray!

planArguments
	^ (self baseArguments asOrderedCollection add: '--plan'; yourself) asArray!

materializeArguments
	^ (self baseArguments asOrderedCollection add: '--run'; yourself) asArray!

savedDefinitionAnswer
	^ self binding runJson: { 'slice'. 'show'. name }!

isAlreadySaved
	"Whether a definition of this name is saved with THIS recipe's exact
	 specification.  Two existences live under one word here: the definition
	 (`sld-') and the materialized result (`est-').  The plan's `exists' answers
	 the second only, so a recipe reading `prospective' can still have its
	 definition save refused for recording no edit."
	| a |
	lastPlan ifNil: [ ^ false ].
	a := self savedDefinitionAnswer.
	^ a hasValue and: [ (a valueAt: 'spec_hash') = lastPlan specHash ]!

materializeCommand
	"`slice create --run' saves a definition and refuses to save one that records
	 no edit, so a recipe whose definition is already saved unchanged is
	 materialized by RUNNING the definition -- which is also how you re-run it
	 over a changed corpus."
	^ self isAlreadySaved
		ifTrue: [ { 'slice'. 'run'. name } ]
		ifFalse: [ self materializeArguments ]!

plan
	"Writes nothing.  The previous plan is kept so the two can be compared.

	 A REFUSED plan must not shift the baseline.  It used to: previousPlan was
	 assigned before the outcome was known, so one failed replan set lastPlan to
	 nil, and the NEXT successful replan then took that nil as its previous --
	 losing the diff for two rounds and making Plan diff look broken long after
	 the failure that caused it.  The shift now happens only on success."
	| a plan |
	a := self binding runJson: self planArguments.
	planAnswer := a.
	a hasValue ifFalse: [ ^ a ].
	plan := (McKdiSlicePlan json: a value answer: a) setRecipe: self.
	"Replanning an UNCHANGED recipe must not consume the baseline either.  The
	 slice id covers every input, so two plans carrying the same one are the same
	 plan, and letting the second overwrite previousPlan empties Plan diff for
	 anyone who pressed the button twice."
	(lastPlan notNil and: [ lastPlan sliceId = plan sliceId ])
		ifFalse: [ previousPlan := lastPlan ].
	lastPlan := plan.
	^ lastPlan!

buildReportDryRun
	^ self buildReport: true!

buildReport
	^ self buildReport: false!

buildReportForcingDraft
	^ self buildReport: false forceDraft: true!

buildReport: dryRun
	^ self buildReport: dryRun forceDraft: false!

buildReport: dryRun forceDraft: forceDraft
	"kdi report build --slice NAME.  The build needs a MATERIALIZED slice, so it
	 is offered only once one exists."
	| a |
	a := McKdiReportBuild recipe: self dryRun: dryRun forceDraft: forceDraft.
	(a isKindOf: McKdiReportBuild)
		ifTrue: [ lastBuild := a. buildAnswer := a answer ]
		ifFalse: [ lastBuild := nil. buildAnswer := a ].
	^ lastBuild ifNil: [ buildAnswer ]!

materialize
	"THE write.  Every other thing this recipe does -- planning, masking, cycling
	 a keyword mode -- saves nothing.  This one saves the definition (superseding
	 the previous version if the recipe has changed since) and materializes one
	 immutable EvidenceSet.  It is a separate argv because the CLI refuses --plan
	 and --run together."
	| a |
	a := self binding runJson: self materializeCommand.
	runAnswer := a.
	lastRun := a hasValue
		ifTrue: [ (McKdiSliceRun json: a value answer: a) setRecipe: self ]
		ifFalse: [ nil ].
	^ lastRun ifNil: [ a ]!

mask: aCandidateId
	"Remove one candidate by hand and replan.  Still write-free."
	(self excludes includes: aCandidateId)
		ifFalse: [ self excludes add: aCandidateId ].
	^ self plan!

unmask: aCandidateId
	self excludes remove: aCandidateId ifAbsent: [ nil ].
	^ self plan!

isMasked: aCandidateId
	^ self excludes includes: aCandidateId! !


!McKdiSliceRecipe methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiSliceRecipe(', name asString, ')'! !


!McKdiSliceRecipe methodsFor: 'views'!
gtRecipeFor: aView
	<gtView>
	^ aView columnedList
		title: 'Recipe';
		priority: 10;
		items: [ self recipeRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ];
		column: 'kind' text: [ :each | each third ] width: 300!

gtRecipeRowsPlaceholderFor: aView
	^ aView empty! !


!McKdiSliceRecipe methodsFor: 'rows'!
recipeRows
	"The recipe as label/value/kind rows.  `kind' is the column that matters:
	 a filter removes candidates, an aspect only orders them."
	^ {
			{ 'name'. name. 'handle' }.
			{ 'query / intent'. (query isEmpty ifTrue: [ '(none)' ] ifFalse: [ query ]).
				'ASPECT -- ranks only, never excludes' }.
			{ 'keywords'. self keywordDescription.
				'FILTER -- exact text, removes non-matches' }.
			{ 'keyword match'. self keywordMatch.
				'token | substring | phrase' }.
			{ 'limit'. limit. 'take' }.
			{ 'set type'. setType ifNil: [ '(default: bundles)' ]. 'FILTER -- exact' }.
			{ 'source URIs'. self sourceUris ifEmpty: [ '(all)' ] ifNotEmpty: [ :u | ', ' join: u ].
				'FILTER -- exact' }.
			{ 'tier ceiling'. tierCeiling ifNil: [ '(none)' ]. 'FILTER -- exact' }.
			{ 'masked candidates'. self excludes size. 'FILTER -- exact, write-free' }.
			{ 'slice id'. self sliceId ifNil: [ '(plan first)' ].
				self resultDescription } }!

resultDescription
	"Whether materializing this recipe would be new work.  The plan already
	 computes the identity the slice WOULD have, so the one write in this loop
	 can be described before it happens."
	lastRun ifNotNil: [ ^ 'MATERIALIZED -- this EvidenceSet is in the store' ].
	lastPlan ifNil: [ ^ 'not planned yet' ].
	^ lastPlan exists
		ifTrue: [ 'already exists -- materializing would reuse it, not write' ]
		ifFalse: [ 'prospective -- Materialize would write this EvidenceSet' ]!

gtPlannedFor: aView
	<gtView>
	"One tab, three states.  It is a single method rather than a success view and
	 a failure view sharing a title, because two views claiming the same title
	 can both be non-empty at once and then the tab appears twice."
	self lastAttemptFailed ifTrue: [
		^ aView textEditor
			title: 'Planned matches';
			priority: 20;
			text: [ self failureText ] ].
	lastPlan ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Planned matches';
		priority: 20;
		object: [ lastPlan ];
		view: #gtCandidatesFor:!

gtCoverageFor: aView
	<gtView>
	"Forwarded from the plan.  The recipe's Planned matches view sends a
	 CANDIDATE when you click a row, so the plan object itself is never landed on
	 -- its coverage, its own fields and its specification would be unreachable
	 unless the recipe carries them too."
	lastPlan ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Provider coverage';
		priority: 22;
		object: [ lastPlan ];
		view: #gtCoverageFor:!

gtPlanDetailFor: aView
	<gtView>
	lastPlan ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Plan';
		priority: 45;
		object: [ lastPlan ];
		view: #gtPlanFor:!

gtPlanNotesFor: aView
	<gtView>
	lastPlan ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Notes';
		priority: 46;
		object: [ lastPlan ];
		view: #gtNotesFor:!

gtPlanSpecFor: aView
	<gtView>
	lastPlan ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Specification';
		priority: 50;
		object: [ lastPlan ];
		view: #gtSpecFor:!

gtKeywordsFor: aView
	<gtView>
	self keywords ifEmpty: [ ^ aView empty ].
	^ aView columnedList
		title: 'Keywords';
		priority: 25;
		items: [ self keywords asArray ];
		column: 'term' text: [ :each | each asString ];
		column: 'combined' text: [ :each | self keywordMode ] width: 100;
		column: 'matched by' text: [ :each | self keywordMatch ] width: 120!

gtMaskedFor: aView
	<gtView>
	self excludes ifEmpty: [ ^ aView empty ].
	^ aView columnedList
		title: 'Masked';
		priority: 30;
		items: [ self excludes asArray ];
		column: 'candidate' text: [ :each | each asString ];
		send: [ :each | McKdiBundle store: store id: each ]!

gtRunFor: aView
	<gtView>
	"Clicking any row lands on the run itself, so its own views stay reachable.
	 A forward here would repeat finding 15."
	lastRun ifNil: [ ^ aView empty ].
	^ aView columnedList
		title: 'Materialized';
		priority: 55;
		items: [ lastRun summaryRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ];
		send: [ :each | lastRun ]!

gtRunFailureFor: aView
	<gtView>
	"Same tab title as the success, for the reason finding 14 records: an empty
	 view means nothing to show, never something went wrong."
	(lastRun notNil or: [ runAnswer isNil ]) ifTrue: [ ^ aView empty ].
	^ aView textEditor
		title: 'Materialized';
		priority: 55;
		text: [ runAnswer failureReport: 'Nothing was written.' ]!

gtReportSettingsFor: aView
	<gtView>
	self isMaterialized ifFalse: [ ^ aView empty ].
	^ aView columnedList
		title: 'Report settings';
		priority: 56;
		items: [ {
			{ 'max tokens (packet budget)'. self maxTokens }.
			{ 'max bundles'. self maxBundles }.
			{ 'max per source'. self maxPerSource }.
			{ 'interpret before drafting'. self interpret
				ifTrue: [ 'yes -- judges whether the packet is worth a dossier' ]
				ifFalse: [ 'no -- draft straight over the packet' ] }.
			{ 'planned candidates cost'. self plannedTokenTotal
				ifNil: [ '(plan first)' ]
				ifNotNil: [ :t | t printString, ' tokens to hold all ',
					lastPlan candidates size printString, ' of them' ] } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtBuildFor: aView
	<gtView>
	"Clicking a row lands on the build, which is the object carrying the stage
	 table, the rendered report and the verification."
	lastBuild ifNil: [ ^ aView empty ].
	^ aView columnedList
		title: 'Report build';
		priority: 57;
		items: [ lastBuild summaryRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ];
		send: [ :each | lastBuild ]!

gtBuildFailureFor: aView
	<gtView>
	(lastBuild notNil or: [ buildAnswer isNil ]) ifTrue: [ ^ aView empty ].
	^ aView textEditor
		title: 'Report build';
		priority: 57;
		text: [ buildAnswer failureReport: 'The report was not built.' ]!

gtDiffFor: aView
	<gtView>
	(lastPlan isNil or: [ previousPlan isNil ]) ifTrue: [ ^ aView empty ].
	^ aView columnedList
		title: 'Plan diff';
		priority: 40;
		items: [ lastPlan diffAgainst: previousPlan ];
		column: 'change' text: [ :each | each first ] width: 110;
		column: 'candidate' text: [ :each | each second asString ];
		column: 'was' text: [ :each | each third asString ] width: 90;
		column: 'now' text: [ :each | each fourth asString ] width: 90! !


!McKdiSliceRecipe methodsFor: 'form'!
formRows
	"label -> current text -> how to apply an edited string.  One list, so the
	 editor and the Recipe tab cannot describe different recipes."
	^ {
		{ 'name (the handle a saved definition takes)'. name asString.
			[ :s | name := s trimBoth ] }.
		{ 'query -- ASPECT, ranks only, never excludes'. query asString.
			[ :s | query := s trimBoth ] }.
		{ 'keywords -- FILTER, exact text, space separated'. ' ' join: self keywords.
			[ :s | self keywords: (s substrings: ' ') ] }.
		{ 'limit'. limit printString.
			[ :s | limit := s asInteger ifNil: [ limit ] ] }.
		{ 'set type'. setType ifNil: [ '' ].
			[ :s | setType := s trimBoth ifEmpty: [ nil ] ] }.
		{ 'tier ceiling'. tierCeiling ifNil: [ '' ].
			[ :s | tierCeiling := s trimBoth ifEmpty: [ nil ] ] }.
		{ 'source URIs -- space separated'. ' ' join: self sourceUris.
			[ :s | sourceUris := (s substrings: ' ') asArray ] } }!

formElementFrom: anElement
	^ self formElementFrom: anElement rows: self formRows label: 'Apply and replan (writes nothing)' then: [ self plan ]!

reportFormElementFrom: anElement
	^ self formElementFrom: anElement rows: self reportFormRows
		label: 'Apply and dry-run the build (writes nothing)'
		then: [ self buildReportDryRun ]!

formElementFrom: anElement rows: aRowList label: aLabel then: aBlock
	"A dropdown holding one editor per field.  There is nothing GT cannot say
	 here -- the elisp that set these from Emacs called the same setters."
	| pane pairs |
	pairs := OrderedCollection new.
	pane := BrVerticalPane new.
	pane constraintsDo: [ :c | c horizontal exact: 520. c vertical fitContent ].
	pane padding: (BlInsets all: 10).
	aRowList do: [ :row | | label editor |
		label := BrLabel new
			aptitude: BrGlamorousLabelAptitude new;
			text: row first.
		label constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ].
		editor := BrEditor new.
		editor aptitude: BrGlamorousRegularEditorAptitude new.
		editor text: row second asString asRopedText.
		editor constraintsDo: [ :c | c horizontal matchParent. c vertical exact: 30 ].
		pairs add: editor -> row third.
		pane addChild: label.
		pane addChild: editor ].
	pane addChild: (self applyButtonFor: anElement pairs: pairs label: aLabel then: aBlock).
	^ pane!

applyButtonFor: anElement pairs: aCollection label: aLabel then: aBlock
	| button |
	button := BrButton new
		aptitude: BrGlamorousButtonWithLabelAptitude new;
		label: aLabel.
	button action: [ self applyPairs: aCollection from: anElement label: aLabel then: aBlock ].
	^ button!

applyPairs: aCollection from: anElement label: aLabel then: aBlock
	"Read each editor, apply it through its own setter, then do the work off the
	 UI process.  A method rather than a block inside the button so the whole
	 apply path can be exercised without a physical click."
	aCollection do: [ :each | each value value: each key text asString ].
	store runOffUi: aBlock from: anElement labelled: aLabel.
	^ self! !


!McKdiSliceRecipe methodsFor: 'actions'!
gtEditActionFor: anAction
	<gtAction>
	^ anAction dropdown
		label: 'Edit recipe';
		priority: 5;
		tooltip: 'Set the name, query, keywords, limit, set type, tier ceiling and sources, then replan';
		content: [ :anElement | self formElementFrom: anElement ]!

gtReportSettingsActionFor: anAction
	<gtAction>
	self isMaterialized ifFalse: [ ^ anAction noAction ].
	^ anAction dropdown
		label: (store actionLabel: 'Report settings');
		priority: 55;
		tooltip: 'The packet budget the report build resolves under. Not part of the slice: it decides how many of the slice''s bundles the packet can afford';
		content: [ :anElement | self reportFormElementFrom: anElement ]!

gtMaterializeActionFor: anAction
	<gtAction>
	"The only button in this loop that writes.  It says so, and the Recipe tab's
	 `slice id' row says beforehand whether the write is new work or a reuse."
	lastPlan ifNil: [ ^ anAction noAction ].
	^ anAction button
		label: (store actionLabel: 'Materialize (WRITES)');
		priority: 50;
		tooltip: 'kdi slice create --run: saves the definition and materializes one immutable EvidenceSet. ',
			self resultDescription;
		action: [ :aButton | store runOffUi: [ self materialize ] from: aButton labelled: 'Materialize' ]!

gtBuildDryRunActionFor: anAction
	<gtAction>
	"Offered only once the slice exists, because a build resolves a materialized
	 slice and saying so with a button that always fails would be worse."
	self isMaterialized ifFalse: [ ^ anAction noAction ].
	^ anAction button
		label: (store actionLabel: 'Report: dry run (writes nothing)');
		priority: 60;
		tooltip: 'kdi report build --slice NAME --dry-run: what each of the five cached stages would do. No write, no model call, no embedding call';
		action: [ :aButton |
			store runOffUi: [ self buildReportDryRun ] from: aButton labelled: 'Report dry run' ]!

gtBuildActionFor: anAction
	<gtAction>
	self isMaterialized ifFalse: [ ^ anAction noAction ].
	^ anAction button
		label: (store actionLabel: 'Report: build (WRITES, calls the model)');
		priority: 70;
		tooltip: 'kdi report build --slice NAME: materializes if needed, builds or reuses the packet, interprets, drafts through the tier-gated backend and renders. Minutes, not seconds';
		action: [ :aButton |
			store runOffUi: [ self buildReport ] from: aButton labelled: 'Report build' ]!

gtForceDraftActionFor: anAction
	<gtAction>
	"Offered only when the last build was blocked by the interpretation, because
	 that is the one case in which the backend itself names --force-draft as the
	 remedy.  A button that is always there would be an invitation to skip a
	 judgement nobody had made yet."
	(lastBuild notNil and: [ lastBuild blockedStage = 'interpret' ])
		ifFalse: [ ^ anAction noAction ].
	^ anAction button
		label: (store actionLabel: 'Report: force draft over the rejection (WRITES)');
		priority: 80;
		tooltip: 'kdi report build --slice NAME --force-draft: draft even though the interpretation rejected this candidate. The rejection stays on record';
		action: [ :aButton |
			store runOffUi: [ self buildReportForcingDraft ] from: aButton labelled: 'Report build (forced)' ]!
gtKeywordModeActionFor: anAction
	<gtAction>
	self keywords ifEmpty: [ ^ anAction noAction ].
	^ anAction button
		label: (store actionLabel: 'all / any');
		priority: 20;
		tooltip: 'Combine the keyword terms conjunctively or disjunctively, and replan';
		action: [ :aButton |
			self keywordMode: (self keywordMode = 'all' ifTrue: [ 'any' ] ifFalse: [ 'all' ]).
			store runOffUi: [ self plan ] from: aButton labelled: 'replan' ]!

gtKeywordMatchActionFor: anAction
	<gtAction>
	self keywords ifEmpty: [ ^ anAction noAction ].
	^ anAction button
		label: (store actionLabel: 'token / substring / phrase');
		priority: 30;
		tooltip: 'Cycle how a keyword term is compared against candidate text, and replan';
		action: [ :aButton |
			self keywordMatch: (self keywordMatch = 'token'
				ifTrue: [ 'substring' ]
				ifFalse: [ self keywordMatch = 'substring' ifTrue: [ 'phrase' ] ifFalse: [ 'token' ] ]).
			store runOffUi: [ self plan ] from: aButton labelled: 'replan' ]!

gtKeywordNegateActionFor: anAction
	<gtAction>
	self keywords ifEmpty: [ ^ anAction noAction ].
	^ anAction button
		label: (store actionLabel: 'negate');
		priority: 40;
		tooltip: 'Remove the candidates that DO match, rather than those that do not';
		action: [ :aButton |
			self keywordNegate: self keywordNegate not.
			store runOffUi: [ self plan ] from: aButton labelled: 'replan' ]!

gtPlanActionFor: anAction
	<gtAction>
	^ anAction button
		label: (store actionLabel: 'Plan matches (writes nothing)');
		priority: 10;
		tooltip: 'kdi slice create --plan: resolves members, saves no definition and no result';
		action: [ :aButton | store runOffUi: [ self plan ] from: aButton labelled: 'Plan matches' ]! !


!McKdiSlicePlan methodsFor: 'accessing'!
setRecipe: aRecipe
	recipe := aRecipe.
	^ self!

recipe
	^ recipe!

candidateCount
	^ (self at: 'candidate_count') ifNil: [ 0 ]!

memberCount
	^ (self at: 'member_count') ifNil: [ 0 ]!

sliceId
	^ self at: 'slice_id'!

specHash
	^ self at: 'spec_hash'!

exists
	"Whether the store already holds the EvidenceSet this plan would produce.
	 The identity covers every input, so `true' means materializing is a reuse."
	^ (self at: 'exists') = true!

tier
	^ self at: 'tier'!

universeSubjectKind
	^ self at: 'universe_subject_kind'!

revisionScope
	^ self at: 'revision_scope'!

didWrite
	^ (self at: 'wrote') = true!

notes
	^ (self at: 'notes') ifNil: [ #() ]!

spec
	^ self at: 'spec'!

candidates
	^ ((self at: 'members') ifNil: [ #() ])
		collect: [ :each | (McKdiSliceCandidate json: each answer: answer) setPlan: self ]!

excludedCandidates
	^ ((self at: 'excluded') ifNil: [ #() ])
		collect: [ :each | (McKdiSliceCandidate json: each answer: answer) setPlan: self; beMasked ]!

allRows
	"Planned matches and masked candidates together, because a masked candidate
	 that disappeared from the table cannot be unmasked."
	| rows |
	rows := OrderedCollection new.
	rows addAll: self candidates.
	rows addAll: self excludedCandidates.
	recipe ifNotNil: [
		recipe excludes do: [ :id |
			(rows anySatisfy: [ :each | each candidateId = id ]) ifFalse: [
				rows add: ((McKdiSliceCandidate
					json: (Dictionary new at: 'candidate_id' put: id; yourself)
					answer: answer) setPlan: self; beMasked) ] ] ].
	^ rows asArray!

coverageRows
	^ ((self at: 'coverage') ifNil: [ #() ])
		collect: [ :each | McKdiCoverageRow json: each answer: answer ]!

providersUnavailable
	^ (self at: 'providers_unavailable') ifNil: [ #() ]!

summaryLine
	^ self memberCount printString, ' of ', self candidateCount printString,
		' candidates selected', (self didWrite ifTrue: [ ' (WROTE)' ] ifFalse: [ ', wrote nothing' ])!

diffAgainst: anotherPlan
	"Gained, lost and moved members between two plans.  Two consecutive plans
	 are not diffed for you anywhere else."
	| mine theirs rows myRanks theirRanks |
	mine := self candidates.
	theirs := anotherPlan candidates.
	myRanks := Dictionary new.
	theirRanks := Dictionary new.
	"1-based, to agree with the rank column in Candidates.  The payload's
	 fused_rank is 0-based, and a diff reading `was 1, now 0' for a row the table
	 calls rank 2 -> rank 1 is a lie about the same number."
	mine do: [ :each | myRanks at: each candidateId put: each displayRank ].
	theirs do: [ :each | theirRanks at: each candidateId put: each displayRank ].
	rows := OrderedCollection new.
	myRanks keysAndValuesDo: [ :id :rank |
		(theirRanks includesKey: id)
			ifFalse: [ rows add: { 'gained'. id. '--'. rank } ]
			ifTrue: [ | was |
				was := theirRanks at: id.
				was = rank ifFalse: [ rows add: { 'moved'. id. was. rank } ] ] ].
	theirRanks keysAndValuesDo: [ :id :rank |
		(myRanks includesKey: id) ifFalse: [ rows add: { 'lost'. id. rank. '--' } ] ].
	^ rows asArray! !


!McKdiSlicePlan methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiSlicePlan(', self summaryLine, ')'! !


!McKdiSlicePlan methodsFor: 'views'!
gtCandidatesFor: aView
	<gtView>
	^ aView columnedList
		title: 'Candidates';
		priority: 10;
		items: [ self allRows ];
		column: 'state' text: [ :each | each state ] width: 90;
		column: 'rank' text: [ :each | each rankDescription ] width: 70;
		column: 'fused score' text: [ :each | each scoreDescription ] width: 110;
		column: 'candidate (EvidenceSet)' text: [ :each | each candidateId asString ];
		column: 'entry reason' text: [ :each | each entryReason asString ];
		send: [ :each | each ]!

gtCoverageFor: aView
	<gtView>
	^ aView columnedList
		title: 'Provider coverage';
		priority: 20;
		items: [ self coverageRows ];
		column: 'provider' text: [ :each | each provider asString ];
		column: 'eligible' text: [ :each | each eligible asString ] width: 90;
		column: 'available' text: [ :each | each available asString ] width: 90;
		column: 'unrepresented' text: [ :each | each unrepresented asString ] width: 120;
		column: 'excluded' text: [ :each | each excluded asString ] width: 90;
		column: 'unavailable' text: [ :each | each unavailable asString ] width: 100;
		column: 'what it did' text: [ :each | (each note ifNil: [ '' ]) asString ];
		send: [ :each | each ]!

gtPlanFor: aView
	<gtView>
	^ aView columnedList
		title: 'Plan';
		priority: 30;
		items: [ {
			{ 'selected'. self summaryLine }.
			{ 'universe'. self universeSubjectKind }.
			{ 'revision scope'. self revisionScope }.
			{ 'tier'. self tier }.
			{ 'slice id (not saved)'. self sliceId }.
			{ 'providers unavailable'. self providersUnavailable ifEmpty: [ '(none)' ]
				ifNotEmpty: [ :p | ', ' join: (p collect: [ :e | e asString ]) ] } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtNotesFor: aView
	<gtView>
	self notes ifEmpty: [ ^ aView empty ].
	^ aView columnedList
		title: 'Notes';
		priority: 40;
		items: [ self notes ];
		column: 'note' text: [ :each | each asString ]!

gtSpecFor: aView
	<gtView>
	self spec ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Specification';
		priority: 50;
		object: [ self spec ];
		view: #gtItemsFor:! !


!McKdiSliceRun methodsFor: 'accessing'!
setRecipe: aRecipe
	recipe := aRecipe.
	^ self!

recipe
	^ recipe!

definitionId
	^ self at: 'definition_id'!

isNewDefinition
	^ (self at: 'created') = true!

supersedesId
	^ self at: 'supersedes_id'!

didSave
	^ (self at: 'saved') = true!

didMaterialize
	^ (self at: 'materialized') = true!

isDefinitionSave
	"`slice create --run' nests the materialization under `run' and adds the
	 definition it saved.  `slice run NAME' answers the materialization alone."
	^ (self at: 'run') notNil!

runReport
	^ (self at: 'run') ifNil: [ json ]!

runAt: aKey
	^ self runReport at: aKey ifAbsent: [ nil ]!

sliceId
	^ self runAt: 'slice_id'!

memberCount
	^ (self runAt: 'member_count') ifNil: [ 0 ]!

candidateCount
	^ (self runAt: 'candidate_count') ifNil: [ 0 ]!

isReuse
	"`created: false' on the run means the identical slice was already in the
	 store.  Reported as loudly as a new one, which is the contract finding 10
	 praised kdi discovery run for."
	^ (self runAt: 'created') = false!

summaryRows
	^ self isDefinitionSave
		ifTrue: [ self saveRows, self resultRows ]
		ifFalse: [ { { 'command'. 'slice run -- the definition was already saved unchanged' } },
			self resultRows ]!

saveRows
	^ {
		{ 'definition'. self definitionId }.
		{ 'definition version'. self isNewDefinition
			ifTrue: [ 'new' ] ifFalse: [ 'identical to the saved version' ] }.
		{ 'supersedes'. self supersedesId }.
		{ 'saved'. self didSave }.
		{ 'materialized'. self didMaterialize } }!

resultRows
	^ {
		{ 'slice (EvidenceSet)'. self sliceId }.
		{ 'result'. self isReuse
			ifTrue: [ 'reused -- identical inputs, identical slice' ]
			ifFalse: [ 'created' ] }.
		{ 'members'. self memberCount }.
		{ 'candidates'. self candidateCount }.
		{ 'tier'. self runAt: 'tier' }.
		{ 'spec hash'. self at: 'spec_hash' } }!

summaryLine
	^ self sliceId asString, ' -- ', self memberCount printString, ' members, ',
		(self isReuse ifTrue: [ 'reused' ] ifFalse: [ 'created' ])! !


!McKdiSliceRun methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiSliceRun(', self summaryLine, ')'! !


!McKdiSliceRun methodsFor: 'views'!
gtRunFor: aView
	<gtView>
	^ aView columnedList
		title: 'Run';
		priority: 10;
		items: [ self summaryRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtMembersFor: aView
	<gtView>
	"The members as materialized.  They open the bundle they name, which is the
	 same walk the plan's candidates offer."
	^ aView columnedList
		title: 'Members';
		priority: 20;
		items: [ (self runAt: 'members') ifNil: [ #() ] ];
		column: 'candidate' text: [ :each | (each at: 'candidate_id' ifAbsent: [ '--' ]) asString ];
		column: 'entry reason' text: [ :each | (each at: 'entry_reason' ifAbsent: [ '--' ]) asString ];
		send: [ :each | McKdiBundle
			store: (recipe ifNotNil: [ :r | r store ])
			id: (each at: 'candidate_id' ifAbsent: [ nil ]) ]!

gtSpecFor: aView
	<gtView>
	^ aView forward
		title: 'Specification';
		priority: 30;
		object: [ (self at: 'spec') ifNil: [ Dictionary new ] ];
		view: #gtItemsFor:! !


!McKdiSliceCandidate methodsFor: 'accessing'!
setPlan: aPlan
	plan := aPlan.
	^ self!

beMasked
	isMasked := true.
	^ self!

plan
	^ plan!

candidateId
	^ self at: 'candidate_id'!

ordinal
	^ self at: 'ordinal'!

fusedScore
	^ self at: 'fused_score'!

fusedRank
	^ self at: 'fused_rank'!

tier
	^ self at: 'tier'!

entryReason
	^ (self at: 'entry_reason') ifNil: [ (self at: 'reason') ifNil: [ '' ] ]!

isMasked
	^ isMasked = true or: [
		plan notNil and: [ plan recipe notNil
			and: [ plan recipe isMasked: self candidateId ] ] ]!

state
	^ self isMasked ifTrue: [ 'masked' ] ifFalse: [ 'planned' ]!

displayRank
	"The rank as the tables show it: 1-based, or nil when the payload gave none."
	^ self fusedRank ifNotNil: [ :r | r + 1 ]!

rankDescription
	self isMasked ifTrue: [ ^ '--' ].
	^ self displayRank ifNil: [ '--' ] ifNotNil: [ :r | r printString ]!

scoreDescription
	^ self fusedScore ifNil: [ '--' ] ifNotNil: [ :s | s printShowingDecimalPlaces: 6 ]!

contributions
	"Every provider's contribution, including providers that measured nothing:
	 `unrepresented' and `never ran' are different facts and the table keeps
	 both."
	| present measured |
	measured := ((self at: 'contributions') ifNil: [ #() ])
		collect: [ :each | McKdiSliceContribution json: each answer: answer ].
	plan ifNil: [ ^ measured ].
	present := measured collect: [ :each | each provider ].
	^ measured, (plan coverageRows
		reject: [ :row | present includes: row provider ]
		thenCollect: [ :row | McKdiSliceContribution unmeasuredFor: row ])! !


!McKdiSliceCandidate methodsFor: 'bundle'!
bundle
	"The candidate as the context bundle it actually is -- which is how you walk
	 a planned match down into its passages and their source text."
	^ bundle ifNil: [
		bundle := McKdiBundle store: plan recipe store id: self candidateId ]!

passages
	^ self bundle loadedMembers collect: [ :each | each passage ]! !


!McKdiSliceCandidate methodsFor: 'refinement'!
mask
	^ plan recipe mask: self candidateId!

unmask
	^ plan recipe unmask: self candidateId! !


!McKdiSliceCandidate methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiSliceCandidate(', self state, ' ', self candidateId asString, ')'! !


!McKdiSliceCandidate methodsFor: 'views'!
gtContributionsFor: aView
	<gtView>
	^ aView columnedList
		title: 'Why it ranked';
		priority: 10;
		items: [ self contributions ];
		column: 'provider' text: [ :each | each provider asString ] width: 130;
		column: 'availability' text: [ :each | each availability asString ] width: 140;
		column: 'measurement' text: [ :each | each measurementDescription ] width: 150;
		column: 'rank' text: [ :each | each rankDescription ] width: 70;
		column: 'reason' text: [ :each | each reason asString ];
		send: [ :each | each ]!

gtBundleFor: aView
	<gtView>
	"Clicking any row LANDS on the bundle.  A forward here showed the bundle's
	 fields while leaving the bundle itself unreachable -- and with it the Plan
	 packet button, which GT builds from the object you are actually on."
	^ aView columnedList
		title: 'Bundle';
		priority: 20;
		items: [ self bundle summaryRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ];
		send: [ :each | self bundle ]!

gtPassagesFor: aView
	<gtView>
	^ aView forward
		title: 'Passages';
		priority: 30;
		object: [ self bundle ];
		view: #gtMembersFor:!

gtTextFor: aView
	<gtView>
	^ aView forward
		title: 'Text';
		priority: 40;
		object: [ self bundle ];
		view: #gtTextFor:!

gtCandidateFor: aView
	<gtView>
	^ aView columnedList
		title: 'Candidate';
		priority: 50;
		items: [ {
			{ 'candidate id'. self candidateId }.
			{ 'what it is'. 'an EvidenceSet -- normally a context bundle' }.
			{ 'state'. self state }.
			{ 'fused rank'. self rankDescription }.
			{ 'fused score'. self scoreDescription }.
			{ 'tier'. self tier }.
			{ 'entry reason'. self entryReason } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]! !


!McKdiSliceCandidate methodsFor: 'actions'!
gtMaskActionFor: anAction
	<gtAction>
	^ anAction button
		label: (plan recipe store actionLabel: 'Mask / unmask (replans, writes nothing)');
		priority: 10;
		tooltip: 'Adds or removes an --exclude and replans; the row stays visible as masked';
		action: [ :aButton |
			plan recipe store
				runOffUi: [ self isMasked ifTrue: [ self unmask ] ifFalse: [ self mask ] ]
				from: aButton labelled: 'Mask / unmask' ]! !


!McKdiSliceContribution class methodsFor: 'instance creation'!
unmeasuredFor: aCoverageRow
	"A provider that ran and measured nothing about this candidate.  Rendering
	 it is the point: an absent row would read as `never ran'."
	^ self json: (Dictionary new
		at: 'provider' put: aCoverageRow provider;
		at: 'availability' put: 'unrepresented';
		at: 'reason' put: 'this provider ran and measured nothing about this candidate';
		yourself) answer: nil! !


!McKdiSliceContribution methodsFor: 'accessing'!
provider
	^ self at: 'provider'!

providerVersion
	^ self at: 'provider_version'!

availability
	^ self at: 'availability'!

measurement
	^ self at: 'measurement'!

measurementUnit
	^ self at: 'measurement_unit'!

measurementDescription
	self measurement ifNil: [ ^ '(nothing measured)' ].
	^ (self measurement printShowingDecimalPlaces: 4), ' ', (self measurementUnit ifNil: [ '' ]) asString!

rank
	^ self at: 'rank'!

rankDescription
	^ self rank ifNil: [ '--' ] ifNotNil: [ :r | (r + 1) printString ]!

score
	^ self at: 'score'!

matchedRole
	^ self at: 'matched_role'!

reason
	^ (self at: 'reason') ifNil: [ '' ]! !


!McKdiSliceContribution methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiSliceContribution(', self provider asString, ' ', self availability asString, ')'! !


!McKdiCoverageRow methodsFor: 'accessing'!
provider
	^ self at: 'provider'!

providerVersion
	^ self at: 'provider_version'!

eligible
	^ (self at: 'eligible') ifNil: [ 0 ]!

available
	^ (self at: 'available') ifNil: [ 0 ]!

unrepresented
	^ (self at: 'unrepresented') ifNil: [ 0 ]!

ambiguous
	^ (self at: 'ambiguous') ifNil: [ 0 ]!

excluded
	^ (self at: 'excluded') ifNil: [ 0 ]!

unavailable
	^ (self at: 'unavailable') ifNil: [ 0 ]!

note
	^ self at: 'note'! !


!McKdiCoverageRow methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiCoverageRow(', self provider asString, ')'! !
