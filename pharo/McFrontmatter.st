"
McFrontmatter -- the Obsidian-style YAML block at the top of a markdown file.

    ---
    title: A doc
    floaty: f@820x560+40-60
    ---
    # the markdown proper

Two readings of that block are wanted, and they fail independently, so they
are separated here.

Where the block is -- #rangeIn: -- is read from the fence lines alone.  It
costs nothing, it cannot fail on a half-typed value, and it is what the floaty
parse needs: the block has to be kept out of the markdown parser's sight, and
the line carrying the floaty directive has to be found, whatever state the
rest of the YAML is in.

What the block says -- #entries -- is read with YAMLParser, which is in the
image and answers an AST whose nodes carry their source positions.  Every
entry therefore knows the interval its value occupies in the file, and an
edit is a replacement of that one span.  Nothing re-emits the YAML, so key
order, comments and blank lines survive an edit by never being touched.

Chunk format: load with fileIn.
"!

Object subclass: #McFrontmatter
	instanceVariableNames: 'source range entries parsed'
	classVariableNames: ''
	package: 'MalleableControl'!

Object subclass: #McFrontmatterEntry
	instanceVariableNames: 'key valueRange'
	classVariableNames: ''
	package: 'MalleableControl'!

!McFrontmatterEntry class methodsFor: 'instance creation'!
key: aString valueRange: anInterval
	^ self new setKey: aString valueRange: anInterval; yourself! !

!McFrontmatterEntry methodsFor: 'initialization'!
setKey: aString valueRange: anInterval
	key := aString.
	valueRange := anInterval! !

!McFrontmatterEntry methodsFor: 'accessing'!
key
	^ key!

valueRange
	"Where this entry's value sits in the file the frontmatter was read from."
	^ valueRange!

valueRange: anInterval
	"Where the value sits after an edit moved it.  An entry is an anchor into
	 the source like any other, and is moved by the replacement that moved the
	 text, not by reading the block again -- which a half-typed value would not
	 let it do anyway."
	valueRange := anInterval! !

!McFrontmatter class methodsFor: 'instance creation'!
on: aString
	"The frontmatter block of aString, or nil when it has none."
	| found |
	found := self rangeIn: aString.
	found ifNil: [ ^ nil ].
	^ self new setSource: aString range: found; yourself! !

!McFrontmatter methodsFor: 'initialization'!
setSource: aString range: anInterval
	source := aString.
	range := anInterval! !

!McFrontmatter methodsFor: 'accessing'!
range
	^ range!

interiorRange
	"Between the fences.  Empty when the block holds nothing."
	| lines opening closing |
	lines := self class lineIntervalsIn: source.
	opening := lines detect: [ :each | each first = range first ].
	closing := lines detect: [ :each | each last = range last ].
	^ (opening last + 2) to: (closing first - 2)!

entries
	"The block's top-level keys in document order.  Empty when the YAML does
	 not parse, which is a state the author passes through on the way to one
	 that does."
	entries ifNil: [ self readEntries ].
	^ entries asArray!

entryNamed: aString
	^ self entries detect: [ :each | each key = aString ] ifNone: [ nil ]!

isParsed
	"Whether the block's YAML reads.  Answered after #entries, which is what
	 finds out."
	entries ifNil: [ self readEntries ].
	^ parsed! !

!McFrontmatter methodsFor: 'parsing'!
readEntries
	| interior file |
	entries := OrderedCollection new.
	parsed := false.
	interior := self interiorRange.
	interior isEmpty ifTrue: [ ^ self ].
	file := [ YAMLParser parse: (source copyFrom: interior first to: interior last) ]
		on: Error
		do: [ :e | nil ].
	file ifNil: [ ^ self ].
	parsed := true.
	file documents do: [ :document |
		(document respondsTo: #mappings) ifTrue: [
			document mappings do: [ :each |
				| offset |
				offset := interior first - 1.
				entries add: (McFrontmatterEntry
					key: each keyObject asString
					valueRange: (each value startPosition + offset
						to: each value stopPosition + offset)) ] ] ]! !

!McFrontmatter class methodsFor: 'detecting'!
rangeIn: aString
	"The interval of the fenced block at the top of aString, fences included,
	 or nil when there is none.  The opening fence must be the first non-blank
	 line; an unclosed block is not a block."
	| lines opening |
	lines := self lineIntervalsIn: aString.
	opening := lines
		detect: [ :each | (self lineIn: aString at: each) trimBoth notEmpty ]
		ifNone: [ nil ].
	opening ifNil: [ ^ nil ].
	(self isFence: (self lineIn: aString at: opening)) ifFalse: [ ^ nil ].
	lines do: [ :each |
		(each first > opening last
			and: [ self isFence: (self lineIn: aString at: each) ])
				ifTrue: [ ^ opening first to: each last ] ].
	^ nil!

isFence: aLine
	^ aLine trimBoth = '---'! !

!McFrontmatter class methodsFor: 'private'!
lineIntervalsIn: aString
	| intervals start index size |
	intervals := OrderedCollection new.
	size := aString size.
	start := 1.
	index := 1.
	[ index <= size ] whileTrue: [
		(aString at: index) = Character lf ifTrue: [
			intervals add: (start to: index - 1).
			start := index + 1 ].
		index := index + 1 ].
	intervals add: (start to: size).
	^ intervals asArray!

lineIn: aString at: anInterval
	anInterval last < anInterval first ifTrue: [ ^ '' ].
	^ aString copyFrom: anInterval first to: anInterval last! !
