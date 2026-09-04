;;; mc-workbench.el --- Open the Workbench multi-panel tool in GT -*- lexical-binding: t; -*-

;; Part of malleable-control.
;;
;; The Workbench hosts an SRT subtitle editor and a terminal panel (coming
;; soon).  It loads the McSrtEditor and McWorkbench Smalltalk classes, which
;; depend on nothing beyond what GT ships with.

;;; Code:

(require 'mc-smalltalk)

(defvar mc-workbench-home
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name
                             (locate-library "mc-workbench")
                             (buffer-file-name)))))
  "Root of the malleable-control project.")

(defconst mc-workbench-files
  '("pharo/McSrtEntry.st"
    "pharo/McSrtEditor.st"
    "pharo/McTerminal.st"
    "pharo/McWorkbench.st")
  "Smalltalk files to load, in dependency order.
McSrtEditor depends on McSrtEntry; McWorkbench depends on both editors.")

;;;###autoload
(defun mc-workbench-open ()
  "Load McWorkbench into GT and open the Workbench window."
  (interactive)
  (mc-workbench-open-from mc-workbench-home))

;;;###autoload
(defun mc-workbench-open-from (root)
  "Load and open the Workbench implementation rooted at ROOT.
The override lasts one invocation."
  (interactive "DWorkbench project/worktree root: ")
  (let ((root (file-name-as-directory (expand-file-name root))))
    (dolist (file mc-workbench-files)
      (mc-st-filein-sync (expand-file-name file root)))
    (mc-st-eval-sync "(Smalltalk at: #McWorkbench) open. 'opened'")
    (message "Workbench opened in GT")))

(provide 'mc-workbench)

;;; mc-workbench.el ends here
