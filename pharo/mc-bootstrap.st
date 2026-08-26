"
malleable-control -- GT bus bootstrap.

Files in the NATS client and the GT service, then connects. Loaded either by
the installed startup script (see bin/gt-install-startup) or directly by
bin/gt-participant.

Two rules this file must never break:

  1. It must not block GT startup. Connecting is forked, so a bus that is down
     costs nothing -- GT comes up as usual and simply is not a participant.
  2. It must not break GT startup. Every failure is caught and reported to the
     Transcript. A broken bus must never be able to stop the image booting.

MC_HOME comes from the global McHome (set by the generated startup script) or
from the MC_HOME environment variable (set by bin/gt-participant).
"!

[ | home env |
  home := Smalltalk at: #McHome ifAbsent: [ nil ].
  home ifNil: [
    env := [ Smalltalk os environment ] on: Error do: [ :e | nil ].
    env ifNotNil: [ home := env at: 'MC_HOME' ifAbsent: [ nil ] ] ].
  home
    ifNil: [ Transcript show: '[mc-gt] MC_HOME unknown, not connecting'; cr ]
    ifNotNil: [
      (home , '/pharo/NatsClient.st') asFileReference fileIn.
      (home , '/pharo/McGtService.st') asFileReference fileIn.
      "Forked: a down bus must not stall the image coming up."
      [ [ (Smalltalk at: #McGtService) start ]
          on: Error
          do: [ :e | Transcript show: '[mc-gt] could not connect: ' , e messageText printString; cr ] ] fork ] ]
  on: Error
  do: [ :e | Transcript show: '[mc-gt] bootstrap failed: ' , e messageText printString; cr ]!
