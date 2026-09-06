# Rich Edit

A **bold** phrase, some _italic_, and `inline code` in one paragraph
that runs across two source lines to prove offsets survive the break.

## Tasks

[ ] Buy groceries
[x] Write the parser
[x] Prove thesis one
[ ] Prove thesis two

## Table

| task | colour | qty |
|:-----|:------:|----:|
| [ ] **write the reader** | #7f5af0 | 11 |
| [x] `ship the styler`    | #2cb67d | 3  |
| [ ] _sort the rows_      | #ff8906 | 7  |

Click a column header to sort -- the rows are rewritten in the document.

## Database View

```sql&db=data/tasks.sqlite
SELECT name, done, prio FROM tasks ORDER BY prio
```

## Code!

```smalltalk
McMarkdownParser parseSource: aString
```

## Lists

- unordered one
- unordered two

1. ordered one
2. ordered two

> A quote with **bold** inside it.

---

Colors: #FF0000 red, #00FF00 green, #3498DB blue.

## Links and Images

The examples below exercise the supported link spellings and resolution
states. Blue links are usable; red links are intentionally dead.

### Web links

- [Markdown link to Example](https://example.com)
- <https://www.wikipedia.org/> (GFM autolink)
- https://www.glamorous-toolkit.com/ (bare URL)
- [Malformed HTTPS URL](https://)
- [Unsupported mail protocol](mailto:nobody@example.com)
- [Blocked script protocol](javascript:alert(1))

### Local links

- [Sibling note, relative](linked-note.md)
- [[linked-note]] (wiki link with inferred `.md`)
- [[linked-note.md|Sibling note with an Obsidian alias]]
- [Sibling note, slash-absolute]($CLOUDSYNC/main/devsync/malleable-control/samples/linked-note.md)
- [Sibling note, file URL](file://$CLOUDSYNC/main/devsync/malleable-control/samples/linked-note.md)
- [Missing relative file](does-not-exist.md)
- [Missing absolute file](/definitely/missing/mc-rich-edit-note.md)

Slash-prefixed paths and `file://` URLs are both treated as absolute local
paths. A leading `~` and any `$NAME` are expanded from the environment
before resolution, which is what keeps the absolute examples above readable
on a machine other than the one that wrote them -- they resolve wherever
`$CLOUDSYNC` points, and read as dead where it is unset. Relative links
remain the portable form for documents kept together.

### Current-document links

These resolve successfully but do not reload the editor or discard its undo
history.

- [This document, relative](demo.md)
- [This document, slash-absolute]($CLOUDSYNC/main/devsync/malleable-control/samples/demo.md)
- [This document, file URL](file://$CLOUDSYNC/main/devsync/malleable-control/samples/demo.md)
- [This document with a future anchor](demo.md#links-and-images)

The fragment is retained for future within-file navigation; today it reports
that anchor navigation is pending without reopening the file.

### Images

![Linked note cards](assets/linked-notes.png "Generated linked-note illustration")

![[assets/linked-notes.png|The same local image using Obsidian embed syntax]]

![Missing image demonstration](assets/missing-image.png "Intentionally missing image")

Buttons: <<hello>>  <<time>>  <<count>>

Move your cursor into any element to reveal its raw source.

## Evaluated code

Nothing on this page runs until you tick **Trust** in the header. Untrusted,
each expression below shows its language tag and its own source; trusted, it
shows what the language answered.

The calculated radius is `{python} 5 * 2` meters.

The statistical mean is `{r} mean(c(10, 20, 30))`.

Matrix determinant: `{julia} det([1 2; 3 4])` -- julia is probably not
installed, which is what a missing interpreter is meant to look like.

Dynamic threshold: `{ojs} Math.PI * 2` -- ojs is parsed and tagged but never
evaluated; there is no interpreter to shell out to.

This image is `{smalltalk} Smalltalk version`, evaluated in the running GT
process rather than a subprocess -- the org-babel `emacs-lisp` case.

Double backticks let an expression quote backticks of its own:
``{python} len("`backticks`")``.

Fenced blocks never run on their own. Trusted, each gets a Run button; the
result is written back into this file as a `results{...}` fence.

```python
sum(range(10))
```

```smalltalk
(1 to: 10) inject: 0 into: [ :a :b | a + b ]
```

Hover any evaluated expression for its source, when it ran, and the re-run
binding.
