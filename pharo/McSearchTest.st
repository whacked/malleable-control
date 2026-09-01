"Tests for the search model.  Load after McSearch.st; nothing here needs
Microdown, the editor or a bus, so the suite runs headless on its own."!

TestCase subclass: #McSearchMatcherTest
	instanceVariableNames: 'matcher'
	classVariableNames: ''
	package: 'MalleableControl'!

!McSearchMatcherTest methodsFor: 'running'!
setUp
	super setUp.
	matcher := McLiteralSearchMatcher new! !

!McSearchMatcherTest methodsFor: 'helpers'!
matches: aString for: aQuery
	^ matcher matchesFor: aQuery in: aString!

matches: aString forText: aText
	^ self matches: aString for: (McSearchQuery text: aText)! !

!McSearchMatcherTest methodsFor: 'tests - literal'!
testAnswersEveryOccurrenceInSourceOrder
	self
		assert: (self matches: 'a link and a link back' forText: 'link')
		equals: { 3 to: 6. 14 to: 17 }!

testRangesAddressTheSourceString
	| source range |
	source := 'one two three'.
	range := (self matches: source forText: 'two') first.
	self assert: (source copyFrom: range first to: range last) equals: 'two'!

testAnswersNoMatchesWhenAbsent
	self assert: (self matches: 'one two' forText: 'three') isEmpty!

testAnswersNoMatchesInEmptySource
	self assert: (self matches: '' forText: 'x') isEmpty!

testNeedleLongerThanSourceDoesNotMatch
	self assert: (self matches: 'ab' forText: 'abc') isEmpty! !

!McSearchMatcherTest methodsFor: 'tests - empty query'!
testEmptyQueryMatchesNothing
	"An empty field clears the overlay, and does so because there is nothing to
	 highlight -- not because the presentation layer suppressed it."
	self assert: (self matches: 'anything at all' for: McSearchQuery empty) isEmpty!

testWhitespaceQueryStillMatches
	"Empty is empty; a space is a thing the user typed and can be searched for."
	self assert: (self matches: 'a b' forText: ' ') equals: { 2 to: 2 }! !

!McSearchMatcherTest methodsFor: 'tests - case'!
testCaseInsensitiveByDefault
	self
		assert: (self matches: 'Link link LINK' forText: 'link')
		equals: { 1 to: 4. 6 to: 9. 11 to: 14 }!

testCaseSensitiveMatchesOnlyExactCase
	self
		assert: (self matches: 'Link link LINK'
			for: ((McSearchQuery text: 'link') withCaseSensitive: true))
		equals: { 6 to: 9 }!

testCaseFoldingDoesNotShiftPositions
	| source range |
	source := 'A LINK here'.
	range := (self matches: source forText: 'link') first.
	self assert: (source copyFrom: range first to: range last) equals: 'LINK'! !

!McSearchMatcherTest methodsFor: 'tests - whole word'!
testWholeWordRejectsMatchesInsideWords
	self
		assert: (self matches: 'cat cats concat cat.'
			for: ((McSearchQuery text: 'cat') withWholeWord: true))
		equals: { 1 to: 3. 17 to: 19 }!

testWholeWordResumesInsideARejectedCandidate
	"Resuming after the rejected candidate rather than one past its start would
	 lose the match that begins inside it."
	self
		assert: (self matches: 'catcat cat'
			for: ((McSearchQuery text: 'cat') withWholeWord: true))
		equals: { 8 to: 10 }!

testWholeWordTreatsDocumentEdgesAsBoundaries
	self
		assert: (self matches: 'cat'
			for: ((McSearchQuery text: 'cat') withWholeWord: true))
		equals: { 1 to: 3 }!

testWholeWordTreatsUnderscoreAndDigitsAsWordCharacters
	self
		assert: (self matches: 'cat_1 cat2 cat'
			for: ((McSearchQuery text: 'cat') withWholeWord: true))
		equals: { 12 to: 14 }!

testWholeWordCombinesWithCaseSensitivity
	self
		assert: (self matches: 'Cat cat'
			for: (((McSearchQuery text: 'cat') withWholeWord: true) withCaseSensitive: true))
		equals: { 5 to: 7 }! !

!McSearchMatcherTest methodsFor: 'tests - overlap policy'!
testMatchesDoNotOverlap
	"Non-overlap is the stated policy: scanning resumes after an accepted
	 match, so 'aa' in 'aaa' is one match and not two."
	self assert: (self matches: 'aaa' forText: 'aa') equals: { 1 to: 2 }!

testAdjacentMatchesAreBothAnswered
	self assert: (self matches: 'aaaa' forText: 'aa') equals: { 1 to: 2. 3 to: 4 }!

testAnsweredRangesAreOrderedAndDisjoint
	| ranges |
	ranges := self matches: 'abababab' forText: 'ab'.
	ranges withIndexDo: [ :each :index |
		index > 1 ifTrue: [
			self assert: (ranges at: index - 1) last < each first ] ]! !

!McSearchMatcherTest methodsFor: 'tests - protocol'!
testBaseMatcherLeavesMatchingToSubclasses
	self
		should: [ McSearchMatcher new matchesFor: (McSearchQuery text: 'x') in: 'x' ]
		raise: Error!

testDefaultMatcherIsLiteral
	self assert: McSearchMatcher default class equals: McLiteralSearchMatcher!

testOnlyMatchersThatImplementTheProtocolAreOffered
	"The extension seam.  A subclass is offered by implementing matchesFor:in:
	 and by nothing else, so a half-built regex or glob matcher cannot be
	 chosen and then silently answer no matches."
	self assert: (McSearchMatcher implementedMatchers includes: McLiteralSearchMatcher).
	McSearchMatcher implementedMatchers do: [ :each |
		self assert: (each includesSelector: #matchesFor:in:).
		self assert: (each new matchesFor: McSearchQuery empty in: 'text') isEmpty ]!

testUnimplementedSubclassesAreNotOffered
	| stub |
	stub := McSearchMatcher subclass: #McStubSearchMatcherForTest
		instanceVariableNames: ''
		classVariableNames: ''
		package: 'MalleableControl-Tests'.
	[ self deny: (McSearchMatcher implementedMatchers includes: stub).
	  self should: [ stub new matchesFor: (McSearchQuery text: 'x') in: 'x' ] raise: Error ]
		ensure: [ stub removeFromSystem ]!

testMatcherIsLabelled
	self assert: McLiteralSearchMatcher new label isString! !

!McSearchMatcherTest methodsFor: 'tests - query'!
testQueryDefaultsToInsensitiveAndUnanchored
	| query |
	query := McSearchQuery text: 'x'.
	self deny: query isCaseSensitive.
	self deny: query isWholeWord!

testQueryCopiesLeaveTheOriginalAlone
	| query revised |
	query := McSearchQuery text: 'x'.
	revised := (query withText: 'y') withWholeWord: true.
	self assert: query text equals: 'x'.
	self deny: query isWholeWord.
	self assert: revised text equals: 'y'.
	self assert: revised isWholeWord!

testQueriesCompareByValue
	self
		assert: (McSearchQuery text: 'x' caseSensitive: true wholeWord: false)
		equals: (McSearchQuery text: 'x' caseSensitive: true wholeWord: false).
	self
		deny: (McSearchQuery text: 'x') = ((McSearchQuery text: 'x') withCaseSensitive: true)!

testEmptyQueryIsEmpty
	self assert: McSearchQuery empty isEmpty.
	self deny: (McSearchQuery text: 'x') isEmpty! !

TestCase subclass: #McSearchSessionTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McSearchSessionTest methodsFor: 'helpers'!
source
	^ 'link one, link two, link three'!

sessionFor: aText
	| session |
	session := McSearchSession on: self source.
	session queryText: aText.
	^ session! !

!McSearchSessionTest methodsFor: 'tests - recomputation'!
testNewSessionHasNoQueryAndNoMatches
	| session |
	session := McSearchSession on: self source.
	self assert: session query isEmpty.
	self deny: session hasMatches.
	self assert: session activeIndex equals: 0.
	self assert: session activeMatch isNil!

testTypingAQueryActivatesTheFirstMatch
	| session |
	session := self sessionFor: 'link'.
	self assert: session matchCount equals: 3.
	self assert: session activeIndex equals: 1.
	self assert: session activeMatch equals: (1 to: 4)!

testClearingTheQueryDropsEveryMatch
	| session |
	session := self sessionFor: 'link'.
	session clear.
	self deny: session hasMatches.
	self assert: session activeMatch isNil.
	self assert: session activeIndex equals: 0!

testQueryWithNoMatchesLeavesNothingActive
	| session |
	session := self sessionFor: 'zzz'.
	self assert: session matchCount equals: 0.
	self assert: session activeMatch isNil!

testSessionDoesNotTouchTheSource
	| session |
	session := self sessionFor: 'link'.
	session next; next.
	self assert: session source equals: self source! !

!McSearchSessionTest methodsFor: 'tests - active retention'!
testTighteningTheOptionsKeepsTheActiveMatchWhenItSurvives
	"Retention is by range, not by index: the first match disappears here and
	 the active one keeps its position while its index moves."
	| session |
	session := McSearchSession on: 'Link one, link two, link three'.
	session queryText: 'link'.
	session next.
	self assert: session activeMatch equals: (11 to: 14).
	self assert: session activeIndex equals: 2.
	session query: (session query withCaseSensitive: true).
	self assert: session activeMatch equals: (11 to: 14).
	self assert: session activeIndex equals: 1!

testRelaxingTheOptionsKeepsTheActiveMatch
	| session |
	session := McSearchSession on: 'Link one, link two, link three'.
	session query: ((McSearchQuery text: 'link') withCaseSensitive: true).
	session next.
	self assert: session activeMatch equals: (21 to: 24).
	session query: (session query withCaseSensitive: false).
	self assert: session activeMatch equals: (21 to: 24).
	self assert: session activeIndex equals: 3!

testFallsBackToTheFirstMatchWhenTheActiveOneDisappears
	| session |
	session := self sessionFor: 'link'.
	session next; next.
	self assert: session activeIndex equals: 3.
	session queryText: 'one'.
	self assert: session activeIndex equals: 1.
	self assert: session activeMatch equals: (6 to: 8)!

testEditingTheSourceRetainsAnUnaffectedActiveMatch
	| session |
	session := self sessionFor: 'link'.
	session next.
	self assert: session activeMatch equals: (11 to: 14).
	session source: self source , ' and link four'.
	self assert: session matchCount equals: 4.
	self assert: session activeMatch equals: (11 to: 14)!

testChangingTheMatcherRecomputes
	| session |
	session := self sessionFor: 'link'.
	session matcher: McLiteralSearchMatcher new.
	self assert: session matchCount equals: 3.
	self assert: session activeMatch equals: (1 to: 4)! !

!McSearchSessionTest methodsFor: 'tests - navigation'!
testNextWrapsPastTheLastMatch
	| session |
	session := self sessionFor: 'link'.
	self assert: session next equals: (11 to: 14).
	self assert: session next equals: (21 to: 24).
	self assert: session next equals: (1 to: 4)!

testPreviousWrapsPastTheFirstMatch
	| session |
	session := self sessionFor: 'link'.
	self assert: session previous equals: (21 to: 24).
	self assert: session previous equals: (11 to: 14).
	self assert: session previous equals: (1 to: 4)!

testRepeatedNavigationIsDeterministic
	| session cycle |
	session := self sessionFor: 'link'.
	cycle := (1 to: 3) collect: [ :each | session next ].
	self assert: ((1 to: 3) collect: [ :each | session next ]) equals: cycle!

testNextAndPreviousAreInverses
	| session before |
	session := self sessionFor: 'link'.
	before := session activeMatch.
	session next.
	self assert: session previous equals: before!

testNavigationOnAnEmptyResultSetIsANoOp
	| session |
	session := self sessionFor: 'zzz'.
	self assert: session next isNil.
	self assert: session previous isNil.
	self assert: session activeIndex equals: 0!

testDirectionRecordsTheLastNavigation
	| session |
	session := self sessionFor: 'link'.
	self assert: session direction equals: #forward.
	session previous.
	self assert: session direction equals: #backward.
	session next.
	self assert: session direction equals: #forward!

testActivatingAnOutOfRangeIndexChangesNothing
	| session |
	session := self sessionFor: 'link'.
	session activateIndex: 99.
	self assert: session activeIndex equals: 1.
	session activateIndex: 0.
	self assert: session activeIndex equals: 1!

testWraparoundCanBeDisabled
	| session |
	session := self sessionFor: 'link'.
	session wrapAround: false.
	session previous.
	self assert: session activeIndex equals: 1.
	session next; next; next.
	self assert: session activeIndex equals: 3! !

TestCase subclass: #McSearchResultTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McSearchResultTest methodsFor: 'tests'!
testStructuredResultCarriesDocumentRangesAndPolicies
	| session result dictionary |
	session := McSearchSession on: 'link and link'.
	session queryText: 'link'.
	result := McSearchResult document: '/notes/demo.md' sourceSize: 13 session: session.
	dictionary := result asDictionary.
	self assert: (dictionary at: #document) equals: '/notes/demo.md'.
	self assert: (dictionary at: #sourceSize) equals: 13.
	self assert: (dictionary at: #query) equals: 'link'.
	self assert: (dictionary at: #matchCount) equals: 2.
	self assert: (dictionary at: #ranges) equals: #((1 4) (10 13)).
	self assert: (dictionary at: #activeRange) equals: #(1 4).
	self assert: (dictionary at: #activeIndex) equals: 1.
	self assert: (dictionary at: #highlightAll).
	self assert: (dictionary at: #wrapAround)! !

TestCase subclass: #McSearchPresentationTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McSearchPresentationTest methodsFor: 'helpers'!
underlayAt: anIndex in: aText
	^ (aText attributesAt: anIndex)
		detect: [ :each | each isKindOf: BlTextUnderlayAttribute ]
		ifNone: [ nil ]!

palette
	^ Dictionary new
		at: 'searchMatch' put: Color yellow;
		at: 'searchActiveMatch' put: Color orange;
		yourself! !

!McSearchPresentationTest methodsFor: 'tests'!
testActiveAndOrdinaryMatchesUseDifferentPresentation
	| session text active ordinary |
	session := McSearchSession on: 'link and link'.
	session queryText: 'link'.
	text := session source asRopedText.
	McSearchPresentation applyTo: text session: session palette: self palette.
	active := self underlayAt: 1 in: text.
	ordinary := self underlayAt: 10 in: text.
	self assert: active paint equals: Color orange.
	self assert: ordinary paint equals: Color yellow!

testHighlightAllCanBeDisabledWhileKeepingTheActiveMatch
	| session text |
	session := McSearchSession on: 'link and link'.
	session queryText: 'link'; highlightAll: false.
	text := session source asRopedText.
	McSearchPresentation applyTo: text session: session palette: self palette.
	self assert: (self underlayAt: 1 in: text) notNil.
	self assert: (self underlayAt: 10 in: text) isNil! !

TestCase subclass: #McCommandKeymapTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McCommandKeymapTest methodsFor: 'tests'!
testRichEditBindingsAreNamedAndRemappable
	| keymap replacement |
	keymap := McCommandKeymap richEditDefaults.
	self assert: (keymap commandNames includes: #openSearch).
	self assert: (keymap bindingFor: #openSearch in: #editor) equals: BlKeyCombination primaryF.
	replacement := BlKeyCombination primaryS.
	keymap bind: #openSearch in: #editor to: replacement.
	self assert: (keymap bindingFor: #openSearch in: #editor) equals: replacement! !
