# Spec: Relational Tables and Database Views

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

Beyond the defects, tables should become functional: sortable by clicking a
column header, and available as a projection of a database query rather
than only of literal pipe rows.

## 2. Scope

### In scope

- One shared read model, `McRelation`, produced both by reading a GFM table
  out of the document and by running a SQLite query
- `McMarkdownInlineStyler`: a single inline-decoration component invocable
  over any source range, used for the document and recursively for cells
- Custom tokens (`[ ]`, `#RRGGBB`, `<<button>>`) move out of `McRichEdit`
  into that component and become range-scoped
- Table cells render as fully-styled markdown, including widgets
- Column-header sorting for GFM tables, applied by rewriting the source
- Fenced database views, read-only, executed through `sqlite3`
- Column-header sorting for database views, applied by rewriting `order by`

### Out of scope

- Writing to the database. Cells are read-only; see section 7.
- Filtering, grouping, aggregation UI. The query expresses those.
- SQL parsing. `McSqlQuery` rewrites a trailing `order by` and nothing more.
- Data sources other than SQLite, though the seam is described in 6.4.
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
    cellsAreMarkdown -> Boolean, see 5.2
    orderedRowIndicesBy: anIndex ascending: aBoolean  -> Array of indices
    isSortedBy: anIndex ascending: aBoolean           -> Boolean

McRelationColumn
    name, alignment  -> #left | #center | #right

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

`orderedRowIndicesBy:ascending:` answers a permutation rather than a sorted
relation. It is the single shared definition of "sorted": the GFM path
applies it to source lines, and a database view uses it only to decide
which arrow to draw. A column is numeric when every non-empty cell in it
parses as a `Number`; otherwise comparison is case-insensitive on the
markup-stripped text, so `**fig**` sorts under `fig`.

## 4. Producers

### 4.1 `McMarkdownTableReader`

Answers an `McRelation` given the document source and a table's line
intervals, with every cell and row carrying its document `Interval`.

It reads the source directly rather than using `MicTableBlock >> rows`,
for three reasons. Microdown's rows are inline-parsed and stripped, so
document positions are already gone. Its handling of the separator row is
inconsistent -- a plain `|---|---|` is dropped and `hasHeader` set, while
`|:---|---:|` is handed back as data with `hasHeader` false -- which the
current code has to second-guess. And both checkbox write-back and sorting
need exact intervals. Microdown keeps the job it is good at: telling us
where the table is.

The reader handles `\|` as a literal pipe, pads or truncates ragged rows to
the separator row's column count, and takes alignments from the separator
row.

### 4.2 `McSqliteSource`

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

## 5. Rendering

### 5.1 `McMarkdownInlineStyler`

The recursion primitive. Given a rope, its source string, a document
offset, a cursor position, a palette and an owner, it applies every
inline-level decoration: bold, italic and monospace via
`MicInlineParser new parse:`, plus checkboxes, colour swatches and buttons.
Widget actions write back through the document offset, so the same
component serves a range of the document and a cell's own private rope.

The three regex passes move here out of `McRichEdit` and become
range-scoped. The visitor invokes them per block content range, never over
the whole document, so a range a widget has claimed is simply never
descended into. The overlapping-`beReplace` defect dies by construction
rather than by a guard.

Two deliberate consequences. A `[ ]` inside a fenced code block now stays
literal, which is correct. And with the cursor inside a table you see raw
`[ ]` rather than a live checkbox, which matches how `**bold**` already
behaves there.

### 5.2 Cells

A cell's source is styled into its own rope by `McMarkdownInlineStyler`,
with the document offset set to the cell's interval start and the cursor
forced away so the cell always renders.

Whether the cell's source is treated as markdown at all is the relation's
`cellsAreMarkdown`. It is true for `McMarkdownTableReader`, whose cells
hold markdown, and false for `McSqliteSource`, whose cells hold data --
otherwise a database value containing `**` would silently turn bold.

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

### 5.3 `McMarkdownTableElement`

A view over an `McRelation` and nothing more. It takes the relation, a
`sortAction:` block of `[ :columnIndex :ascending | ]`, and an optional
`refreshAction:`. It does not know where its data came from.

Header cells are clickable when a sort action is supplied. The arrow shows
only when the relation reports that column as currently sorted in that
direction, so there is **no stored sort state** -- nothing to keep in sync
with a rope that changes on every keystroke. Clicking toggles direction.

## 6. Database views

### 6.1 Syntax

````
```sql&db=data/tasks.sqlite
select name, qty from fruit order by qty desc
```
````

This is sugar over section 4.2, and deliberately thin: extract `db=` from
`MicCodeBlock >> firstLine`, take the body as the query, call
`McSqliteSource`. Microdown already parses the fence and hands back the
info string verbatim, so there is no new grammar.

The form matches the prior art -- Obsidian Dataview, Quarto, Observable
Framework and Org Babel all put a view in a parameterised fence and reserve
inline syntax for scalars -- and it degrades to an ordinary code block in
any other renderer.

Relative paths resolve against the project root; absolute paths are taken
as given.

### 6.2 When queries run

The cursor-locality model settles this. While a query is being typed the
cursor is inside the block, so it renders as raw source and no query runs.
Execution can only follow the cursor leaving. No debounce is needed.

A result cache on `McRichEdit`, keyed by `(dbPath, sql)`, covers restyling
on every keystroke elsewhere in the document. A miss renders a "running"
placeholder and runs the query off the UI thread, then requests a restyle.
A refresh control in the widget drops the entry and re-runs. The cache is
bounded at 32 entries.

### 6.3 Sorting a view

Clicking a header rewrites the `order by` clause in the fence body, which
is an ordinary document edit -- the same rule as a GFM table, applied to
the query instead of to rows.

`McSqlQuery` is deliberately shallow: it finds a trailing `order by` and
replaces it, or appends one. When it cannot rewrite confidently the header
is simply not clickable. Sorting the fetched page client-side would lie
whenever the query has a `limit`, so it is not offered.

### 6.4 Errors and the source seam

A failed query renders as a bordered error box carrying sqlite3's stderr.
Nothing escapes the styler as an exception; the existing rule that a parse
failure degrades to unstyled text applies here too.

The fence parses to a source kind, a source reference and a query. Only
SQLite is implemented. A later source -- a Smalltalk expression, a CSV, a
bus query -- would add a producer answering an `McRelation` and touch
nothing in the renderer. No such source is built now.

## 7. Trust

A document with a database view executes SQL from that document when the
cursor leaves the block. This is the same trust model `<<button>>` handlers
already carry: a document is as trustworthy as its author. `-readonly`
bounds the damage to reads. This is stated rather than mitigated further,
because the editor's whole premise is documents that do things.

## 8. Files

| File | Contents |
|---|---|
| `pharo/McRelation.st` | new -- `McRelation`, `McRelationColumn`, `McRelationRow`, `McRelationCell` |
| `pharo/McSqlite.st` | new -- `McSqliteSource`, `McSqliteError`, `McSqlQuery` |
| `pharo/McMarkdownInline.st` | new -- `McMarkdownInlineStyler` |
| `pharo/McMarkdownTable.st` | new -- `McMarkdownTableReader`, `McMarkdownTableElement` |
| `pharo/McMarkdown.st` | `McMarkdownParser` unchanged; visitor loses cell stringification and inline styling |
| `pharo/McRichEdit.st` | loses three regex passes; gains the query cache |

`McMarkdown.st` is 717 lines holding two classes already. The new work is
split across focused files rather than added to it. Load order:
`McRelation`, `McSqlite`, `McMarkdownInline`, `McMarkdownTable`,
`McMarkdown`, `McRichEdit` -- to be reflected in `elisp/mc-rich-edit.el`
and `test/run-pharo-tests.sh`.

## 9. Testing

Everything load-bearing is pure or shell-only, so most of it tests without
Bloc.

`McRelationTest` -- sort keys and numeric detection, the ordering
permutation, `isSortedBy:ascending:`, named row access.

`McMarkdownTableReaderTest` -- cell intervals asserted by the substring
they select, following the existing pattern rather than asserting on
numbers; both separator spellings; escaped `\|`; ragged rows; alignment
parsing; the source produced by a sort round-tripping through the reader.

`McSqliteTest` -- against a fixture `.sqlite` built in `setUp` by shelling
out; `-ascii` framing, empty results, the error path, and `-readonly`
refusing a write. `McSqlQuery` order-by rewrite cases, including the
refusal case.

`McMarkdownInlineStylerTest` -- emphasis offsets within a cell substring; a
checkbox at a cell offset producing a write-back range that selects the
right document characters.

Regression tests for the two reported defects -- emphasis surviving into a
rendered cell, and a checkbox in a cell producing exactly one adornment
attribute over the table range rather than a nested table.

The existing full-cursor-sweep robustness test gains demo content with
widgets inside cells and a query block.

## 10. Phases

**Phase 1** -- sections 3, 4.1, 5 and GFM sorting. Stands alone and fixes
both reported defects.

**Phase 2** -- sections 4.2 and 6. Additive; reuses the widget unchanged.

## 11. Risks

| Risk | Mitigation |
|---|---|
| An embedded editor per widget-bearing cell is expensive | Only cells whose rope actually carries an adornment pay for one; the widget is built only when the cursor is away. Measure before optimising further. |
| Rewriting rows on sort loses the cursor | `replaceFrom:to:with:` already replaces the whole rope, as checkboxes do today. Preserving the cursor is a separate improvement, applying equally to the existing behaviour. |
| `McSqlQuery` mis-rewrites an exotic query | It refuses rather than guesses; a header that cannot be rewritten is not clickable. |
| A slow query blocks the UI | The query runs off the UI thread behind a placeholder, and cannot be triggered while typing. |
| Microdown changes its table handling | The reader no longer depends on `MicTableBlock >> rows`, only on where the block starts and ends. |

## 12. Success criteria

1. Bold, italic, inline code, checkboxes, colour swatches and buttons all
   render inside table cells.
2. A checkbox in a cell toggles the correct characters in the document and
   never renders a copy of the table.
3. Clicking a column header reorders the rows in the document source, and
   the arrow reflects the document's actual order with no stored state.
4. A `sql&db=` fence renders as the same table widget; clicking a header
   rewrites its `order by`.
5. `McSqliteSource` is usable from a playground with no editor present, and
   is tested that way.
6. A failed query and a malformed table both degrade to a visible message
   rather than an exception out of the styler.
