# Ragged tables

A fixture for the table projection, and nothing else. Every table here is
written badly on purpose: the source columns do not line up, the padding
differs from cell to cell, one row drops its outer pipes, one row is short and
one is long, and cells hold the things that are *drawn* rather than spelled —
emphasis, code, a wiki alias, a colour, a checkbox.

A table renders correctly here only if the columns line up for the right
reason. A projection that leaves the author's padding showing gets a tidy
source right and this one wrong, and a projection whose column box is dropped
whenever the whole cell is drawn as a widget gets every row without a checkbox
right and every row with one wrong.

## Every alignment, and a drawn cell in the middle

The `done` column is column 2 of 4 on purpose. A column box lost there moves
`owner` and `qty` left on that row alone, which is the failure a last-column
checkbox hides.

| task            |done|   owner |  qty |
|:----------------|:--:|--------:|------|
| **ship** it     |[x] |   ana   | 11   |
|a|[ ]|bo|3|
| `rm -rf` safely |[x]| *carmen* |    7 |
| [[notes\|read]] |[ ]|          | 1.25 |
|   trailing pipe dropped   |[x]| dee |  0
wrapped | [ ] | in | nothing

## Empty cells, in every position

An empty cell is a column with nothing in it, not an absent column. Each of
these rows leaves a different one blank, so a column that collapses shows up as
a row whose later cells have slid left.

| one |  two  | three |
|:----|:-----:|------:|
|     |   b   |     c |
| a   |       |     c |
| a   |   b   |       |
|     |       |       |
| a   ||     c |

## A short row and a long one

| alpha | beta | gamma |
|-------|------|-------|
| 1     | 2    |
| 1     | 2    | 3     | 4 |

## One column, drawn

| colour     |
|:----------:|
| #7f5af0    |
| `#2cb67d`  |
| [x]        |
