# Floaty corkboard

<!-- f@820x560+40-60 -->

This is the host card. It carries an absolute directive, so its geometry is
read in the corkboard's own signed document pixels, and it keeps showing the
whole file the way floaty's host buffer does.

Drag a card by its header. The directive below it is rewritten in place, and
because every card is a view onto the same text, the new numbers appear here
too.

## Relative child

<!-- f@45%x30%+5%+18% -->

This card is written in percentages, so it is 45% of the host's width and 30%
of its height, offset 5% and 18% into it. Dragging it rewrites the percentages
rather than replacing them with pixels: the unit is the intent.

### Nested deeper

<!-- f@80%x40%+10%+50% -->

A third level. Its percentages resolve against the card above it, not against
the host, and it paints above both because a card is a Bloc child of the card
it nests in.

## Fixed child

<!-- f@300x150+430+330 -->

Percent and pixel cards coexist; each of the four numbers carries its own unit.

## Not a card

This section has no directive, so it never becomes a card. Its text still
belongs to the host, which is why you can read it here.
