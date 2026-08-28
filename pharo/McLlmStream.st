"
malleable-control -- streaming responses from an OpenAI-compatible server.

GT never streams: GtLOpenAiResponsesEndpoint hardcodes 'stream' -> false, posts
with a plain ZnClient that reads the whole body, and only then builds the
assistant message. So the chat sits frozen until the model is completely done.

Nothing here patches GT. Three facts make that possible:

  1. GtLEndpoint >> additionalEntity is an official hook whose contents are
     merged into the request LAST, so 'stream' -> true overrides the hardcoded
     false without touching the endpoint.
  2. The SSE stream ends with a response.completed event carrying the COMPLETE
     response object, identical in shape to the non-streaming reply. Hand that
     to GtLEndpoint >> resultFrom:context: and everything downstream -- message
     construction, tool calls, compaction -- runs unchanged.
  3. GtLChat >> addAssistantMessage: sets finalMessage: on the reply message.
     It is a slot, not an append, so a partial message can be published over
     and over as text arrives, and the real one simply replaces it at the end.

The read loop checks the provider's execution state each time round, so the
chat's existing stop button ends a response mid-flight and keeps the text that
had already arrived.
"!

Object subclass: #McLlmStream
	instanceVariableNames: ''
	classVariableNames: 'Diagnostics'
	package: 'MalleableControl'!

!McLlmStream class methodsFor: 'diagnostics'!
diagnostics
	"Streaming is hard to watch from outside, so the last run records what it
	 did. Read it with McLlmStream report."
	^ Diagnostics ifNil: [ Diagnostics := Dictionary new ]! !

!McLlmStream class methodsFor: 'diagnostics'!
resetDiagnostics
	Diagnostics := Dictionary new.
	^ 'reset'! !

!McLlmStream class methodsFor: 'diagnostics'!
note: aKey
	self diagnostics at: aKey put: (self diagnostics at: aKey ifAbsent: [ 0 ]) + 1! !

!McLlmStream class methodsFor: 'diagnostics'!
note: aKey value: anObject
	self diagnostics at: aKey put: anObject! !

!McLlmStream class methodsFor: 'diagnostics'!
report
	| nl |
	nl := String lf.
	^ String streamContents: [ :s |
		(self diagnostics associations sorted: [ :a :b | a key < b key ])
			do: [ :each |
				s << '  '; << each key asString; << ': '; << each value printString; << nl ] ]! !

!McLlmStream class methodsFor: 'testing'!
isStreamingRequested: anEntity
	^ [ (anEntity at: 'stream' ifAbsent: [ false ]) = true ]
		on: Error do: [ :e | false ]! !

!McLlmStream class methodsFor: 'accessing'!
previewIntervalMilliseconds
	"How often a partial message is published. Tokens arrive far faster than
	 anyone can read, and every publish costs a re-render, so redraw on a
	 clock rather than on every delta.

	 Just under GT's own coalescing window: GtLMessageViewsElement drives its
	 rebuilds through a BrElementUpdater postponed by 300 ms, so previews
	 published faster than that are collapsed and thrown away. At 80 ms a
	 response produced 512 previews and 157 rebuilds -- the other 355 were
	 wasted, and not cheaply: snapshotOf: serializes and reparses the whole
	 response so far, so publishing n times over a response of length n costs
	 quadratic work on the UI process. Fewer, better-timed previews look the
	 same and leave the frame budget alone."
	^ 250! !

!McLlmStream class methodsFor: 'requesting'!
postStreaming: aPath withEntity: anEntity client: aModelClient
	"POST with SSE, publishing partial messages as text arrives, and answer the
	 same GtLRequestResponse the blocking path would have answered."
	| znClient assembled provider |
	provider := [ aModelClient provider ] on: Error do: [ :e | nil ].
	"The request entity is not plain JSON data. Once a chat has tools or a
	 response format it carries objects whose JSON form is defined by the writer
	 GT configures, and STONJSON toString: raises 'wrong object class for JSON
	 mode' on them. This code used to serialize with STONJSON, so any chat that
	 acquired tools fell back to the blocking path and quietly stopped
	 streaming -- quietly, because the fallback answers correctly."
	znClient := ZnClient new.
	"GT's client is beOneShot, and Zn refuses to stream on a one-shot client,
	 so borrow only the piece that matters -- the writer that knows how to turn
	 the request entity into JSON."
	[ znClient contentWriter: aModelClient initializeClient contentWriter ]
		on: Error do: [ :e |  ].
	znClient url: aModelClient baseUrl / aPath.
	[ znClient contents: anEntity ]
		on: Error
		do: [ :e |
			znClient entity: (ZnEntity
					with: (STONJSON toString: anEntity)
					type: ZnMimeType applicationJson) ].
	znClient streaming: true.
	znClient timeout: 1200.
	self note: #postStreamingCalled.
	znClient post.
	znClient response isSuccess
		ifFalse: [ self error: 'streaming request failed: ' , znClient response status printString ].
	assembled := [ self readEventsFrom: znClient provider: provider ]
			on: Error
			do: [ :e |
				self note: #readError value: e class name asString , ': ' , e messageText asString.
				e signal ].
	assembled ifNil: [ self error: 'stream carried no response' ].
	^ GtLRequestResponse new
		request: znClient request;
		response: znClient response;
		result: assembled;
		yourself! !

!McLlmStream class methodsFor: 'requesting'!
readEventsFrom: aZnClient provider: aProvider
	"Consume the SSE body, assembling a response object as events arrive."
	| stream assembled lastPreview previewMessage |
	stream := aZnClient response entity stream.
	assembled := nil.
	lastPreview := 0.
	previewMessage := nil.
	[ stream atEnd or: [ self shouldStop: aProvider ] ] whileFalse: [
		| line |
		line := self nextLineFrom: stream.
		(line notNil and: [ line beginsWith: 'data: ' ]) ifTrue: [
			| payload |
			payload := [ STONJSON fromString: (line allButFirst: 6) trimBoth ]
					on: Error do: [ :e | nil ].
			payload ifNotNil: [
				self note: #events.
				(payload at: 'type' ifAbsent: [ '' ]) = 'response.completed'
					ifTrue: [ self note: #sawCompleted ].
				assembled := self apply: payload to: assembled.
				(Time millisecondClockValue - lastPreview >= self previewIntervalMilliseconds)
					ifTrue: [
						lastPreview := Time millisecondClockValue.
						previewMessage := self
								publishPreview: assembled
								provider: aProvider
								into: previewMessage ] ] ] ].
	self note: #providerWasNil value: aProvider isNil.
	self note: #exitedBecause value: (stream atEnd ifTrue: [ 'stream atEnd' ] ifFalse: [ 'stop requested' ]).
	^ assembled! !

!McLlmStream class methodsFor: 'requesting'!
nextLineFrom: aStream
	"One SSE line. The stream is bytes, not characters -- and splitting on LF
	 is safe on raw bytes because a UTF-8 continuation byte is never 10."
	| bytes |
	bytes := [ aStream upTo: 10 ] on: Error do: [ :e | nil ].
	bytes ifNil: [ ^ nil ].
	^ [ bytes asByteArray utf8Decoded ] on: Error do: [ :e | '' ]! !

!McLlmStream class methodsFor: 'requesting'!
shouldStop: aProvider
	"True once the chat's stop button has been pressed."
	aProvider ifNil: [ ^ false ].
	^ [ aProvider state ifCanContinue: [ false ] ifDisabled: [ true ] ]
		on: Error do: [ :e | false ]! !

!McLlmStream class methodsFor: 'assembling'!
apply: aPayload to: assembled
	"Fold one SSE event into the response being assembled."
	| type |
	type := aPayload at: 'type' ifAbsent: [ '' ].
	(type = 'response.created' or: [ type = 'response.completed' ])
		ifTrue: [ ^ self normalized: (aPayload at: 'response' ifAbsent: [ assembled ]) ].
	assembled ifNil: [ ^ nil ].
	(type = 'response.output_item.added' or: [ type = 'response.output_item.done' ])
		ifTrue: [
			self
				setItem: (aPayload at: 'item' ifAbsent: [ nil ])
				at: (aPayload at: 'output_index' ifAbsent: [ 0 ])
				in: assembled.
			^ assembled ].
	(type endsWith: '.delta') ifTrue: [
		self
			appendDelta: (aPayload at: 'delta' ifAbsent: [ '' ])
			outputIndex: (aPayload at: 'output_index' ifAbsent: [ 0 ])
			contentIndex: (aPayload at: 'content_index' ifAbsent: [ 0 ])
			kind: ((type includesSubstring: 'reasoning')
					ifTrue: [ 'reasoning_text' ]
					ifFalse: [ 'output_text' ])
			in: assembled.
		^ assembled ].
	^ assembled! !

!McLlmStream class methodsFor: 'assembling'!
normalized: aResponse
	"JSON arrays parse as fixed-size Arrays, which cannot grow. Every array this
	 code appends to becomes an OrderedCollection."
	aResponse ifNil: [ ^ nil ].
	aResponse
		at: 'output'
		put: (aResponse at: 'output' ifAbsent: [ #() ]) asOrderedCollection.
	(aResponse at: 'output') do: [ :each | self normalizedItem: each ].
	^ aResponse! !

!McLlmStream class methodsFor: 'assembling'!
normalizedItem: anItem
	| content |
	(anItem isKindOf: Dictionary) ifFalse: [ ^ anItem ].
	content := anItem at: 'content' ifAbsent: [ nil ].
	anItem
		at: 'content'
		put: (content isNil
				ifTrue: [ OrderedCollection new ]
				ifFalse: [ content asOrderedCollection ]).
	^ anItem! !

!McLlmStream class methodsFor: 'assembling'!
setItem: anItem at: anOutputIndex in: assembled
	"Place an item at its output index, growing the list if events arrive for
	 an index we have not seen."
	| output index |
	anItem ifNil: [ ^ self ].
	output := assembled at: 'output'.
	index := anOutputIndex + 1.
	[ output size < index ] whileTrue: [ output add: (self newItemOfKind: 'output_text') ].
	output at: index put: (self normalizedItem: anItem)! !

!McLlmStream class methodsFor: 'assembling'!
newItemOfKind: aKind
	^ Dictionary newFrom: {
		'type' -> (aKind = 'reasoning_text' ifTrue: [ 'reasoning' ] ifFalse: [ 'message' ]).
		'role' -> 'assistant'.
		'content' -> OrderedCollection new }! !

!McLlmStream class methodsFor: 'assembling'!
appendDelta: aString outputIndex: anOutputIndex contentIndex: aContentIndex kind: aKind in: assembled
	| output item content part |
	output := assembled at: 'output'.
	[ output size < (anOutputIndex + 1) ]
		whileTrue: [ output add: (self newItemOfKind: aKind) ].
	item := self normalizedItem: (output at: anOutputIndex + 1).
	content := item at: 'content'.
	[ content size < (aContentIndex + 1) ]
		whileTrue: [ content add: (Dictionary newFrom: { 'type' -> aKind. 'text' -> '' }) ].
	part := content at: aContentIndex + 1.
	(part isKindOf: Dictionary) ifFalse: [ ^ self ].
	part at: 'text' put: (part at: 'text' ifAbsent: [ '' ]) , aString! !

!McLlmStream class methodsFor: 'previewing'!
publishPreview: assembled provider: aProvider into: aMessageOrNil
	"Show what has arrived so far, through one message object for the whole
	 response. Answers the message to reuse on the next preview.

	 This used to build a fresh assistant message every 80 ms and hand it to
	 addAssistantMessage:, which sets finalMessage: on the reply. The view layer
	 keys its elements off that object, so every preview tore the message
	 element down and built another one. Measured on a single answer: 512
	 previews, 157 element rebuilds -- and sampling the live window during a
	 response found the editor missing altogether in about a quarter of the
	 samples. That is the flicker: the box empties, collapses to nothing and is
	 repopulated, a dozen times a second.

	 Reusing one object means finalMessage: sees the message it already holds
	 and returns early, so the element survives and only its text grows. It also
	 stops the reply being stamped finished on every preview, which
	 finalMessage: does unconditionally."
	| chat message |
	(assembled isNil or: [ aProvider isNil ]) ifTrue: [ ^ aMessageOrNil ].
	self note: #previewAttempts.
	^ [ chat := aProvider chat.
		chat
			ifNil: [ self note: #previewChatWasNil. aMessageOrNil ]
			ifNotNil: [
				message := aMessageOrNil ifNil: [ aProvider assistantMessageClass new ].
				self refresh: message from: assembled provider: aProvider.
				aMessageOrNil ifNil: [ chat addAssistantMessage: message ].
				chat ensureReplyMessage notifyReplyMessageChanged.
				self note: #previewsPublished.
				message ] ]
		on: Error
		do: [ :e |
			"a preview that cannot render must not abort the response"
			self note: #previewError value: e class name asString , ': ' , e messageText asString.
			aMessageOrNil ]! !

!McLlmStream class methodsFor: 'previewing'!
refresh: aMessage from: assembled provider: aProvider
	"Point an assistant message at the response as it stands, in place.

	 responseModels and responseEntity are both caches over rawData, computed
	 once and kept. Clearing them is what makes the message re-read what has
	 just arrived rather than answering with the first token it ever saw."
	aMessage
		instVarNamed: 'responseModels' put: nil;
		instVarNamed: 'responseEntity' put: nil.
	aMessage
		initializeFromResult: (GtLModelResponse
				from: (self snapshotOf: assembled)
				model: aProvider model)
		provider: aProvider! !

!McLlmStream class methodsFor: 'previewing'!
snapshotOf: assembled
	"A detached copy, so the message just published does not keep changing
	 underneath the view as more deltas land."
	^ [ STONJSON fromString: (STONJSON toString: assembled) ]
		on: Error
		do: [ :e | assembled ]! !
