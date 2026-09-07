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

"Temps are declared here, at the top of the doit, NOT inside the protected
 block below. The on:do: handler references `note', and a handler block is
 outside the scope of the block it guards -- declaring them inside makes the
 whole file fail to compile with 'Undeclared variable'."
| home env note |
note := [ :text |
    | logName |
    logName := Smalltalk at: #McStartupLog ifAbsent: [ nil ].
    Transcript show: '[mc-gt] ' , text; cr.
    logName ifNotNil: [
      [ logName asFileReference writeStreamDo: [ :s |
          s setToEnd; nextPutAll: DateAndTime now printString , ' ' , text; lf ] ]
        on: Error do: [ :ignored | ] ] ].

[ home := Smalltalk at: #McHome ifAbsent: [ nil ].
  home ifNil: [
    env := [ Smalltalk os environment ] on: Error do: [ :e | nil ].
    env ifNotNil: [ home := env at: 'MC_HOME' ifAbsent: [ nil ] ] ].
  home
    ifNil: [ note value: 'MC_HOME unknown, not connecting' ]
    ifNotNil: [
      (home , '/pharo/NatsClient.st') asFileReference fileIn.
      (home , '/pharo/McGtService.st') asFileReference fileIn.
      (home , '/pharo/McGtPatches.st') asFileReference fileIn.
      (home , '/pharo/McLlmStream.st') asFileReference fileIn.
      (home , '/pharo/McLlm.st') asFileReference fileIn.
      "Core, and unconditional: every tool's class-side open compiles a
       reference to McWindow, so it has to be here before any of them is
       filed in -- including in a headless image, where the guarded block
       below never gets as far as the panel."
      (home , '/pharo/McWindow.st') asFileReference fileIn.
      note value: 'classes loaded from ' , home.
      "The launcher panel.  Guarded on its own: a headless image has no
       GtHome, so the extension method fails to compile there -- and a home
       screen that will not build must never stop the bus connection below."
      [ (home , '/pharo/McOffUi.st') asFileReference fileIn.
        (home , '/pharo/McLauncher.st') asFileReference fileIn.
        note value: 'launcher panel loaded' ]
        on: Error
        do: [ :e | note value: 'launcher panel not loaded: ' , e messageText printString ].
      "The bus lights.  Guarded separately from the launcher panel rather than
       folded into it: they are two independent home-screen sections, and one
       failing to compile must not cost you the other."
      [ (home , '/pharo/McBusStatus.st') asFileReference fileIn.
        note value: 'bus status panel loaded' ]
        on: Error
        do: [ :e | note value: 'bus status panel not loaded: ' , e messageText printString ].
      "Patches to GT's own code. Kept out of the image on purpose, so they
       are version controlled and reapplied every start. A patch that fails
       must not stop the bus connection below."
      [ note value: (Smalltalk at: #McGtPatches) apply ]
        on: Error
        do: [ :e | note value: 'patches failed: ' , e messageText printString ].
      "Forked: a down bus must not stall the image coming up."
      [ [ (Smalltalk at: #McGtService) start.
          note value: 'connected'.
          "The home screen was built and probed BEFORE this fork got here, so
           its lights say the bus is down -- which was true when they were
           drawn and is not any more.  Probing again on arrival is what stops
           every launch from showing three red lights until someone presses
           Check."
          (Smalltalk at: #McBusStatus ifAbsent: [ nil ])
            ifNotNil: [ :statusClass | statusClass current probe ] ]
          on: Error
          do: [ :e | note value: 'could not connect: ' , e messageText printString ] ] fork ] ]
  on: Error
  do: [ :e | note value: 'bootstrap failed: ' , e messageText printString ]!
