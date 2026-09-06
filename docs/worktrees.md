# Active development worktrees

All repository worktrees live in the single sibling directory
`$CLOUDSYNC/main/devsync/malleable-control-worktrees`.

| Purpose | Branch | Path |
|---|---|---|
| _(none active)_ | | |

Git remains the authoritative registry:

```sh
git worktree list
```

## Merged

| Purpose | Branch | Merged into |
|---|---|---|
| Interactive Rich Edit search | `codex/rich-edit-search` | `relational-tables` |
| Coordinate corkboard canvas | `codex/corkboard-canvas` | `relational-tables` |

Both now load from the main checkout, so neither needs a worktree path:

```elisp
(require 'mc-launchers)
(mc-rich-edit-open)
(mc-corkboard-open)
```

Both commands are generated from `launchers/`, so `mc-corkboard.el` and
`mc-workbench.el` no longer exist -- `mc-launchers` is the only require.

Close an existing Rich Edit window first: `McRichEdit class>>open` foregrounds
an existing live instance rather than creating a second instance.

## Working from a worktree

`mc-launcher-open-from` takes a launcher name and an explicit root, so a
worktree can be loaded without touching the global home. It replaces the
per-tool `mc-rich-edit-open-from` and `mc-corkboard-open-from`, and works for
every launcher including ones added later:

```elisp
(mc-launcher-open-from "rich-edit" ".../malleable-control-worktrees/<name>")
```

It reads the worktree's OWN `launchers/` directory, so a worktree that changed
a tool's load order is honoured rather than the main checkout's.

One caveat that has cost real debugging time: every worktree files into the
same GT image. Loading an older `McRichEdit.st` from a stale worktree silently
reverts whatever the main checkout had installed.
