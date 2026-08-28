;;; mc-llm.el --- Summon GT's LLM chat from Emacs -*- lexical-binding: t; -*-

;; Part of malleable-control.

;;; Commentary:

;; GT's chat lives in the image, not in a window.  There are three places it
;; can surface, and this file drives all three from Emacs over the bus:
;;
;;   the third pane of the main window   `mc-llm-refresh-home'
;;   the chat dropdown in the toolbar    (same call -- it is rebuilt too)
;;   a chat in its own window            `mc-llm-chat' / `mc-llm-new-chat'
;;
;; Why a refresh is needed at all: GtHome asks GtLConnectionRegistry exactly
;; once, while it is being built, whether to draw the chat panel or the
;; "Setup LLM connections" placeholder -- and the world toolbar asks the same
;; question, once, about its chat dropdown.  Both are built while the image
;; boots, before the malleable-control startup script has registered the
;; OpenAI-compatible connector, and nothing ever asks again.  So a GT that is
;; perfectly well connected still shows the placeholder until something
;; re-renders it.  McGtPatches does this at the end of every apply; this is
;; the same call, on demand.
;;
;; Usage from Emacs (after mc-emacs-start):
;;
;;   (require 'mc-llm)
;;   (mc-llm-chat)              ; C-c g c  with the keymap below
;;
;; To bind them:
;;
;;   (mc-llm-install-keys)      ; C-c g c/n/h/s/w/d/o/l
;;
;; A chat keeps the backend it was born with: `GtLChat >> provider' builds
;; from the registry default the first time it is asked and then caches it,
;; so changing the default moves only NEW chats.  `mc-llm-switch' re-points
;; the chat already on screen, history and all.

;;; Code:

(require 'mc-emacs-service)

(defgroup mc-llm nil
  "Summon GT's LLM chat from Emacs."
  :group 'tools
  :prefix "mc-llm-")

(defcustom mc-llm-keymap-prefix "C-c g"
  "Prefix `mc-llm-install-keys' hangs its bindings from."
  :type 'string
  :group 'mc-llm)

(defun mc-llm--unquote (printed)
  "Turn a Smalltalk printString of a String back into the string.

`gt.cmd.eval' answers `printString', so a String comes back wrapped in
single quotes with any embedded quote doubled.  Anything else -- a number,
nil, an object -- is returned untouched."
  (if (and (stringp printed)
           (> (length printed) 1)
           (string-prefix-p "'" printed)
           (string-suffix-p "'" printed))
      (replace-regexp-in-string "''" "'" (substring printed 1 -1) t t)
    printed))

(defun mc-llm--eval (expression)
  "Evaluate EXPRESSION in the connected GT image and return its printString.

Returns nil and reports in the minibuffer if GT does not answer or the
expression raised.  This is `gt.cmd.eval', the same channel bin/gt-eval
uses, so anything one can do the other can."
  (unless (nats-connected-p mc-emacs-connection)
    (user-error "Not connected -- run M-x mc-emacs-start"))
  (let ((reply (nats-request-sync mc-emacs-connection "gt.cmd.eval"
                                  (json-serialize
                                   `(:v 1 :args (:expression ,expression))))))
    (if (null reply)
        (progn (message "GT did not answer (is it running and connected?)") nil)
      (let* ((envelope (json-parse-string reply
                                          :object-type 'plist
                                          :null-object nil
                                          :false-object nil))
             (ok (plist-get envelope :ok))
             (result (plist-get envelope :result))
             (err (plist-get envelope :error)))
        (if ok
            (mc-llm--unquote (plist-get result :value))
          (message "GT error: %s" (or (plist-get err :message) reply))
          (mc-emacs--log "gt.cmd.eval failed: %s" reply)
          nil)))))

;;;###autoload
(defun mc-llm-refresh-home ()
  "Re-render GT's main window so the chat pane and toolbar dropdown appear.

Idempotent, and safe on a window that is already correct: it rebuilds
GtHome's sections and the world toolbar from their stencils."
  (interactive)
  (let ((answer (mc-llm--eval "(Smalltalk at: #McGtPatches) refreshHome printString , ' main window(s) refreshed'")))
    (when answer (message "%s" answer))
    answer))

;;;###autoload
(defun mc-llm-chat ()
  "Open GT's chat in its own window, reusing the most recent chat.

Use `mc-llm-refresh-home' instead to get it as the third pane of the main
window, which is where GT itself puts it."
  (interactive)
  (let ((answer (mc-llm--eval "(Smalltalk at: #McLlm) openChat")))
    (when answer (message "GT: %s" answer))
    answer))

;;;###autoload
(defun mc-llm-new-chat ()
  "Open a GT chat with a fresh history, in its own window."
  (interactive)
  (let ((answer (mc-llm--eval "(Smalltalk at: #McLlm) newChat")))
    (when answer (message "GT: %s" answer))
    answer))

(defun mc-llm--connection-labels ()
  "The labels of every connectable connection in GT, newest state."
  (let ((answer (mc-llm--eval
                 (concat "String streamContents: [ :s | "
                         "GtLConnectionRegistry instance connectableConnections "
                         "do: [ :c | s << c label asString ] "
                         "separatedBy: [ s << String lf ] ]"))))
    (when (and answer (not (string-empty-p answer)))
      (split-string answer "\n" t))))

(defun mc-llm--read-connection (prompt)
  "Ask for a connection label, completing over what GT currently offers."
  (let ((labels (mc-llm--connection-labels)))
    (unless labels (user-error "GT has no connectable connections"))
    (completing-read prompt labels nil t nil nil (car labels))))

;;;###autoload
(defun mc-llm-switch (label)
  "Point the chat already on screen at LABEL, keeping its history.

This is the one `mc-llm-use' cannot do.  `GtLChat >> provider\' builds from
the registry default the first time it is asked and caches it forever, so a
chat is welded to whatever was default when it started.  Switching hands the
running chat a new provider."
  (interactive (list (mc-llm--read-connection "Switch this chat to: ")))
  (let ((answer (mc-llm--eval (mc-llm--selector-call "switchChat:" label))))
    (when answer (message "GT: %s" answer))
    answer))

;;;###autoload
(defun mc-llm-use (label)
  "Make LABEL the default connection, which is what NEW chats get.

Existing chats keep their own backend -- use `mc-llm-switch\' for those."
  (interactive (list (mc-llm--read-connection "Default for new chats: ")))
  (let ((answer (mc-llm--eval (mc-llm--selector-call "use:" label))))
    (when answer (message "GT: %s" answer))
    answer))

;;;###autoload
(defun mc-llm-new-chat-on (label)
  "Open a chat on LABEL without changing the default."
  (interactive (list (mc-llm--read-connection "New chat on: ")))
  (let ((answer (mc-llm--eval (mc-llm--selector-call "newChatOn:" label))))
    (when answer (message "GT: %s" answer))
    answer))

;;;###autoload
(defun mc-llm-chats ()
  "Show every chat and the server it actually talks to."
  (interactive)
  (mc-llm--show-in-buffer "*mc-llm-chats*"
                          (mc-llm--eval "(Smalltalk at: #McLlm) chatsReport")))

(defun mc-llm--selector-call (selector label)
  "Smalltalk sending SELECTOR to McLlm with LABEL, quote-escaped."
  (format "(Smalltalk at: #McLlm) %s '%s'"
          selector
          (replace-regexp-in-string "'" "''" label t t)))

(defun mc-llm--show-in-buffer (name text)
  "Put TEXT in buffer NAME and display it."
  (when text
    (with-current-buffer (get-buffer-create name)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (goto-char (point-min)))
      (special-mode)
      (display-buffer (current-buffer))))
  text)

;;;###autoload
(defun mc-llm-status ()
  "Show which LLM connections GT has, and why the others are unusable."
  (interactive)
  (mc-llm--show-in-buffer "*mc-llm-status*"
                          (mc-llm--eval "(Smalltalk at: #McLlm) status")))

;;;###autoload
(defun mc-llm-install-keys ()
  "Bind the launchers under `mc-llm-keymap-prefix' globally."
  (interactive)
  (let ((prefix mc-llm-keymap-prefix))
    (global-set-key (kbd (concat prefix " c")) #'mc-llm-chat)
    (global-set-key (kbd (concat prefix " n")) #'mc-llm-new-chat)
    (global-set-key (kbd (concat prefix " h")) #'mc-llm-refresh-home)
    (global-set-key (kbd (concat prefix " s")) #'mc-llm-status)
    (global-set-key (kbd (concat prefix " w")) #'mc-llm-switch)
    (global-set-key (kbd (concat prefix " d")) #'mc-llm-use)
    (global-set-key (kbd (concat prefix " o")) #'mc-llm-new-chat-on)
    (global-set-key (kbd (concat prefix " l")) #'mc-llm-chats)
    (message "mc-llm: %s c/n/h/s/w/d/o/l -> chat / new / home / status / switch / default / new-on / list"
             prefix)))

(provide 'mc-llm)

;;; mc-llm.el ends here
