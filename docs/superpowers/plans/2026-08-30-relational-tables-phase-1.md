# Relational Tables (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make table cells render as fully-styled markdown, backed by a shared relational read model, with column-header sorting that rewrites the document — fixing both reported defects.

**Architecture:** A pure value object, `McRelation`, becomes the read model for tables. `McMarkdownTableReader` builds one by reading the document source directly, so every cell carries the character span it came from. `McMarkdownInlineStyler` becomes the single component that applies inline decoration — emphasis and the custom `[ ]` / `#RRGGBB` / `<<button>>` tokens — over any source range, invoked by the visitor per block and recursively per cell. The table widget is then just a view over a relation.

**Tech Stack:** Pharo 12 / Glamorous Toolkit v1.1.564, Microdown, Bloc/Brick, SUnit. Source files are Pharo chunk format, loaded with `fileIn`.

**Spec:** `docs/superpowers/specs/2026-08-30-relational-tables-and-db-views-design.md` (phase 1 = sections 3, 5.1, 6, and sorting)

## Global Constraints

- **Chunk format.** Every `.st` file is Pharo chunk format. Methods are wrapped in `!ClassName methodsFor: 'protocol'!` … `! !`. A bare `!` inside a string literal or comment terminates the chunk and breaks the fileIn — double it (`!!`) or reword to avoid it. A free-floating comment must end with `"!` or it swallows the next chunk header.
- **Pharo regex has no `\t`.** `'[ \t]*'` raises "bad backslash escape". Use `\s`.
- **SUnit in this image has no `assert:equals:description:`.** Only `assert:equals:` and `assert:description:` exist.
- **Assert on substrings, not offsets.** Range tests must assert on the text a range selects (`parser sourceOf:`, `source copyFrom:to:`), never on raw index numbers. A failure must say *what* was selected.
- **`OrderedCollection = Array` is false.** Normalise with `asArray` on both sides before comparing collections.
- **The styler must never raise.** It runs on every keystroke. Anything that can fail is wrapped so a failure degrades to unstyled text plus a status message.
- **Package:** every class is `package: 'MalleableControl'`.
- **Load order:** `McRelation`, `McMarkdownInline`, `McMarkdownTable`, `McMarkdown`, `McRichEdit`. Reflected in `test/run-pharo-tests.sh` and `elisp/mc-rich-edit.el`.
- **Test command:** `test/run-pharo-tests.sh`. It prints `PHARO_TESTS_OK` on success and `PHARO_TESTS_FAILED` with per-suite `FAIL`/`ERROR` selectors otherwise. There is no way to run a single test from the shell; run the whole suite and read the named failures.

---

## File Structure

| File | Responsibility |
|---|---|
| `pharo/McRelation.st` | new. `McTableDirectives`, `McRelationCell`, `McRelationColumn`, `McRelationRow`, `McRelation`. Pure — no Bloc, no Microdown. |
| `pharo/McRelationTest.st` | new. Tests for the above. |
| `pharo/McMarkdownInline.st` | new. `McMarkdownInlineStyler` — all inline decoration, over any range. |
| `pharo/McMarkdownTable.st` | new. `McMarkdownTableReader` (source → relation, and the sort edit) and `McMarkdownTableElement` (relation → widget). |
| `pharo/McMarkdown.st` | modified. The visitor delegates inline work to the styler and tables to the reader/element. |
| `pharo/McRichEdit.st` | modified. Loses `styleBold:`-era regex passes; keeps `replaceFrom:to:with:`. |
| `pharo/McMarkdownTest.st` | modified. Gains reader, inline styler, and regression tests. |
| `test/run-pharo-tests.sh` | modified. Loads the new files, runs `McRelationTest`. |
| `elisp/mc-rich-edit.el` | modified. Loads the new files in order. |

---

### Task 1: The relational read model

Pure value objects with sorting semantics. No Bloc, no Microdown, no editor — this task is testable entirely on its own.

**Files:**
- Create: `pharo/McRelation.st`
- Create: `pharo/McRelationTest.st`
- Modify: `test/run-pharo-tests.sh`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `McTableDirectives class >> forMarkdownTable` → cells `#markdown`, sortable `true`
  - `McTableDirectives class >> forQuery` → cells `#text`, sortable `false`
  - `McTableDirectives >> cellsAreMarkdown` → `Boolean`; `>> isSortable` → `Boolean`
  - `McRelationCell class >> source: aString interval: anIntervalOrNil`
  - `McRelationCell >> source` → `String`; `>> interval` → `Interval` or nil; `>> text` → `String`; `>> number` → `Number` or nil; `>> sortKey` → `Number` or `String`
  - `McRelationColumn class >> name: aString alignment: aSymbol` (`#left`/`#center`/`#right`)
  - `McRelationColumn >> name`, `>> alignment`, `>> isDerived`
  - `McRelationRow >> at: aColumnName` → `McRelationCell`; `>> atIndex: anInteger` → `McRelationCell`; `>> interval` → `Interval` or nil
  - `McRelation class >> columns: anArray rows: anArray directives: aDirectives`
  - `McRelation >> columns`, `>> rowCount`, `>> columnCount`, `>> rowAt:`, `>> rowsDo:`, `>> at:column:`, `>> directives`
  - `McRelation >> orderedRowIndicesBy: anInteger ascending: aBoolean` → `Array` of row indices
  - `McRelation >> isSortedBy: anInteger ascending: aBoolean` → `Boolean`

- [ ] **Step 1: Write the failing tests**

Create `pharo/McRelationTest.st`:

```smalltalk
"
McRelationTest -- tests for the relational read model.

The model is deliberately free of Bloc and of Microdown, so everything here
runs without a window and without a parser.  What is worth pinning down is
the sorting semantics: a column sorts numerically only when every cell in it
is a number, markup does not affect the sort key, and `sorted' is derived
from the data rather than remembered.

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

testCellNumberRejectsPartiallyNumericText
	"`3 apples' must not sort as 3."
	self assert: (self cell: '3 apples') number isNil.
	self assert: (self cell: 'fig') number isNil.
	self assert: (self cell: '') number isNil!

testCellSortKeyFallsBackToLowercasedText
	self assert: (self cell: 'Fig') sortKey equals: 'fig'.
	self assert: (self cell: '11') sortKey equals: 11! !

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

testMarkupDoesNotAffectSortOrder
	| relation |
	relation := self relationWithRows: #( #('**pear**') #('apple') ).
	self
		assert: (relation orderedRowIndicesBy: 1 ascending: true) asArray
		equals: #(2 1)!

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
```

- [ ] **Step 2: Register the new suite, then run to verify it fails**

In `test/run-pharo-tests.sh`, add the fileIn line before `McMarkdownTest`:

```bash
  '$MC_HOME/pharo/McRelation.st' asFileReference fileIn.
  '$MC_HOME/pharo/McRelationTest.st' asFileReference fileIn.
```

and add the suite to the run list:

```bash
  #( #NatsClientTest #McRelationTest #McMarkdownTest ) do: [ :each |
```

Run: `test/run-pharo-tests.sh`
Expected: FAIL — the fileIn of `McRelation.st` errors because the file does not exist, or `McRelationTest` errors with `McRelationCell` undeclared.

- [ ] **Step 3: Write the implementation**

Create `pharo/McRelation.st`:

```smalltalk
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
	"Answer the cell as a Number, or nil when the text is not entirely
	 numeric.  asNumber alone would read `3 apples' as 3 and sort it among
	 the numbers."
	| stripped |
	stripped := self text.
	stripped isEmpty ifTrue: [ ^ nil ].
	(stripped allSatisfy: [ :each |
		each isDigit or: [ '+-.eE' includes: each ] ]) ifFalse: [ ^ nil ].
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `test/run-pharo-tests.sh`
Expected: `PHARO-TESTS McRelationTest 13 ran, 13 passed`, and `PHARO_TESTS_OK`.

- [ ] **Step 5: Commit**

```bash
git add pharo/McRelation.st pharo/McRelationTest.st test/run-pharo-tests.sh
git commit -m "Add McRelation, the read model shared by tables and queries"
```

---

### Task 2: Reading a table out of the document

`McMarkdownTableReader` turns a table's source into a relation whose cells carry document intervals. This is what makes both write-back and sorting possible, and it replaces the current guesswork around Microdown's inconsistent separator-row handling.

**Files:**
- Create: `pharo/McMarkdownTable.st`
- Modify: `pharo/McMarkdownTest.st` (new protocol `tests - table reader`)
- Modify: `test/run-pharo-tests.sh`

**Interfaces:**
- Consumes: `McRelation`, `McRelationRow`, `McRelationColumn`, `McRelationCell`, `McTableDirectives` from Task 1. `McMarkdownParser >> source`, `>> rangeOf:`, `>> lineIntervalsWithin:`, `>> lineAt:` from the existing `McMarkdown.st`.
- Produces:
  - `McMarkdownTableReader class >> source: aString lineIntervals: aCollection` — `aCollection` is the table's line `Interval`s, in order
  - `McMarkdownTableReader >> relation` → `McRelation`
  - `McMarkdownTableReader >> sortEditBy: aColumnIndex ascending: aBoolean` → `Association` of `Interval -> String`, or nil when there is nothing to reorder

- [ ] **Step 1: Write the failing tests**

Append to the end of `pharo/McMarkdownTest.st`. Each block below is a complete chunk (`!McMarkdownTest methodsFor: '…'!` … `! !`), so it appends cleanly:

```smalltalk
!McMarkdownTest methodsFor: 'helpers - tables'!
readerFor: aString
	"Build a reader over the first table in aString."
	| parser table |
	parser := self parse: aString.
	table := parser root children
		detect: [ :each | each class name asString = 'MicTableBlock' ].
	^ McMarkdownTableReader
		source: parser source
		lineIntervals: (parser lineIntervalsWithin: (parser rangeOf: table))!

sourceOfCell: aCell in: aString
	"What a cell's interval actually selects, so failures name the text."
	aCell interval ifNil: [ ^ nil ].
	^ aString copyFrom: aCell interval first to: aCell interval last! !

!McMarkdownTest methodsFor: 'tests - table reader'!
testReaderFindsColumnsAndRows
	| source relation |
	source := '| name | qty |
|------|-----|
| fig  | 11  |
| pear | 3   |'.
	relation := (self readerFor: source) relation.
	self assert: (relation columns collect: [ :each | each name ]) asArray equals: #('name' 'qty').
	self assert: relation rowCount equals: 2.
	self assert: (relation at: 1 column: 1) text equals: 'fig'.
	self assert: (relation at: 2 column: 2) text equals: '3'!

testReaderRecordsCellIntervals
	"The interval is what lets a widget inside a cell write back."
	| source relation |
	source := '| name | qty |
|------|-----|
| fig  | 11  |'.
	relation := (self readerFor: source) relation.
	self
		assert: (self sourceOfCell: (relation at: 1 column: 1) in: source)
		equals: ' fig  '.
	self
		assert: (self sourceOfCell: (relation at: 1 column: 2) in: source)
		equals: ' 11  '!

testReaderRecordsRowIntervals
	| source relation |
	source := '| a |
|---|
| 1 |
| 2 |'.
	relation := (self readerFor: source) relation.
	self
		assert: (source copyFrom: (relation rowAt: 2) interval first to: (relation rowAt: 2) interval last)
		equals: '| 2 |'!

testReaderReadsPlainSeparatorRow
	"Microdown drops |---|---| and sets hasHeader; the reader must not
	 depend on which of the two spellings was used."
	| relation |
	relation := (self readerFor: '| a | b |
|---|---|
| 1 | 2 |') relation.
	self assert: relation rowCount equals: 1.
	self assert: (relation columns collect: [ :each | each alignment ]) asArray equals: #(#left #left)!

testReaderReadsAlignedSeparatorRow
	"Microdown keeps |:--|--:| as data with hasHeader false."
	| relation |
	relation := (self readerFor: '| a | b | c |
|:--|:-:|--:|
| 1 | 2 | 3 |') relation.
	self assert: relation rowCount equals: 1.
	self
		assert: (relation columns collect: [ :each | each alignment ]) asArray
		equals: #(#left #center #right)!

testReaderTreatsEscapedPipeAsContent
	| relation |
	relation := (self readerFor: '| a | b |
|---|---|
| x \| y | z |') relation.
	self assert: relation columnCount equals: 2.
	self assert: (relation at: 1 column: 1) text equals: 'x \| y'!

testReaderPadsRaggedRows
	| relation |
	relation := (self readerFor: '| a | b | c |
|---|---|---|
| 1 |
| 1 | 2 | 3 | 4 |') relation.
	self assert: (relation rowAt: 1) size equals: 3.
	self assert: (relation rowAt: 2) size equals: 3.
	self assert: (relation at: 1 column: 3) source equals: ''!

testReaderDefaultsToMarkdownCells
	self assert: (self readerFor: '| a |
|---|
| 1 |') relation directives cellsAreMarkdown! !

!McMarkdownTest methodsFor: 'tests - table sorting'!
testSortEditReordersRowLines
	| source edit |
	source := '| name | qty |
|------|-----|
| pear | 3   |
| fig  | 11  |'.
	edit := (self readerFor: source) sortEditBy: 1 ascending: true.
	self
		assert: edit value
		equals: '| fig  | 11  |
| pear | 3   |'!

testSortEditCoversOnlyTheDataRows
	"The header and separator must stay where they are."
	| source edit |
	source := '| name |
|------|
| b    |
| a    |'.
	edit := (self readerFor: source) sortEditBy: 1 ascending: true.
	self assert: (source copyFrom: edit key first to: edit key last) equals: '| b    |
| a    |'!

testSortEditSortsNumericallyByNumericColumn
	| source edit |
	source := '| n |
|---|
| 3 |
| 11 |
| 7 |'.
	edit := (self readerFor: source) sortEditBy: 1 ascending: true.
	self assert: edit value equals: '| 3 |
| 7 |
| 11 |'!

testSortEditDescending
	| source edit |
	source := '| n |
|---|
| 1 |
| 2 |'.
	edit := (self readerFor: source) sortEditBy: 1 ascending: false.
	self assert: edit value equals: '| 2 |
| 1 |'!

testSortEditIsNilWithNothingToReorder
	self
		assert: ((self readerFor: '| a |
|---|
| 1 |') sortEditBy: 1 ascending: true) isNil! !
```

- [ ] **Step 2: Register the new file, then run to verify the tests fail**

In `test/run-pharo-tests.sh`, add before the `McMarkdown.st` line:

```bash
  '$MC_HOME/pharo/McMarkdownTable.st' asFileReference fileIn.
```

Run: `test/run-pharo-tests.sh`
Expected: `PHARO_TESTS_FAILED` with `ERROR` on the new `testReader*` and `testSortEdit*` selectors — `McMarkdownTableReader` is undeclared.

- [ ] **Step 3: Write the implementation**

Create `pharo/McMarkdownTable.st`. This task adds only the reader; the element follows in Task 5.

```smalltalk
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `test/run-pharo-tests.sh`
Expected: `PHARO_TESTS_OK`, with `McMarkdownTest` up by 13 tests.

If `testReaderRecordsCellIntervals` fails, read what substring it reports — the interval bounds are inclusive of the spaces around the cell text, which is what `' fig  '` asserts.

- [ ] **Step 5: Commit**

```bash
git add pharo/McMarkdownTable.st pharo/McMarkdownTest.st test/run-pharo-tests.sh
git commit -m "Read GFM tables from source into a relation with document intervals"
```

---

### Task 3: One inline styler, invoked per range

This is the task that fixes the self-referencing checkbox. The three regex passes leave `McRichEdit`, join emphasis in a single component, and become scoped to a range instead of scanning the flat document — so a range a widget has claimed is never overlaid.

**Files:**
- Create: `pharo/McMarkdownInline.st`
- Modify: `pharo/McMarkdown.st` (visitor: delegate inline visiting)
- Modify: `pharo/McRichEdit.st` (delete `styleCheckboxes:`, `styleColors:`, `styleButtons:` and their calls)
- Modify: `pharo/McMarkdownTest.st`
- Modify: `test/run-pharo-tests.sh`, `elisp/mc-rich-edit.el`

**Interfaces:**
- Consumes: nothing from Tasks 1–2.
- Produces:
  - `McMarkdownInlineStyler class >> source: aString targetMap: anArray documentMap: anArray text: aRope cursor: anInteger palette: aDictionary owner: anObjectOrNil`
  - `McMarkdownInlineStyler class >> identityMapOfSize: anInteger` → `Array` `#(1 2 3 …)`
  - `McMarkdownInlineStyler class >> mapForInterval: anInterval` → `Array` of the interval's document indices
  - `McMarkdownInlineStyler >> styleAll` — applies emphasis and custom tokens

**Why two maps.** The styler decorates a rope, but the string it reasons about is not always that rope's content. For a document block, Microdown's inline string is the block's lines joined with a CR and its markup prefix stripped, so source index *i* lands at `documentMap at: i` in the rope — and the rope *is* the document, so the target map is the same array. For a cell, the rope holds exactly the cell source, so the target map is the identity, while the document map carries the cell's interval for write-back. Both cases are the same code with different maps.

- [ ] **Step 1: Write the failing tests**

Append to `pharo/McMarkdownTest.st`:

```smalltalk
!McMarkdownTest methodsFor: 'helpers - inline'!
styleFragment: aString cursor: anInteger
	"Style aString as a standalone fragment, the way a table cell is styled."
	| text |
	text := aString asRopedText.
	(McMarkdownInlineStyler
		source: aString
		targetMap: (McMarkdownInlineStyler identityMapOfSize: aString size)
		documentMap: (McMarkdownInlineStyler identityMapOfSize: aString size)
		text: text
		cursor: anInteger
		palette: self palette
		owner: nil) styleAll.
	^ text!

styleFragmentAway: aString
	^ self styleFragment: aString cursor: -1!

adornmentCountIn: aText
	| count |
	count := 0.
	1 to: aText size do: [ :index |
		((aText attributesAt: index) anySatisfy: [ :each |
			each isKindOf: BrTextAdornmentAttribute ]) ifTrue: [ count := count + 1 ] ].
	^ count! !

!McMarkdownTest methodsFor: 'tests - inline styler'!
testFragmentStylesBold
	| text |
	text := self styleFragmentAway: 'a **b** c'.
	self assert: (self in: text hasAttribute: BlFontWeightAttribute at: 6).
	self assert: (self in: text hasAttribute: BrTextHideAttribute at: 3)!

testFragmentStylesItalic
	| text |
	text := self styleFragmentAway: 'a _b_ c'.
	self assert: (self in: text hasAttribute: BlFontEmphasisAttribute at: 4)!

testFragmentRevealsMarkupNearTheCursor
	| text |
	text := self styleFragment: 'a **b** c' cursor: 4.
	self deny: (self in: text hasAttribute: BrTextHideAttribute at: 3)!

testFragmentRendersACheckbox
	| text |
	text := self styleFragmentAway: '[ ] todo'.
	self assert: (self in: text hasAttribute: BrTextAdornmentAttribute at: 1)!

testFragmentRendersAColourSwatch
	| text |
	text := self styleFragmentAway: 'pick #ff0000 now'.
	self assert: (self in: text hasAttribute: BrTextAdornmentAttribute at: 6)!

testFragmentRendersAButton
	| text |
	text := self styleFragmentAway: 'press <<Go>> now'.
	self assert: (self in: text hasAttribute: BrTextAdornmentAttribute at: 7)! !

!McMarkdownTest methodsFor: 'tests - inline scoping'!
testCustomTokensDoNotApplyInsideACodeFence
	"The passes used to scan the flat document, so a checkbox rendered inside
	 a code block.  They are per-block now, and code blocks are literal."
	| text |
	text := self styleAway: '```
[ ] not a checkbox
```'.
	self assert: (self adornmentCountIn: text) equals: 0!

testDocumentStillRendersCheckboxesInParagraphs
	| text |
	text := self styleAway: '[ ] a real one'.
	self assert: (self in: text hasAttribute: BrTextAdornmentAttribute at: 1)! !
```

- [ ] **Step 2: Run to verify the tests fail**

Add to `test/run-pharo-tests.sh`, before the `McMarkdownTable.st` line:

```bash
  '$MC_HOME/pharo/McMarkdownInline.st' asFileReference fileIn.
```

Run: `test/run-pharo-tests.sh`
Expected: `PHARO_TESTS_FAILED` — `McMarkdownInlineStyler` undeclared on the new selectors, and `testCustomTokensDoNotApplyInsideACodeFence` failing with a non-zero adornment count.

- [ ] **Step 3: Write the styler**

Create `pharo/McMarkdownInline.st`:

```smalltalk
"
McMarkdownInlineStyler -- every inline decoration, over any source range.

One component serves two callers.  The visitor styles a block of the document
with it, and a table cell styles its own private rope with it.  That is what
makes cell contents recursive: a cell is just a smaller document.

It carries two index maps because the string it reasons about is not always
the rope it decorates.  For a document block, Microdown's inline string is the
block's lines joined with a CR and its markup prefix stripped, so source index
i lands at documentMap[i] in the rope -- and the rope is the document, so the
target map is that same array.  For a cell the rope holds exactly the cell
source, so the target map is the identity while the document map carries the
cell's interval, which is what a widget writes back through.

Custom tokens live here rather than in McRichEdit because scanning the flat
document was the cause of two defects: a checkbox rendered inside a code
fence, and a checkbox inside a table added a second beReplace adornment on top
of the table's own, which made the cell render a copy of the table.  Scoping
every pass to a range removes the possibility rather than guarding against it.

Chunk format: load with fileIn.
"!

Object subclass: #McMarkdownInlineStyler
	instanceVariableNames: 'source targetMap documentMap text cursor palette owner'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownInlineStyler class methodsFor: 'instance creation'!
source: aString targetMap: aTargetMap documentMap: aDocumentMap text: aText cursor: anInteger palette: aPalette owner: anOwner
	^ self new
		setSource: aString
		targetMap: aTargetMap
		documentMap: aDocumentMap
		text: aText
		cursor: anInteger
		palette: aPalette
		owner: anOwner!

identityMapOfSize: anInteger
	^ (1 to: anInteger) asArray!

mapForInterval: anInterval
	^ (anInterval first to: anInterval last) asArray! !

!McMarkdownInlineStyler methodsFor: 'initialization'!
setSource: aString targetMap: aTargetMap documentMap: aDocumentMap text: aText cursor: anInteger palette: aPalette owner: anOwner
	source := aString.
	targetMap := aTargetMap asArray.
	documentMap := aDocumentMap asArray.
	text := aText.
	cursor := anInteger.
	palette := aPalette.
	owner := anOwner! !

!McMarkdownInlineStyler methodsFor: 'accessing'!
paletteAt: aKey
	^ palette at: aKey ifAbsent: [ Color gray ]!

targetAt: anIndex
	^ targetMap at: anIndex ifAbsent: [ nil ]!

documentAt: anIndex
	^ documentMap at: anIndex ifAbsent: [ nil ]! !

!McMarkdownInlineStyler methodsFor: 'styling'!
styleAll
	"Emphasis first, then the tokens Microdown does not know about."
	self styleEmphasis.
	self styleCheckboxes.
	self styleColours.
	self styleButtons!

apply: anAttribute fromSource: start toSource: stop
	"Map a source range onto the rope and apply one attribute, ignoring
	 anything that falls outside.  A styler that raises mid-pass leaves the
	 editor half-decorated, so this is bounds-checked once here."
	| targetStart targetStop |
	(start isNil or: [ stop isNil ]) ifTrue: [ ^ self ].
	start > stop ifTrue: [ ^ self ].
	targetStart := self targetAt: start.
	targetStop := self targetAt: stop.
	(targetStart isNil or: [ targetStop isNil ]) ifTrue: [ ^ self ].
	(targetStart < 1 or: [ targetStop > text size ]) ifTrue: [ ^ self ].
	targetStart > targetStop ifTrue: [ ^ self ].
	text attribute: anAttribute from: targetStart to: targetStop!

hideFromSource: start toSource: stop
	self apply: BrTextHideAttribute new fromSource: start toSource: stop!

highlightFromSource: start toSource: stop
	self
		apply: (BlTextForegroundAttribute new paint: (self paletteAt: 'highlight'))
		fromSource: start
		toSource: stop!

dimFromSource: start toSource: stop
	self
		apply: (BlTextForegroundAttribute new paint: (self paletteAt: 'dimDelimiter'))
		fromSource: start
		toSource: stop!

replace: aStencil fromSource: start toSource: stop
	self
		apply: (BrTextAdornmentDynamicAttribute new beReplace; stencil: aStencil)
		fromSource: start
		toSource: stop!

append: aStencil fromSource: start toSource: stop
	self
		apply: (BrTextAdornmentDynamicAttribute new beAppend; stencil: aStencil)
		fromSource: start
		toSource: stop! !

!McMarkdownInlineStyler methodsFor: 'cursor locality'!
isNearSource: start to: stop
	"The cursor is 0-based and document positions are 1-based, which is where
	 the offset of two comes from: it lets the cursor sit just before a token
	 and still count as on it."
	| documentStart documentStop |
	cursor < 0 ifTrue: [ ^ false ].
	documentStart := self documentAt: start.
	documentStop := self documentAt: stop.
	(documentStart isNil or: [ documentStop isNil ]) ifTrue: [ ^ false ].
	^ cursor >= (documentStart - 2) and: [ cursor <= documentStop ]! !

!McMarkdownInlineStyler methodsFor: 'styling - emphasis'!
styleEmphasis
	"Microdown's inline parser gives start/end for each formatted run,
	 relative to the string it was handed -- which is exactly our source."
	| nodes |
	nodes := [ MicInlineParser new parse: source ] on: Error do: [ :e | #() ].
	nodes do: [ :each | self styleEmphasisNode: each ]!

styleEmphasisNode: aNode
	| name start stop width inner |
	name := aNode class name asString.
	start := [ aNode start ] on: Error do: [ :e | nil ].
	stop := [ aNode end ] on: Error do: [ :e | nil ].
	(start isNil or: [ stop isNil ]) ifTrue: [ ^ self ].
	width := self delimiterWidthOf: aNode from: start to: stop.
	width < 1 ifTrue: [ ^ self ].
	inner := (start + width) to: (stop - width).
	inner first > inner last ifTrue: [ ^ self ].
	(self isNearSource: start to: stop) ifTrue: [
		self dimFromSource: start toSource: inner first - 1.
		self dimFromSource: inner last + 1 toSource: stop.
		^ self ].
	self hideFromSource: start toSource: inner first - 1.
	self hideFromSource: inner last + 1 toSource: stop.
	name = 'MicBoldFormatBlock' ifTrue: [
		self
			apply: (BlFontWeightAttribute new weight: BlFontWeight bold)
			fromSource: inner first toSource: inner last.
		self
			apply: (BlTextForegroundAttribute new paint: (self paletteAt: 'boldText'))
			fromSource: inner first toSource: inner last ].
	name = 'MicItalicFormatBlock' ifTrue: [
		self apply: BlFontEmphasisAttribute italic fromSource: inner first toSource: inner last ].
	name = 'MicMonospaceFormatBlock' ifTrue: [
		self
			apply: (BlFontFamilyAttribute new name: 'Source Code Pro')
			fromSource: inner first toSource: inner last.
		self
			apply: (BlTextUnderlayAttribute paint: (self paletteAt: 'codeBg'))
			fromSource: inner first toSource: inner last ]!

delimiterWidthOf: aNode from: start to: stop
	"Half the difference between the raw span and the inner text is one
	 delimiter's width: ** for bold, _ for italic, ` for monospace."
	| innerSize |
	innerSize := [ aNode substring size ] on: Error do: [ :e | 0 ].
	^ (stop - start + 1 - innerSize) // 2! !

!McMarkdownInlineStyler methodsFor: 'styling - tokens'!
styleCheckboxes
	"Replace [ ] and [x] with a live checkbox that writes back through the
	 document map."
	('\[[ xX]\]' asRegex matchingRangesIn: source) do: [ :range |
		| start stop checked documentIndex |
		start := range first.
		stop := range last.
		checked := ((source at: start + 1) = $x) or: [ (source at: start + 1) = $X ].
		documentIndex := self documentAt: start + 1.
		(self isNearSource: start to: stop)
			ifTrue: [ self highlightFromSource: start toSource: stop ]
			ifFalse: [
				self
					replace: [
						| box |
						box := BrCheckbox new.
						box aptitude: BrGlamorousCheckboxAptitude new.
						box beNormalSize.
						box checked: checked.
						box margin: (BlInsets right: 4).
						box whenCheckedDo: [ self write: 'x' at: documentIndex ].
						box whenUncheckedDo: [ self write: ' ' at: documentIndex ].
						box ]
					fromSource: start
					toSource: stop ] ]!

styleColours
	('#[0-9A-Fa-f]{6}' asRegex matchingRangesIn: source) do: [ :range |
		| start stop hex |
		start := range first.
		stop := range last.
		hex := source copyFrom: start + 1 to: stop.
		(self isNearSource: start to: stop)
			ifTrue: [ self highlightFromSource: start toSource: stop ]
			ifFalse: [
				self
					append: [
						| swatch |
						swatch := BlElement new.
						swatch size: 14 @ 14.
						swatch geometry: (BlRoundedRectangleGeometry cornerRadius: 3).
						swatch background: ([ Color fromHexString: hex ] on: Error do: [ :e | Color gray ]).
						swatch margin: (BlInsets left: 4).
						swatch ]
					fromSource: start
					toSource: stop ] ]!

styleButtons
	"The handler is looked up fresh on every restyle, so toggling between raw
	 text and the widget never loses the binding: it is by name, not by
	 reference."
	('<<[^>]+>>' asRegex matchingRangesIn: source) do: [ :range |
		| start stop label |
		start := range first.
		stop := range last.
		label := source copyFrom: start + 2 to: stop - 2.
		(self isNearSource: start to: stop)
			ifTrue: [ self highlightFromSource: start toSource: stop ]
			ifFalse: [
				self
					replace: [
						| button |
						button := BrButton new.
						button label: label.
						button aptitude: BrGlamorousButtonWithLabelAptitude new.
						button beSmallSize.
						button margin: (BlInsets left: 2 right: 2).
						button action: [ self performButton: label ].
						button ]
					fromSource: start
					toSource: stop ] ]! !

!McMarkdownInlineStyler methodsFor: 'actions'!
write: aString at: aDocumentIndex
	"Widgets mutate the document, never the relation or the rope's
	 attributes.  With no owner -- under test -- there is nothing to write to."
	owner ifNil: [ ^ self ].
	aDocumentIndex ifNil: [ ^ self ].
	owner replaceFrom: aDocumentIndex to: aDocumentIndex with: aString!

performButton: aLabel
	owner ifNil: [ ^ self ].
	owner performButtonNamed: aLabel! !
```

- [ ] **Step 4: Point the visitor at the styler and strip the passes from McRichEdit**

In `pharo/McMarkdown.st`, replace the body of `visitInlineChildrenOf:` so it runs the styler over the block's inline source instead of visiting inline children, and delete `visitBold:`, `visitItalic:`, `visitMonospace:`, `styleInline:near:away:`, `delimiterWidthOf:range:`, `dimDelimitersOf:inner:` and `hideDelimitersOf:inner:`:

```smalltalk
visitInlineChildrenOf: aBlock
	"Hand the block's inline source to the shared styler.  The block's inline
	 string is not its document substring -- Microdown joins the lines with a
	 CR and strips the markup prefix -- so the parser's index map is what
	 relates the two, and it serves as both the target and the document map
	 because the rope being decorated is the document."
	| inlineSource blockMap |
	inlineSource := parser inlineSourceOf: aBlock.
	blockMap := parser inlineMapOf: aBlock.
	(inlineSource isNil or: [ blockMap isNil ]) ifTrue: [ ^ self ].
	(McMarkdownInlineStyler
		source: inlineSource
		targetMap: blockMap
		documentMap: blockMap
		text: text
		cursor: cursor
		palette: palette
		owner: owner) styleAll!
```

In `pharo/McRichEdit.st`, delete the three protocols `styling - checkboxes`, `styling - colors` and `styling - buttons` entirely, and reduce `styleText:` to:

```smalltalk
styleText: aText
	"Main styling entry point.  The document is parsed into a Microdown AST
	 and projected by McMarkdownStylerVisitor, which reaches inline
	 decoration -- emphasis and this editor's own tokens alike -- through
	 McMarkdownInlineStyler, per block.  Nothing scans the flat document any
	 more: a range a widget has claimed is simply never descended into."
	self styleMarkdown: aText source: aText asString cursor: self cursorPosition!
```

Add the button dispatch `McMarkdownInlineStyler` calls, in the `text mutation` protocol of `McRichEdit`:

```smalltalk
performButtonNamed: aLabel
	| handler |
	handler := buttonHandlers at: aLabel ifAbsent: [ nil ].
	handler
		ifNil: [ self showStatus: 'No handler for: ' , aLabel ]
		ifNotNil: [ handler value ]!
```

Add the load line to `elisp/mc-rich-edit.el` so the editor still opens — `McMarkdownInline.st` before `McMarkdown.st`, matching the runner.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `test/run-pharo-tests.sh`
Expected: `PHARO_TESTS_OK`. The previously-passing emphasis tests in `tests - styling emphasis` must still pass — they now exercise the new styler through the visitor, which is the point.

- [ ] **Step 6: Commit**

```bash
git add pharo/McMarkdownInline.st pharo/McMarkdown.st pharo/McRichEdit.st \
        pharo/McMarkdownTest.st test/run-pharo-tests.sh elisp/mc-rich-edit.el
git commit -m "Move all inline decoration into one range-scoped styler"
```

---

### Task 4: Cells that render

The cell element, chosen by what the styling produced. This is where the emphasis defect is fixed.

**Files:**
- Modify: `pharo/McMarkdownTable.st` (add `McMarkdownTableElement`, cells only)
- Modify: `pharo/McMarkdownTest.st`

**Interfaces:**
- Consumes: `McMarkdownInlineStyler` (Task 3), `McRelation` (Task 1).
- Produces:
  - `McMarkdownTableElement class >> relation: aRelation palette: aDictionary owner: anObjectOrNil`
  - `McMarkdownTableElement >> cellTextFor: aCell` → `BlRunRopedText`
  - `McMarkdownTableElement >> cellElementFor: aCell alignment: aSymbol isHeader: aBoolean` → `BlElement`
  - `McMarkdownTableElement >> hasAdornment: aText` → `Boolean`

**Why the element differs by content.** Adornments are realised only by the editor's segment machinery, never by a plain text painter. Measured in this image: a `BlTextElement` given adorned text yields zero children and an unchanged extent, while an embedded `BrEditorElement` yields one live `BrCheckbox` and an extent of 66.4×18 against 51.3×16. So a cell with no adornment uses the cheap element, and only a cell that actually holds a widget pays for an editor.

- [ ] **Step 1: Write the failing tests**

Append to `pharo/McMarkdownTest.st`:

```smalltalk
!McMarkdownTest methodsFor: 'helpers - cells'!
elementForTable: aString
	| reader |
	reader := self readerFor: aString.
	^ McMarkdownTableElement
		relation: reader relation
		palette: self palette
		owner: nil!

cellTextIn: aString at: aRowIndex column: aColumnIndex
	| reader element |
	reader := self readerFor: aString.
	element := McMarkdownTableElement
		relation: reader relation
		palette: self palette
		owner: nil.
	^ element cellTextFor: (reader relation at: aRowIndex column: aColumnIndex)! !

!McMarkdownTest methodsFor: 'tests - cell rendering'!
testCellRendersBold
	"The reported defect: emphasis was flattened to a plain string one call
	 before it could be styled."
	| text |
	text := self cellTextIn: '| a |
|---|
| **fig** |' at: 1 column: 1.
	self assert: (self in: text hasAttribute: BlFontWeightAttribute at: 5)!

testCellRendersACheckboxAsAnAdornment
	| text |
	text := self cellTextIn: '| a |
|---|
| [ ] todo |' at: 1 column: 1.
	self assert: (self in: text hasAttribute: BrTextAdornmentAttribute at: 3)!

testPlainCellHasNoAdornment
	| element text |
	element := self elementForTable: '| a |
|---|
| plain |'.
	text := element cellTextFor: ((self readerFor: '| a |
|---|
| plain |') relation at: 1 column: 1).
	self deny: (element hasAdornment: text)!

testPlainCellUsesTheCheapElement
	| element cell |
	element := self elementForTable: '| a |
|---|
| plain |'.
	cell := element
		cellElementFor: ((self readerFor: '| a |
|---|
| plain |') relation at: 1 column: 1)
		alignment: #left
		isHeader: false.
	self assert: cell class equals: BlTextElement!

testWidgetCellUsesAnEmbeddedEditor
	"Only the editor's segment machinery realises adornments."
	| element cell |
	element := self elementForTable: '| a |
|---|
| [ ] todo |'.
	cell := element
		cellElementFor: ((self readerFor: '| a |
|---|
| [ ] todo |') relation at: 1 column: 1)
		alignment: #left
		isHeader: false.
	self assert: cell class equals: BrEditorElement!

testTextCellsSkipTheStylerEntirely
	"cells=text means the source is data, not markup."
	| relation element text |
	relation := McRelation
		columns: (Array with: (McRelationColumn name: 'a' alignment: #left))
		rows: (Array with: (McRelationRow
			cells: (Array with: (McRelationCell source: '**not bold**' interval: nil))
			columns: (Array with: (McRelationColumn name: 'a' alignment: #left))
			interval: nil))
		directives: McTableDirectives forQuery.
	element := McMarkdownTableElement relation: relation palette: self palette owner: nil.
	text := element cellTextFor: (relation at: 1 column: 1).
	self deny: (self in: text hasAttribute: BlFontWeightAttribute at: 5)! !
```

- [ ] **Step 2: Run to verify the tests fail**

Run: `test/run-pharo-tests.sh`
Expected: `PHARO_TESTS_FAILED` — `McMarkdownTableElement` undeclared.

- [ ] **Step 3: Write the element's cell half**

Append to `pharo/McMarkdownTable.st`:

```smalltalk
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
	 would override the colours the styler puts on individual runs."
	| text |
	text := aCell source asRopedText.
	text foreground: (self paletteAt: (aBoolean ifTrue: [ 'boldText' ] ifFalse: [ 'text' ])).
	text fontSize: 14.
	aBoolean ifTrue: [ text bold ].
	relation directives cellsAreMarkdown ifFalse: [ ^ text ].
	(McMarkdownInlineStyler
		source: aCell source
		targetMap: (McMarkdownInlineStyler identityMapOfSize: aCell source size)
		documentMap: (aCell interval
			ifNil: [ McMarkdownInlineStyler identityMapOfSize: aCell source size ]
			ifNotNil: [ :interval | McMarkdownInlineStyler mapForInterval: interval ])
		text: text
		cursor: -1
		palette: palette
		owner: (aCell interval ifNil: [ nil ] ifNotNil: [ :ignored | owner ])) styleAll.
	^ text!

hasAdornment: aText
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `test/run-pharo-tests.sh`
Expected: `PHARO_TESTS_OK`.

- [ ] **Step 5: Commit**

```bash
git add pharo/McMarkdownTable.st pharo/McMarkdownTest.st
git commit -m "Render table cells as markdown, with widgets where they appear"
```

---

### Task 5: The grid, and sorting by clicking a header

**Files:**
- Modify: `pharo/McMarkdownTable.st` (grid build + header interaction)
- Modify: `pharo/McMarkdown.st` (`visitTable:` uses the reader and element)
- Modify: `pharo/McMarkdownTest.st`

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces:
  - `McMarkdownTableElement >> build` — populates the grid; answers self
  - `McMarkdownTableElement >> headerElementFor: aColumn index: anInteger` → `BlElement`
  - `McMarkdownTableElement >> arrowFor: anInteger` → `String` — `ascendingArrow`, `descendingArrow`, or `''`
  - `McMarkdownTableElement >> ascendingArrow`, `>> descendingArrow` → `String`
  - `McMarkdownTableElement >> nextAscendingFor: anInteger` → `Boolean`

- [ ] **Step 1: Write the failing tests**

Append to `pharo/McMarkdownTest.st`:

```smalltalk
!McMarkdownTest methodsFor: 'tests - table element'!
testGridHasOneChildPerCellPlusHeaders
	| element |
	element := (self elementForTable: '| a | b |
|---|---|
| 1 | 2 |
| 3 | 4 |') build.
	self assert: element children size equals: 6!

testHeaderShowsAscendingArrowWhenAlreadySorted
	| element |
	element := self elementForTable: '| n |
|---|
| 1 |
| 2 |'.
	self assert: (element arrowFor: 1) equals: element ascendingArrow!

testHeaderShowsDescendingArrowWhenReversed
	| element |
	element := self elementForTable: '| n |
|---|
| 2 |
| 1 |'.
	self assert: (element arrowFor: 1) equals: element descendingArrow!

testHeaderShowsNoArrowWhenUnsorted
	| element |
	element := self elementForTable: '| n |
|---|
| 2 |
| 1 |
| 3 |'.
	self assert: (element arrowFor: 1) equals: ''!

testClickingASortedColumnAsksForTheOppositeDirection
	"Direction toggles without being remembered: it is read off the data."
	| element |
	element := self elementForTable: '| n |
|---|
| 1 |
| 2 |'.
	self deny: (element nextAscendingFor: 1)!

testClickingAnUnsortedColumnAsksForAscending
	| element |
	element := self elementForTable: '| n |
|---|
| 2 |
| 1 |
| 3 |'.
	self assert: (element nextAscendingFor: 1)! !

!McMarkdownTest methodsFor: 'tests - table regression'!
testCheckboxInACellDoesNotNestTheTable
	"The reported defect: the custom-token pass added a second beReplace
	 adornment inside the table's own, so the checkbox slot rendered a copy
	 of the table.  Exactly one adornment may cover the table's range."
	| source text parser range count |
	source := '| a | b |
|---|---|
| [ ] x | y |'.
	text := self styleAway: source.
	parser := self parse: source.
	range := parser rangeOf: (parser root children
		detect: [ :each | each class name asString = 'MicTableBlock' ]).
	count := 0.
	range first to: range last do: [ :index |
		count := count max: ((text attributesAt: index)
			select: [ :each | each isKindOf: BrTextAdornmentAttribute ]) size ].
	self assert: count equals: 1!

testTableStillRendersWithTheCursorAway
	| source text parser range |
	source := '| a | b |
|---|---|
| 1 | 2 |'.
	text := self styleAway: source.
	parser := self parse: source.
	range := parser rangeOf: (parser root children
		detect: [ :each | each class name asString = 'MicTableBlock' ]).
	self assert: (self in: text hasAttribute: BrTextAdornmentAttribute at: range first)! !
```

- [ ] **Step 2: Run to verify the tests fail**

Run: `test/run-pharo-tests.sh`
Expected: `PHARO_TESTS_FAILED` — `build`, `arrowFor:` and `nextAscendingFor:` are not understood, and `testCheckboxInACellDoesNotNestTheTable` reports a count of 2.

- [ ] **Step 3: Write the grid and the header interaction**

Append to `pharo/McMarkdownTable.st`:

```smalltalk
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
	 asks for ascending."
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
```

Note that `headerElementFor:index:` builds its cell from an interval-free `McRelationCell`, so a header never writes back and its arrow is never mistaken for content.

- [ ] **Step 4: Wire the visitor to the reader and element**

In `pharo/McMarkdown.st`, replace `visitTable:` and delete `tableModelFor:`, `tableElementFor:`, `tableCellFor:alignment:isHeader:`, `textOfCell:`, `isDelimiterRow:`, `isDelimiterCell:` and `alignmentFor:` — all superseded by the reader. Keep `styleTableSourceIn:` and `isDelimiterLine:`, which style the raw view.

```smalltalk
visitTable: aTable
	"A table is a multi-line block, so away from the cursor the whole run of
	 pipe rows is replaced by one grid element built from the relation.  The
	 reader is captured by the sort action, which turns a header click into
	 an ordinary document edit."
	| range reader |
	range := parser rangeOf: aTable.
	range ifNil: [ ^ self ].
	(self isNear: range) ifTrue: [ ^ self styleTableSourceIn: range ].
	reader := McMarkdownTableReader
		source: parser source
		lineIntervals: (parser lineIntervalsWithin: range).
	reader relation rowCount = 0 ifTrue: [ ^ self ].
	self
		replace: [
			| element |
			element := McMarkdownTableElement
				relation: reader relation
				palette: palette
				owner: owner.
			element sortAction: [ :columnIndex :ascending |
				self applySortFrom: reader column: columnIndex ascending: ascending ].
			element build ]
		from: range first
		to: range last!

applySortFrom: aReader column: aColumnIndex ascending: aBoolean
	"Sorting is an edit to the document, not a property of the view."
	| edit |
	owner ifNil: [ ^ self ].
	edit := aReader sortEditBy: aColumnIndex ascending: aBoolean.
	edit ifNil: [ ^ self ].
	owner replaceFrom: edit key first to: edit key last with: edit value!
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `test/run-pharo-tests.sh`
Expected: `PHARO_TESTS_OK`, including `testCheckboxInACellDoesNotNestTheTable`.

- [ ] **Step 6: Commit**

```bash
git add pharo/McMarkdownTable.st pharo/McMarkdown.st pharo/McMarkdownTest.st
git commit -m "Build the table grid from the relation and sort by rewriting rows"
```

---

### Task 6: Demo content, robustness, and a look at it

Prove the whole thing in the live image and leave the demo document exercising it.

**Files:**
- Modify: `pharo/McRichEdit.st` (`demoContent`)
- Modify: `pharo/McMarkdownTest.st` (robustness sweep)
- Create: `agents/notes/2026/08/2026-08-30.001-relational-tables-lessons.md`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing new.

- [ ] **Step 1: Extend the robustness sweep**

The existing `testStylingSurvivesEveryCursorPositionOfTheDemoDocument` runs the styler at every cursor position of the demo document. Add a table with widgets in its cells to the fixture it uses, by appending this test:

```smalltalk
!McMarkdownTest methodsFor: 'tests - robustness'!
testStylingSurvivesEveryCursorPositionOfATableWithWidgets
	"A table whose cells hold every custom token, swept at every cursor
	 position.  This is where the two reported defects showed up, and where a
	 range-mapping mistake would raise."
	| source |
	source := '| task | colour | go |
|:-----|:------:|---:|
| [ ] **write** | #ff0000 | <<Run>> |
| [x] `ship`    | #00ff00 | <<Stop>> |'.
	-1 to: source size do: [ :cursor |
		self
			assert: (self style: source cursor: cursor) notNil
			description: 'raised at cursor ' , cursor printString ]! !
```

- [ ] **Step 2: Run it to verify it fails or passes**

Run: `test/run-pharo-tests.sh`
Expected: PASS if Tasks 1–5 are correct. If it raises, the failure names the cursor position — reproduce that single position in a playground with `self style: source cursor: N`.

- [ ] **Step 3: Update the demo content**

In `pharo/McRichEdit.st`, replace the table in `demoContent` with one that exercises cells, and add a line naming the sort affordance. Keep the rest of the document as it is:

```smalltalk
| task | colour | qty |
|:-----|:------:|----:|
| [ ] **write the reader** | #7f5af0 | 11 |
| [x] `ship the styler`    | #2cb67d | 3  |
| [ ] *sort the rows*      | #ff8906 | 7  |

Click a column header to sort -- the rows are rewritten in the document.
```

- [ ] **Step 4: Look at it in the live image**

The editor must be loaded in file order. With GT running:

```bash
nix-shell --run "bin/gt-load pharo/McRelation.st"
nix-shell --run "bin/gt-load pharo/McMarkdownInline.st"
nix-shell --run "bin/gt-load pharo/McMarkdownTable.st"
nix-shell --run "bin/gt-load pharo/McMarkdown.st"
nix-shell --run "bin/gt-load pharo/McRichEdit.st"
nix-shell --run "bin/gt-eval '(Smalltalk at: #McRichEdit) open. 1'"
```

Confirm by eye: bold and inline code render inside cells; the checkboxes are live and toggling one rewrites only that cell; the swatches appear; the buttons render; clicking `qty` reorders the rows and the arrow appears. Then move the cursor into the table and confirm the raw pipes come back.

`screencapture` is blocked in this environment (no screen-recording permission). To capture a render instead, use `space root exportAsForm` with `PNGReadWriter putForm:onFileNamed:` from inside the image.

- [ ] **Step 5: Write the lessons note**

Create `agents/notes/2026/08/2026-08-30.001-relational-tables-lessons.md` with front matter matching `2026-08-29.002-microdown-ast-styler-lessons.md` (`date`, `author`, `slug`, `source_notes`, `tags`). Record what was actually learned, at minimum: that `beReplace` adornments do not nest and what the overlap renders as; that adornments are realised only by the editor's segment machinery, with the measured extents for `BlTextElement` versus an embedded `BrEditorElement`; and anything discovered during implementation that the next person would otherwise rediscover.

- [ ] **Step 6: Run the full suite and commit**

```bash
test/run-pharo-tests.sh
git add pharo/McRichEdit.st pharo/McMarkdownTest.st agents/notes/2026/08/2026-08-30.001-relational-tables-lessons.md
git commit -m "Exercise cells with widgets in the demo document and the cursor sweep"
```

---

## Phase 1 done when

1. `test/run-pharo-tests.sh` prints `PHARO_TESTS_OK`.
2. Bold, italic, inline code, checkboxes, colour swatches and buttons render inside table cells.
3. A checkbox in a cell toggles the correct characters and never renders a copy of the table.
4. Clicking a column header reorders the rows in the document source, and the arrow reflects the document's actual order with no stored state.
5. `McRichEdit` no longer scans the flat document for any token.

Phases 2 (directives, `cells`/`sort`, links and images, derivation) and 3 (database views) follow from the same spec.
