"Tests for deterministic structural addresses.  Load after McMarkdown.st and
McMarkdownSnapshot.st."!

TestCase subclass: #McMarkdownSnapshotTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownSnapshotTest methodsFor: 'helpers'!
source
	^ '# H

first

- one
- two

second

---'! !

!McMarkdownSnapshotTest methodsFor: 'tests'!
testAddressesAreDeterministicAcrossParses
	| first second |
	first := McMarkdownDocumentSnapshot parseSource: self source.
	second := McMarkdownDocumentSnapshot parseSource: self source.
	self assert: (first allNodes collect: #addressString) asSet equals: (second allNodes collect: #addressString) asSet!

testEveryGeneratedAddressRoundTrips
	| snapshot resolver |
	snapshot := McMarkdownDocumentSnapshot parseSource: self source.
	resolver := McMarkdownPathResolver on: snapshot.
	snapshot allNodes do: [ :node |
		self assert: (resolver resolve: node addressString) == node ]!

testUsesStableVocabularyAndSameKindOrdinals
	| snapshot |
	snapshot := McMarkdownDocumentSnapshot parseSource: self source.
	self assert: (snapshot nodeAtAddress: '/document/header[1]') notNil.
	self assert: (snapshot nodeAtAddress: '/document/paragraph[1]') notNil.
	self assert: (snapshot nodeAtAddress: '/document/unordered-list[1]/item[2]') notNil.
	self assert: (snapshot nodeAtAddress: '/document/horizontal-rule[1]') notNil.
	self deny: ((snapshot allNodes anySatisfy: [ :node | node addressString includesSubstring: 'Mic' ]))!

testMalformedAndMissingPathsDoNotResolve
	| snapshot |
	snapshot := McMarkdownDocumentSnapshot parseSource: self source.
	self assert: (McMarkdownPath fromString: '/document/paragraph[0]') isNil.
	self assert: (McMarkdownPath fromString: '/wrong/paragraph[1]') isNil.
	self assert: (snapshot resolve: '/document/paragraph[99]') isNil!

testDifferentKindSiblingDoesNotChangeParagraphOrdinal
	| before after |
	before := McMarkdownDocumentSnapshot parseSource: 'one

two'.
	after := McMarkdownDocumentSnapshot parseSource: '# heading

one

two'.
	self assert: (before nodeAtAddress: '/document/paragraph[2]') syntaxFingerprint
		equals: (after nodeAtAddress: '/document/paragraph[2]') syntaxFingerprint! !
