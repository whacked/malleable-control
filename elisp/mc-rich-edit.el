;;; mc-rich-edit.el --- Open the rich-edit prototype in GT -*- lexical-binding: t; -*-

;; Part of malleable-control.

;;; Code:

(require 'mc-emacs-service)
(require 'mc-smalltalk)
(require 'mc-launchers)

;; `mc-rich-edit-open' is generated from launchers/rich-edit.json -- the
;; thirteen-file load order used to be inlined here as a format string, and was
;; the copy most likely to drift.  What is left in this file is the commands
;; that operate on an editor that is already running.

(defvar mc-rich-edit-home
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name
                             (locate-library "mc-rich-edit")
                             (buffer-file-name)))))
  "Root of the malleable-control project.")

(defun mc-rich-edit--unquote-smalltalk-string (printed)
  "Decode the printString representation of a Smalltalk String."
  (if (and (stringp printed)
           (> (length printed) 1)
           (string-prefix-p "'" printed)
           (string-suffix-p "'" printed))
      (replace-regexp-in-string "''" "'" (substring printed 1 -1) t t)
    printed))

;;;###autoload
(defun mc-rich-edit-search (query)
  "Search the active Rich Edit for QUERY and return structured result data.
Interactively, prompt for QUERY and report the active/count summary.  The
returned plist includes :document, :ranges, :activeRange, :activeIndex,
:matchCount, :highlightAll, and :wrapAround."
  (interactive "sSearch Rich Edit: ")
  (let* ((escaped (replace-regexp-in-string "'" "''" query t t))
         (printed
          (mc-st-eval-sync
           (format
            (concat "| instance | instance := (Smalltalk at: #McRichEdit) activeInstance. "
                    "instance ifNil: [ self error: 'No open Rich Edit' ]. "
                    "NeoJSONWriter toString: (instance searchFor: '%s')")
            escaped)))
         (result
          (json-parse-string
           (mc-rich-edit--unquote-smalltalk-string printed)
           :object-type 'plist :array-type 'list
           :null-object nil :false-object nil)))
    (when (called-interactively-p 'interactive)
      (message "Rich Edit search: %s/%s"
               (or (plist-get result :activeIndex) 0)
               (or (plist-get result :matchCount) 0)))
    result))

;;;###autoload
(defun mc-rich-edit-render (markdown)
  "Render MARKDOWN through McRichEdit and display the PNG in Emacs.
With a prefix arg, prompts for the string; otherwise uses the region
or the whole buffer."
  (interactive
   (list (cond
          (current-prefix-arg (read-string "Markdown: "))
          ((use-region-p)
           (buffer-substring-no-properties (region-beginning) (region-end)))
          (t (buffer-substring-no-properties (point-min) (point-max))))))
  (unless (nats-connected-p mc-emacs-connection)
    (user-error "Not connected — run M-x mc-emacs-start"))
  (let* ((out (expand-file-name (format "render-%s.png"
                                        (format-time-string "%H%M%S"))
                                temporary-file-directory))
         ;; Escape single quotes for Smalltalk string literal.
         (escaped (replace-regexp-in-string "'" "''" markdown))
         (expr (format "(Smalltalk at: #McRichEdit) renderMarkdown: '%s' toFile: '%s'"
                       escaped out))
         (reply (nats-request-sync mc-emacs-connection "gt.cmd.eval"
                  (json-serialize `(:v 1 :args (:expression ,expr)))
                  5)))
    (unless reply
      (user-error "GT did not respond (is it running?)"))
    (let ((parsed (json-parse-string reply :object-type 'plist)))
      (unless (eq (plist-get parsed :ok) t)
        (user-error "Render failed: %s"
                    (plist-get (plist-get parsed :error) :message))))
    (with-current-buffer (get-buffer-create "*mc-render*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert-image (create-image out 'png nil :max-width 800))
        (image-mode-setup-winprops)
        (goto-char (point-min)))
      (setq buffer-file-name nil)
      (set-buffer-modified-p nil)
      (special-mode))
    (pop-to-buffer "*mc-render*")
    (message "Rendered %d chars → %s" (length markdown) out)))

(provide 'mc-rich-edit)

;;; mc-rich-edit.el ends here
