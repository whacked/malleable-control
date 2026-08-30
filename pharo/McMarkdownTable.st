"
McMarkdownTable -- reading a GFM table out of the document, and viewing it.

The reader scans the document source rather than using MicTableBlock's rows,
for three reasons.  Microdown's rows are inline-parsed and stripped, so the
document positions a projectional editor needs are already gone.  Its
handling of the separator row is inconsistent: a plain |---|---| is dropped
and hasHeader set, while |:--|--:| is handed back as data with hasHeader
false.  And both widget write-back and sorting need exact character spans.

Microdown keeps the job it is good at: telling us where the table is.

Chunk format: load with fileIn.
"!

Object subclass: #McMarkdownTableReader
	instanceVariableNames: 'source lineIntervals relation separatorIndex'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownTableReader class methodsFor: 'instance creation'!
source: aString lineIntervals: aCollection
	^ self new setSource: aString lineIntervals: aCollection! !

!McMarkdownTableReader methodsFor: 'initialization'!
setSource: aString lineIntervals: aCollection
	source := aString.
	lineIntervals := aCollection asArray! !

!McMarkdownTableReader methodsFor: 'accessing'!
source
	^ source!

relation
	^ relation ifNil: [ relation := self readRelation ]! !

!McMarkdownTableReader methodsFor: 'reading'!
readRelation
	"Split every line into cells carrying their document intervals, then use
	 the separator row to decide the columns and drop it from the data."
	| parsed columnCount columns dataLines rows |
	parsed := lineIntervals collect: [ :each | self cellsInLine: each ].
	separatorIndex := self separatorIndexIn: parsed.
	columnCount := self columnCountFrom: parsed separator: separatorIndex.
	columns := self columnsFrom: parsed separator: separatorIndex count: columnCount.
	dataLines := self dataLineIndicesFor: parsed separator: separatorIndex.
	rows := dataLines collect: [ :index |
		McRelationRow
			cells: (self padCells: (parsed at: index) to: columnCount)
			columns: columns
			interval: (lineIntervals at: index) ].
	^ McRelation
		columns: columns
		rows: rows
		directives: McTableDirectives forMarkdownTable!

cellsInLine: anInterval
	"Answer the line's cells as McRelationCells with document intervals.  A
	 pipe preceded by a backslash is content, not a delimiter -- GFM's only
	 escape inside a table."
	| cells start index stop |
	cells := OrderedCollection new.
	start := nil.
	index := anInterval first.
	stop := anInterval last.
	[ index <= stop ] whileTrue: [
		((source at: index) = $| and: [ index = anInterval first or: [ (source at: index - 1) ~= $\ ] ])
			ifTrue: [
				start ifNotNil: [
					cells add: (McRelationCell
						source: (source copyFrom: start to: index - 1)
						interval: (start to: index - 1)) ].
				start := index + 1 ].
		index := index + 1 ].
	"Trailing content after the last pipe belongs to no cell in GFM."
	^ cells asArray!

separatorIndexIn: aCollectionOfRows
	"The first row whose every cell is dashes with optional colons."
	aCollectionOfRows doWithIndex: [ :row :index |
		(self isSeparatorRow: row) ifTrue: [ ^ index ] ].
	^ 0!

isSeparatorRow: aRowOfCells
	aRowOfCells isEmpty ifTrue: [ ^ false ].
	^ aRowOfCells allSatisfy: [ :each | self isSeparatorCell: each source ]!

isSeparatorCell: aString
	| trimmed |
	trimmed := aString trimBoth.
	trimmed isEmpty ifTrue: [ ^ false ].
	(trimmed includes: $-) ifFalse: [ ^ false ].
	^ (trimmed reject: [ :char | char = $- or: [ char = $: ] ]) isEmpty!

columnCountFrom: aCollectionOfRows separator: anIndex
	anIndex > 0 ifTrue: [ ^ (aCollectionOfRows at: anIndex) size ].
	^ aCollectionOfRows inject: 0 into: [ :best :row | best max: row size ]!

columnsFrom: aCollectionOfRows separator: anIndex count: aCount
	"Names come from the header row above the separator; alignments from the
	 separator itself."
	| names alignments |
	names := (anIndex > 1)
		ifTrue: [ (aCollectionOfRows at: anIndex - 1) collect: [ :each | each text ] ]
		ifFalse: [ #() ].
	alignments := (anIndex > 0)
		ifTrue: [ (aCollectionOfRows at: anIndex) collect: [ :each | self alignmentFor: each source ] ]
		ifFalse: [ #() ].
	^ (1 to: aCount) collect: [ :index |
		McRelationColumn
			name: (names at: index ifAbsent: [ '' ])
			alignment: (alignments at: index ifAbsent: [ #left ]) ]!

alignmentFor: aString
	| trimmed |
	trimmed := aString trimBoth.
	(trimmed beginsWith: ':')
		ifTrue: [ ^ (trimmed endsWith: ':') ifTrue: [ #center ] ifFalse: [ #left ] ].
	(trimmed endsWith: ':') ifTrue: [ ^ #right ].
	^ #left!

dataLineIndicesFor: aCollectionOfRows separator: anIndex
	"Everything below the separator.  With no separator at all, everything
	 below the first line."
	anIndex = 0 ifTrue: [ ^ (2 to: aCollectionOfRows size) asArray ].
	^ ((anIndex + 1) to: aCollectionOfRows size) asArray!

padCells: aCollectionOfCells to: aCount
	"GFM truncates a long row and pads a short one to the header's width."
	^ (1 to: aCount) collect: [ :index |
		aCollectionOfCells at: index ifAbsent: [ McRelationCell empty ] ]! !

!McMarkdownTableReader methodsFor: 'sorting'!
sortEditBy: aColumnIndex ascending: aBoolean
	"Answer the document edit that sorts the table: the interval spanning the
	 data rows, associated with their reordered source.

	 Sorting is an edit rather than a view because the document is the model.
	 Answer nil when there is nothing to reorder."
	| order first last text |
	self relation rowCount < 2 ifTrue: [ ^ nil ].
	order := self relation orderedRowIndicesBy: aColumnIndex ascending: aBoolean.
	first := (self relation rowAt: 1) interval first.
	last := (self relation rowAt: self relation rowCount) interval last.
	text := String streamContents: [ :stream |
		order doWithIndex: [ :rowIndex :position |
			| interval |
			interval := (self relation rowAt: rowIndex) interval.
			position = 1 ifFalse: [ stream nextPutAll: self lineSeparator ].
			stream nextPutAll: (source copyFrom: interval first to: interval last) ] ].
	^ (first to: last) -> text!

lineSeparator
	"Whatever separates the data rows in this document -- LF, CR or CRLF.
	 Taken from the source rather than assumed, so sorting never introduces
	 mixed line endings into a file that used the other one."
	| first second |
	self relation rowCount < 2 ifTrue: [ ^ String with: Character lf ].
	first := (self relation rowAt: 1) interval last.
	second := (self relation rowAt: 2) interval first.
	^ source copyFrom: first + 1 to: second - 1! !
