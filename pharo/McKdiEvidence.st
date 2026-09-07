"
McKdiEvidence -- the passage-first public objects of a KDI evidence store.

These mirror KDI design 43's *public* model, not its storage schema:

    Source -> SourceRevision -> StructuralNode -> Passage

A passage is one exact citable appearance of source text at one location, with a
selector.  Morsel and occurrence are private storage vocabulary and deliberately
are not modelled here, even though a passage id is still an occurrence id.

That applies to the ACCESSORS too, not only to the labels: McKdiNode answers
passageCount and subtreePassageCount, and keeps occurrenceCount and
subtreeOccurrenceCount as deprecated aliases answering the same numbers.  The
payload keys are untouched -- occurrence_count is what the backend sends, and
renaming it here would be inventing a contract nobody agreed to.

Every object holds the McKdiAnswer it was built from, so every screen names the
command that produced it and can be reproduced by pasting that command.  Every
accessor tolerates a missing key and answers nil, because the point of this
explorer is to find out whether the backend model is intelligible, and a walkback
tells you much less than a blank cell does.

Chunk format: load with fileIn.
"!

Object subclass: #McKdiObject
	instanceVariableNames: 'json answer'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiSource
	instanceVariableNames: 'store treeAnswer nodes childIndex revisionId qcAudit'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiNode
	instanceVariableNames: 'source passagePage provenanceAnswer subtreeCount'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiPassage
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiPassagePage
	instanceVariableNames: 'scope'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiQcAudit
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!


!McKdiObject class methodsFor: 'instance creation'!
json: aDictionary answer: anAnswer
	^ self new setJson: aDictionary answer: anAnswer! !


!McKdiObject methodsFor: 'initialization'!
setJson: aDictionary answer: anAnswer
	json := aDictionary.
	answer := anAnswer.
	^ self! !


!McKdiObject methodsFor: 'accessing'!
json
	^ json!

answer
	^ answer!

at: aKey
	"Read one key, tolerating absence.  A missing key is a fact about the
	 backend answer, not a reason to stop drawing."
	(json isKindOf: Dictionary) ifFalse: [ ^ nil ].
	^ json at: aKey ifAbsent: [ nil ]!

at: aKey ifAbsent: aBlock
	(json isKindOf: Dictionary) ifFalse: [ ^ aBlock value ].
	^ json at: aKey ifAbsent: aBlock!

stringAt: aKey
	^ (self at: aKey) ifNil: [ '' ] ifNotNil: [ :v | v asString ]!

fieldRows
	"Every key of the underlying answer, as label/value pairs, so no field is
	 invisible just because no view was written for it yet."
	(json isKindOf: Dictionary) ifFalse: [ ^ #() ].
	^ (json keys asSortedCollection: [ :a :b | a <= b ]) asArray
		collect: [ :k | { k. json at: k } ]! !


!McKdiObject methodsFor: 'views'!
gtFieldsFor: aView
	<gtView>
	^ aView columnedList
		title: 'Fields';
		priority: 80;
		items: [ self fieldRows ];
		column: 'key' text: [ :each | each first ];
		column: 'value' text: [ :each | self describeValue: each second ];
		send: [ :each | each second ]!

gtCommandFor: aView
	<gtView>
	answer ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Command';
		priority: 95;
		object: [ answer ];
		view: #gtCommandFor:!

gtRawFor: aView
	<gtView>
	^ aView forward
		title: 'Raw';
		priority: 90;
		object: [ json ];
		view: #gtItemsFor:!

describeValue: aValue
	aValue ifNil: [ ^ '--' ].
	(aValue isKindOf: Collection) ifTrue: [
		aValue isString ifFalse: [
			^ aValue size printString, ' item(s)' ] ].
	^ aValue asString! !


!McKdiSource class methodsFor: 'instance creation'!
store: aStore json: aDictionary answer: anAnswer
	^ (self json: aDictionary answer: anAnswer) setStore: aStore! !


!McKdiSource methodsFor: 'initialization'!
setStore: aStore
	store := aStore.
	^ self! !


!McKdiSource methodsFor: 'accessing'!
store
	^ store!

binding
	^ store binding!

uri
	^ self at: 'uri'!

id
	^ self at: 'id'!

tier
	^ self at: 'tier'!

adapterType
	^ self at: 'adapter_type'!

sourceType
	^ self at: 'source_type'!

revisionCount
	^ self at: 'revision_count'!

revisionId
	self nodes.
	^ revisionId!

label
	^ self uri ifNil: [ self id ifNil: [ 'source' ] ]! !


!McKdiSource methodsFor: 'structure'!
loadTree
	"The structural tree of the latest revision.  Revision-scoped: the
	 revision_count column is what tells you older immutable revisions exist."
	| rows |
	treeAnswer := self binding runJson: { 'tree'. self uri }.
	revisionId := treeAnswer valueAt: 'source_revision_id'.
	rows := (treeAnswer valueAt: 'nodes') ifNil: [ #() ].
	nodes := rows collect: [ :each | McKdiNode source: self json: each answer: treeAnswer ].
	childIndex := Dictionary new.
	nodes do: [ :node |
		| parent |
		parent := node parentId.
		parent ifNotNil: [
			(childIndex at: parent ifAbsentPut: [ OrderedCollection new ]) add: node ] ].
	childIndex valuesDo: [ :each |
		each sort: [ :a :b | (a ordinal ifNil: [ 0 ]) <= (b ordinal ifNil: [ 0 ]) ] ].
	^ nodes!

nodes
	^ nodes ifNil: [ self loadTree ]!

childrenOf: aNodeId
	self nodes.
	^ (childIndex at: aNodeId ifAbsent: [ #() ]) asArray!

rootNodes
	^ self nodes select: [ :each | each parentId isNil ]!

treeAnswer
	self nodes.
	^ treeAnswer! !


!McKdiSource methodsFor: 'quality'!
loadQcAudit
	"kdi passage check on the head revision.  A read, so nothing to confirm.
	 The workbench displays the report and never recomputes validity."
	| a |
	self revisionId ifNil: [ ^ nil ].
	a := self binding runJson: { 'passage'. 'check'. self revisionId }.
	qcAudit := a hasValue
		ifTrue: [ McKdiQcAudit json: a value answer: a ]
		ifFalse: [ nil ].
	^ qcAudit!

qcAudit
	^ qcAudit ifNil: [ self loadQcAudit ]! !


!McKdiSource methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiSource(', self label asString, ')'! !


!McKdiSource methodsFor: 'views'!
gtStructureFor: aView
	<gtView>
	^ aView columnedTree
		title: 'Structure';
		priority: 10;
		items: [ self rootNodes ];
		children: [ :each | each children ];
		column: 'structure' text: [ :each | each treeLabel ];
		column: 'type' text: [ :each | each nodeType asString ] width: 120;
		column: 'direct' text: [ :each | each passageCount asString ] width: 80;
		column: 'subtree' text: [ :each | each subtreePassageCount asString ] width: 90!

gtPassagesFor: aView
	<gtView>
	^ aView forward
		title: 'Passages';
		priority: 20;
		object: [ self rootNodes
			ifEmpty: [ McKdiPassagePage empty ]
			ifNotEmpty: [ :roots | roots first passagePage ] ];
		view: #gtPassagesFor:!

gtQualityFor: aView
	<gtView>
	^ aView forward
		title: 'QC audit';
		priority: 30;
		object: [ self qcAudit ifNil: [ McKdiQcAudit json: Dictionary new answer: nil ] ];
		view: #gtSummaryFor:!

gtDetailsFor: aView
	<gtView>
	^ aView columnedList
		title: 'Source';
		priority: 40;
		items: [ {
			{ 'uri'. self uri }.
			{ 'id'. self id }.
			{ 'tier'. self tier }.
			{ 'source type'. self sourceType }.
			{ 'adapter'. self adapterType }.
			{ 'revisions'. self revisionCount }.
			{ 'head revision'. self revisionId }.
			{ 'nodes in head'. self nodes size } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]! !


!McKdiNode class methodsFor: 'instance creation'!
source: aSource json: aDictionary answer: anAnswer
	^ (self json: aDictionary answer: anAnswer) setSource: aSource! !


!McKdiNode methodsFor: 'initialization'!
setSource: aSource
	source := aSource.
	^ self! !


!McKdiNode methodsFor: 'accessing'!
source
	^ source!

binding
	^ source binding!

id
	^ self at: 'id'!

parentId
	^ self at: 'parent_id'!

ordinal
	^ self at: 'ordinal'!

depth
	^ self at: 'depth'!

nodeType
	^ (self at: 'node_type') ifNil: [ '--' ]!

title
	^ self at: 'title'!

stableKey
	^ self at: 'stable_key'!

passageCount
	"Direct passages on this node only.  The tree answer's occurrence_count is
	 not a subtree total: for a document root it is 0 while the root's subtree
	 holds every passage in the revision."
	^ (self at: 'occurrence_count') ifNil: [ 0 ]!

subtreePassageCount
	"What `kdi passage list` on this node would be scoped to, computed here
	 because the backend answer does not carry it."
	^ subtreeCount ifNil: [
		subtreeCount := self children
			inject: self passageCount
			into: [ :sum :each | sum + each subtreePassageCount ] ]!

children
	^ source childrenOf: self id!

treeLabel
	"What to call this node in the tree.  A block node normally has no title,
	 so the stable key is the only human-readable handle it has."
	self title ifNotNil: [ :t | t isEmpty ifFalse: [ ^ t ] ].
	self stableKey ifNotNil: [ :k | k isEmpty ifFalse: [ ^ k ] ].
	^ self id asString! !


!McKdiNode methodsFor: 'deprecated - compatibility'!
occurrenceCount
	"DEPRECATED -- use passageCount.  Occurrence is the storage word; passage is
	 the public one.  Kept because the two names denote the same number and
	 nothing written against the old one should break."
	^ self passageCount!

subtreeOccurrenceCount
	"DEPRECATED -- use subtreePassageCount."
	^ self subtreePassageCount! !


!McKdiNode methodsFor: 'passages'!
passageLimit
	^ 250!

loadPassages
	"The passages of this node's whole subtree, because passages attach only to
	 block nodes.  Bounded by the CLI's own --limit, and the page says so."
	| a |
	a := self binding runJson: {
		'passage'. 'list'. self id. '--limit'. self passageLimit printString }.
	passagePage := a hasValue
		ifTrue: [ McKdiPassagePage json: a value answer: a ]
		ifFalse: [ McKdiPassagePage empty ].
	^ passagePage!

passagePage
	^ passagePage ifNil: [ self loadPassages ]!

passages
	^ self passagePage passages! !


!McKdiNode methodsFor: 'provenance'!
loadProvenance
	provenanceAnswer := self binding runJson: { 'prov'. self id }.
	^ provenanceAnswer!

provenanceAnswer
	^ provenanceAnswer ifNil: [ self loadProvenance ]! !


!McKdiNode methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiNode(', self nodeType asString, ' ', self treeLabel asString, ')'! !


!McKdiNode methodsFor: 'views'!
gtChildrenFor: aView
	<gtView>
	self children ifEmpty: [ ^ aView empty ].
	^ aView columnedTree
		title: 'Children';
		priority: 10;
		items: [ self children ];
		children: [ :each | each children ];
		column: 'structure' text: [ :each | each treeLabel ];
		column: 'type' text: [ :each | each nodeType asString ] width: 120;
		column: 'direct' text: [ :each | each passageCount asString ] width: 80;
		column: 'subtree' text: [ :each | each subtreePassageCount asString ] width: 90!

gtPassagesFor: aView
	<gtView>
	^ aView forward
		title: 'Passages';
		priority: 20;
		object: [ self passagePage ];
		view: #gtPassagesFor:!

gtNodeFor: aView
	<gtView>
	^ aView columnedList
		title: 'Node';
		priority: 30;
		items: [ {
			{ 'id'. self id }.
			{ 'type'. self nodeType }.
			{ 'title'. self title }.
			{ 'stable key'. self stableKey }.
			{ 'depth'. self depth }.
			{ 'ordinal'. self ordinal }.
			{ 'passages here'. self passageCount }.
			{ 'passages in subtree'. self subtreePassageCount }.
			{ 'parent'. self parentId }.
			{ 'source'. source uri } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtProvenanceFor: aView
	<gtView>
	^ aView forward
		title: 'Provenance';
		priority: 50;
		object: [ self provenanceAnswer ];
		view: #gtValueFor:! !


!McKdiPassagePage class methodsFor: 'instance creation'!
empty
	^ self json: Dictionary new answer: nil! !


!McKdiPassagePage methodsFor: 'accessing'!
passages
	^ ((self at: 'passages') ifNil: [ #() ])
		collect: [ :each | McKdiPassage json: each answer: answer ]!

total
	^ (self at: 'total') ifNil: [ 0 ]!

limit
	^ self at: 'limit'!

offset
	^ self at: 'offset'!

isTruncated
	^ (self at: 'truncated') = true!

scopeKind
	^ self at: 'scope_kind'!

scopeId
	^ self at: 'scope_id'!

boundDescription
	"State the bound in the label rather than letting a scroll bar imply one."
	| shown |
	shown := ((self at: 'passages') ifNil: [ #() ]) size.
	^ shown printString, ' of ', self total printString, ' shown',
		(self isTruncated ifTrue: [ ' (truncated)' ] ifFalse: [ '' ])! !


!McKdiPassagePage methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiPassagePage(', self boundDescription, ')'! !


!McKdiPassagePage methodsFor: 'views'!
gtPassagesFor: aView
	<gtView>
	^ aView columnedList
		title: 'Passages';
		priority: 10;
		items: [ self passages ];
		column: 'order' text: [ :each | each ordinal asString ] width: 70;
		column: 'type' text: [ :each | each contentType asString ] width: 110;
		column: 'tier' text: [ :each | each tier asString ] width: 80;
		column: 'text' text: [ :each | each previewText ];
		send: [ :each | each ]!

gtBoundFor: aView
	<gtView>
	^ aView columnedList
		title: 'Bound';
		priority: 60;
		items: [ {
			{ 'shown'. self boundDescription }.
			{ 'total'. self total }.
			{ 'limit'. self limit }.
			{ 'offset'. self offset }.
			{ 'scope'. self scopeKind }.
			{ 'scope id'. self scopeId } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]! !


!McKdiPassage methodsFor: 'accessing'!
id
	^ self at: 'id'!

text
	^ (self at: 'text') ifNil: [ '' ]!

exactQuote
	^ self at: 'exact_quote'!

contentType
	^ (self at: 'content_type') ifNil: [ '--' ]!

contentHash
	^ self at: 'content_hash'!

tier
	^ (self at: 'tier') ifNil: [ '--' ]!

ordinal
	^ self at: 'ordinal'!

nodeTitle
	^ self at: 'node_title'!

nodeType
	^ self at: 'node_type'!

headingPath
	^ (self at: 'heading_path') ifNil: [ #() ]!

headingPathString
	^ ' > ' join: (self headingPath collect: [ :each | each asString ])!

selectorType
	^ self at: 'selector_type'!

selector
	^ self at: 'selector'!

resolutionStatus
	^ self at: 'resolution_status'!

sourceUri
	^ self at: 'source_uri'!

revisionId
	^ self at: 'source_revision_id'!

previewText
	| t |
	t := self text copyReplaceAll: (String with: Character cr) with: ' '.
	t := t copyReplaceAll: (String with: Character lf) with: ' '.
	^ t size > 140 ifTrue: [ (t first: 140), '...' ] ifFalse: [ t ]! !


!McKdiPassage methodsFor: 'grounding ui'!
groundingElement
	"The composed view: two text cards and a verdict bar."
	| container |
	container := BrVerticalPane new
		matchParent;
		padding: (BlInsets all: 12);
		cellSpacing: 10;
		yourself.
	container addChild: self groundingVerdictBar.
	container addChild: (self
		groundingCard: 'NORMALIZED TEXT'
		subtitle: 'what the content hash covers, and what a citation quotes'
		body: self text
		accent: (Color r: 0.15 g: 0.42 b: 0.66)).
	container addChild: (self
		groundingCard: 'EXACT QUOTED SOURCE CHARACTERS'
		subtitle: (self exactQuote
			ifNil: [ 'this selector locates a region, not characters' ]
			ifNotNil: [ :q | 'the run of characters the ', self selectorType asString,
				' selector actually read' ])
		body: (self exactQuote ifNil: [ '(no quote recorded)' ])
		accent: (Color r: 0.55 g: 0.35 b: 0.09)).
	^ container!

groundingCard: aTitle subtitle: aSubtitle body: aString accent: aColor
	"One labelled panel: accent rule, heading, explanatory subtitle, body text."
	| card header |
	card := BrVerticalPane new
		hMatchParent;
		vFitContent;
		padding: (BlInsets all: 10);
		cellSpacing: 4;
		background: (Color gray: 0.96);
		border: (BlBorder paint: (Color gray: 0.85) width: 1);
		yourself.
	header := BrLabel new
		aptitude: (BrGlamorousLabelAptitude new
			fontSize: 11;
			bold;
			foreground: aColor);
		text: aTitle;
		yourself.
	card addChild: header.
	card addChild: (BrLabel new
		aptitude: (BrGlamorousLabelAptitude new fontSize: 10;
			foreground: (Color gray: 0.45));
		text: aSubtitle;
		yourself).
	card addChild: (BrEditor new
		aptitude: BrGlamorousRegularEditorAptitude new;
		beReadOnlyWithSelection;
		hMatchParent;
		vFitContentLimited;
		text: aString asRopedText;
		yourself).
	^ card!

groundingVerdictBar
	"The comparison as a pill: green when the two strings are identical, amber
	 when normalization changed them, grey when there is nothing to compare."
	| bar colour verdict |
	verdict := self groundingVerdict.
	colour := verdict = #identical
		ifTrue: [ Color r: 0.11 g: 0.47 b: 0.22 ]
		ifFalse: [ verdict = #differs
			ifTrue: [ Color r: 0.70 g: 0.45 b: 0.05 ]
			ifFalse: [ Color gray: 0.45 ] ].
	bar := BrHorizontalPane new hMatchParent; vFitContent; cellSpacing: 8; yourself.
	bar addChild: (BrLabel new
		aptitude: (BrGlamorousLabelAptitude new fontSize: 11; bold;
			foreground: Color white);
		padding: (BlInsets top: 3 left: 9 bottom: 3 right: 9);
		background: colour;
		text: self groundingVerdictLabel;
		yourself).
	bar addChild: (BrLabel new
		aptitude: (BrGlamorousLabelAptitude new fontSize: 11;
			foreground: (Color gray: 0.3));
		text: self groundingVerdictDetail;
		yourself).
	bar addChild: (BrLabel new
		aptitude: (BrGlamorousLabelAptitude new fontSize: 10;
			foreground: (Color gray: 0.5));
		text: 'resolution: ', self resolutionStatus asString;
		yourself).
	^ bar!

firstDifferenceIndex
	"Where the two strings first diverge, 1-based, or nil if one is a prefix of
	 the other.  Saying `they differ' without saying where is not much of an
	 answer when both are a paragraph long."
	| a b |
	a := self text.
	b := self exactQuote ifNil: [ ^ nil ].
	1 to: (a size min: b size) do: [ :i |
		(a at: i) = (b at: i) ifFalse: [ ^ i ] ].
	^ nil!

groundingVerdict
	self exactQuote ifNil: [ ^ #incomparable ].
	^ self exactQuote = self text ifTrue: [ #identical ] ifFalse: [ #differs ]!

groundingVerdictLabel
	^ self groundingVerdict = #identical
		ifTrue: [ 'IDENTICAL' ]
		ifFalse: [ self groundingVerdict = #differs
			ifTrue: [ 'DIFFERS' ]
			ifFalse: [ 'NOT COMPARABLE' ] ]!

groundingVerdictDetail
	self groundingVerdict = #identical ifTrue: [
		^ 'the normalized text and the quoted source characters are the same string' ].
	self groundingVerdict = #differs ifTrue: [
		| delta at |
		delta := self text size - self exactQuote size.
		delta = 0 ifFalse: [
			^ 'normalization changed the length by ', delta abs printString,
				' character(s) (', self exactQuote size printString, ' quoted, ',
				self text size printString, ' normalized)' ].
		at := self firstDifferenceIndex.
		^ 'same length, but the characters differ',
			(at ifNil: [ '' ] ifNotNil: [ :i | ' from position ', i printString ]) ].
	^ 'this selector locates a region rather than characters, so there is no quote to compare'! !


!McKdiPassage methodsFor: 'grounding'!
groundingReport
	"Two different strings, deliberately side by side: what the content hash
	 covers and a citation quotes, and the run of characters the selector
	 actually read.  A selector that locates a region rather than characters
	 records no quote, and saying so is an answer, not a missing field."
	| s quote |
	s := WriteStream on: String new.
	s nextPutAll: 'NORMALIZED TEXT'; cr; cr.
	s nextPutAll: self text; cr; cr.
	s nextPutAll: 'EXACT QUOTED SOURCE CHARACTERS'; cr; cr.
	quote := self exactQuote.
	quote
		ifNil: [ s nextPutAll: '(none -- this selector locates a region, not characters)' ]
		ifNotNil: [ s nextPutAll: quote ].
	s cr; cr; nextPutAll: 'COMPARISON: '.
	quote
		ifNil: [ s nextPutAll: 'not comparable; selector type is ', self selectorType asString ]
		ifNotNil: [
			s nextPutAll: (quote = self text
				ifTrue: [ 'identical' ]
				ifFalse: [ 'they differ -- normalization changed ',
					(self text size - quote size) abs printString, ' character(s) of length' ]) ].
	s cr; cr; nextPutAll: 'resolution: ', self resolutionStatus asString.
	^ s contents! !


!McKdiPassage methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiPassage(', self contentType asString, ' ', self previewText, ')'! !


!McKdiPassage methodsFor: 'views'!
gtGroundingFor: aView
	<gtView>
	"Three panels, not three text headings.  The whole point of this view is
	 that two different strings are being compared, so they get two visually
	 separate cards and the verdict gets a coloured pill rather than a line of
	 prose that reads like more of the same text."
	^ aView explicit
		title: 'Grounding';
		priority: 10;
		stencil: [ self groundingElement ]!

gtGroundingReportFor: aView
	<gtView>
	"The same thing as plain text, for copying."
	^ aView textEditor
		title: 'Grounding (text)';
		priority: 15;
		text: [ self groundingReport ]!

gtTextFor: aView
	<gtView>
	^ aView textEditor
		title: 'Text';
		priority: 20;
		text: [ self text ]!

gtPassageFor: aView
	<gtView>
	^ aView columnedList
		title: 'Passage';
		priority: 30;
		items: [ {
			{ 'id'. self id }.
			{ 'source'. self sourceUri }.
			{ 'revision'. self revisionId }.
			{ 'heading path'. self headingPathString }.
			{ 'node'. self nodeType }.
			{ 'content type'. self contentType }.
			{ 'tier'. self tier }.
			{ 'ordinal'. self ordinal }.
			{ 'selector'. self selectorType }.
			{ 'resolution'. self resolutionStatus }.
			{ 'content hash'. self contentHash } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtSelectorFor: aView
	<gtView>
	self selector ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Selector';
		priority: 40;
		object: [ self selector ];
		view: #gtItemsFor:! !


!McKdiQcAudit methodsFor: 'accessing'!
revisionId
	^ self at: 'revision_id'!

isValid
	^ (self at: 'valid') = true!

verdict
	"Valid means exactly no error-severity finding.  Warnings remain visible and
	 are facts, not failures."
	^ self isValid ifTrue: [ 'VALID' ] ifFalse: [ 'INVALID' ]!

checks
	^ (self at: 'checks') ifNil: [ #() ]!

counts
	^ (self at: 'counts') ifNil: [ Dictionary new ]!

countAt: aKey
	^ self counts at: aKey ifAbsent: [ 0 ]!

issues
	^ (self at: 'issues') ifNil: [ #() ]! !


!McKdiQcAudit methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiQcAudit(', self verdict, ')'! !


!McKdiQcAudit methodsFor: 'views'!
gtSummaryFor: aView
	<gtView>
	^ aView columnedList
		title: 'Audit';
		priority: 10;
		items: [ {
			{ 'verdict'. self verdict }.
			{ 'revision'. self revisionId }.
			{ 'checks run'. ', ' join: (self checks collect: [ :e | e asString ]) }.
			{ 'passages'. self countAt: 'occurrences' }.
			{ 'nodes'. self countAt: 'structural_nodes' }.
			{ 'content'. self countAt: 'morsels' }.
			{ 'errors'. self countAt: 'errors' }.
			{ 'warnings'. self countAt: 'warnings' } } ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtIssuesFor: aView
	<gtView>
	self issues ifEmpty: [ ^ aView empty ].
	^ aView columnedList
		title: 'Issues';
		priority: 20;
		items: [ self issues ];
		column: 'severity' text: [ :each | each at: 'severity' ifAbsent: [ '--' ] ] width: 100;
		column: 'code' text: [ :each | each at: 'code' ifAbsent: [ '--' ] ] width: 260;
		column: 'subject' text: [ :each | (each at: 'subject' ifAbsent: [ '--' ]) asString ];
		send: [ :each | each ]! !
