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
(require 'mc-weather)
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
(require 'mc-rich-edit)
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
(require 'mc-corkboard)
(mc-corkboard-open)
```

## Workbench

The Workbench is a multi-panel BlSpace window. The left panel is an SRT
subtitle editor with a tabular view, dirty tracking, and a native file
picker. The right panel is a tmux-backed terminal emulator.

```emacs-lisp
(require 'mc-workbench)
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
