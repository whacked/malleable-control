"
McRelationTest -- tests for the relational read model.

The model is deliberately free of Bloc and of Microdown, so everything here
runs without a window and without a parser.  What is worth pinning down is
the sorting semantics: a column sorts numerically only when every non-empty
cell in it is a number, an empty cell sorts to the end of either direction,
markup does not affect the sort key, and `sorted' is derived from the data
rather than remembered.

Chunk format: load with fileIn.
"!

TestCase subclass: #McRelationTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McRelationTest methodsFor: 'helpers'!
cell: aString
	^ McRelationCell source: aString interval: nil!

relationWithRows: anArrayOfArrays
	"Build a relation from arrays of cell source strings, columns named a, b, c."
	| columns rows |
	columns := (1 to: (anArrayOfArrays isEmpty ifTrue: [ 0 ] ifFalse: [ anArrayOfArrays first size ]))
		collect: [ :index |
			McRelationColumn
				name: (String with: (Character value: 96 + index))
				alignment: #left ].
	rows := anArrayOfArrays collect: [ :each |
		McRelationRow
			cells: (each collect: [ :s | self cell: s ])
			columns: columns
			interval: nil ].
	^ McRelation columns: columns rows: rows directives: McTableDirectives forMarkdownTable! !

!McRelationTest methodsFor: 'tests - cells'!
testCellTextStripsInlineMarkup
	"A sort key must not be decided by the markup around the value."
	self assert: (self cell: '**fig**') text equals: 'fig'.
	self assert: (self cell: '`code`') text equals: 'code'.
	self assert: (self cell: '  spaced  ') text equals: 'spaced'!

testCellNumberRecognisesNumbers
	self assert: (self cell: '11') number equals: 11.
	self assert: (self cell: ' -2.5 ') number equals: -2.5!

testCellNumberRecognisesWellFormedVariants
	"Leading zeros, trailing fractional zeros and exponents are all still
	 one well-formed number."
	self assert: (self cell: '011') number equals: 11.
	self assert: (self cell: '1.50') number equals: 1.5.
	self assert: (self cell: '1e3') number equals: 1000!

testCellNumberRejectsPartiallyNumericText
	"`3 apples' must not sort as 3."
	self assert: (self cell: '3 apples') number isNil.
	self assert: (self cell: 'fig') number isNil.
	self assert: (self cell: '') number isNil!

testCellNumberRejectsMalformedNumbers
	"asNumber parses greedily and stops at the first character it cannot
	 use, so a character-class guard alone is not enough: `1.2.3' would
	 come back as 1.2 without raising.  number must reject anything that
	 is not one well-formed number, not just anything built from numeric
	 characters."
	self assert: (self cell: '1.2.3') number isNil.
	self assert: (self cell: '5-3') number isNil.
	self assert: (self cell: '1..2') number isNil.
	self assert: (self cell: '5+') number isNil.
	self assert: (self cell: '1.2e') number isNil!

testCellSortKeyFallsBackToLowercasedText
	self assert: (self cell: 'Fig') sortKey equals: 'fig'.
	self assert: (self cell: '11') sortKey equals: 11!

testCellTextStripsBalancedItalicUnderscores
	"This Microdown build recognises _..._ as its only italic spelling, so
	 the one italic form that renders was the one the sort key kept."
	self assert: (self cell: '_pear_') text equals: 'pear'.
	self assert: (self cell: '__pear__') text equals: 'pear'.
	self assert: (self cell: '**_pear_**') text equals: 'pear'!

testCellTextKeepsAnInteriorDelimiter
	"Stripping every '*' anywhere turned '5*3' into '53', which then parsed
	 as one well-formed number and sorted among the numbers as fifty-three.
	 Only balanced runs at the two ends are markup."
	self assert: (self cell: '5*3') text equals: '5*3'.
	self assert: (self cell: '5*3') number isNil.
	self assert: (self cell: 'a_b') text equals: 'a_b'!

testCellTextLeavesUnbalancedDelimitersAlone
	"Nothing to strip when the two ends do not match, and a cell that is
	 nothing but delimiters keeps them rather than emptying itself."
	self assert: (self cell: '*fig') text equals: '*fig'.
	self assert: (self cell: '**') text equals: '**'! !

!McRelationTest methodsFor: 'tests - sorting'!
testNumericColumnSortsNumerically
	"String comparison would put 11 before 3."
	| relation |
	relation := self relationWithRows: #( #('a' '3') #('b' '11') #('c' '7') ).
	self
		assert: (relation orderedRowIndicesBy: 2 ascending: true) asArray
		equals: #(1 3 2)!

testTextColumnSortsCaseInsensitively
	| relation |
	relation := self relationWithRows: #( #('Pear') #('apple') #('Fig') ).
	self
		assert: (relation orderedRowIndicesBy: 1 ascending: true) asArray
		equals: #(2 3 1)!

testMixedColumnSortsAsText
	"One non-numeric cell demotes the whole column to text comparison."
	| relation |
	relation := self relationWithRows: #( #('3') #('11') #('n/a') ).
	self
		assert: (relation orderedRowIndicesBy: 1 ascending: true) asArray
		equals: #(2 1 3)!

testDescendingReversesTheOrder
	| relation |
	relation := self relationWithRows: #( #('3') #('11') #('7') ).
	self
		assert: (relation orderedRowIndicesBy: 1 ascending: false) asArray
		equals: #(2 3 1)!

testSemverColumnSortsAsTextNotTruncatedNumber
	"1.2.3 is not one well-formed number, so this column must sort as text
	 rather than compare on a truncated numeric parse (1.2.3 -> 1.2)."
	| relation |
	relation := self relationWithRows: #( #('1.2.3') #('1.10.0') #('1.2.0') ).
	self
		assert: (relation orderedRowIndicesBy: 1 ascending: true) asArray
		equals: #(2 3 1)!

testMarkupDoesNotAffectSortOrder
	| relation |
	relation := self relationWithRows: #( #('**pear**') #('apple') ).
	self
		assert: (relation orderedRowIndicesBy: 1 ascending: true) asArray
		equals: #(2 1)!

testItalicMarkupDoesNotAffectSortOrder
	"The '**' spelling was covered; the underscore one, which is the only
	 italic this Microdown build parses, was not -- and it sorted '_pear_'
	 before 'apple'."
	| relation |
	relation := self relationWithRows: #( #('_pear_') #('apple') ).
	self
		assert: (relation orderedRowIndicesBy: 1 ascending: true) asArray
		equals: #(2 1)!

testEmptyCellDoesNotDemoteANumericColumn
	"Section 3: a column is numeric when every *non-empty* cell parses as a
	 Number.  Blank cells are ordinary in hand-written tables, and
	 padCells:to: manufactures one for every ragged row, so requiring every
	 cell sorted an ordinary numeric column as text: '', '11', '3'."
	| relation |
	relation := self relationWithRows: #( #('3') #('') #('11') ).
	self
		assert: (relation orderedRowIndicesBy: 1 ascending: true) asArray
		equals: #(1 3 2)!

testEmptyCellsSortLastInBothDirections
	"An empty cell has no value, so it leads neither order."
	| relation |
	relation := self relationWithRows: #( #('3') #('') #('11') ).
	self
		assert: (relation orderedRowIndicesBy: 1 ascending: false) asArray
		equals: #(3 1 2)!

testEmptyCellSortsLastInATextColumn
	| relation |
	relation := self relationWithRows: #( #('pear') #('') #('apple') ).
	self
		assert: (relation orderedRowIndicesBy: 1 ascending: true) asArray
		equals: #(3 1 2).
	self
		assert: (relation orderedRowIndicesBy: 1 ascending: false) asArray
		equals: #(1 3 2)!

testIsSortedByIsDerivedFromTheData
	"There is no stored sort state -- the arrow is computed."
	| relation |
	relation := self relationWithRows: #( #('1') #('2') #('3') ).
	self assert: (relation isSortedBy: 1 ascending: true).
	self deny: (relation isSortedBy: 1 ascending: false)! !

!McRelationTest methodsFor: 'tests - access'!
testRowAccessByColumnName
	| relation row |
	relation := self relationWithRows: #( #('fig' '11') ).
	row := relation rowAt: 1.
	self assert: (row at: 'a') source equals: 'fig'.
	self assert: (row at: 'b') source equals: '11'.
	self assert: (row atIndex: 2) source equals: '11'!

testMissingColumnNameAnswersAnEmptyCell
	"A formula or a caller asking for a column that is not there must get an
	 empty cell rather than an exception out of the render path."
	| relation |
	relation := self relationWithRows: #( #('fig') ).
	self assert: ((relation rowAt: 1) at: 'nope') source equals: ''!

testRelationShape
	| relation |
	relation := self relationWithRows: #( #('a' 'b') #('c' 'd') #('e' 'f') ).
	self assert: relation rowCount equals: 3.
	self assert: relation columnCount equals: 2.
	self assert: (relation at: 3 column: 2) source equals: 'f'! !

!McRelationTest methodsFor: 'tests - directives'!
testMarkdownTableDefaults
	self assert: McTableDirectives forMarkdownTable cellsAreMarkdown.
	self assert: McTableDirectives forMarkdownTable isSortable!

testQueryDefaults
	"A query result holds data, not markup, and its ordering belongs to the
	 query."
	self deny: McTableDirectives forQuery cellsAreMarkdown.
	self deny: McTableDirectives forQuery isSortable! !
