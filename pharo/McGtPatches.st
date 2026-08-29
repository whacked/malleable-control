"
malleable-control -- patches applied to Glamorous Toolkit's own code.

These are overrides of upstream GT methods, kept here rather than saved into
the image so they are version controlled and reapplied on every start (see
mc-bootstrap.st). Each patch says which defect it repairs.

Applying is idempotent -- McGtPatches apply can be run any number of times,
including over the bus into a running image.
"!

Object subclass: #McGtPatches
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McGtPatches class methodsFor: 'llm setup page'!
llmSetupPageTitles
	"Titles the LLM setup page has shipped under, newest first."
	^ #('How to setup LLM connections for the Moldable Agent Harness'
		'How to setup LLM connections')! !

!McGtPatches class methodsFor: 'llm setup page'!
llmSetupPage
	"The GT Book page explaining how to set up LLM connections, or nil.

	 The two 'Setup LLM connections' buttons looked this page up by a title
	 that upstream had since renamed, so pageNamed: signalled KeyNotFound
	 out of the button's action block and GT opened a debugger. Try each
	 known title, then fall back to a substring match, so the next rename
	 degrades quietly instead of raising."
	| db |
	db := [ LeDatabase gtBook ] on: Error do: [ :e | nil ].
	db ifNil: [ ^ nil ].
	self llmSetupPageTitles
		do: [ :each |
			(db pageNamed: each ifAbsent: [ nil ])
				ifNotNil: [ :page | ^ page ] ].
	^ [ db pages
		detect: [ :p | p title asLowercase includesSubstring: 'setup llm connections' ]
		ifNone: [ nil ] ] on: Error do: [ :e | nil ]! !

!McGtPatches class methodsFor: 'llm setup page'!
spawnLlmSetupFrom: aButton
	"Open the LLM setup page next to aButton. With no page to open, show the
	 connection registry itself -- that is where the connections live, so it
	 is a useful destination rather than a dead end."
	| page |
	page := self llmSetupPage.
	page
		ifNil: [ BlSpace spawnObject: GtLlmConnectionRegistry uniqueInstance from: aButton ]
		ifNotNil: [ BlSpace spawnPage: page from: aButton ]! !

!McGtPatches class methodsFor: 'llm setup page'!
spawnLlmSetupInNewSpaceFrom: aButton
	"As spawnLlmSetupFrom:, for the call site that opens its own window."
	| page space |
	page := self llmSetupPage.
	space := BlSpace new withCommonSettings.
	page
		ifNil: [ space spawnObject: GtLlmConnectionRegistry uniqueInstance from: aButton ]
		ifNotNil: [ space spawnPage: page from: aButton ]! !

!McGtPatches class methodsFor: 'applying'!
apply
	"Reapply every patch. Idempotent."
	| repaired refreshed |
	self patchGtHomeLlmCard.
	self patchChatRegistryEmptyConnections.
	self patchLocalConnectorDiscovery.
	self patchErrorMessageSerialization.
	self patchAssistantTurnSerialization.
	self patchStreamingViewSwap.
	self patchMacOsEditorKeymap.
	self patchMicrodownEmptyTable.
	self emacsEditorKeymapEnabled ifTrue: [ self applyEmacsEditorKeymap ].
	repaired := self repairOpenButtons.
	self applyRememberedLlmDefault.
	refreshed := self refreshHome.
	^ 'McGtPatches applied (' , repaired printString , ' open button(s) rebound, '
		, refreshed printString , ' home(s) refreshed)'! !

!McGtPatches class methodsFor: 'applying'!
patchMicrodownEmptyTable
	"MicTableBlock >> closeMe takes `rows first size' without checking that
	 there are any rows, so parsing a table that contributed none raises
	 SubscriptOutOfBounds.

	 A row is contributed only by a line the block did not read as a header
	 separator, and isHeader: answers true for any line of pipes, dashes and
	 spaces -- including a bare `|'.  So the moment a table row is begun by
	 typing a single pipe, Microdown throws, which for a live styler means
	 the whole document loses its styling for as long as the row is
	 incomplete.  Guard the empty case; an empty table simply has no rows to
	 normalise.

	 Body is upstream's, with only the guard added."
	(Smalltalk at: #MicTableBlock ifAbsent: [ nil ]) ifNil: [ ^ self ].
	(Smalltalk at: #MicTableBlock)
		compile: 'closeMe
	| firstSize |
	rows isEmpty ifTrue: [ ^ self ].
	firstSize := rows first size.
	rows := rows collect: [ :each | self cut: each toSize: firstSize ].
	rows := rows collect: [ :each |
		each collect: [ :e | self inlineParse: e ] ]'
		classified: 'malleable-control patch'! !

!McGtPatches class methodsFor: 'applying'!
patchGtHomeLlmCard
	"GtHome's 'Get started' section: the card whose button raised KeyNotFound.
	 Body is upstream's, with only the action block redirected."
	(Smalltalk at: #GtHomeMultiCardGetStartedSection ifAbsent: [ nil ])
		ifNil: [ ^ self ].
	(Smalltalk at: #GtHomeMultiCardGetStartedSection)
		compile: 'llmNoConnectionsCardElement
	| container label button |
	container := BrVerticalPane new
			matchParent;
			alignCenterLeft;
			cellSpacing: 10.
	container
		padding: (BlInsets all: 20);
		margin: (BlInsets
				top: self spaceGap
				left: 2 * self spaceGap
				bottom: 2 * self spaceGap
				right: 2 * self spaceGap);
		background: Color white;
		addAptitude: BrShadowAptitude new beLarge;
		hExact: 350;
		vExact: 400.
	label := BrEditor new
			aptitude: BrGlamorousRegularEditorAptitude;
			vFitContent;
			hMatchParent;
			text: ''To work with the moldable AI agent, you need connections to LLMs. There aren''''t any just yet.'' asRopedText.
	button := BrButton new
			aptitude: BrGlamorousButtonWithLabelAptitude;
			label: ''Setup LLM connections'';
			action: [ :aButton | McGtPatches spawnLlmSetupFrom: aButton ].
	container
		addChild: label;
		addChild: button.
	^ container'
		classified: 'malleable-control patch'! !

!McGtPatches class methodsFor: 'applying'!
patchChatRegistryEmptyConnections
	"The same defect in the chat registry's empty state."
	(Smalltalk at: #GtLChatRegistryEmptyConnectionsElement ifAbsent: [ nil ])
		ifNil: [ ^ self ].
	(Smalltalk at: #GtLChatRegistryEmptyConnectionsElement)
		compile: 'initializeButtonElement
	buttonElement := BrButton new
			aptitude: BrGlamorousButtonWithLabelAptitude;
			label: ''Setup LLM connections'';
			action: [ :aButton | McGtPatches spawnLlmSetupInNewSpaceFrom: aButton ]'
		classified: 'malleable-control patch'! !

!McGtPatches class methodsFor: 'applying'!
repairOpenButtons
	"Patching a method does not touch elements already on screen: the card in
	 an open GtHome was built before the patch and still holds the old action
	 block. Rebind those, so a window that is already up is fixed without
	 having to restart GT or re-render the page."
	| repaired |
	repaired := 0.
	self openSpaces do: [ :space |
		(self buttonsUnder: space root labelled: 'Setup LLM connections')
			do: [ :button |
				button action: [ :aButton | McGtPatches spawnLlmSetupFrom: aButton ].
				repaired := repaired + 1 ] ].
	^ repaired! !

!McGtPatches class methodsFor: 'applying'!
openSpaces
	"Every space currently on screen. Empty in a headless image."
	| universeClass |
	universeClass := Smalltalk at: #BlParallelUniverse ifAbsent: [ nil ].
	universeClass ifNil: [ ^ #() ].
	^ [ (universeClass allInstances flatCollect: [ :each |
			[ each spaces ] on: Error do: [ :e | #() ] ]) asArray ]
		on: Error do: [ :e | #() ]! !

!McGtPatches class methodsFor: 'applying'!
buttonsUnder: anElement labelled: aString
	"Depth-first walk of a live element tree, collecting buttons by label."
	| found visit |
	found := OrderedCollection new.
	visit := nil.
	visit := [ :el |
		((el isKindOf: BrButton)
			and: [ [ el label asString includesSubstring: aString ]
					on: Error do: [ :e | false ] ])
			ifTrue: [ found add: el ].
		[ el children do: [ :child | visit value: child ] ]
			on: Error do: [ :e | ] ].
	visit value: anElement.
	^ found! !

!McGtPatches class methodsFor: 'home'!
applyRememberedLlmDefault
	"Re-apply the connection chosen with McLlm use:.

	 GtLConnectionRegistry >> updateConnections resets the default to its own
	 hardcoded standardDefaultConnection every time it runs, and it runs on the
	 way up -- so without this the choice would survive on disk but not in the
	 image. Doing it here also forces the connection list to be built before
	 refreshHome asks GtHome to re-render against it."
	| llm |
	llm := Smalltalk at: #McLlm ifAbsent: [ nil ].
	llm ifNil: [ ^ nil ].
	^ [ llm applyPreferredDefault ] on: Error do: [ :e | nil ]! !

!McGtPatches class methodsFor: 'home'!
refreshHome
	"Re-render the main window against the current state of the world.

	 GtHome decides once -- while it is being built -- whether its third pane
	 is the chat panel or the 'Setup LLM connections' placeholder, and the
	 world toolbar decides once whether to carry its chat dropdown. Both
	 questions are asked of GtLConnectionRegistry, and both are asked while the
	 image is still booting, before this file has registered the
	 OpenAI-compatible connector. So both come up saying 'no connections' and
	 nothing ever asks again. Ask again, here, once the patches have landed."
	| worlds |
	worlds := self openWorldElements.
	worlds
		do: [ :each |
			[ each
				enqueueTask: (BlTaskAction new
						action: [ [ each home requestWidgetUpdate ] on: Error do: [ :e |  ].
							[ each updateToolbarActions ] on: Error do: [ :e |  ] ]) ]
				on: Error
				do: [ :e |  ] ].
	^ worlds size! !

!McGtPatches class methodsFor: 'home'!
openWorldElements
	"Every GtWorldElement on screen -- one per GT main window. Empty in a
	 headless image, which is why refreshHome costs nothing there."
	| worldClass found |
	worldClass := Smalltalk at: #GtWorldElement ifAbsent: [ nil ].
	worldClass ifNil: [ ^ #() ].
	found := OrderedCollection new.
	self openSpaces
		do: [ :space |
			[ space root
				allChildrenBreadthFirstDo: [ :each |
					(each isKindOf: worldClass) ifTrue: [ found add: each ] ] ]
				on: Error
				do: [ :e |  ] ].
	^ found asArray! !

!McGtPatches class methodsFor: 'applying'!
patchLocalConnectorDiscovery
	"Two changes to GtLConnectionRegistry >> knownOllamaConnectors.

	 First, a guard. Upstream assumed that whatever answers on Ollama's port is
	 Ollama, and caught only ConnectionClosed. Anything else there -- another
	 service on 11434, or an Ollama with no models -- answers JSON with no
	 'models' key, so `nil groupedBy:' raised. That raise landed inside
	 updateConnections, which had already emptied the connection list before
	 rebuilding it, leaving the registry with no connections at all.

	 Second, this is the registry's only hook for connections discovered on
	 this machine rather than hardcoded -- knownConnectors appends its result
	 to a literal list of Anthropic and OpenAI models. So malleable-control's
	 OpenAI-compatible endpoint is appended here too, which is what keeps those
	 connections alive across updateConnections. The name is upstream's and now
	 undersells what it returns."
	(Smalltalk at: #GtLConnectionRegistry ifAbsent: [ nil ])
		ifNil: [ ^ self ].
	(Smalltalk at: #GtLConnectionRegistry)
		compile: 'knownOllamaConnectors
	| ollama |
	ollama := GtLOllamaProvider isConnectable
			ifFalse: [ #() ]
			ifTrue: [ | names |
				names := [ GtLOllamaProvider new availableModels keys ]
						on: Error do: [ :ex | #() ].
				names isNil
					ifTrue: [ #() ]
					ifFalse: [ names sorted collect: [ :name |
						GtLConnection new
							providerClass: GtLOllamaProvider;
							label: name;
							modelName: name ] ] ].
	^ ollama asArray , ([ McLlm openAiCompatibleConnectors ] on: Error do: [ :ex | #() ]) asArray'
		classified: 'malleable-control patch'! !

!McGtPatches class methodsFor: 'editor keymap'!
mcHome
	"The repo root, however this image was started."
	^ (Smalltalk at: #McHome ifAbsent: [ nil ])
		ifNil: [ [ Smalltalk os environment at: 'MC_HOME' ifAbsent: [ nil ] ]
				on: Error do: [ :e | nil ] ]! !

!McGtPatches class methodsFor: 'editor keymap'!
editorKeymap
	"Brick's live, mutable editor keymap -- one global shared by every editor
	 in the image, chat input included."
	| registry |
	registry := Smalltalk at: #BlShortcutKeymapRegistry ifAbsent: [ nil ].
	registry ifNil: [ ^ nil ].
	^ [ registry default editor ] on: Error do: [ :e | nil ]! !

!McGtPatches class methodsFor: 'editor keymap'!
editorKeymapEntry: aShortcutIdSelector
	"The keymap entry for one editor shortcut id, or nil."
	| keymap ids |
	keymap := self editorKeymap.
	keymap ifNil: [ ^ nil ].
	ids := Smalltalk at: #BrEditorShortcutIds ifAbsent: [ nil ].
	ids ifNil: [ ^ nil ].
	^ [ keymap keymapFor: (ids default perform: aShortcutIdSelector) ]
		on: Error do: [ :e | nil ]! !

!McGtPatches class methodsFor: 'editor keymap'!
setMacOsBindingOf: aShortcutIdSelector to: aCombination
	"Replace what this shortcut answers to on macOS."
	| entry |
	entry := self editorKeymapEntry: aShortcutIdSelector.
	entry ifNil: [ ^ false ].
	[ entry combinationForMacOS: aCombination ] on: Error do: [ :e | ^ false ].
	^ true! !

!McGtPatches class methodsFor: 'editor keymap'!
addMacOsBindingOf: aShortcutIdSelector to: aCombination
	"Add a macOS binding *alongside* whatever is already there, rather than
	 replacing it, so adding Ctrl+A does not cost you Home."
	| entry current |
	entry := self editorKeymapEntry: aShortcutIdSelector.
	entry ifNil: [ ^ false ].
	current := [ entry combinationForMacOS ] on: Error do: [ :e | nil ].
	current ifNil: [ current := [ entry combination ] on: Error do: [ :e | nil ] ].
	[ entry combinationForMacOS: (current
			ifNil: [ aCombination ]
			ifNotNil: [ BlAlternativeCombination combination: current or: aCombination ]) ]
		on: Error do: [ :e | ^ false ].
	^ true! !

!McGtPatches class methodsFor: 'editor keymap'!
controlKey: aKeySelector
	^ BlKeyCombination builder control; key: (BlKeyboardKey perform: aKeySelector); build! !

!McGtPatches class methodsFor: 'editor keymap'!
altKey: aKeySelector
	^ BlKeyCombination builder alt; key: (BlKeyboardKey perform: aKeySelector); build! !

!McGtPatches class methodsFor: 'editor keymap'!
patchMacOsEditorKeymap
	"Give word deletion its macOS binding.

	 BrEditorKeymapRegistry registers cursor motion and selection with macOS
	 variants -- move-to-previous-word is Ctrl+ArrowLeft generally and
	 Alt+ArrowLeft on macOS -- but registers word *deletion* with no macOS
	 variant at all:

		deletePreviousWordShortcutId  with: Cmd+Backspace   (no macOs:)
		deleteNextWordShortcutId      with: Cmd+Delete      (no macOs:)

	 So delete-previous-word answers to Cmd+Backspace, which on macOS means
	 'delete to start of line', while Alt+Backspace -- what every native text
	 field uses to kill a word backwards -- does nothing. The operations were
	 always there; only the bindings were missing. Added rather than replaced,
	 so Cmd+Backspace keeps working for anyone used to it."
	| changed |
	changed := 0.
	(self addMacOsBindingOf: #deletePreviousWordShortcutId to: (self altKey: #backspace))
		ifTrue: [ changed := changed + 1 ].
	(self addMacOsBindingOf: #deleteNextWordShortcutId to: (self altKey: #delete))
		ifTrue: [ changed := changed + 1 ].
	^ changed! !

!McGtPatches class methodsFor: 'editor keymap'!
emacsEditorBindings
	"emacs motions that map onto shortcut ids Brick already has, as
	 shortcutId -> key.

	 Ctrl+K, Ctrl+W, Ctrl+Y and Ctrl+Space are deliberately absent: there is no
	 kill-to-end-of-line, no kill ring and no mark in Brick, so those would
	 have to be *written*, not merely bound."
	^ {
		#moveCursorToLineStartShortcutId -> #a.
		#moveCursorToLineEndShortcutId -> #e.
		#moveCursorRightShortcutId -> #f.
		#moveCursorLeftShortcutId -> #b.
		#moveCursorDownShortcutId -> #n.
		#moveCursorUpShortcutId -> #p.
		#deleteOneLetterAfterCursorShortcutId -> #d }! !

!McGtPatches class methodsFor: 'editor keymap'!
emacsWordBindings
	"Alt+f and Alt+b, the emacs word motions."
	^ {
		#moveCursorToNextWordShortcutId -> #f.
		#moveCursorToPreviousWordShortcutId -> #b }! !

!McGtPatches class methodsFor: 'editor keymap'!
emacsKeymapFlagFile
	"Presence of this file means 'emacs bindings on'. Under run/ because it is
	 a preference of this machine, not of the project."
	| home |
	home := self mcHome.
	home ifNil: [ ^ nil ].
	^ home asFileReference / 'run' / 'emacs-editor-keys'! !

!McGtPatches class methodsFor: 'editor keymap'!
emacsEditorKeymapEnabled
	| file |
	file := self emacsKeymapFlagFile.
	^ file notNil and: [ file exists ]! !

!McGtPatches class methodsFor: 'editor keymap'!
applyEmacsEditorKeymap
	"Bind the emacs keys. Additive, so the existing bindings all still work."
	| changed |
	changed := 0.
	self emacsEditorBindings do: [ :each |
		(self addMacOsBindingOf: each key to: (self controlKey: each value))
			ifTrue: [ changed := changed + 1 ] ].
	self emacsWordBindings do: [ :each |
		(self addMacOsBindingOf: each key to: (self altKey: each value))
			ifTrue: [ changed := changed + 1 ] ].
	^ changed! !

!McGtPatches class methodsFor: 'editor keymap'!
enableEmacsEditorKeymap
	| file changed |
	file := self emacsKeymapFlagFile.
	file ifNil: [ ^ 'MC_HOME unknown -- cannot remember the setting' ].
	file parent ensureCreateDirectory.
	file exists ifFalse: [ file writeStreamDo: [ :s | s nextPutAll: 'on' ] ].
	changed := self applyEmacsEditorKeymap.
	^ 'emacs editor keys on (' , changed printString , ' bindings added)'! !

!McGtPatches class methodsFor: 'editor keymap'!
disableEmacsEditorKeymap
	"Drop the emacs bindings by restoring each entry from a pristine registry,
	 then reapply the macOS word-deletion fix, which is not part of this set."
	| file pristine ids keymap restored |
	file := self emacsKeymapFlagFile.
	(file notNil and: [ file exists ]) ifTrue: [ file delete ].
	pristine := [ BrEditorKeymapRegistry new ] on: Error do: [ :e | nil ].
	keymap := self editorKeymap.
	ids := Smalltalk at: #BrEditorShortcutIds ifAbsent: [ nil ].
	(pristine isNil or: [ keymap isNil or: [ ids isNil ] ])
		ifTrue: [ ^ 'emacs editor keys off (restart GT to drop the bindings)' ].
	restored := 0.
	(self emacsEditorBindings , self emacsWordBindings) do: [ :each |
		[ | id entry |
		id := ids default perform: each key.
		entry := keymap keymapFor: id.
		entry combinationForMacOS: (pristine keymapFor: id) combinationForMacOS.
		restored := restored + 1 ] on: Error do: [ :e | ] ].
	self patchMacOsEditorKeymap.
	^ 'emacs editor keys off (' , restored printString , ' bindings restored)'! !

!McGtPatches class methodsFor: 'editor keymap'!
describeEditorKeymap
	"What the editor answers to on macOS right now."
	| nl ids keymap |
	nl := String lf.
	ids := Smalltalk at: #BrEditorShortcutIds ifAbsent: [ nil ].
	keymap := self editorKeymap.
	(ids isNil or: [ keymap isNil ]) ifTrue: [ ^ 'no editor keymap in this image' ].
	^ String streamContents: [ :s |
		s << 'emacs bindings: '; << (self emacsEditorKeymapEnabled ifTrue: [ 'on' ] ifFalse: [ 'off' ]); << nl; << nl.
		(ids selectors asSortedCollection
			select: [ :sel | sel asString endsWith: 'ShortcutId' ])
			do: [ :sel |
				[ | entry |
				entry := keymap keymapFor: (ids default perform: sel).
				s << '  '; << sel asString; << nl; << '      ';
					<< (((entry combinationForMacOS ifNil: [ entry combination ]) gtDisplayString)) asString; << nl ]
					on: Error do: [ :e | ] ] ]! !

!McGtPatches class methodsFor: 'chat errors'!
errorTextFor: anErrorMessage
	"What a failed turn says to the model when the history is replayed.

	 Deliberately short, and this is the one place these patches do not follow
	 upstream. GtLErrorMessage >> serializeForOpenAIResponsesAPI reports the
	 exception's message, class, description *and* full stack trace -- and that
	 turn then stays in the chat for the rest of its life, going out with every
	 later message. Measured on this chat, three failures in: 348 KB of request
	 payload, nearly all of it Pharo backtrace, and the model answered with
	 nothing at all. A model can act on 'the previous turn failed, and why'. It
	 can do nothing with a VM stack."
	| exception detail |
	exception := [ anErrorMessage exception ] on: Error do: [ :e | nil ].
	exception ifNil: [ ^ '[this turn failed and was not answered]' ].
	detail := [ exception className asString , ': ' , (exception messageText ifNil: [ '' ]) asString ]
			on: Error do: [ :e | exception class name asString ].
	^ '[this turn failed and was not answered: ' , (detail truncateTo: 300) , ']'! !

!McGtPatches class methodsFor: 'chat errors'!
patchErrorMessageSerialization
	"One failed reply used to break a chat permanently.

	 When a request fails, GT keeps the failure in the history: the reply's
	 final message becomes a GtLErrorMessage, and GtLReplyMessage >> messagesDo:
	 hands it to the request builder along with everything else. Serialization
	 dispatches through GtLBasicMessage >> acceptVisitor:, which performs
	 #visit<ClassName>: -- so an error in the history means
	 #visitGtLErrorMessage:, and no visitor in the image implements it. Every
	 later message in that chat then died with

	     Instance of GtLOpenAiResponsesMessageVisitor
	     did not understand #visitGtLErrorMessage:

	 before it reached the network, however healthy the server was by then. So
	 a single blip -- a server restarting, a laptop changing networks -- cost
	 the chat rather than the message.

	 Upstream has already decided what an error should look like on the wire:
	 GtLErrorMessage >> serializeForOpenAIResponsesAPI reports it to the model
	 as a turn carrying the error, its class and its stack, so a model can see
	 that a tool or a request broke. That method serves the older
	 GtLOpenAI*Message family; the newer visitor path was written without an
	 error case, and the Anthropic path has none either. These patches carry
	 upstream's own choice into the paths that lack it."
	self patchOpenAiResponsesErrorSerialization.
	self patchOllamaErrorSerialization.
	self patchAnthropicErrorSerialization! !

!McGtPatches class methodsFor: 'chat errors'!
patchOpenAiResponsesErrorSerialization
	"The path our vLLM servers use. Role is 'user' rather than the message's
	 own #role, which answers 'error' -- not one of the roles the API accepts.
	 Upstream hardcodes 'user' here for the same reason."
	(Smalltalk at: #GtLOpenAiResponsesMessageVisitor ifAbsent: [ nil ])
		ifNil: [ ^ self ].
	(Smalltalk at: #GtLOpenAiResponsesMessageVisitor)
		compile: 'visitGtLErrorMessage: anErrorMessage
	^ {
		''role'' -> ''user''.
		''content'' -> { {
			''type'' -> ''input_text''.
			''text'' -> (McGtPatches errorTextFor: anErrorMessage)
			} asDictionary }
		} asDictionary'
		classified: 'malleable-control patch'! !

!McGtPatches class methodsFor: 'chat errors'!
patchOllamaErrorSerialization
	"Same defect, same file, other endpoint. Shaped like this visitor's own
	 assistant messages, which are bare content blocks."
	(Smalltalk at: #GtLOllamaCompletionsMessageVisitor ifAbsent: [ nil ])
		ifNil: [ ^ self ].
	(Smalltalk at: #GtLOllamaCompletionsMessageVisitor)
		compile: 'visitGtLErrorMessage: anErrorMessage
	^ { {
		''type'' -> ''text''.
		''text'' -> (McGtPatches errorTextFor: anErrorMessage)
		} asDictionary }'
		classified: 'malleable-control patch'! !

!McGtPatches class methodsFor: 'chat errors'!
patchAnthropicErrorSerialization
	"Anthropic does not go through a visitor: GtLAnthropicCompleteChatAPICommand
	 sends #serializeForAnthropicMessagesAPI to each message, and
	 GtLErrorMessage does not implement it. Role is 'assistant', not the 'user'
	 the OpenAI path uses, because the error stands where the assistant's reply
	 would have been and this API wants the roles to alternate."
	(Smalltalk at: #GtLErrorMessage ifAbsent: [ nil ])
		ifNil: [ ^ self ].
	(Smalltalk at: #GtLErrorMessage)
		compile: 'serializeForAnthropicMessagesAPI
	^ {
		''content'' -> { {
			''type'' -> ''text''.
			''text'' -> (McGtPatches errorTextFor: self)
			} asDictionary }.
		''role'' -> ''assistant''
		} asDictionary'
		classified: 'malleable-control patch'! !

!McGtPatches class methodsFor: 'chat history'!
patchAssistantTurnSerialization
	"A chat could not get past its first exchange.

	 GtLOpenAiResponsesMessageVisitor serializes a previous assistant turn as

	     {'role': 'assistant', 'content': [{'type': 'output_text', ...}]}

	 and sends it back in the request's input list. In the Responses API
	 output_text is an *output* content type: an input item carrying it has to
	 be a full output message -- 'type': 'message' as well, plus the id and
	 status the server issued. Without that, the item can only match the plain
	 input-message shape, whose content blocks may be input_text, input_image
	 or input_file and nothing else. So the request was rejected before the
	 model saw it, and vLLM answered

	     240 validation errors: Input should be a valid string ...

	 which is pydantic reporting that it tried every branch of the union and
	 none fit. The count is the giveaway: it grows with the conversation.

	 The effect was that every chat worked exactly once. The first message has
	 no assistant turn to replay, so it went through; from the second message
	 on, every request carried one and was refused. Nothing about it depended
	 on which server was up.

	 Fixed by replaying a past assistant turn as input_text, which is what an
	 input message is allowed to carry. Both places that build one had it."
	(Smalltalk at: #GtLOpenAiResponsesMessageVisitor ifAbsent: [ nil ])
		ifNil: [ ^ self ].
	(Smalltalk at: #GtLOpenAiResponsesMessageVisitor)
		compile: 'roleAndContentFrom: aMessage
	^ {
		''role'' -> aMessage role.
		''content'' -> { {
			''type'' -> ''input_text''.
			''text'' -> aMessage contentText
			} asDictionary }
		} asDictionary'
		classified: 'malleable-control patch'.
	(Smalltalk at: #GtLOpenAiResponsesMessageVisitor)
		compile: 'visitGtLModelCompactionMessage: aCompactionMessage
	| provider |
	provider := aCompactionMessage providerForSerialization.
	(provider notNil and: [
		aCompactionMessage isServerSideCompactionOutputFor: provider ])
		ifTrue: [
			^ aCompactionMessage
				rawDataFor: provider
				ifAbsent: [ self error: ''Missing native compaction data'' ] ].
	aCompactionMessage hasPortableContent ifFalse: [
		self error: ''This opaque compaction cannot be serialized for the current provider'' ].
	^ {
		''role'' -> ''assistant''.
		''content'' -> { {
			''type'' -> ''input_text''.
			''text'' -> aCompactionMessage portableContentText
		} asDictionary }
	} asDictionary'
		classified: 'malleable-control patch'! !

!McGtPatches class methodsFor: 'chat streaming'!
patchStreamingViewSwap
	"Stop the message box collapsing on every streamed update.

	 While a response streams in, each preview announces that the message
	 changed, and GtLMessageViewsElement rebuilds the whole views element:

	     onViewsReady: anElementOrNil
	         self removeChildNamed: #'message-tabs'.
	         anElementOrNil ifNil: [ ^ self ].
	         self addChild: anElementOrNil as: #'message-tabs'

	 The child holding the text is thrown away and a freshly computed one put in
	 its place, and the replacement's content is filled by an async widget. So
	 for a frame or two there is nothing in the box, and because the element is
	 vFitContentLimited its height falls to nothing and everything below jumps.
	 Sampling the live window during a response found the text editor missing in
	 roughly a quarter of the samples.

	 The fix is a floor, not a fixed size: the element keeps fitting its content
	 and simply may not become shorter than the tallest it has already been,
	 rounded up to a whole number of text lines. In CSS terms it is min-height,
	 and Bloc spells it the same way -- BlLayoutCommonConstraints >> minHeight:.

	 An exact height is the wrong tool here, and was the first thing tried: it
	 holds the box open but also stops it growing, so the arriving text stays
	 clipped to whatever height the box had when the response started, which
	 reads as the streaming output having been removed.

	 The floor is only ever taken from heights this element has actually had, so
	 it can never reserve more room than the message really occupied."
	(Smalltalk at: #GtLMessageViewsElement ifAbsent: [ nil ])
		ifNil: [ ^ self ].
	(Smalltalk at: #GtLMessageViewsElement)
		compile: 'onViewsReady: anElementOrNil
	| floor |
	floor := McGtPatches heightFloorFor: self.
	self removeChildNamed: #''message-tabs''.
	anElementOrNil ifNil: [ ^ self ].
	self addChild: anElementOrNil as: #''message-tabs''.
	McGtPatches holdHeightOf: self atLeast: floor'
		classified: 'malleable-control patch'! !

!McGtPatches class methodsFor: 'chat streaming'!
heightFloorFor: anElement
	"The tallest this element has legitimately been, snapped up to a whole
	 number of text lines. Read before the swap, while the old text is still
	 there to measure."
	| remembered current |
	remembered := [ anElement userData at: #mcHeightFloor ifAbsent: [ 0 ] ]
			on: Error do: [ :e | 0 ].
	current := [ anElement height ] on: Error do: [ :e | 0 ].
	^ self snap: (remembered max: current) toLineOf: anElement! !

!McGtPatches class methodsFor: 'chat streaming'!
lineHeightOf: anElement
	"One line of text, measured rather than assumed: the shortest paragraph on
	 screen, since a paragraph that wrapped is more than one line. Answers 0
	 when there is nothing to measure, and then nothing is snapped."
	| best |
	best := 0.
	[ anElement allChildrenBreadthFirstDo: [ :each |
		(each class name asString = 'BrTextEditorParagraphElement'
			and: [ each height > 0 ])
			ifTrue: [ best := best = 0 ifTrue: [ each height ] ifFalse: [ best min: each height ] ] ] ]
		on: Error do: [ :e |  ].
	^ best! !

!McGtPatches class methodsFor: 'chat streaming'!
snap: aHeight toLineOf: anElement
	"Round a height up to a whole number of lines, so the box grows in the
	 steps the text does instead of tracking every reflow by a pixel or two."
	| line |
	aHeight <= 0 ifTrue: [ ^ 0 ].
	line := self lineHeightOf: anElement.
	line <= 0 ifTrue: [ ^ aHeight ].
	^ (aHeight / line) ceiling * line! !

!McGtPatches class methodsFor: 'chat streaming'!
holdHeightOf: anElement atLeast: aHeight
	"Keep the box from collapsing while its content is rebuilt.

	 minHeight and not vExact: an exact height holds the box open but also stops
	 it growing with the response."
	aHeight <= 0 ifTrue: [ ^ self ].
	[ anElement userData at: #mcHeightFloor put: aHeight.
	anElement constraintsDo: [ :c | c minHeight: aHeight ].
	anElement requestLayout ]
		on: Error do: [ :e |  ]! !
