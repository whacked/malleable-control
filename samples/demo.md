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
paths. The absolute examples are intentionally machine-specific; relative
links are the portable form for documents kept together.

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
