;;; nats-client-test.el --- Framing tests for nats-client -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests the wire parser with no server involved.  Framing is the part of a
;; NATS client that actually breaks: MSG carries a payload length in BYTES,
;; messages arrive split across arbitrary TCP reads, and several can land in
;; one read.  Each of those is a case below.
;;
;; Run with:
;;   emacs -Q --batch -L elisp -l ert -l elisp/nats-client-test.el \
;;         -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'nats-client)

(defun nats-test--connection ()
  "A connection with no socket, usable for driving the parser directly."
  (nats--make-connection :name "test" :host "127.0.0.1" :port 4223))

(defun nats-test--collector (conn sid subject)
  "Subscribe SID on CONN to SUBJECT, collecting deliveries into a list cell."
  (let ((seen (list nil)))
    (puthash sid
             (cons subject
                   (lambda (s payload reply)
                     (push (list s payload reply) (car seen))))
             (nats-connection-subs conn))
    seen))

(defun nats-test--feed (conn bytes)
  "Push BYTES into CONN's parser exactly as the process filter would."
  (setf (nats-connection-inbuf conn)
        (concat (nats-connection-inbuf conn) bytes))
  (nats--drain conn))

;;;; Header parsing

(ert-deftest nats-test-msg-header-without-reply ()
  (should (equal (nats--parse-msg-header "MSG foo.bar 1 11")
                 '("foo.bar" "1" nil 11))))

(ert-deftest nats-test-msg-header-with-reply ()
  (should (equal (nats--parse-msg-header "MSG foo.bar 1 _INBOX.abc.1 11")
                 '("foo.bar" "1" "_INBOX.abc.1" 11))))

(ert-deftest nats-test-msg-header-malformed-signals ()
  (should-error (nats--parse-msg-header "MSG foo.bar")))

;;;; Framing

(ert-deftest nats-test-delivers-a-whole-message ()
  (let* ((conn (nats-test--connection))
         (seen (nats-test--collector conn "1" "foo")))
    (nats-test--feed conn "MSG foo 1 5\r\nhello\r\n")
    (should (equal (car seen) '(("foo" "hello" nil))))))

(ert-deftest nats-test-message-split-across-reads ()
  "A message arriving in three TCP reads must still be delivered once, whole."
  (let* ((conn (nats-test--connection))
         (seen (nats-test--collector conn "1" "foo")))
    (nats-test--feed conn "MSG foo 1 ")
    (should (null (car seen)))
    (nats-test--feed conn "11\r\nhello")
    (should (null (car seen)))
    (nats-test--feed conn " world\r\n")
    (should (equal (car seen) '(("foo" "hello world" nil))))))

(ert-deftest nats-test-two-messages-in-one-read ()
  (let* ((conn (nats-test--connection))
         (seen (nats-test--collector conn "1" "foo")))
    (nats-test--feed conn "MSG foo 1 3\r\nabc\r\nMSG foo 1 3\r\ndef\r\n")
    (should (equal (car seen) '(("foo" "def" nil) ("foo" "abc" nil))))))

(ert-deftest nats-test-payload-length-is-bytes-not-characters ()
  "The regression that motivated making the whole client unibyte.

\"héllo ☃\" is 7 characters but 10 bytes.  A parser that measures the buffer
in characters desynchronises here and corrupts every message after it."
  (let* ((conn (nats-test--connection))
         (seen (nats-test--collector conn "1" "foo"))
         (payload (encode-coding-string "héllo ☃" 'utf-8)))
    (should (= (length payload) 10))
    (should (= (length "héllo ☃") 7))
    (nats-test--feed conn (concat "MSG foo 1 10\r\n" payload "\r\n"))
    (should (equal (car seen) '(("foo" "héllo ☃" nil))))))

(ert-deftest nats-test-reply-to-is-passed-through ()
  (let* ((conn (nats-test--connection))
         (seen (nats-test--collector conn "1" "foo")))
    (nats-test--feed conn "MSG foo 1 _INBOX.x.1 2\r\nhi\r\n")
    (should (equal (car seen) '(("foo" "hi" "_INBOX.x.1"))))))

(ert-deftest nats-test-raising-handler-does-not-stop-the-parser ()
  "One bad handler must not deafen the client for every later message."
  (let ((conn (nats-test--connection))
        (delivered nil))
    (puthash "1" (cons "boom" (lambda (&rest _) (error "handler blew up")))
             (nats-connection-subs conn))
    (puthash "2" (cons "fine" (lambda (&rest _) (setq delivered t)))
             (nats-connection-subs conn))
    (nats-test--feed conn "MSG boom 1 1\r\nx\r\nMSG fine 2 1\r\ny\r\n")
    (should delivered)))

(ert-deftest nats-test-unknown-sid-is-ignored ()
  (let ((conn (nats-test--connection)))
    (nats-test--feed conn "MSG nobody 99 2\r\nhi\r\n")
    (should (equal (nats-connection-inbuf conn) ""))))

;;;; Handshake gating

(ert-deftest nats-test-second-info-does-not-re-handshake ()
  "The server sends another INFO after CONNECT because we announce protocol 1.

Treating that as a second handshake subscribes everything twice and makes the
client reply twice to every request."
  (let ((conn (nats-test--connection))
        (handshakes 0))
    (cl-letf (((symbol-function 'nats--handshake)
               (lambda (c) (cl-incf handshakes)
                 (setf (nats-connection-connected c) t))))
      (nats--handle-line conn "INFO {\"server_id\":\"a\"}")
      (nats--handle-line conn "INFO {\"server_id\":\"a\"}")
      (should (= handshakes 1)))))

;;;; URL parsing

(ert-deftest nats-test-url-parsing ()
  (should (equal (nats--parse-url "nats://127.0.0.1:4223") '("127.0.0.1" . 4223)))
  (should (equal (nats--parse-url "localhost:4222") '("localhost" . 4222)))
  (should (equal (nats--parse-url "nats://example") '("example" . 4222))))

;;;; Publish framing

(ert-deftest nats-test-publish-frames-byte-length ()
  "PUB must advertise the UTF-8 byte count, not the character count."
  (let ((conn (nats-test--connection))
        (sent nil))
    (cl-letf (((symbol-function 'nats--send)
               (lambda (_c bytes) (setq sent bytes))))
      (nats-publish conn "foo" "héllo ☃")
      (should (string-prefix-p "PUB foo 10\r\n" sent))
      (nats-publish conn "foo" "hi" "_INBOX.x.1")
      (should (string-prefix-p "PUB foo _INBOX.x.1 2\r\n" sent)))))

(provide 'nats-client-test)

;;; nats-client-test.el ends here
