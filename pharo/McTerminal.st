"
McTerminal -- Terminal emulator panel backed by tmux.

Creates a tmux session, polls its screen state at ~30 FPS via capture-pane,
renders the output as styled text with a visible cursor, and forwards all
keyboard input through send-keys.  Uses LibC system: for all subprocess
calls because GtSubprocessWithInMemoryOutput cannot launch processes from
within the running GT image.

Standalone:  (Smalltalk at: #McTerminal) open.
Hosted:      (Smalltalk at: #McWorkbench) open.
"!

Object subclass: #McTerminal
	instanceVariableNames: 'tmuxPath tmuxSession tmpFile rows cols termElement panel pollProcess running specialKeys symbolChars shiftSymbolChars shiftDigitChars'
	classVariableNames: ''
	package: 'MalleableControl'!

!McTerminal class methodsFor: 'opening'!
open
	| space term |
	term := self new.
	space := BlSpace new.
	space title: 'Terminal'.
	space extent: 820 @ 520.
	space root addChild: term buildPanel.
	term start.
	space show.
	^ term! !

!McTerminal methodsFor: 'initialization'!
initialize
	super initialize.
	rows := 24. cols := 80.
	running := false.
	tmuxPath := self detectTmux.
	tmpFile := '/tmp/mc-term-' , self identityHash printString.
	self buildKeyMaps!

detectTmux
	"Find the tmux binary by checking known paths.
	 GT subprocesses may not inherit the user login-shell PATH."
	#(  '$HOME/.nix-profile/bin/tmux'
		'/opt/homebrew/bin/tmux'
		'/usr/local/bin/tmux'
		'/usr/bin/tmux'
		'/bin/tmux' )
		do: [ :p | p asFileReference exists ifTrue: [ ^ p ] ].
	^ 'tmux'!

buildKeyMaps
	"Maps from BlKeyboardKey names to tmux send-keys arguments."
	specialKeys := Dictionary new.
	#(
		('Return' 'Enter') ('Escape' 'Escape') ('Tab' 'Tab')
		('Backspace' 'BSpace') ('BackSpace' 'BSpace')
		('Delete' 'DC') ('Space' 'Space')
		('ArrowUp' 'Up') ('ArrowDown' 'Down')
		('ArrowLeft' 'Left') ('ArrowRight' 'Right')
		('Home' 'Home') ('End' 'End')
		('PageUp' 'PPage') ('PageDown' 'NPage')
		('F1' 'F1') ('F2' 'F2') ('F3' 'F3') ('F4' 'F4')
		('F5' 'F5') ('F6' 'F6') ('F7' 'F7') ('F8' 'F8')
		('F9' 'F9') ('F10' 'F10') ('F11' 'F11') ('F12' 'F12')
	) do: [ :pair | specialKeys at: pair first put: pair second ].
	"Symbol keys: unshifted character."
	symbolChars := Dictionary new.
	#(
		('Semicolon' ';') ('Period' '.') ('Comma' ',') ('Slash' '/')
		('Backslash' '\') ('Grave' '`') ('BackQuote' '`')
		('Minus' '-') ('Equal' '=') ('Equals' '=')
		('LeftBracket' '[') ('RightBracket' ']')
	) do: [ :pair | symbolChars at: pair first put: pair second ].
	symbolChars at: 'Quote' put: (Character value: 39) asString.
	"Symbol keys: shifted character."
	shiftSymbolChars := Dictionary new.
	#(
		('Semicolon' ':') ('Period' '>') ('Comma' '<') ('Slash' '?')
		('Backslash' '|') ('Quote' '"') ('Grave' '~') ('BackQuote' '~')
		('Minus' '_') ('Equal' '+') ('Equals' '+')
		('LeftBracket' '{') ('RightBracket' '}')
	) do: [ :pair | shiftSymbolChars at: pair first put: pair second ].
	"Shift+digit to symbol (US keyboard)."
	shiftDigitChars := Dictionary new.
	#(('2' '@') ('3' '#') ('4' '$') ('5' '%')
	  ('6' '^') ('7' '&') ('8' '*') ('9' '(') ('0' ')'))
		do: [ :pair | shiftDigitChars at: pair first put: pair second ].
	shiftDigitChars at: '1' put: (Character value: 33) asString! !

!McTerminal methodsFor: 'building'!
buildPanel
	panel := BlElement new.
	panel layout: BlLinearLayout vertical.
	panel constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ].
	panel background: (Color fromHexString: '#0c0c14').
	termElement := BrEditor new.
	termElement aptitude: (BrGlamorousRegularEditorAptitude new
		foreground: (Color fromHexString: '#d3d7cf');
		fontSize: 14).
	termElement constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ].
	termElement background: (Color fromHexString: '#0c0c14').
	termElement padding: (BlInsets all: 4).
	"Intercept all keyboard input before the editor can process it."
	termElement addEventFilter: (BlEventHandler on: BlKeyDownEvent do: [ :event |
		self handleKeyDown: event.
		event consumed: true ]).
	termElement text: ('Terminal — click here, then type to interact' asRopedText
		foreground: (Color fromHexString: '#555570')).
	panel addChild: termElement.
	^ panel! !

!McTerminal methodsFor: 'lifecycle'!
start
	| exitCode |
	tmuxSession := 'mc-' , 99999 atRandom printString.
	[ exitCode := self fireTmux: { 'new-session'. '-d'. '-s'. tmuxSession.
			'-x'. cols printString. '-y'. rows printString }.
	  exitCode = 0
		ifTrue: [ running := true. self startPolling ]
		ifFalse: [ self showError: 'tmux session failed (exit ' , exitCode printString , ')' ] ]
	on: Error do: [ :e |
		self showError: 'tmux start error: ' , e messageText ]!

stop
	running := false.
	tmuxSession ifNotNil: [
		[ self fireTmux: { 'kill-session'. '-t'. tmuxSession } ]
			on: Error do: [ :e | ] ].
	[ tmpFile asFileReference delete ] on: Error do: [ :e | ]!

startPolling
	pollProcess := [
		[ running ] whileTrue: [
			[ self pollOnce ] on: Error do: [ :e |
				self showError: e messageText ].
			33 milliSeconds wait ]
	] forkAt: Processor userBackgroundPriority named: 'mc-terminal-poll'!

pollOnce
	| output cursor styled |
	output := self capturePane.
	output ifNil: [ ^ self ].
	cursor := self getCursorPosition.
	styled := self renderOutput: output cursor: cursor.
	panel space ifNotNil: [ :sp |
		sp enqueueTask: (BlTaskAction new action: [
			termElement text: styled ]) ]!

showError: aString
	"Display an error message in the terminal panel."
	panel space ifNotNil: [ :sp |
		sp enqueueTask: (BlTaskAction new action: [
			termElement text: (aString asRopedText foreground: Color red; fontSize: 13) ]) ]! !

!McTerminal methodsFor: 'tmux'!
runTmux: anArray
	"Run tmux with args, return stdout via LibC system: and a temp file."
	| exitCode result |
	exitCode := LibC uniqueInstance system: (self buildShellCommand: anArray) , ' >' , tmpFile.
	exitCode = 0
		ifTrue: [ [ result := tmpFile asFileReference contents ]
			on: Error do: [ :e | result := nil ] ]
		ifFalse: [ result := nil ].
	^ result!

fireTmux: anArray
	"Run tmux with args, return exit code."
	^ LibC uniqueInstance system: (self buildShellCommand: anArray)!

buildShellCommand: anArray
	"Build a shell command string with proper quoting."
	^ String streamContents: [ :s |
		self shellQuote: tmuxPath on: s.
		anArray do: [ :arg |
			s nextPut: $ .
			self shellQuote: arg on: s ] ]!

shellQuote: aString on: aStream
	"Single-quote a string for POSIX shell."
	| q |
	q := Character value: 39.
	aStream nextPut: q.
	aString do: [ :ch |
		ch = q
			ifTrue: [ aStream nextPut: q; nextPut: $\; nextPut: q; nextPut: q ]
			ifFalse: [ aStream nextPut: ch ] ].
	aStream nextPut: q!

capturePane
	^ self runTmux: { 'capture-pane'. '-t'. tmuxSession. '-p' }!

getCursorPosition
	"Return col@row, both 0-based."
	| output parts |
	output := self runTmux: { 'display-message'. '-t'. tmuxSession. '-p'. '#{cursor_x},#{cursor_y}' }.
	output ifNil: [ ^ 0 @ 0 ].
	output := output trim.
	parts := $, split: output.
	parts size < 2 ifTrue: [ ^ 0 @ 0 ].
	^ parts first asInteger @ parts second asInteger!

sendTmuxKey: aKeyName
	"Send a named key (Enter, Escape, Up, etc.)."
	running ifFalse: [ ^ self ].
	[ self fireTmux: { 'send-keys'. '-t'. tmuxSession. aKeyName } ] fork!

sendTmuxLiteral: aString
	"Send literal text (no key-name interpretation)."
	(running and: [ aString isNotEmpty ]) ifFalse: [ ^ self ].
	[ self fireTmux: { 'send-keys'. '-t'. tmuxSession. '-l'. aString } ] fork! !

!McTerminal methodsFor: 'rendering'!
renderOutput: output cursor: cursorPoint
	"Build styled text from the plain-text capture-pane output,
	 highlighting the cursor position with inverse video."
	| text lines cursorRow cursorCol defaultFg |
	text := '' asRopedText.
	lines := output lines.
	cursorCol := cursorPoint x + 1.  "convert to 1-based"
	cursorRow := cursorPoint y + 1.
	defaultFg := Color fromHexString: '#d3d7cf'.
	1 to: rows do: [ :row |
		| line |
		line := row <= lines size ifTrue: [ lines at: row ] ifFalse: [ '' ].
		"Pad to full width for consistent rendering."
		line size < cols ifTrue: [
			line := line , (String new: cols - line size withAll: $ ) ].
		line size > cols ifTrue: [ line := line copyFrom: 1 to: cols ].
		row = cursorRow ifTrue: [
			| before cursor after |
			before := (cursorCol > 1
				ifTrue: [ line copyFrom: 1 to: cursorCol - 1 ]
				ifFalse: [ '' ]) asRopedText foreground: defaultFg.
			cursor := (line copyFrom: cursorCol to: (cursorCol min: line size)) asRopedText
				background: defaultFg;
				foreground: (Color fromHexString: '#0c0c14').
			after := (cursorCol < line size
				ifTrue: [ line copyFrom: cursorCol + 1 to: line size ]
				ifFalse: [ '' ]) asRopedText foreground: defaultFg.
			text append: before. text append: cursor. text append: after ]
		ifFalse: [
			text append: (line asRopedText foreground: defaultFg) ].
		row < rows ifTrue: [ text append: String lf asRopedText ] ].
	^ text! !

!McTerminal methodsFor: 'keyboard'!
handleKeyDown: event
	"Map a Bloc key event to a tmux send-keys call."
	| key keyName shift ctrl |
	running ifFalse: [ ^ self ].
	key := event key.
	keyName := key name.
	shift := event modifiers isShift.
	ctrl := [ event modifiers isCtrl ] on: MessageNotUnderstood
		do: [ :e | [ event modifiers isControl ] on: MessageNotUnderstood do: [ :e2 | false ] ].
	"Ctrl combinations: C-a through C-z."
	(ctrl and: [ keyName size = 1 and: [ (keyName at: 1) isLetter ] ]) ifTrue: [
		^ self sendTmuxKey: 'C-' , keyName asLowercase ].
	"Special keys (Return, Escape, arrows, etc.)."
	(specialKeys at: keyName ifAbsent: [ nil ]) ifNotNil: [ :tmuxKey |
		^ self sendTmuxKey: tmuxKey ].
	"Letter keys."
	(keyName size = 1 and: [ (keyName at: 1) isLetter ]) ifTrue: [
		^ self sendTmuxLiteral: (shift ifTrue: [ keyName asUppercase ] ifFalse: [ keyName asLowercase ]) ].
	"Digit keys."
	(keyName size = 1 and: [ (keyName at: 1) isDigit ]) ifTrue: [
		^ self sendTmuxLiteral: (shift
			ifTrue: [ shiftDigitChars at: keyName ifAbsent: [ keyName ] ]
			ifFalse: [ keyName ]) ].
	"Symbol keys (semicolon, period, slash, brackets, etc.)."
	shift ifTrue: [
		(shiftSymbolChars at: keyName ifAbsent: [ nil ]) ifNotNil: [ :ch |
			^ self sendTmuxLiteral: ch ] ].
	(symbolChars at: keyName ifAbsent: [ nil ]) ifNotNil: [ :ch |
		^ self sendTmuxLiteral: ch ]! !

!McTerminal methodsFor: 'accessing'!
tmuxSession
	^ tmuxSession!

panel
	^ panel!

termElement
	^ termElement!

isRunning
	^ running! !
