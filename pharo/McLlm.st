"
malleable-control -- LLM connection control for the GT image.

Everything here drives GtLConnectionRegistry, which is what GtHome's
'Get started' card consults. That card is not a thing in its own right: it
shows a 'Setup LLM connections' placeholder while
`GtLConnectionRegistry instance hasConnectableDefaultConnection' is false, and
GT's chat panel -- prompt input and all -- as soon as it is true.

A connection is connectable when its provider says so:

  Anthropic   ~/.secrets/anthropic-api-key.txt exists
  OpenAI      ~/.secrets/open-ai-api-key.txt exists
  Ollama      GtLOllamaProvider markConnectable has been sent, and the local
              Ollama server has at least one model pulled

Note what is deliberately absent: nothing here accepts an API key. Keys are
written to disk by bin/gt-llm, so they never travel over the bus.
"!

Object subclass: #McLlm
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McLlm class methodsFor: 'accessing'!
registry
	"The registry GtHome actually consults. Note this is GtLConnectionRegistry,
	 not the similarly named GtLlmConnectionRegistry -- they are different
	 classes with different instances, and only this one drives the card."
	^ GtLConnectionRegistry instance! !

!McLlm class methodsFor: 'accessing'!
providers
	"providerName -> provider class, for every provider the registry can use."
	| found |
	found := Dictionary new.
	self registry connections
		do: [ :each | found at: (self nameOf: each providerClass) put: each providerClass ].
	(Smalltalk at: #GtLOllamaProvider ifAbsent: [ nil ])
		ifNotNil: [ :cls | found at: (self nameOf: cls) put: cls ].
	self endpointUrl
		ifNotNil: [ :url |
			self providerClass
				ifNotNil: [ :cls | found at: (self nameOf: cls) put: cls ] ].
	^ found! !

!McLlm class methodsFor: 'accessing'!
nameOf: aProviderClass
	"Not every provider class defines providerName -- GtLLmStudioProvider does
	 not -- so fall back to the class name rather than raising."
	^ [ aProviderClass providerName asString ]
		on: Error
		do: [ :e | aProviderClass name asString ]! !

!McLlm class methodsFor: 'querying'!
isReady
	"True when the chat panel has something to talk to."
	^ [ self registry hasConnectableDefaultConnection ] on: Error do: [ :e | false ]! !

!McLlm class methodsFor: 'querying'!
status
	"A plain-text report of why the chat panel is or is not available."
	| nl reg |
	nl := String lf.
	reg := self registry.
	^ String
		streamContents: [ :s |
			s << 'chat panel ready: '; << self isReady printString; << nl.
			s << 'default connection: '; << ([ reg defaultConnection ifNil: [ 'none' ] ifNotNil: [ :c | c label asString ] ]
					on: Error do: [ :e | 'error' ]) asString; << nl; << nl.
			s << 'providers'; << nl.
			(self providers associations sorted: [ :a :b | a key < b key ])
				do: [ :assoc |
					s << '  '; << assoc key; << ': ';
						<< ([ assoc value isConnectable ] on: Error do: [ :e | false ]) printString.
					([ assoc value isConnectable ] on: Error do: [ :e | false ])
						ifFalse: [ s << '  (' ; << (self whyNotConnectable: assoc value); << ')' ].
					s << nl ].
			s << nl; << 'openai-compatible endpoints (first is preferred)'; << nl.
			self endpointUrls
				ifEmpty: [ s << '  none'; << nl ]
				ifNotEmpty: [ :urls |
					urls do: [ :url |
						s << '  '; << url;
							<< '  ';
							<< ((self cachedModels at: url ifAbsent: [ #() ]) asArray printString);
							<< nl ] ].
			s << nl; << 'remembered default: ';
				<< (self preferredLabel ifNil: [ 'none (falls back to the first connectable)' ]) asString; << nl.
			s << nl; << 'connections'; << nl.
			reg connections
				do: [ :each |
					s << '  ';
						<< (([ each isConnectable ] on: Error do: [ :e | false ])
								ifTrue: [ '[ok] ' ] ifFalse: [ '[  ] ' ]);
						<< each label asString; << '  ('; << (self nameOf: each providerClass); << ')'; << nl ] ]! !

!McLlm class methodsFor: 'querying'!
whyNotConnectable: aProviderClass
	"A one-line reason, so status says what to do rather than only that it failed."
	| file |
	file := self keyFileFor: aProviderClass.
	file ifNotNil: [ ^ 'no key at ' , file fullName asString ].
	((Smalltalk at: #GtLOllamaProvider ifAbsent: [ nil ]) = aProviderClass)
		ifTrue: [ ^ 'not enabled -- McLlm enableOllama' ].
	^ 'provider reports not connectable'! !

!McLlm class methodsFor: 'querying'!
probe
	"Everything status knows, plus what the configured endpoint actually says."
	^ self status , String lf , 'endpoint probe: ' , self probeEndpoint! !

!McLlm class methodsFor: 'querying'!
keyFileFor: aProviderClass
	"The API key file a provider checks, or nil if it needs no key."
	| name |
	name := aProviderClass name asString.
	(name includesSubstring: 'Anthropic')
		ifTrue: [ ^ GtAnthropicClient apiKeyFile ].
	(name includesSubstring: 'OpenAI')
		ifTrue: [ ^ GtLOpenAIClient apiKeyFile ].
	^ nil! !

!McLlm class methodsFor: 'changing'!
refresh
	"Re-read provider connectability and rebuild the connection list. Call this
	 after a key file appears on disk or Ollama is enabled."
	self registry updateConnections.
	self applyPreferredDefault.
	^ self status! !

!McLlm class methodsFor: 'changing'!
preferredLabelFile
	| home |
	home := self mcHome.
	home ifNil: [ ^ nil ].
	^ home asFileReference / 'run' / 'llm-default.txt'! !

!McLlm class methodsFor: 'changing'!
preferredLabel
	"The connection label chosen with McLlm use:, or nil for none."
	| file text |
	file := self preferredLabelFile.
	(file isNil or: [ file exists not ]) ifTrue: [ ^ nil ].
	text := [ file contents trimBoth ] on: Error do: [ :e | '' ].
	^ text isEmpty ifTrue: [ nil ] ifFalse: [ text ]! !

!McLlm class methodsFor: 'changing'!
preferredLabel: aStringOrNil
	| file |
	file := self preferredLabelFile.
	file ifNil: [ ^ self ].
	file parent ensureCreateDirectory.
	"writeStreamDo: overwrites from position 0 without truncating, so writing a
	 shorter label over a longer one would leave the tail of the old one behind."
	file exists ifTrue: [ file delete ].
	aStringOrNil
		ifNotNil: [ :label | file writeStreamDo: [ :s | s nextPutAll: label trimBoth ] ]! !

!McLlm class methodsFor: 'changing'!
applyPreferredDefault
	"Re-apply the remembered choice after a rebuild.

	 GtLConnectionRegistry >> updateConnections resets the default to its own
	 hardcoded standardDefaultConnection every time it runs, so without this a
	 choice made with use: lasts only until the next refresh -- which happens
	 at every startup."
	| label match |
	label := self preferredLabel.
	label ifNil: [ ^ nil ].
	match := self registry connections
			detect: [ :each | [ each label asString = label ] on: Error do: [ :e | false ] ]
			ifNone: [ nil ].
	match ifNil: [ ^ nil ].
	[ self registry defaultConnection: match ] on: Error do: [ :e | ^ nil ].
	^ match! !

!McLlm class methodsFor: 'changing'!
enableOllama
	"Ollama needs no key, only this opt-in flag -- after which the registry asks
	 the local server which models it has. With no models pulled, that answers
	 an empty list and nothing becomes connectable."
	(Smalltalk at: #GtLOllamaProvider ifAbsent: [ nil ])
		ifNil: [ ^ 'no GtLOllamaProvider in this image' ].
	(Smalltalk at: #GtLOllamaProvider) markConnectable.
	^ self refresh! !

!McLlm class methodsFor: 'changing'!
disableOllama
	(Smalltalk at: #GtLOllamaProvider ifAbsent: [ nil ])
		ifNil: [ ^ 'no GtLOllamaProvider in this image' ].
	(Smalltalk at: #GtLOllamaProvider) markNonconnectable.
	^ self refresh! !

!McLlm class methodsFor: 'changing'!
use: aLabel
	"Make the connection with this label the default one, and remember it so a
	 rebuild does not undo the choice."
	| match |
	match := self registry connections
			detect: [ :each | each label asString = aLabel ]
			ifNone: [ nil ].
	match ifNil: [ ^ 'no connection labelled ' , aLabel printString
			, String lf , 'known labels: '
			, (self registry connections collect: [ :each | each label asString ]) asArray printString ].
	match isConnectable ifFalse: [ ^ aLabel , ' is not connectable yet' ].
	self registry defaultConnection: match.
	self preferredLabel: aLabel.
	^ 'default connection is now ' , aLabel
		, ' (' , self syncConnectionPickers printString , ' picker(s) updated)'
		, String lf
		, 'this is what NEW chats get -- existing ones keep their own: McLlm switchChat:'! !

!McLlm class methodsFor: 'ui'!
connectionNamed: aLabel
	"The connection with this label, or nil."
	^ self registry connections
		detect: [ :each | [ each label asString = aLabel ] on: Error do: [ :e | false ] ]
		ifNone: [ nil ]! !

!McLlm class methodsFor: 'ui'!
onScreenChats
	"Every chat currently shown in a GT window, in the order found.

	 GtPhlowChatToolElement is the chat tool itself -- the thing with the prompt
	 -- and it holds the GtLChat it is showing. The chat pane on Home is not one
	 of these: that is a registry element, an index of chats."
	| toolClass found |
	toolClass := Smalltalk at: #GtPhlowChatToolElement ifAbsent: [ nil ].
	toolClass ifNil: [ ^ #() ].
	found := OrderedCollection new.
	(Smalltalk at: #McGtPatches ifAbsent: [ nil ])
		ifNil: [ ^ #() ]
		ifNotNil: [ :patches |
			patches openSpaces do: [ :space |
				[ space root allChildrenBreadthFirstDo: [ :each |
					(each isKindOf: toolClass) ifTrue: [
						[ each chat ifNotNil: [ :chat | found add: chat ] ]
							on: Error do: [ :e |  ] ] ] ]
					on: Error
					do: [ :e |  ] ] ].
	^ found asArray! !

!McLlm class methodsFor: 'ui'!
switchChat: aLabel
	"Point a chat that already exists at a different backend, keeping its history.

	 This is the one thing McLlm use: cannot do. GtLChat >> provider is lazy and
	 then permanent -- it builds from the registry default the first time it is
	 asked and caches the result in an instance variable, so a chat is welded to
	 whatever was default when it started. Nothing re-reads it. Switching means
	 handing the chat a new provider.

	 Applies to the chats on screen, which is what 'the current chat' means; with
	 no chat window open it falls back to the most recent chat."
	| connection targets |
	connection := self connectionNamed: aLabel.
	connection ifNil: [ ^ 'no connection labelled ' , aLabel printString
			, String lf , 'known labels: '
			, (self registry connections collect: [ :each | each label asString ]) asArray printString ].
	connection isConnectable ifFalse: [ ^ aLabel , ' is not connectable' ].
	targets := self onScreenChats.
	targets ifEmpty: [
		targets := GtL registry hasChats
				ifTrue: [ { GtL registry lastChat } ]
				ifFalse: [ #() ] ].
	targets ifEmpty: [ ^ 'no chat to switch -- McLlm openChat first' ].
	targets do: [ :chat | chat provider: connection buildProvider ].
	^ targets size printString , ' chat(s) now on ' , aLabel! !

!McLlm class methodsFor: 'ui'!
newChatOn: aLabel
	"A fresh chat on a named connection, leaving the default alone."
	| connection chat |
	connection := self connectionNamed: aLabel.
	connection ifNil: [ ^ 'no connection labelled ' , aLabel printString ].
	connection isConnectable ifFalse: [ ^ aLabel , ' is not connectable' ].
	self closeStrandedChatWindows.
	chat := GtL registry newChatWithProvider: connection buildProvider.
	chat inspect.
	^ 'new chat opened on ' , aLabel! !

!McLlm class methodsFor: 'ui'!
syncConnectionPickers
	"Point the chat pane's connection picker at the current default.

	 Same lazy-then-permanent trap as the chat itself: the registry view model
	 latches selectedConnection the first time it is read, so after use: the
	 picker keeps offering the old one and + keeps building it. Re-selecting
	 through the element's own handler updates its label too."
	| pickerClass default count |
	pickerClass := Smalltalk at: #GtLChatRegistryAddNewChatElement ifAbsent: [ nil ].
	pickerClass ifNil: [ ^ 0 ].
	default := [ self registry defaultConnection ] on: Error do: [ :e | nil ].
	default ifNil: [ ^ 0 ].
	count := 0.
	(Smalltalk at: #McGtPatches ifAbsent: [ nil ])
		ifNil: [ ^ 0 ]
		ifNotNil: [ :patches |
			patches openSpaces do: [ :space |
				[ space root allChildrenBreadthFirstDo: [ :each |
					(each isKindOf: pickerClass) ifTrue: [
						[ each onSelectConnection: default. count := count + 1 ]
							on: Error do: [ :e |  ] ] ] ]
					on: Error
					do: [ :e |  ] ] ].
	^ count! !

!McLlm class methodsFor: 'ui'!
chatsReport
	"Every chat and the server it talks to. A chat keeps the backend it was
	 born with, so this is the only way to see what is actually in use."
	| onScreen |
	onScreen := self onScreenChats.
	GtL registry hasChats ifFalse: [ ^ 'no chats' ].
	^ String
		streamContents: [ :s |
			GtL registry chats
				doWithIndex: [ :chat :index |
					s << index printString; << '. ';
						<< ((onScreen identityIncludes: chat) ifTrue: [ '[on screen] ' ] ifFalse: [ '           ' ]);
						<< ([ chat messages size ] on: Error do: [ :e | 0 ]) printString; << ' message(s)  ';
						<< ([ chat provider
								ifNil: [ 'no backend yet' ]
								ifNotNil: [ :provider | provider client baseUrl printString ] ]
							on: Error do: [ :e | 'unknown' ]);
						<< String lf ] ]! !

!McLlm class methodsFor: 'ui'!
openChat
	"Open a live chat -- the thing with a prompt input -- reusing the most
	 recent one if there is one.

	 Not GtLChatRegistryElement in a bare space, which is what this did at
	 first. That element is an *index* of chats: opening one from it is a phlow
	 spawn event, and only a phlow container catches those -- an inspector, a
	 pager, GtWorldElement. A bare BlSpace is none of them, so the list drew
	 fine, + added a row, and clicking the row went nowhere.

	 Inspecting a chat opens GtPhlowChatTool, which is a phlow container and is
	 the chat itself."
	| chat |
	self isReady ifFalse: [ ^ 'not ready -- McLlm status says why' ].
	self closeStrandedChatWindows.
	chat := (GtL registry hasChats
			ifTrue: [ GtL registry lastChat ]
			ifFalse: [ GtL registry newChat ]).
	chat inspect.
	^ 'chat window opened'! !

!McLlm class methodsFor: 'ui'!
newChat
	"A fresh chat with its own history, rather than reopening the last one."
	self isReady ifFalse: [ ^ 'not ready -- McLlm status says why' ].
	self closeStrandedChatWindows.
	GtL registry newChat inspect.
	^ 'new chat window opened'! !

!McLlm class methodsFor: 'ui'!
closeStrandedChatWindows
	"Close the dead-end window the first version of openChat produced. Matches
	 only the title this code gave it, so it cannot touch a window of yours."
	| patches |
	patches := Smalltalk at: #McGtPatches ifAbsent: [ nil ].
	patches ifNil: [ ^ 0 ].
	^ (patches openSpaces
		select: [ :each | [ each title asString = 'LLM chat' ] on: Error do: [ :e | false ] ])
		inject: 0
		into: [ :count :space | [ space close. count + 1 ] on: Error do: [ :e | count ] ]! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
mcHome
	"The repo root, however this image was started."
	^ (Smalltalk at: #McHome ifAbsent: [ nil ])
		ifNil: [ [ Smalltalk os environment at: 'MC_HOME' ifAbsent: [ nil ] ]
				on: Error do: [ :e | nil ] ]! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
endpointFile
	"Where the configured endpoint is remembered. Under run/ because it is
	 machine-local: the URL of a server on this network is not a fact about
	 the project."
	| home |
	home := self mcHome.
	home ifNil: [ ^ nil ].
	^ home asFileReference / 'run' / 'llm-endpoint.txt'! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
endpointUrl
	"The preferred OpenAI-compatible server -- the first line of the file -- or
	 nil when none is configured. This is the one a bare provider is built
	 against; every connection overrides it with its own baseUrl option."
	^ self endpointUrls ifEmpty: [ nil ] ifNotEmpty: [ :urls | urls first ]! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
endpointUrl: aStringOrNil
	"Replace the endpoint list with this one server, or nil to forget them all."
	^ self endpointUrls: (aStringOrNil ifNil: [ #() ] ifNotNil: [ :url | { url } ])! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
endpointUrls
	"Every configured OpenAI-compatible server, in preference order. One URL
	 per line; blank lines and # comments ignored, so the file stays editable
	 by hand."
	| file text |
	file := self endpointFile.
	(file isNil or: [ file exists not ]) ifTrue: [ ^ #() ].
	text := [ file contents ] on: Error do: [ :e | '' ].
	^ (text lines
		collect: [ :each | each trimBoth ])
		reject: [ :each | each isEmpty or: [ each beginsWith: '#' ] ]! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
endpointUrls: aCollection
	"Remember these servers, in this order. The first one is the one whose
	 model becomes the default connection."
	| file cleaned |
	file := self endpointFile.
	file ifNil: [ ^ 'MC_HOME unknown -- cannot remember the endpoints' ].
	cleaned := OrderedCollection new.
	aCollection do: [ :each |
		| url |
		url := each asString trimBoth.
		(url isEmpty or: [ cleaned includes: url ]) ifFalse: [ cleaned add: url ] ].
	file parent ensureCreateDirectory.
	file exists ifTrue: [ file delete ].
	cleaned ifNotEmpty: [
		file writeStreamDo: [ :s |
			cleaned do: [ :url | s nextPutAll: url ] separatedBy: [ s lf ] ] ].
	"A provider built earlier holds the old URL, so rebuild the connection list."
	^ self refresh! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
addEndpoint: aString
	"Add a server, keeping the existing ones and their order. The first server
	 configured stays first, so adding one never moves the default."
	^ self endpointUrls: (self endpointUrls asOrderedCollection
			add: aString asString trimBoth;
			yourself)! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
removeEndpoint: aString
	"Forget one server. Its cached models go too, so it stops appearing in the
	 dropdown."
	| wanted |
	wanted := aString asString trimBoth.
	self forgetModelsFor: wanted.
	^ self endpointUrls: (self endpointUrls reject: [ :each | each = wanted ])! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
endpointTimeoutSeconds
	"How long to wait on a server before giving up on it.

	 This is not a nicety. Connection discovery runs inside the registry's lock,
	 which runs on the bus read loop, so an unreachable server with no timeout
	 stops the whole image answering -- for as long as the OS takes to give up
	 on the connect, which is minutes."
	^ 5! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
hostLabelFor: aUrl
	"host:port, for telling two servers apart in the connection list."
	^ [ | url |
		url := aUrl asZnUrl.
		url port
			ifNil: [ url host asString ]
			ifNotNil: [ :port | url host asString , ':' , port asString ] ]
		on: Error
		do: [ :e | aUrl asString ]! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
labelFor: aModelName at: aUrl
	"Both of our servers serve a model called Qwen3.8-27B. The label has to say
	 which machine, or the dropdown offers the same name twice."
	^ aModelName asString , ' @ ' , (self hostLabelFor: aUrl)! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
providerClass
	"A provider pointed at the configured OpenAI-compatible server.

	 Built programmatically rather than declared in this file, because its
	 superclass exists only inside a GT image and this file has to stay
	 loadable without one.

	 GtLLmStudioProvider is the right parent: it is already 'an OpenAI /v1
	 server at a base URL of my choosing, with no API key', which is exactly
	 what vLLM and LM Studio both are. All this subclass changes is the URL."
	| existing parent |
	existing := Smalltalk at: #McOpenAiCompatibleProvider ifAbsent: [ nil ].
	existing ifNotNil: [ ^ existing ].
	parent := Smalltalk at: #GtLLmStudioProvider ifAbsent: [ nil ].
	parent ifNil: [ ^ nil ].
	parent
		subclass: #McOpenAiCompatibleProvider
		instanceVariableNames: ''
		classVariableNames: ''
		package: 'MalleableControl'.
	existing := Smalltalk at: #McOpenAiCompatibleProvider.
	existing
		compile: 'initialize
	| client |
	super initialize.
	client := McLlm clientClass new.
	client provider: self.
	McLlm endpointUrl ifNotNil: [ :url | client baseUrl: url asZnUrl ].
	model provider: self; client: client.
	model endpointAt: ''availableModels'' put: McLlm modelsEndpointClass new.
	McLlm streamingEnabled ifTrue: [
		(model endpointAt: ''userMessage'') additionalEntity at: ''stream'' put: true ]'
		classified: 'initialization'.
	existing class
		compile: 'providerName
	^ ''OpenAI-compatible'''
		classified: 'accessing'.
	^ existing! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
modelsEndpointClass
	"GT's model-listing endpoint is LM Studio's, not OpenAI's: it asks
	 /api/v1/models and reads a models array of display_name entries. A plain
	 OpenAI /v1 server -- vLLM included -- serves /v1/models and answers a
	 data array of id entries. This is that endpoint.

	 Built programmatically for the same reason as the provider: GtLEndpoint
	 only exists inside a GT image."
	| existing parent |
	existing := Smalltalk at: #McOpenAiModelsEndpoint ifAbsent: [ nil ].
	existing ifNotNil: [ ^ existing ].
	parent := Smalltalk at: #GtLEndpoint ifAbsent: [ nil ].
	parent ifNil: [ ^ nil ].
	parent
		subclass: #McOpenAiModelsEndpoint
		instanceVariableNames: ''
		classVariableNames: ''
		package: 'MalleableControl'.
	existing := Smalltalk at: #McOpenAiModelsEndpoint.
	existing
		compile: 'path
	^ ''/v1/models'''
		classified: 'accessing'.
	existing
		compile: 'resultFrom: aResponse
	| models |
	models := [ aResponse result at: ''data'' ifAbsent: [ nil ] ]
			on: Error do: [ :e | nil ].
	models ifNil: [ ^ Dictionary new ].
	^ models groupedBy: [ :each | each at: ''id'' ]'
		classified: 'accessing'.
	^ existing! !

!McLlm class methodsFor: 'streaming'!
clientClass
	"The HTTP client our provider uses: GT's, plus a streaming POST.

	 Subclassed programmatically for the same reason as everything else here --
	 GtLOllamaClient exists only inside a GT image. It carries a back-reference
	 to its provider, which the streaming code needs to reach the chat it is
	 writing partial messages into."
	| existing parent |
	existing := Smalltalk at: #McStreamingClient ifAbsent: [ nil ].
	existing ifNotNil: [ ^ existing ].
	parent := Smalltalk at: #GtLOllamaClient ifAbsent: [ nil ].
	parent ifNil: [ ^ nil ].
	parent
		subclass: #McStreamingClient
		instanceVariableNames: 'provider'
		classVariableNames: ''
		package: 'MalleableControl'.
	existing := Smalltalk at: #McStreamingClient.
	existing compile: 'provider
	^ provider' classified: 'accessing'.
	existing compile: 'provider: anObject
	provider := anObject' classified: 'accessing'.
	existing
		compile: 'post: aString withEntity: anEntity
	(McLlmStream isStreamingRequested: anEntity)
		ifFalse: [ ^ super post: aString withEntity: anEntity ].
	^ [ McLlmStream postStreaming: aString withEntity: anEntity client: self ]
		on: Error
		do: [ :e |
			"Anything at all going wrong in the streaming path falls back to the
			 blocking one, minus the flag that just failed, so a chat still gets
			 its answer. Recorded, because the fallback is invisible otherwise --
			 answers keep arriving, they just stop arriving progressively, and
			 that is exactly what a broken streaming path looks like from the
			 outside. McLlmStream report says whether this has happened."
			McLlmStream note: #streamFellBack value: e class name asString , '': '' , e messageText asString.
			anEntity removeKey: ''stream'' ifAbsent: [ ].
			super post: aString withEntity: anEntity ]'
		classified: 'requests'.
	^ existing! !

!McLlm class methodsFor: 'streaming'!
streamingFlagFile
	| home |
	home := self mcHome.
	home ifNil: [ ^ nil ].
	^ home asFileReference / 'run' / 'llm-streaming'! !

!McLlm class methodsFor: 'streaming'!
streamingEnabled
	| file |
	file := self streamingFlagFile.
	^ file notNil and: [ file exists ]! !

!McLlm class methodsFor: 'streaming'!
enableStreaming
	| file |
	file := self streamingFlagFile.
	file ifNil: [ ^ 'MC_HOME unknown -- cannot remember the setting' ].
	file parent ensureCreateDirectory.
	file exists ifFalse: [ file writeStreamDo: [ :s | s nextPutAll: 'on' ] ].
	"Providers are rebuilt per request, so this takes effect on the next message."
	^ 'streaming on'! !

!McLlm class methodsFor: 'streaming'!
disableStreaming
	| file |
	file := self streamingFlagFile.
	(file notNil and: [ file exists ]) ifTrue: [ file delete ].
	^ 'streaming off'! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
openAiCompatibleConnectors
	"One connection per model, per configured server.

	 Cache-first, and never blocking on a server it has talked to before. This
	 method runs inside the registry's lock every time connections are rebuilt,
	 which is at every startup -- so it must not depend on a server being up.
	 A machine that is off the network keeps the connections it had, and keeps
	 its place in the dropdown, until it is removed explicitly."
	| cls connectors |
	cls := self providerClass.
	cls ifNil: [ ^ #() ].
	connectors := OrderedCollection new.
	self endpointUrls do: [ :url |
		(self modelsFor: url) do: [ :name |
			connectors add: (GtLConnection new
					providerClass: cls;
					label: (self labelFor: name at: url);
					modelName: name asString;
					addOption: #baseUrl withValue: url asZnUrl;
					yourself) ] ].
	^ connectors asArray! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
modelsCacheFile
	"The last model list each server answered with. Under run/ because it is
	 machine-local and disposable: delete it and the next refresh re-asks."
	| home |
	home := self mcHome.
	home ifNil: [ ^ nil ].
	^ home asFileReference / 'run' / 'llm-models.txt'! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
cachedModels
	"url -> Array of model names, as last seen. One record per line:
	 the URL, a tab, then the model name."
	| file result |
	result := Dictionary new.
	file := self modelsCacheFile.
	(file isNil or: [ file exists not ]) ifTrue: [ ^ result ].
	[ file contents lines do: [ :line |
		| parts |
		parts := line substrings: String tab.
		parts size = 2 ifTrue: [
			(result at: parts first trimBoth ifAbsentPut: [ OrderedCollection new ])
				add: (parts at: 2) trimBoth ] ] ]
		on: Error
		do: [ :e | ^ Dictionary new ].
	^ result! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
cacheModels: aCollection for: aUrl
	"Remember what this server answered, replacing whatever it answered before."
	| file all |
	file := self modelsCacheFile.
	file ifNil: [ ^ self ].
	all := self cachedModels.
	all at: aUrl put: aCollection asOrderedCollection.
	file parent ensureCreateDirectory.
	file exists ifTrue: [ file delete ].
	file writeStreamDo: [ :s |
		(all keys asSortedCollection) do: [ :url |
			(all at: url) do: [ :name |
				s nextPutAll: url; tab; nextPutAll: name asString; lf ] ] ]! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
forgetModelsFor: aUrl
	"Drop one server's cached models, so it stops producing connections."
	| file all |
	file := self modelsCacheFile.
	file ifNil: [ ^ self ].
	all := self cachedModels.
	(all includesKey: aUrl) ifFalse: [ ^ self ].
	all removeKey: aUrl.
	file parent ensureCreateDirectory.
	file exists ifTrue: [ file delete ].
	file writeStreamDo: [ :s |
		(all keys asSortedCollection) do: [ :url |
			(all at: url) do: [ :name |
				s nextPutAll: url; tab; nextPutAll: name asString; lf ] ] ]! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
modelsFor: aUrl
	"What this server serves: the cache if we have ever heard from it, and only
	 otherwise a bounded request to find out."
	| cached |
	cached := self cachedModels at: aUrl ifAbsent: [ nil ].
	cached ifNotNil: [ ^ cached asArray ].
	^ self probeModelsFor: aUrl! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
probeModelsFor: aUrl
	"Ask a server what it serves, with a timeout, and remember the answer.
	 Answers an empty array if it cannot be reached -- never raises, because
	 callers run inside the registry lock."
	| cls names |
	cls := self providerClass.
	cls ifNil: [ ^ #() ].
	names := [ ZnConnectionTimeout
			value: self endpointTimeoutSeconds
			during: [ | provider |
				provider := cls new.
				provider baseUrl: aUrl asZnUrl.
				provider availableModels keys asArray ] ]
		on: Error
		do: [ :e | nil ].
	names ifNil: [ ^ #() ].
	self cacheModels: names asSortedCollection asArray for: aUrl.
	^ names asSortedCollection asArray! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
rediscoverModels
	"Re-ask every configured server, replacing the cache, then rebuild the
	 connection list. This is the one that goes to the network on purpose."
	self endpointUrls do: [ :url | self probeModelsFor: url ].
	^ self refresh! !

!McLlm class methodsFor: 'openai-compatible endpoint'!
probeEndpoint
	"Ask every configured server what it serves, and say plainly what came
	 back. Bounded, so a machine that is off the network costs a few seconds
	 rather than the whole image."
	| urls |
	urls := self endpointUrls.
	urls ifEmpty: [ ^ 'no endpoint configured' ].
	^ String
		streamContents: [ :s |
			urls
				do: [ :url |
					| names |
					names := [ ZnConnectionTimeout
							value: self endpointTimeoutSeconds
							during: [ | provider |
								provider := self providerClass new.
								provider baseUrl: url asZnUrl.
								provider availableModels keys asSortedCollection asArray ] ]
						on: Error
						do: [ :e | nil ].
					s << url.
					names
						ifNil: [ | cached |
							cached := self cachedModels at: url ifAbsent: [ #() ].
							s << ' -- unreachable'.
							cached ifNotEmpty: [
								s << ' (offering ' ; << cached asArray printString ; << ' from cache)' ] ]
						ifNotNil: [ s << ' -- serves ' ; << names printString ] ]
				separatedBy: [ s << String lf ] ]! !
