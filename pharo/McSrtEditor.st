"
McSrtEditor -- Tabular SRT subtitle editor for Glamorous Toolkit.

Parses an SRT file into McSrtEntry objects and presents them in a structured
table: index (read-only), start time, end time, and subtitle text (all
editable).  Edits flow back through the model; Save serializes the entries
to SRT format and overwrites the file.

This exercises a rich structured view with real-time mapping back to a flat
text format, similar to what McRichEdit does for Markdown.

Standalone:
    (Smalltalk at: #McSrtEditor) open.
Hosted inside the Workbench:
    (Smalltalk at: #McWorkbench) open.
"!

"--- McSrtEntry: model for a single subtitle entry ---"!

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

"--- McSrtEditor: tabular editor ---"!

Object subclass: #McSrtEditor
	instanceVariableNames: 'filePath entries dirty panel listContainer pathLabel dirtyLabel saveButton savedContent loading'
	classVariableNames: ''
	package: 'MalleableControl'!

!McSrtEditor class methodsFor: 'opening'!
open
	| space editor |
	editor := self new.
	space := BlSpace new.
	space title: 'SRT Editor'.
	space extent: 800 @ 600.
	space root addChild: editor buildPanel.
	space show.
	^ editor! !

!McSrtEditor class methodsFor: 'parsing'!
parseSrt: aString
	"Parse an SRT string into an OrderedCollection of McSrtEntry.
	 Handles LF, CR, or CRLF line endings."
	| allLines entries currentBlock |
	allLines := aString lines.
	entries := OrderedCollection new.
	currentBlock := OrderedCollection new.
	allLines do: [ :line |
		line trim isEmpty
			ifTrue: [
				currentBlock isEmpty ifFalse: [
					entries add: (self parseBlock: currentBlock asArray).
					currentBlock := OrderedCollection new ] ]
			ifFalse: [ currentBlock add: line ] ].
	currentBlock isEmpty ifFalse: [
		entries add: (self parseBlock: currentBlock asArray) ].
	^ entries!

parseBlock: lines
	"Parse a single SRT block (array of non-empty lines) into an McSrtEntry."
	| number tsLine arrowIdx startTime endTime textLines |
	number := lines first trim asInteger.
	tsLine := lines second.
	arrowIdx := tsLine findString: ' --> ' startingAt: 1.
	arrowIdx = 0
		ifTrue: [ startTime := tsLine. endTime := '' ]
		ifFalse: [
			startTime := (tsLine copyFrom: 1 to: arrowIdx - 1) trim.
			endTime := (tsLine copyFrom: arrowIdx + 5 to: tsLine size) trim ].
	textLines := lines size > 2
		ifTrue: [ lines copyFrom: 3 to: lines size ]
		ifFalse: [ #() ].
	^ McSrtEntry
		number: number
		startTime: startTime
		endTime: endTime
		text: (String lf join: textLines)! !

!McSrtEditor methodsFor: 'initialization'!
initialize
	super initialize.
	loading := false.
	dirty := false.
	savedContent := ''.
	entries := OrderedCollection new! !

!McSrtEditor methodsFor: 'building'!
buildPanel
	| toolbar headerRow scrollable |
	panel := BlElement new.
	panel layout: BlLinearLayout vertical.
	panel constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ].
	panel background: (Color fromHexString: '#1e1e2e').
	toolbar := self buildToolbar.
	panel addChild: toolbar.
	headerRow := self buildHeaderRow.
	panel addChild: headerRow.
	"Scrollable list of entry rows."
	listContainer := BlElement new.
	listContainer layout: BlLinearLayout vertical.
	listContainer constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ].
	scrollable := BlScrollableElement new.
	scrollable constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ].
	scrollable addChild: listContainer.
	panel addChild: scrollable.
	^ panel!

buildToolbar
	| toolbar openButton |
	toolbar := BlElement new.
	toolbar layout: BlLinearLayout horizontal.
	toolbar constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ].
	toolbar padding: (BlInsets top: 8 right: 8 bottom: 8 left: 8).
	toolbar background: (Color fromHexString: '#2d2d3a').
	openButton := BrButton new.
	openButton label: 'Open'.
	openButton aptitude: BrGlamorousButtonWithLabelAptitude new.
	openButton action: [ self openFilePicker ].
	toolbar addChild: openButton.
	pathLabel := BrLabel new.
	pathLabel text: ('No file loaded' asRopedText
		foreground: (Color fromHexString: '#a0a0b0'); fontSize: 13).
	pathLabel constraintsDo: [ :c |
		c horizontal matchParent.
		c linear vertical alignCenter ].
	pathLabel margin: (BlInsets left: 12 right: 8).
	toolbar addChild: pathLabel.
	dirtyLabel := BrLabel new.
	dirtyLabel text: '' asRopedText.
	dirtyLabel constraintsDo: [ :c |
		c horizontal fitContent.
		c linear vertical alignCenter ].
	dirtyLabel margin: (BlInsets right: 8).
	toolbar addChild: dirtyLabel.
	saveButton := BrButton new.
	saveButton label: 'Save'.
	saveButton aptitude: BrGlamorousButtonWithLabelAptitude new.
	saveButton action: [ self save ].
	saveButton enabled: false.
	toolbar addChild: saveButton.
	^ toolbar!

buildHeaderRow
	"Column header labels matching the data row widths."
	| row |
	row := BlElement new.
	row layout: BlLinearLayout horizontal.
	row constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ].
	row padding: (BlInsets top: 6 right: 8 bottom: 6 left: 8).
	row background: (Color fromHexString: '#252538').
	row addChild: (self headerLabel: '#' width: 50).
	row addChild: (self headerLabel: 'Start' width: 150).
	row addChild: (self headerLabel: 'End' width: 150).
	row addChild: (self headerLabel: 'Lines' width: nil).
	^ row!

headerLabel: aString width: widthOrNil
	| lbl |
	lbl := BrLabel new.
	lbl text: (aString asRopedText foreground: (Color fromHexString: '#8888a0'); bold; fontSize: 12).
	lbl constraintsDo: [ :c |
		widthOrNil
			ifNil: [ c horizontal matchParent ]
			ifNotNil: [ c horizontal exact: widthOrNil ].
		c vertical fitContent ].
	lbl margin: (BlInsets right: 4).
	^ lbl!

buildEntryRow: anEntry index: anIndex
	"One table row: read-only index, editable start/end/text."
	| row bg indexLabel startEditor endEditor textEditor separator cells |
	bg := anIndex even
		ifTrue: [ Color fromHexString: '#282840' ]
		ifFalse: [ Color fromHexString: '#2d2d4a' ].
	row := BlElement new.
	row layout: BlLinearLayout vertical.
	row constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ].
	row background: bg.
	"Data cells in a horizontal row."
	cells := BlElement new.
	cells layout: BlLinearLayout horizontal.
	cells constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ].
	cells padding: (BlInsets top: 4 right: 8 bottom: 4 left: 8).
	indexLabel := BrLabel new.
	indexLabel text: (anEntry number printString asRopedText
		foreground: (Color fromHexString: '#666680'); bold; fontSize: 13).
	indexLabel constraintsDo: [ :c | c horizontal exact: 50. c vertical fitContent ].
	cells addChild: indexLabel.
	startEditor := self timecodeEditorFor: anEntry startTime.
	startEditor editor when: BrTextEditorModifiedEvent do: [ :e |
		anEntry startTime: startEditor text asString. self markDirty ].
	cells addChild: startEditor.
	endEditor := self timecodeEditorFor: anEntry endTime.
	endEditor editor when: BrTextEditorModifiedEvent do: [ :e |
		anEntry endTime: endEditor text asString. self markDirty ].
	cells addChild: endEditor.
	textEditor := BrEditor new.
	textEditor aptitude: (BrGlamorousRegularEditorAptitude new
		foreground: (Color fromHexString: '#e0e0e0'); fontSize: 13).
	textEditor text: anEntry text asRopedText.
	textEditor constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ].
	textEditor padding: (BlInsets left: 4).
	textEditor editor when: BrTextEditorModifiedEvent do: [ :e |
		anEntry text: textEditor text asString. self markDirty ].
	cells addChild: textEditor.
	row addChild: cells.
	"Thin separator line."
	separator := BlElement new.
	separator constraintsDo: [ :c | c horizontal matchParent. c vertical exact: 1 ].
	separator background: (Color fromHexString: '#3a3a5a').
	row addChild: separator.
	^ row!

timecodeEditorFor: aTimeString
	"Small fixed-width editor for a timecode cell."
	| ed |
	ed := BrEditor new.
	ed aptitude: (BrGlamorousRegularEditorAptitude new
		foreground: (Color fromHexString: '#4a9eff'); fontSize: 13).
	ed text: aTimeString asRopedText.
	ed constraintsDo: [ :c | c horizontal exact: 150. c vertical fitContent ].
	ed padding: (BlInsets left: 2 right: 4).
	^ ed!

rebuildList
	"Clear the list container and recreate rows from the entries model."
	listContainer removeChildren.
	entries doWithIndex: [ :entry :idx |
		listContainer addChild: (self buildEntryRow: entry index: idx) ]! !

!McSrtEditor methodsFor: 'file operations'!
openFilePicker
	"Show the native macOS file-open dialog, filtered to *.srt."
	[ | process path |
		process := GtSubprocessWithInMemoryOutput new
			command: '/usr/bin/osascript';
			arguments: {
				'-e'.
				'POSIX path of (choose file of type {"srt"} with prompt "Open SRT File")' };
			runAndWait.
		process exitCode = 0 ifTrue: [
			path := process stdout trimBoth.
			panel space enqueueTask: (BlTaskAction new action: [
				self loadFile: path asFileReference ]) ]
	] fork!

loadFile: aFileReference
	| ref contents |
	ref := aFileReference asFileReference asAbsolute.
	(ref exists and: [ ref isFile ]) ifFalse: [
		pathLabel text: ('File not found' asRopedText foreground: Color red; fontSize: 13).
		^ self ].
	contents := ref contents.
	filePath := ref.
	savedContent := contents.
	loading := true.
	entries := self class parseSrt: contents.
	self rebuildList.
	loading := false.
	pathLabel text: (ref basename asRopedText
		foreground: (Color fromHexString: '#e0e0e0'); fontSize: 13).
	self markClean!

save
	| serialized |
	filePath ifNil: [ ^ self ].
	serialized := self serializeSrt.
	filePath writeStreamDo: [ :s | s nextPutAll: serialized ].
	savedContent := serialized.
	self markClean! !

!McSrtEditor methodsFor: 'serialization'!
serializeSrt
	"Serialize the entries model back to SRT format."
	^ String streamContents: [ :stream |
		entries do: [ :entry |
			stream nextPutAll: entry asSrtString.
			stream nextPut: Character lf.
			stream nextPut: Character lf ] ]! !

!McSrtEditor methodsFor: 'dirty tracking'!
markDirty
	loading ifTrue: [ ^ self ].
	dirty := true.
	dirtyLabel text: ('●' asRopedText
		foreground: (Color fromHexString: '#ff6b6b'); fontSize: 16).
	saveButton enabled: filePath notNil!

markClean
	dirty := false.
	dirtyLabel text: '' asRopedText.
	saveButton enabled: false!

isDirty
	^ dirty! !

!McSrtEditor methodsFor: 'accessing'!
filePath
	^ filePath!

entries
	^ entries!

panel
	^ panel!

listContainer
	^ listContainer! !
