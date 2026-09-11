---
title: Floaty with frontmatter
tags: corkboard, floaty, frontmatter
floaty: f@760x520+900+40
---

# Frontmatter host

This document's host directive is the `floaty` key in the block above, not a
comment at the top of the file. A key in the frontmatter says outright what the
whole document is, so it outranks anything written below the block.

The block is the document's metadata, not its prose, so it is not part of this
card's text: the card starts here, at the markdown proper. The panel at the top
right of this card is where the block is edited. Each key is a window onto the
span its value occupies in the file, so typing in one writes that span and
leaves the key order, the comments and everything else exactly as written --
nothing re-emits the YAML. The `floaty` key is not one of those rows: it is this
card's directive, so it appears in the directive row above, where retyping it
moves the card the way retyping any directive does.

Fold the panel away with its toggle when you are reading rather than editing.

Break the `floaty` line and the card does not go anywhere. A child card whose
directive breaks is taken off the board, because the document no longer says
there is one; the document itself is still there, so its card stays exactly
where it was and keeps that place for the session. What it loses is the row --
there is no longer a line saying where it is -- and reopening the file starts it
wherever the program puts it.

<!-- f@45%x42%+40%+11% -->
## A child of a frontmatter host

The markdown after the block is read exactly as it is in any other floaty
document: this directive introduces a heading, so the heading belongs to this
card, and the percentages resolve against the host above.

<!-- f@80%x45%+10%+48% -->
### Nested deeper

A third level, resolving against the card above it rather than against the host.

## Not a card

No directive of its own, so no card -- the text belongs to the host, which is
why you can read it there.
