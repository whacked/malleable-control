# Rich Edit Search Strategy

## Outcome

Add a modular, source-addressed incremental search experience to `McRichEdit`:

- typing updates results immediately;
- all matches receive a search highlight;
- one active result receives a distinct highlight;
- next/previous navigation wraps and makes the active match visible;
- cancellation removes only search presentation, restoring normal markdown
  projection; and
- literal search is the default, with an API that admits regex, glob, and
  multi-string matchers without changing editor integration.

## Architectural boundary

Search is an ephemeral overlay, not a concern of `McMarkdownStylerVisitor`.
It works over the editor's source rope and composes *after* markdown
projection:

```text
source rope -> markdown AST/projection -> search overlay attributes
```

This keeps search state out of parsing and prevents one matcher implementation
from becoming the editor's only search model.  Search-owned attributes must be
identifiable and removable without clearing markdown styles or live adornments.

## Public model

Introduce small, independently testable objects.

- `McSearchQuery`: input text plus options such as case sensitivity and whole
  word.  Empty input produces no matches.
- `McSearchMatcher`: protocol `matchesFor:in:` answering ordered, nonempty
  source ranges.  Start with `McLiteralSearchMatcher`; define extension seams
  for `McRegexSearchMatcher`, `McGlobSearchMatcher`, and
  `McMultiStringSearchMatcher`.
- `McSearchSession`: query, matcher, match ranges, active index, and direction.
  It owns wraparound navigation and answers the active range.
- `McSearchPresentation`: applies normal and active overlay attributes and
  clears only attributes it owns.
- `McSearchNavigator`: routes next/previous commands and scrolls/focuses the
  active range through the editor API.

The editor should depend only on the matcher protocol and session interface,
not on literal-search implementation details.

## Rendering and interaction policy

1. Recompute the session on each query change; preserve the active result when
   its range survives, otherwise select the first result.
2. Apply the overlay after every markdown styling pass.  This is necessary
   while normal source edits still require full markdown projection.
3. On cancellation, clear search-owned attributes and leave markdown
   attributes/adornments untouched.
4. Matches address source ranges.  If a match is hidden by a replacement
   adornment, normal highlighting may target the visible owner component; an
   active match should reveal its source owner or visibly outline that owner.
   Implement the basic source-text path first and make replacement handling an
   explicit, tested policy rather than an accidental side effect.
5. Search must not mutate the document, undo stack, or cursor merely by
   highlighting.  Navigation may move/scroll the caret only when invoked.

## Delivery sequence

1. **Model and matcher tests** — literal matching, case options, empty query,
   overlapping/non-overlapping policy, wraparound, and active-index retention.
2. **Presentation layer** — search-owned normal/active attributes, idempotent
   reapplication, and precise cleanup.
3. **Editor integration** — lifecycle state, reapply after markdown styling,
   next/previous/cancel hooks, and viewport navigation.
4. **UI affordance** — keyboard-triggered incremental search with a compact
   query control; `Esc` cancels, Enter/Shift-Enter navigate.
5. **Replacement/transclusion policy** — component owner highlighting or source
   reveal for active hidden matches.
6. **Extensions** — regex, glob, and multi-string matchers conforming to the
   same protocol.

## Acceptance criteria

- Searching `link` in `demo.md` highlights every source-visible match, with
  one distinct active match.
- Repeated next/previous commands wrap deterministically.
- Editing the query updates results without modifying document text.
- Cancelling restores the exact markdown projection and removes search-only
  attributes.
- A markdown restyle caused by an edit re-applies the active search overlay.
- Matcher/session/presentation tests run headlessly; rich-editor integration
  tests cover search lifecycle and cleanup.

## Guardrails

- Do not couple search matching to Microdown parsing.
- Do not clear all text attributes during search cleanup.
- Keep matcher computation off external I/O and make literal search linear in
  source size per query revision.
- Preserve unrelated user changes and keep work isolated in a dedicated
  worktree until integration review.
