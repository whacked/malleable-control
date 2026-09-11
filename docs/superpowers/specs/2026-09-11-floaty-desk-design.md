# Floaty Desk — a library beside the corkboard

*2026-09-11*

## What this is

A new tool, reached from a card in the **Malleable Control** section of GT's
home screen. It puts a file browser beside the corkboard, so a board stops
being one file's board and becomes a place you gather documents.

Today `McCorkboard open` projects exactly one document — `samples/floaty.md` —
and the only way to see another one is to open it instead. The desk keeps the
canvas and lets documents come and go on it.

Its cards are rendered by `McRichEdit`'s styler rather than by the corkboard's
plain editor, which is the first place the two prototypes are made to share a
text surface. The floaty logic is unchanged: the same parse, the same
directive rows, the same write-through editing, the same settle.

## The screen

```
┌────────────────┬──────────────────────────────────────────┐
│ samples        │                                          │
│ [Choose…]      │        ┌──────────────┐                  │
│ *.md           │        │ floaty.md    │   ┌───────────┐  │
│ ───────────    │        │ ┌──────────┐ │   │ notes.md  │  │
│ ▸ assets       │        │ │ child    │ │   │           │  │
│   demo.md      │        │ └──────────┘ │   └───────────┘  │
│   floaty.md    │        └──────────────┘                  │
│   linked.md    │                                          │
└────────────────┴──────────────────────────────────────────┘
```

Left: the library. A path, a button to change it, a glob, and a tree of what
matches. Right: one corkboard plane carrying every open document.

## Components

### `McFloatyLibrary` — what is on disk

A directory, a glob, and the entries under them. Knows nothing about Bloc.

- `root` — a directory. Default from `MC_FLOATY_ROOT`, else `<McHome>/samples`.
- `glob` — default from `MC_FLOATY_GLOB`, else `*.md`. Matched with Pharo's
  own `String>>match:`, which is already a glob (`*` and `#`).
- `entriesIn: aDirectory` — the subdirectories, then the files that match,
  each sorted by name. Directories are always listed: the glob selects
  documents, not places to look.

`McFloatyLibraryEntry` is one row: a file reference, whether it is a
directory, and — for a file — whether it carries a top-level floaty
directive. That last question has exactly one right answer already, and it is
`McFloatyDocument>>host isAnchored`: it is true for a directive comment on the
first non-blank line and for a `floaty:` key in Obsidian frontmatter, and
false otherwise, which is the two cases this tool must colour differently.
The entry reads the file once and remembers.

### `McFloatyDesk` — the tool

Owns the space, the sidebar, and one `McCorkboard` in **plane** mode. Opens
every directive-carrying document in the library onto that plane; opens the
others when their row is clicked.

- `openEntry:` — put a document on the plane, or bring its card forward when
  it is already there.
- `closeSheet:` — take one off.
- `class >> placeExtent:near:avoiding:` — where a document with nothing to say
  about its position goes: the point asked for, pushed along a short cascade
  until it stops overlapping what is already drawn. A pure function, so it is
  tested as one.

### `McCorkboard` — plane and sheet

The corkboard grows two modes rather than a sibling class, because everything
the desk needs from it — the frontmatter panel, the directive rows, the
write-through bodies, the settle, the caret restore — is already there and
none of it is worth a second copy.

- **plane**: canvas, grid, pan and zoom, and no document. `buildPlane`.
- **sheet**: one document projected into a *layer element* on somebody else's
  canvas, sharing that owner's space. `buildSheetOn:in:space:`.

A sheet is an ordinary document board whose `canvas` happens to be a layer
rather than a `BlCanvassableElement`, so `projectDocument`, `clearCanvas`,
`commitStructure` and the rest run unchanged. `clearCanvas` learns to leave
the grid alone on a sheet — a layer has no grid of its own — and that is the
whole of the difference.

`afterSaveDo:` is the hook the desk hangs the last requirement on.

### Rich text in the cards

`McCardRichEdit` is an `McRichEdit` attached to a card's editor with
`attachToEditor:` and nothing else: no window, no status bar, no file
watcher. It exists to override `showStatus:`, which otherwise writes to a
status label this configuration does not have, and to let the desk say which
file the card's text came from so relative image paths and trust resolve the
way they do in the editor proper.

A card in rich mode styles in two passes: the markdown styler first, the
floaty directive blocks over it. Floaty goes last so that a directive line is
a band whatever Microdown decided the comment was.

Rich mode is per-board, off by default, so the classic corkboard is untouched.

## The four behaviours the desk has to get right

**Documents with a directive are already placed.** The file says where the
card goes; the desk does not choose. They are opened when the desk opens.

**Documents without one are placed by the desk.** At the centre of what is on
screen now — `documentPointAt: viewportExtent / 2`, so panning moves where the
next one lands — cascaded clear of the root cards already drawn. The position
is the session's: nothing is written to the file, which is the rule the
always-present host already follows.

**Breaking a host directive does not take its card away.** That is settled
behaviour and stays exactly as it is: the card holds still and keeps its
place for the session.

**Saving a document whose host directive is broken takes it off the board.**
Save is the deliberate act. The file is written as it stands, the sheet is
dropped from the plane, and the sidebar row goes grey — because the file no
longer carries a directive, which is what grey means.

## Testing

| What | How |
| --- | --- |
| `McFloatyLibrary` | temp directories; globs, sorting, nesting, env defaults |
| directive detection | files with a comment host, a frontmatter host, and neither |
| `placeExtent:near:avoiding:` | pure function, rectangles in and a point out |
| plane and sheet modes | headless boards; a sheet keeps no grid, a plane keeps no cards |
| the desk | headless: open, count sheets, click a grey entry, break a host, save |

No test opens a window. `McCorkboard` already builds its space without
showing it, and the desk does the same.
