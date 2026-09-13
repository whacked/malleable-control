<!-- f@1000x720+40-40 -->

# SQLite database views

Every fence below is a `sql&db=` **database view**: the info string names a
SQLite file, the body is a query, and the table under it is what the query
answered. Nothing here has a **Run** button. Tick **Trust** in this sheet before
the queries run: SQLite safe mode blocks common escape routes but is not a full
filesystem sandbox, so the server refuses every query from an untrusted page.

Keep the repository as the desk's root. A database path is resolved against the
**root**, not against this file's directory, so the fences deliberately spell
`samples/floaty-desk-debug/data/desk.sqlite` rather than `data/desk.sqlite` or
`../data/desk.sqlite`.

## A table, and how its columns are aligned

<!-- f@460x300+20+120 -->

`seconds` and `id` right-align because every cell in them is a number; `label`
does not. The alignment is derived from the answer on every render and is
nowhere in this file.

```sql&db=samples/floaty-desk-debug/data/desk.sqlite
SELECT id, label, seconds, passed FROM runs ORDER BY seconds
```

## Cells that would break a lesser format

<!-- f@460x300+500+120 -->

Commas, pipes, quotes, an empty string and a NULL. `-ascii` framing puts 0x1F
between fields and 0x1E between records, so none of these needs quoting and none
of them is escaped on the way here.

```sql&db=samples/floaty-desk-debug/data/desk.sqlite
SELECT kind, body FROM notes ORDER BY id
```

## A query that answers nothing

<!-- f@460x220+20+440 -->

An empty result is a result, and says so. A view that matched no rows must not
look like a view that has not run.

```sql&db=samples/floaty-desk-debug/data/desk.sqlite
SELECT label FROM runs WHERE seconds > 1000
```

## A failure, and the Retry button

<!-- f@460x260+500+440 -->

`sqlite3` reports the error, the box says what it was, and **Retry** asks again.
Retry writes nothing: the document is byte-identical before and after.

```sql&db=samples/floaty-desk-debug/data/desk.sqlite
SELECT * FROM table_that_is_not_there
```

## A database that is not there

<!-- f@460x220+20+720 -->

`Database not found`. Put a file at that path and the box replaces itself with a
table on the next render — the answer is filed under the database's modification
time and size, so a file appearing is a different question rather than a cached
"no".

```sql&db=samples/floaty-desk-debug/data/absent.sqlite
SELECT 1
```

## What a view may not do

<!-- f@460x300+500+720 -->

After Trust is granted, each of these common escape routes is still refused by
`sqlite3 --safe`. Safe mode is defense in depth; the Trust gate is required
because SQLite builds may expose other file-reading virtual tables.

```sql&db=samples/floaty-desk-debug/data/desk.sqlite
ATTACH DATABASE '/etc/passwd' AS other; SELECT 1
```

<!-- f@460x200+500+1040 -->

```sql&db=samples/floaty-desk-debug/data/desk.sqlite
SELECT readfile('/etc/hosts')
```

## Not a database view

<!-- f@460x220+20+960 -->

A bare language name is ordinary code and behaves exactly as it did: no table,
and a **Run** button in a trusted document. Nothing in this tranche changed it.

```sql
SELECT 1
```
