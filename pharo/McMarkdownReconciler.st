"
McMarkdownReconciler -- deterministic, monotonic reconciliation between two
McMarkdownDocumentSnapshot revisions.

Scope is the document root sibling sequence: the block sequence McRichEdit
owns and renders.  A matched block is the atomic render patch, so a block whose
subtree fingerprint changed is dirty as a whole and no descent is required.

Equality is exact kind plus subtree fingerprint.  Alignment is monotonic:

  1. fingerprints unique on both sides are patience anchors, reduced to a
     longest increasing run so the anchor set itself is monotonic,
  2. each remaining run is trimmed by common prefix and suffix, then aligned
     with an LCS over the same equality relation, and
  3. a leftover gap whose old and new members correspond one-to-one by kind is
     treated as a local modification, which keeps the lineage while marking the
     block dirty.

Because alignment never crosses an anchor, a reordering or cross-parent move
degrades to remove-plus-add rather than producing a non-monotonic match.

Lineage IDs are opaque identities carried from the old revision to confidently
matched new nodes.  Unmatched new nodes receive freshly allocated IDs, and
unmatched old lineages retire.  Addresses and fingerprints stay separate from
lineage: an unchanged block whose address or range shifted is reported as
relocated, not dirty.

Chunk format: load with fileIn.
"!

Object subclass: #McMarkdownLineageAllocator
	instanceVariableNames: 'prefix counter'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownLineageAllocator methodsFor: 'accessing'!
prefix
	^ prefix ifNil: [ prefix := 'ln' ]!

prefix: aString
	prefix := aString!

counter
	^ counter ifNil: [ counter := 0 ]! !

!McMarkdownLineageAllocator methodsFor: 'allocating'!
next
	counter := self counter + 1.
	^ self prefix , '-' , counter printString!

observeLineageId: anId
	"Keep freshly allocated IDs above every ID already carried by a revision,
	 so a reconciler created per document run cannot reissue a live identity."
	| digits value |
	(anId isString and: [ anId beginsWith: self prefix , '-' ]) ifFalse: [ ^ self ].
	digits := anId allButFirst: self prefix size + 1.
	digits isEmpty ifTrue: [ ^ self ].
	digits do: [ :character | character isDigit ifFalse: [ ^ self ] ].
	value := digits asNumber.
	value > self counter ifTrue: [ counter := value ]! !

Object subclass: #McMarkdownReconciliation
	instanceVariableNames: 'oldSnapshot newSnapshot oldNodes newNodes newForOld oldForNew unchangedNodes modifiedNodes addedNodes removedNodes relocatedNodes dirtyNodes retiredLineageIds lineageIndex totalWeight dirtyWeight ambiguous'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownReconciliation class methodsFor: 'instance creation'!
oldSnapshot: anOldSnapshot newSnapshot: aNewSnapshot oldNodes: anOldCollection newNodes: aNewCollection matches: aMatchArray ambiguous: aBoolean
	^ self new
		setOldSnapshot: anOldSnapshot
		newSnapshot: aNewSnapshot
		oldNodes: anOldCollection
		newNodes: aNewCollection
		matches: aMatchArray
		ambiguous: aBoolean;
		yourself! !

!McMarkdownReconciliation methodsFor: 'initialization'!
setOldSnapshot: anOldSnapshot newSnapshot: aNewSnapshot oldNodes: anOldCollection newNodes: aNewCollection matches: aMatchArray ambiguous: aBoolean
	oldSnapshot := anOldSnapshot.
	newSnapshot := aNewSnapshot.
	oldNodes := anOldCollection asArray.
	newNodes := aNewCollection asArray.
	ambiguous := aBoolean.
	newForOld := IdentityDictionary new.
	oldForNew := IdentityDictionary new.
	unchangedNodes := OrderedCollection new.
	modifiedNodes := OrderedCollection new.
	addedNodes := OrderedCollection new.
	removedNodes := OrderedCollection new.
	relocatedNodes := OrderedCollection new.
	dirtyNodes := OrderedCollection new.
	retiredLineageIds := OrderedCollection new.
	lineageIndex := Dictionary new.
	totalWeight := 0.
	dirtyWeight := 0.
	self classify: aMatchArray!

classify: aMatchArray
	| matchedOld |
	matchedOld := Set new.
	newNodes withIndexDo: [ :node :index |
		| weight oldIndex oldNode |
		weight := self weightOf: node.
		totalWeight := totalWeight + weight.
		node lineageId ifNotNil: [ :id | lineageIndex at: id put: node ].
		oldIndex := aMatchArray at: index.
		oldIndex = 0
			ifTrue: [
				addedNodes add: node.
				dirtyNodes add: node.
				dirtyWeight := dirtyWeight + weight ]
			ifFalse: [
				matchedOld add: oldIndex.
				oldNode := oldNodes at: oldIndex.
				newForOld at: oldNode put: node.
				oldForNew at: node put: oldNode.
				(self isExactMatchOld: oldNode new: node)
					ifTrue: [
						unchangedNodes add: node.
						(self hasMovedOld: oldNode new: node)
							ifTrue: [ relocatedNodes add: node ] ]
					ifFalse: [
						modifiedNodes add: node.
						dirtyNodes add: node.
						dirtyWeight := dirtyWeight + weight ] ] ].
	oldNodes withIndexDo: [ :node :index |
		(matchedOld includes: index) ifFalse: [
			removedNodes add: node.
			node lineageId ifNotNil: [ :id | retiredLineageIds add: id ] ] ]!

weightOf: aNode
	"Phase-one render weight: a fixed block cost plus its source size.  Richer
	 per-kind weights belong to the render policy, not to matching."
	^ 1 + (aNode sourceRange ifNil: [ 0 ] ifNotNil: [ :range | range size ])!

isExactMatchOld: anOldNode new: aNewNode
	^ anOldNode kind = aNewNode kind
		and: [ anOldNode subtreeFingerprint = aNewNode subtreeFingerprint ]!

hasMovedOld: anOldNode new: aNewNode
	^ anOldNode addressString ~= aNewNode addressString
		or: [ anOldNode sourceRange ~= aNewNode sourceRange ]! !

!McMarkdownReconciliation methodsFor: 'accessing'!
oldSnapshot
	^ oldSnapshot!

newSnapshot
	^ newSnapshot!

oldNodes
	^ oldNodes copy!

newNodes
	^ newNodes copy!

unchangedNodes
	"New-revision nodes whose kind and subtree fingerprint survived unchanged."
	^ unchangedNodes asArray!

dirtyNodes
	"New-revision nodes McRichEdit must render: added plus modified, in
	 document order."
	^ dirtyNodes asArray!

modifiedNodes
	^ modifiedNodes asArray!

addedNodes
	^ addedNodes asArray!

removedNodes
	"Old-revision nodes with no successor; their render owners must be dropped."
	^ removedNodes asArray!

relocatedNodes
	"Unchanged nodes whose address or source range moved.  Their attributes may
	 be relocated but must not be restyled."
	^ relocatedNodes asArray!

retiredLineageIds
	^ retiredLineageIds asArray!

carriedLineageIds
	"Lineages that survived into the new revision, in document order.  Iterating
	 the match dictionary instead would answer them in identity-hash order,
	 which is not reproducible across images."
	^ (newNodes
		select: [ :each | oldForNew includesKey: each ]
		thenCollect: [ :each | each lineageId ]) asArray! !

!McMarkdownReconciliation methodsFor: 'querying'!
matchFor: aNewNode
	"The old-revision node a new node was matched to, or nil when it is new."
	^ oldForNew at: aNewNode ifAbsent: [ nil ]!

successorOf: anOldNode
	^ newForOld at: anOldNode ifAbsent: [ nil ]!

lineageIdFor: aNewNode
	^ aNewNode lineageId!

nodeForLineage: anId
	^ lineageIndex at: anId ifAbsent: [ nil ]!

isUnchanged: aNewNode
	^ unchangedNodes anySatisfy: [ :each | each == aNewNode ]!

isDirty: aNewNode
	^ dirtyNodes anySatisfy: [ :each | each == aNewNode ]!

isFirstRevision
	^ oldSnapshot isNil! !

!McMarkdownReconciliation methodsFor: 'render policy'!
totalWeight
	^ totalWeight!

dirtyWeight
	^ dirtyWeight!

dirtyFraction
	"Share of the new revision's render weight that must be redrawn.  An empty
	 new revision that replaced content counts as fully dirty so the caller
	 falls back to a full pass rather than dividing by zero."
	totalWeight = 0 ifTrue: [
		^ (removedNodes isEmpty and: [ oldSnapshot notNil ]) ifTrue: [ 0.0 ] ifFalse: [ 1.0 ] ].
	^ (dirtyWeight / totalWeight) asFloat!

confidence
	^ ambiguous ifTrue: [ 0.0 ] ifFalse: [ 1.0 ]!

requiresFullRender
	"True when matching bailed out, so lineage ownership cannot be trusted."
	^ ambiguous!

fallbackReason
	^ ambiguous
		ifTrue: [ 'a sibling run exceeded the deterministic alignment budget' ]
		ifFalse: [ nil ]!

printOn: aStream
	aStream
		nextPutAll: self class name asString;
		nextPutAll: '(unchanged: ';
		print: unchangedNodes size;
		nextPutAll: ' modified: ';
		print: modifiedNodes size;
		nextPutAll: ' added: ';
		print: addedNodes size;
		nextPutAll: ' removed: ';
		print: removedNodes size;
		nextPutAll: ' dirty: ';
		print: self dirtyFraction;
		nextPut: $)! !

Object subclass: #McMarkdownReconciler
	instanceVariableNames: 'allocator maximumAlignmentCells ambiguous'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownReconciler class methodsFor: 'reconciling'!
reconcileFrom: anOldSnapshot to: aNewSnapshot
	"Convenience for a one-shot comparison.  A live editor should keep one
	 reconciler per document so lineage allocation stays sequential."
	^ self new reconcileFrom: anOldSnapshot to: aNewSnapshot! !

!McMarkdownReconciler methodsFor: 'accessing'!
allocator
	^ allocator ifNil: [ allocator := McMarkdownLineageAllocator new ]!

maximumAlignmentCells
	"Alignment budget for one unanchored run.  Beyond it the run is reported as
	 ambiguous instead of matched, because a mis-owned block is worse than a
	 full render."
	^ maximumAlignmentCells ifNil: [ 4096 ]!

maximumAlignmentCells: anInteger
	maximumAlignmentCells := anInteger! !

!McMarkdownReconciler methodsFor: 'reconciling'!
reconcileFrom: anOldSnapshot to: aNewSnapshot
	| oldNodes newNodes matches |
	aNewSnapshot ifNil: [ ^ self error: 'a new snapshot is required' ].
	ambiguous := false.
	newNodes := aNewSnapshot root children.
	oldNodes := anOldSnapshot ifNil: [ #() ] ifNotNil: [ anOldSnapshot root children ].
	self seedLineagesIn: anOldSnapshot.
	matches := self alignOld: oldNodes new: newNodes.
	self carryLineagesFrom: oldNodes to: newNodes matches: matches.
	aNewSnapshot root lineageId: (anOldSnapshot
		ifNil: [ self allocator next ]
		ifNotNil: [ anOldSnapshot root lineageId ]).
	^ McMarkdownReconciliation
		oldSnapshot: anOldSnapshot
		newSnapshot: aNewSnapshot
		oldNodes: oldNodes
		newNodes: newNodes
		matches: matches
		ambiguous: ambiguous!

seedLineagesIn: aSnapshot
	"A snapshot arrives without lineage; the first reconciliation gives the old
	 revision its identities so later revisions have something to carry."
	| nodes |
	aSnapshot ifNil: [ ^ self ].
	nodes := (OrderedCollection with: aSnapshot root)
		addAll: aSnapshot root children;
		yourself.
	nodes do: [ :node | self allocator observeLineageId: node lineageId ].
	nodes do: [ :node | node lineageId ifNil: [ node lineageId: self allocator next ] ]!

carryLineagesFrom: oldNodes to: newNodes matches: aMatchArray
	newNodes withIndexDo: [ :node :index |
		| oldIndex |
		oldIndex := aMatchArray at: index.
		oldIndex = 0
			ifTrue: [ node lineageId: self allocator next ]
			ifFalse: [ node lineageId: (oldNodes at: oldIndex) lineageId ] ]! !

!McMarkdownReconciler methodsFor: 'matching'!
matchKeyFor: aNode
	"Exact structural equality: stable kind plus subtree fingerprint.  Kind is
	 repeated explicitly so two kinds sharing a fingerprint cannot collide."
	^ aNode kind , String tab , aNode subtreeFingerprint!

alignOld: oldNodes new: newNodes
	"Answer, per new-node index, the matched old-node index or 0."
	| matches anchors |
	matches := Array new: newNodes size withAll: 0.
	(oldNodes isEmpty or: [ newNodes isEmpty ]) ifTrue: [ ^ matches ].
	anchors := self monotonicAnchorsOld: oldNodes new: newNodes.
	anchors do: [ :pair | matches at: pair second put: pair first ].
	self alignRunsOld: oldNodes new: newNodes anchors: anchors into: matches.
	^ matches!

monotonicAnchorsOld: oldNodes new: newNodes
	"Patience anchors: keys occurring exactly once on both sides, reduced to a
	 longest increasing run so the anchors themselves never cross."
	| oldCounts newCounts newPositions candidates |
	oldCounts := self keyCountsFor: oldNodes.
	newCounts := self keyCountsFor: newNodes.
	newPositions := Dictionary new.
	newNodes withIndexDo: [ :node :index |
		newPositions at: (self matchKeyFor: node) ifAbsentPut: [ index ] ].
	candidates := OrderedCollection new.
	oldNodes withIndexDo: [ :node :index |
		| key |
		key := self matchKeyFor: node.
		((oldCounts at: key ifAbsent: [ 0 ]) = 1 and: [ (newCounts at: key ifAbsent: [ 0 ]) = 1 ])
			ifTrue: [ candidates add: { index. newPositions at: key } ] ].
	^ self longestIncreasingRunIn: candidates!

keyCountsFor: aCollection
	| counts |
	counts := Dictionary new.
	aCollection do: [ :node |
		| key |
		key := self matchKeyFor: node.
		counts at: key put: (counts at: key ifAbsent: [ 0 ]) + 1 ].
	^ counts!

longestIncreasingRunIn: aCollection
	"Patience piles over pairs already ordered by their old index."
	| pairs piles predecessors result cursor |
	pairs := aCollection asArray.
	pairs isEmpty ifTrue: [ ^ OrderedCollection new ].
	piles := OrderedCollection new.
	predecessors := Array new: pairs size withAll: 0.
	pairs withIndexDo: [ :pair :index |
		| low high position |
		low := 1.
		high := piles size.
		[ low <= high ] whileTrue: [
			| middle |
			middle := (low + high) // 2.
			(pairs at: (piles at: middle)) second < pair second
				ifTrue: [ low := middle + 1 ]
				ifFalse: [ high := middle - 1 ] ].
		position := low.
		position > 1 ifTrue: [ predecessors at: index put: (piles at: position - 1) ].
		position > piles size
			ifTrue: [ piles add: index ]
			ifFalse: [ piles at: position put: index ] ].
	result := OrderedCollection new.
	cursor := piles last.
	[ cursor = 0 ] whileFalse: [
		result addFirst: (pairs at: cursor).
		cursor := predecessors at: cursor ].
	^ result!

alignRunsOld: oldNodes new: newNodes anchors: anchors into: matches
	"Align each run between consecutive anchors, plus the trailing run."
	| previousOld previousNew bounded |
	previousOld := 0.
	previousNew := 0.
	bounded := anchors asOrderedCollection
		copyWith: { oldNodes size + 1. newNodes size + 1 }.
	bounded do: [ :pair |
		self
			alignRunOld: (previousOld + 1 to: pair first - 1) asArray
			new: (previousNew + 1 to: pair second - 1) asArray
			nodesOld: oldNodes
			nodesNew: newNodes
			into: matches.
		previousOld := pair first.
		previousNew := pair second ]!

alignRunOld: oldRun new: newRun nodesOld: oldNodes nodesNew: newNodes into: matches
	"Trim the common prefix and suffix, then align what remains.  Trimming
	 first gives a duplicate run the append bias: the surviving prefix keeps its
	 lineages and the extra copy is the new one."
	| oldKeys newKeys limit prefix suffix |
	(oldRun isEmpty or: [ newRun isEmpty ]) ifTrue: [ ^ self ].
	oldKeys := oldRun collect: [ :index | self matchKeyFor: (oldNodes at: index) ].
	newKeys := newRun collect: [ :index | self matchKeyFor: (newNodes at: index) ].
	limit := oldRun size min: newRun size.
	prefix := 0.
	[ prefix < limit and: [ (oldKeys at: prefix + 1) = (newKeys at: prefix + 1) ] ]
		whileTrue: [ prefix := prefix + 1 ].
	suffix := 0.
	[ suffix < (limit - prefix)
		and: [ (oldKeys at: oldKeys size - suffix) = (newKeys at: newKeys size - suffix) ] ]
		whileTrue: [ suffix := suffix + 1 ].
	1 to: prefix do: [ :offset |
		matches at: (newRun at: offset) put: (oldRun at: offset) ].
	1 to: suffix do: [ :offset |
		matches
			at: (newRun at: newRun size - offset + 1)
			put: (oldRun at: oldRun size - offset + 1) ].
	self
		alignMiddleOld: (oldRun copyFrom: prefix + 1 to: oldRun size - suffix)
		new: (newRun copyFrom: prefix + 1 to: newRun size - suffix)
		nodesOld: oldNodes
		nodesNew: newNodes
		into: matches!

alignMiddleOld: oldRun new: newRun nodesOld: oldNodes nodesNew: newNodes into: matches
	"Exact LCS first, then treat each leftover gap that lines up one-to-one by
	 kind as a local modification of the same lineage."
	| pairs previousOld previousNew bounded |
	(oldRun isEmpty or: [ newRun isEmpty ]) ifTrue: [ ^ self ].
	pairs := self
		commonSubsequenceOld: oldRun
		new: newRun
		nodesOld: oldNodes
		nodesNew: newNodes.
	pairs do: [ :pair | matches at: pair second put: pair first ].
	previousOld := oldRun first - 1.
	previousNew := newRun first - 1.
	bounded := pairs asOrderedCollection
		copyWith: { oldRun last + 1. newRun last + 1 }.
	bounded do: [ :pair |
		self
			matchModifiedOld: (previousOld + 1 to: pair first - 1) asArray
			new: (previousNew + 1 to: pair second - 1) asArray
			nodesOld: oldNodes
			nodesNew: newNodes
			into: matches.
		previousOld := pair first.
		previousNew := pair second ]!

matchModifiedOld: oldRun new: newRun nodesOld: oldNodes nodesNew: newNodes into: matches
	"An unmatched gap is a local edit only when its two sides correspond
	 exactly, position by position and kind by kind.  Anything else -- an
	 insertion, a deletion, a split, a merge -- stays add-plus-remove, because
	 guessing there could attach a retained widget to unrelated syntax."
	oldRun isEmpty ifTrue: [ ^ self ].
	oldRun size = newRun size ifFalse: [ ^ self ].
	1 to: oldRun size do: [ :offset |
		(oldNodes at: (oldRun at: offset)) kind = (newNodes at: (newRun at: offset)) kind
			ifFalse: [ ^ self ] ].
	1 to: oldRun size do: [ :offset |
		matches at: (newRun at: offset) put: (oldRun at: offset) ]!

commonSubsequenceOld: oldRun new: newRun nodesOld: oldNodes nodesNew: newNodes
	"Deterministic LCS over exact structural keys.  Backtracking prefers the
	 earlier old node on ties so repeated runs align identically every time."
	| oldKeys newKeys rows columns table pairs row column |
	rows := oldRun size.
	columns := newRun size.
	rows * columns > self maximumAlignmentCells ifTrue: [
		ambiguous := true.
		^ OrderedCollection new ].
	oldKeys := oldRun collect: [ :index | self matchKeyFor: (oldNodes at: index) ].
	newKeys := newRun collect: [ :index | self matchKeyFor: (newNodes at: index) ].
	table := (0 to: rows) collect: [ :each | Array new: columns + 1 withAll: 0 ].
	1 to: rows do: [ :i |
		1 to: columns do: [ :j |
			(oldKeys at: i) = (newKeys at: j)
				ifTrue: [ (table at: i + 1) at: j + 1 put: ((table at: i) at: j) + 1 ]
				ifFalse: [
					(table at: i + 1)
						at: j + 1
						put: (((table at: i) at: j + 1) max: ((table at: i + 1) at: j)) ] ] ].
	pairs := OrderedCollection new.
	row := rows.
	column := columns.
	[ row > 0 and: [ column > 0 ] ] whileTrue: [
		(oldKeys at: row) = (newKeys at: column)
			ifTrue: [
				pairs addFirst: { oldRun at: row. newRun at: column }.
				row := row - 1.
				column := column - 1 ]
			ifFalse: [
				((table at: row) at: column + 1) >= ((table at: row + 1) at: column)
					ifTrue: [ row := row - 1 ]
					ifFalse: [ column := column - 1 ] ] ].
	^ pairs! !
