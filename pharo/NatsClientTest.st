"
Framing tests for NatsClient. No server involved.

Framing is the part of a NATS client that actually breaks: MSG carries a
payload length in BYTES, messages arrive split across arbitrary TCP reads, and
several can land in one read. Each of those is a case below.
"!

TestCase subclass: #NatsClientTest
	instanceVariableNames: 'client received'
	classVariableNames: ''
	package: 'MalleableControl'!

!NatsClientTest methodsFor: 'running'!
setUp
	super setUp.
	received := OrderedCollection new.
	client := (Smalltalk at: #NatsClient) on: '127.0.0.1' port: 4223 name: 'test'!

collect
	"Subscribe a collector. Offline, so no SUB frame is sent anywhere."
	^ client subscribe: 'foo' do: [ :subject :payload :replyTo |
		received add: (Array with: subject with: payload with: replyTo) ]!

feed: aString
	"Push bytes into the parser exactly as the read loop would."
	client instVarNamed: 'inbuf' put: (client instVarNamed: 'inbuf') , aString utf8Encoded.
	client drain!

feedBytes: aByteArray
	client instVarNamed: 'inbuf' put: (client instVarNamed: 'inbuf') , aByteArray.
	client drain!

settle
	"Handlers are dispatched in forked processes, so give them a moment."
	(Delay forMilliseconds: 150) wait! !

!NatsClientTest methodsFor: 'tests-header'!
testParseMsgHeaderWithoutReply
	| h |
	h := client parseMsgHeader: 'MSG foo.bar 1 11'.
	self assert: (h at: 1) equals: 'foo.bar'.
	self assert: (h at: 2) equals: '1'.
	self assert: (h at: 3) equals: nil.
	self assert: (h at: 4) equals: 11!

testParseMsgHeaderWithReply
	| h |
	h := client parseMsgHeader: 'MSG foo.bar 1 _INBOX.abc.1 11'.
	self assert: (h at: 1) equals: 'foo.bar'.
	self assert: (h at: 3) equals: '_INBOX.abc.1'.
	self assert: (h at: 4) equals: 11!

testParseMsgHeaderMalformedSignals
	self should: [ client parseMsgHeader: 'MSG foo.bar' ] raise: Error! !

!NatsClientTest methodsFor: 'tests-framing'!
testIndexOfCRLF
	"utf8Encoded matters: the buffer is always a ByteArray, and indexOfCRLF
	 compares byte values. Handed a String it would compare Characters to 13
	 and never match."
	client instVarNamed: 'inbuf' put: ('ab' , String crlf , 'cd') utf8Encoded.
	self assert: client indexOfCRLF equals: 3.
	client instVarNamed: 'inbuf' put: 'no terminator here' utf8Encoded.
	self assert: client indexOfCRLF equals: nil!

testDeliversAWholeMessage
	self collect.
	self feed: 'MSG foo 1 5' , String crlf , 'hello' , String crlf.
	self settle.
	self assert: received size equals: 1.
	self assert: (received first at: 2) equals: 'hello'!

testMessageSplitAcrossReads
	"A message arriving in three reads must be delivered once, whole."
	self collect.
	self feed: 'MSG foo 1 '.
	self assert: received isEmpty.
	self feed: '11' , String crlf , 'hello'.
	self assert: received isEmpty.
	self feed: ' world' , String crlf.
	self settle.
	self assert: received size equals: 1.
	self assert: (received first at: 2) equals: 'hello world'!

testTwoMessagesInOneRead
	self collect.
	self feed: 'MSG foo 1 3' , String crlf , 'abc' , String crlf ,
		'MSG foo 1 3' , String crlf , 'def' , String crlf.
	self settle.
	self assert: received size equals: 2.
	self assert: (received first at: 2) equals: 'abc'.
	self assert: (received second at: 2) equals: 'def'!

testPayloadLengthIsBytesNotCharacters
	"The regression that motivated keeping the buffer a ByteArray throughout.
	 This string is 7 characters but 10 bytes. A parser that measures in
	 characters desynchronises here and corrupts everything after it."
	| text bytes stream |
	text := 'héllo ☃'.
	bytes := text utf8Encoded.
	self assert: text size equals: 7.
	self assert: bytes size equals: 10.
	self collect.
	stream := WriteStream on: ByteArray new.
	stream nextPutAll: ('MSG foo 1 10' , String crlf) utf8Encoded.
	stream nextPutAll: bytes.
	stream nextPutAll: String crlf utf8Encoded.
	self feedBytes: stream contents.
	self settle.
	self assert: received size equals: 1.
	self assert: (received first at: 2) equals: text!

testReplyToIsPassedThrough
	self collect.
	self feed: 'MSG foo 1 _INBOX.x.1 2' , String crlf , 'hi' , String crlf.
	self settle.
	self assert: (received first at: 3) equals: '_INBOX.x.1'!

testUnknownSidIsIgnored
	self feed: 'MSG nobody 99 2' , String crlf , 'hi' , String crlf.
	self settle.
	self assert: received isEmpty.
	self assert: (client instVarNamed: 'inbuf') isEmpty! !

!NatsClientTest methodsFor: 'tests-handshake'!
testSecondInfoDoesNotReHandshake
	"The server sends another INFO after CONNECT because we announce protocol 1.
	 Treating that as a second handshake subscribes everything twice and makes
	 the client reply twice to every request."
	| firstInboxSid |
	client handleLine: 'INFO {}'.
	firstInboxSid := client instVarNamed: 'inboxSid'.
	self assert: client isConnected.
	self deny: firstInboxSid isNil.
	client handleLine: 'INFO {}'.
	self assert: (client instVarNamed: 'inboxSid') equals: firstInboxSid! !
