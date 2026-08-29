;;; mc-smalltalk.el --- nREPL-like Smalltalk eval via GT over NATS -*- lexical-binding: t; -*-

;; Part of malleable-control.
;;
;; Provides two things:
;;
;;   1. `mc-st-repl' — interactive Smalltalk REPL buffer connected to GT.
;;   2. `mc-st-mode' — minor mode for .st files with eval keybindings.
;;
;; Keybindings (minor mode and REPL):
;;
;;   C-x C-e   Eval region (or current line if no region)
;;   C-c C-c   Eval current method chunk (fileIn the method at point)
;;   C-c C-k   FileIn the whole buffer/file
;;   C-c C-z   Switch to REPL
;;
;; Usage:
;;
;;   (require 'mc-smalltalk)
;;   M-x mc-st-repl          ; open REPL
;;   M-x mc-st-mode          ; activate in any .st buffer

;;; Code:

(require 'mc-emacs-service)

(defvar mc-st-home
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name
                             (locate-library "mc-smalltalk")
                             (buffer-file-name)))))
  "Root of the malleable-control project.")

;;;; ---- Core eval --------------------------------------------------------

(defun mc-st-eval-sync (code)
  "Evaluate CODE in GT via gt.cmd.eval.  Return result string.
Signals an error on GT eval failure or timeout."
  (unless (and mc-emacs-connection (nats-connected-p mc-emacs-connection))
    (user-error "Not connected to NATS — run M-x mc-emacs-start"))
  (let ((reply (nats-request-sync mc-emacs-connection "gt.cmd.eval"
                 (json-serialize `(:v 1 :args (:expression ,code))))))
    (unless reply (user-error "GT did not respond (timeout)"))
    (let* ((resp (json-parse-string reply
                   :object-type 'plist
                   :null-object nil
                   :false-object nil))
           (ok (plist-get resp :ok)))
      (if ok
          (plist-get (plist-get resp :result) :value)
        (error "GT: %s" (plist-get (plist-get resp :error) :message))))))

(defun mc-st-filein-sync (file)
  "FileIn FILE into GT.  Return the result string."
  (mc-st-eval-sync (format "'%s' asFileReference fileIn. 'fileIn ok'" file)))

(defun mc-st-filein-string-sync (chunk)
  "FileIn a chunk string into GT via a temp file.
Avoids quoting issues by writing CHUNK to a temp file first."
  (let ((tmpfile (make-temp-file "mc-st-" nil ".st")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile (insert chunk))
          (mc-st-eval-sync
           (format "'%s' asFileReference fileIn. 'fileIn ok'" tmpfile)))
      (delete-file tmpfile t))))

;;;; ---- REPL -------------------------------------------------------------

(defvar mc-st-repl-buffer-name "*Smalltalk*"
  "Name of the Smalltalk REPL buffer.")

(defvar-local mc-st--input-start nil
  "Marker for the start of user input in the REPL.")

(defvar-local mc-st--history nil
  "Input history for the REPL.")

(defvar-local mc-st--history-index -1
  "Current position in history for M-p / M-n navigation.")

(defvar-local mc-st--history-saved-input nil
  "Saved current input before history navigation.")

(defvar mc-st-repl-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET")     #'mc-st-repl-send)
    (define-key map (kbd "M-p")     #'mc-st-repl-history-prev)
    (define-key map (kbd "M-n")     #'mc-st-repl-history-next)
    (define-key map (kbd "C-c C-k") #'mc-st-eval-buffer)
    (define-key map (kbd "C-c C-z") #'mc-st-switch-to-repl)
    map)
  "Keymap for the Smalltalk REPL.")

(define-derived-mode mc-st-repl-mode fundamental-mode "ST-REPL"
  "Major mode for a Smalltalk REPL connected to GT via NATS."
  (setq-local mc-st--input-start (make-marker))
  (setq-local mc-st--history nil)
  (setq-local mc-st--history-index -1))

(defun mc-st-repl ()
  "Open a Smalltalk REPL connected to the running GT instance."
  (interactive)
  (let ((buf (get-buffer-create mc-st-repl-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'mc-st-repl-mode)
        (mc-st-repl-mode)
        (let ((inhibit-read-only t))
          (insert (propertize "Smalltalk REPL — connected to GT via NATS bus\n\n"
                              'read-only t 'face 'font-lock-comment-face)))
        (mc-st--insert-prompt)))
    (pop-to-buffer buf)))

(defun mc-st--insert-prompt ()
  "Insert the REPL prompt and set input start marker."
  (let ((inhibit-read-only t))
    (insert (propertize "ST> " 'read-only t 'rear-nonsticky t
                        'front-sticky t 'face 'minibuffer-prompt)))
  (set-marker mc-st--input-start (point)))

(defun mc-st--current-input ()
  "Return the current input string in the REPL."
  (buffer-substring-no-properties mc-st--input-start (point-max)))

(defun mc-st-repl-send ()
  "Send the current input to GT for evaluation."
  (interactive)
  (let ((input (string-trim (mc-st--current-input))))
    (when (string-empty-p input) (user-error "Empty input"))
    (goto-char (point-max))
    (let ((inhibit-read-only t))
      (insert "\n")
      (push input mc-st--history)
      (setq mc-st--history-index -1)
      (condition-case err
          (let ((result (mc-st-eval-sync input)))
            (insert (propertize (format "=> %s\n\n" result)
                                'read-only t 'face 'font-lock-string-face)))
        (error
         (insert (propertize (format "!! %s\n\n" (error-message-string err))
                             'read-only t 'face 'font-lock-warning-face))))
      (mc-st--insert-prompt)
      (goto-char (point-max)))))

(defun mc-st-repl-history-prev ()
  "Navigate to the previous history entry."
  (interactive)
  (when (null mc-st--history) (user-error "No history"))
  (when (= mc-st--history-index -1)
    (setq mc-st--history-saved-input (mc-st--current-input)))
  (when (< mc-st--history-index (1- (length mc-st--history)))
    (cl-incf mc-st--history-index)
    (delete-region mc-st--input-start (point-max))
    (insert (nth mc-st--history-index mc-st--history))))

(defun mc-st-repl-history-next ()
  "Navigate to the next history entry."
  (interactive)
  (cond
   ((> mc-st--history-index 0)
    (cl-decf mc-st--history-index)
    (delete-region mc-st--input-start (point-max))
    (insert (nth mc-st--history-index mc-st--history)))
   ((= mc-st--history-index 0)
    (setq mc-st--history-index -1)
    (delete-region mc-st--input-start (point-max))
    (when mc-st--history-saved-input
      (insert mc-st--history-saved-input)))))

;;;; ---- Minor mode for .st files -----------------------------------------

(defvar mc-st-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-x C-e") #'mc-st-eval-region-or-line)
    (define-key map (kbd "C-c C-c") #'mc-st-eval-method-at-point)
    (define-key map (kbd "C-c C-k") #'mc-st-eval-buffer)
    (define-key map (kbd "C-c C-z") #'mc-st-switch-to-repl)
    map)
  "Keymap for mc-st-mode.")

;;;###autoload
(define-minor-mode mc-st-mode
  "Minor mode for evaluating Smalltalk in GT via the NATS bus.

\\{mc-st-mode-map}"
  :lighter " ST"
  :keymap mc-st-mode-map)

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.st\\'" . mc-st-auto-activate))

(defun mc-st-auto-activate ()
  "Activate `mc-st-mode' for .st files."
  (fundamental-mode)
  (mc-st-mode 1))

;;;; ---- Eval commands ----------------------------------------------------

(defun mc-st--chunk-format-p (code)
  "Non-nil if CODE looks like Smalltalk chunk format (starts with !)."
  (string-match-p "\\`!" code))

(defun mc-st-eval-region-or-line ()
  "Eval the active region or current line in GT.
If the code looks like chunk format (starts with !), fileIn it.
Otherwise, evaluate it as a Smalltalk expression.
Result is shown in the minibuffer and the REPL (if open)."
  (interactive)
  (let* ((code (if (use-region-p)
                   (buffer-substring-no-properties (region-beginning) (region-end))
                 (string-trim (thing-at-point 'line t))))
         (code (string-trim code)))
    (when (string-empty-p code) (user-error "Nothing to evaluate"))
    (if (mc-st--chunk-format-p code)
        (mc-st--eval-and-display-filein code "fileIn ok")
      (mc-st--eval-and-display code))))

(defun mc-st-eval-method-at-point ()
  "FileIn the current method at point.
Finds the enclosing category header (!Class methodsFor: ...!) and the
method body (delimited by !) and sends them to GT as a fileIn chunk."
  (interactive)
  (let ((chunk (mc-st--extract-method-chunk)))
    (mc-st--eval-and-display-filein chunk "method installed")))

(defun mc-st-eval-buffer ()
  "FileIn the current buffer's file into GT."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless file (user-error "Buffer is not visiting a file"))
    (when (buffer-modified-p) (save-buffer))
    (condition-case err
        (let ((result (mc-st-filein-sync file)))
          (mc-st--echo-result result)
          (message "FileIn: %s — %s" (file-name-nondirectory file) result))
      (error (message "FileIn error: %s" (error-message-string err))))))

(defun mc-st-switch-to-repl ()
  "Switch to the Smalltalk REPL buffer, creating it if needed."
  (interactive)
  (mc-st-repl))

;;;; ---- Chunk extraction -------------------------------------------------

(defun mc-st--extract-method-chunk ()
  "Extract the current method as a fileIn-able chunk string.
Returns a string: !Class methodsFor: 'category'!\\nmethod body! !"
  (save-excursion
    (let (header-start header-end method-start method-end category-header)
      ;; Find the category header above point.
      (unless (re-search-backward "^!\\(.+\\)methodsFor:\\s-*'\\([^']*\\)'\\s-*!" nil t)
        (user-error "No category header (!...methodsFor:...!) found above point"))
      (setq category-header (match-string 0))
      (setq header-end (match-end 0))

      ;; Move past the header to find method boundaries.
      (goto-char header-end)
      (forward-line 1)
      (setq method-start (point))

      ;; Find which method contains the original point.
      ;; Methods are separated by ! at end of line (but not ! !).
      (let ((orig-point (point))
            (found nil))
        ;; Walk through methods in this category.
        (goto-char header-end)
        (forward-line 1)
        (setq method-start (point))
        (while (and (not found)
                    (re-search-forward "^\\(.*\\)!\\s-*$" nil t))
          (setq method-end (match-beginning 0))
          ;; Check if this is the category terminator (! !)
          (if (looking-at "\\s-*!")
              ;; End of category — use last method
              (setq found t)
            ;; Method boundary — check if original point is in this method
            (if (<= orig-point (point))
                (setq found t)
              ;; Move to next method
              (forward-line 1)
              (setq method-start (point)))))

        (unless method-end
          (setq method-end (point-max)))

        (let ((method-body (string-trim-right
                            (buffer-substring-no-properties method-start method-end))))
          (format "%s\n%s! !" category-header method-body))))))

;;;; ---- Display helpers --------------------------------------------------

(defun mc-st--eval-and-display (code)
  "Eval CODE as an expression, show result in minibuffer and REPL."
  (condition-case err
      (let ((result (mc-st-eval-sync code)))
        (mc-st--echo-result result)
        (message "=> %s" result))
    (error
     (message "!! %s" (error-message-string err)))))

(defun mc-st--eval-and-display-filein (chunk success-msg)
  "FileIn CHUNK, show SUCCESS-MSG or error in minibuffer."
  (condition-case err
      (let ((result (mc-st-filein-string-sync chunk)))
        (mc-st--echo-result result)
        (message "%s" (or success-msg result)))
    (error
     (message "!! %s" (error-message-string err)))))

(defun mc-st--echo-result (result)
  "If the REPL buffer exists, append RESULT above the prompt."
  (when-let ((buf (get-buffer mc-st-repl-buffer-name)))
    (with-current-buffer buf
      (when (derived-mode-p 'mc-st-repl-mode)
        (save-excursion
          (goto-char mc-st--input-start)
          (forward-line 0)              ; beginning of prompt line
          (let ((inhibit-read-only t))
            (insert (propertize (format "[eval] => %s\n" result)
                                'read-only t 'face 'font-lock-doc-face))))))))

(provide 'mc-smalltalk)

;;; mc-smalltalk.el ends here
