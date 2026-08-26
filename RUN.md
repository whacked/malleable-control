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

Everything below assumes you are inside that shell. Emacs 30+ and the GT app
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

Three things that look like breakage but are not:

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
pharo/NatsClient.st         Core NATS protocol for Pharo. Knows no subjects.
pharo/McGtService.st        gt.* subjects -> GT operations. Display-agnostic.
pharo/mc-bootstrap.st       Loads both into an image and connects.
nats/nats-server.conf       Localhost-only, port 4223.
bin/                        Lifecycle scripts.
demo/  test/                Proof.
```

The protocol/semantics split is deliberate: the subject namespace will churn in
later phases, and none of that should reach wire-protocol code.

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
