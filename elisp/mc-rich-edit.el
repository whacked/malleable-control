;;; mc-rich-edit.el --- Open the rich-edit prototype in GT -*- lexical-binding: t; -*-

;; Part of malleable-control.

;;; Code:

(require 'mc-emacs-service)

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
  (let* ((markdown-path (expand-file-name "pharo/McMarkdown.st" mc-rich-edit-home))
         (st-path (expand-file-name "pharo/McRichEdit.st" mc-rich-edit-home))
         ;; McMarkdown must load first: McRichEdit's styler calls into it.
         (expr (format (concat "'%s' asFileReference fileIn. "
                               "'%s' asFileReference fileIn. "
                               "(Smalltalk at: #McRichEdit) open. 'opened'")
                       markdown-path st-path))
         (reply (nats-request-sync mc-emacs-connection "gt.cmd.eval"
                  (json-serialize `(:v 1 :args (:expression ,expr))))))
    (if reply
        (message "Rich Edit prototype opened in GT")
      (message "GT did not respond (is it running?)"))))

(provide 'mc-rich-edit)

;;; mc-rich-edit.el ends here
