# Spec: GFM Rich-Edit Engine — Microdown Parser + AST Styler

Date: 2026-08-29
Status: implemented (see agents/notes/2026/08/2026-08-29.002-microdown-ast-styler-lessons.md)

## 1. Scope

Replace McRichEdit's ad-hoc regex scanners with a proper parse → AST → style
pipeline, using Microdown as the parser and a new BlText visitor as the
renderer. This delivers GFM-subset coverage (tables, bold/italic, headers,
lists, code blocks, horizontal rules) with the cursor-locality rendering
model already proven in the prototype.

### In scope

- Load Microdown parser into the GT image (parser packages only, not Morphic renderers)
- Write `McMarkdownStylerVisitor` — walks `MicAbstractBlock` AST, applies BlText
  attributes with cursor-locality toggling
- Migrate existing features (bold, checkboxes, buttons, color swatches) to AST nodes
  or post-AST annotation passes
- Add **table** rendering via `BrTextAdornmentDynamicAttribute` injecting a
  `BlElement` grid widget
- Add **header** rendering (font size + weight scaling)
- Add **fenced code block** rendering (monospace, background tint)
- Add **horizontal rule** rendering
- Add **list** rendering (indentation + bullet/number styling)
- Wire the new styler into McRichEdit, replacing the 4 regex scanners
- Update demo content to exercise all supported elements
- Test against GFM spec examples where Microdown covers them

### Out of scope

- Org-mode support (dropped)
- Full CommonMark conformance (Microdown is a practical subset)
- Strikethrough, extended autolinks, footnotes (not in Microdown)
- Inline images / link navigation (future work)
- Editing-side features (auto-indent, auto-close delimiters)
- Performance optimization for large documents

## 2. Architecture

### Current state (regex)

```
Source rope
  → styleText: calls 4 regex scanners
    → styleCheckboxes:  (regex → widget)
    → styleBold:        (regex → hide + bold)
    → styleColors:      (regex → swatch widget)
    → styleButtons:     (regex → button widget)
  → cursor locality checked per match
```

### Target state (AST)

```
Source rope
  → MicParser parse: ropeString
    → MicAbstractBlock AST
  → McMarkdownStylerVisitor visit: ast withText: aBlText cursor: pos
    → walks AST, applies BlText attributes per node type
    → cursor locality checked per AST node range
  → Post-AST annotation pass (custom tokens: [ ]/[x], #RRGGBB, <<btn>>)
    → regex scan for tokens Microdown doesn't know about
    → apply same widget-injection attributes
```

The two-phase approach (AST first, then custom-token overlay) lets us
leverage Microdown for standard markdown while keeping our prototype's
custom features (checkboxes, color swatches, buttons).

### Key classes

| Class | Role |
|---|---|
| `MicParser` | Microdown's line-by-line GFM-strategy parser |
| `MicAbstractBlock` | AST node base class (headers, paragraphs, lists, tables, code blocks) |
| `McMarkdownStylerVisitor` | New. Walks AST, applies BlText attributes |
| `McRichEdit` | Existing. Owns editor, palette, button handlers |
| `BlPluggableStyler` | Existing. Entry point; block now calls parser + visitor |

### Table rendering

Tables are multi-line block elements. The visitor will:

1. Identify the table node's text range (start of first `|` to end of last row)
2. When cursor is **away**: apply `BrTextAdornmentDynamicAttribute beReplace`
   injecting a `BlElement` with `BlGridLayout` containing styled cells
3. When cursor is **near**: show raw pipe syntax with column-alignment
   highlighting (same pattern as bold/checkboxes)

Table cells will be `BlTextElement` instances inside the grid, inheriting
palette colors. Header row gets bold weight. Alignment (`:---`, `:---:`,
`---:`) maps to `BlLinearLayout` alignment on the cell.

### Header rendering

Headers (`# ` through `######`) map to font size scaling:

| Level | Font size | Weight |
|---|---|---|
| H1 | 28 | bold |
| H2 | 24 | bold |
| H3 | 20 | bold |
| H4 | 18 | bold |
| H5 | 16 | bold |
| H6 | 14 | bold |

The `#` prefix characters get `BrTextHideAttribute` when cursor is away,
shown dimmed when cursor is near (same pattern as `**` for bold).

### Fenced code blocks

Triple-backtick blocks get:
- Monospace font attribute on the content range
- Background tint via a `BrTextAdornmentDynamicAttribute beAppend` or
  direct background attribute
- Fence lines (``` ``` ```) hidden when cursor is away
- Language tag preserved for future syntax highlighting

### Cursor locality

The existing `cursor:isNear:to:` method generalizes to AST nodes.
Each node has a source range. The visitor checks proximity once per
node and branches into "raw" vs "rendered" styling.

## 3. Implementation phases

### Phase 1: Parser integration (foundation)

Load Microdown parser into GT. Verify it parses our demo content
into a correct AST. Write a minimal visitor that just applies
bold/italic to prove the pipeline works end-to-end.

### Phase 2: Migrate existing features

Move bold, header, and paragraph styling from regex to AST visitor.
Keep checkboxes, colors, and buttons as post-AST annotation passes
(they are custom tokens Microdown doesn't parse).

### Phase 3: Tables

Add table node visiting. Build the BlGridLayout widget. Wire up
cursor locality for the table block. Update demo content with a
sample table.

### Phase 4: Remaining block elements

Add code blocks, horizontal rules, and lists. Each is a new
`visitXxx:` method in the visitor.

### Phase 5: Polish and testing

Update demo content to exercise all features. Test against GFM
spec examples. Fix edge cases. Commit.

## 4. Risks

| Risk | Mitigation |
|---|---|
| Microdown may not load cleanly into GT's Pharo 12 | Load parser packages only; they have no Morphic deps. Test early (Phase 1). |
| Microdown's AST may not expose source ranges | Check `MicAbstractBlock` for `start`/`stop` or equivalent. If missing, patch or compute from structure. |
| Multi-line `beReplace` on tables may cause layout issues | Prototype a simple 2×2 table widget first. Fall back to column-aligned text if widget injection doesn't work for multi-line blocks. |
| Re-parsing on every keystroke may be slow | Microdown is fast for small documents. Defer optimization until it's measurably slow. |
| Cursor locality for nested AST nodes (bold inside table cell) | Walk depth-first; innermost match wins. Same precedence as current regex approach. |

## 5. Success criteria

1. Demo content renders bold, headers, tables, code blocks, lists, and horizontal rules
2. Cursor-locality toggling works for all rendered elements
3. Custom tokens (checkboxes, colors, buttons) still work via post-AST pass
4. No regression in existing prototype functionality
5. Tables render as grid widgets with header row styling and cell alignment
