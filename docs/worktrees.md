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
(mc-rich-edit-open)   ; requires mc-rich-edit
(mc-corkboard-open)   ; requires mc-corkboard
```

Close an existing Rich Edit window first: `McRichEdit class>>open` foregrounds
an existing live instance rather than creating a second instance.

## Working from a worktree

`mc-rich-edit-open-from` and `mc-corkboard-open-from` take an explicit root, so
a worktree can be loaded without touching the global home:

```elisp
(load-file ".../malleable-control-worktrees/<name>/elisp/mc-rich-edit.el")
(mc-rich-edit-open-from ".../malleable-control-worktrees/<name>")
```

One caveat that has cost real debugging time: every worktree files into the
same GT image. Loading an older `McRichEdit.st` from a stale worktree silently
reverts whatever the main checkout had installed.
