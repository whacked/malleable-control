"
McRichEditPerfTest -- tests for the work McRichEdit does not do.

The editor restyles synchronously, and it used to do it twice for every
keystroke: once because the text changed, once again because the caret moved as
a result.  Three mechanisms cut that down, and each is only safe because of a
property that has to be pinned by a test rather than argued in a comment.

  1. McCursorProbe records where a styling pass' answers about the caret would
     have flipped.  The tests here check the recorded boundaries against the
     comparisons that produced them, and then check the claim those boundaries
     stand for directly: sweeping the caret across a document one position at a
     time, a step that crosses no boundary must leave every attribute exactly
     where it was.  That sweep is the real test -- it would fail if any cursor
     comparison escaped the probe.

  2. Parsing is reused while the source is unchanged.  The reuse is only sound
     if a styling pass leaves the parser alone, so the sweep above runs on one
     shared parser: a pass that mutated it would show up as a projection that
     depends on how many passes came before it.

  3. replaceFrom:to:with: edits the range in place instead of handing the editor
     a new rope.  Its tests compare against the string splice the old
     implementation performed, and check what the splice used to destroy: the
     text instance and the caret's position relative to the edit.

Requires McRelation.st, McMarkdownInline.st, McMarkdownTable.st, McSqlite.st,
McMarkdown.st and McRichEdit.st to be filed in first.

Chunk format: load with fileIn.
"!

TestCase subclass: #McRichEditPerfTest
	instanceVariableNames: 'sharedSource sharedParser sharedPalette'
	classVariableNames: ''
	package: 'MalleableControl'!

!McRichEditPerfTest methodsFor: 'helpers - documents'!
sampleDocument
	"One document holding every construct whose projection depends on the
	 caret: a header prefix, emphasis delimiters, a checkbox, a colour
	 swatch, a button, list markers, a quote bar, a fenced code block, a
	 table and a horizontal rule.  A database view is left out on purpose --
	 it shells out to sqlite3."
	^ '# Title

Some **bold** and _italic_ with #ff8800 and <<hello>> here.

A [link](note.md) and !![image](missing.png "caption").

- [ ] first
- second

> quoted line

| a | b |
| - | - |
| 1 | 2 |

---
'!

palette
	"Every key the visitor and the inline styler ask for.  Taken from a real
	 McRichEdit so the test cannot drift from the colours the editor uses."
	^ sharedPalette ifNil: [ sharedPalette := McRichEdit new palette ]! !

!McRichEditPerfTest methodsFor: 'helpers - styling'!
parserFor: aString
	"One parser per source for the whole test, which is also what makes the
	 sweep a test of parser reuse: every pass over the sample document shares
	 the parser the first pass built."
	(sharedSource notNil and: [ sharedSource = aString ])
		ifTrue: [ ^ sharedParser ].
	sharedParser := McMarkdownParser parseSource: aString.
	sharedSource := aString.
	^ sharedParser!

style: aString cursor: aCursor
	"Style aString as McRichEdit does and answer the decorated text.  aCursor
	 may be an Integer or an McCursorProbe -- the visitor cannot tell."
	| text parser |
	text := aString asRopedText.
	parser := self parserFor: aString.
	(McMarkdownStylerVisitor
		parser: parser
		text: text
		cursor: aCursor
		palette: self palette
		owner: nil) visit: parser root.
	^ text!

signatureOf: aString cursor: anInteger
	"Answer { attribute signature. recorded boundaries } for one pass."
	| probe text |
	probe := McCursorProbe on: anInteger.
	text := self style: aString cursor: probe.
	^ { self signatureOfText: text. probe boundaries }!

styleWith: aParser source: aString cursor: anInteger
	"Style through a parser the caller supplies, so a fresh parse and a reused
	 one can be compared."
	| text |
	text := aString asRopedText.
	(McMarkdownStylerVisitor
		parser: aParser
		text: text
		cursor: anInteger
		palette: self palette
		owner: nil) visit: aParser root.
	^ text!

signatureOfText: aText
	"A comparable description of everything the pass decided, index by index.
	 Attribute instances are new on every pass, so they are described by class
	 and by the paint they carry -- which is what separates a dimmed delimiter
	 from a titled one, the two cases a class name alone would confuse."
	^ (1 to: aText size) collect: [ :index |
		((aText attributesAt: index) collect: [ :each |
			String streamContents: [ :out |
				out nextPutAll: each class name.
				(each respondsTo: #paint) ifTrue: [
					out nextPutAll: '/'; nextPutAll: each paint asString ] ] ])
			asSortedCollection asArray ]! !

!McRichEditPerfTest methodsFor: 'helpers - editor'!
editorOn: aString
	"A BrEditor attached to a pulsed off-screen space, which is what makes its
	 editor model real: unattached, BrEditor answers a model that is not the
	 one its text lives in."
	| space editor |
	space := BlSpace new.
	space extent: 400 @ 300.
	editor := BrEditor new.
	editor aptitude: BrGlamorousRegularEditorAptitude new.
	editor text: aString asRopedText.
	editor constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ].
	space root addChild: editor.
	space pulse.
	^ editor!

instanceOn: aString
	"An McRichEdit wired to an off-screen editor without opening a window.
	 openView builds the whole window in one method, so the two instance
	 variables the text-mutation and restyle-gating paths read are set
	 directly rather than by taking the editor apart."
	| editor instance |
	editor := self editorOn: aString.
	instance := McRichEdit new.
	instance attachToEditor: editor.
	instance instVarNamed: 'statusLabel' put: BlTextElement new.
	^ instance!

spliceOf: aString from: start to: stop with: aReplacement
	"The string the old whole-document replaceFrom:to:with: produced."
	^ (aString copyFrom: 1 to: start - 1)
		, aReplacement
		, (aString copyFrom: stop + 1 to: aString size)! !

!McRichEditPerfTest methodsFor: 'tests - cursor probe'!
testProbeAnswersEveryComparisonLikeTheInteger
	| probe |
	probe := McCursorProbe on: 5.
	self assert: probe value equals: 5.
	self assert: probe >= 5.
	self deny: probe >= 6.
	self assert: probe <= 5.
	self deny: probe <= 4.
	self assert: probe > 4.
	self deny: probe > 5.
	self deny: probe < 0.
	self assert: probe < 6.
	self assert: probe = 5.
	self deny: probe = 4!

testProbeRecordsTheBoundaryOfGreaterOrEqual
	"cursor >= k is false below k and true from k on, so k is where it flips."
	| probe |
	probe := McCursorProbe on: 5.
	probe >= 7.
	self assert: (probe boundaries includes: 7)!

testProbeRecordsTheBoundaryOfLessOrEqual
	"cursor <= m is true up to m, so it flips one past it."
	| probe |
	probe := McCursorProbe on: 5.
	probe <= 7.
	self assert: (probe boundaries includes: 8).
	self deny: (probe boundaries includes: 7)!

testProbeRecordsTheBoundaryOfLessThan
	| probe |
	probe := McCursorProbe on: 5.
	probe < 0.
	self assert: (probe boundaries includes: 0)!

testProbeRecordsBothBoundsOfBetween
	| probe |
	probe := McCursorProbe on: 5.
	self assert: (probe between: 1 and: 9).
	self assert: (probe boundaries includes: 1).
	self assert: (probe boundaries includes: 10)!

testProbeRecordsNothingUntilAsked
	self assert: (McCursorProbe on: 5) boundaries isEmpty!

testProbeAbandonsTheRecordForAnUnknownMessage
	"An unrecognised message is forwarded so behaviour is unchanged, but the
	 boundary record is given up -- the caller then restyles every time."
	| probe |
	probe := McCursorProbe on: 5.
	probe >= 3.
	self assert: probe isTrusted.
	self assert: probe + 1 equals: 6.
	self deny: probe isTrusted.
	self assert: probe boundaries isNil!

testProbeAbandonsTheRecordForAComparisonWrittenBackwards
	"`position <= cursor' asks the same question as `cursor >= position' but
	 arrives through Pharo's coercion protocol rather than as a message the
	 probe declares, so it cannot be recorded.  It must still answer, and it
	 must give up the record."
	| probe |
	probe := McCursorProbe on: 5.
	self assert: 3 <= probe.
	self deny: 7 <= probe.
	self deny: probe isTrusted!

testProbeForwardsArithmeticAndAbandonsTheRecord
	| probe |
	probe := McCursorProbe on: 5.
	self assert: (probe max: 9) equals: 9.
	self deny: probe isTrusted!

testProbeStylesIdenticallyToAnInteger
	"The probe must be invisible to the pipeline: same document, same caret,
	 same attributes whether the cursor is wrapped or not."
	| source |
	source := self sampleDocument.
	#(-1 0 3 20 45 90) do: [ :cursor |
		self
			assert: (self signatureOfText: (self style: source cursor: (McCursorProbe on: cursor)))
			equals: (self signatureOfText: (self style: source cursor: cursor)) ]! !

!McRichEditPerfTest methodsFor: 'tests - boundary exactness'!
testBoundarySetCoversEveryProjectionChange
	"The claim the whole optimisation rests on: if a caret step crosses none
	 of the boundaries the previous pass recorded, the projection is
	 unchanged, so the restyle McRichEdit skips would have produced exactly
	 what is already on screen.

	 Checked by sweeping the caret one position at a time across a document
	 holding every cursor-sensitive construct.  A comparison that escaped the
	 probe would leave its flip unrecorded, and this would find it."
	| source size previous |
	source := self sampleDocument.
	size := source size.
	previous := self signatureOf: source cursor: 0.
	1 to: size do: [ :cursor |
		| current |
		current := self signatureOf: source cursor: cursor.
		self
			assert: previous second notNil
			description: 'the probe gave up its record at caret ' , (cursor - 1) printString.
		(previous second includes: cursor) ifFalse: [
			self
				assert: current first = previous first
				description: 'caret ' , (cursor - 1) printString , ' -> ' , cursor printString
					, ' crossed no recorded boundary but changed the projection' ].
		previous := current ]!

testBoundarySweepIsNotVacuous
	"The sweep above only means something if the projection really does change
	 as the caret moves, and if boundaries really are recorded."
	| source changes previous |
	source := self sampleDocument.
	changes := 0.
	previous := self signatureOf: source cursor: 0.
	1 to: source size do: [ :cursor |
		| current |
		current := self signatureOf: source cursor: cursor.
		current first = previous first ifFalse: [ changes := changes + 1 ].
		previous := current ].
	self assert: changes > 4.
	self assert: (self signatureOf: source cursor: 0) second size > 4!

testBoundariesAreRecordedForAnAwayCursor
	"A caret parked outside the document still records where it would have to
	 move to matter -- otherwise the first move would be free to skip."
	| probe |
	probe := McCursorProbe on: -1.
	self style: self sampleDocument cursor: probe.
	self assert: probe boundaries notEmpty!

testBoundarySetCoversDatabaseViewProjectionChanges
	"The database fence takes a cursor-dependent branch before choosing raw
	 source or a result widget.  A missing, unique path keeps the test free of
	 sqlite while still exercising that branch and its error projection."
	| path source previous |
	path := (FileLocator temp / ('mc-rich-edit-missing-' , UUID new asString , '.sqlite')) fullName.
	source := 'before

```sql&db=' , path , '
SELECT 1
```

after'.
	[ McSqliteSource clearCache.
	  previous := self signatureOf: source cursor: 0.
	  1 to: source size do: [ :cursor |
		| current |
		current := self signatureOf: source cursor: cursor.
		(previous second includes: cursor) ifFalse: [
			self
				assert: current first = previous first
				description: 'database-view projection changed without a recorded boundary' ].
		previous := current ] ]
		ensure: [ McSqliteSource clearCache ]! !

!McRichEditPerfTest methodsFor: 'tests - parser reuse'!
testParserIsReusedForUnchangedSource
	| instance first |
	instance := McRichEdit new.
	first := instance parserFor: '# Title'.
	self assert: (instance parserFor: '# Title' copy) == first!

testParserIsRebuiltForChangedSource
	| instance first |
	instance := McRichEdit new.
	first := instance parserFor: '# Title'.
	self deny: (instance parserFor: '# Titles') == first!

testReusedParserStylesLikeAFreshOne
	"Reuse is only safe if a pass leaves the parser as it found it."
	| source instance fresh reused |
	source := self sampleDocument.
	instance := McRichEdit new.
	fresh := self signatureOfText:
		(self styleWith: (McMarkdownParser parseSource: source) source: source cursor: 12).
	instance parserFor: source.
	self styleWith: (instance parserFor: source) source: source cursor: 40.
	reused := self signatureOfText:
		(self styleWith: (instance parserFor: source) source: source cursor: 12).
	self assert: reused equals: fresh! !

!McRichEditPerfTest methodsFor: 'tests - palette'!
testPaletteIsBuiltOncePerMode
	| instance light |
	instance := McRichEdit new.
	light := instance palette.
	self assert: instance palette == light.
	self assert: instance palette == light!

testPaletteIsRebuiltWhenTheModeChanges
	| instance light dark |
	instance := McRichEdit new.
	light := instance palette.
	instance darkMode: true.
	dark := instance palette.
	self deny: dark == light.
	self deny: (dark at: 'editorBg') = (light at: 'editorBg').
	instance darkMode: false.
	self assert: (instance palette at: 'editorBg') equals: (light at: 'editorBg')!

testPaletteHoldsTheKeysTheStylerAsks
	| palette |
	palette := McRichEdit new palette.
	#( 'text' 'title' 'boldText' 'dimDelimiter' 'highlight' 'editorBg' 'codeBg'
	   'codeText' 'rule' 'tableBorder' 'tableHeaderBg' 'quoteBar' 'quoteText'
	   'listMarker' 'link' 'deadLink' ) do: [ :key |
		self assert: (palette includesKey: key) description: 'missing ' , key ]! !

!McRichEditPerfTest methodsFor: 'tests - text mutation'!
testReplaceMatchesTheStringSplice
	"Every case the old whole-document rebuild handled, answered the same way."
	| source |
	source := 'abcdefghij'.
	{ { 3. 5. 'XY' }. { 1. 1. 'Z' }. { 1. 10. 'all' }. { 4. 4. '' }.
	  { 3. 2. 'ins' }. { 10. 10. 'Q' } } do: [ :each |
		| instance start stop replacement |
		start := each first.
		stop := each second.
		replacement := each third.
		instance := self instanceOn: source.
		instance replaceFrom: start to: stop with: replacement.
		self
			assert: instance editorElement editor text asString
				= (self spliceOf: source from: start to: (stop max: start - 1) with: replacement)
			description: 'replacing ' , start printString , '..' , stop printString ]!

testReplaceKeepsTheTextInstance
	"The point of editing in place: restoreText: threw the segment collector
	 away with the rope, and rebuilt every segment for a one-character edit."
	| instance before |
	instance := self instanceOn: '- [ ] task'.
	before := instance editorElement editor text.
	instance replaceFrom: 4 to: 4 with: 'x'.
	self assert: instance editorElement editor text == before.
	self assert: instance editorElement editor text asString equals: '- [x] task'!

testReplaceShiftsACaretAfterTheEdit
	| instance model |
	instance := self instanceOn: 'abcdefghij'.
	model := instance editorElement editor.
	model navigator moveTo: 9; apply.
	instance replaceFrom: 2 to: 4 with: 'X'.
	self assert: model text asString equals: 'aXefghij'.
	self assert: instance cursorPosition equals: 7!

testReplaceLeavesACaretBeforeTheEditAlone
	| instance model |
	instance := self instanceOn: 'abcdefghij'.
	model := instance editorElement editor.
	model navigator moveTo: 1; apply.
	instance replaceFrom: 5 to: 6 with: 'XYZ'.
	self assert: model text asString equals: 'abcdXYZghij'.
	self assert: instance cursorPosition equals: 1!

testReplaceOfEqualLengthLeavesTheCaretAlone
	"The checkbox case: one character swapped under a caret parked elsewhere."
	| instance model |
	instance := self instanceOn: '- [ ] task'.
	model := instance editorElement editor.
	model navigator moveTo: 8; apply.
	instance replaceFrom: 4 to: 4 with: 'x'.
	self assert: model text asString equals: '- [x] task'.
	self assert: instance cursorPosition equals: 8!

testReplaceClampsARangePastTheEnd
	| instance |
	instance := self instanceOn: 'abc'.
	instance replaceFrom: 2 to: 99 with: 'Z'.
	self assert: instance editorElement editor text asString equals: 'aZ'! !

!McRichEditPerfTest methodsFor: 'tests - file watching'!
testAChangedDocumentStampReloadsThroughTheEditor
	"Drive one watcher tick deterministically: no Delay and no background
	 process.  The queued UI task must update the existing editor rope."
	| ref instance text |
	ref := FileLocator temp / ('mc-rich-watch-' , UUID new asString , '.md').
	[ ref writeStreamDo: [ :stream | stream nextPutAll: 'old' ].
	  instance := self instanceOn: 'old'.
	  text := instance editorElement editor text.
	  instance instVarNamed: 'documentFile' put: ref.
	  instance instVarNamed: 'lastDocumentStamp' put: instance documentStamp.
	  ref writeStreamDo: [ :stream | stream nextPutAll: 'new and longer' ].
	  instance checkDocumentForChanges.
	  instance editorElement space pulse.
	  self assert: instance editorElement editor text == text.
	  self assert: instance editorElement editor text asString equals: 'new and longer' ]
		ensure: [ ref exists ifTrue: [ ref delete ] ]! !

!McRichEditPerfTest methodsFor: 'tests - restyle gating'!
gatingFixture
	"An editor on a document whose only cursor-sensitive construct is the
	 header on its first line, with a styler that counts its own runs.  The
	 count is an OrderedCollection so the test can read it back out."
	| instance editor runs |
	instance := self instanceOn: '# Title

plain paragraph text here
'.
	editor := instance editorElement.
	editor editor useSyncStylerStrategy.
	runs := OrderedCollection new.
	editor styler: (BlPluggableStyler new block: [ :aText |
		runs add: aText asString.
		instance styleText: aText ]).
	runs removeAll.
	^ { instance. editor editor. runs }!

testCursorMoveThatCrossesNoBoundaryDoesNotRestyle
	"Both positions sit inside the paragraph, well past the header's prefix,
	 so nothing about the projection can differ between them."
	| fixture instance model runs |
	fixture := self gatingFixture.
	instance := fixture first.
	model := fixture second.
	runs := fixture third.
	model navigator moveTo: 20; apply.
	model styleText.
	self assert: runs size equals: 1.
	model navigator moveTo: 22; apply.
	instance onCursorMoved.
	self assert: runs size equals: 1!

testCursorMoveOntoAHeaderRestyles
	"Moving from the paragraph onto the header crosses the end of the header's
	 range, which is where the # prefix stops being hidden."
	| fixture instance model runs |
	fixture := self gatingFixture.
	instance := fixture first.
	model := fixture second.
	runs := fixture third.
	model navigator moveTo: 20; apply.
	model styleText.
	self assert: runs size equals: 1.
	model navigator moveTo: 2; apply.
	instance onCursorMoved.
	self assert: runs size equals: 2!

testRepeatedMovesWithinOneRegionStaySkipped
	"Skipped moves are measured against the last pass, not against each other,
	 so wandering around inside the paragraph never accumulates into a
	 restyle -- and a move back out of it still does."
	| fixture instance model runs |
	fixture := self gatingFixture.
	instance := fixture first.
	model := fixture second.
	runs := fixture third.
	model navigator moveTo: 20; apply.
	model styleText.
	self assert: runs size equals: 1.
	#( 22 25 18 30 12 ) do: [ :position |
		model navigator moveTo: position; apply.
		instance onCursorMoved ].
	self assert: runs size equals: 1.
	model navigator moveTo: 4; apply.
	instance onCursorMoved.
	self assert: runs size equals: 2!

testCursorMoveRestylesWhenTheSourceChangedUnderneath
	"A backspace moves the caret before it deletes, so the cursor event can
	 arrive while the styled source is already stale."
	| fixture instance model runs |
	fixture := self gatingFixture.
	instance := fixture first.
	model := fixture second.
	runs := fixture third.
	model navigator moveTo: 20; apply.
	model styleText.
	self assert: runs size equals: 1.
	instance
		instVarNamed: 'lastStyledSource'
		put: model text asString , ' drifted'.
	model navigator moveTo: 22; apply.
	instance onCursorMoved.
	self assert: runs size equals: 2!

testCursorMoveRestylesWithNoRecordedPass
	| fixture instance model runs |
	fixture := self gatingFixture.
	instance := fixture first.
	model := fixture second.
	runs := fixture third.
	instance invalidateStyleState.
	model navigator moveTo: 12; apply.
	instance onCursorMoved.
	self assert: runs size equals: 1! !

!McRichEditPerfTest methodsFor: 'tests - retained renderer seams'!
testStylingSuspensionIsNestingSafe
	| instance |
	instance := McRichEdit new.
	self deny: instance isStylingSuspended.
	instance beginStylingSuspension; beginStylingSuspension.
	self assert: instance isStylingSuspended.
	instance endStylingSuspension.
	self assert: instance isStylingSuspended.
	instance endStylingSuspension.
	self deny: instance isStylingSuspended!

testPendingEditDescriptorIsConsumedOnlyByTheExpectedRopeSize
	| instance descriptor |
	instance := McRichEdit new.
	instance notePendingEditFrom: 3 to: 4 replacement: 'abc' expectedSize: 12.
	self assert: (instance consumePendingEditDescriptorFor: '123456789012' asRopedText) notNil.
	instance notePendingEditFrom: 3 to: 4 replacement: 'abc' expectedSize: 12.
	descriptor := instance consumePendingEditDescriptorFor: 'short' asRopedText.
	self assert: descriptor isNil.
	self assert: instance pendingEditDescriptor isNil! !

!McRichEditPerfTest methodsFor: 'tests - search'!
testProgrammaticSearchAnswersStructuredRangesAndNavigates
	| instance result |
	instance := self instanceOn: 'link and link'.
	result := instance searchFor: 'link'.
	self assert: (result at: #matchCount) equals: 2.
	self assert: (result at: #ranges) equals: #((1 4) (10 13)).
	self assert: (result at: #activeRange) equals: #(1 4).
	result := instance nextSearch.
	self assert: (result at: #activeIndex) equals: 2.
	self assert: (result at: #activeRange) equals: #(10 13).
	instance cancelSearch.
	self assert: instance searchSession isNil! !
