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
	^ relation ifNil: [ relation := self readRelation ]!

separatorIndex
	"Which line is the |---|---| row, or 0 for a run of pipes that has none.
	 Forces the relation, because reading it is where the row is found.

	 Worth answering rather than keeping private: Microdown makes a
	 MicTableBlock out of any line containing a pipe, so the separator is the
	 only thing that tells a table from a sentence, and a caller deciding
	 whether to render a grid needs to ask."
	self relation.
	^ separatorIndex!

hasSeparatorRow
	^ self separatorIndex > 0! !

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

BlElement subclass: #McMarkdownTableElement
	instanceVariableNames: 'relation palette owner sortAction'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownTableElement class methodsFor: 'instance creation'!
relation: aRelation palette: aPalette owner: anOwner
	^ self new setRelation: aRelation palette: aPalette owner: anOwner! !

!McMarkdownTableElement methodsFor: 'initialization'!
setRelation: aRelation palette: aPalette owner: anOwner
	relation := aRelation.
	palette := aPalette.
	owner := anOwner! !

!McMarkdownTableElement methodsFor: 'accessing'!
relation
	^ relation!

paletteAt: aKey
	^ palette at: aKey ifAbsent: [ Color gray ]!

sortAction: aBlock
	"A two-argument block of columnIndex and ascending, or nil for a table
	 that does not sort."
	sortAction := aBlock! !

!McMarkdownTableElement methodsFor: 'cells'!
cellTextFor: aCell
	^ self cellTextFor: aCell isHeader: false!

cellTextFor: aCell isHeader: aBoolean
	"A cell is a smaller document: its source goes through the same inline
	 styler, with the cursor forced away so it always renders, and with the
	 document map set from the cell's interval so a widget inside it writes
	 back to the right characters.

	 When the table's cells are data rather than markup, the styler is
	 skipped entirely -- a value containing ** must not turn bold, and one
	 reading [ ] must not become a checkbox with nowhere to write.

	 Base styling is applied first: a whole-range foreground added afterwards
	 would override the colours the styler puts on individual runs.

	 styleAll has no rescue of its own.  The visitor's calls to it are
	 covered by McRichEdit>>styleMarkdown:source:cursor:'s on: Error do:, but
	 a cell's text is built inside the table widget's stencil block, which
	 Bloc evaluates at render time -- outside that rescue entirely.  Without
	 a rescue here, a styling failure would escape into Bloc's render loop
	 instead of degrading, so this cell gets its own: on failure it falls
	 back to its literal, base-styled source rope."
	| text |
	relation directives cellsAreMarkdown
		ifFalse: [ ^ self baseTextFor: aCell isHeader: aBoolean ].
	text := self baseTextFor: aCell isHeader: aBoolean.
	[ (McMarkdownInlineStyler
		source: aCell source
		targetMap: (McMarkdownInlineStyler identityMapOfSize: aCell source size)
		documentMap: (aCell interval
			ifNil: [ McMarkdownInlineStyler identityMapOfSize: aCell source size ]
			ifNotNil: [ :interval | McMarkdownInlineStyler mapForInterval: interval ])
		text: text
		cursor: -1
		palette: palette
		owner: (aCell interval ifNil: [ nil ] ifNotNil: [ :ignored | owner ])) styleAll ]
		on: Error do: [ :e | ^ self baseTextFor: aCell isHeader: aBoolean ].
	^ text!

baseTextFor: aCell isHeader: aBoolean
	| text |
	text := aCell source asRopedText.
	text foreground: (self paletteAt: (aBoolean ifTrue: [ 'boldText' ] ifFalse: [ 'text' ])).
	text fontSize: 14.
	aBoolean ifTrue: [ text bold ].
	^ text!

hasAdornment: aText
	"The base class, not the narrower BrTextAdornmentDynamicAttribute: a
	 hide attribute -- used to collapse ** delimiters -- is itself a
	 BrTextAdornmentAttribute, and BlTextElement honours neither hide nor
	 adornments.  Measured in this image: a bold-only cell's ** delimiters
	 stayed visible in a BlTextElement (37.07 -> 36.07 wide) but collapsed in
	 an embedded BrEditorElement (58.80 -> 25.20 wide).  So any cell holding
	 an adornment of either kind -- hide included -- needs the editor, and
	 only a cell with none at all may take the cheap element."
	1 to: aText size do: [ :index |
		((aText attributesAt: index) anySatisfy: [ :each |
			each isKindOf: BrTextAdornmentAttribute ]) ifTrue: [ ^ true ] ].
	^ false!

cellElementFor: aCell alignment: aSymbol isHeader: aBoolean
	"Adornments are realised only by the editor's segment machinery, never by
	 a plain text painter, so a cell holding a widget needs an embedded
	 editor.  Everything else -- the overwhelming majority -- gets the cheap
	 element and costs what a cell costs today."
	| content element |
	content := self cellTextFor: aCell isHeader: aBoolean.
	element := (self hasAdornment: content)
		ifTrue: [ self editorElementFor: content ]
		ifFalse: [ BlTextElement new text: content; yourself ].
	element padding: (BlInsets top: 3 right: 10 bottom: 3 left: 10).
	aBoolean ifTrue: [ element background: (self paletteAt: 'tableHeaderBg') ].
	element constraintsDo: [ :c |
		c horizontal fitContent.
		c vertical fitContent.
		aSymbol = #right ifTrue: [ c grid horizontal alignRight ].
		aSymbol = #center ifTrue: [ c grid horizontal alignCenter ].
		aSymbol = #left ifTrue: [ c grid horizontal alignLeft ] ].
	^ element!

editorElementFor: aText
	| model element |
	model := BrTextEditorModel new.
	model text: aText.
	model beReadOnlyWithoutSelection.
	element := BrEditorElement new.
	element editor: model.
	^ element! !

!McMarkdownTableElement methodsFor: 'building'!
build
	"Fill the grid: one header row from the columns, then one row per row of
	 the relation."
	| count |
	count := relation columnCount max: 1.
	self layout: (BlGridLayout horizontal columnCount: count).
	self constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
	self background: (self paletteAt: 'editorBg').
	self border: (BlBorder paint: (self paletteAt: 'tableBorder') width: 1).
	self margin: (BlInsets top: 2 bottom: 2).
	self removeChildren.
	relation columns doWithIndex: [ :column :index |
		self addChild: (self headerElementFor: column index: index) ].
	1 to: relation rowCount do: [ :rowIndex |
		1 to: count do: [ :columnIndex |
			self addChild: (self
				cellElementFor: (relation at: rowIndex column: columnIndex)
				alignment: (relation columns
					at: columnIndex
					ifAbsent: [ McRelationColumn name: '' alignment: #left ]) alignment
				isHeader: false) ] ].
	^ self! !

!McMarkdownTableElement methodsFor: 'sorting'!
arrowFor: aColumnIndex
	"The arrow is derived from the data, so no sort state is stored: there is
	 nothing to keep in sync with a rope that changes on every keystroke."
	relation rowCount < 2 ifTrue: [ ^ '' ].
	(relation isSortedBy: aColumnIndex ascending: true) ifTrue: [ ^ self ascendingArrow ].
	(relation isSortedBy: aColumnIndex ascending: false) ifTrue: [ ^ self descendingArrow ].
	^ ''!

ascendingArrow
	"Built from a code point rather than written as a literal: chunk files are
	 read byte-wise and a multi-byte character in a string literal does not
	 survive fileIn reliably."
	^ ' ' , (String with: (Character value: 9650))!

descendingArrow
	^ ' ' , (String with: (Character value: 9660))!

nextAscendingFor: aColumnIndex
	"Clicking a column already ascending asks for descending; anything else
	 asks for ascending.  Same guard as arrowFor:: with fewer than two rows
	 'ascending' is vacuously true, and without this guard the header would
	 show no arrow while a click asked for descending anyway."
	relation rowCount < 2 ifTrue: [ ^ true ].
	^ (relation isSortedBy: aColumnIndex ascending: true) not!

isSortable
	^ relation directives isSortable and: [ sortAction notNil ]! !

!McMarkdownTableElement methodsFor: 'header'!
headerElementFor: aColumn index: anIndex
	| cell |
	cell := self
		cellElementFor: (McRelationCell source: aColumn name , (self arrowFor: anIndex) interval: nil)
		alignment: aColumn alignment
		isHeader: true.
	self isSortable ifTrue: [
		cell addEventHandlerOn: BlClickEvent do: [ :event |
			sortAction value: anIndex value: (self nextAscendingFor: anIndex) ] ].
	^ cell! !
