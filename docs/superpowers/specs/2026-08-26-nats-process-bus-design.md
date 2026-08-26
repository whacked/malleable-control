# Spec: NATS Local Process Bus — Phase 1 (Interop Proof)

Date: 2026-08-26
Status: approved, implementing
Parent design: [`docs/nats_local_process_bus_design.md`](../../nats_local_process_bus_design.md)

## 1. Scope

This spec covers what the parent design calls **Phases 1–3**, collapsed into a
single deliverable:

| Parent phase | Deliverable | Success criterion |
|---|---|---|
| 1 — Bus bootstrap | local `nats-server`, `nats` CLI | terminal A publishes, terminal B receives |
| 2 — Emacs adapter | native Elisp NATS client + `emacs.*` services | terminal to Emacs and back |
| 3 — GT adapter | native Pharo NATS client + `gt.*` services | terminal to GT, GT to Emacs, Emacs to GT |

The combined success criterion is a **full mesh**: every participant can
publish, subscribe, serve a request, and issue a request.

Out of scope for this spec: JetStream, ACLs, authentication, launchd
supervision as the default, the full §19 subject set, presence detection for
crashed participants.

## 2. Decisions taken

Three decisions were made before implementation:

1. **Native protocol clients, no sidecars.** Core NATS is a line-based text
   protocol. Emacs implements it over `make-network-process`; Pharo implements
   it over `Socket`. No bridge processes to supervise. Follows parent §16, §17.
2. **Full mesh proof, not fan-out.** A participant that cannot answer a
   question is not a control plane.
3. **GT connects at launch via its own startup hook.** Verified present and
   enabled in the installed image (`StartupPreferencesLoader allowStartupScript`
   is `true`, image-local script name is `startup.st`).

## 3. Verified environment facts

Established by probe before writing this spec, not assumed:

| Fact | Value |
|---|---|
| GT install | `/Applications/GlamorousToolkit-MacOS-aarch64-v1.1.564` |
| Headless runner | `GlamorousToolkit.app/Contents/MacOS/GlamorousToolkit-cli <image> eval <expr>` |
| Headless keep-alive | `--no-quit` flag exists |
| Startup hook (used) | any `*.st` in `~/Library/Preferences/pharo/12.0/`; enabled by default |
| Startup hook (rejected) | image-local `startup.st` — resolved against `FileSystem workingDirectory`, which is `/` on a Finder launch, so it silently never runs |
| Emacs daemon socket | `$TMPDIR/emacs<uid>/<name>`; `--daemon=<abs path>` hits a name-length cap, and macOS `/tmp` is rejected as a symlink |
| Image classes present | `Socket`, `NeoJSONObject`, `ZnServer`, `StartupPreferencesLoader` |
| Code loading | Pharo **chunk format** via `fileIn` — verified working |
| Emacs | 30.2, with built-in `json-parse-string` / `json-serialize` |
| Nix packages | `nats-server-2.14.5`, `natscli-0.4.0` |

**Consequence of chunk-format loading:** a class created by `fileIn` cannot be
referenced by name in the same compiled expression — the reference is resolved
at compile time, before the class exists. All bootstrap code must reach classes
late, via `Smalltalk at: #Name`.

## 4. Architecture

Five units, split on the wire-protocol / semantics line so that phase 2 can
change the subject namespace without touching protocol code.

| Unit | Responsibility | Depends on |
|---|---|---|
| `nats/nats-server.conf`, `bin/bus-*` | Run a localhost-only server on port 4223 with pid and log files | nats-server |
| `elisp/nats-client.el` | Core NATS wire protocol. CONNECT, SUB, UNSUB, PUB, MSG, PING, PONG, inbox request-reply, reconnect. Knows nothing about subjects or JSON. | none |
| `elisp/mc-emacs-service.el` | Maps `emacs.*` subjects to editor operations; publishes `emacs.event.*` | `nats-client.el` |
| `pharo/NatsClient.st` | Same wire protocol in Pharo; same four-verb API | none |
| `pharo/McGtService.st` | Maps `gt.*` subjects to GT operations; display-aware | `NatsClient.st` |

Port **4223**, not the default 4222, so this bus never collides with an
unrelated NATS instance.

## 5. Wire contract

Per parent §7 and §10, with one addition.

```
request   {"v":1,"args":{...}}
reply ok  {"v":1,"ok":true,"result":{...}}
reply err {"v":1,"ok":false,"error":{"code":"...","message":"..."}}
event     {"v":1,"source":"emacs","ts":<unix-ms>,"data":{...}}
```

**Addition to the parent design:** events carry `source` and `ts`. The parent
leaves the event envelope unspecified; both fields become necessary the moment
two participants emit the same event name, which parent §19 already schedules
(`emacs.event.selection.changed` and `gt.event.selection.changed`).

## 6. Phase-1 subject set

Deliberately thin, per parent §19.

```
emacs.query.capabilities          gt.query.capabilities
emacs.query.buffer.current        gt.query.image.info
emacs.query.buffer.contents       gt.cmd.inspect
emacs.cmd.buffer.open             gt.cmd.eval
emacs.cmd.eval                    gt.event.inspector.opened
emacs.event.buffer.opened

system.event.client.connected
system.event.client.disconnected
```

`*.cmd.eval` is the escape hatch of parent §12, present for bootstrapping and
labelled as such. It is not the protocol.

`gt.cmd.inspect` is the display-agnostic case. With a UI it opens a GT
inspector and emits `gt.event.inspector.opened`. Headless it returns the same
result payload with `"headless":true` and skips the UI. Same subject, same
contract, one conditional.

## 7. Known gap: presence

Core NATS has no last-will. `system.event.client.disconnected` fires only on
graceful shutdown; a crashed participant simply goes silent. Real presence
detection needs heartbeats or JetStream and is deferred. This is documented
rather than worked around.

## 8. The headline proof

Parent §23's example flow, run end to end:

```
terminal  PUB emacs.cmd.buffer.open
  Emacs   opens file, PUB emacs.event.buffer.opened
  GT      subscribed to emacs.event.>, REQ emacs.query.buffer.contents
  Emacs   replies with contents
  GT      PUB gt.event.inspector.opened
terminal  SUB gt.event.> observes it
```

Three further round trips exercise the remaining mesh edges:

- terminal to GT: `nats req gt.query.capabilities`
- Emacs to GT: `M-x mc-demo-ask-gt`, which requests `gt.query.image.info`
- broadcast: a `system.event.*` message both participants log

## 9. Running it

- `bin/bus-start`, `bin/bus-stop`, `bin/bus-status` — server lifecycle.
- `bin/emacs-participant` — `emacs --daemon` with the service loaded. The same
  service loads into an existing Emacs with `(require 'mc-emacs-service)`.
- `bin/gt-install-startup` — generates and installs `startup.st` next to the GT
  image, with the repo path and bus URL baked in. **Opt-in and reversible**; it
  writes inside the GT install directory, so no demo or test script may call
  it implicitly. `bin/gt-uninstall-startup` removes it.
- After installing the startup hook, launching `GlamorousToolkit.app` normally
  brings up a connected participant. Headless is the same script plus
  `--no-quit`.
- `shell.nix` gains `pkgs.natscli`, which is currently missing — without it
  parent §18 cannot be run at all.
- A launchd plist (parent §14) ships as an optional artifact. The foreground
  dev runner is the phase-1 default.

## 10. Error handling

| Condition | Behaviour |
|---|---|
| Unknown subject | No subscriber, so no reply; requester times out. This is parent §4 capability filtering working correctly, and a demo script shows it deliberately. |
| Handler raises | Caught, replied as `ok:false` with an error code. Never kills the read loop. |
| Server down or restarted | Client retries with backoff, logs, and re-subscribes on reconnect. Must never wedge Emacs or GT. Handlers are registered **once**, not in the on-connect hook -- the client restores its own subscriptions, and re-registering there would double every subscription and every reply. |
| Handler needs user input | Fatal, by design. A participant has no user; a handler that reaches `y-or-n-p` blocks the process filter forever and silently deafens the whole client. Prompts are turned into error replies instead. |
| Request timeout | Default 5s, configurable. |

## 11. Testing

- **Protocol unit tests, no server required.** ERT for the Elisp MSG-framing
  parser, SUnit for the Pharo one. Framing is the likely break point: `MSG`
  carries a payload byte count, and Elisp process filters hand back strings, so
  the client must be unibyte end to end.
- **Integration.** `test/integration.sh` starts a server on its own port,
  starts both participants, drives the §8 flow, asserts on observed messages,
  and exits non-zero on failure.
- **Toy demos.** `demo/01`–`demo/05`, one concept each, for eyeballing.

## 12. Deliverables

`RUN.md` (install, start bus, start participants, run demos), the `demo/`
scripts, `test/integration.sh`, and this spec. Phase-1 deltas against the
parent design are recorded in §5 and §7 above.
