# Corkboard coordinate-canvas prototype

## Decision

This is not a hierarchy of native child windows. It is one GT `BlSpace` whose
root holds a `BlCanvassableElement`. The canvas is an infinite, pannable and
zoomable coordinate plane; each card is an ordinary Bloc element projected at
its model coordinate with `relocate:`.

`McCorkboardPanelModel` holds the durable panel identity, committed signed
`x`/`y`, text, and separately typed coordinate drafts. `McCorkboardDocument`
indexes those models by stable id. Neither knows about Bloc, a space, pixels,
or the current zoom. That is the persistence/addressing boundary.

`McCorkboard` is the view/controller prototype. It deliberately pins basic
`BrEditor` text rather than the full Markdown projection: the experiment is
coordinate placement and interaction, not rich-edit throughput.

## Interaction contract

- Coordinate drafts are visibly `DIRTY` and never move a card while typed.
- **Apply** parses both signed integer drafts and commits atomically; invalid
  input leaves the placement unchanged.
- **Escape** discards pending drafts. It is installed as a canvas event filter
  because focused `BrEditor` instances consume normal Escape shortcuts.
- A header-only `BlPullHandler` moves cards. Its final Bloc document position
  is committed to the same model path as Apply, which resets both displayed
  coordinate values to the committed result.
- Positive and negative coordinates are first-class. `disableAutoScale` is
  required: automatic fit-to-content would make displayed coordinates differ
  from the user’s document plane.

## Deliberate limits

The prototype relies on `BlCanvassableElement` for pan/zoom but does not yet
add a minimap, persistence codec, virtualisation, selection of multiple cards,
or viewport-origin labels. Full `McRichEdit` embedding is deferred until the
card contract is stable; the model and panel boundary were chosen expressly so
the basic `BrEditor` body can be swapped for a Rich Edit element.

## Verification

`McCorkboardTest` pins signed coordinates, dirty/apply/discard, invalid input,
and id-to-coordinate lookup. A manual open probe is:

```smalltalk
'pharo/McCorkboardPanelModel.st' asFileReference fileIn.
'pharo/McCorkboardDocument.st' asFileReference fileIn.
'pharo/McCorkboard.st' asFileReference fileIn.
(Smalltalk at: #McCorkboard) open.
```
