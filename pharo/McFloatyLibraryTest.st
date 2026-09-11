TestCase subclass: #McFloatyLibraryTest
	instanceVariableNames: 'root'
	classVariableNames: ''
	package: 'MalleableControl'!

!McFloatyLibraryTest methodsFor: 'running'!
setUp
	super setUp.
	root := (FileLocator temp / ('mc-floaty-library-' , UUID new asString36))
		ensureCreateDirectory!

tearDown
	[ root ensureDeleteAll ] on: Error do: [ :e | nil ].
	super tearDown! !

!McFloatyLibraryTest methodsFor: 'building'!
write: aString to: aName
	| file |
	file := root / aName.
	file parent ensureCreateDirectory.
	file writeStreamDo: [ :stream | stream nextPutAll: aString ].
	^ file!

library
	^ McFloatyLibrary on: root!

namesOf: aCollection
	^ (aCollection collect: [ :each | each basename ]) asArray! !

!McFloatyLibraryTest methodsFor: 'tests - listing'!
testEntriesAreTheFilesTheGlobMatches
	self write: '# one' to: 'one.md'.
	self write: 'two' to: 'two.txt'.
	self assert: (self namesOf: self library entries) equals: #('one.md')!

testTheGlobCanBeChanged
	self write: '# one' to: 'one.md'.
	self write: 'two' to: 'two.txt'.
	self assert: (self namesOf: (self library glob: '*.txt'; entries)) equals: #('two.txt')!

testDirectoriesAreListedWhateverTheGlobSays
	(root / 'assets') ensureCreateDirectory.
	self write: '# one' to: 'one.md'.
	self assert: (self namesOf: self library entries) equals: #('assets' 'one.md')!

testFilesAreSortedAndDirectoriesComeFirst
	(root / 'zeta') ensureCreateDirectory.
	self write: '' to: 'b.md'.
	self write: '' to: 'a.md'.
	self assert: (self namesOf: self library entries) equals: #('zeta' 'a.md' 'b.md')!

testADirectorysChildrenAreReadWithTheSameGlob
	self write: '# deep' to: 'assets/deep.md'.
	self write: 'no' to: 'assets/deep.txt'.
	self assert: (self namesOf: self library entries first children) equals: #('deep.md')!

testAMissingRootHasNoEntries
	self assert: (McFloatyLibrary on: root / 'nowhere') entries isEmpty! !

!McFloatyLibraryTest methodsFor: 'tests - directives'!
testAFileOpeningWithADirectiveCommentCarriesOne
	self write: '<!!-- f@400x300+10+10 -->
# Host' to: 'host.md'.
	self assert: self library entries first hasDirective!

testAFileWhoseFrontmatterDeclaresFloatyCarriesOne
	self write: '---
title: A note
floaty: f@400x300+10+10
---
# Host' to: 'host.md'.
	self assert: self library entries first hasDirective!

testAFileWithNoTopLevelDirectiveCarriesNone
	self write: '# Just a heading

Some prose.' to: 'plain.md'.
	self deny: self library entries first hasDirective!

testADirectiveBelowOtherTextIsNotATopLevelOne
	self write: '# Heading

<!!-- f@400x300+10+10 -->
## Child' to: 'later.md'.
	self deny: self library entries first hasDirective!

testADirectoryIsNeverADocument
	(root / 'assets') ensureCreateDirectory.
	self deny: self library entries first isDocument.
	self deny: self library entries first hasDirective!

testAFileThatCannotBeReadCarriesNoDirective
	| entry |
	self write: '<!!-- f@400x300+10+10 -->' to: 'gone.md'.
	entry := self library entries first.
	(root / 'gone.md') ensureDelete.
	self deny: entry hasDirective! !

!McFloatyLibraryTest methodsFor: 'tests - defaults'!
testTheRootFallsBackToSamplesWhenNothingSaysOtherwise
	self
		assert: (McFloatyLibrary rootFor: nil home: '/tmp/somewhere') fullName
		equals: '/tmp/somewhere/samples'!

testTheEnvironmentNamesTheRoot
	self
		assert: (McFloatyLibrary rootFor: root fullName home: '/tmp/somewhere') fullName
		equals: root fullName!

testAnEmptyEnvironmentValueIsNotARoot
	self
		assert: (McFloatyLibrary rootFor: '  ' home: '/tmp/somewhere') fullName
		equals: '/tmp/somewhere/samples'!

testTheGlobFallsBackToMarkdown
	self assert: (McFloatyLibrary globFor: nil) equals: '*.md'!

testTheEnvironmentNamesTheGlob
	self assert: (McFloatyLibrary globFor: '*.txt') equals: '*.txt'! !
