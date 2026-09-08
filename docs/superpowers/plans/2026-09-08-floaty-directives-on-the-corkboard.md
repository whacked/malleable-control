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

**Hierarchy is the document's, not the directives'.** In markdown a directive
attaches geometry to the heading section containing it, so heading levels alone
decide what nests inside what, and a section with no directive is simply not a
card. Everywhere else every directive is at the same level and floaty's own
rule applies: a directive on the first non-blank line governs the whole file
and every later one is its child.

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

`McFloatyTest` (27) pins the grammar and its rejections, percent resolution,
markdown nesting by heading level, the fenced-heading case that justifies using
the real parser, the flat-file host rule and `f@end`, and writeback — unit
preserved, rounding, comment style, indentation, and repeated moves as the text
changes length. `McCorkboardTest` (8 more) pins the projection: nesting,
relative placement, paint order, host-drag carrying children without touching
their directives, and a percent child rewritten in percent.

A manual open probe:

```smalltalk
McCorkboard openDocument: 'samples/floaty.md' asFileReference.
```
