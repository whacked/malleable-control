# NATS-Based Local Process Bus for GT, Emacs, and Terminal

## 1. Purpose

This document defines a baseline architecture for a local heterogeneous process communication system built around **Core NATS**.

The target environment is macOS, with the initial participants:

- **Glamorous Toolkit / Pharo**
  - bidirectional participant
  - publishes commands and events
  - issues queries
  - serves commands and queries from other clients
- **Emacs**
  - bidirectional participant
  - primarily exposes editor capabilities
  - publishes editor state/events
  - may issue queries or commands to other participants
- **Terminal / shell**
  - primarily a controller interface
  - typically publishes commands or issues one-shot requests
  - not expected to maintain substantial state

The design goal is a **small, mature, local message kernel** that lets heterogeneous processes communicate without introducing an HTTP server, a central `eval` loop, or tight coupling between peers.

---

## 2. Core Design Decision

Use **Core NATS** as the local message bus.

The architectural model is:

```text
                    +----------------+
                    |  nats-server   |
                    | localhost:4222 |
                    +-------+--------+
                            |
             +--------------+--------------+
             |              |              |
             v              v              v
          Emacs             GT          Terminal
        pub/sub          pub/sub        mostly pub
        req/reply        req/reply      occasional req
```

The NATS server acts as an **interest-based routing kernel**.

Clients:

- connect persistently where appropriate;
- subscribe only to subjects they understand;
- publish commands or events without knowing which consumers exist;
- use request/reply when a response is required.

This avoids making any one client the mandatory communication hub.

---

## 3. Why NATS

NATS is preferred over several plausible alternatives.

### 3.1 Versus HTTP

HTTP encourages endpoint-centric RPC and request/response semantics.

The desired system needs:

- asynchronous events;
- bidirectional communication;
- fanout;
- request/reply;
- decoupled publishers and subscribers;
- lightweight persistent client connections.

NATS provides these directly.

### 3.2 Versus D-Bus

D-Bus is a strong fit for Linux desktop IPC, but the target environment is macOS.

Using D-Bus on macOS would add ecosystem friction without providing a decisive advantage for:

- Emacs Lisp;
- Pharo;
- shell tools;
- arbitrary future languages.

### 3.3 Versus Apple XPC

XPC is native to macOS but is strongly coupled to Apple frameworks and process models.

It is not an ideal lingua franca for heterogeneous runtimes such as:

- Pharo;
- Emacs;
- shell clients;
- future non-Apple runtimes.

### 3.4 Versus ZeroMQ

ZeroMQ provides communication primitives but not the full bus abstraction.

Using ZeroMQ would require designing more of:

- routing;
- discovery;
- request/reply conventions;
- subscription semantics;
- reconnect behavior;
- fanout;
- wildcard addressing.

NATS already provides these.

### 3.5 Versus MQTT

MQTT is mature and viable, but its center of gravity is device/event telemetry.

NATS is a better semantic fit for a programmable process fabric because request/reply, services, and dynamic process communication are first-class patterns.

---

## 4. Architectural Principle

The primary API surface should be the **subject namespace**, not a universal `eval` endpoint.

Example subjects:

```text
emacs.cmd.buffer.open
emacs.cmd.buffer.close
emacs.cmd.point.set

emacs.query.selection
emacs.query.buffer.contents
emacs.query.point

emacs.event.buffer.opened
emacs.event.buffer.closed
emacs.event.selection.changed

gt.cmd.inspect
gt.cmd.coder.open

gt.query.object
gt.query.selection

gt.event.inspector.opened
gt.event.selection.changed

system.event.client.connected
system.event.client.disconnected
system.query.capabilities
```

A client subscribes only to the operations it understands.

If Emacs subscribes to:

```text
emacs.cmd.buffer.open
emacs.query.selection
```

but does not subscribe to:

```text
emacs.cmd.make.sandwich
```

then that unsupported message is simply not delivered to Emacs.

The bus therefore performs part of the capability filtering.

---

## 5. Message Categories

Use three conceptual categories.

### 5.1 Commands

Commands request a state change.

Examples:

```text
emacs.cmd.buffer.open
emacs.cmd.point.set
gt.cmd.inspect
gt.cmd.coder.open
```

Typical transport:

```text
PUB
```

Commands may optionally use request/reply when acknowledgement or a result is important.

---

### 5.2 Queries

Queries request information.

Examples:

```text
emacs.query.selection
emacs.query.buffer.contents
gt.query.object
```

Typical transport:

```text
REQ -> response
```

Queries should normally be side-effect free.

---

### 5.3 Events

Events announce state changes or occurrences.

Examples:

```text
emacs.event.selection.changed
emacs.event.buffer.opened
gt.event.inspector.opened
system.event.client.connected
```

Typical transport:

```text
PUB
```

Events may have zero, one, or many subscribers.

---

## 6. Client Roles

## 6.1 Emacs

Emacs is a persistent bus participant.

It should:

- maintain a NATS connection;
- subscribe to editor-related command and query subjects;
- publish editor state events;
- optionally issue queries and commands to GT or other clients.

Initial capabilities may include:

```text
emacs.cmd.buffer.open
emacs.cmd.buffer.close
emacs.cmd.point.set
emacs.cmd.selection.set
emacs.cmd.command.execute

emacs.query.buffer.current
emacs.query.buffer.contents
emacs.query.point
emacs.query.selection
emacs.query.file.current

emacs.event.buffer.opened
emacs.event.buffer.closed
emacs.event.buffer.changed
emacs.event.point.changed
emacs.event.selection.changed
```

An `emacs.eval` capability may exist, but it should be considered an escape hatch rather than the core protocol.

---

## 6.2 Glamorous Toolkit / Pharo

GT is also a persistent bidirectional participant.

It should:

- maintain a NATS connection;
- expose GT-specific capabilities;
- publish state and UI events;
- issue commands and queries to Emacs;
- optionally act as an inspection or orchestration environment for the broader system.

Potential initial subjects:

```text
gt.cmd.inspect
gt.cmd.coder.open
gt.cmd.object.send

gt.query.object
gt.query.selection
gt.query.inspector.current

gt.event.selection.changed
gt.event.inspector.opened
gt.event.inspector.closed
```

As with Emacs, a `gt.eval` endpoint may exist for debugging or escape-hatch usage, but should not become the main abstraction.

---

## 6.3 Terminal / Shell

The terminal is primarily a control surface.

Its expected usage is one-shot publication or request/reply through the NATS CLI.

Examples:

```bash
nats pub emacs.cmd.buffer.open \
  '{"path":"/tmp/foo.el"}'
```

```bash
nats req emacs.query.selection '{}'
```

```bash
nats pub gt.cmd.inspect \
  '{"object_id":"..."}'
```

```bash
nats sub 'system.event.>'
```

The terminal does not need a persistent custom daemon initially.

---

## 7. Payload Format

Start with **JSON**.

Do not introduce protobuf, MessagePack, Cap'n Proto, or a custom binary schema until there is a demonstrated need.

Example:

Subject:

```text
emacs.cmd.buffer.open
```

Payload:

```json
{
  "path": "/Users/example/project/foo.el",
  "line": 37,
  "column": 4
}
```

Recommended minimal envelope:

```json
{
  "v": 1,
  "args": {
    "path": "/Users/example/project/foo.el",
    "line": 37,
    "column": 4
  }
}
```

The version field allows protocol evolution.

For trivial operations, the envelope may be omitted initially if simplicity is preferred.

---

## 8. Subject Naming Convention

Recommended general form:

```text
<owner>.<kind>.<resource>.<operation>
```

Where:

```text
owner:
  emacs
  gt
  system
  future clients

kind:
  cmd
  query
  event
```

Examples:

```text
emacs.cmd.buffer.open
emacs.query.selection
emacs.event.buffer.changed

gt.cmd.inspect
gt.query.object
gt.event.selection.changed
```

Avoid overly deep subject trees unless they add useful wildcarding semantics.

---

## 9. Wildcard Subscription Strategy

NATS wildcard subjects are useful for broad capability families.

Examples:

```text
emacs.cmd.>
emacs.query.>
emacs.event.>

gt.cmd.>
gt.query.>
gt.event.>

system.event.>
```

However, clients should not blindly subscribe to broad namespaces unless they internally dispatch safely.

Where practical, subscribe to specific implemented subjects.

This preserves the desirable property:

> a client only receives message types it understands.

---

## 10. Request/Reply Semantics

Use NATS request/reply for operations requiring a response.

Example:

```text
REQ emacs.query.selection
```

Response:

```json
{
  "buffer": "foo.el",
  "start": 127,
  "end": 184,
  "text": "(message \"hello\")"
}
```

Recommended response shape:

```json
{
  "ok": true,
  "result": {
    "buffer": "foo.el",
    "start": 127,
    "end": 184,
    "text": "(message \"hello\")"
  }
}
```

Errors:

```json
{
  "ok": false,
  "error": {
    "code": "no-active-buffer",
    "message": "No current buffer is available."
  }
}
```

---

## 11. Capability Discovery

Do not require a large registry initially.

A minimal convention is enough.

Each persistent client may expose:

```text
<client>.query.capabilities
```

Example:

```text
emacs.query.capabilities
```

Response:

```json
{
  "commands": [
    "emacs.cmd.buffer.open",
    "emacs.cmd.point.set"
  ],
  "queries": [
    "emacs.query.selection",
    "emacs.query.buffer.contents"
  ],
  "events": [
    "emacs.event.selection.changed"
  ]
}
```

A broader system-level discovery mechanism can be added later if needed.

---

## 12. Eval as an Escape Hatch

Arbitrary evaluation is useful but should not be the architectural foundation.

Possible subjects:

```text
emacs.cmd.eval
gt.cmd.eval
```

Use cases:

- debugging;
- experimental operations;
- bootstrapping new capabilities;
- developer-only workflows.

Production interactions should prefer semantic operations such as:

```text
emacs.cmd.buffer.open
```

over:

```text
emacs.cmd.eval
```

with a payload containing Lisp source.

This keeps the protocol inspectable, versionable, and easier to secure.

---

## 13. Reliability Model

Start with **Core NATS only**.

Core NATS provides ephemeral messaging.

Implication:

- if no subscriber is present when a message is published, the message is not retained.

This is appropriate for interactive commands such as:

```text
open buffer
move point
inspect object
what is selected?
```

Do not add persistence until a concrete use case requires it.

Potential future persistent use cases:

```text
task history
event history
offline work queues
audit logs
state replication
```

At that point, introduce **JetStream** selectively.

Do not make JetStream a baseline dependency.

---

## 14. Process Lifecycle

Recommended local deployment:

```text
launchd
  |
  +-- nats-server
```

NATS should run as a local macOS user service.

Clients may connect to:

```text
nats://127.0.0.1:4222
```

Initial deployment should be localhost-only.

No network exposure is required.

---

## 15. Security Baseline

Initial assumptions:

- single-user workstation;
- localhost-only NATS listener;
- no externally reachable port;
- no untrusted local clients.

Even under these assumptions, arbitrary `eval` subjects should be treated separately from ordinary semantic capabilities.

Future hardening may include:

- NATS authentication;
- per-client credentials;
- subject-level permissions;
- separate privileged and unprivileged subject namespaces;
- TLS if non-local transport is introduced.

Example permission model:

```text
terminal:
  publish:
    emacs.cmd.*
    gt.cmd.*
  request:
    emacs.query.*
    gt.query.*

emacs:
  subscribe:
    emacs.cmd.*
    emacs.query.*
  publish:
    emacs.event.*

gt:
  subscribe:
    gt.cmd.*
    gt.query.*
  publish:
    gt.event.*
```

Exact ACLs can be added after the namespace stabilizes.

---

## 16. Emacs Implementation Strategy

Avoid adding an unnecessary native dependency if possible.

A minimal Emacs client can be implemented directly in Elisp using:

```text
make-network-process
process filters
process sentinels
buffered framing state
```

The Core NATS client protocol is small enough that a direct implementation is plausible.

Minimum operations required:

```text
CONNECT
SUB
UNSUB
PUB
PING
PONG
MSG parsing
```

Request/reply can be implemented using generated inbox subjects.

A native Elisp adapter should expose a higher-level API such as:

```text
nats-publish
nats-request
nats-subscribe
nats-unsubscribe
```

Application-facing Emacs code should not depend directly on wire protocol details.

---

## 17. GT / Pharo Implementation Strategy

GT may likewise use either:

1. an existing NATS client library, if mature enough; or
2. a small native Pharo implementation of the Core NATS protocol.

The same minimal API should exist:

```text
publish(subject, payload)
request(subject, payload)
subscribe(subject, handler)
unsubscribe(subscription)
```

The GT layer should then map subjects to native domain operations.

---

## 18. Terminal Interface

Use the official `nats` CLI initially.

Examples:

### Send command

```bash
nats pub emacs.cmd.buffer.open \
  '{"path":"/tmp/foo.el"}'
```

### Issue query

```bash
nats req emacs.query.selection '{}'
```

### Observe events

```bash
nats sub 'emacs.event.>'
```

### Send GT command

```bash
nats pub gt.cmd.inspect \
  '{"object_id":"abc123"}'
```

This provides an immediately usable controller interface before any custom CLI exists.

---

## 19. Recommended Initial Subject Set

Keep the initial protocol deliberately small.

### Emacs

```text
emacs.cmd.buffer.open
emacs.cmd.point.set
emacs.cmd.command.execute

emacs.query.buffer.current
emacs.query.buffer.contents
emacs.query.point
emacs.query.selection
emacs.query.capabilities

emacs.event.buffer.opened
emacs.event.buffer.changed
emacs.event.selection.changed
```

### GT

```text
gt.cmd.inspect
gt.cmd.coder.open

gt.query.selection
gt.query.capabilities

gt.event.selection.changed
gt.event.inspector.opened
```

### System

```text
system.event.client.connected
system.event.client.disconnected
```

Do not attempt to model every possible operation before working code exists.

---

## 20. Development Phases

### Phase 1 — Bus Bootstrap

Deliver:

- local `nats-server`;
- `nats` CLI;
- launchd configuration;
- basic manual pub/sub validation.

Success criterion:

```text
terminal A publishes -> terminal B receives
```

---

### Phase 2 — Emacs Adapter

Deliver:

- persistent connection;
- publish;
- subscribe;
- request;
- reply;
- reconnect handling;
- JSON encoding/decoding.

Expose at least:

```text
emacs.cmd.buffer.open
emacs.query.selection
```

Success criterion:

```text
terminal -> NATS -> Emacs
terminal <- NATS <- Emacs response
```

---

### Phase 3 — GT Adapter

Deliver equivalent NATS primitives in Pharo.

Expose at least:

```text
gt.cmd.inspect
gt.query.capabilities
```

Success criterion:

```text
terminal -> GT
GT -> Emacs
Emacs -> GT
```

---

### Phase 4 — Shared Protocol Conventions

Standardize:

- subject naming;
- JSON envelopes;
- response format;
- error format;
- versioning;
- capability discovery.

Do this only after the first cross-process workflows work.

---

### Phase 5 — Event Integration

Add useful live state events.

Examples:

```text
emacs.event.selection.changed
gt.event.selection.changed
```

This enables loosely coupled reactive workflows.

---

### Phase 6 — Security and Persistence

Only when required, add:

- subject ACLs;
- authentication;
- JetStream;
- audit/event persistence;
- remote networking.

---

## 21. Non-Goals for the Initial System

The initial implementation should not attempt to solve:

- distributed object identity;
- transparent remote objects;
- schema registries;
- exactly-once delivery;
- durable queues;
- global transaction semantics;
- arbitrary binary streaming;
- distributed consensus;
- generic remote filesystem access;
- a universal object model across GT and Emacs.

These may be layered on later if concrete use cases justify them.

---

## 22. Key Architectural Rules

1. **NATS is the bus, not the application model.**
2. **Subjects carry semantic meaning.**
3. **Clients subscribe only to operations they support.**
4. **Commands, queries, and events are conceptually distinct.**
5. **Use JSON first.**
6. **Use Core NATS first.**
7. **Keep `eval` as an escape hatch.**
8. **Do not make Emacs or GT the mandatory router.**
9. **Prefer semantic capabilities over source-code execution.**
10. **Add persistence, schemas, ACLs, and richer object semantics only when real use cases demand them.**

---

## 23. Target End State

The desired system should behave like this:

```text
                    LOCAL PROCESS FABRIC
                           NATS
                            |
          +-----------------+-----------------+
          |                 |                 |
        Emacs               GT             Terminal
          |                 |                 |
    editor service    inspection/UI       controller
    event source      event source         scripting
    query target      query target
    command target    command target
          |                 |
          +-------- bidirectional ----------+
```

Example flow:

```text
Terminal:
    PUB emacs.cmd.buffer.open

Emacs:
    receives command
    opens file
    PUB emacs.event.buffer.opened

GT:
    receives event
    REQ emacs.query.buffer.contents

Emacs:
    replies with buffer contents

GT:
    visualizes or inspects resulting state
```

The resulting architecture is a small, local, language-neutral message fabric with minimal coupling between participants and enough structure to evolve into a broader programmable environment.
