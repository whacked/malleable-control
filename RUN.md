# malleable-control — run guide

Core NATS as a local routing layer between **Glamorous Toolkit**, **Emacs**, and
**any terminal**. No participant is the router; the bus is.

Phase 1 is an interop proof: every participant can publish, subscribe, serve a
request, and issue one. Architecture and rationale live in
[`docs/nats_local_process_bus_design.md`](docs/nats_local_process_bus_design.md);
what this phase actually builds is in
[`docs/superpowers/specs/2026-08-26-nats-process-bus-design.md`](docs/superpowers/specs/2026-08-26-nats-process-bus-design.md).

## Prerequisites

```bash
nix-shell          # provides nats-server + the nats CLI; sets MC_HOME, PATH
```

**Everything below assumes you are inside that shell**, including
`bin/bus-status`. Participant checks are made by asking over the bus with the
`nats` CLI, so outside `nix-shell` they cannot be made at all -- `bus-status`
says `UNKNOWN` and tells you why. The bus line itself reads a pid file and
works either way, which is exactly what makes running it from the wrong shell
confusing. Emacs 30+ and the GT app
are expected to be installed already; set `GT_HOME` if yours is not at
`/Applications/GlamorousToolkit-MacOS-aarch64-v1.1.564`.

## Start the bus

```bash
bin/bus-start        # nats-server on 127.0.0.1:4223  (not 4222 -- no collisions)
bin/bus-status       # bus + which participants are actually answering
bin/bus-status --wait  # ...but wait for them (GT takes ~15s from launch)
bin/bus-stop
```

## Connect Emacs

```bash
bin/emacs-participant start     # a hermetic -Q daemon; stop / status also work
```

To use **your own** Emacs instead, evaluate:

```elisp
(add-to-list 'load-path "<MC_HOME>/elisp")
(require 'mc-emacs-service)
(mc-emacs-start)
```

## Connect Glamorous Toolkit

One-time, opt-in:

```bash
bin/gt-install-startup     # writes ~/Library/Preferences/pharo/12.0/mc-bus-startup.st
```

Then **launch `GlamorousToolkit.app` normally** — it comes up connected. Undo
with `bin/gt-uninstall-startup`.

For a headless GT (what the tests use):

```bash
bin/gt-participant start
```

## Prove it works

```bash
bash test/integration.sh          # full mesh, on its own isolated port
```

Or watch it happen, one idea per script:

| Demo | Shows |
|---|---|
| `demo/01-terminal-to-emacs.sh` | terminal asks Emacs, Emacs answers |
| `demo/02-terminal-to-gt.sh` | terminal asks GT, GT answers |
| `demo/03-emacs-to-gt.sh` | Emacs as a *client* of the bus, not just a service |
| `demo/04-full-mesh-flow.sh` | terminal → Emacs → GT → Emacs → terminal |
| `demo/05-broadcast.sh` | events: one publish, no reply, whoever cares listens |
| `demo/06-unknown-subject.sh` | the bus filters capabilities; unknown subjects just time out |

Unit tests need no bus and no display:

```bash
emacs -Q --batch -L elisp -l ert -l elisp/nats-client-test.el -f ert-run-tests-batch-and-exit
bash test/run-pharo-tests.sh
```

## Subjects in this phase

```
emacs.query.capabilities        gt.query.capabilities
emacs.query.buffer.current      gt.query.image.info
emacs.query.buffer.contents     gt.cmd.inspect
emacs.cmd.buffer.open           gt.cmd.eval          (escape hatch)
emacs.cmd.eval    (escape hatch) gt.event.inspector.opened
emacs.event.buffer.opened

system.event.client.connected / .disconnected
```

Envelopes:

```json
request   {"v":1,"args":{...}}
reply ok  {"v":1,"ok":true,"result":{...}}
reply err {"v":1,"ok":false,"error":{"code":"...","message":"..."}}
event     {"v":1,"source":"emacs","ts":1787737891000,"data":{...}}
```

## Driving it by hand, from each client

**From a terminal**

```bash
nats --server "$MC_NATS_URL" request emacs.query.buffer.current '{"v":1,"args":{}}'
nats --server "$MC_NATS_URL" request gt.query.image.info        '{"v":1,"args":{}}'
nats --server "$MC_NATS_URL" pub emacs.cmd.buffer.open '{"v":1,"args":{"path":"/tmp/hello.txt"}}'
nats --server "$MC_NATS_URL" pub gt.cmd.inspect        '{"v":1,"args":{"expression":"3 + 4"}}'
nats --server "$MC_NATS_URL" sub 'emacs.event.>'     # watch Emacs
nats --server "$MC_NATS_URL" sub '>'                 # watch everything
```

**From Emacs** (`M-:`, or `C-x C-e` in a scratch buffer)

```elisp
(mc-demo-ask-gt)                       ; ask GT about its image

(nats-request-sync mc-emacs-connection "gt.cmd.inspect"
  (json-serialize '(:v 1 :args (:expression "1 to: 10"))))
;; => {"ok":true,"result":{"class":"Interval","printString":"(1 to: 10)",...}}

(mc-emacs-publish-event "system.event.demo.ping" '(:note "hi from emacs"))
```

**From Glamorous Toolkit** (a Playground)

```smalltalk
McGtService current client isConnected.

McGtService current client
	request: 'emacs.query.buffer.current'
	data: '{"v":1,"args":{}}'
	timeout: 5.

McGtService current client
	publish: 'emacs.cmd.buffer.open'
	data: '{"v":1,"args":{"path":"/tmp/hello.txt"}}'.
```

In a windowed GT, `gt.cmd.inspect` opens a real inspector and the reply carries
`"inspectorOpened":true`; headless it reports `"headless":true` and opens
nothing. Note that "headless" here means *no Bloc space open* -- GT always runs
the VM headless and draws through Bloc, so `Smalltalk isHeadless` is true even
in a windowed image and is not a usable display check.

## When GT does not connect

The startup hook logs every launch to `run/gt-startup.log`:

```
... startup script ran; imagePath='/Applications/...' matches=true
... classes loaded from /Users/.../malleable-control
... connected
```

`matches=false` means the hook fired in a different Pharo image and correctly
skipped. No file at all means the hook is not installed -- run
`bin/gt-install-startup`. On a GUI launch the Transcript is invisible, so this
log is the only place failures show up.

Four things that look like breakage but are not:

- **Running `bin/bus-status` outside `nix-shell`.** Participant status is
  `UNKNOWN`, not DOWN, and the script says so.

- **GT takes roughly fifteen seconds to appear.** The startup hook runs late in
  image boot, so checking straight after opening the app reports DOWN for
  something that is merely still starting. `bin/bus-status --wait` blocks until
  it shows up; `tail -f run/gt-startup.log` shows it happening.
- **A participant can lag a bus restart by a few seconds.** Clients reconnect
  on a backoff capped at 5s, so `bus-status` may report DOWN briefly after
  `bin/bus-start`. Ask again.
- **Two participants of the same kind both answer.** A leftover
  `bin/gt-participant` and a windowed GT both serve `gt.*`, so requests get two
  replies. `bin/gt-participant stop` before using the app, and
  `bin/emacs-participant stop` sweeps stray daemons by name.

## Layout

```
elisp/nats-client.el        Core NATS protocol for Emacs. Knows no subjects.
elisp/mc-emacs-service.el   emacs.* subjects -> editor operations.
elisp/mc-llm.el             Emacs launcher for GT's chat. Binds C-c g.
elisp/mc-launchers.el       Reads launchers/ and defines one command per tool.
launchers/*.json            One per tool: its .st load order and how to open it.
run/llm-endpoint.txt        OpenAI-compatible servers, one per line.
run/llm-models.txt          What each of them last said it serves.
run/llm-default.txt         The connection chosen with 'gt-llm use'.
pharo/NatsClient.st         Core NATS protocol for Pharo. Knows no subjects.
pharo/McGtService.st        gt.* subjects -> GT operations. Display-agnostic.
pharo/McGtPatches.st        Overrides of GT's own code. Reapplied every start.
pharo/McLlm.st              GT's LLM connections, driven from the bus.
pharo/McLlmStream.st        Streaming responses from an OpenAI-compatible server.
pharo/McRichText.st         Demo: markdown blocks swapped for live components.
pharo/McLauncher.st         Reads launchers/; the home-screen launcher panel.
pharo/McOffUi.st            Runs work off the UI process, marking the button.
pharo/mc-bootstrap.st       Loads all of the above into an image and connects.
nats/nats-server.conf       Localhost-only, port 4223.
bin/                        Lifecycle scripts.
demo/  test/                Proof.
```

The protocol/semantics split is deliberate: the subject namespace will churn in
later phases, and none of that should reach wire-protocol code.

## Launcher manifests

A launcher is two facts -- an ordered list of `.st` files to file in, and one
expression to evaluate once they are in. Both live in one JSON file per tool
under `launchers/`, and three things read that directory:

- **GT's home screen.** `McLauncherSection` builds one card per manifest, in a
  **Malleable Control** panel below Get Started.
- **Emacs.** `mc-launchers.el` defines `mc-<name>-open` per manifest.
- **`test/run-pharo-tests.sh`.** Files in each manifest's sources and runs the
  suites it declares.

None of the three keeps a list of its own, so they cannot disagree about what
is launchable or in what order it loads. Adding a tool is adding one file.

One thing the manifest does *not* carry: where a suite's own `.st` lives. The
runner names `pharo/Mc*Test.st` files explicitly, because a test class has to
exist before `Smalltalk at:` can find it and the manifest only lists the classes
to run. **A new suite is therefore two edits** — the class names in the
manifest's `tests`, and a `fileIn` line in `test/run-pharo-tests.sh`. Forgetting
the second is loud rather than silent: the runner reports `NO SUCH TEST CLASS`
and fails.

```json
{
  "title":    "Corkboard",
  "blurb":    "Coordinate-addressable canvas, independent of the rich editor",
  "files":    ["pharo/McCorkboardPanelModel.st",
               "pharo/McCorkboardDocument.st",
               "pharo/McCorkboard.st"],
  "open":     "McCorkboard open",
  "tests":    ["McCorkboardTest"],
  "priority": 30,
  "icon":     "play",
  "note":     "free text; JSON has no comments"
}
```

| field | required | meaning |
|---|---|---|
| `title` | yes | the card's label, and the sort key when priorities tie |
| `blurb` | yes | one line; becomes the card's tooltip |
| `files` | yes | the ordered load list, relative to `MC_HOME` |
| `open` | yes | one Smalltalk expression, evaluated after the files are in |
| `tests` | no | test class names for the runner; absent means none |
| `priority` | no | card order; absent sorts last, then by `title` |
| `icon` | no | a `BrGlamorousVectorIcons` selector; absent uses a default |
| `note` | no | ignored by every reader |

Unknown keys are ignored, so the format can grow without breaking older readers.

**The launcher's name comes from the filename, not a field.** `corkboard.json`
is the launcher `corkboard`, which Emacs exposes as `mc-corkboard-open`. Two
launchers therefore cannot collide, and the command name is predictable without
opening the file.

**`open` is compiled separately from the fileIns, and this is not optional.**
Pharo resolves variable names when it COMPILES an expression, so
`'...McCorkboard.st' asFileReference fileIn. McCorkboard open` does not compile:
the class does not exist yet. Both readers evaluate the two halves as separate
expressions, the second only after the first has run. It is the same reason the
older hand-written elisp said `(Smalltalk at: #McRichEdit) open`.

Nothing fails silently. A manifest that will not parse renders as a card
carrying its own error rather than vanishing from the panel; one whose sources
are missing keeps its title and names the missing path; and either one fails
`test/run-pharo-tests.sh` outright.

### One window per tool

A second click on a card does not open a second window. Every `open` runs the
same two lines,

```smalltalk
open
	^ (McWindow front: self) ifNil: [ self new openView ]
```

and `McWindow front:` finds the live window by looking for an instance of the
class whose `space` variable holds an open `BlSpace`. That is a search of
`allInstances`, not a registry, on purpose: the launcher re-files sources from
disk before every open, and a registry would go stale across a class
redefinition at exactly the moment the panel is being used to reload code. It
answers `nil` when there is no live window, which is the caller's signal to
build one.

**Refresh is opt in, and the default is to leave the window alone.** On finding
a live window `McWindow` foregrounds it, then sends `refreshView` if -- and only
if -- the class implements it:

| tool | on a second click |
|---|---|
| Corkboard | front, then re-project the cards from the model, or from the floaty document when one is loaded |
| Weather | front, then re-fetch |
| KDI Explorer | front, then fire the inspector's update wish |
| Rich Edit | front only -- it may hold unsaved text |
| Workbench | front only -- it holds a live tmux session |

So a tool that cannot refresh itself without destroying work says so by not
implementing the method, and adding a tool can never silently start discarding
a user's edits.

KDI is the one tool that cannot be found this way: `GtInspector` builds a fresh
space on every call and hands it to a pager, so the space belongs to the pager
rather than to the store. `McKdiStore` therefore remembers its own pager and
fronts that instead. Its refresh is the update wish, which re-renders the views
from answers already cached -- no subprocess call.

Because the reuse lives in each tool's `open` rather than in the panel, the
Emacs commands get it too: `mc-corkboard-open` twice also yields one window.

## Inspecting and changing the live image

`gt.cmd.eval` gives full control of a running GT over the bus, and two scripts
wrap it.

```bash
bin/gt-eval 'Smalltalk version'          # evaluate an expression
bin/gt-eval <<'PHARO'                    # or a whole block on stdin
LeDatabase gtBook pages size
PHARO
bin/gt-load pharo/McLlm.st               # push edited code into the live image
bin/gt-load                              # reload everything this repo owns
```

Smalltalk uses single quotes for strings, so prefer a quoted heredoc over a
shell-quoted argument.

`bin/gt-load` is the loop that makes this worth having: edit a file here, push
it into the image you already have open, and keep the windows you were working
in. Nothing is saved into the image — `pharo/` is the source of truth, and
`mc-bootstrap.st` files it all back in on the next start.

### Patches to GT's own code

`pharo/McGtPatches.st` holds overrides of upstream GT methods. They live here
rather than being saved into the image so they are version controlled and
reapplied on every start. Five are in place:

- The two **"Setup LLM connections"** buttons looked up a GT Book page by a
  title upstream had since renamed, so `pageNamed:` signalled `KeyNotFound` out
  of the button's action block and GT opened a debugger. They now resolve the
  page by any of its known titles, then by substring, and fall back to the
  connection registry rather than raising.
- **Ollama discovery** assumed anything answering on Ollama's port was Ollama.
  Any other service there answers JSON with no `models` key, which raised
  mid-way through `updateConnections` — after it had already emptied the
  connection list, leaving the registry with no connections at all. A failure
  there now just means "Ollama offered nothing".
- **A past assistant turn** was replayed to the server as `output_text`, which
  in the Responses API is an *output* content type. An input item carrying it
  has to be a full output message, so the item matched nothing and the request
  was rejected before the model saw it. Replayed as `input_text` now. See
  *When a request fails* below — this is the one that made every chat work
  exactly once.
- **A failed turn could not be serialized at all.** No visitor in the image
  implements `visitGtLErrorMessage:`, so once a chat contained one error, every
  later message in it died with a `MessageNotUnderstood` before reaching the
  network. All three provider paths can serialize one now.
- **The message box collapsed on every streamed update.**
  `GtLMessageViewsElement >> onViewsReady:` throws the child holding the text
  away and puts a freshly computed one in its place, and the replacement fills
  asynchronously — so the box briefly holds nothing and, being
  `vFitContentLimited`, falls to no height. The patch pins the height across
  the swap. See *Why streaming used to flicker* below.

`McGtPatches apply` is idempotent and also rebinds matching buttons in windows
that are already open, since patching a method does not touch elements already
drawn.

## Setting up LLM connections

The rightmost card on GT's Home page is not a thing in its own right. It shows
a **"Setup LLM connections"** placeholder while
`GtLConnectionRegistry instance hasConnectableDefaultConnection` is false, and
GT's chat panel — prompt input and all — as soon as it is true. So there is no
separate panel to add: make one connection connectable and that same card
becomes the prompt. It decides once, though, so after changing anything below
run `bin/gt-llm home` — see [Where the chat actually is](#where-the-chat-actually-is).

```bash
bin/gt-llm status                          # what is connectable, and why not
bin/gt-llm endpoint                        # list the OpenAI-compatible servers
bin/gt-llm endpoint add http://vllm-b:8000    # add one, keep the others
bin/gt-llm endpoint remove http://vllm-b:8000
bin/gt-llm probe                           # ask each what it serves
bin/gt-llm rediscover                      # re-ask, replacing the model cache
pbpaste | bin/gt-llm set-key anthropic
pbpaste | bin/gt-llm set-key openai
bin/gt-llm enable-ollama                   # local Ollama instead
bin/gt-llm use 'Qwen3.8-27B @ vllm-b:8000'    # pick the default
bin/gt-llm streaming on                    # live token-by-token output
bin/gt-llm home                            # re-render GT's main window
bin/gt-llm open-chat                       # live chat window (reuses the last)
bin/gt-llm new-chat                        # live chat with a fresh history
```

A connection is connectable when its provider says so:

| Provider          | Requirement |
|-------------------|-------------|
| OpenAI-compatible | `bin/gt-llm endpoint <url>` — **no key needed** |
| Anthropic         | `~/.secrets/anthropic-api-key.txt` exists |
| OpenAI            | `~/.secrets/open-ai-api-key.txt` exists |
| Ollama            | enabled *and* the local Ollama server has a model pulled |

`set-key` reads the key from **stdin**, never from the command line, and never
sends it over the bus — it writes the file GT checks (mode 600) and then asks
GT only to re-read its providers.

### Any OpenAI-compatible server

`endpoint` is the path that needs no credential. Point it at anything serving
OpenAI's `/v1` — vLLM, LM Studio, llama.cpp — and one connection is registered
per model the server reports from `/v1/models`.

```bash
bin/gt-llm endpoint http://vllm-a:8000     # make this the only one
bin/gt-llm endpoint add http://vllm-b:8000  # or run several at once
bin/gt-llm probe
#   http://vllm-a:8000 -- unreachable (offering #('Qwen3.8-27B') from cache)
#   http://vllm-b:8000 -- serves #('Qwen3.8-27B')
```

The URLs are remembered in `run/llm-endpoint.txt`, one per line, gitignored —
the address of a server on your network is not a fact about the project. A
`/v1` suffix and a trailing slash are stripped for you; the endpoints already
carry their own paths.

#### Several servers at once

Every configured server contributes one connection per model it serves, and
they all appear together in the `+` dropdown of the chat pane, grouped under
**OpenAI-compatible**:

```
Qwen3.8-27B @ vllm-a:8000
Qwen3.8-27B @ vllm-b:8000
```

The `@ host:port` is not decoration. Two vLLM servers can serve a model of the
same name — ours both serve `Qwen3.8-27B` — and without the host the dropdown
would offer the same word twice.

**Order is preference.** The first server in the file is the one whose model
becomes the default connection, and `endpoint add` appends, so adding a server
never moves the default. To choose explicitly:

```bash
bin/gt-llm use 'Qwen3.8-27B @ vllm-b:8000'
```

That choice is remembered in `run/llm-default.txt` and re-applied on every
rebuild — including at startup, from `McGtPatches apply`. It has to be:
`GtLConnectionRegistry >> updateConnections` resets the default to its own
hardcoded `standardDefaultConnection` every time it runs, so a choice made
without this would survive on disk and nowhere else.

#### Switching a chat's backend

`use` sets the default, and the default is only ever read **once per chat**:

```smalltalk
GtLChat >> provider
	^ provider ifNil: [ self buildDefaultProvider ]
```

Lazy, then permanent. A chat is welded to whatever was default the first time
it needed a backend, and nothing re-reads it — so `use` cannot move a chat that
already exists, and the chat pane's own picker latches the same way
(`GtLChatRegistryViewModel >> selectedConnection` caches on first read too).

| Want | Do |
|---|---|
| move the chat on screen, keeping its history | `bin/gt-llm switch '<label>'` |
| set what **new** chats get | `bin/gt-llm use '<label>'` |
| a new chat on one server, default untouched | `bin/gt-llm new-chat '<label>'` |
| see which chat talks to which server | `bin/gt-llm chats` |

```
$ bin/gt-llm chats
1.            2 message(s)  http://vllm-a:8000/
2.            0 message(s)  http://vllm-b:8000/
3. [on screen] 2 message(s)  http://vllm-b:8000/
```

`switch` re-points every chat currently in a window — that is what "the current
chat" means — and falls back to the most recent chat when no chat window is
open. History stays: it lives on the chat, not the provider.

In GT itself, the chat pane has a connection button next to `+`: pick there,
then `+`, and the new chat is built on that connection
(`GtLChatRegistryViewModel >> addChat` uses `selectedConnection`, not the
registry default). `bin/gt-llm use` now re-points that picker too, so the
button and the config cannot disagree.

#### A server that is off the network

Model lists are cached in `run/llm-models.txt` and connection discovery is
**cache-first**: a server GT has talked to before keeps its connections, and
its place in the dropdown, whether or not it answers today. `bin/gt-llm
rediscover` re-asks every server and replaces the cache.

This is not a convenience. `openAiCompatibleConnectors` runs inside the
registry's lock, on the bus read loop, every time connections are rebuilt —
which includes every startup. A blocking call to a machine that is off the
network stops the whole image answering for as long as the OS takes to give up
on the connect, which is minutes. So every request that can reach the network
is wrapped:

```smalltalk
ZnConnectionTimeout value: self endpointTimeoutSeconds during: [ ... ]
```

Five seconds, measured: an unreachable host returns `ConnectionTimedOut` in
3014 ms at a 3-second setting rather than hanging.

Note that a **default** connection pointing at a server that is down still
costs you: GT's own UI asks that connection questions, and those requests are
not wrapped by anything of ours. If the machine is off the network for long,
`bin/gt-llm use` the other one.

Two things had to be bridged to make this work, both in `McLlm`:

- GT's nearest provider, `GtLLmStudioProvider`, is already "an OpenAI `/v1`
  server at a base URL of my choosing, with no API key". `McLlm providerClass`
  subclasses it and changes only the URL.
- GT's model-listing endpoint is LM Studio's, not OpenAI's: it asks
  `/api/v1/models` and reads a `models` array of `display_name` entries. A plain
  OpenAI server serves `/v1/models` and answers a `data` array of `id` entries.
  `McLlm modelsEndpointClass` is that endpoint.

Both classes are built programmatically rather than declared in the chunk file,
because their superclasses exist only inside a GT image.

`open-chat` opens **a chat**, not the chat registry. The registry element — the
list with the `+` button — is an *index*: opening a chat from it is a phlow spawn event,
and only a phlow container catches those (an inspector, a pager,
`GtWorldElement`). Put that list in a bare `BlSpace` and it draws fine, `+` adds
a row, and clicking the row goes nowhere. `McLlm openChat` inspects the chat
instead, which opens `GtPhlowChatTool` — a phlow container, and the chat itself.

#### When a request fails

Two defects used to make a single failure permanent. Both are patched in
`pharo/McGtPatches.st`; they are described here because the symptoms are
confusing and they are upstream's, so they will come back if the patches are
ever dropped.

**Every chat worked exactly once.** GT serialized a previous assistant turn as

```json
{"role": "assistant", "content": [{"type": "output_text", "text": "..."}]}
```

and sent it back in the request's `input` list. `output_text` is an *output*
content type: an input item carrying it must also say `"type": "message"` and
carry the id and status the server issued. Without that the item can only match
the plain input-message shape, whose blocks may be `input_text`, `input_image`
or `input_file` and nothing else. So vLLM rejected the whole request:

```
240 validation errors: Input should be a valid string ...
```

That is pydantic reporting that it tried every branch of the union and none
fit — the count grows with the conversation, which is the giveaway. The first
message in a chat has no assistant turn to replay and so always went through;
every message after it was refused. Nothing about it depended on which server
was up.

**And then the chat was stuck for good.** When a request fails, the reply's
final message becomes a `GtLErrorMessage` and stays in the history.
`GtLReplyMessage >> messagesDo:` hands it to the request builder with
everything else, serialization dispatches through `acceptVisitor:` — which
performs `visit<ClassName>:` — and no visitor in the image implements
`visitGtLErrorMessage:`. So every later message died with

```
Instance of GtLOpenAiResponsesMessageVisitor did not understand #visitGtLErrorMessage:
```

*before* touching the network, however healthy the server was by then. A blip
cost the chat rather than the message.

A failed turn is now replayed as a one-line note:

```
[this turn failed and was not answered: ConnectionClosed: Connection aborted to vllm-a:8000]
```

This is the one place these patches do not follow upstream. GT's own
`GtLErrorMessage >> serializeForOpenAIResponsesAPI` reports the exception's
message, class, description **and full stack trace** — and that turn then goes
out with every later message for the rest of the chat's life. Measured on a
chat three failures in: **348 KB** of request payload, nearly all of it Pharo
backtrace, and the model answered with nothing at all. The same chat with the
short note is 2 KB and answers normally. A model can act on "the previous turn
failed, and why"; it can do nothing with a VM stack. The full error is still
shown in the chat window, which is where it is useful.

## Where the chat actually is

GT does not have a chat *window* it opens on demand. The chat is a pane, and
there are three places it surfaces:

| Where | How it gets there |
|-------|-------------------|
| Third pane of the main window | `GtHomeMultiCardGetStartedSection >> gtLlmCard` |
| Chat dropdown in the world toolbar | `GtWorldElement >> gtWorldChatRegistryActionFor:` |
| Its own window | `bin/gt-llm open-chat` — an inspector on a `GtLChat` |

**Both of the first two are decided once, while the image boots, and never
asked again.** Each asks `GtLConnectionRegistry instance
hasConnectableDefaultConnection`, and each asks it before `mc-bootstrap.st`
has registered the OpenAI-compatible connector. So a GT that is perfectly well
connected still shows the "Setup LLM connections" placeholder and no toolbar
dropdown — the answer was cached from a moment when it was honestly false.

`McGtPatches refreshHome` re-renders both from their stencils, and `apply`
calls it, so a normal start now comes up correct. On demand:

```bash
bin/gt-llm home         # 1 main window(s) refreshed
```

The pane it draws is `GtLChatRegistryElement` — an *index* of chats, with a `+`
that adds one. Clicking a row opens that chat, because `GtWorldElement`
catches `GtPhlowObjectToSpawn`. That is why the same element in a bare
`BlSpace` looks inert: the row spawns an event with nothing to catch it.

### Customizing the three panes

The panes are methods, found by pragma, ordered by `priority:`:

```
GtHome >> ...                              <gtHomeSection>   -- a section
GtHomeMultiCardGetStartedSection >> ...    <gtSectionCard>   -- a card in it
```

Every pane you see is a card in the one section:

| Card | Title | priority |
|------|-------|----------|
| `gtUsedKnowledgeBaseCard` | Local knowledge base | 1 |
| `gtBookCard` | Glamorous Toolkit Book | 10 |
| `gtLlmCard` | the chat, or the placeholder | 50 |

So: add a pane by adding a `<gtSectionCard>` method returning a `GtHomeCard`;
remove one by commenting out its pragma (which is exactly what upstream does
to `GtHome >> toolsSection` and `gt4llmSection`); reorder by changing
`priority:`. Then `bin/gt-llm home` to see it without restarting.

## From Emacs

`elisp/mc-llm.el` drives all of the above over the bus:

```elisp
(require 'mc-llm)
(mc-llm-install-keys)   ; C-c g c / C-c g n / C-c g h / C-c g s
```

| Key | Command | Effect |
|-----|---------|--------|
| `C-c g h` | `mc-llm-refresh-home` | re-render the main window |
| `C-c g c` | `mc-llm-chat` | chat in its own window, reusing the last |
| `C-c g n` | `mc-llm-new-chat` | chat in its own window, fresh history |
| `C-c g s` | `mc-llm-status` | connections report in a buffer |
| `C-c g w` | `mc-llm-switch` | re-point the chat on screen |
| `C-c g d` | `mc-llm-use` | set the default for new chats |
| `C-c g o` | `mc-llm-new-chat-on` | new chat on a named connection |
| `C-c g l` | `mc-llm-chats` | every chat and its server |

The three that take a connection complete over what GT currently offers, read
live off the bus — no list to keep in sync.

`mc-llm--eval` underneath is `gt.cmd.eval`, so anything `bin/gt-eval` can do,
Emacs can do:

```elisp
(mc-llm--eval "GtLConnectionRegistry instance connections size printString")
```

`emacs-work.org` is the scratch buffer for all of it.

### Why streaming used to flicker

Sampling the live window during a response found the text editor **missing in
about a quarter of the samples**, with a different editor object almost every
time. The box was being emptied and rebuilt, not appended to.

Two causes, one ours and one GT's.

Ours: `publishPreview:` built a **new** assistant message every 80 ms and
handed it to `addAssistantMessage:`, which sets `finalMessage:` on the reply —
stamping it finished each time, incidentally. It now reuses one message object
for the whole response and refreshes it in place, so `finalMessage:` sees what
it already holds and returns early. Previews are also published at 250 ms
rather than 80 ms: GT coalesces redraws through a `BrElementUpdater` postponed
by 300 ms, so anything faster was collapsed and thrown away — one measured
response published 512 previews and got 157 rebuilds. The 355 wasted ones were
not free either, because `snapshotOf:` re-serializes the whole response so far.

GT's: `GtLMessageViewsElement >> onViewsReady:` does

```smalltalk
self removeChildNamed: #'message-tabs'.
anElementOrNil ifNil: [ ^ self ].
self addChild: anElementOrNil as: #'message-tabs'
```

and the replacement's content arrives through an async widget, so there is a
real window with nothing in the box. `McGtPatches patchStreamingViewSwap` pins
the element's height across the swap and restores `vFitContentLimited` on the
next frame. The rebuild still happens — it stops being visible as a collapse.
After the patch the box held its height through the swaps and the editor was
missing in 2 samples of 20 rather than 5 of 22.

Removing the rebuild altogether would mean updating the existing editor's text
instead of recollecting the view, which is a larger change to GT's view layer.

## Swapping markdown blocks for components

`pharo/McRichText.st` is a demonstration, not part of the bus. It answers
whether a message's text can be parsed, have its blocks replaced by live
components, and still be the same text underneath.

```
bin/gt-eval '(Smalltalk at: #McRichText) proveRoundTrip'
bin/gt-eval '(Smalltalk at: #McRichText) open'
```

`open` puts two renderings of one document side by side: `#asChat`, which is
what the chat does today, and `#asComponents`, which renders the table as a
grid and the list as checkboxes.

It works because in Bloc a component is not a replacement for text — it is an
**attribute over** text. The string is never consumed, so the backward
direction needs no conversion at all:

```
source: 250 characters, 5 blocks
  chars 1-19    header    -> MicHeaderBlock
  chars 22-62   paragraph -> MicParagraphBlock
  chars 65-164  table     -> MicTableBlock
  chars 167-218 list      -> MicUnorderedListBlock
  chars 221-249 code      -> MicCodeBlock

asComponents:
  components built: #('BrVerticalPane' 'BrVerticalPane' 'GtSourceCoderExpandedOnlyElement')
  source characters replaced by a component: 181 of 250
  text asString still equals the source: true
```

A styler is a one-argument block over the text (`BlPluggableStyler`), and a
view takes one with `styler:`. So a component set is swappable by passing a
different styler — nothing else in the view changes. Blocks are located by
source interval, which is what lets a component know exactly which characters
it stands for, and lets an edit be written back into those characters.

Parsing is `MicrodownParser`, not the `LeParser` the chat uses, which is why
tables and lists parse at all. Microdown also covers quotes, strikethrough,
figures and math.

## Evaluating code in a document

Rich Edit understands Quarto's language-labeled inline code and Org Babel's
evaluation semantics.

```
The calculated radius is `{python} 5 * 2` meters.
The statistical mean is `{r} mean(c(10, 20, 30))`.
This image is `{smalltalk} Smalltalk version`.
``{python} len("`backticks`")``
```

The label names a **language**, not an execution context. That matters because
the same label is what a syntax highlighter will key on later, and because it
lets `python` gain a session evaluator one day without anything in a document
having to be renamed. The fence width is data, not a constant, which is why the
double-backtick form above can quote backticks of its own.

`smalltalk` (alias `gt`) is evaluated by **this image**, on the calling
process. That is the same relationship org-babel has with `emacs-lisp`, and it
is not new capability: `McGtService` already answers `gt.cmd.eval` with
`Smalltalk compiler evaluate:`, and the Emacs REPL in `emacs-work.md` is a
front end to it. The editor runs inside GT, so it reaches the same evaluation
without the bus.

Everything else is a one-shot subprocess per expression: `python3 -c`,
`Rscript -e`, `julia -e`, capped by `timeout` when it is on `PATH`. Interpreters
are located by searching `PATH` and then the places a per-user package manager
puts things, because a windowed GT inherits almost no `PATH` -- the same reason
`McTerminal` has to go looking for tmux. An interpreter you do not have renders
as a visible `no interpreter for julia`, not as a broken document. `ojs` parses
and tags but never evaluates: Observable JS is a browser dataflow runtime, and
there is nothing to shell out to.

### Trust

**Nothing evaluates until you tick `Trust`**, the labelled checkbox beside
`Dark Mode`. It is per document and lives in memory for the image's lifetime;
there is deliberately no trust store on disk, because a file asserting that
some document is trustworthy is one that goes stale, gets copied between
machines, and can be edited by the thing it gates.

| | untrusted (default) | trusted |
|---|---|---|
| `` `{python} 5 * 2` `` | tagged source, nothing runs | evaluates, renders the result |
| ` ```python ` block | no Run button at all | a permanent Run button |

This matters because the editor follows links and wiki-links into documents you
never chose to open.

### Fenced blocks

A block never evaluates by being rendered, trusted or not -- only its **Run**
button does, which is Org Babel's rule. The button is permanent: it survives
success and failure alike.

On success the result is written **into the document**, as real markdown:

    ```results{2026-09-06T14:22:01.123Z}
    12.0
    ```

So it outlives the session, and any other markdown tool shows it as a code
block with an unfamiliar language. The timestamp is there because a result with
no timestamp cannot be told apart from one that stopped being true some time
ago. Re-running replaces that fence rather than adding a second one, and a
failed run removes a fence left by an earlier success -- a stale result must
not outlive the code that produced it. A failure writes nothing; its message
appears beside the button.

### Re-running

Results are cached, bounded and least-recently-used, and they **never
invalidate themselves** -- `{smalltalk} McKdiStore session label` reads live
image state, and a subprocess may read a file that has since changed. So
re-running is explicit:

- `Cmd-Shift-E` drops the cached result for whatever the cursor is in.
- Hovering a rendered expression shows its source, when it was evaluated, and
  that binding. The tooltip exists precisely because a cache with no visible
  way to clear it is a bug waiting to be reported.

### What this cannot do

A subprocess is capped by `timeout`. **In-image Smalltalk is not and cannot
be**: `{smalltalk} [ true ] whileTrue` freezes the editor. That is the same
bargain Org Babel makes with elisp, and the trust checkbox is the only thing
standing in front of it.

There are no persistent sessions, so an inline expression cannot see variables
defined in a fenced block above it. That keeps the cache honest: a result is a
pure function of the language and the expression, which is what makes it safe
to reuse at all.

## Streaming responses

GT never streams. `GtLOpenAiResponsesEndpoint` hardcodes `'stream' -> false`,
posts with a `ZnClient` that reads the whole body, and only then builds the
assistant message — so the chat sits frozen until the model is completely done.

```bash
bin/gt-llm streaming on     # takes effect on the next message
bin/gt-llm streaming off
bin/gt-llm streaming status
```

With it on, text appears as it arrives and the chat's existing **stop button
ends a response mid-flight, keeping the text that already came through**.

`pharo/McLlmStream.st` does this **without patching GT**, which three facts make
possible:

- `GtLEndpoint >> additionalEntity` is an official hook, merged into the request
  *last*, so `'stream' -> true` overrides the hardcoded `false`.
- The SSE stream ends with a `response.completed` event carrying the complete
  response object, identical in shape to the non-streaming reply. Handing that
  to `resultFrom:context:` leaves message construction, tool calls and
  compaction running exactly as before.
- `GtLChat >> addAssistantMessage:` sets `finalMessage:` on the reply message —
  a *slot*, not an append. A partial message can be published over and over as
  text arrives, and the real one simply replaces it at the end.

Partial messages are published on an 80 ms clock rather than per token, because
tokens arrive faster than anyone reads and every publish costs a re-render. Any
failure in the streaming path falls back to the blocking one, minus the flag
that failed, so a chat still gets its answer.

`McLlmStream report` prints what the last run did — event count, previews
published, why the read loop ended — since a stream is otherwise hard to observe
from outside.

One known wrinkle: publishing a partial sets `finalMessage`, so
`GtLChat >> isFinishedSuccesss` reads true from the first partial onward. Nothing
in the chat UI uses it — the stop button keys off the provider's execution state,
which stays live — but a chat-list view that asks may show a run as finished
early.

## macOS and emacs keys in GT editors

GT's text inputs are `BrEditor` — `BrEditor < BrEditorElement < BlInfiniteElement
< BlElement`, pure Bloc, drawn by GT. They are not `NSTextView`, so they inherit
nothing from macOS's text system, which is where Alt-Backspace and the emacs
bindings come from in every native field.

```bash
bin/gt-llm keys show        # every editor binding, as resolved for macOS
bin/gt-llm keys emacs on
bin/gt-llm keys emacs off
```

`McGtPatches patchMacOsEditorKeymap` is applied always, and is a bug fix rather
than a preference. `BrEditorKeymapRegistry` registers cursor motion and
selection with macOS variants — move-to-previous-word is `Ctrl+ArrowLeft`
generally and `Alt+ArrowLeft` on macOS — but registers word *deletion* with no
macOS variant at all, leaving delete-previous-word on `Cmd+Backspace`, which on
macOS means "delete to start of line". The operations existed; only the bindings
were missing. Added, not replaced:

```
deletePreviousWordShortcutId  ->  Cmd+Backspace | Alt+Backspace
deleteNextWordShortcutId      ->  Cmd+Delete | Alt+Delete
```

`keys emacs on` adds `Ctrl+A/E/F/B/N/P/D` and `Alt+F`/`Alt+B` alongside the
existing bindings, and is remembered in `run/emacs-editor-keys`. `Ctrl+K`,
`Ctrl+W`, `Ctrl+Y` and `Ctrl+Space` are deliberately absent: Brick has no
kill-to-end-of-line, no kill ring and no mark, so those need *writing*, not
binding.

Both take effect immediately in editors that are already open — `BrEditorShortcut`
resolves its combination from the registry at dispatch, not at construction. And
both are global to the image: every GT editor, not just the chat input.

## Known gaps

- **Presence is graceful-only.** Core NATS has no last-will, so
  `system.event.client.disconnected` fires on a clean shutdown and never for a
  crash — a dead participant just goes quiet. Real presence needs heartbeats or
  JetStream; deferred on purpose.
- **No auth or ACLs.** Localhost listener, single-user workstation, as
  designed for this phase. `*.cmd.eval` is an escape hatch, not the protocol.
- **`bin/emacs-participant` runs `-Q`.** A large personal config makes the
  participant slow and non-deterministic, and can block daemon startup on an
  interactive prompt. Set `MC_EMACS_FULL_INIT=1` to override.
