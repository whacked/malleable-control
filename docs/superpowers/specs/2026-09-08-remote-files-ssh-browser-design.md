# Remote Files — a Miller-column SSH file browser

**Date:** 2026-09-08
**Plugin:** `bb-plugins/bb-plugin-remote-files`, display name "Remote Files", icon `FolderTree`
**Status:** design approved, implementation not started

## Purpose

Browse a remote machine's filesystem from inside BB over nothing but SSH — no
FUSE mount, no SSHFS, no agent installed on the far side. The interaction model
is ranger, nnn, yazi, and mc: a strip of directory columns you walk into, with
the selection previewed in a pane on the right. Images preview as images.

The plugin is named "Remote Files" rather than anything containing "browser"
because `bb-plugin-browser` is the web browser and the sidebar should not offer
two things by that name.

## Constraints

1. **The remote host is left pristine.** Nothing is written to remote disk — not
   a helper script, not a temp file, not a cache. This is a hard constraint, and
   the design satisfies it by construction rather than by cleaning up after
   itself.
2. **SSH only.** No mount, no additional daemon, no port forwarding.
3. **Nothing machine-specific is committed.** The host and root directory are
   resolved at runtime, blank by default.
4. **Read-only.** v1 lists, traverses, and previews. It does not rename, delete,
   upload, or download.

## Architecture

Five units, each independently testable:

| Unit | File | Responsibility |
|---|---|---|
| Target parsing & config | `lib/target.ts` | `user@host:port` / alias → validated argv fragments; the four-tier config resolution |
| Transport | `lib/ssh.ts` | Multiplexed `ssh` invocation, capability probe, tier selection |
| Remote operations | `lib/remote.ts` + `lib/helper.py` | Listing, stat, head-read, resize — over both tiers |
| Cache | `lib/cache.ts` | Content-addressed blob store, size policy, LRU eviction |
| Surfaces | `server.ts`, `app.tsx` | RPC contract, HTTP byte routes, CLI, Miller-column UI |

### Configuration

Machine-specific values are resolved at runtime in the precedence order this
project already uses (see `bb-plugin-fitness-factory`), most specific first:

1. **Session override** — a field in the panel and `bb remote use`. Held in a
   plain variable in the plugin process, never persisted.
2. **Saved setting** — `sshTarget` and `rootDir` via `bb.settings.define`,
   stored by BB in `bb.db`, table `plugin_settings`.
3. **Environment** — `REMOTE_FILES_SSH_TARGET` and `REMOTE_FILES_ROOT_DIR`, read
   from the environment the bb server was started with.
4. **Unset** — a legible state, not an error. The panel says which of the three
   ways to set it are available and every read comes back empty.

`sshTarget` accepts `user@host:port`, `host:port`, `user@host`, or a bare
`~/.ssh/config` alias. The port is split out and passed as `-p`. The remainder
is validated against a strict character class before it can reach argv, the
guard `eda-accompanist-frontend` already uses:

```
/^[A-Za-z0-9][A-Za-z0-9._@-]*$/
```

Every SSH call is built as an argv array. No command is ever assembled as a
shell string on the local side.

### Transport

One `ssh` process per operation, made cheap by connection multiplexing:

```
-o ControlMaster=auto
-o ControlPath=<socket>
-o ControlPersist=300
-o BatchMode=yes
-o ConnectTimeout=10
-T
```

The first call performs a real handshake; subsequent calls reuse the master and
cost about 5ms. `ControlPersist=300` keeps the master for five idle minutes.

`BatchMode=yes` means authentication is by key or agent only. A host that would
prompt for a password fails immediately with a clear message instead of hanging
on a prompt nobody can see.

`-T` allocates no tty, so ssh does not mangle stdout. File bytes therefore cross
the wire raw, not base64 — a 33% saving. A byte-count mismatch against the
`stat` size triggers one retry through `base64`, which is the fallback rather
than the default.

**The control socket cannot live in the plugin directory.** Unix socket paths
are capped at 104 bytes on macOS and this checkout's path is already ~85. The
socket goes in `os.tmpdir()` as `bb-rf-<8 hex of target>`. It is an ephemeral
socket, not cached data, so this does not contradict the cache location below.

### Remote operations: two tiers

At Connect time a single round trip probes the far side and pins a tier for the
session.

**Tier A — interpreter helper.** `ssh <target> python3 -` with a small helper
delivered **on stdin**. It exists only in that process's memory and never
touches remote disk, which is what makes the zero-traces constraint structural
rather than a promise to clean up. It emits one JSON document per invocation and
handles listing, stat, head-read, and resize, so one round trip replaces three.

JSON per entry: `name`, `type` (`file` | `dir` | `link` | `other`), `size`,
`mtime`, `linkTarget`, `mode`. Being JSON, it is locale-independent and safe for
filenames containing spaces, newlines, or quotes.

**Tier B — shell fallback.** For hosts without `python3`. `find -maxdepth 1
-print0` plus per-entry `stat`, with the GNU/BSD `stat` flavor determined by the
probe. Tier B supports listing and raw file reads; it has no remote resize.

The probe reports, in one JSON line: `python3` presence and version, PIL
availability, ImageMagick (`magick` or `convert`), `vips`, and the `stat`
flavor.

### Path confinement

Every path is resolved **on the remote** to a realpath, and the realpath is
checked to be under the realpath of the configured root. Traversal is relative
to the start directory and `..` cannot escape it.

The check runs on the far side deliberately: that is where symlinks actually
resolve. Confining paths by local string manipulation would be defeated by a
symlink out of the root.

### Size policy

`stat` is always consulted before any transfer.

| Condition | Action |
|---|---|
| ≤ 2 MB | Transfer whole file, cache it |
| Image > 2 MB, remote resize available | `convert - -resize 2048x2048 -` on the remote; only the resized bytes cross the wire |
| Image > 2 MB, no remote resize | Transfer whole file, resize locally, cache original and derivative |
| Text > 2 MB | `head -c 262144` only; the preview says it is truncated |
| Anything else > 2 MB | Metadata only, no transfer |

Remote resizing is a pure pipe: bytes in on stdin, bytes out on stdout, nothing
written on the far side.

### Cache

The cache lives in the plugin's own directory, gitignored:

```
.cache/blobs/<aa>/<hash>          originals and remote-resized derivatives
.cache/thumbs/<aa>/<hash>-<w>     locally derived thumbnails
.cache/index.json                 the index
```

The index is a JSON file rather than SQLite. `bb.storage.database()` would
place it in bb's data directory and split cache state across two locations, and
bb externalizes `better-sqlite3` from the server bundle precisely because it
expects plugins to go through that API — a direct import loads under plain
`node` and fails under bb's own loader. Dropping the dependency keeps the whole
cache in one place and removes a native build from the plugin.

Key: `sha256(sshTarget + realpath + size + mtime)`. A changed remote file
produces a different key, so the cache misses rather than serving stale bytes —
there is no invalidation step to get wrong.

Eviction is LRU against a configurable total cap, default 1 GB, checked after
each insert.

### Serving bytes to the UI

Two routes via `bb.http.route(..., { auth: "local" })`, mounted under
`/api/v1/plugins/<id>/http/`:

- `GET /file?path=…` — streams a cached blob with its Content-Type and an ETag
  equal to the cache hash.
- `GET /thumb?path=…&w=…` — the same for a derived thumbnail.

Images in the preview pane are ordinary `<img src>` against these routes. Real
bytes, streamed from disk, cached by the browser, never base64 through the RPC
channel.

Listings and text previews travel over RPC as JSON.

### UI

A horizontally scrolling strip of Miller columns with draggable widths and a
breadcrumb, and a preview pane pinned to the right. Deeper columns stay
reachable by scrolling rather than being discarded.

The preview pane renders:

- **Images** — from the HTTP route, fit to the pane.
- **Text** — head-only, monospace, line numbers, with a truncation notice.
- **Directories** — the directory's own contents, one level ahead of the
  selection, as in ranger and yazi.

Keyboard: `h`/`j`/`k`/`l` and arrows, `h`/`←` ascends and `l`/`→` descends,
`gg` and `G` jump to ends, `/` filters the focused column.

The column strip and preview pane are adapted from the Library → Cell → View
layout already built in `eda-accompanist-frontend/app.tsx`.

### Agent surface

A `bb remote` CLI giving agents the same reads as the panel:

- `bb remote status` — effective target and root, which of the four config tiers
  supplied them, connection state, probe results
- `bb remote use <target> [root]` — set the session override
- `bb remote ls [path]` — listing as JSON or a table
- `bb remote cat <path>` — head-read of a text file

### Error handling

Every failure is reported as a state the panel can render, never a thrown blob:

- **Unset config** — an empty state naming the three ways to set it.
- **Unreachable host** — the ssh stderr, verbatim, with the target that was
  tried.
- **Auth failure** — distinguished from unreachable, and says that `BatchMode`
  means key or agent auth only.
- **Missing root** — reported by Test separately from reachability, so "I can
  reach the box but the directory is wrong" is legible.
- **Path escapes root** — refused with the realpath that was resolved.
- **Too large to preview** — a state showing size and type, not an error.
- **Tier B limitations** — a preview that would need remote resize says the host
  lacks the tooling and offers to fetch the original.

### Testing

`node --test 'test/*.test.ts'` plus `createFakePluginHost()` from
`@get-bb/plugin-sdk/testing`, matching `bb-plugin-nats-bus`.

The load-bearing logic is pure and is tested without a network:

- target parsing — every accepted form, and rejection of shell- and flag-shaped
  input
- ssh argv construction — multiplexing options, port handling, no shell string
- path confinement — `..`, absolute paths, symlink escape
- cache keying — a changed size or mtime produces a different key
- the size-policy decision table — every row
- both listing parsers — against captured GNU and BSD fixtures, including
  filenames with spaces and newlines

The transport layer is integration-tested against a fake `ssh` executable placed
on `PATH`, which asserts the argv it receives and replays canned stdout.

## Out of scope for v1

Write operations of any kind. Download-to-local. Video and PDF thumbnails.
Binary hexdump fallback. Syntax highlighting. Multiple simultaneous hosts.

## Repository

The plugin is its own standalone git repository under `bb-plugins/`, consistent
with every other plugin in this project. The parent `malleable-control` repo
does not track it; only this design document is committed to the parent.
