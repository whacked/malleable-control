TestCase subclass: #McSrtEditorTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McSrtEditorTest methodsFor: 'helpers'!
sampleSrt
	^ '1', String lf,
	  '00:02:37,801 --> 00:02:39,325', String lf,
	  'Let us have him.', String lf,
	  String lf,
	  '2', String lf,
	  '00:02:39,569 --> 00:02:42,436', String lf,
	  '- We''ve got to have him.', String lf,
	  '- Impossible, children.', String lf! !

!McSrtEditorTest methodsFor: 'tests - parsing'!
testParseSrtProducesEntries
	| entries |
	entries := McSrtEditor parseSrt: self sampleSrt.
	self assert: entries size equals: 2.
	self assert: entries first number equals: 1.
	self assert: entries first startTime equals: '00:02:37,801'.
	self assert: entries first endTime equals: '00:02:39,325'.
	self assert: entries first text equals: 'Let us have him.'.
	self assert: entries second number equals: 2.
	self assert: entries second text equals: ('- We''ve got to have him.', String lf, '- Impossible, children.')!

testParseSrtHandlesCRLF
	| crlf src entries |
	crlf := String crlf.
	src := '1', crlf, '00:00:01,000 --> 00:00:02,000', crlf, 'Hello', crlf, crlf.
	entries := McSrtEditor parseSrt: src.
	self assert: entries size equals: 1.
	self assert: entries first startTime equals: '00:00:01,000'.
	self assert: entries first text equals: 'Hello'!

testParseSrtSkipsTrailingBlanks
	| src entries |
	src := '1', String lf, '00:00:01,000 --> 00:00:02,000', String lf, 'Hi', String lf, String lf, String lf, String lf.
	entries := McSrtEditor parseSrt: src.
	self assert: entries size equals: 1! !

!McSrtEditorTest methodsFor: 'tests - serialization'!
testSerializeRoundTrip
	| entries serialized reparsed editor |
	entries := McSrtEditor parseSrt: self sampleSrt.
	"Build a temporary editor to call serializeSrt."
	editor := McSrtEditor new.
	editor initialize.
	editor instVarNamed: 'entries' put: entries.
	serialized := editor serializeSrt.
	reparsed := McSrtEditor parseSrt: serialized.
	self assert: reparsed size equals: 2.
	self assert: reparsed first startTime equals: '00:02:37,801'.
	self assert: reparsed first endTime equals: '00:02:39,325'.
	self assert: reparsed first text equals: 'Let us have him.'.
	self assert: reparsed second text equals: ('- We''ve got to have him.', String lf, '- Impossible, children.')!

testEntrySrtString
	| entry |
	entry := McSrtEntry number: 3 startTime: '00:01:00,000' endTime: '00:01:05,000' text: 'Hello world'.
	self assert: (entry asSrtString includesSubstring: '3').
	self assert: (entry asSrtString includesSubstring: '00:01:00,000 --> 00:01:05,000').
	self assert: (entry asSrtString includesSubstring: 'Hello world')! !

!McSrtEditorTest methodsFor: 'tests - building'!
testBuildPanelCreatesElements
	| editor panel |
	editor := McSrtEditor new.
	panel := editor buildPanel.
	self assert: panel isNotNil.
	self assert: editor listContainer isNotNil.
	self assert: editor panel identicalTo: panel!

testWorkbenchBuildViewCreatesPanels
	| workbench |
	workbench := McWorkbench new buildView.
	self assert: workbench srtEditor isNotNil.
	self assert: workbench space isNotNil! !

!McSrtEditorTest methodsFor: 'tests - file operations'!
testLoadFilePopulatesEntries
	| editor tmp |
	tmp := '/tmp/mc-srt-editor-test.srt' asFileReference.
	[ tmp writeStreamDo: [ :s | s nextPutAll: self sampleSrt ].
	  editor := McSrtEditor new.
	  editor buildPanel.
	  editor loadFile: tmp.
	  self assert: editor entries size equals: 2.
	  self deny: editor isDirty.
	  self assert: editor filePath equals: tmp asAbsolute
	] ensure: [ tmp ensureDelete ]!

testSaveWritesSerializedContent
	| editor tmp |
	tmp := '/tmp/mc-srt-editor-save-test.srt' asFileReference.
	[ tmp writeStreamDo: [ :s | s nextPutAll: self sampleSrt ].
	  editor := McSrtEditor new.
	  editor buildPanel.
	  editor loadFile: tmp.
	  "Mutate an entry through the model."
	  editor entries first text: 'Changed text'.
	  editor save.
	  self assert: (tmp contents includesSubstring: 'Changed text').
	  self deny: editor isDirty
	] ensure: [ tmp ensureDelete ]! !
