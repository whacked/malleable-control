TestCase subclass: #McFrontmatterTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McFrontmatterTest methodsFor: 'samples'!
sample
	^ String lf join: #(
		'---'
		'title: A doc'
		'floaty: f@820x560+40-60'
		'---'
		'# Heading'
		'body')! !

!McFrontmatterTest methodsFor: 'tests - detection'!
testRangeCoversTheWholeFencedBlock
	| range |
	range := McFrontmatter rangeIn: self sample.
	self
		assert: (self sample copyFrom: range first to: range last)
		equals: (String lf join: #('---' 'title: A doc' 'floaty: f@820x560+40-60' '---'))!

testUnclosedFenceIsNotAFrontmatterBlock
	"A block is the text between two fences.  One fence is a thematic break
	 the author has typed, and swallowing the rest of the file for it would
	 hide the whole document."
	self assert: (McFrontmatter rangeIn: (String lf join: #(
		'---'
		'title: A doc'
		'# Heading'))) isNil!

testFenceBelowOtherTextIsNotAFrontmatterBlock
	self assert: (McFrontmatter rangeIn: (String lf join: #(
		'# Heading'
		'---'
		'title: A doc'
		'---'))) isNil! !

!McFrontmatterTest methodsFor: 'tests - entries'!
testEntriesAreTheKeysInDocumentOrder
	self
		assert: ((McFrontmatter on: self sample) entries collect: [ :each | each key ])
		equals: #('title' 'floaty')!

testAnEntrysValueRangeAddressesTheWholeSource
	"The YAML is parsed out of the block, but an entry has to point into the
	 file, because that is what an edit replaces."
	| entry |
	entry := (McFrontmatter on: self sample) entries second.
	self
		assert: (self sample copyFrom: entry valueRange first to: entry valueRange last)
		equals: 'f@820x560+40-60'!

testEntryNamedAnswersTheEntryWithThatKey
	self
		assert: ((McFrontmatter on: self sample) entryNamed: 'floaty') valueRange
		equals: ((McFrontmatter on: self sample) entries second) valueRange!

testEntryNamedAnswersNilForAKeyTheBlockDoesNotHave
	self assert: ((McFrontmatter on: self sample) entryNamed: 'author') isNil!

testYamlThatDoesNotParseHasNoEntries
	"A half-typed value is a state the author passes through.  The block says
	 nothing until it parses again, and says so rather than guessing."
	| fm |
	fm := McFrontmatter on: (String lf join: #(
		'---'
		'tags: [a,'
		'---'
		'# Heading')).
	self deny: fm isParsed.
	self assert: fm entries isEmpty! !
