;;; mc-launchers.el --- Generate launcher commands from launchers/*.json -*- lexical-binding: t; -*-

;; Part of malleable-control.
;;
;; A launcher is two facts: an ordered list of .st files to file in, and one
;; expression to evaluate once they are in.  Those facts used to live here, in
;; elisp, duplicated into test/run-pharo-tests.sh and invisible to GT -- which
;; is backwards, since GT is the core and Emacs is a client of the bus.
;;
;; They now live in launchers/*.json, which GT reads to build its home-screen
;; panel and the test runner reads to know what to file in.  This file is the
;; third reader: it defines one `mc-NAME-open' command per manifest.
;;
;; Adding a tool is adding one JSON file.  No elisp changes.

;;; Code:

(require 'seq)
(require 'mc-smalltalk)

(defvar mc-launchers-home
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name
                             (locate-library "mc-launchers")
                             (buffer-file-name)))))
  "Root of the malleable-control project.")

(defvar mc-launchers nil
  "Alist of (NAME . MANIFEST-PLIST), populated by `mc-launchers-load'.")

(defun mc-launchers--directory (&optional root)
  (expand-file-name "launchers" (or root mc-launchers-home)))

(defun mc-launchers--read-file (file)
  "Parse FILE as a launcher manifest.
Answers a plist with at least :name, or nil if FILE will not parse.
A broken manifest is reported and skipped rather than signalling, so one
bad file cannot stop the rest of the launchers being defined."
  (condition-case err
      (let ((json (json-parse-string
                   (with-temp-buffer
                     (insert-file-contents file)
                     (buffer-string))
                   :object-type 'plist :array-type 'list
                   :null-object nil :false-object nil)))
        (dolist (key '(:title :blurb :files :open))
          (unless (plist-member json key)
            (error "missing required key %s" key)))
        (plist-put json :name (file-name-base file)))
    (error (message "mc-launchers: %s: %s" (file-name-nondirectory file)
                    (error-message-string err))
           nil)))

(defun mc-launchers--manifests (&optional root)
  "Every readable manifest under ROOT, sorted by priority then title."
  (let* ((dir (mc-launchers--directory root))
         (files (and (file-directory-p dir)
                     (directory-files dir t "\\.json\\'")))
         (manifests (delq nil (mapcar #'mc-launchers--read-file files))))
    (sort manifests
          (lambda (a b)
            (let ((pa (or (plist-get a :priority) most-positive-fixnum))
                  (pb (or (plist-get b :priority) most-positive-fixnum)))
              (if (= pa pb)
                  (string< (plist-get a :title) (plist-get b :title))
                (< pa pb)))))))

(defun mc-launcher--hook-symbol (name)
  (intern (format "mc-launcher-%s-hook" name)))

(defun mc-launcher--ensure-hook (name)
  "Make sure `mc-launcher-NAME-hook' exists as a special variable.
Defined here rather than with `defvar' because the set of launchers is
not known until launchers/ has been read."
  (let ((symbol (mc-launcher--hook-symbol name)))
    (unless (boundp symbol)
      (set-default symbol nil))
    (put symbol 'variable-documentation
         (format "Run before the %s launcher opens.  See `mc-launcher-open'."
                 name))
    symbol))

(defun mc-launcher-open (name &optional root)
  "File in the sources for launcher NAME and evaluate its open expression.
ROOT overrides the project root for one invocation, which is how a
worktree is opened without touching the global.  Runs
`mc-launcher-NAME-hook' between filing the sources in and opening, which
is where Emacs-side setup that GT knows nothing about -- a bus
subscription, a store binding -- attaches itself.

The files are filed in one call at a time and the open expression is a
call of its own.  That separation is required, not stylistic: Pharo
resolves variable names when it COMPILES an expression, so an open
expression bundled with the fileIns that create its class would fail to
compile."
  (let ((manifest (mc-launcher--manifest name root)))
    (mc-launcher-filein name root)
    ;; After the sources, before the open.  KDI's hook installs a binding by
    ;; evaluating `McKdiBinding root: ...', which cannot compile until
    ;; McKdi.st has been filed in -- so a hook that ran first would break the
    ;; launcher it was meant to configure.
    (run-hooks (mc-launcher--hook-symbol name))
    (mc-st-eval-sync (plist-get manifest :open))
    (message "%s opened in GT" (plist-get manifest :title))))

(defun mc-launcher--manifest (name &optional root)
  "The manifest named NAME under ROOT, or signal."
  (or (seq-find (lambda (m) (equal (plist-get m :name) name))
                (mc-launchers--manifests (or root mc-launchers-home)))
      (user-error "No launcher named %s in %s"
                  name (mc-launchers--directory root))))

;;;###autoload
(defun mc-launcher-filein (name &optional root)
  "File in launcher NAME's sources, in order, without opening anything.
This is the reload half of a launcher.  Adding a gtView method to a
class and filing it back in is picked up by an inspector that is already
open, so this is how a view is grown while looking at the data."
  (interactive
   (list (completing-read "Launcher: "
                          (mapcar (lambda (m) (plist-get m :name))
                                  (mc-launchers--manifests))
                          nil t)))
  (let* ((root (or root mc-launchers-home))
         (manifest (mc-launcher--manifest name root)))
    (dolist (file (plist-get manifest :files))
      (let ((path (expand-file-name file root)))
        (unless (file-exists-p path)
          (user-error "%s: missing source %s" name file))
        (mc-st-filein-sync path)))
    (when (called-interactively-p 'interactive)
      (message "%s: %d file(s) filed in"
               (plist-get manifest :title)
               (length (plist-get manifest :files))))
    manifest))

;;;###autoload
(defun mc-launcher-open-from (name root)
  "Open launcher NAME from the checkout at ROOT.
The override lasts one invocation, which is the worktree workflow in
docs/worktrees.md."
  (interactive
   (list (completing-read "Launcher: "
                          (mapcar (lambda (m) (plist-get m :name))
                                  (mc-launchers--manifests))
                          nil t)
         (read-directory-name "Project/worktree root: ")))
  (mc-launcher-open name (file-name-as-directory (expand-file-name root))))

;;;###autoload
(defun mc-launchers-load ()
  "Read launchers/ and define one `mc-NAME-open' command per manifest.
Called at load time.  Re-run it after adding a manifest."
  (interactive)
  (setq mc-launchers nil)
  (dolist (manifest (mc-launchers--manifests))
    (let* ((name (plist-get manifest :name))
           (title (plist-get manifest :title))
           (blurb (plist-get manifest :blurb))
           (command (intern (format "mc-%s-open" name))))
      (push (cons name manifest) mc-launchers)
      (mc-launcher--ensure-hook name)
      (defalias command
        (lambda ()
          (interactive)
          (mc-launcher-open name))
        (format "Load and open %s in GT.\n\n%s\n\nGenerated from launchers/%s.json."
                title blurb name))))
  (setq mc-launchers (nreverse mc-launchers))
  (when (called-interactively-p 'interactive)
    (message "mc-launchers: %d launcher(s)" (length mc-launchers)))
  mc-launchers)

(mc-launchers-load)

(provide 'mc-launchers)

;;; mc-launchers.el ends here
