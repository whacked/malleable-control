<!-- f@820x560+40-60 -->
# Floaty corkboard

This is the host card. Its directive is the top comment of the file, which is
what makes it the host: it governs the whole document, in the corkboard's own
signed document pixels, and it keeps showing the whole text the way floaty's
host buffer does.

Drag a card by its header. The directive is rewritten in place, and because
every card is a view onto the same text, the new numbers appear here too.

<!-- f@45%x42%+40%+11% -->
## Relative child

The directive sits above the heading, so the heading belongs to this card. It
is written in percentages, so it is 45% of the host's width and 42% of its
height, offset 40% and 11% into it. Dragging rewrites the percentages rather
than replacing them with pixels: the unit is the intent.

<!-- f@80%x45%+10%+48% -->
### Nested deeper

A third level. Its percentages resolve against the card above it, not against
the host, and it paints above both.

<!-- f@300x170+430+330 -->
## Fixed child

Percent and pixel cards coexist; each of the four numbers carries its own unit.

<!-- f@end -->

An `f@end` closes a card early. This paragraph is still inside the `## Fixed
child` section, so the host below shows it, but the card above stops before it.

## Not a card

This section has no directive of its own, so it never becomes a card. Its text
still belongs to the host, which is why you can read it here.

Neither does the `# Floaty corkboard` heading above: the host directive precedes
it and owns the whole file, so no separate card is made for that section.
