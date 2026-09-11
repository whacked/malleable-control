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

frontmatterSample
	"The host directive is a key inside the frontmatter, so the markdown that
	 follows the block is all child level."
	^ String lf join: #(
		'---'
		'title: A doc'
		'floaty: f@820x560+40-60'
		'---'
		'# Title'
		'intro body'
		''
		'<!!-- f@50%x25%+5%+2% -->'
		'## Section A'
		'body A')!

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

!McFloatyTest methodsFor: 'tests - replacement'!
overwrite: aString from: aStart to: aStop with: aReplacement
	^ (McFloatyReplacement from: aStart to: aStop with: aReplacement)
		applyTo: aString!

testAReplacementRewritesTheStringItCovers
	self assert: (self overwrite: 'abcdef' from: 3 to: 4 with: 'XYZ') equals: 'abXYZef'!

testAnInsertionKeepsEveryCharacter
	"An insertion at p is the empty interval p to p - 1, so the two halves meet
	 exactly at p and nothing is consumed."
	self assert: ((McFloatyReplacement at: 3 insert: 'XY') applyTo: 'abcdef')
		equals: 'abXYcdef'.
	self assert: ((McFloatyReplacement at: 1 insert: 'X') applyTo: 'abc')
		equals: 'Xabc'.
	self assert: ((McFloatyReplacement at: 4 insert: 'X') applyTo: 'abc')
		equals: 'abcX'!

testADeletionIsAReplacementByNothing
	self assert: (self overwrite: 'abcdef' from: 2 to: 4 with: '') equals: 'aef'!

testARangeBeforeTheEditDoesNotMove
	| replacement |
	replacement := McFloatyReplacement from: 10 to: 12 with: 'much longer'.
	self assert: (replacement transform: (2 to: 5)) equals: (2 to: 5)!

testARangeAfterTheEditMovesByTheDelta
	| replacement |
	replacement := McFloatyReplacement from: 3 to: 4 with: 'XYZ'.
	self assert: (replacement transform: (10 to: 20)) equals: (11 to: 21)!

testARangeAfterADeletionMovesBack
	| replacement |
	replacement := McFloatyReplacement from: 3 to: 6 with: ''.
	self assert: (replacement transform: (10 to: 20)) equals: (6 to: 16)!

testAnEditInsideARangeStretchesIt
	| replacement |
	replacement := McFloatyReplacement from: 5 to: 6 with: 'abcde'.
	self assert: (replacement transform: (1 to: 10)) equals: (1 to: 13)!

testARangeTheEditCoveredBecomesWhatReplacedIt
	"The card whose own line a drag rewrites is the reason this matters: it has
	 to be able to address that line again on the next drag."
	| replacement |
	replacement := McFloatyReplacement from: 4 to: 8 with: 'XYZ'.
	self assert: (replacement transform: (4 to: 8)) equals: (4 to: 6)!

testARangeADeletionCoveredComesBackEmpty
	| replacement |
	replacement := McFloatyReplacement from: 4 to: 8 with: ''.
	self assert: (replacement transform: (5 to: 7)) isEmpty!

testADeletionAcrossARangesStartClampsIt
	"What survives is the tail, and it begins where the deletion did."
	| replacement |
	replacement := McFloatyReplacement from: 3 to: 6 with: ''.
	self assert: (replacement transform: (5 to: 12)) equals: (3 to: 8)!

testADeletionAcrossARangesEndLeavesThePrefix
	| replacement |
	replacement := McFloatyReplacement from: 6 to: 9 with: ''.
	self assert: (replacement transform: (2 to: 7)) equals: (2 to: 5)!

testTypingAtARangesFirstCharacterFallsOutsideIt
	"Both anchors shift, so the text belongs to whatever precedes the range.
	 Handing it to the range instead is an affinity the editor knows and this
	 object does not, so it is not decided here."
	| replacement |
	replacement := McFloatyReplacement at: 5 insert: 'XX'.
	self assert: (replacement transform: (5 to: 9)) equals: (7 to: 11)!

testTypingJustPastARangesLastCharacterFallsOutsideIt
	| replacement |
	replacement := McFloatyReplacement at: 10 insert: 'XX'.
	self assert: (replacement transform: (5 to: 9)) equals: (5 to: 9)!

testTypingInsideARangeExtendsIt
	| replacement |
	replacement := McFloatyReplacement at: 6 insert: 'XX'.
	self assert: (replacement transform: (5 to: 9)) equals: (5 to: 11)! !

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
	self assert: (lower directiveLabelled: 'Title') level equals: 1.
	self deny: (lower directiveLabelled: 'Title') regionStart equals: 1.
	self deny: (lower directiveLabelled: 'document') isAnchored!

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
	self deny: document host isAnchored.
	self assert: document host children size equals: 1.
	self assert: document host children first label equals: 'Title'!

testHashCommentIsNotADirectiveInMarkdown
	"## opens a heading in markdown, so it cannot also be the comment that
	 configures the section it opens."
	| document |
	document := self markdown: (String lf join: #(
		'# Title'
		'## f@40x10+0+0'
		'body')).
	self assert: document allDirectives size equals: 1.
	self deny: document host isAnchored! !

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

!McFloatyTest methodsFor: 'tests - frontmatter'!
testFrontmatterFloatyKeyIsTheHost
	| host |
	host := (self markdown: self frontmatterSample) roots first.
	self assert: host label equals: 'document'.
	self assert: host geometry asDirectiveString equals: 'f@820x560+40-60'!

testCommentInsideTheFrontmatterIsNotADirective
	"The block is YAML, not markdown.  A comment line in it is a value, or a
	 key the author is in the middle of writing, and either way it opens no
	 card."
	| doc |
	doc := self markdown: (String lf join: #(
		'---'
		'<!!-- f@300x200+0+0 -->'
		'title: A doc'
		'---'
		'# Title'
		'body')).
	self assert: doc allDirectives size equals: 1.
	self deny: doc host isAnchored!

testHostTextStartsAfterTheFrontmatter
	"The block is the document's metadata, not its prose.  The host shows the
	 markdown proper; the frontmatter has an editor of its own."
	| doc host |
	doc := self markdown: self frontmatterSample.
	host := doc roots first.
	self assert: ((doc renderRange: host contentRange) beginsWith: '# Title')!

testYamlCommentInTheFrontmatterIsNotAHeading
	"# opens a comment in YAML and a heading in markdown.  Read as a heading it
	 would name and own sections of a document it is not even part of."
	| doc |
	doc := self markdown: (String lf join: #(
		'---'
		'# Overview'
		'floaty: f@800x600+0+0'
		'---'
		'<!!-- f@50%x50%+0+0 -->'
		'some prose')).
	self
		deny: ((doc allDirectives collect: [ :each | each label ]) includes: 'Overview')!

testDirectiveOnTheFirstLineAfterTheFrontmatterIsTheHost
	"With no floaty key in the block, the top comment rule still holds -- it is
	 just that the top of the markdown is where the block ends."
	| host |
	host := (self markdown: (String lf join: #(
		'---'
		'title: A doc'
		'---'
		'<!!-- f@800x600+10-20 -->'
		'# Title'
		'body'))) roots first.
	self assert: host label equals: 'document'.
	self assert: host geometry asDirectiveString equals: 'f@800x600+10-20'!

testFrontmatterKeyOutranksADirectiveAfterTheBlock
	"Both say what the whole document is.  The block is the document's own
	 metadata, so it is the one that says it, and the comment is left to govern
	 the section it introduces."
	| doc |
	doc := self markdown: (String lf join: #(
		'---'
		'floaty: f@820x560+40-60'
		'---'
		'<!!-- f@300x200+0+0 -->'
		'# Title'
		'body')).
	self assert: doc roots size equals: 1.
	self assert: doc roots first geometry asDirectiveString equals: 'f@820x560+40-60'.
	self assert: doc roots first regionStart equals: 1.
	self
		assert: ((doc renderRange: doc roots first contentRange)
			beginsWith: '<!!-- f@300x200+0+0 -->').
	self assert: doc roots first children first label equals: 'Title'!

testDraggingAFrontmatterHostRewritesItsKeyLine
	| doc host |
	doc := self markdown: self frontmatterSample.
	host := doc roots first.
	doc writeGeometryOf: host as: (McFloatyGeometry parse: '900x700+10+20').
	self assert: (doc source lines at: 3) equals: 'floaty: f@900x700+10+20'!

testDraggingAFrontmatterHostKeepsTheCommentBesideIt
	"# opens a comment in YAML, and a drag has no business deleting one."
	| doc host |
	doc := self markdown: (String lf join: #(
		'---'
		'floaty: f@820x560+40-60 # the board'
		'---'
		'# Title'
		'body')).
	host := doc roots first.
	doc writeGeometryOf: host as: (McFloatyGeometry parse: '900x700+10+20').
	self
		assert: (doc source lines at: 2)
		equals: 'floaty: f@900x700+10+20 # the board'!

testRetypingAFrontmatterKeyLineMovesItsCard
	"The same live feedback a retyped comment directive gives: the card follows
	 the keystroke that finishes the line, without waiting for a reparse."
	| doc host |
	doc := self markdown: self frontmatterSample.
	host := doc roots first.
	self assert: (doc writeLineOf: host as: 'floaty: f@900x700+10+20').
	self assert: host geometry asDirectiveString equals: 'f@900x700+10+20'! !

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

testFlatFileWithoutALeadingDirectiveIsStillHosted
	"No directive on the first line means no directive says what the whole file
	 is -- but the file is still a document, and the regions in it are still
	 parts of it."
	| document |
	document := self flat: (String lf join: #(
		'(defun preamble ())'
		';;; f@40x10+0+0'
		'(defun one ())'
		';;; f@40x10+0+20'
		'(defun two ())')).
	self assert: document roots size equals: 1.
	self deny: document host isAnchored.
	self assert: document host children size equals: 2!

testHashCommentIsADirectiveOutsideMarkdown
	| document |
	document := self flat: (String lf join: #('## f@40x10+0+0' 'body')).
	self assert: document roots size equals: 1.
	self assert: document roots first geometry width value equals: 40! !

!McFloatyTest methodsFor: 'tests - blocks'!
testTokensKeepEveryDirectiveLineIncludingEnds
	"The tree drops an f@end once it has closed a region, but the rendering
	 still has to know the line is a directive and not prose."
	| document |
	document := self flat: (String lf join: #(
		';;; f@900x700+0+0'
		'(defun host ())'
		';;; f@30%x20%+5%+5%'
		'(defun child ())'
		';;; f@end'
		'(defun after ())')).
	self assert: (document tokens collect: [ :each | each kind ])
		equals: #(#card #card #end).
	self assert: (document tokens collect: [ :each | each directive notNil ])
		equals: #(true true false)! !

!McFloatyTest methodsFor: 'tests - blocks'!
testACardTokenReadsAsTheLineTheDragWrote
	"A drag rewrites the source, and a token re-reads its line from it, so
	 every rendering of that line agrees without anyone being told."
	| document child |
	document := self markdown: self markdownSample.
	child := document directiveLabelled: 'Section A'.
	document
		writeGeometryOf: child
		as: (McFloatyGeometry parse: '10x20+30+40').
	self assert: ((document tokens detect: [ :each | each directive == child ]) text
		includesSubstring: 'f@10x20+30+40')!

testATokenTheEditConsumedIsDropped
	"A directive line deleted outright leaves no block behind to draw."
	| document child before |
	document := self markdown: self markdownSample.
	child := document directiveLabelled: 'Section A'.
	before := document tokens size.
	document replaceFrom: child range first to: child range last with: ''.
	self assert: document tokens size equals: before - 1.
	self deny: (document tokens anySatisfy: [ :each | each directive == child ])! !

!McFloatyTest methodsFor: 'tests - blocks'!
testARenderedTokenAddressesTheLineItLandedOn
	"A rewritten directive is rarely the length of the one in the file, so a
	 token's rendered range has to be measured rather than offset."
	| document host rendered |
	document := self markdown: self markdownSample.
	document
		writeGeometryOf: (document directiveLabelled: 'Section A')
		as: (McFloatyGeometry parse: '1x2+3+4').
	host := document roots first.
	rendered := document renderRange: host regionRange.
	self assert: (document tokensIn: host regionRange) size equals: 3.
	(document tokensIn: host regionRange) do: [ :token |
		self assert: (rendered copyFrom: token range first to: token range last)
			equals: token text ]! !

!McFloatyTest methodsFor: 'tests - blocks'!
testContentRangeLeavesOutTheDirectiveThatOpensTheCard
	"The card draws its own directive as a block above the text, so the text
	 itself starts on the line after it."
	| document child content |
	document := self markdown: self markdownSample.
	child := document directiveLabelled: 'Sub'.
	self assert: child contentRange first equals: child range last + 2.
	content := document renderRange: child contentRange.
	self deny: (content includesSubstring: 'f@').
	self assert: (content beginsWith: '### Sub')! !

!McFloatyTest methodsFor: 'tests - host without a directive'!
testDocumentWithNoDirectiveStillHasAHost
	"A card can be taken away; the document cannot.  There is always something
	 the whole text belongs to, so there is always a host -- it just has no line
	 in the file to remember its geometry, and starts where the program puts it."
	| doc |
	doc := self markdown: (String lf join: #('# Title' 'body')).
	self assert: doc roots size equals: 1.
	self assert: doc host label equals: 'document'.
	self deny: doc host isAnchored.
	self assert: doc host geometry equals: McFloatyDocument defaultHostGeometry!

testChildrenNestUnderAHostThatHasNoDirective
	| doc |
	doc := self markdown: (String lf join: #(
		'# Title'
		''
		'<!!-- f@50%x50%+0+0 -->'
		'## Section'
		'body')).
	self assert: doc roots size equals: 1.
	self assert: doc host children first label equals: 'Section'!

testHostKeepsItsGeometryWhenItsDirectiveBreaks
	"Breaking a child's directive takes its card away.  The host has nowhere to
	 go, so it stays where it was and keeps the position for the session."
	| doc range |
	doc := self markdown: self markdownSample.
	doc writeGeometryOf: doc host as: (McFloatyGeometry parse: '900x700+10+20').
	range := doc host range.
	doc replaceFrom: range first to: range last with: 'not a directive'.
	doc reparse.
	self deny: doc host isAnchored.
	self assert: doc host geometry asDirectiveString equals: 'f@900x700+10+20'!

testDraggingAHostWithNoDirectiveLeavesTheSourceAlone
	"There is no line to write the geometry into, and inventing one would be
	 the board editing a document the author did not ask it to edit."
	| doc before |
	doc := self markdown: (String lf join: #('# Title' 'body')).
	before := doc source.
	doc writeGeometryOf: doc host as: (McFloatyGeometry parse: '900x700+10+20').
	self assert: doc source equals: before.
	self assert: doc host geometry asDirectiveString equals: 'f@900x700+10+20'!

testHostWithNoDirectiveShowsTheMarkdownAfterTheFrontmatter
	| doc |
	doc := self markdown: (String lf join: #(
		'---'
		'title: A doc'
		'---'
		'# Title'
		'body')).
	self assert: ((doc renderRange: doc host contentRange) beginsWith: '# Title')! !

!McFloatyTest methodsFor: 'tests - writeback'!
move: aDirective to: aPoint in: anExtent document: aDocument
	^ aDocument
		writeGeometryOf: aDirective
		as: (aDirective geometry withPosition: aPoint in: anExtent)!

testMovingAnAbsoluteCardWritesPixelsBack
	| document title |
	document := self markdown: self markdownSample.
	title := document roots first.
	self move: title to: 123 @ -45 in: 1000 @ 700 document: document.
	self assert: (document source includesSubstring: '<!!-- f@800x600+123-45 -->').
	self deny: (document source includesSubstring: '+10-20')!

testMovingAPercentCardKeepsItInPercent
	"The unit the author wrote is the intent, so a drag re-expresses the drop
	 in that unit rather than replacing it with pixels."
	| document sectionA |
	document := self markdown: self markdownSample.
	sectionA := document directiveLabelled: 'Section A'.
	self move: sectionA to: 40 @ 12 in: 800 @ 600 document: document.
	self assert: (document source includesSubstring: 'f@50%x25%+5%+2%')!

testPercentWritebackRoundsToTheNearestWholePercent
	"46/800 is 5.75%, which has no exact whole-percent spelling; the drop lands
	 on the nearest one instead of growing a decimal."
	| document sectionA |
	document := self markdown: self markdownSample.
	sectionA := document directiveLabelled: 'Section A'.
	self move: sectionA to: 46 @ 18 in: 800 @ 600 document: document.
	self assert: (document source includesSubstring: 'f@50%x25%+6%+3%')!

testWritebackPreservesCommentStyleAndIndentation
	| document card |
	document := self flat: (String lf join: #(
		';;; f@900x700+0+0'
		'(defun host ())'
		'    ;;; f@40x10+0+0'
		'(defun child ())')).
	card := document roots first children first.
	self move: card to: 7 @ 9 in: 900 @ 700 document: document.
	self assert: (document source includesSubstring: '    ;;; f@40x10+7+9')!

testWritebackLeavesEveryOtherDirectiveAlone
	| document |
	document := self markdown: self markdownSample.
	self move: document roots first to: 1 @ 2 in: 1000 @ 700 document: document.
	self assert: (document source includesSubstring: 'f@50%x25%+5%+2%').
	self assert: (document source includesSubstring: 'f@40%x30%+1%+1%')!

testAnUntouchedDocumentIsItsSourceByteForByte
	"Nothing is replayed over the source on the way out any more, so a document
	 nobody has dragged is the file it was read from."
	| document |
	document := self markdown: self markdownSample.
	self assert: document source equals: self markdownSample!

testRepeatedMovesStayCorrectAsTheTextChangesLength
	"Each move rewrites the source, so the next one has to find the directive
	 where the last one left it -- a line that grows by three characters moves
	 everything after it by three."
	| document title |
	document := self markdown: self markdownSample.
	title := document roots first.
	#(1 22 333 4444) do: [ :each |
		self move: title to: each @ each negated in: 1000 @ 700 document: document ].
	self assert: (document source includesSubstring: 'f@800x600+4444-4444').
	self assert: (document source includesSubstring: 'f@50%x25%+5%+2%').
	self assert: (document source includesSubstring: 'body B')!

testAMoveLeavesEveryOtherCardShowingTheSameTextAsBefore
	"The anchors after a rewritten line move with it, so a sibling still reads
	 as its own region rather than as a window slid off by the length delta."
	| document before |
	document := self markdown: self markdownSample.
	before := document renderRange: (document directiveLabelled: 'Sub') regionRange.
	self move: document roots first to: 4444 @ -4444 in: 1000 @ 700 document: document.
	self
		assert: (document renderRange: (document directiveLabelled: 'Sub') regionRange)
		equals: before!

testAMoveKeepsTheCardsOwnLineAddressable
	"The directive the edit replaced is anchored to what replaced it, so a
	 second drag reads its own line and not the one that follows."
	| document title |
	document := self markdown: self markdownSample.
	title := document roots first.
	self move: title to: 4444 @ -4444 in: 1000 @ 700 document: document.
	self
		assert: (document renderRange: title range)
		equals: '<!!-- f@800x600+4444-4444 -->'! !
