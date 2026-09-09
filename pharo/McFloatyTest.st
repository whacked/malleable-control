TestCase subclass: #McFloatyTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McFloatyTest methodsFor: 'samples'!
markdownSample
	"The top comment is the host and owns the whole file.  Section A nests
	 inside it and Sub inside A, each introduced by the directive above its
	 heading.  Title and Section B carry no directive of their own and so are
	 not cards at all."
	^ String lf join: #(
		'<!!-- f@800x600+10-20 -->'
		'# Title'
		'intro body'
		''
		'<!!-- f@50%x25%+5%+2% -->'
		'## Section A'
		'body A'
		''
		'<!!-- f@40%x30%+1%+1% -->'
		'### Sub'
		'body sub'
		''
		'## Section B'
		'body B')!

flatSample
	^ String lf join: #(
		';;; f@900x700+0+0'
		'(defun host ())'
		''
		';;; f@30%x20%+5%+5%'
		'(defun child-one ())'
		';;; f@end'
		''
		';;; f@30%x20%+5%+30%'
		'(defun child-two ())')!

markdown: aString
	^ McFloatyDocument on: aString markdown: true!

flat: aString
	^ McFloatyDocument on: aString markdown: false! !

!McFloatyTest methodsFor: 'tests - measure'!
testMeasureParsesSignedIntegersAndPercents
	self assert: (McFloatyMeasure parse: '330') value equals: 330.
	self deny: (McFloatyMeasure parse: '330') isPercent.
	self assert: (McFloatyMeasure parse: '-120') value equals: -120.
	self assert: (McFloatyMeasure parse: '+420') value equals: 420.
	self assert: (McFloatyMeasure parse: '50%') value equals: 50.
	self assert: (McFloatyMeasure parse: '50%') isPercent.
	self assert: (McFloatyMeasure parse: '-5%') value equals: -5!

testMeasureRejectsAnythingElse
	#('' ' 12' '12 ' '12px' '--2' '+' '-' '%' '5%%' 'x' '1.5')
		do: [ :each | self assert: (McFloatyMeasure parse: each) isNil ]!

testDimensionRejectsASignAndOffsetRequiresOne
	self assert: (McFloatyMeasure parseDimension: '40') value equals: 40.
	self assert: (McFloatyMeasure parseDimension: '+40') isNil.
	self assert: (McFloatyMeasure parseDimension: '-40') isNil.
	self assert: (McFloatyMeasure parseOffset: '+40') value equals: 40.
	self assert: (McFloatyMeasure parseOffset: '40') isNil!

testPercentResolvesAgainstTheParentBox
	self assert: ((McFloatyMeasure percent: 50) resolveAgainst: 800) equals: 400.
	self assert: ((McFloatyMeasure percent: 25) resolveAgainst: 600) equals: 150.
	self assert: ((McFloatyMeasure px: 330) resolveAgainst: 800) equals: 330! !

!McFloatyTest methodsFor: 'tests - geometry'!
testGeometryParsesAbsoluteAndSignedOffsets
	| geometry |
	geometry := McFloatyGeometry parse: '330x230+420-120'.
	self assert: geometry width value equals: 330.
	self assert: geometry height value equals: 230.
	self assert: geometry x value equals: 420.
	self assert: geometry y value equals: -120.
	self assert: geometry asDirectiveString equals: 'f@330x230+420-120'!

testGeometryParsesPercentsPerComponent
	| geometry mixed |
	geometry := McFloatyGeometry parse: '50%x25%+5%+2%'.
	self assert: geometry width isPercent.
	self assert: geometry y value equals: 2.
	self assert: geometry hasPercent.
	"Each of the four numbers carries its own unit, so a fixed width may sit
	 next to a proportional offset."
	mixed := McFloatyGeometry parse: '50%x230+5%-120'.
	self assert: mixed width isPercent.
	self deny: mixed height isPercent.
	self assert: mixed x isPercent.
	self deny: mixed y isPercent.
	self assert: mixed asDirectiveString equals: 'f@50%x230+5%-120'!

testGeometryDefaultsMissingOffsetsToTheParentOrigin
	| geometry |
	geometry := McFloatyGeometry parse: '40x10'.
	self assert: geometry x value equals: 0.
	self assert: geometry y value equals: 0.
	self assert: geometry asDirectiveString equals: 'f@40x10+0+0'!

testGeometryRejectsIncompleteForms
	#('' '40' '40x' 'x10' '40x10+' '40x10+5' '40x10+5+' '-40x10' '40x-10' '40X10')
		do: [ :each | self assert: (McFloatyGeometry parse: each) isNil ]!

testGeometryResolvesInsideTheParentBox
	| geometry |
	geometry := McFloatyGeometry parse: '50%x25%+5%+2%'.
	self assert: (geometry extentIn: 800 @ 600) equals: 400 @ 150.
	self assert: (geometry positionIn: 800 @ 600) equals: 40 @ 12! !

!McFloatyTest methodsFor: 'tests - markdown hierarchy'!
testMarkdownNestsCardsByHeadingLevel
	| document host sectionA |
	document := self markdown: self markdownSample.
	self assert: document roots size equals: 1.
	host := document roots first.
	self assert: host label equals: 'document'.
	self assert: host level equals: 0.
	self assert: host children size equals: 1.
	sectionA := host children first.
	self assert: sectionA label equals: 'Section A'.
	self assert: sectionA level equals: 2.
	self assert: sectionA children size equals: 1.
	self assert: sectionA children first label equals: 'Sub'.
	self assert: sectionA children first level equals: 3!

testMarkdownSectionWithoutADirectiveIsNotACard
	| document |
	document := self markdown: self markdownSample.
	self assert: (document directiveLabelled: 'Section B') isNil.
	self assert: (document directiveLabelled: 'Title') isNil.
	self assert: document allDirectives size equals: 3!

testOnlyTheTopCommentIsTheHost
	"Being first is the whole of what makes a directive the host.  The same
	 directive one line lower governs the heading above it instead."
	| top lower |
	top := self markdown: (String lf join: #(
		'<!!-- f@800x600+0+0 -->'
		'# Title'
		'body')).
	self assert: top roots first label equals: 'document'.
	self assert: top roots first level equals: 0.
	self assert: top roots first regionStart equals: 1.
	lower := self markdown: (String lf join: #(
		'# Title'
		'<!!-- f@800x600+0+0 -->'
		'body')).
	self assert: lower roots first label equals: 'Title'.
	self assert: lower roots first level equals: 1.
	self deny: lower roots first regionStart equals: 1!

testDirectiveAboveAHeadingTakesTheHeadingIntoTheCard
	| document card |
	document := self markdown: self markdownSample.
	card := document directiveLabelled: 'Section A'.
	self assert: ((document renderRange: card regionRange)
		includesSubstring: '## Section A')!

testDirectiveBelowAHeadingLeavesTheHeadingBehind
	"The card starts at its own directive, so a heading above that line stays
	 with the host rather than being pulled into the card."
	| document card |
	document := self markdown: (String lf join: #(
		'# Host'
		'## Section A'
		'<!!-- f@50%x25%+0+0 -->'
		'body A')).
	card := document directiveLabelled: 'Section A'.
	self deny: ((document renderRange: card regionRange)
		includesSubstring: '## Section A').
	self assert: ((document renderRange: card regionRange)
		includesSubstring: 'body A')!

testEveryCardOpensWithItsOwnDirective
	"A card too short to scroll must still show what positions it."
	| document |
	document := self markdown: self markdownSample.
	self assert: document allDirectives size equals: 3.
	document allDirectives do: [ :each |
		self assert: (document renderRange: each regionRange) lines first trimBoth
			equals: each directiveLine trimBoth ]!

testHostRegionIsTheWholeDocument
	"The host keeps showing the whole text, as floaty's host buffer does."
	| document title |
	document := self markdown: self markdownSample.
	title := document roots first.
	self assert: title regionStart equals: 1.
	self assert: title regionStop equals: self markdownSample size!

testChildRegionStopsAtTheNextSectionOfItsOwnLevel
	| document sectionA region |
	document := self markdown: self markdownSample.
	sectionA := document directiveLabelled: 'Section A'.
	region := document renderRange: sectionA regionRange.
	self assert: (region includesSubstring: 'body A').
	self assert: (region includesSubstring: 'body sub').
	self deny: (region includesSubstring: 'body B').
	self deny: (region includesSubstring: 'intro body')!

testHostStillShowsEveryChildSection
	"The host keeps the whole text, so nothing a child card lifts out goes
	 missing from it."
	| document region |
	document := self markdown: self markdownSample.
	region := document renderRange: document roots first regionRange.
	#('intro body' 'body A' 'body sub' 'body B') do: [ :each |
		self assert: (region includesSubstring: each) ]!

testHeadingInsideACodeFenceDoesNotOpenASection
	"The payoff for reading headings from McMarkdownParser rather than scanning
	 for a leading hash: the fenced heading is not a section, so the directive
	 below it still belongs to Title -- and being the second directive in that
	 one section, it is left as ordinary text rather than describing the card
	 twice."
	| document |
	document := self markdown: (String lf join: #(
		'# Title'
		'<!!-- f@800x600+0+0 -->'
		''
		'```text'
		'## Fake heading'
		'```'
		'<!!-- f@50%x25%+0+0 -->'
		'body')).
	self assert: document roots size equals: 1.
	self assert: document allDirectives size equals: 1.
	self assert: document roots first label equals: 'Title'!

testHashCommentIsNotADirectiveInMarkdown
	"## opens a heading in markdown, so it cannot also be the comment that
	 configures the section it opens."
	| document |
	document := self markdown: (String lf join: #(
		'# Title'
		'## f@40x10+0+0'
		'body')).
	self assert: document allDirectives isEmpty! !

!McFloatyTest methodsFor: 'tests - markdown hierarchy'!
testMarkdownEndDirectiveClosesASection
	"A section normally runs to the next heading at or above its level.  An
	 f@end stops the card earlier, and what is left of the section stays with
	 the host, which owns the whole file anyway."
	| document child region |
	document := self markdown: (String lf join: #(
		'<!!-- f@800x600+0+0 -->'
		'# Doc'
		''
		'<!!-- f@50%x40%+5%+5% -->'
		'## Section A'
		'inside A'
		'<!!-- f@end -->'
		'past the end'
		''
		'## Section B'
		'body B')).
	child := document roots first children first.
	region := document renderRange: child regionRange.
	self assert: (region includesSubstring: 'inside A').
	self deny: (region includesSubstring: 'past the end').
	self deny: (region includesSubstring: 'Section B')! !

!McFloatyTest methodsFor: 'tests - markdown hierarchy'!
testMarkdownEndDirectiveCannotExtendASection
	"An f@end only ever shortens.  One sitting beyond the heading that already
	 ends the section changes nothing."
	| document child region |
	document := self markdown: (String lf join: #(
		'<!!-- f@800x600+0+0 -->'
		'# Doc'
		''
		'<!!-- f@50%x40%+5%+5% -->'
		'## Section A'
		'inside A'
		''
		'## Section B'
		'body B'
		'<!!-- f@end -->')).
	child := document roots first children first.
	region := document renderRange: child regionRange.
	self assert: (region includesSubstring: 'inside A').
	self deny: (region includesSubstring: 'body B')! !

!McFloatyTest methodsFor: 'tests - flat hierarchy'!
testFlatFileHostsTheWholeDocumentFromItsFirstLine
	| document host |
	document := self flat: self flatSample.
	self assert: document roots size equals: 1.
	host := document roots first.
	self assert: host label equals: 'document'.
	self assert: host regionStart equals: 1.
	self assert: host regionStop equals: self flatSample size.
	self assert: host children size equals: 2!

testFlatChildrenAreLabelledByTheirFirstRealLine
	| document |
	document := self flat: self flatSample.
	self assert: (document roots first children collect: [ :each | each label ])
		equals: #('(defun child-one ())' '(defun child-two ())')!

testFlatEndDirectiveClosesARegion
	"Nothing follows the f@end here, so it is the only thing that can close the
	 region.  The flatSample alone would not prove this: there the next
	 directive closes the card whether or not the f@end is understood."
	| document childOne region |
	document := self flat: (String lf join: #(
		';;; f@900x700+0+0'
		'(defun host ())'
		''
		';;; f@30%x20%+5%+5%'
		'(defun child-one ())'
		';;; f@end'
		'(defun after-the-end ())')).
	childOne := document roots first children first.
	region := document renderRange: childOne regionRange.
	self assert: (region includesSubstring: 'child-one').
	self deny: (region includesSubstring: 'after-the-end')!

testFlatFileWithoutALeadingDirectiveHasNoHost
	| document |
	document := self flat: (String lf join: #(
		'(defun preamble ())'
		';;; f@40x10+0+0'
		'(defun one ())'
		';;; f@40x10+0+20'
		'(defun two ())')).
	self assert: document roots size equals: 2.
	self assert: document roots first children isEmpty!

testHashCommentIsADirectiveOutsideMarkdown
	| document |
	document := self flat: (String lf join: #('## f@40x10+0+0' 'body')).
	self assert: document roots size equals: 1.
	self assert: document roots first geometry width value equals: 40! !

!McFloatyTest methodsFor: 'tests - writeback'!
testMovingAnAbsoluteCardWritesPixelsBack
	| document title |
	document := self markdown: self markdownSample.
	title := document roots first.
	title geometry: (title geometry withPosition: 123 @ -45 in: 1000 @ 700).
	self assert: (document renderedSource includesSubstring: '<!!-- f@800x600+123-45 -->').
	self deny: (document renderedSource includesSubstring: '+10-20')!

testMovingAPercentCardKeepsItInPercent
	"The unit the author wrote is the intent, so a drag re-expresses the drop
	 in that unit rather than replacing it with pixels."
	| document sectionA |
	document := self markdown: self markdownSample.
	sectionA := document directiveLabelled: 'Section A'.
	sectionA geometry: (sectionA geometry withPosition: 40 @ 12 in: 800 @ 600).
	self assert: (document renderedSource includesSubstring: 'f@50%x25%+5%+2%')!

testPercentWritebackRoundsToTheNearestWholePercent
	"46/800 is 5.75%, which has no exact whole-percent spelling; the drop lands
	 on the nearest one instead of growing a decimal."
	| document sectionA |
	document := self markdown: self markdownSample.
	sectionA := document directiveLabelled: 'Section A'.
	sectionA geometry: (sectionA geometry withPosition: 46 @ 18 in: 800 @ 600).
	self assert: (document renderedSource includesSubstring: 'f@50%x25%+6%+3%')!

testWritebackPreservesCommentStyleAndIndentation
	| document card |
	document := self flat: (String lf join: #(
		';;; f@900x700+0+0'
		'(defun host ())'
		'    ;;; f@40x10+0+0'
		'(defun child ())')).
	card := document roots first children first.
	card geometry: (card geometry withPosition: 7 @ 9 in: 900 @ 700).
	self assert: (document renderedSource includesSubstring: '    ;;; f@40x10+7+9')!

testWritebackLeavesEveryOtherDirectiveAlone
	| document |
	document := self markdown: self markdownSample.
	document roots first
		geometry: (document roots first geometry withPosition: 1 @ 2 in: 1000 @ 700).
	self assert: (document renderedSource includesSubstring: 'f@50%x25%+5%+2%').
	self assert: (document renderedSource includesSubstring: 'f@40%x30%+1%+1%')!

testRenderedSourceKeepsTheDocumentOtherwiseByteForByte
	| document |
	document := self markdown: self markdownSample.
	self assert: document renderedSource equals: self markdownSample!

testRepeatedMovesStayCorrectAsTheTextChangesLength
	"Ranges are stamped once and never move, so a directive that grows or
	 shrinks must not disturb where the others were found."
	| document title |
	document := self markdown: self markdownSample.
	title := document roots first.
	#(1 22 333 4444) do: [ :each |
		title geometry: (title geometry withPosition: each @ each negated in: 1000 @ 700) ].
	self assert: (document renderedSource includesSubstring: 'f@800x600+4444-4444').
	self assert: (document renderedSource includesSubstring: 'f@50%x25%+5%+2%').
	self assert: (document renderedSource includesSubstring: 'body B')! !
