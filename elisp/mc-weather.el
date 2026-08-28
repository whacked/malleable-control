;;; mc-weather.el --- Weather station: Emacs triggers GT, GT fetches and reports back -*- lexical-binding: t; -*-

;; Part of malleable-control.

;;; Commentary:

;; Emacs asks GT to open a weather view.  GT auto-detects the user's location,
;; fetches the current weather from Open-Meteo (free, no API key), renders
;; temperature and conditions with vector Bloc icons, and publishes
;; `gt.event.weather' back over the bus.  This file subscribes to that event
;; so the temperature also appears in the Emacs minibuffer.
;;
;; Usage from Emacs (after mc-emacs-start):
;;
;;   (require 'mc-weather)
;;   (mc-weather-open)          ; opens the GT view and subscribes
;;   mc-weather--last           ; last weather plist received

;;; Code:

(require 'mc-emacs-service)

(defvar mc-weather-home
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name
                             (locate-library "mc-weather")
                             (buffer-file-name)))))
  "Root of the malleable-control project.")

(defvar mc-weather--subscription nil
  "NATS subscription id for gt.event.weather, or nil.")

(defvar mc-weather--last nil
  "Last weather report received from GT, as a plist.")

(defun mc-weather--ensure-subscription ()
  "Subscribe to weather events from GT if not already listening."
  (when (and mc-emacs-connection
             (nats-connected-p mc-emacs-connection)
             (null mc-weather--subscription))
    (setq mc-weather--subscription
          (nats-subscribe mc-emacs-connection "gt.event.weather"
            (lambda (_subject payload _reply)
              (condition-case err
                  (let* ((envelope (json-parse-string payload
                                    :object-type 'plist
                                    :null-object nil
                                    :false-object nil))
                         (data (plist-get envelope :data)))
                    (setq mc-weather--last data)
                    (mc-emacs--log "weather: %s°F at %s (%s)"
                                  (plist-get data :temperature)
                                  (plist-get data :location)
                                  (plist-get data :description))
                    (message "GT weather: %s°F — %s — %s"
                             (plist-get data :temperature)
                             (plist-get data :description)
                             (plist-get data :location)))
                (error
                 (mc-emacs--log "weather event error: %S" err))))))))

;;;###autoload
(defun mc-weather-open ()
  "Load the weather view into GT and open it.

Subscribes to `gt.event.weather' so that when the user clicks Fetch
Weather in the GT window, the reading also appears in the Emacs
minibuffer."
  (interactive)
  (unless (nats-connected-p mc-emacs-connection)
    (user-error "Not connected — run M-x mc-emacs-start"))
  (mc-weather--ensure-subscription)
  (let* ((st-path (expand-file-name "pharo/McWeatherView.st" mc-weather-home))
         (expr (format "'%s' asFileReference fileIn. (Smalltalk at: #McWeatherView) open. 'opened'"
                       st-path))
         (reply (nats-request-sync mc-emacs-connection "gt.cmd.eval"
                  (json-serialize `(:v 1 :args (:expression ,expr))))))
    (if reply
        (message "Weather view opened in GT")
      (message "GT did not respond (is it running?)"))))

(provide 'mc-weather)

;;; mc-weather.el ends here
