# floaty-desk-debug

Small, single-purpose fixtures for debugging one Floaty Desk feature at a time.
Each document here exercises one thing and says which; add a new one rather than
growing an existing one.

`samples/demo.md` is deliberately untouched by everything in here. It exercises
headings, tables, links, images, checkboxes, buttons and execution all at once,
which is what makes it a good acceptance page and a bad place to debug one
feature.

## The `sql&db=` database view

`sqlite-view.md` and `data/` are that fixture, and the rest of this file is about
them.

## Using it

Keep Floaty Desk rooted at this repository, then open the two fixtures directly:

```
bb floaty open samples/floaty-desk-debug/ragged-tables.md
bb floaty open samples/floaty-desk-debug/sqlite-view.md
```

The root matters. A database path in a `sql&db=` info string resolves against the
**desk's root**, not against the document's own directory — `McSqliteSource`'s
rule, and the reason the fixture spells the full root-relative path
`samples/floaty-desk-debug/data/desk.sqlite`.

Tick **Trust** in `sqlite-view.md` to run its queries. The server deliberately
does not start SQLite for an untrusted document.

## What is here, for the database view

- `sqlite-view.md` — seven views: an aligned table, cells that would break a
  quoted format, an empty result, a SQL error with **Retry**, a missing
  database, two queries `--safe` refuses, and one ordinary ```sql block that is
  *not* a view.
- `data/desk.sql` — the database in full, as text.
- `data/desk.sqlite` — a local generated fixture (ignored by git). Build it with:

  ```
  ./build-sqlite.sh
  ```

  The `.sql` is tracked so the ignored binary is reproducible rather than
  mysteriously machine-specific.

## What to look for

- The query stays visible under a `sqlite <path>` chip and the table is drawn
  **beside** it, not in place of it. That is this port's one deviation from
  Pharo, which replaces the whole fence; a CodeMirror decoration provided as a
  function may not be a block widget or cover a line break, so there is no way
  to collapse a three-line fence into one element.
- Putting the caret on a fence takes the table away and gives the source back.
  Moving it off revalidates the result; an unchanged database is a server-cache
  hit, while a changed modification time or size runs the query again.
- No **Run** button appears on any `sql&db=` fence, trusted or not.
- Before Trust, each database view is a locked box and no subprocess starts.
- `git diff` says nothing after any of it, including after pressing Retry.
