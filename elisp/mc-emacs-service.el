;;; mc-emacs-service.el --- Emacs participant on the NATS process bus -*- lexical-binding: t; -*-

;; Part of malleable-control.  See docs/nats_local_process_bus_design.md.

;;; Commentary:

;; Maps `emacs.*' subjects onto editor operations, and publishes
;; `emacs.event.*' when editor state changes.
;;
;; This is the semantics half of the Emacs participant; `nats-client' is the
;; wire half and knows nothing of what lives here.
;;
;; Envelopes (parent design sections 7 and 10):
;;
;;   request   {"v":1,"args":{...}}
;;   reply ok  {"v":1,"ok":true,"result":{...}}
;;   reply err {"v":1,"ok":false,"error":{"code":"...","message":"..."}}
;;   event     {"v":1,"source":"emacs","ts":<unix-ms>,"data":{...}}
;;
;; Start with `M-x mc-emacs-start'.

;;; Code:

(require 'nats-client)
(require 'cl-lib)
(require 'subr-x)

(defgroup mc-emacs nil
  "Emacs participant on the local NATS process bus."
  :group 'communication
  :prefix "mc-emacs-")

(defcustom mc-emacs-url (or (getenv "MC_NATS_URL") "nats://127.0.0.1:4223")
  "Bus URL for the Emacs participant."
  :type 'string
  :group 'mc-emacs)

(defvar mc-emacs-connection nil
  "The live `nats-connection', or nil when not started.")

(defvar mc-emacs--last-buffer nil
  "Most recent buffer opened via `emacs.cmd.buffer.open'.")

(defconst mc-emacs-protocol-version 1)

;;;; Envelope

(defun mc-emacs--now-ms ()
  "Current time as integer milliseconds since the epoch."
  (truncate (* 1000 (float-time))))

(defun mc-emacs--parse-args (payload)
  "Return the `args' plist from request PAYLOAD, or nil.

A malformed or absent envelope yields nil rather than an error: a caller that
sends junk should get a clean error reply, not silence."
  (condition-case nil
      (let ((obj (json-parse-string (or payload "{}")
                                    :object-type 'plist
                                    :array-type 'list
                                    :null-object nil
                                    :false-object nil)))
        (plist-get obj :args))
    (error nil)))

(defun mc-emacs--ok (result)
  "Serialise a success reply carrying RESULT."
  (json-serialize `(:v ,mc-emacs-protocol-version :ok t :result ,result)))

(defun mc-emacs--err (code message)
  "Serialise a failure reply with CODE and MESSAGE."
  (json-serialize `(:v ,mc-emacs-protocol-version :ok :false
                    :error (:code ,code :message ,message))))

(defun mc-emacs--event-payload (data)
  "Serialise an event envelope carrying DATA."
  (json-serialize `(:v ,mc-emacs-protocol-version
                    :source "emacs"
                    :ts ,(mc-emacs--now-ms)
                    :data ,data)))

(defun mc-emacs-publish-event (subject data)
  "Publish DATA as an event on SUBJECT."
  (when (nats-connected-p mc-emacs-connection)
    (nats-publish mc-emacs-connection subject (mc-emacs--event-payload data))))

;;;; Handler registration

(defun mc-emacs--prompt-is-fatal (prompt &rest _)
  "Signal rather than let a bus handler ask the user PROMPT.

A participant has no user.  If a handler reaches `y-or-n-p' it will block
forever waiting on an answer nobody will give, and -- because that happens
inside the process filter -- it takes the whole client down with it: the
participant stops answering everything, silently.  Turning the prompt into an
error costs one failed request instead."
  (error "Handler required interactive confirmation: %s" prompt))

(defun mc-emacs--serve (subject fn)
  "Subscribe to SUBJECT, replying with whatever FN returns.

FN is called with the request `args' plist and must return a plist to be
wrapped in a success reply.  If FN signals, the error is caught and returned
as a failure reply -- a bad handler must never deafen the client."
  (nats-subscribe
   mc-emacs-connection subject
   (lambda (subj payload reply)
     (let ((response
            (condition-case err
                (cl-letf (((symbol-function 'y-or-n-p)
                           #'mc-emacs--prompt-is-fatal)
                          ((symbol-function 'yes-or-no-p)
                           #'mc-emacs--prompt-is-fatal))
                  (mc-emacs--ok (funcall fn (mc-emacs--parse-args payload))))
              (error (mc-emacs--err "handler-error"
                                    (error-message-string err))))))
       (if reply
           (nats-publish mc-emacs-connection reply response)
         ;; Fire-and-forget command: nothing to reply to, but the handler has
         ;; already run, which is the point.
         (mc-emacs--log "no reply-to on %s" subj))))))

(defun mc-emacs--log (fmt &rest args)
  "Append a line to `*mc-emacs*' formatted from FMT and ARGS."
  (with-current-buffer (get-buffer-create "*mc-emacs*")
    (goto-char (point-max))
    (insert (format-time-string "[%H:%M:%S] ")
            (apply #'format fmt args) "\n")))

;;;; Capability inventory
;;
;; Declared once, so that `emacs.query.capabilities' cannot drift away from
;; what is actually subscribed -- the same list drives both.

(defconst mc-emacs-commands
  '("emacs.cmd.buffer.open"
    "emacs.cmd.eval")
  "Command subjects this participant serves.")

(defconst mc-emacs-queries
  '("emacs.query.capabilities"
    "emacs.query.buffer.current"
    "emacs.query.buffer.contents")
  "Query subjects this participant serves.")

(defconst mc-emacs-events
  '("emacs.event.buffer.opened")
  "Event subjects this participant publishes.")

;;;; Handlers

(defun mc-emacs--current-buffer ()
  "Best guess at the buffer the user means.

In a windowed session that is the selected window's buffer.  In a daemon there
is no selected window worth trusting, so fall back to the last buffer opened
over the bus, then to the first non-internal buffer."
  (or (and (not noninteractive)
           (window-live-p (selected-window))
           (window-buffer (selected-window)))
      (and (buffer-live-p mc-emacs--last-buffer) mc-emacs--last-buffer)
      (seq-find (lambda (b) (not (string-prefix-p " " (buffer-name b))))
                (buffer-list))))

(defun mc-emacs--buffer-descriptor (buffer)
  "Return a plist describing BUFFER."
  (with-current-buffer buffer
    (list :name (buffer-name)
          :file (or (buffer-file-name) :null)
          :point (point)
          :line (line-number-at-pos)
          :size (buffer-size))))

(defun mc-emacs--handle-capabilities (_args)
  "Report what this participant serves.

Note the `vconcat': `json-serialize' renders a Lisp list as a JSON *object*,
so a bare list of subject names silently becomes malformed output.  Arrays
must be vectors."
  (list :commands (vconcat mc-emacs-commands)
        :queries (vconcat mc-emacs-queries)
        :events (vconcat mc-emacs-events)
        :pid (emacs-pid)
        :emacs (emacs-version)))

(defun mc-emacs--handle-buffer-current (_args)
  "Describe the current buffer."
  (let ((buf (mc-emacs--current-buffer)))
    (unless buf (error "No buffer available"))
    (mc-emacs--buffer-descriptor buf)))

(defun mc-emacs--handle-buffer-contents (args)
  "Return the text of the buffer named in ARGS, or the current one."
  (let* ((name (plist-get args :buffer))
         (buf (if name (get-buffer name) (mc-emacs--current-buffer))))
    (unless buf (error "No such buffer: %s" (or name "<current>")))
    (with-current-buffer buf
      (list :name (buffer-name)
            :file (or (buffer-file-name) :null)
            :text (buffer-substring-no-properties (point-min) (point-max))))))

(defun mc-emacs--open-file (path)
  "Return a buffer visiting PATH, without ever prompting.

`find-file-noselect' asks \"file changed on disk, reread?\" when a buffer
already visits PATH and the file has since changed underneath it.  That is a
perfectly reasonable question to ask a human and a fatal one to ask a daemon,
so decide it here: an unmodified buffer is reverted silently, and a modified
one is left alone and reported rather than quietly discarded."
  (let ((existing (get-file-buffer path)))
    (cond
     ((null existing) (find-file-noselect path))
     ((buffer-modified-p existing)
      (error "Buffer for %s has unsaved changes; refusing to reread" path))
     (t (with-current-buffer existing
          (revert-buffer :ignore-auto :noconfirm :preserve-modes)
          existing)))))

(defun mc-emacs--handle-buffer-open (args)
  "Open the file named in ARGS and announce it.

Never selects a window, so this behaves identically in a windowed Emacs and in
a daemon with no frame at all."
  (let ((path (plist-get args :path))
        (line (plist-get args :line)))
    (unless path (error "Missing required argument: path"))
    (let ((buf (mc-emacs--open-file (expand-file-name path))))
      (setq mc-emacs--last-buffer buf)
      (when line
        (with-current-buffer buf
          (goto-char (point-min))
          (forward-line (1- line))))
      (mc-emacs--log "opened %s" path)
      (mc-emacs-publish-event
       "emacs.event.buffer.opened"
       (list :path (expand-file-name path)
             :name (buffer-name buf)
             :size (buffer-size buf)))
      (mc-emacs--buffer-descriptor buf))))

(defun mc-emacs--handle-eval (args)
  "Evaluate the Lisp form in ARGS.

Escape hatch (parent design section 12).  Present for bootstrapping and
debugging; semantic subjects are the protocol."
  (let ((form (plist-get args :form)))
    (unless form (error "Missing required argument: form"))
    (list :value (format "%S" (eval (car (read-from-string form)) t)))))

;;;; Lifecycle

(defun mc-emacs--register-handlers ()
  "Register every `emacs.*' handler exactly once.

Deliberately NOT called from the client's on-connect hook.  The client already
restores its own subscriptions after a reconnect, so re-registering there
would add a second subscription per subject -- and Emacs would then answer
every request twice, which looks like a working system until something counts
the replies."
  (mc-emacs--serve "emacs.query.capabilities"     #'mc-emacs--handle-capabilities)
  (mc-emacs--serve "emacs.query.buffer.current"   #'mc-emacs--handle-buffer-current)
  (mc-emacs--serve "emacs.query.buffer.contents"  #'mc-emacs--handle-buffer-contents)
  (mc-emacs--serve "emacs.cmd.buffer.open"        #'mc-emacs--handle-buffer-open)
  (mc-emacs--serve "emacs.cmd.eval"               #'mc-emacs--handle-eval))

(defun mc-emacs--announce-connected (_conn)
  "Announce arrival.  Safe to run on every (re)connect."
  (mc-emacs-publish-event "system.event.client.connected"
                          (list :client "emacs" :pid (emacs-pid)))
  (mc-emacs--log "connected to %s" mc-emacs-url))

;;;###autoload
(defun mc-emacs-start ()
  "Connect Emacs to the local process bus."
  (interactive)
  (when (nats-connected-p mc-emacs-connection)
    (user-error "Already connected to %s" mc-emacs-url))
  (setq mc-emacs-connection
        (nats-connect :url mc-emacs-url
                      :name "emacs"
                      :on-connect #'mc-emacs--announce-connected))
  ;; Registered before the handshake completes on purpose: `nats-subscribe'
  ;; records the subscription and sends SUB once connected, so there is no
  ;; window where a request could arrive unserved.
  (mc-emacs--register-handlers)
  (message "mc-emacs: connecting to %s" mc-emacs-url)
  mc-emacs-connection)

;;;###autoload
(defun mc-emacs-stop ()
  "Announce departure and disconnect from the bus.

Core NATS has no last-will, so this graceful notice is the only
`system.event.client.disconnected' anyone will ever see -- a crashed Emacs
just goes quiet.  See the spec's \"known gap: presence\"."
  (interactive)
  (when mc-emacs-connection
    (mc-emacs-publish-event "system.event.client.disconnected"
                            (list :client "emacs" :pid (emacs-pid)))
    ;; Give the publish a moment to reach the socket before we close it.
    (accept-process-output (nats-connection-process mc-emacs-connection) 0.1)
    (nats-close mc-emacs-connection)
    (setq mc-emacs-connection nil)
    (message "mc-emacs: disconnected")))

;;;; Demo: Emacs as a requester

;;;###autoload
(defun mc-demo-ask-gt ()
  "Ask GT about its image and report the answer.

This is the Emacs-to-GT edge of the mesh: Emacs is not only a service here,
it is a client of other participants."
  (interactive)
  (unless (nats-connected-p mc-emacs-connection)
    (user-error "Not connected -- run M-x mc-emacs-start"))
  (let ((reply (nats-request-sync mc-emacs-connection
                                  "gt.query.image.info"
                                  (json-serialize '(:v 1 :args ())))))
    (if reply
        (progn (mc-emacs--log "gt.query.image.info -> %s" reply)
               (message "GT says: %s" reply)
               reply)
      (message "GT did not answer (is it running and connected?)")
      nil)))

(provide 'mc-emacs-service)

;;; mc-emacs-service.el ends here
