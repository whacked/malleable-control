"McRichEdit configuration.
 This file is evaluated as a Smalltalk expression and must answer a
 Dictionary mapping string keys to string values.  Override by placing
 a mc-config.st alongside this file."

Dictionary new
	at: 'demoFile' put: 'samples/demo.md';
	yourself
