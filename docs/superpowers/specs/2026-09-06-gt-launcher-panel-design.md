# GT launcher panel — one manifest, three readers

A fourth panel on GT's home screen, built from a directory rather than from a
list of buttons, so that adding a tool is adding one file and nothing else.

## The problem

A launcher, today, is two facts: an ordered list of `.st` files to file in, and
one expression to evaluate once they are in. Neither fact is written down
anywhere GT can read it.

Both live in elisp — `mc-corkboard-files`, `mc-workbench-files`, `mc-kdi-files`,
and, for rich edit, thirteen paths inlined into a `format` string. The image
has no idea what the launchable set is. That is tolerable at five tools and
becomes unmanageable as the connection points accumulate, which is the trajectory
the KDI explorer, the corkboard and the rich editor are already on.

It is worse than a duplication between two places, because there is a third
copy. `test/run-pharo-tests.sh` hand-maintains its own `fileIn` sequence of
every tool's sources — and it has already drifted: it loads the corkboard,
rich-edit, SRT and workbench sets and knows nothing about KDI. That drift is
silent. Nothing fails; the tests simply do not cover what you think they cover.

The asymmetry that makes this urgent is the one the bus was built for. GT is
core; Emacs is a client that talks to it over NATS and can be swapped, run
elsewhere, or not run at all. A design in which the client is the only thing
that knows what the core can launch has the dependency backwards.

## Goals

- A panel on GT's home screen whose buttons are derived from a directory, not
  written out one by one.
- Exactly one place per tool where its load order and entry point are recorded.
- Emacs, GT and the test runner all read that one place.
- Nothing fails silently. A broken manifest is visible on the home screen; a
  missing source file is named when you click.

## Non-goals

- A configuration system. The manifest says how to load and enter a tool. It
  does not carry per-tool settings. KDI, the only tool that needs configuration,
  resolves its own binding behind its `open` expression.
- Replacing the Emacs commands that are not launchers — `mc-rich-edit-search`,
  `mc-rich-edit-render`, `mc-kdi-plan`, `mc-kdi-ingest`, `mc-kdi-slice` and the
  rest stay hand-written, because they are operations on a running tool, not
  ways to start one.
- A standalone launcher window. The value is being on the screen that is already
  there at startup.

## The contract

One JSON file per tool in `$MC_HOME/launchers/`. The whole schema:

```json
{
  "title":    "Corkboard",
  "blurb":    "Coordinate-addressable canvas, independent of rich-edit",
  "files":    ["pharo/McCorkboardPanelModel.st",
               "pharo/McCorkboardDocument.st",
               "pharo/McCorkboard.st"],
  "open":     "McCorkboard open",
  "tests":    ["McCorkboardTest"],
  "priority": 30,
  "icon":     "playIcon",
  "note":     "free text; JSON has no comments"
}
```

| field | required | meaning |
|---|---|---|
| `title` | yes | the card's label, and the section's sort key when priorities tie |
| `blurb` | yes | one line; becomes the card's tooltip |
| `files` | yes | the ordered load list, relative to `$MC_HOME`. **This is the fact that is currently triplicated.** |
| `open` | yes | one Smalltalk expression, evaluated after the files are in |
| `tests` | no | test class names for `run-pharo-tests.sh`; absent means the tool has none |
| `priority` | no | card order within the panel; absent sorts last, then by `title` |
| `icon` | no | a `BrGlamorousVectorIcons` class-side selector; absent uses a default |
| `note` | no | ignored by every reader |

Unknown keys are ignored, so the format can grow without breaking older readers.

**JSON, not STON.** STON is the native Pharo choice and would be the obvious one
for a single reader in the image. But this format has three readers, one of
which is Emacs, and elisp has `json-parse-string` built in while STON would mean
writing a parser. Pharo reads JSON with `NeoJSONReader`, which is present in the
image. JSON is the only format all three readers already have. The cost is the
absence of comments, which the `note` field absorbs.

**The launcher's name comes from the filename, not a field.** `corkboard.json`
is the launcher `corkboard`, which Emacs exposes as `mc-corkboard-open`. Deriving
it makes two launchers with the same name impossible, and makes the Emacs command
predictable without opening the file.

## The manifests to write

One per tool that has an Emacs launcher today:

| file | files | open |
|---|---|---|
| `corkboard.json` | the 3 from `mc-corkboard-files` | `McCorkboard open` |
| `workbench.json` | the 4 from `mc-workbench-files` | `McWorkbench open` |
| `rich-edit.json` | the 13 currently inlined in `mc-rich-edit-open` | `McRichEdit open` |
| `kdi.json` | the 7 from `mc-kdi-files` | `McKdiStore openLauncherSession` |
| `weather.json` | `pharo/McWeatherView.st` | `McWeatherView open` |

The KDI entry is the only one whose `open` is not an existing selector, and the
reason is exactly the coupling this change exists to loosen. `McKdiStore class >>
openSession` raises `'no KDI store bound -- run mc-kdi-bind first'` when nothing
has bound it, and `McKdiStore class >> default` is commented "a store on the
binding **the Emacs launcher** last installed". A card on GT's home screen cannot
depend on Emacs having run first.

So `McKdiStore class >> openLauncherSession` is new, and small: reuse
`McKdiBinding default` if a binding is installed, otherwise build one from the
`KDI_*` environment variables — the same variables `mc-kdi.el`'s defcustoms
already fall back to — and only then `openSession`. If neither is available it
reports what is missing on the card rather than raising.

Its purpose is to keep configuration out of the manifest format: the tool that
needs a binding is the tool that knows how to find one.

## Reader 1 — `McLauncherManifest`

A value object, one per file, in `pharo/McLauncher.st`.

```
McLauncherManifest class >> allIn: aDirectory   " sorted, one per *.json "
McLauncherManifest class >> fromFile: aReference
McLauncherManifest >> name                      " derived from the filename "
McLauncherManifest >> isValid
McLauncherManifest >> parseError                " nil when valid "
McLauncherManifest >> missingFiles              " entries not on disk "
McLauncherManifest >> loadExpression            " the fileIn chain "
```

The governing rule is that **nothing fails silently**, because silent failure is
the disease being treated.

- **Malformed JSON, or a missing required key**, does not raise and does not
  vanish from the listing. It answers an *invalid* manifest carrying the filename
  and the error, which the panel renders as an error card saying so. A manifest
  you broke while editing tells you on the home screen. This is also GT's own
  behaviour — `GtHomeMultiCardSection >> cards` catches a card method's error and
  substitutes a `GtHomeErrorCard`.
- **A manifest whose `files` are not on disk** is valid but unsatisfiable. Its
  card renders, is marked, and stays clickable; clicking reports which path is
  missing. Marked-but-clickable is deliberate over greying out: a disabled button
  with no explanation is precisely the dead end this change exists to remove.

## Reader 2 — `McLauncherSection`, the panel

A subclass of `GtHomeSection` in `pharo/McLauncher.st`.

It is **not** a `GtHomeMultiCardSection`. That class collects its cards from
`<gtSectionCard>` pragma methods — one method per card, fixed at compile time.
These cards come from a directory, so the section subclasses `GtHomeSection`
directly (it is a `BrStencil`; `create` is the hook) and builds cards in a loop
with the inherited `newToolCardWithTitle:icon:action:description:`, which gives
a 120×120 button with icon, label and tooltip.

`create` re-globs `launchers/` on every render, so a new manifest appears at the
next re-render with nothing cached to invalidate. The grid carries one extra card
at the end, **Reload launchers**, which re-renders the section in place, so the
panel can refresh itself without going through the bus.

`priority` is **40**. `GtHomeMultiCardGetStartedSection` is 30, and
`GtPhlowUtility class >> hasHigherPriority:than:` compares with `<`, so lower
sorts earlier: 40 places the launcher directly below the Get Started panel.

## Entering GtHome

`GtHome` builds its content from methods carrying a `<gtHomeSection>` pragma,
gathered by `GtHomeSectionsCollector` searching from the object. Of the three
such methods upstream ships, only `getStartedSection` still has its pragma live;
`toolsSection` and `gt4llmSection` have theirs commented out.

So the panel enters as one method:

```smalltalk
!GtHome methodsFor: '*MalleableControl'!
mcLauncherSection
	<gtHomeSection>
	^ McLauncherSection new priority: 40! !
```

This is a **package extension method, not a `McGtPatches` patch.** The
distinction is load-bearing. Every existing patch *replaces* an upstream method
body, which is why `McGtPatches` holds the body as a string and recompiles it —
and why each one has to be re-pasted when upstream edits that method. This method
is purely additive: nothing upstream is overridden, so it can be an ordinary
method with ordinary source, and it does not inherit that fragility.

`mc-bootstrap.st` files `pharo/McLauncher.st` in alongside the patches, guarded
the way everything there is guarded: a headless image has no `GtHome`, the fileIn
fails, and the failure is reported to the Transcript without stopping the bus
connection. `McGtPatches refreshHome` already re-renders every open home, so
`bin/gt-eval 'McGtPatches refreshHome'` is the path for picking up a manifest
added while GT is running.

## Clicking a card

**Every click re-files the sources from disk**, then evaluates `open`. Editing a
`.st` and clicking the button reloads it, which keeps the card and the Emacs
command the same thing and keeps the panel a live development surface rather
than a shortcut.

The work is forked, not run on the UI process. `McKdiStore >>
runOffUi:from:labelled:` already solves this and documents two traps someone paid
for:

1. A subprocess — or thirteen `fileIn`s — on the UI process is "not a spinner, it
   is a hang".
2. Refreshing through a phlow update wish **replaces the button element**, so the
   completion callback is enqueued on a detached element and never runs. The
   label sticks at "running" for a job that has already finished. The busy state
   must be written straight onto the pressed button.

It also ignores a second press while the first is in flight rather than queueing
it. All three behaviours are wanted here unchanged.

That method is therefore **lifted out of `McKdiStore` into a shared
`McOffUi class >> run:from:labelled:`**, with `McKdiStore` delegating to it. This
is the targeted improvement the change earns: the alternative is a second copy of
a comment whose whole content is "here is what we got wrong the first time".

A launcher whose `fileIn` or `open` raises reports the error on the card. It does
not open a debugger and does not take the panel down with it.

## Reader 3 — Emacs

A new generic `elisp/mc-launchers.el` reads `$MC_HOME/launchers/*.json` at load
time and defines one `mc-<name>-open` command per manifest, each of which files
the sources in through `mc-st-filein-sync` and evaluates `open` — exactly what
the hand-written commands do now.

Deleted, because the manifests now hold them:

- `mc-corkboard-files` and `mc-corkboard-open` / `-open-from`
- `mc-workbench-files` and `mc-workbench-open` / `-open-from`
- `mc-kdi-files` and `mc-kdi-load`'s list
- the thirteen-path `format` string inside `mc-rich-edit-open`

Kept, because they are operations on a running tool rather than ways to start
one: `mc-rich-edit-search`, `mc-rich-edit-render`, `mc-kdi-bind`,
`mc-kdi-status`, `mc-kdi-plan`, `mc-kdi-ingest`, `mc-kdi-discovery`,
`mc-kdi-slice`, `mc-kdi-keyword`, and every `mc-kdi-*` defcustom.

The `-open-from ROOT` variants, which point a launcher at a worktree for one
invocation, are preserved as a generic `mc-launcher-open-from` that prompts for
both the launcher and the root. The worktree workflow in `docs/worktrees.md`
depends on them.

**One launcher does more on the Emacs side than load and open.** `mc-weather-open`
also subscribes to `gt.event.weather`, so the reading appears in the minibuffer
when you click Fetch Weather in GT — a subscription that is meaningless to the GT
card and must not be lost. `mc-launchers.el` therefore runs a per-launcher hook,
`mc-launcher-<name>-hook`, before opening, and `mc-weather.el` keeps its
subscription by adding to `mc-launcher-weather-hook`. Emacs-specific behaviour
stays in Emacs; only the load list is shared.

## Reader 4 — the test runner

`test/run-pharo-tests.sh` stops carrying its own `fileIn` list. It reads the
manifests, files in each one's `files`, and runs the union of their `tests`
alongside the suites that belong to no launcher (`NatsClientTest`,
`McRelationTest`, `McCacheTest`, the markdown suites).

This is the check with teeth: a manifest with a bad path or a bad load order
fails the test run loudly, so the thing all three readers depend on cannot rot
unnoticed. It also repairs the drift that exists today — KDI's seven classes have
never been in that list.

## Testing

The repo's line is followed rather than a stricter one: `McCorkboardTest` tests
`McCorkboardPanelModel`, not the Bloc canvas, and nothing in `pharo/` builds
elements headless.

**`McLauncherManifestTest`** — pure, headless, no bus:

- a well-formed manifest parses, and every field lands where it should
- malformed JSON answers an invalid manifest carrying its error, and does not raise
- a missing required key answers invalid, naming the key
- `name` derives from the filename, not from any field
- `missingFiles` names the entries that are not on disk, and an otherwise-valid
  manifest with missing files is still valid
- ordering is by `priority`, then `title`; a manifest with no priority sorts last
- unknown keys are ignored

**The section's rendering** is verified live over the bus, not unit-tested,
consistent with every other Bloc element in this repo.

**`test/integration.sh`** gains a check that after `mc-launchers` is loaded,
`mc-corkboard-open` and `mc-kdi-open` are defined — via `mc_emacsclient --eval`,
in the harness that already drives real Emacs and real GT.

## Verification

Beyond the suites: with GT running, `bin/gt-eval 'McGtPatches refreshHome'` and
confirm the fourth panel appears below Get Started with one card per manifest;
click one and confirm the tool opens and the window stays responsive while it
loads; break a manifest's JSON and confirm an error card naming the file appears
rather than the card vanishing; point a manifest at a nonexistent `.st` and
confirm the click names that path.

## Note on repository state

Every KDI file in this repo is currently untracked — `pharo/McKdi*.st` (seven
files), `elisp/mc-kdi.el`, and two design documents. `kdi.json` will reference
files that are not yet in git. This is noted, not fixed here.
