-- The debug fixture's database, in full.
--
-- Checked in beside the .sqlite it builds so the binary is reproducible rather
-- than merely present: `sqlite3 desk.sqlite < desk.sql` on an empty file gives
-- byte-for-byte the same tables and rows.
--
-- Deliberately small and deliberately mixed. `runs` has an integer column, a
-- real column and a text column, because the alignment rule under test is
-- "right-align a column when every non-empty cell in it is a number" and a
-- table where every column is numeric would not tell the two apart. `notes` has
-- an empty string and a NULL in the same column, because those render
-- identically in `-ascii` output and the parse must not treat either as the end
-- of a row.

PRAGMA foreign_keys = ON;

CREATE TABLE runs (
  id       INTEGER PRIMARY KEY,
  label    TEXT    NOT NULL,
  seconds  REAL    NOT NULL,
  passed   INTEGER NOT NULL
);

INSERT INTO runs (id, label, seconds, passed) VALUES
  (1, 'parse',   0.4,   1),
  (2, 'project', 12.25, 1),
  (3, 'query',   3.0,   0),
  (4, 'write',   108.5, 1);

CREATE TABLE notes (
  id   INTEGER PRIMARY KEY,
  kind TEXT    NOT NULL,
  body TEXT
);

INSERT INTO notes (id, kind, body) VALUES
  (1, 'plain',  'an ordinary note'),
  (2, 'empty',  ''),
  (3, 'null',   NULL),
  (4, 'comma',  'one, two, three'),
  (5, 'pipe',   'a | b | c'),
  (6, 'quote',  'she said "hello"');
