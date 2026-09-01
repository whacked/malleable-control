# Active development worktrees

All repository worktrees live in the single sibling directory
`$CLOUDSYNC/main/devsync/malleable-control-worktrees`.

| Purpose | Branch | Path |
|---|---|---|
| Interactive Rich Edit search | `codex/rich-edit-search` | `$CLOUDSYNC/main/devsync/malleable-control-worktrees/search` |
| Coordinate corkboard canvas | `codex/corkboard-canvas` | `$CLOUDSYNC/main/devsync/malleable-control-worktrees/corkboard` |

Git remains the authoritative registry:

```sh
git worktree list
```

From Emacs, load the search worktree's helper once and open that explicit root:

```elisp
(load-file "$CLOUDSYNC/main/devsync/malleable-control-worktrees/search/elisp/mc-rich-edit.el")
(mc-rich-edit-open-from
 "$CLOUDSYNC/main/devsync/malleable-control-worktrees/search")
```

Close an existing Rich Edit window first: `McRichEdit class>>open` foregrounds
an existing live instance rather than creating a second instance.

Open the corkboard from Emacs with:

```elisp
(let ((root "$CLOUDSYNC/main/devsync/malleable-control-worktrees/corkboard/"))
  (dolist (file '("pharo/McCorkboardPanelModel.st"
                  "pharo/McCorkboardDocument.st"
                  "pharo/McCorkboard.st"))
    (mc-st-filein-sync (expand-file-name file root)))
  (mc-st-eval-sync "(Smalltalk at: #McCorkboard) open"))
```
