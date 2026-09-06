# Language-labeled code, evaluated in place

**Status:** design, approved 2026-09-06
**Supersedes nothing.** Extends the markdown parser, the inline styler, the
block visitor and the rich text editor.

## The idea

Markdown's inline code span carries no language, so nothing can be done with
it beyond drawing it in a monospace font. Quarto extends the syntax with a
leading label:

```
The calculated radius is `{python} 5 * 2` meters.
The statistical mean is `{r} mean(c(10, 20, 30))`.
Matrix determinant: `{julia} det([1 2; 3 4])`.
Dynamic threshold: `{ojs} Math.PI * 2`.
``{python} len("`backticks`")``
```

The label has two jobs. Syntax highlighting on export, later and out of scope
here; and evaluation, which is the point of this phase.

The semantics are Org Babel's, not Quarto's:

  * For most languages the evaluator is a one-shot subprocess, one per unique
    expression.
  * For `smalltalk` the evaluator is the running GT image itself, exactly as
    `#+begin_src emacs-lisp` evaluates against the running Emacs.

That second case is not new capability. `McGtService` already answers
`gt.cmd.eval` with `Smalltalk compiler evaluate:`, and `emacs-work.md`
documents `mc-llm--eval` as a front end to it, so the Emacs REPL already
evaluates against the live image. The editor runs *inside* GT, so it reaches
the same evaluation without the bus.

## Naming: the language is `smalltalk`

The marker is `smalltalk`, not `gt`. Language and execution context are
separate axes: the label's other stated purpose is syntax highlighting, and a
highlighter wants a language name. Running in-image is a property of the
*evaluator registered for* that language, which leaves room for `python` to
gain a session evaluator later without renaming the language. `gt` is accepted
as an alias.

## Architecture

Five units, two of them new files. Each one is independently testable and
none of them knows about the next.

```
McMarkdownCodeScanner   syntax only -> McMarkdownCode (value object)
McCodeEvaluator         language -> result, cached and off the UI process
McBoundedCache          existing; the LRU
McMarkdownInlineStyler  existing; renders inline spans
McMarkdownStylerVisitor existing; renders fenced blocks
```

The scanner never evaluates. The evaluator never parses. Neither touches the
rope. This mirrors `McMarkdownLink`/`McMarkdownLinkScanner`, whose class
comment already states the rule: "The scanner owns syntax only. It never
resolves a path, stats a file, opens a browser, or loads an image."

### 1. `pharo/McMarkdownCode.st` -- the node and the scanner

`McMarkdownCode` replaces the generic monospace node for labeled spans. It
carries:

| ivar | meaning |
|------|---------|
| `language` | lowercased label from `{...}`, e.g. `'python'` |
| `expression` | the source between the label and the closing fence, trimmed |
| `start`, `stop` | full span in the inline source, delimiters included |
| `bodyStart`, `bodyStop` | the expression's own span, for cursor locality |
| `fence` | length of the backtick run |
| `isInline` | true for spans, false for fenced blocks |

`McMarkdownCodeScanner` walks one inline block and is deliberately tolerant,
for the same reason the link scanner is: every intermediate keystroke is
parsed, so an incomplete token must be left alone rather than swallowing the
rest of the line.

**The fence length is data, not a constant.** The scanner counts the opening
run of backticks and closes only on a run of the same length. That is what
makes

```
``{python} len("`backticks`")``
```

parse correctly, and it is why the scanner cannot be built on Microdown's
`MicMonospaceFormatBlock`, which assumes a symmetric fixed-width delimiter
(see `delimiterWidthOf:from:to:`, which computes the width by halving the
difference between the raw span and the inner text).

A span is labeled only when `{` follows the opening run *immediately*, the
label is non-empty and contains no whitespace or backtick, and `}` closes it.
Anything else is not a labeled span and is left entirely alone, so ordinary
inline code keeps rendering exactly as it does today.

### 2. `pharo/McCodeEval.st` -- results and evaluators

`McCodeEvalResult`, modeled on `McSqliteResult`: `ready` / `failed` /
`pending`, carrying `output`, `message` and `evaluatedAt` (a UTC
`DateAndTime`).

`McCodeEvaluator` holds a class-side registry from language to evaluator, and
the cache. Two evaluator kinds:

**Subprocess evaluators** -- `python3 -c`, `Rscript -e` and `julia -e`.
These run on a background process
through the same mechanism `McSqliteSource` uses, whose class comment states
the contract: the styler "takes whatever the source already knows and never
waits", a cold expression answers `pending` and starts a job, and when the job
lands it does not touch the rope -- it asks the editor to restyle, and the
restyle finds the result in the cache. Identical in-flight jobs coalesce under
a mutex so two spans with the same expression run one process, not two.

The command is wrapped in `timeout` when `timeout` is on PATH. It is on this
machine, from the nix profile.

**The in-image evaluator** -- `smalltalk` (alias `gt`) is
`Smalltalk compiler evaluate:`, run synchronously on the calling process,
answering `printString` of the value. There is no subprocess and no
background job, because the whole point is to reach *this* image's state.

**Missing interpreters answer `failed`, they do not raise.** `julia` is not on
PATH on this machine, so `{julia} det([1 2; 3 4])` renders as a visible "no
interpreter for julia" rather than a broken document. `ojs` is registered with
no evaluator at all and always answers that way -- Observable JS is a browser
dataflow runtime with nothing to shell out to, and mapping it onto `node`
would silently diverge from real OJS the moment anything used a reactive cell
or `FileAttachment`.

**Known limitation, stated rather than hidden:** a subprocess can be capped by
`timeout`; in-image Smalltalk cannot. `{smalltalk} [ true ] whileTrue` freezes
the editor, and there is no honest way around that in this phase. It is the
same bargain Org Babel makes with elisp.

### 3. The cache

`McBoundedCache`, unchanged, at its `default` limit of 64 and configurable
through `limit:`. It already provides exactly the three properties wanted --
a bound, recency, and hit/miss counters -- and its class comment explains that
the counters exist so a test can assert a fast path was taken instead of
timing it. That is how the caching tests here are written.

The key is the language plus the canonicalized source. Canonicalization trims
leading and trailing whitespace and **leaves the interior exactly alone**.
Collapsing interior whitespace would silently corrupt Python, where
indentation is syntax.

Cached results are not invalidated automatically. `{smalltalk} McKdiStore
session label` reads live image state and a subprocess may read a file that
has changed since, so re-evaluation is explicit: a keystroke re-runs the
expression under the cursor, dropping just its cache entry; with a prefix
argument it clears every entry for the document. Because that is a hidden
feature, the rendered element carries a tooltip naming the binding -- see
Rendering below.

### 4. Trust

Executing a labeled expression means that opening a document can run arbitrary
code, and this editor follows links and wiki-links into other documents. So
evaluation is gated.

A **`Trust` checkbox with a visible label**, in the header row beside
`Dark Mode`, using the same `BrGlamorousCheckboxAptitude`. Scope is one
document. State lives in memory for the image's lifetime; **there is no
on-disk trust store**, deliberately, so there is nothing to go stale or be
edited into a lie.

Untrusted is the default, and it governs both halves:

| | untrusted (default) | trusted |
|---|---|---|
| inline `{lang} expr` | renders as tagged source; nothing runs | evaluates and renders its result |
| fenced ` ```lang ` block | **no Run button is drawn at all** | a permanent Run button under every block |

A fenced block still never evaluates by being rendered, trusted or not.
Trust decides whether the control to run it exists.

### 5. Rendering -- inline

A new `styleCode` pass in `McMarkdownInlineStyler`, first among the token
passes in `styleAll`, so it claims its source range ahead of checkboxes,
colour swatches and buttons. The class comment's rule holds: first claim wins,
and `styleAll`'s order is the precedence, so a checkbox inside a labeled
expression stays literal text.

Labeled spans are masked in `maskedForEmphasis` alongside link destinations,
so Microdown never parses them as monospace and cannot apply a second set of
attributes underneath our adornment.

Three states:

  * **Cursor near** (`isNearSource:to:`, already used identically by links):
    the raw source, so it can be edited.
  * **Cursor away, evaluated**: a small colored tag naming the language,
    followed by the output. The tag's colour comes from the palette, keyed by
    language, so it survives the dark-mode toggle.
  * **Cursor away, pending**: the tag plus a placeholder, replaced when the
    restyle triggered by the finished job comes round.

**Hover tooltip.** `BrGlamorousWithExplicitTooltipAptitude` on the rendered
element, carrying the source, the evaluation timestamp, and the re-run binding
(`Cmd-Shift-E`). This exists specifically so the re-run keystroke is
discoverable rather than folklore.

### 6. Rendering -- fenced blocks

`visitCode:` currently branches on `info beginsWith: 'sql&db='`. That becomes
a general dispatch on the info string, with `sql&db=` as one case among
several and everything else falling through to today's behaviour.

A ` ```python ` block renders as a code block exactly as it does now. When the
document is trusted it also gets a **Run** button beneath it. The button is
**permanent** -- it does not disappear after a successful run, and it does not
disappear after a failed one. Org Babel's blocks are always re-evaluatable and
this copies that, for better or worse. When the document is untrusted no
button is drawn at all.

Where the button sits depends on the cursor. Away from the block the closing
fence is replaced by the button, so the block reads as code followed by its
control; with the cursor on the block the source is showing and the button is
appended after it, so editing a block never takes its button away. The closing
fence is never both hidden and replaced -- a hide attribute and an adornment
over the same characters render unpredictably.

Blocks never evaluate on their own. Only the button runs them.

**On success the result is written into the document as text**, because a
result that exists only as render state is invisible to every other tool and
gone at the end of the session:

    ```results{2026-09-06T14:22:01.123Z}
    12.0
    ```

The info string carries the ISO-8601 UTC timestamp of the evaluation. A
`results{...}` fence is itself recognized by the visitor and rendered as a
result panel with that timestamp as a small annotation along its top edge.
Other markdown tools show it as a code block with an unfamiliar language,
which is a fair degradation.

Re-running a block **replaces** its existing results fence rather than
appending a second one. The results fence belonging to a block is the
`results{...}` fence immediately following it, separated by at most a blank
line.

**On error nothing is written to the document.** The button remains, and the
error is shown beside it as transient render state. A failed run must not
leave a stale success behind, so an existing results fence for that block is
removed when a re-run fails.

Writing goes through `owner replaceFrom:to:with:`, the same call a checkbox
inside a table cell already uses to mutate the document.

**The main risk in this design.** Evaluation now mutates the document, which
puts it in contact with the file watcher, the reconciler and the render
snapshot -- machinery the ephemeral `sql&db=` view never touches. This gets
its own task and its own tests rather than riding along with the block work.

## Testing

The existing kit covers this without a display. `test/run-pharo-tests.sh`
runs headless through the GT CLI and reads `launchers/*.json` for what to
load, so new suites are registered by editing `launchers/rich-edit.json`
rather than a second list.

  * `McMarkdownCodeTest` -- the scanner is a pure function over strings:
    labels, fence widths, the double-backtick case, unterminated spans,
    non-labeled spans left alone, and interaction with links and checkboxes.
  * `McCodeEvalTest` -- registry lookup, missing interpreter, the cache's
    hit/miss counters proving a second render did not re-run anything,
    eviction at the limit, canonicalization preserving interior whitespace,
    and in-image `smalltalk` evaluation.
  * Write-back is asserted through `McRecordingOwner`, the existing test
    double that the checkbox-in-a-cell test uses to verify document offsets.

Regression cover is the 138 existing tests in `McMarkdownTest`, including the
parser-parity suite that compares against stock Microdown.

## Out of scope

Syntax highlighting of expressions; persistent REPL sessions; `ojs`
execution; variable sharing between blocks; trust state on disk.
