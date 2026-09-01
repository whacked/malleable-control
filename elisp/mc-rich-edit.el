;;; mc-rich-edit.el --- Open the rich-edit prototype in GT -*- lexical-binding: t; -*-

;; Part of malleable-control.

;;; Code:

(require 'mc-emacs-service)
(require 'mc-smalltalk)

(defvar mc-rich-edit-home
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name
                             (locate-library "mc-rich-edit")
                             (buffer-file-name)))))
  "Root of the malleable-control project.")

;;;###autoload
(defun mc-rich-edit-open ()
  "Load McRichEdit into GT and open the prototype editor."
  (interactive)
  (unless (nats-connected-p mc-emacs-connection)
    (user-error "Not connected — run M-x mc-emacs-start"))
  (let* ((cache-path (expand-file-name "pharo/McCache.st" mc-rich-edit-home))
         (relation-path (expand-file-name "pharo/McRelation.st" mc-rich-edit-home))
         (link-path (expand-file-name "pharo/McMarkdownLink.st" mc-rich-edit-home))
         (inline-path (expand-file-name "pharo/McMarkdownInline.st" mc-rich-edit-home))
         (table-path (expand-file-name "pharo/McMarkdownTable.st" mc-rich-edit-home))
         (sqlite-path (expand-file-name "pharo/McSqlite.st" mc-rich-edit-home))
         (markdown-path (expand-file-name "pharo/McMarkdown.st" mc-rich-edit-home))
         (snapshot-path (expand-file-name "pharo/McMarkdownSnapshot.st" mc-rich-edit-home))
         (reconciler-path (expand-file-name "pharo/McMarkdownReconciler.st" mc-rich-edit-home))
         (keymap-path (expand-file-name "pharo/McKeymap.st" mc-rich-edit-home))
         (search-path (expand-file-name "pharo/McSearch.st" mc-rich-edit-home))
         (st-path (expand-file-name "pharo/McRichEdit.st" mc-rich-edit-home))
         (links-path (expand-file-name "pharo/McRichEditLinks.st" mc-rich-edit-home))
         ;; Load order matters: McBoundedCache is used by McMarkdownInline,
         ;; McMarkdownTable and McSqlite, McMarkdownTable's cell reader
         ;; depends on McRelation, McSqlite depends on McRelation,
         ;; McMarkdown's visitor calls into McMarkdownInline, McMarkdownTable,
         ;; and McSqlite, and McRichEdit's styler calls into McMarkdown.
         (expr (format (concat "'%s' asFileReference fileIn. "
                               "'%s' asFileReference fileIn. "
                               "'%s' asFileReference fileIn. "
                               "'%s' asFileReference fileIn. "
                               "'%s' asFileReference fileIn. "
                               "'%s' asFileReference fileIn. "
                               "'%s' asFileReference fileIn. "
                               "'%s' asFileReference fileIn. "
                               "'%s' asFileReference fileIn. "
                               "'%s' asFileReference fileIn. "
                               "'%s' asFileReference fileIn. "
                               "'%s' asFileReference fileIn. "
                               "'%s' asFileReference fileIn. "
                               "(Smalltalk at: #McRichEdit) open. 'opened'")
                       cache-path relation-path link-path inline-path table-path
                       sqlite-path markdown-path snapshot-path reconciler-path
                       keymap-path search-path st-path links-path))
         (reply (nats-request-sync mc-emacs-connection "gt.cmd.eval"
                  (json-serialize `(:v 1 :args (:expression ,expr))))))
    (if reply
        (message "Rich Edit prototype opened in GT")
      (message "GT did not respond (is it running?)"))))

;;;###autoload
(defun mc-rich-edit-open-from (root)
  "Load and open the Rich Edit implementation rooted at ROOT.
This is the explicit worktree/development entry point; unlike changing the
global `mc-rich-edit-home', the override lasts for one invocation only."
  (interactive "DRich Edit project/worktree root: ")
  (let ((mc-rich-edit-home (file-name-as-directory (expand-file-name root))))
    (mc-rich-edit-open)))

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
