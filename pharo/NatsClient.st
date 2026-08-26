"
Core NATS protocol client for Pharo / Glamorous Toolkit.
Part of malleable-control. See docs/nats_local_process_bus_design.md.

This class speaks the wire protocol and nothing else. It has no opinion about
subject naming, JSON, or what any message means -- that lives in McGtService.

Wire protocol (client -> server):
	CONNECT {json}       PUB <subject> [reply-to] <#bytes>
	SUB <subject> <sid>  UNSUB <sid>        PING / PONG

Wire protocol (server -> client):
	INFO {json}          MSG <subject> <sid> [reply-to] <#bytes>
	+OK / -ERR <msg>     PING / PONG

Framing is byte-oriented: MSG carries a payload length in BYTES, so the
accumulation buffer is a ByteArray throughout and UTF-8 decoding happens only
at the dispatch edge.

This file is in Pharo CHUNK format and is loaded with fileIn. A class created
by fileIn cannot be referenced by name in the same compiled expression -- the
reference is resolved at compile time, before the class exists. Reach it with
(Smalltalk at: #NatsClient) instead.
"!

Object subclass: #NatsClient
	instanceVariableNames: 'name host port socket readProcess sendMutex running connected inbuf pending subs sidCounter inboxPrefix inboxSid requestCounter pendingRequests onConnect reconnectDelay'
	classVariableNames: ''
	package: 'MalleableControl'!

!NatsClient class methodsFor: 'instance creation'!
on: aHost port: aPort name: aName
	^ self new setHost: aHost port: aPort name: aName! !

!NatsClient methodsFor: 'initialization'!
initialize
	super initialize.
	sendMutex := Mutex new.
	subs := Dictionary new.
	pendingRequests := Dictionary new.
	sidCounter := 0.
	requestCounter := 0.
	inbuf := ByteArray new.
	pending := nil.
	running := false.
	connected := false.
	reconnectDelay := 0.5!

setHost: aHost port: aPort name: aName
	host := aHost.
	port := aPort.
	name := aName.
	inboxPrefix := '_INBOX.' , self newId! !

!NatsClient methodsFor: 'accessing'!
name
	^ name!

host
	^ host!

port
	^ port!

isConnected
	^ connected = true!

onConnect: aBlock
	"aBlock is evaluated with this client each time the handshake completes.
	 Register subscriptions there, not before, so they are restored after a
	 reconnect."
	onConnect := aBlock! !

!NatsClient methodsFor: 'connecting'!
connect
	running := true.
	self openSocket.
	readProcess := [ self readLoop ] forkAt: Processor userBackgroundPriority.
	readProcess name: 'NATS read loop'.
	^ self!

openSocket
	inbuf := ByteArray new.
	pending := nil.
	connected := false.
	socket := Socket newTCP.
	socket connectTo: (NetNameResolver addressForName: host) port: port.
	socket waitForConnectionFor: 5!

handleSocketClosed
	"A dropped bus is not fatal. Tear the socket down, keep the subscription
	 table, and let the read loop retry -- callers never see the gap."
	connected := false.
	socket ifNotNil: [ [ socket closeAndDestroy ] on: Error do: [ :e | ]. socket := nil ].
	inbuf := ByteArray new.
	pending := nil.
	self logString: 'socket closed, will retry'!

attemptReconnect
	(Delay forSeconds: reconnectDelay) wait.
	running ifFalse: [ ^ self ].
	[ self openSocket. reconnectDelay := 0.5 ]
		on: Error
		do: [ :e |
			socket := nil.
			reconnectDelay := (reconnectDelay * 2) min: 30 ]!

waitForConnectionFor: seconds
	"Block until the handshake completes. Answer whether it did."
	| deadline |
	deadline := DateAndTime now + seconds seconds.
	[ self isConnected not and: [ DateAndTime now < deadline ] ]
		whileTrue: [ (Delay forMilliseconds: 25) wait ].
	^ self isConnected!

disconnect
	running := false.
	connected := false.
	readProcess ifNotNil: [ readProcess terminate. readProcess := nil ].
	socket ifNotNil: [ [ socket closeAndDestroy ] on: Error do: [ :e | ]. socket := nil ]! !

!NatsClient methodsFor: 'public api'!
publish: aSubject data: aString
	self publish: aSubject data: aString replyTo: nil!

publish: aSubject data: aString replyTo: anInbox
	| body header stream |
	body := aString utf8Encoded.
	header := anInbox
		ifNil: [ 'PUB ' , aSubject , ' ' , body size printString ]
		ifNotNil: [ 'PUB ' , aSubject , ' ' , anInbox , ' ' , body size printString ].
	stream := WriteStream on: ByteArray new.
	stream nextPutAll: (header , String crlf) utf8Encoded.
	stream nextPutAll: body.
	stream nextPutAll: String crlf utf8Encoded.
	self sendBytes: stream contents!

subscribe: aSubject do: aBlock
	"aBlock is evaluated with subject, payload string, and reply-to (or nil).
	 Answer a subscription id for unsubscribe:."
	| sid |
	sid := self nextSid.
	subs at: sid put: aSubject -> aBlock.
	self isConnected ifTrue: [ self sendLine: 'SUB ' , aSubject , ' ' , sid ].
	^ sid!

unsubscribe: aSid
	subs removeKey: aSid ifAbsent: [ nil ].
	self isConnected ifTrue: [ self sendLine: 'UNSUB ' , aSid ]!

request: aSubject data: aString timeout: seconds
	"Send a request and block until the reply arrives. Answer the reply string,
	 or nil on timeout."
	| inbox sem result |
	requestCounter := requestCounter + 1.
	inbox := inboxPrefix , '.' , requestCounter printString.
	sem := Semaphore new.
	pendingRequests at: inbox put: [ :reply | result := reply. sem signal ].
	self publish: aSubject data: aString replyTo: inbox.
	^ sem
		waitTimeoutSeconds: seconds
		onCompletion: [ result ]
		onTimeout: [ pendingRequests removeKey: inbox ifAbsent: [ nil ]. nil ]!

request: aSubject data: aString
	^ self request: aSubject data: aString timeout: 5!

reply: anInbox with: aString
	"Answer a request. A nil inbox means the sender did not want a reply."
	anInbox ifNotNil: [ self publish: anInbox data: aString ]! !

!NatsClient methodsFor: 'private-io'!
sendBytes: aByteArray
	"Serialised: handlers run in forked processes and may publish concurrently,
	 and two interleaved PUB frames would corrupt the stream."
	sendMutex critical: [
		socket ifNotNil: [
			[ socket sendData: aByteArray ]
				on: Error
				do: [ :e | self logString: 'send failed: ' , e messageText printString ] ] ]!

sendLine: aString
	self sendBytes: (aString , String crlf) utf8Encoded!

readLoop
	[ running ] whileTrue: [
		socket
			ifNil: [ self attemptReconnect ]
			ifNotNil: [
				[ self pumpOnce ]
					on: Error
					do: [ :e |
						running ifTrue: [
							self logString: 'read loop: ' , e messageText printString ].
						self handleSocketClosed ] ] ]!

pumpOnce
	| buffer count |
	socket ifNil: [ ^ self ].
	socket
		waitForDataFor: 1
		ifClosed: [ self handleSocketClosed. ^ self ]
		ifTimedOut: [ ^ self ].
	buffer := ByteArray new: 8192.
	count := socket receiveAvailableDataInto: buffer.
	count > 0 ifTrue: [
		inbuf := inbuf , (buffer copyFrom: 1 to: count).
		self drain ]! !

!NatsClient methodsFor: 'private-parsing'!
drain
	"Consume as many whole frames as the buffer currently holds. Two states:
	 awaiting the payload of an already-parsed MSG header, or awaiting the next
	 CRLF-terminated control line."
	| more |
	more := true.
	[ more ] whileTrue: [
		more := pending
			ifNil: [ self drainControlLine ]
			ifNotNil: [ self drainPayload ] ]!

drainControlLine
	| idx line |
	idx := self indexOfCRLF.
	idx ifNil: [ ^ false ].
	line := (inbuf copyFrom: 1 to: idx - 1) asString.
	inbuf := inbuf copyFrom: idx + 2 to: inbuf size.
	self handleLine: line.
	^ true!

drainPayload
	| len payload |
	len := pending at: 4.
	inbuf size < (len + 2) ifTrue: [ ^ false ].
	payload := inbuf copyFrom: 1 to: len.
	inbuf := inbuf copyFrom: len + 3 to: inbuf size.
	self dispatch: pending payload: payload.
	pending := nil.
	^ true!

indexOfCRLF
	"Answer the 1-based index of the CR of the first CRLF, or nil."
	2 to: inbuf size do: [ :i |
		(((inbuf at: i - 1) = 13) and: [ (inbuf at: i) = 10 ])
			ifTrue: [ ^ i - 1 ] ].
	^ nil!

handleLine: line
	(line beginsWith: 'MSG ') ifTrue: [ pending := self parseMsgHeader: line. ^ self ].
	(line beginsWith: 'PING') ifTrue: [ self sendLine: 'PONG'. ^ self ].
	(line beginsWith: 'PONG') ifTrue: [ ^ self ].
	"Only the FIRST INFO on a socket is a handshake cue. Announcing protocol 1
	 opts into async INFO updates, so the server sends another INFO right after
	 CONNECT -- handshaking on that one too would subscribe everything twice
	 and reply twice to every request."
	(line beginsWith: 'INFO ') ifTrue: [
		self isConnected ifFalse: [ self handshake ].
		^ self ].
	(line beginsWith: '+OK') ifTrue: [ ^ self ].
	(line beginsWith: '-ERR') ifTrue: [ self logString: 'server error: ' , line. ^ self ]!

parseMsgHeader: line
	"Answer an Array of subject, sid, reply-to (or nil), and byte length."
	| parts |
	parts := line substrings: ' '.
	parts size = 4 ifTrue: [
		^ Array with: (parts at: 2) with: (parts at: 3) with: nil
			with: (parts at: 4) asNumber ].
	parts size = 5 ifTrue: [
		^ Array with: (parts at: 2) with: (parts at: 3) with: (parts at: 4)
			with: (parts at: 5) asNumber ].
	self error: 'Malformed MSG header: ' , line!

dispatch: header payload: bytes
	| subject sid replyTo text entry |
	subject := header at: 1.
	sid := header at: 2.
	replyTo := header at: 3.
	text := [ bytes utf8Decoded ] on: Error do: [ :e | bytes asString ].
	sid = inboxSid ifTrue: [ ^ self resolveRequest: subject with: text ].
	entry := subs at: sid ifAbsent: [ nil ].
	entry ifNil: [ ^ self ].
	"Each handler runs in its own process. A handler that issues a synchronous
	 request would otherwise block the very read loop that must deliver its
	 reply -- a self-inflicted deadlock. Forking also means one raising handler
	 cannot deafen the client."
	[ [ entry value value: subject value: text value: replyTo ]
		on: Error
		do: [ :e | self logString: 'handler for ' , subject , ' raised: ' , e messageText printString ] ] fork!

resolveRequest: anInbox with: text
	| blk |
	blk := pendingRequests removeKey: anInbox ifAbsent: [ nil ].
	blk ifNotNil: [ [ [ blk value: text ] on: Error do: [ :e | ] ] fork ]!

handshake
	self sendLine: 'CONNECT {"verbose":false,"pedantic":false,"tls_required":false,"name":"' , name , '","lang":"pharo","version":"0.1","protocol":1}'.
	self sendLine: 'PING'.
	connected := true.
	inboxSid := self nextSid.
	self sendLine: 'SUB ' , inboxPrefix , '.* ' , inboxSid.
	"Subscriptions belong to the client, not to the socket, so restore them all."
	subs keysAndValuesDo: [ :sid :entry |
		self sendLine: 'SUB ' , entry key , ' ' , sid ].
	onConnect ifNotNil: [
		[ [ onConnect value: self ]
			on: Error
			do: [ :e | self logString: 'onConnect raised: ' , e messageText printString ] ] fork ]! !

!NatsClient methodsFor: 'private-support'!
nextSid
	sidCounter := sidCounter + 1.
	^ sidCounter printString!

newId
	^ ((UUID new asString) copyWithout: $-) first: 12!

logString: aString
	Transcript show: '[nats:' , (name ifNil: [ '?' ]) , '] ' , aString; cr! !
