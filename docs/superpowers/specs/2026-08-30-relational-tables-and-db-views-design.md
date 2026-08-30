# Spec: Relational Tables, Table Directives, and Database Views

Date: 2026-08-30
Status: approved, not started

## 1. Problem

Two defects were reported against the Microdown AST styler, and they share
one cause.

**Emphasis dies at the cell boundary.** `textOfCell:` flattens a cell's
inline nodes into a bare `String`, and `tableCellFor:alignment:isHeader:`
turns that back into an unattributed rope. Everything the parser knew about
the cell is discarded one call before it could be used.

**A checkbox inside a cell renders the whole table again.** With the cursor
away, `visitTable:` puts a `beReplace` adornment across the table's entire
range. `styleCheckboxes:` then regexes the flat document string, finds the
`[ ]` inside that range, and adds a second `beReplace` adornment over three
characters within it. The sub-range splits the table's attribute run, the
table stencil is evaluated for the split segment, and the checkbox slot
shows a copy of the table.

The common cause is that the three custom-token passes -- checkboxes,
colour swatches, buttons -- scan the flat document and know nothing about
the AST or about which ranges a widget has already claimed. `beReplace`
regions do not compose. A widget must own its range exclusively and render
its own contents.

Beyond the defects, a table should be able to declare how it is rendered,
should be sortable by clicking a column header, should be able to derive a
column from its own data, and should be available as a projection of a
database query rather than only of literal pipe rows.

## 2. Scope

### In scope

- One shared read model, `McRelation`, produced both by reading a GFM table
  out of the document and by running a SQLite query
- `McMarkdownInlineStyler`: a single inline-decoration component invocable
  over any source range, used for the document and recursively for cells
- Custom tokens (`[ ]`, `#RRGGBB`, `<<button>>`) move out of `McRichEdit`
  into that component and become range-scoped
- Table cells render as fully-styled markdown, including widgets, links and
  images -- or as plain text, by declaration
- **Table directives**: a fence immediately preceding a table declaring how
  it renders and what it derives
- Column-header sorting, applied by rewriting the source
- Column derivation, behind a deliberately replaceable language seam
- Fenced database views, read-only, executed through `sqlite3`

### Out of scope

- Writing to the database. Cells are read-only; see section 9.
- Sorting a database view. See 4.3.
- A real table query language. Section 7 builds a placeholder and the seam
  it will be replaced through.
- Formula dependencies: cross-row references, and formulas reading other
  derived columns.
- Nested tables, and block-level markdown inside a cell.

## 3. The read model

`McRelation` is a plain value object with no dependency on Bloc, Brick or
the editor. It is *derived*: rebuilt from the source on every parse, never
mutated in place.

This does not weaken the rule that the document is the model -- it names
the other half of it. The relation is the read model; the document remains
the sole write model. Sorting does not reorder a relation. It emits an edit
to the source, which reparses into a new relation.

```
McRelation
    columns          -> Array of McRelationColumn
    rowCount, columnCount
    rowsDo:          -> iterate McRelationRow
    rowAt:           -> McRelationRow
    at:column:       -> McRelationCell
    directives       -> McTableDirectives
    orderedRowIndicesBy: anIndex ascending: aBoolean  -> Array of indices
    isSortedBy: anIndex ascending: aBoolean           -> Boolean

McRelationColumn
    name, alignment  -> #left | #center | #right
    isDerived        -> Boolean, see section 7

McRelationRow
    at: aName        -> McRelationCell, by column name
    atIndex:         -> McRelationCell
    interval         -> document Interval of the row's line, or nil

McRelationCell
    source           -> the raw string
    interval         -> document Interval, or nil
    sortKey          -> Number when the column is numeric, else the
                        markup-stripped String, lowercased
```

An *interval* is Pharo's range object, here the character span in the whole
document string that a cell or row occupies. A cell needs it so a widget
rendered inside the cell knows which characters of the document to rewrite
when clicked. Query results have no such span, and theirs is nil.

`orderedRowIndicesBy:ascending:` answers a permutation rather than a sorted
relation. It is the single shared definition of "sorted", used by the GFM
path to reorder source lines and by both paths, through
`isSortedBy:ascending:`, to decide which arrow a header draws. A column is
numeric when every non-empty cell in it parses as a `Number`; otherwise
comparison is case-insensitive on the markup-stripped text, so `**fig**`
sorts under `fig`.

## 4. Table directives

### 4.1 Syntax

A table's properties are declared by a fenced block immediately preceding
it. A database view uses the same shape, with the query in the body:

````
```table&cells=text&sort=off          ```sql&db=tasks.sqlite
total = qty * price                   select name, qty from fruit
```                                    ```
| item | qty | price | total |
|------|----:|------:|------:|
| fig  |  11 |  0.50 |       |
````

**The info string carries options; the body carries whatever produces or
computes the content** -- formulas for a literal table, SQL for a database
view. One mechanism, one parse path.

This shape was chosen on evidence rather than taste. Microdown parses a
fence followed by a pipe table as exactly two blocks, with or without a
blank line between them, and hands back the info string verbatim as
`MicCodeBlock >> firstLine`. The convention used by Djot, Pandoc, MyST and
Quarto -- a `{key=value}` attribute line before the block -- was tried
first and is unusable here: `{` at the start of a line opens a
`MicMetaDataBlock` that swallows the table, leaving a single child. Org
mode's affixed `#+KEY:` lines are the same idea as the fence and would need
new grammar; the fence needs none.

A directives fence binds to the table that follows it, separated by at most
one blank line. A fence with no table after it is left as an ordinary code
block. Like all markup, the fence hides when the cursor is away and shows
as raw source when the cursor enters it.

### 4.2 Options

| Option | Values | Default |
|---|---|---|
| `cells` | `markdown`, `text` | `markdown` for a literal table, `text` for a database view |
| `sort` | `on`, `off` | `on` for a literal table, `off` for a database view |
| `db` | a path | -- (database views only) |

`cells=markdown` renders each cell's source through the inline styler, so
links, images, emphasis, inline code and custom widgets all work inside
cells. `cells=text` skips the styler entirely and renders the cell
literally. Both are available to both producers: the defaults reflect that
a literal table holds markdown and a query result holds data, but a
document that stores markdown in a database column can say so.

### 4.3 Why database views do not sort

Sorting a database view by clicking a header would have to either rewrite
the query's `order by` or sort the fetched page. Rewriting means parsing
SQL well enough to know where the clause ends. Sorting the page lies
whenever the query has a `limit`, because the rows that would sort to the
top may not have been fetched.

Neither is worth it: the query already expresses ordering. So `sort`
defaults to `off` for database views, the header is simply not clickable,
and no SQL is ever parsed or rewritten. A view whose result genuinely is
the whole table can opt in with `sort=on`, which sorts the fetched rows.

## 5. Producers

### 5.1 `McMarkdownTableReader`

Answers an `McRelation` given the document source, a table's line
intervals, and its directives, with every cell and row carrying its
document `Interval`.

It reads the source directly rather than using `MicTableBlock >> rows`, for
three reasons. Microdown's rows are inline-parsed and stripped, so document
positions are already gone. Its handling of the separator row is
inconsistent -- a plain `|---|---|` is dropped and `hasHeader` set, while
`|:---|---:|` is handed back as data with `hasHeader` false -- which the
current code has to second-guess. And both widget write-back and sorting
need exact intervals. Microdown keeps the job it is good at: telling us
where the table is.

The reader handles `\|` as a literal pipe, pads or truncates ragged rows to
the separator row's column count, and takes alignments from the separator
row.

### 5.2 `McSqliteSource`

A plain object, usable with no editor present:

```smalltalk
(McSqliteSource on: 'data/tasks.sqlite') query: 'select name, qty from fruit'
```

Answers an `McRelation`, or an `McSqliteError` carrying the process's
stderr. It runs `sqlite3 -readonly -header -ascii <db> <sql>` through
`GtSubprocessWithInMemoryOutput`. The `-ascii` mode frames columns with
`0x1F` and rows with `0x1E`, so there is no quoting or escaping to parse
and column order is preserved. `-readonly` makes the read-only decision the
driver's rather than our discipline: a write fails with `attempt to write a
readonly database`.

Cells carry no intervals. Alignment is derived: numeric columns right,
everything else left.

The fence is sugar over this object -- extract `db=` from the info string,
take the body as the query, call `query:`. The execution model is therefore
tested directly, in code, with no editor and no fence involved; only a
couple of thin tests cover the fence-to-call mapping.

## 6. Rendering

### 6.1 `McMarkdownInlineStyler`

The recursion primitive. Given a rope, its source string, a document
offset, a cursor position, a palette and an owner, it applies every
inline-level decoration: bold, italic and monospace via `MicInlineParser
new parse:`, plus checkboxes, colour swatches and buttons. Widget actions
write back through the document offset, so the same component serves a
range of the document and a cell's own private rope.

Links and images are *not* part of it. They are phase 2 (section 12), and
until then the styler whitelists the three symmetric-delimiter format
classes and leaves `MicLinkBlock` and `MicFigureBlock` untouched: the
delimiter-width heuristic it uses to find the inner text is only valid for
symmetric delimiters, and applied to a link it would hide the wrong halves
of the source. All phase 1 owes them is to not mangle them.

The three regex passes move here out of `McRichEdit` and become
range-scoped. The visitor invokes them per block content range, never over
the whole document, so a range a widget has claimed is simply never
descended into. *Across* blocks, that kills the overlapping-`beReplace`
defect by construction rather than by a guard. *Within* one range it takes a
guard, because the passes still run over the same source knowing nothing of
each other: the styler keeps the source intervals its widgets cover and a
later pass skips any range intersecting one. First claim wins, so the pass
order -- emphasis, checkboxes, colour swatches, buttons -- is the
precedence.

Two deliberate consequences. A `[ ]` inside a fenced code block now stays
literal, which is correct. And with the cursor inside a table you see raw
`[ ]` rather than a live checkbox, which matches how `**bold**` already
behaves there.

### 6.2 Cells

When the table's `cells` option is `markdown`, a cell's source is styled
into its own rope by `McMarkdownInlineStyler`, with the document offset set
to the cell's interval start and the cursor forced away so the cell always
renders. When it is `text`, the styler is skipped entirely and the cell
renders literally -- so a database value containing `**` does not silently
turn bold, and a value reading `[ ]` does not become a checkbox with
nowhere to write back to.

The element used depends on what the styling produced:

- no adornment attribute in the rope -- the overwhelmingly common case --
  renders as a `BlTextElement`, costing what today's cells cost;
- an adornment present renders as an embedded `BrEditorElement` with
  `beReadOnlyWithoutSelection` and `fitContent` constraints.

This is forced by Bloc: adornments are realised only by the editor's
segment machinery (`BrTextEditorLineSegmentAdornmentPiece`), never by a
plain text painter. Measured in the image, a `BlTextElement` given adorned
text yields zero children and an unchanged extent, while the embedded
editor yields one live `BrCheckbox` and an extent of 66.4x18 against
51.3x16 for the text alone. GT embeds editors this way itself; see
`BrEmbeddedEditorExamples`.

### 6.3 `McMarkdownTableElement`

A view over an `McRelation` and nothing more. It takes the relation and a
`sortAction:` block of `[ :columnIndex :ascending | ]`, which is nil when
the table's `sort` option is off. It does not know where its data came
from.

Header cells are clickable only when a sort action is supplied. The arrow
shows only when the relation reports that column as currently sorted in
that direction, so there is **no stored sort state** -- nothing to keep in
sync with a rope that changes on every keystroke. Clicking toggles
direction.

## 7. Column derivation

Org mode is the only real prior art for table formulas; no Markdown dialect
has them. This design takes org's concept -- a formula list attached to the
table, recalculating cells from the table's own data -- and none of its
syntax.

**The formula language here is a placeholder and is expected to be thrown
away.** Table querying, sorting and modification is its own domain with its
own body of work, and adopting a proven language from it is a separate
exercise. What this spec commits to is the seam, not the syntax:

```
McTableFormulaLanguage        (abstract)
    parseFormulasFrom: aString  -> Array of McTableFormula, or errors

McTableFormula
    targetColumnName
    valueForRow: anMcRelationRow  -> a value, or an McFormulaError
```

Swapping the language means subclassing `McTableFormulaLanguage` and
changing which class the directives ask. Nothing else in the pipeline
moves.

The placeholder, `McSmalltalkFormulaLanguage`, reads one formula per body
line as `name = expression` and evaluates the expression with the row's
literal columns bound as variables. It is the simplest thing available
rather than the most powerful: the image already has a compiler, so this
needs no grammar and no evaluator, where even a small arithmetic DSL would
need both.

Evaluation is a single pass with no ordering. A formula reads only the
table's literal columns, in its own row: never another derived column,
never another row. So there is no dependency graph, no recalculation order,
and no cycle detection. Aggregates and cross-row references are the real
language's problem, not the placeholder's.

A derived column appears in the relation with `isDerived` true. Its cells
have no interval -- they are computed, not written -- and are therefore
rendered as text and never sorted into the source. A formula that fails
renders its error in the cell.

## 8. Execution of database views

The cursor-locality model settles when queries run. While a query is being
typed the cursor is inside the block, so it renders as raw source and no
query runs. Execution can only follow the cursor leaving. No debounce is
needed.

A result cache on `McRichEdit`, keyed by `(dbPath, sql)`, covers restyling
on every keystroke elsewhere in the document. A miss renders a "running"
placeholder and runs the query off the UI thread, then requests a restyle.
A refresh control in the widget drops the entry and re-runs. The cache is
bounded at 32 entries.

A failed query renders as a bordered error box carrying sqlite3's stderr.
Nothing escapes the styler as an exception; the existing rule that a parse
failure degrades to unstyled text applies here too.

The fence parses to a source kind, a source reference and a query. Only
SQLite is implemented. A later source -- a Smalltalk expression, a CSV, a
bus query -- would add a producer answering an `McRelation` and touch
nothing in the renderer. No such source is built now.

## 9. Trust

A document with a database view executes SQL from that document when the
cursor leaves the block, and a table with formulas evaluates expressions
from that document. This is the same trust model `<<button>>` handlers
already carry: a document is as trustworthy as its author. `-readonly`
bounds the database case to reads. This is stated rather than mitigated
further, because the editor's whole premise is documents that do things.

## 10. Files

| File | Contents |
|---|---|
| `pharo/McRelation.st` | new -- `McRelation`, `McRelationColumn`, `McRelationRow`, `McRelationCell`, `McTableDirectives` |
| `pharo/McTableFormula.st` | new in phase 2 -- `McTableFormulaLanguage`, `McSmalltalkFormulaLanguage`, `McTableFormula` |
| `pharo/McSqlite.st` | new -- `McSqliteSource`, `McSqliteError` |
| `pharo/McMarkdownInline.st` | new -- `McMarkdownInlineStyler` |
| `pharo/McMarkdownTable.st` | new -- `McMarkdownTableReader`, `McMarkdownTableElement` |
| `pharo/McMarkdown.st` | `McMarkdownParser` unchanged; visitor loses cell stringification and inline styling |
| `pharo/McRichEdit.st` | loses three regex passes; gains the query cache |
| `pharo/McRelationTest.st` | new -- relation, sorting, directives, formula tests |
| `pharo/McSqliteTest.st` | new -- source and fixture database tests |
| `pharo/McMarkdownTest.st` | gains reader, inline styler, and regression tests |

`McTableDirectives` was meant to have a file of its own. Phase 1 put it in
`McRelation.st` instead: it is a handful of accessors, it is read by every
relation, and it has no dependency the relation family does not already
have. The formula classes keep the separate file, under the name they are
actually about.

`McMarkdown.st` is 595 lines holding two classes already. The new work is
split across focused files rather than added to it. Load order as shipped:
`McRelation`, `McMarkdownInline`, `McMarkdownTable`, `McMarkdown`,
`McRichEdit`, with `McTableFormula` and `McSqlite` joining after
`McRelation` in later phases -- reflected in `elisp/mc-rich-edit.el` and
`test/run-pharo-tests.sh`.

## 11. Testing

Everything load-bearing is pure or shell-only, so most of it tests without
Bloc.

`McRelationTest` -- sort keys and numeric detection, the ordering
permutation, `isSortedBy:ascending:`, named row access. Directive parsing:
defaults per producer, each option, an unknown option ignored, a fence with
no table following it. Formula parsing and per-row evaluation, including
the error path and a derived column being unsorted and interval-free.

Reader coverage -- cell intervals asserted by the substring they select,
following the existing pattern rather than asserting on numbers; both
separator spellings; escaped `\|`; ragged rows; alignment parsing; the
source produced by a sort round-tripping through the reader.

Inline styler coverage -- emphasis offsets within a cell substring; a
checkbox at a cell offset producing a write-back range that selects the
right document characters; two overlapping tokens never nesting two
adornments. Links and images arrive with phase 2.

Both were planned as `McMarkdownTableReaderTest` and
`McMarkdownInlineStylerTest`. Phase 1 folded them into `McMarkdownTest.st`
as protocols instead -- `tests - table reader`, `tests - table sorting`,
`tests - inline styler`, `tests - inline scoping`, `tests - cell
rendering`, `tests - table element` -- because they all share that class's
palette, parse and styling helpers, which a separate class would have had
to duplicate or inherit. The file is now 1113 lines and wants splitting;
that is phase-2 work, and the protocol names are the seams to split along.

`McSqliteTest` -- against a fixture `.sqlite` built in `setUp` by shelling
out; `-ascii` framing, empty results, the error path, and `-readonly`
refusing a write.

Regression tests for the two reported defects -- emphasis surviving into a
rendered cell, and a checkbox in a cell producing exactly one adornment
attribute over the table range rather than a nested table.

The existing full-cursor-sweep robustness test gains demo content with
widgets inside cells, a directives fence, a derived column and a query
block.

## 12. Phases

**Phase 1** -- sections 3, 5.1, 6, and sorting. Cells render emphasis,
inline code and custom widgets. Fixes both reported defects and stands
alone.

**Phase 2** -- sections 4 and 7: the directives fence, `cells` and `sort`
options, links and images in cells, and derivation behind its seam.

**Phase 3** -- sections 5.2 and 8: database views.

## 13. Risks

| Risk | Mitigation |
|---|---|
| An embedded editor per widget-bearing cell is expensive | Only cells whose rope actually carries an adornment pay for one; the widget is built only when the cursor is away. Measure before optimising further. |
| Rewriting rows on sort loses the cursor | `replaceFrom:to:with:` already replaces the whole rope, as checkboxes do today. Preserving the cursor is a separate improvement, applying equally to the existing behaviour. |
| The placeholder formula language leaks into the design | The seam is specified before the placeholder, and the placeholder is the only implementation of it. Tests target `McTableFormulaLanguage`'s protocol, not its syntax. |
| A slow query blocks the UI | The query runs off the UI thread behind a placeholder, and cannot be triggered while typing. |
| Microdown changes its table handling | The reader no longer depends on `MicTableBlock >> rows`, only on where the block starts and ends. |
| A directives fence drifts away from its table during editing | Binding is positional and re-evaluated on every parse; a fence with no table after it degrades to an ordinary code block rather than erroring. |

## 14. Success criteria

1. Bold, italic, inline code, checkboxes, colour swatches and buttons all
   render inside table cells, and links and images do after phase 2.
2. A checkbox in a cell toggles the correct characters in the document and
   never renders a copy of the table.
3. Clicking a column header reorders the rows in the document source, and
   the arrow reflects the document's actual order with no stored state.
4. A `table&cells=text` fence renders its table literally; the same table
   without the fence renders its cells as markdown.
5. A derived column computes per row, and swapping the formula language
   means writing one subclass and changing nothing else.
6. A `sql&db=` fence renders as the same table widget, with sorting off and
   no SQL ever rewritten.
7. `McSqliteSource` is usable from a playground with no editor present, and
   is tested that way.
8. A failed query, a failed formula, and a malformed table all degrade to a
   visible message rather than an exception out of the styler.
