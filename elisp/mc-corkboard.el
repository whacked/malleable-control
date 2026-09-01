;;; mc-corkboard.el --- Open the corkboard canvas prototype in GT -*- lexical-binding: t; -*-

;; Part of malleable-control.
;;
;; The corkboard is its own component, not a rich-edit feature, so it gets
;; its own loader.  It shares no Smalltalk class with McRichEdit: the three
;; files below are the whole dependency set.

;;; Code:

(require 'mc-smalltalk)

(defvar mc-corkboard-home
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name
                             (locate-library "mc-corkboard")
                             (buffer-file-name)))))
  "Root of the malleable-control project.")

(defconst mc-corkboard-files
  '("pharo/McCorkboardPanelModel.st"
    "pharo/McCorkboardDocument.st"
    "pharo/McCorkboard.st")
  "Smalltalk files to load, in dependency order.
McCorkboard projects a McCorkboardDocument, which holds
McCorkboardPanelModel instances.")

;;;###autoload
(defun mc-corkboard-open ()
  "Load McCorkboard into GT and open the coordinate canvas prototype."
  (interactive)
  (mc-corkboard-open-from mc-corkboard-home))

;;;###autoload
(defun mc-corkboard-open-from (root)
  "Load and open the corkboard implementation rooted at ROOT.
Mirrors `mc-rich-edit-open-from': the override lasts one invocation."
  (interactive "DCorkboard project/worktree root: ")
  (let ((root (file-name-as-directory (expand-file-name root))))
    (dolist (file mc-corkboard-files)
      (mc-st-filein-sync (expand-file-name file root)))
    (mc-st-eval-sync "(Smalltalk at: #McCorkboard) open. 'opened'")
    (message "Corkboard opened in GT")))

(provide 'mc-corkboard)

;;; mc-corkboard.el ends here
