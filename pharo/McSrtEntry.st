"
McSrtEntry -- Model for a single SRT subtitle entry.

Each entry holds an index number, start/end timestamps (as strings in
HH:MM:SS,MMM format), and the subtitle text (which may contain newlines
for multi-line subtitles).
"!

Object subclass: #McSrtEntry
	instanceVariableNames: 'number startTime endTime text'
	classVariableNames: ''
	package: 'MalleableControl'!

!McSrtEntry class methodsFor: 'instance creation'!
number: anInteger startTime: aStart endTime: anEnd text: aString
	^ self new
		number: anInteger;
		startTime: aStart;
		endTime: anEnd;
		text: aString;
		yourself! !

!McSrtEntry methodsFor: 'accessing'!
number
	^ number!

number: anInteger
	number := anInteger!

startTime
	^ startTime!

startTime: aString
	startTime := aString!

endTime
	^ endTime!

endTime: aString
	endTime := aString!

text
	^ text!

text: aString
	text := aString! !

!McSrtEntry methodsFor: 'serialization'!
asSrtString
	"Serialize this entry to SRT format (without trailing blank line)."
	^ String streamContents: [ :s |
		s nextPutAll: number printString.
		s nextPut: Character lf.
		s nextPutAll: startTime.
		s nextPutAll: ' --> '.
		s nextPutAll: endTime.
		s nextPut: Character lf.
		s nextPutAll: text ]! !

!McSrtEntry methodsFor: 'printing'!
printOn: aStream
	super printOn: aStream.
	aStream nextPutAll: '('.
	aStream nextPutAll: number printString.
	aStream nextPutAll: ' '.
	aStream nextPutAll: (startTime ifNil: [ '?' ]).
	aStream nextPutAll: ')'! !
