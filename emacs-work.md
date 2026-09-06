# Emacs Workbench

## Bootstrap

Resolve `elisp/` from this file's own location so the buffer works wherever
the checkout lives.

```emacs-lisp
(add-to-list 'load-path
             (expand-file-name
              "elisp"
              (file-name-directory
               (or load-file-name buffer-file-name default-directory))))
(require 'mc-emacs-service)
(mc-emacs-start)
(mc-demo-ask-gt)
```

## Launchers

Every tool below is described by one file in `launchers/`, holding its ordered
`.st` load list and the expression that opens it. Three things read that
directory and nothing keeps a list of its own: GT's home screen, which grows one
button per manifest; the Emacs commands in this file, which are generated from
it; and `test/run-pharo-tests.sh`, which files in and runs from it.

Adding a tool is adding one JSON file. No elisp, no Smalltalk, no test-runner
edit.

```emacs-lisp
(require 'mc-launchers)
(mc-launchers-load)     ; re-read after adding or editing a manifest
```

That defines `mc-corkboard-open`, `mc-rich-edit-open`, `mc-kdi-open`,
`mc-workbench-open` and `mc-weather-open`. Each files its sources in from disk
every time it runs, so editing a `.st` and re-running the command reloads it.

`mc-launcher-filein` is the reload half without the open -- add a `gtView`
method, file it back in, and an inspector that is already open picks it up:

```emacs-lisp
(mc-launcher-filein "kdi")
```

To open one from a worktree rather than this checkout, for one invocation:

```emacs-lisp
(mc-launcher-open-from "rich-edit" "/path/to/worktree")
```

The same launchers are on GT's home screen, in a **Malleable Control** panel
below Get Started. Those buttons do exactly what these commands do, including
re-filing the sources on every press. After adding a manifest while GT is up,
press **Reload** in the panel, or:

```emacs-lisp
(mc-llm--eval "McGtPatches refreshHome")
```

A manifest that will not parse does not disappear: it renders as a card
carrying its own error. One whose sources are missing keeps its title and says
which path is gone.

## LLM Chat Launcher

GT's chat lives in the image, not in a window. These commands surface it from
Emacs over the bus.

```emacs-lisp
(require 'mc-llm)
(mc-llm-install-keys)   ; C-c g c/n/h/s/w/d/o/l
```

Refresh GT's main window to re-render the chat pane and add a chat dropdown to
the toolbar. This is needed because `GtHome` asks whether there are LLM
connections exactly once, while the image is still booting, and never asks
again.

```emacs-lisp
(mc-llm-refresh-home)   ; C-c g h
```

Open or inspect chats:

```emacs-lisp
(mc-llm-chat)           ; C-c g c -- chat in its own window (reuses the last)
(mc-llm-new-chat)       ; C-c g n -- chat in its own window, fresh history
(mc-llm-status)         ; C-c g s -- what is connectable, and why not
```

Choose which backend a chat talks to. A chat keeps the connection it was born
with: `GtLChat` builds a provider from the registry default the first time it
is asked, then caches it forever. Changing the default therefore affects only
new chats; the chat currently on screen must be re-pointed explicitly.

```emacs-lisp
(mc-llm-switch)         ; C-c g w -- re-point the chat on screen, keep history
(mc-llm-use)            ; C-c g d -- set the default, i.e. what NEW chats get
(mc-llm-new-chat-on)     ; C-c g o -- new chat on a named connection
(mc-llm-chats)          ; C-c g l -- every chat and the server it talks to
```

## Weather Station Demo

Open a Bloc view in GT with a Fetch Weather button. GT auto-detects the
location, fetches from Open-Meteo, renders vector weather icons, and publishes
the temperature back here.

```emacs-lisp
(require 'mc-weather)   ; for the gt.event.weather subscription
(mc-weather-open)
```

After clicking **Fetch Weather** in GT, inspect the full plist from the last
reading:

```emacs-lisp
mc-weather--last
```

## Smalltalk REPL / Eval Minor Mode

This provides an nREPL-like workflow: a REPL buffer and evaluation keybindings
for `.st` files.

```emacs-lisp
(require 'mc-smalltalk)
```

Commands and keybindings:

```text
M-x mc-st-repl          open REPL
M-x mc-st-mode          activate in .st buffers (auto for .st files)
C-x C-e                 eval region/line
C-c C-c                 eval method at point
C-c C-k                 fileIn buffer
C-c C-z                 switch to REPL
```

## Evaluate Anything

`mc-llm--eval` is `gt.cmd.eval`: whatever `bin/gt-eval` can do, this can.

```emacs-lisp
(mc-llm--eval "GtLConnectionRegistry instance connections size printString")
(mc-llm--eval "(Smalltalk at: #McGtPatches) apply")
```

## Rich Edit Demo

```emacs-lisp
(require 'mc-launchers)
(mc-rich-edit-open)
```

### Verify we're loading the latest source

```emacs-lisp
(mc-llm--eval
 "((Smalltalk at: #McRichEdit) >> #attachToEditor:) sourceCode")
```

### Search

The rich edit includes an interactive search overlay (Cmd-F in GT).
You can also drive it programmatically from Emacs:

```emacs-lisp
(mc-rich-edit-search "link")
```

That returns a plist shaped roughly like:

```emacs-lisp
(:document "/…/samples/demo.md"
           :sourceSize 2944
           :query "link"
           :matchCount 21
           :ranges ((846 849) (906 909) ...)
           :activeIndex 1
           :activeRange (846 849)
           :highlightAll t
           :wrapAround t)
```

## Corkboard Demo

The corkboard is a standalone coordinate-addressable canvas, independent of
the rich-edit editor.

```emacs-lisp
(require 'mc-launchers)
(mc-corkboard-open)
```

## KDI Data Explorer

A moldable alternative to `kdi tui`. GT runs `kdi ... --json` as a subprocess and
turns the answers into inspectable objects, so exploring a corpus is drill-down
rather than tab-hopping: a source opens its structural tree, a node opens its
passages, a passage opens its grounding. GT never opens the evidence SQLite
database and never imports a KDI schema — the whole contract is the public JSON.

Bind the store first. `mc-kdi-store` is the only setting without a usable
default; the rest fall back to `KDI_*` environment variables.

`mc-kdi-find-root` locates the checkout instead of naming it, so nothing here
is specific to one machine: it walks `$CLOUDSYNC/work` breadth-first looking
for a directory called `knowledge-base-collector`. Emacs globbing has no `**`,
and breadth-first also settles ties the way you want -- the shallowest match
wins, so a stale copy nested deeper cannot shadow the live checkout. Set
`mc-kdi-search-root` if the tree lives somewhere else.

```emacs-lisp
(require 'mc-kdi)
(setq mc-kdi-root    (or (mc-kdi-find-root)
                         (error "No knowledge-base-collector under %s"
                                mc-kdi-search-root))
      mc-kdi-store   (expand-file-name ".kdi/local/evidence.sqlite" mc-kdi-root)
      mc-kdi-profile "local"
      mc-kdi-tier    "public"
      mc-kdi-paths   '("docs/operating")
      mc-kdi-pipeline-profile "hook")
(mc-kdi-open)
```

`mc-kdi-open` is generated from `launchers/kdi.json`: it files that manifest's
sources in, installs the binding from the settings above, and inspects one
`McKdiStore` in GT. That inspector **is** the explorer.

The store's own tabs are Preflight, Sources, Ingestion, Plan, Last ingest,
Transcript and Binding, with four buttons: **Refresh**, **Plan update** (writes
nothing, calls nothing external), **Ingest** (canonical evidence only, no
enrichment stage, so no provider is reachable) and **Initialize store**. Each
button runs its subprocess off the UI process, so the image stays usable.

From there, selecting a row opens the object it names:

```text
McKdiStore -> McKdiSource -> McKdiNode -> McKdiPassage
                  |              |             `- Grounding, Text, Selector
                  |              `- Children, Passages (N of M shown), Provenance
                  `- Structure (tree), QC audit, Passages
```

Every object also carries a **Raw** view of the JSON it was built from and a
**Command** view naming the exact argv, exit code and duration — so any screen
can be reproduced by pasting a command.

Run things without opening a window:

```emacs-lisp
(mc-kdi-status)   ; profile/tier, schema, source / node / passage counts
(mc-kdi-plan)     ; kdi update plan, write-free
(mc-kdi-ingest)   ; kdi ingest over mc-kdi-paths
```

### The derived layer — bundles and slices

Bundles are the *context block* step of the chain, and the normal slice
candidate. They do not exist until discovery has derived them, which the store's
**Run discovery** button does (`kdi discovery run --topics none` — it writes
bundles, and reaches no provider; topics are left off because `auto` evaluates a
recorded grid).

```emacs-lisp
(mc-kdi-discovery)   ; run it without opening a window
```

The store then grows **Discovery**, **Bundles** and **Slice** tabs. Selecting a
bundle opens it with its reconstructed **Text** and its **Passages** — and
selecting a passage row there walks straight down to that passage's grounding.
That walk, from a derived grouping into the exact source characters, is the one
the Textual workbench lists under its own Known limits as impossible.

The **Slice** tab lists the recipe; **click any row to open the recipe itself**,
which is where its buttons live. (GT builds the action bar from the object being
inspected, so a forwarded view shows another object's *view* while the toolbar
still belongs to the store — the store therefore also carries its own **Plan
matches** button so you never have to leave it.)

The step-by-step walkthrough of the derived layer lives in
`docs/kdi-explorer-walkthrough.md`.

On the recipe, **Planned matches** is the tab after **Recipe**, and the plan's
own **Provider coverage**, **Plan**, **Notes** and **Specification** are
forwarded onto the recipe beside it -- clicking a planned row sends a *candidate*,
so the plan object itself is never landed on. If the plan was
refused -- the commonest case being a recipe with no query and no keywords, which
would select the whole universe in an arbitrary order -- that same tab shows the
backend's refusal, its exit code and the exact argv, instead of disappearing.

**`Edit recipe`** is a dropdown with one editor per field -- name, query,
keywords, limit, set type, tier ceiling, source URIs -- and `Apply and replan`
sets them all and replans. `mc-kdi-keyword` and `mc-kdi-slice` call the same
setters, so either surface works; nothing in the walkthrough needs Emacs.

The loop is write-free up to the last line:

```text
McKdiSliceRecipe  -- query, limit, set type, sources, tier ceiling, mask
   |  Plan matches (writes nothing)
McKdiSlicePlan    -- Candidates, Provider coverage, Plan, Notes, Specification
   |
McKdiSliceCandidate -- Why it ranked, Bundle, Passages, Text
   |
McKdiBundle -> McKdiBundleMember -> McKdiPassage -> Grounding
   |  Plan packet (writes nothing)
McKdiPacket -> McKdiPacketItem -> McKdiPassage -> Grounding
   |
McKdiSliceRecipe -- Materialize (WRITES: the definition and one EvidenceSet)
```

### The packet -- what a report is actually built from

`kdi infer plan --bundle ID --no-cache` answers the evidence packet a report
would be drafted over, makes no model call and writes nothing at all. It is on
every bundle as **Plan packet (writes nothing)**.

A packet takes **exactly one subject** -- a topic, a bundle, or a *materialized*
slice. A recipe is not a subject, which is why the bundle is the crossing that
costs nothing and the slice route needs the write first.

Its tabs are **Items** (`handle` -- `E001`, what a report cites -- role,
relevance, tokens, overlap, and a sentence saying why each is in the packet),
**Excluded** (the candidates the packet refused, the rule that refused them and
the arithmetic: `token-budget` / `needs 5424 token(s); 5157 remain in the
budget`), **Packet**, **Coverage**, **Bundles**, **Limitations**, **Universe**
and **Specification**. A packet item's `Passages` walk down to the same grounding
screen a bundle member does.

### The one write

`Materialize (WRITES)` runs `slice create --run`: it saves the definition under
the recipe's name and materializes one immutable EvidenceSet. `--plan` and
`--run` are refused together by the CLI, so it is a different argv rather than a
flag added to the plan's.

It is previewable. The plan already computes the identity the slice *would*
have, so the Recipe tab's `slice id` row reads either `prospective --
Materialize would write this EvidenceSet` or `already exists -- materializing
would reuse it, not write` before you press anything. Afterwards the
**Materialized** tab reports the definition id, whether that version is new or
identical to the saved one, what it supersedes, and whether the result was
created or `reused -- identical inputs, identical slice`.

Then `kdi report build --slice gt-explorer` takes the name directly.

The recipe view labels every field **FILTER — exact** or **ASPECT — ranks only,
never excludes**, because that distinction decides what a slice means and nothing
in the Textual form separates them visually.

**Keywords are a filter; the query is an aspect.** `--query` ranks and never
removes, so on a 19-bundle universe a query alone returns all 19. The `keyword`
filter is the exact text predicate:

| control | what it does |
|---|---|
| terms | keep only candidates whose text matches |
| `all` / `any` | conjunctive or disjunctive over the terms |
| `token` / `substring` / `phrase` | whole tokens (case folded) · raw characters, for identifiers and paths · an exact contiguous run |
| `negate` | remove the candidates that **do** match |

The recipe carries buttons for all three toggles, each of which replans. Combine
them freely — a keyword filter removes, then the surviving candidates are ranked
by whatever aspects are present. That is the hybrid: one collection of methods,
each of which is either exact or ranking, and the recipe says which.

```emacs-lisp
(mc-kdi-keyword "grounding selector")   ; exact filter; empty string clears it
(mc-kdi-slice   "passage grounding")    ; ranking aspect
```

**Mask / unmask** on a candidate adds an `--exclude` and replans. It writes
nothing, and the masked candidate stays in the table as a `masked` row so it can
be unmasked — it does not vanish. Nothing in this loop costs a definition version
or a materialized result.

Two consecutive plans are diffed for you, which nothing else in KDI does: the
recipe's **Plan diff** tab lists gained, lost and moved candidates with their
rank movement, and the store's **Plan diff** does the same per stage for two
`kdi update plan` runs.


### Adding a view while you are looking at the data

This is the point of doing it in GT. Add a `gtView` method to any `McKdi*` class,
file it in, and the open inspector picks it up — no restart, no layout code:

```emacs-lisp
(mc-st-filein-sync (expand-file-name "pharo/McKdiEvidence.st" mc-kdi-home))
```

File them in dependency order if you touch more than one. `McKdiEvidence`
defines `McKdiObject`, which every other class subclasses, so reloading it alone
leaves the rest stale:

```emacs-lisp
(mc-kdi-load)   ; the whole set, in the order launchers/kdi.json declares
```

Findings about KDI's public model that came out of building this are in
`docs/kdi-explorer-findings.md`.

## Workbench

The Workbench is a multi-panel BlSpace window. The left panel is an SRT
subtitle editor with a tabular view, dirty tracking, and a native file
picker. The right panel is a tmux-backed terminal emulator.

```emacs-lisp
(require 'mc-launchers)
(mc-workbench-open)
```

**SRT Editor (left):** Click **Open** to choose an `.srt` file via the
macOS file picker. Entries appear in a table: index, start time, end time,
and subtitle text (all editable except index). A red dot and an enabled
**Save** button appear when anything has been modified.

**Terminal (right):** Click inside the terminal panel to give it focus,
then type normally. The terminal runs a real tmux session so full-screen
programs like `vim` work. The panel polls tmux at ~30 FPS and forwards
all keystrokes. Currently monochrome; ANSI colour support is planned.
