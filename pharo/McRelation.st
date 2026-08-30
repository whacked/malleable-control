"
McRelation -- the read model shared by markdown tables and query results.

A relation is derived, never authoritative.  It is rebuilt from the source on
every parse and is never mutated in place: sorting does not reorder a
relation, it emits an edit to the document, which reparses into a new one.
The document stays the write model; this is the read model.

Cells and rows carry an `interval' -- the span of characters in the whole
document string they came from -- so that a widget rendered inside a cell
knows which characters to rewrite when it is clicked.  Rows produced by a
query have no such span, and theirs is nil.

Chunk format: load with fileIn.
"!

Object subclass: #McTableDirectives
	instanceVariableNames: 'cells sortable'
	classVariableNames: ''
	package: 'MalleableControl'!

Object subclass: #McRelationCell
	instanceVariableNames: 'source interval'
	classVariableNames: ''
	package: 'MalleableControl'!

Object subclass: #McRelationColumn
	instanceVariableNames: 'name alignment derived'
	classVariableNames: ''
	package: 'MalleableControl'!

Object subclass: #McRelationRow
	instanceVariableNames: 'cells columns interval'
	classVariableNames: ''
	package: 'MalleableControl'!

Object subclass: #McRelation
	instanceVariableNames: 'columns rows directives'
	classVariableNames: ''
	package: 'MalleableControl'!

!McTableDirectives class methodsFor: 'instance creation'!
forMarkdownTable
	"A literal table holds markdown and its order lives in the document."
	^ self new setCells: #markdown sortable: true!

forQuery
	"A query result holds data, and its ordering belongs to the query."
	^ self new setCells: #text sortable: false! !

!McTableDirectives methodsFor: 'initialization'!
setCells: aSymbol sortable: aBoolean
	cells := aSymbol.
	sortable := aBoolean! !

!McTableDirectives methodsFor: 'accessing'!
cells
	^ cells!

cellsAreMarkdown
	^ cells = #markdown!

isSortable
	^ sortable! !

!McRelationCell class methodsFor: 'instance creation'!
source: aString interval: anIntervalOrNil
	^ self new setSource: aString interval: anIntervalOrNil!

empty
	^ self source: '' interval: nil! !

!McRelationCell methodsFor: 'initialization'!
setSource: aString interval: anIntervalOrNil
	source := aString.
	interval := anIntervalOrNil! !

!McRelationCell methodsFor: 'accessing'!
source
	^ source!

interval
	^ interval!

text
	"The source with the common inline markers removed.  Deliberately crude:
	 this produces a sort key, not a rendering, and the renderer does the
	 real parse."
	^ (source copyWithoutAll: '*`') trimBoth!

number
	"Answer the cell as a Number, or nil when the text is not one well-formed
	 number.  A character-class check is not enough: asNumber parses greedily
	 and stops at the first character it cannot use, so `1.2.3' comes back as
	 1.2 without raising, and a column of semvers would sort as truncated
	 numbers.  The whole string has to match before asNumber is trusted."
	| stripped |
	stripped := self text.
	stripped isEmpty ifTrue: [ ^ nil ].
	('[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?' asRegex matches: stripped)
		ifFalse: [ ^ nil ].
	^ [ stripped asNumber ] on: Error do: [ :e | nil ]!

sortKey
	"A Number when the cell is one, otherwise the lowercased text.  The
	 relation decides whether a whole column may use the numeric form."
	^ self number ifNil: [ self text asLowercase ]! !

!McRelationCell methodsFor: 'printing'!
printOn: aStream
	aStream << 'McRelationCell(' << source << ')'! !

!McRelationColumn class methodsFor: 'instance creation'!
name: aString alignment: aSymbol
	^ self new setName: aString alignment: aSymbol derived: false! !

!McRelationColumn methodsFor: 'initialization'!
setName: aString alignment: aSymbol derived: aBoolean
	name := aString.
	alignment := aSymbol.
	derived := aBoolean! !

!McRelationColumn methodsFor: 'accessing'!
name
	^ name!

alignment
	^ alignment!

isDerived
	"False in phase 1; derived columns arrive with the formula seam."
	^ derived! !

!McRelationRow class methodsFor: 'instance creation'!
cells: aCollection columns: aColumnCollection interval: anIntervalOrNil
	^ self new setCells: aCollection columns: aColumnCollection interval: anIntervalOrNil! !

!McRelationRow methodsFor: 'initialization'!
setCells: aCollection columns: aColumnCollection interval: anIntervalOrNil
	cells := aCollection asArray.
	columns := aColumnCollection asArray.
	interval := anIntervalOrNil! !

!McRelationRow methodsFor: 'accessing'!
size
	^ cells size!

interval
	^ interval!

atIndex: anInteger
	^ cells at: anInteger ifAbsent: [ McRelationCell empty ]!

at: aColumnName
	"Access by column name.  A name that is not a column answers an empty
	 cell rather than raising, because this is on the render path."
	| index |
	index := columns findFirst: [ :each | each name = aColumnName ].
	index = 0 ifTrue: [ ^ McRelationCell empty ].
	^ self atIndex: index! !

!McRelation class methodsFor: 'instance creation'!
columns: aColumnCollection rows: aRowCollection directives: aDirectives
	^ self new setColumns: aColumnCollection rows: aRowCollection directives: aDirectives! !

!McRelation methodsFor: 'initialization'!
setColumns: aColumnCollection rows: aRowCollection directives: aDirectives
	columns := aColumnCollection asArray.
	rows := aRowCollection asArray.
	directives := aDirectives! !

!McRelation methodsFor: 'accessing'!
columns
	^ columns!

directives
	^ directives!

rowCount
	^ rows size!

columnCount
	^ columns size!

rowAt: anInteger
	^ rows at: anInteger!

rowsDo: aBlock
	rows do: aBlock!

at: aRowIndex column: aColumnIndex
	^ (self rowAt: aRowIndex) atIndex: aColumnIndex! !

!McRelation methodsFor: 'sorting'!
sortKeysFor: aColumnIndex
	"The column's sort keys, demoted to text unless every one is a Number.
	 A single non-numeric cell makes the whole column compare as text --
	 mixing the two would raise on the first comparison."
	| keys |
	keys := (1 to: self rowCount) collect: [ :each |
		(self at: each column: aColumnIndex) sortKey ].
	(keys allSatisfy: [ :each | each isNumber ]) ifTrue: [ ^ keys ].
	^ keys collect: [ :each | each asString asLowercase ]!

orderedRowIndicesBy: aColumnIndex ascending: aBoolean
	"Answer the permutation of row indices that sorts the relation by a
	 column.  A permutation rather than a sorted relation, because the GFM
	 path applies it to source lines and the relation itself never moves."
	| keys |
	self rowCount = 0 ifTrue: [ ^ #() ].
	keys := self sortKeysFor: aColumnIndex.
	^ ((1 to: self rowCount) asSortedCollection: [ :a :b |
		aBoolean
			ifTrue: [ (keys at: a) <= (keys at: b) ]
			ifFalse: [ (keys at: a) >= (keys at: b) ] ]) asArray!

isSortedBy: aColumnIndex ascending: aBoolean
	"Whether the rows are already in that order.  Derived, so a header arrow
	 never has to be remembered across a restyle."
	^ (self orderedRowIndicesBy: aColumnIndex ascending: aBoolean)
		= (1 to: self rowCount) asArray! !
