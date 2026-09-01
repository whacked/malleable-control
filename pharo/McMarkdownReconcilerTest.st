"Tests for monotonic lineage reconciliation between two snapshots.  Load after
McMarkdown.st, McMarkdownSnapshot.st and McMarkdownReconciler.st."!

TestCase subclass: #McMarkdownReconcilerTest
	instanceVariableNames: 'reconciler'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownReconcilerTest methodsFor: 'running'!
setUp
	super setUp.
	reconciler := McMarkdownReconciler new! !

!McMarkdownReconcilerTest methodsFor: 'helpers'!
snapshotFor: aString
	^ McMarkdownDocumentSnapshot parseSource: aString!

blocksOf: aSnapshot
	^ aSnapshot root children!

lineagesOf: aSnapshot
	^ (self blocksOf: aSnapshot) collect: [ :each | each lineageId ]!

addressesOf: aCollection
	^ (aCollection collect: [ :each | each addressString ]) asArray!

matchMapFor: aReconciliation
	"An address-to-address view of the matching, independent of allocation order."
	| map |
	map := Dictionary new.
	(self blocksOf: aReconciliation newSnapshot) do: [ :node |
		map
			at: node addressString
			put: ((aReconciliation matchFor: node)
				ifNil: [ nil ]
				ifNotNil: [ :old | old addressString ]) ].
	^ map! !

!McMarkdownReconcilerTest methodsFor: 'tests - baseline'!
testFirstRevisionAddsEveryBlockWithFreshLineages
	| snapshot result |
	snapshot := self snapshotFor: 'alpha

beta'.
	result := reconciler reconcileFrom: nil to: snapshot.
	self assert: result isFirstRevision.
	self assert: result addedNodes size equals: 2.
	self assert: result unchangedNodes isEmpty.
	self assert: result dirtyNodes size equals: 2.
	self assert: result dirtyFraction equals: 1.0.
	self assert: (self lineagesOf: snapshot) asSet size equals: 2.
	self assert: snapshot root lineageId notNil!

testIdenticalSourceLeavesEverythingUnchanged
	| before after result |
	before := self snapshotFor: '# title

alpha

beta'.
	after := self snapshotFor: '# title

alpha

beta'.
	reconciler reconcileFrom: nil to: before.
	result := reconciler reconcileFrom: before to: after.
	self assert: result unchangedNodes size equals: 3.
	self assert: result dirtyNodes isEmpty.
	self assert: result removedNodes isEmpty.
	self assert: result retiredLineageIds isEmpty.
	self assert: result relocatedNodes isEmpty.
	self assert: result dirtyFraction equals: 0.0.
	self assert: (self lineagesOf: after) equals: (self lineagesOf: before)!

testLineageIdsAreUniqueWithinARevision
	| before after result |
	before := self snapshotFor: 'alpha

beta'.
	after := self snapshotFor: 'alpha

inserted

beta

tail'.
	reconciler reconcileFrom: nil to: before.
	result := reconciler reconcileFrom: before to: after.
	self assert: (self lineagesOf: after) asSet size equals: 4.
	self deny: ((self lineagesOf: after) anySatisfy: [ :each | each isNil ]).
	self assert: result confidence equals: 1.0.
	self deny: result requiresFullRender.
	self assert: result fallbackReason isNil! !

!McMarkdownReconcilerTest methodsFor: 'tests - insertion'!
testInsertionOnlyDirtiesTheInsertedBlock
	| before after result |
	before := self snapshotFor: 'alpha

beta'.
	after := self snapshotFor: 'alpha

inserted

beta'.
	reconciler reconcileFrom: nil to: before.
	result := reconciler reconcileFrom: before to: after.
	self assert: result dirtyNodes size equals: 1.
	self assert: (self addressesOf: result dirtyNodes) equals: #('/document/paragraph[2]').
	self assert: result unchangedNodes size equals: 2.
	self assert: result removedNodes isEmpty.
	self assert: ((self lineagesOf: after) at: 1) equals: ((self lineagesOf: before) at: 1).
	self assert: ((self lineagesOf: after) at: 3) equals: ((self lineagesOf: before) at: 2).
	self deny: ((self lineagesOf: before) includes: ((self lineagesOf: after) at: 2))!

testInsertionAboveABlockRelocatesItWithoutDirtyingIt
	| before after result moved |
	before := self snapshotFor: 'anchor block'.
	after := self snapshotFor: 'brand new

anchor block'.
	reconciler reconcileFrom: nil to: before.
	result := reconciler reconcileFrom: before to: after.
	moved := (self blocksOf: after) second.
	self assert: (result isUnchanged: moved).
	self deny: (result isDirty: moved).
	self assert: (result relocatedNodes includes: moved).
	self assert: moved addressString equals: '/document/paragraph[2]'.
	self assert: (result matchFor: moved) addressString equals: '/document/paragraph[1]'.
	self assert: moved lineageId equals: (self blocksOf: before) first lineageId! !

!McMarkdownReconcilerTest methodsFor: 'tests - modification'!
testLocalEditKeepsItsOwnLineageAndItsNeighboursLineages
	| before after result edited |
	before := self snapshotFor: 'alpha

beta

gamma'.
	after := self snapshotFor: 'alpha

beta edited

gamma'.
	reconciler reconcileFrom: nil to: before.
	result := reconciler reconcileFrom: before to: after.
	edited := (self blocksOf: after) second.
	self assert: result modifiedNodes size equals: 1.
	self assert: result modifiedNodes first == edited.
	self assert: result addedNodes isEmpty.
	self assert: result removedNodes isEmpty.
	self assert: result retiredLineageIds isEmpty.
	self assert: (result isDirty: edited).
	self assert: (self lineagesOf: after) equals: (self lineagesOf: before)!

testEditedHeaderDoesNotStealTheParagraphLineage
	| before after result |
	before := self snapshotFor: '# title

body'.
	after := self snapshotFor: '# other title

body'.
	reconciler reconcileFrom: nil to: before.
	result := reconciler reconcileFrom: before to: after.
	self assert: (self addressesOf: result dirtyNodes) equals: #('/document/header[1]').
	self assert: (self addressesOf: result unchangedNodes) equals: #('/document/paragraph[1]').
	self assert: (self lineagesOf: after) equals: (self lineagesOf: before)!

testDirtyFractionTracksTheChangedWeightOnly
	| before after result |
	before := self snapshotFor: 'a short line

a much longer paragraph that carries most of the render weight of this document

another long paragraph that also carries a great deal of render weight here'.
	after := self snapshotFor: 'a shorter line

a much longer paragraph that carries most of the render weight of this document

another long paragraph that also carries a great deal of render weight here'.
	reconciler reconcileFrom: nil to: before.
	result := reconciler reconcileFrom: before to: after.
	self assert: result dirtyNodes size equals: 1.
	self assert: result dirtyFraction equals: (result dirtyWeight / result totalWeight) asFloat.
	self assert: result dirtyFraction < 0.2.
	self assert: result dirtyWeight equals: (result dirtyNodes first sourceRange size + 1)! !

!McMarkdownReconcilerTest methodsFor: 'tests - deletion'!
testDeletionRetiresOnlyTheRemovedLineage
	| before after result removedLineage |
	before := self snapshotFor: 'alpha

beta

gamma'.
	after := self snapshotFor: 'alpha

gamma'.
	reconciler reconcileFrom: nil to: before.
	removedLineage := (self lineagesOf: before) at: 2.
	result := reconciler reconcileFrom: before to: after.
	self assert: result removedNodes size equals: 1.
	self assert: result removedNodes first == (self blocksOf: before) second.
	self assert: result retiredLineageIds equals: (Array with: removedLineage).
	self assert: result dirtyNodes isEmpty.
	self assert: result unchangedNodes size equals: 2.
	self assert: result dirtyFraction equals: 0.0.
	self assert: (self lineagesOf: after)
		equals: (Array with: ((self lineagesOf: before) at: 1) with: ((self lineagesOf: before) at: 3))!

testDeletingEveryBlockRetiresEveryLineageAndForcesAFullPass
	| before after result |
	before := self snapshotFor: 'alpha

beta'.
	after := self snapshotFor: ''.
	reconciler reconcileFrom: nil to: before.
	result := reconciler reconcileFrom: before to: after.
	self assert: result removedNodes size equals: 2.
	self assert: result retiredLineageIds asSet equals: (self lineagesOf: before) asSet.
	self assert: result dirtyFraction equals: 1.0! !

!McMarkdownReconcilerTest methodsFor: 'tests - duplicates and moves'!
testDuplicateParagraphsReconcileDeterministically
	| before after first second |
	before := self snapshotFor: 'dup

dup

tail'.
	after := self snapshotFor: 'dup

dup

dup

tail'.
	reconciler reconcileFrom: nil to: before.
	first := reconciler reconcileFrom: before to: after.
	self assert: first unchangedNodes size equals: 3.
	self assert: (self addressesOf: first addedNodes) equals: #('/document/paragraph[3]').
	self assert: ((self lineagesOf: after) at: 1) equals: ((self lineagesOf: before) at: 1).
	self assert: ((self lineagesOf: after) at: 2) equals: ((self lineagesOf: before) at: 2).
	self assert: ((self lineagesOf: after) at: 4) equals: ((self lineagesOf: before) at: 3).
	self assert: (self lineagesOf: after) asSet size equals: 4.
	second := McMarkdownReconciler new
		reconcileFrom: (self snapshotFor: before source)
		to: (self snapshotFor: after source).
	self assert: (self matchMapFor: second) equals: (self matchMapFor: first)!

testDeletingOneOfTwoDuplicatesRetiresExactlyOneLineage
	| before after result |
	before := self snapshotFor: 'dup

dup

tail'.
	after := self snapshotFor: 'dup

tail'.
	reconciler reconcileFrom: nil to: before.
	result := reconciler reconcileFrom: before to: after.
	self assert: result removedNodes size equals: 1.
	self assert: result retiredLineageIds size equals: 1.
	self assert: result unchangedNodes size equals: 2.
	self assert: ((self lineagesOf: after) at: 1) equals: ((self lineagesOf: before) at: 1)!

testReorderIsConservativeRemovePlusAdd
	"Matching is monotonic within the sibling sequence, so a block moved to the
	 front is retired and re-added rather than matched backwards."
	| before after result movedLineage |
	before := self snapshotFor: 'alpha

beta

gamma'.
	after := self snapshotFor: 'gamma

alpha

beta'.
	reconciler reconcileFrom: nil to: before.
	movedLineage := (self lineagesOf: before) at: 3.
	result := reconciler reconcileFrom: before to: after.
	self assert: result unchangedNodes size equals: 2.
	self assert: (self addressesOf: result addedNodes) equals: #('/document/paragraph[1]').
	self assert: result retiredLineageIds equals: (Array with: movedLineage).
	self assert: ((self lineagesOf: after) at: 2) equals: ((self lineagesOf: before) at: 1).
	self assert: ((self lineagesOf: after) at: 3) equals: ((self lineagesOf: before) at: 2).
	self deny: ((self lineagesOf: after) at: 1) equals: movedLineage! !

!McMarkdownReconcilerTest methodsFor: 'tests - revisions'!
testLineageSurvivesSuccessiveRevisions
	| first second third stable |
	first := self snapshotFor: 'stable block

edited block'.
	second := self snapshotFor: 'stable block

edited block once'.
	third := self snapshotFor: 'stable block

edited block once

appended block'.
	reconciler reconcileFrom: nil to: first.
	stable := (self blocksOf: first) first lineageId.
	reconciler reconcileFrom: first to: second.
	reconciler reconcileFrom: second to: third.
	self assert: (self blocksOf: second) first lineageId equals: stable.
	self assert: (self blocksOf: third) first lineageId equals: stable.
	self assert: (self blocksOf: second) second lineageId
		equals: (self blocksOf: first) second lineageId.
	self assert: (self blocksOf: third) second lineageId
		equals: (self blocksOf: first) second lineageId.
	self assert: (self lineagesOf: third) asSet size equals: 3!

testEditCoincidingWithAnInsertStaysConservative
	"One gap holding both an edit and an insertion cannot be attributed without
	 guessing, so the old lineage retires instead of being handed to whichever
	 new block happens to sit there."
	| before after result |
	before := self snapshotFor: 'alpha

beta'.
	after := self snapshotFor: 'alpha

beta edited

gamma'.
	reconciler reconcileFrom: nil to: before.
	result := reconciler reconcileFrom: before to: after.
	self assert: result unchangedNodes size equals: 1.
	self assert: result modifiedNodes isEmpty.
	self assert: result addedNodes size equals: 2.
	self assert: result retiredLineageIds
		equals: (Array with: (self blocksOf: before) second lineageId).
	self assert: result confidence equals: 1.0.
	self assert: result dirtyFraction > 0.5!

testLineageLookupResolvesBackToTheNewNode
	| before after result node |
	before := self snapshotFor: 'alpha

beta'.
	after := self snapshotFor: 'alpha

beta changed'.
	reconciler reconcileFrom: nil to: before.
	result := reconciler reconcileFrom: before to: after.
	node := (self blocksOf: after) second.
	self assert: (result nodeForLineage: (result lineageIdFor: node)) == node.
	self assert: (result nodeForLineage: 'no-such-lineage') isNil.
	self assert: (result successorOf: (self blocksOf: before) second) == node!

testCarriedLineageIdsAreAnsweredInDocumentOrder
	| before after result |
	before := self snapshotFor: 'alpha

beta

gamma'.
	after := self snapshotFor: 'inserted

alpha

beta edited

gamma'.
	reconciler reconcileFrom: nil to: before.
	result := reconciler reconcileFrom: before to: after.
	"alpha, beta and gamma all keep their lineage; the report must follow the
	 new revision's block order rather than a dictionary's iteration order."
	self assert: result carriedLineageIds
		equals: ((self blocksOf: before) collect: [ :each | each lineageId ]) asArray.
	self assert: result retiredLineageIds isEmpty! !
