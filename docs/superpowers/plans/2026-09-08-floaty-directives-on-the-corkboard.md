# Floaty directives on the corkboard

Cards can now come from a file. A comment alone on its line gives a section its
geometry, and the corkboard projects the result:

```markdown
# Floaty corkboard
<!-- f@820x560+40-60 -->

## Relative child
<!-- f@45%x30%+5%+18% -->
```

The form is whacked/floaty-edit-mode's — `COMMENT_PREFIX f@WWWxHHH` with an
optional offset — and `McFloaty` is the parse layer for it. `McCorkboard` gains
a second build path beside the example board; the existing one is untouched.

## Decision

**Hierarchy is the document's, not the directives'.** A directive on the first
non-blank line of the file is the host and governs the whole document — being
the *top comment* is the whole of what makes it the host, so a directive one
line lower is a child however early it appears. Every other directive governs a
heading section: the one it introduces, when a heading is the next non-blank
line after it, and otherwise the one it sits inside. Heading levels alone then
decide nesting, and a section with no directive is not a card.

**A card's text begins at its own directive line.** That one rule settles two
things at once. It decides whether a heading belongs to the card or stays with
the host — a directive placed *above* a heading takes it in, one placed *below*
leaves it behind — and it guarantees the first line a card shows is the
directive that positions it, which keeps that directive legible in a card far
too short to scroll:

```markdown
<!-- f@45%x42%+40%+11% -->
## Relative child          <- in the card, because the directive precedes it
```

**Headings are read from `McMarkdownParser`, not by scanning for a hash.** That
parser already knows a hash inside a fenced code block is not a heading, and it
records a source range for every node — which is what lets a directive be
rewritten in place after a drag. It needed one accommodation: Microdown reads
`<!` as the opener of an environment block, so an HTML comment does not merely
fail to be a heading, it swallows the rest of the document. `McFloatyDocument`
blanks the directive lines with spaces before parsing. The mask is the same
length as what it replaces, so every offset the parser stamps still addresses
the real source.

**Two departures from floaty, both forced by the corkboard's plane.** Offsets
are signed (`f@330x230+420-120`), because a signed document coordinate is the
prototype's whole premise and `+XXX+YYY` cannot say `-120`. And the numbers are
document pixels rather than character cells, so they are the units the
coordinate fields already show and a drag writeback is lossless rather than a
rounding.

**Percentages are the new syntax, per component.** Any of the four numbers may
carry `%` independently — `f@50%x230+5%-120` is legal — and resolves against
the parent card's box: width and x against its width, height and y against its
height. A root card's parent box is the canvas viewport, so the rule needs no
special case at the top.

**A card is a Bloc child of the card it nests in.** That single choice pays for
the three things the document asks for, with no bookkeeping: a child's
`constraints position` already means "relative to my host", dragging a host
carries its children with their relative positions intact, and a child added
after its parent's body paints above it. Dragging a host therefore rewrites
only the host's own directive — the children never moved.

## Interaction contract

- A drag re-expresses the drop **in the unit the author wrote**. A percent card
  stays a percent card; the cost is that it lands on the nearest whole percent
  of the parent box, which reads as snapping. Decimals remain a pure widening
  of the grammar if that ever chafes.
- Comment style and indentation are the author's and survive writeback. Only
  the geometry is rewritten, and only for the card that moved.
- Every card body is a view onto a range of the one document, so a directive a
  drag has just rewritten reappears in every card whose region covers it — the
  host included, since the host keeps showing the whole text as floaty's host
  buffer does.
- Source ranges are stamped once and never move. `#renderedSource` replays the
  directives onto the original string back to front, so the ranges stay valid
  however often a card is dragged.
- Nothing reaches disk until **Save**. A drag updates the document the way
  floaty updates a buffer.

## Deliberate limits

**There is no transclusion yet, and no shared memory.** A card body is a fresh
rope built from a substring: `body text: (document renderRange: ...)`. Nothing
is shared between a host and the cards drawn over it. The *effect* of
transclusion comes from `refreshCardTexts` re-slicing every body from the one
`McFloatyDocument` after each change, so the document's source string is the
single truth and the cards are recomputed projections of it. That is
indistinguishable from the real thing while bodies cannot be edited, and it is
exactly what stops being true when they can.

Real transclusion here means one text with many views, which in this image is
either a shared `BrTextEditorModel` (only usable where two cards show the same
range) or the approach `McRichText` already argues for — one rope, with a card
as an *attribute over a range of it* rather than a copy of that range. The
second is the target, and it is what makes editable cards fall out instead of
being bolted on.

Card bodies are **read only**. This iteration owns parsing, hierarchy,
percentages, nested projection, drag and writeback; editing a card back into
the host rope is a separate problem — shared-rope editing or range-reconciled
writeback — and is the next piece of work.

`##` is a directive prefix only outside markdown. In a markdown file it opens a
heading, and a line cannot be both the heading that creates a section and the
comment that configures it, so `<!--` is the only prefix there.

Missing offsets default to the parent origin rather than to floaty's
stacking-by-frame-count, which would need state the parse layer does not carry.
Two directives in one section describe the same card twice; the first wins and
the second stays ordinary text.

## Verification

`McFloatyTest` (32) pins the grammar and its rejections, percent resolution,
markdown nesting by heading level, that only the top comment is the host, that
a directive above a heading takes it into the card and one below leaves it
behind, that every card region opens with its own directive, the fenced-heading
case that justifies using the real parser, the flat-file host rule and `f@end`,
and writeback — unit preserved, rounding, comment style, indentation, and
repeated moves as the text changes length. `McCorkboardTest` (10 more) pins the
projection: nesting, relative placement, paint order, host-drag carrying
children without touching their directives, a percent child rewritten in
percent, and that the demo's sample file exists and projects.

## The board itself

A **dot grid** every 40px marks the plane. It is a child of the canvas rather
than the canvas background, so it pans and zooms with the cards; a background
would sit still and say nothing about where the origin went. It is also one
stamped `Form` rather than a repeating cell, because `BlImagePatternPaint` does
not tile in this image — `#matchExtent:` is a stub that says so outright, and
`#asSpartaPaintOn:` hands Sparta the bare form, which paints it once at the
element's origin. So the plane is bounded (2400×1600 about the origin) and that
bound is what the grid costs.

Card **chrome** separates the two things a card is: the frame and title bar are
light grey, the text area is white. Bodies use `BrGlamorousCodeEditorAptitude`
for the system monospace font — a card whose first line is
`<!-- f@45%x42%+40%+11% -->` wants digits that line up.

**Interaction on the background:** the wheel zooms (clamped to 0.15–6×), and a
middle- or right-button drag pans. The left button does nothing on the
background. GT's own `withZoomOnScrollWheel` is not usable here: it zooms only
while the primary modifier is held and pans on a bare wheel, which is backwards
for a canvas, so the handler is ours.

Trackpad pinch-to-zoom and two-finger pan are a **TODO in the code**. This image
has no `BlPinchEvent` or `BlZoomEvent`, so a trackpad arrives as ordinary wheel
events and cannot be told apart from a mouse; doing it properly needs
host-level gesture events first.

## Demonstrating it

The launcher card *is* the demo. `McCorkboard open` projects
`samples/floaty.md`, so the cards the board shows come from a text file rather
than from anything hard coded, and editing that file changes what the demo
shows. Three ways in, all the same thing:

- the **Corkboard** card on GT's home screen,
- `M-x mc-corkboard-open` in Emacs (the command name comes from
  `launchers/corkboard.json`'s filename),
- `McCorkboard open` evaluated in the image.

The launcher re-files every source in the manifest before it opens, so the loop
is: edit the `.st`, click the card again, see the change. No image restart, and
one window either way.

The older free-coordinate board — cards placed by typed x and y, with Apply,
DIRTY and Escape — is still there as `McCorkboard openExample`. It is no longer
on the launcher, and its two cards remain hard coded because they are now a test
fixture rather than a demo; giving a fixture a file dependency would only make
the suite need a filesystem.

A missing sample falls back to that example board rather than raising, so the
launcher card cannot become a stack trace.

```smalltalk
McCorkboard open.                                   "the demo"
McCorkboard openDocument: 'some/other.md' asFileReference.
McCorkboard openExample.                            "the older board"
```
