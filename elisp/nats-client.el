;;; nats-client.el --- Core NATS protocol client for Emacs -*- lexical-binding: t; -*-

;; Part of malleable-control.  See docs/nats_local_process_bus_design.md.

;;; Commentary:

;; A native Core NATS client built on `make-network-process'.  No external
;; process, no C module, no dependency beyond Emacs itself.
;;
;; This file speaks the wire protocol and nothing else.  It has no opinion
;; about subject naming, JSON, or what any message means -- that lives in
;; `mc-emacs-service'.  Keeping the seam here is what lets the subject
;; namespace churn in later phases without touching protocol code.
;;
;; Wire protocol (client -> server):
;;
;;   CONNECT {json}\r\n
;;   PUB <subject> [reply-to] <#bytes>\r\n<payload>\r\n
;;   SUB <subject> [queue] <sid>\r\n
;;   UNSUB <sid> [max]\r\n
;;   PING\r\n / PONG\r\n
;;
;; Wire protocol (server -> client):
;;
;;   INFO {json}\r\n
;;   MSG <subject> <sid> [reply-to] <#bytes>\r\n<payload>\r\n
;;   +OK / -ERR <msg> / PING / PONG
;;
;; EVERYTHING HERE IS UNIBYTE.  `MSG' carries a payload length in *bytes*,
;; while Emacs process filters will happily hand back multibyte strings whose
;; `length' is characters.  Get that wrong and the parser desynchronises the
;; moment anyone sends a non-ASCII payload, which is a miserable bug to chase.
;; So: the process coding system is binary, the accumulation buffer is
;; unibyte, and UTF-8 encode/decode happens only at the publish/dispatch edge.

;;; Code:

(require 'cl-lib)

(defgroup nats nil
  "Core NATS client."
  :group 'communication
  :prefix "nats-")

(defcustom nats-default-url "nats://127.0.0.1:4223"
  "Default bus URL.  Port 4223, not 4222, to avoid colliding with other servers."
  :type 'string
  :group 'nats)

(defcustom nats-request-timeout 5.0
  "Seconds to wait for a reply before a request is considered failed."
  :type 'number
  :group 'nats)

(defcustom nats-verbose nil
  "When non-nil, log every frame to the `*nats-log*' buffer."
  :type 'boolean
  :group 'nats)

(defconst nats-max-reconnect-delay 30.0
  "Ceiling on reconnect backoff, in seconds.")

(cl-defstruct (nats-connection (:constructor nats--make-connection)
                               (:copier nil))
  name host port process
  (inbuf "")            ; unibyte accumulation buffer
  (pending nil)         ; mid-MSG state: (SUBJECT SID REPLY LEN)
  (sid-counter 0)
  (subs (make-hash-table :test #'equal))      ; sid string -> (SUBJECT . HANDLER)
  (requests (make-hash-table :test #'equal))  ; inbox subject -> (CALLBACK . TIMER)
  inbox-prefix
  inbox-sid
  (request-counter 0)
  (reconnect-delay 0.5)
  (reconnect-timer nil)
  (connected nil)
  on-connect
  on-disconnect)

;;;; Logging

(defun nats--log (conn fmt &rest args)
  "Append a formatted line to `*nats-log*' when `nats-verbose' is on.
CONN names the connection; FMT and ARGS are as for `format'."
  (when nats-verbose
    (with-current-buffer (get-buffer-create "*nats-log*")
      (goto-char (point-max))
      (insert (format "[%s] %s\n"
                      (if conn (nats-connection-name conn) "-")
                      (apply #'format fmt args))))))

;;;; Byte helpers

(defun nats--to-bytes (s)
  "Return S as a unibyte string, UTF-8 encoding it only if it is multibyte."
  (cond ((null s) "")
        ((multibyte-string-p s) (encode-coding-string s 'utf-8))
        (t s)))

(defun nats--from-bytes (s)
  "Decode unibyte string S as UTF-8."
  (decode-coding-string s 'utf-8))

(defconst nats--crlf (unibyte-string ?\r ?\n))

(defun nats--send (conn bytes)
  "Write unibyte BYTES to CONN's socket, if it is live."
  (let ((proc (nats-connection-process conn)))
    (when (and proc (process-live-p proc))
      (nats--log conn "-> %s" bytes)
      (process-send-string proc bytes))))

(defun nats--send-line (conn line)
  "Send control LINE to CONN, appending CRLF."
  (nats--send conn (concat (nats--to-bytes line) nats--crlf)))

;;;; URL parsing

(defun nats--parse-url (url)
  "Split URL into a (HOST . PORT) cons."
  (if (string-match "\\`\\(?:nats://\\)?\\([^:/]+\\)\\(?::\\([0-9]+\\)\\)?" url)
      (cons (match-string 1 url)
            (string-to-number (or (match-string 2 url) "4222")))
    (error "Unparseable NATS url: %s" url)))

;;;; Connection lifecycle

;;;###autoload
(cl-defun nats-connect (&key (url nats-default-url) (name "emacs")
                             on-connect on-disconnect)
  "Open a connection to the NATS server at URL and return it.

NAME identifies this client to the server.  ON-CONNECT is called with the
connection once the handshake completes -- register subscriptions there, not
before, so that they are re-established automatically after a reconnect.
ON-DISCONNECT is called with the connection when the socket drops."
  (let* ((hp (nats--parse-url url))
         (conn (nats--make-connection
                :name name :host (car hp) :port (cdr hp)
                :on-connect on-connect :on-disconnect on-disconnect)))
    (setf (nats-connection-inbox-prefix conn)
          (format "_INBOX.%s" (nats--new-id)))
    (nats--open-socket conn)
    conn))

(defun nats--new-id ()
  "Return a short random identifier."
  (let ((chars "abcdefghijklmnopqrstuvwxyz0123456789"))
    (apply #'string
           (cl-loop repeat 12 collect (aref chars (random (length chars)))))))

(defun nats--open-socket (conn)
  "Open (or re-open) CONN's TCP socket."
  (setf (nats-connection-inbuf conn) ""
        (nats-connection-pending conn) nil
        (nats-connection-connected conn) nil)
  (let ((proc (condition-case err
                  (make-network-process
                   :name (format "nats-%s" (nats-connection-name conn))
                   :host (nats-connection-host conn)
                   :service (nats-connection-port conn)
                   :coding '(binary . binary)
                   :nowait nil
                   :noquery t
                   :filter #'nats--filter
                   :sentinel #'nats--sentinel)
                (error
                 (nats--log conn "connect failed: %S" err)
                 nil))))
    (if (null proc)
        (nats--schedule-reconnect conn)
      (process-put proc 'nats-connection conn)
      (setf (nats-connection-process conn) proc))))

(defun nats-close (conn)
  "Close CONN and cancel any reconnect attempt.  Safe to call twice."
  (when-let ((timer (nats-connection-reconnect-timer conn)))
    (cancel-timer timer)
    (setf (nats-connection-reconnect-timer conn) nil))
  (setf (nats-connection-connected conn) nil)
  (when-let ((proc (nats-connection-process conn)))
    (set-process-sentinel proc #'ignore)
    (when (process-live-p proc) (delete-process proc)))
  (setf (nats-connection-process conn) nil))

(defun nats-connected-p (conn)
  "Return non-nil when CONN has completed its handshake."
  (and conn (nats-connection-connected conn)))

(defun nats--sentinel (proc event)
  "Handle socket state change EVENT for PROC by scheduling a reconnect."
  (let ((conn (process-get proc 'nats-connection)))
    (when (and conn (not (process-live-p proc)))
      (nats--log conn "socket closed: %s" (string-trim event))
      (setf (nats-connection-connected conn) nil)
      (when-let ((f (nats-connection-on-disconnect conn)))
        (condition-case err (funcall f conn)
          (error (nats--log conn "on-disconnect raised: %S" err))))
      (nats--schedule-reconnect conn))))

(defun nats--schedule-reconnect (conn)
  "Arrange to retry CONN after its current backoff, then double the backoff.

A dropped bus must never wedge Emacs, so this is a plain timer: the retry
happens on the idle loop and a failure just schedules the next one."
  (unless (nats-connection-reconnect-timer conn)
    (let ((delay (nats-connection-reconnect-delay conn)))
      (nats--log conn "reconnecting in %.1fs" delay)
      (setf (nats-connection-reconnect-timer conn)
            (run-at-time delay nil
                         (lambda ()
                           (setf (nats-connection-reconnect-timer conn) nil)
                           (nats--open-socket conn))))
      (setf (nats-connection-reconnect-delay conn)
            (min nats-max-reconnect-delay (* 2 delay))))))

;;;; Parser

(defun nats--filter (proc string)
  "Accumulate STRING from PROC and drain complete frames out of it."
  (let ((conn (process-get proc 'nats-connection)))
    (when conn
      (setf (nats-connection-inbuf conn)
            (concat (nats-connection-inbuf conn) string))
      (nats--drain conn))))

(defun nats--drain (conn)
  "Consume as many whole frames as CONN's buffer currently holds.

Two states: either we are waiting on the payload of a `MSG' we have already
parsed the header of, or we are waiting on the next CRLF-terminated control
line.  Anything short of a whole frame is left in the buffer for next time."
  (catch 'nats--need-more
    (while t
      (let ((pending (nats-connection-pending conn))
            (buf (nats-connection-inbuf conn)))
        (if pending
            (cl-destructuring-bind (subject sid reply len) pending
              ;; len payload bytes, then a trailing CRLF.
              (when (< (length buf) (+ len 2))
                (throw 'nats--need-more nil))
              (let ((payload (substring buf 0 len)))
                (setf (nats-connection-inbuf conn) (substring buf (+ len 2))
                      (nats-connection-pending conn) nil)
                (nats--dispatch conn subject sid reply payload)))
          (let ((idx (string-search nats--crlf buf)))
            (unless idx (throw 'nats--need-more nil))
            (let ((line (substring buf 0 idx)))
              (setf (nats-connection-inbuf conn) (substring buf (+ idx 2)))
              (nats--handle-line conn line))))))))

(defun nats--handle-line (conn line)
  "Act on one control LINE received on CONN."
  (nats--log conn "<- %s" line)
  (cond
   ((string-prefix-p "MSG " line)
    (setf (nats-connection-pending conn) (nats--parse-msg-header line)))
   ((string-prefix-p "PING" line)
    (nats--send-line conn "PONG"))
   ((string-prefix-p "PONG" line) nil)
   ((string-prefix-p "INFO " line)
    ;; Only the FIRST INFO on a socket is a handshake cue. Because we announce
    ;; protocol 1 we opt into async INFO updates, so the server sends another
    ;; INFO right after CONNECT -- handshaking on that one too would subscribe
    ;; everything twice and reply twice to every request.
    (unless (nats-connection-connected conn)
      (nats--handshake conn)))
   ((string-prefix-p "+OK" line) nil)
   ((string-prefix-p "-ERR" line)
    (message "nats: server error: %s" line))
   (t nil)))

(defun nats--parse-msg-header (line)
  "Parse a `MSG' header LINE into (SUBJECT SID REPLY LEN).

Both forms are accepted:
  MSG <subject> <sid> <#bytes>
  MSG <subject> <sid> <reply-to> <#bytes>"
  (let ((parts (split-string line " " t)))
    (pcase (length parts)
      (4 (list (nth 1 parts) (nth 2 parts) nil
               (string-to-number (nth 3 parts))))
      (5 (list (nth 1 parts) (nth 2 parts) (nth 3 parts)
               (string-to-number (nth 4 parts))))
      (_ (error "Malformed MSG header: %s" line)))))

(defun nats--dispatch (conn subject sid reply payload)
  "Route a delivered message on CONN to its subscriber or pending request.

SUBJECT, SID, REPLY and PAYLOAD are as delivered by the server; PAYLOAD is a
unibyte string and is decoded to text here, at the protocol edge."
  (let ((text (nats--from-bytes payload)))
    (if (equal sid (nats-connection-inbox-sid conn))
        (nats--resolve-request conn subject text)
      (when-let ((entry (gethash sid (nats-connection-subs conn))))
        (condition-case err
            (funcall (cdr entry) subject text reply)
          ;; A raising handler must not take down the read loop -- one bad
          ;; subject handler should not silently deafen the whole client.
          (error
           (nats--log conn "handler for %s raised: %S" subject err)
           (message "nats: handler for %s raised: %S" subject err)))))))

(defun nats--handshake (conn)
  "Send CONNECT after INFO, then restore CONN's subscriptions."
  (nats--send-line
   conn
   (concat "CONNECT "
           (json-serialize
            `(:verbose ,:false :pedantic ,:false :tls_required ,:false
              :name ,(nats-connection-name conn)
              :lang "elisp" :version "0.1" :protocol 1))))
  (nats--send-line conn "PING")
  (setf (nats-connection-connected conn) t
        (nats-connection-reconnect-delay conn) 0.5)
  ;; Re-SUB everything we had before the drop.  Subscriptions are owned by the
  ;; connection, not by the socket, so a reconnect is invisible to callers.
  (let ((inbox-sid (nats--next-sid conn)))
    (setf (nats-connection-inbox-sid conn) inbox-sid)
    (nats--send-line
     conn (format "SUB %s.* %s" (nats-connection-inbox-prefix conn) inbox-sid)))
  (maphash (lambda (sid entry)
             (nats--send-line conn (format "SUB %s %s" (car entry) sid)))
           (nats-connection-subs conn))
  (when-let ((f (nats-connection-on-connect conn)))
    (condition-case err (funcall f conn)
      (error (nats--log conn "on-connect raised: %S" err)))))

(defun nats--next-sid (conn)
  "Return the next subscription id for CONN, as a string."
  (number-to-string (cl-incf (nats-connection-sid-counter conn))))

;;;; Public API

(defun nats-publish (conn subject payload &optional reply-to)
  "Publish PAYLOAD to SUBJECT on CONN, optionally naming REPLY-TO."
  (let* ((body (nats--to-bytes payload))
         (header (nats--to-bytes
                  (if reply-to
                      (format "PUB %s %s %d" subject reply-to (length body))
                    (format "PUB %s %d" subject (length body))))))
    (nats--send conn (concat header nats--crlf body nats--crlf))))

(defun nats-subscribe (conn subject handler)
  "Subscribe CONN to SUBJECT, calling HANDLER for each message.

HANDLER receives (SUBJECT PAYLOAD REPLY-TO); REPLY-TO is nil unless the sender
asked for a reply.  Returns a subscription id for `nats-unsubscribe'.

The subscription is recorded on the connection, so it survives reconnects."
  (let ((sid (nats--next-sid conn)))
    (puthash sid (cons subject handler) (nats-connection-subs conn))
    (when (nats-connected-p conn)
      (nats--send-line conn (format "SUB %s %s" subject sid)))
    sid))

(defun nats-unsubscribe (conn sid)
  "Cancel subscription SID on CONN."
  (remhash sid (nats-connection-subs conn))
  (when (nats-connected-p conn)
    (nats--send-line conn (format "UNSUB %s" sid))))

(defun nats-request (conn subject payload callback &optional timeout)
  "Send PAYLOAD to SUBJECT on CONN and call CALLBACK with the reply.

CALLBACK receives the reply payload as a string, or nil if TIMEOUT (default
`nats-request-timeout') elapses first.  Returns the inbox subject used."
  (let* ((inbox (format "%s.%d"
                        (nats-connection-inbox-prefix conn)
                        (cl-incf (nats-connection-request-counter conn))))
         (timer (run-at-time (or timeout nats-request-timeout) nil
                             (lambda () (nats--resolve-request conn inbox nil)))))
    (puthash inbox (cons callback timer) (nats-connection-requests conn))
    (nats-publish conn subject payload inbox)
    inbox))

(defun nats--resolve-request (conn inbox text)
  "Settle the pending request on INBOX for CONN with TEXT (nil means timeout)."
  (when-let ((entry (gethash inbox (nats-connection-requests conn))))
    (remhash inbox (nats-connection-requests conn))
    (when (cdr entry) (cancel-timer (cdr entry)))
    (condition-case err
        (funcall (car entry) text)
      (error (nats--log conn "request callback raised: %S" err)))))

(defun nats-request-sync (conn subject payload &optional timeout)
  "Send PAYLOAD to SUBJECT on CONN and block until the reply arrives.

Returns the reply string, or nil on timeout.  Intended for interactive and
batch use; prefer `nats-request' anywhere responsiveness matters."
  (let* ((limit (or timeout nats-request-timeout))
         (done nil) (result nil))
    (nats-request conn subject payload
                  (lambda (reply) (setq result reply done t))
                  limit)
    (let ((deadline (+ (float-time) limit 0.5)))
      (while (and (not done) (< (float-time) deadline))
        (accept-process-output (nats-connection-process conn) 0.05)))
    result))

(defun nats-wait-for-connection (conn &optional timeout)
  "Block until CONN completes its handshake.  Return non-nil on success."
  (let ((deadline (+ (float-time) (or timeout 5.0))))
    (while (and (not (nats-connected-p conn)) (< (float-time) deadline))
      (accept-process-output (nats-connection-process conn) 0.05))
    (nats-connected-p conn)))

(provide 'nats-client)

;;; nats-client.el ends here
