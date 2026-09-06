"
McMarkdownLinkTest -- syntax, projection, and local resolution tests.

The scanner tests exact spans rather than relying on Microdown's batch inline
parser.  Projection tests inspect attributes instead of pixels, and target
tests use temporary files; none performs network I/O or opens a browser.

Chunk format: load with fileIn.
"!

Object subclass: #McMarkdownLinkTestOwner
	instanceVariableNames: 'state activated'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownLinkTestOwner methodsFor: 'accessing'!
state: aSymbol
	state := aSymbol!

activated
	^ activated! !

!McMarkdownLinkTestOwner methodsFor: 'links'!
linkStateFor: aLink
	^ state ifNil: [ #available ]!

activateLink: aLink
	activated := aLink!

imageElementFor: aLink
	^ BlElement new size: 20 @ 20; yourself! !

Object subclass: #McMarkdownImageCacheTestOwner
	instanceVariableNames: 'pool calls'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownImageCacheTestOwner methodsFor: 'accessing'!
calls
	"How many elements were actually built.  The point of the pool is that this
	 stays at one per occurrence however many restyles run over it."
	^ calls ifNil: [ 0 ]! !

!McMarkdownImageCacheTestOwner methodsFor: 'images - adornment pool'!
imageAdornmentCache
	^ pool ifNil: [ pool := Dictionary new ]! !

!McMarkdownImageCacheTestOwner methodsFor: 'links'!
linkStateFor: aLink
	^ #available!

imageElementFor: aLink
	calls := self calls + 1.
	^ BlElement new size: 20 @ 20; yourself! !

McRichEdit subclass: #McRichEditNavigationTestDouble
	instanceVariableNames: 'openedFile statusMessage'
	classVariableNames: ''
	package: 'MalleableControl'!

!McRichEditNavigationTestDouble methodsFor: 'testing'!
openedFile
	^ openedFile!

statusMessage
	^ statusMessage! !

!McRichEditNavigationTestDouble methodsFor: 'navigation'!
openDocument: aFileReference
	openedFile := aFileReference!

showStatus: aString
	statusMessage := aString! !

TestCase subclass: #McMarkdownLinkTest
	instanceVariableNames: 'tempDir homeDir'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownLinkTest methodsFor: 'running'!
tearDown
	tempDir ifNotNil: [
		[ tempDir ensureDeleteAll ] on: Error do: [ :e | nil ] ].
	homeDir ifNotNil: [
		[ homeDir ensureDeleteAll ] on: Error do: [ :e | nil ] ].
	super tearDown! !

!McMarkdownLinkTest methodsFor: 'helpers'!
scan: aString
	^ McMarkdownLinkScanner scan: aString!

tempDir
	^ tempDir ifNil: [
		tempDir := FileLocator temp / ('mc-link-test-' , UUID new asString).
		tempDir ensureCreateDirectory.
		tempDir ]!

homeDir
	"A sandbox under HOME rather than under temp, because HOME is the one
	 variable an expansion test can count on naming this directory: the
	 image resolves FileLocator temp to /private/tmp, which is not what
	 TMPDIR holds.  Removed again in tearDown."
	^ homeDir ifNil: [
		homeDir := FileLocator home / ('mc-link-test-' , UUID new asString).
		homeDir ensureCreateDirectory.
		homeDir ]!

write: aString to: aName
	| ref |
	ref := self tempDir / aName.
	ref parent ensureCreateDirectory.
	ref writeStreamDo: [ :stream | stream nextPutAll: aString ].
	^ ref!

linkTarget: aString
	^ McMarkdownLink
		kind: #link
		start: 1
		stop: 1
		labelStart: 1
		labelStop: 1
		target: aString
		label: aString
		caption: ''!

style: aString cursor: anInteger owner: anOwner
	| text |
	text := aString asRopedText.
	self styleText: text cursor: anInteger owner: anOwner.
	^ text!

styleCell: aString at: anInteger owner: anOwner
	"A styler wired the way a table cell's is: an identity map into the cell's
	 own private rope, and the cell's interval as the document map.  Two
	 different objects, which is how the styler knows the rope it decorates is
	 not the document."
	| text |
	text := aString asRopedText.
	(McMarkdownInlineStyler
		source: aString
		targetMap: (McMarkdownInlineStyler identityMapOfSize: aString size)
		documentMap: (McMarkdownInlineStyler
			mapForInterval: (anInteger to: anInteger + aString size - 1))
		text: text
		cursor: -1
		palette: McRichEdit new palette
		owner: anOwner) styleAll.
	^ text!

styleText: aText cursor: anInteger owner: anOwner
	| source map |
	source := aText asString.
	map := McMarkdownInlineStyler identityMapOfSize: source size.
	(McMarkdownInlineStyler
		source: source
		targetMap: map
		documentMap: map
		text: aText
		cursor: anInteger
		palette: McRichEdit new palette
		owner: anOwner) styleAll.
	^ aText!

hasAttribute: aClass in: aText at: anIndex
	^ (aText attributesAt: anIndex) anySatisfy: [ :each | each isKindOf: aClass ]!

adornmentsIn: aText
	"The dynamic adornment attributes on aText, one entry per attribute rather
	 than one per character it spans, in document order."
	| result |
	result := OrderedCollection new.
	1 to: aText size do: [ :index |
		(aText attributesAt: index) do: [ :each |
			((each isKindOf: BrTextAdornmentDynamicAttribute)
				and: [ (result identityIncludes: each) not ])
					ifTrue: [ result add: each ] ] ].
	^ result asArray!

buildAdornment: anAttribute
	"Build through the attribute, not its raw stencil, so Brick's pooled cache
	 participates exactly as it does in an editor.  These stencils take no
	 segment or editor arguments, so nil context is sufficient here."
	^ (anAttribute affect: nil in: nil) first! !

!McMarkdownLinkTest methodsFor: 'tests - scanner'!
testScansAStandardMarkdownLink
	| link |
	link := (self scan: 'a [label](notes/a.md) z') first.
	self assert: link kind equals: #link.
	self assert: link target equals: 'notes/a.md'.
	self assert: link label equals: 'label'.
	self assert: link range equals: (3 to: 21).
	self assert: link labelRange equals: (4 to: 8)!

testScansNestedParenthesesInADestination
	| link |
	link := (self scan: '[api](docs/fn(a).md)') first.
	self assert: link target equals: 'docs/fn(a).md'.
	self assert: link stop equals: 20!

testScansAnImageCaption
	| link |
	link := (self scan: '!![diagram](arch.png "System map")') first.
	self assert: link isImage.
	self assert: link target equals: 'arch.png'.
	self assert: link label equals: 'diagram'.
	self assert: link caption equals: 'System map'!

testImageAltTextIsTheCaptionWhenNoTitleExists
	self assert: (self scan: '!![diagram](arch.png)') first caption equals: 'diagram'!

testScansWikiAndObsidianAliases
	| plain aliased image |
	plain := (self scan: '[[Notes/Today]]') first.
	aliased := (self scan: '[[Notes/Today|today]]') first.
	image := (self scan: '!![[map.png|Floor plan]]') first.
	self assert: plain kind equals: #wiki.
	self assert: plain label equals: 'Notes/Today'.
	self assert: aliased target equals: 'Notes/Today'.
	self assert: aliased label equals: 'today'.
	self assert: image kind equals: #wikiImage.
	self assert: image caption equals: 'Floor plan'!

testScansAutolinksAndBareUrls
	| links |
	links := self scan: '<https://example.com/a> and https://example.org/b.'.
	self assert: links size equals: 2.
	self assert: links first kind equals: #autolink.
	self assert: links second kind equals: #bare.
	self assert: links second target equals: 'https://example.org/b'!

testIncompleteTokensRemainRaw
	#('[label' '[label](' '[[target' '!![alt](image') do: [ :source |
		self assert: (self scan: source) isEmpty description: source ]!

testAOneLetterLinkIsNotACheckbox
	| links |
	links := self scan: '[x](done.md)'.
	self assert: links size equals: 1.
	self assert: links first kind equals: #link! !

!McMarkdownLinkTest methodsFor: 'tests - load order'!
testExistingWidgetsStillRenderWithoutTheOptionalLinkScanner
	| scannerClass text |
	scannerClass := Smalltalk at: #McMarkdownLinkScanner.
	[ Smalltalk at: #McMarkdownLinkScanner put: nil.
	  text := self style: '[ ] task' cursor: -1 owner: nil.
	  self assert: (self hasAttribute: BrTextAdornmentDynamicAttribute in: text at: 1) ]
		ensure: [ Smalltalk at: #McMarkdownLinkScanner put: scannerClass ]! !

!McMarkdownLinkTest methodsFor: 'tests - projection'!
testAwayLinkHidesSyntaxAndIsClickable
	| text owner |
	owner := McMarkdownLinkTestOwner new.
	text := self style: '[label](notes.md)' cursor: -1 owner: owner.
	self assert: (self hasAttribute: BrTextHideAttribute in: text at: 1).
	self assert: (self hasAttribute: BrTextHideAttribute in: text at: 8).
	self assert: (self hasAttribute: BrTextClickAttribute in: text at: 2).
	self assert: (self hasAttribute: BrTextTooltipAttribute in: text at: 2).
	self assert: (self hasAttribute: BlTextDecorationAttribute in: text at: 2)!

testNearLinkLeavesItsSourceVisible
	| text owner |
	owner := McMarkdownLinkTestOwner new.
	text := self style: '[label](notes.md)' cursor: 2 owner: owner.
	self deny: (self hasAttribute: BrTextHideAttribute in: text at: 1).
	self deny: (self hasAttribute: BrTextClickAttribute in: text at: 2)!

testImageUsesOneReplacementAdornment
	| text owner |
	owner := McMarkdownLinkTestOwner new.
	text := self style: '!![alt](image.png)' cursor: -1 owner: owner.
	self assert: (self hasAttribute: BrTextAdornmentDynamicAttribute in: text at: 1)! !

!McMarkdownLinkTest methodsFor: 'tests - image pooling'!
testImageElementIsPooledAcrossCursorOnlyRestyles
	"A caret step restyles the whole rope.  The same occurrence of the same
	 image must come back from the pool rather than be rebuilt."
	| owner source first second |
	owner := McMarkdownImageCacheTestOwner new.
	source := 'see !![alt](image.png) here'.
	first := self adornmentsIn: (self style: source cursor: -1 owner: owner).
	second := self adornmentsIn: (self style: source cursor: 25 owner: owner).
	self assert: first size equals: 1.
	self assert: second size equals: 1.
	self assert: first first cache == second first cache.
	self assert: (self buildAdornment: first first) == (self buildAdornment: second first).
	self assert: owner calls equals: 1!

testAttachedEditorReusesImageAfterRevealAndHide
	"Exercise Brick's real adornment lifecycle: render the image, reveal its
	 source by moving the synthetic caret onto it, then render it again."
	| owner cursor source editor model space styler |
	owner := McMarkdownImageCacheTestOwner new.
	cursor := ValueHolder new contents: -1; yourself.
	source := 'see !![alt](image.png) here'.
	editor := BrEditor new.
	editor aptitude: BrGlamorousRegularEditorAptitude new.
	editor text: source asRopedText.
	editor constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ].
	model := editor editor.
	model useSyncStylerStrategy.
	styler := BlPluggableStyler new block: [ :text |
		self styleText: text cursor: cursor contents owner: owner ].
	editor styler: styler.
	space := BlSpace new.
	space extent: 500 @ 200.
	space root addChild: editor.
	[
		model styleText.
		space pulse; pulse.
		self assert: owner calls equals: 1.
		cursor contents: 5.
		model styleText.
		space pulse; pulse.
		self assert: owner calls equals: 1.
		cursor contents: -1.
		model styleText.
		space pulse; pulse.
		self assert: owner calls equals: 1 ]
		ensure: [ space close ]!

testTwoOccurrencesOfOneImageGetDistinctElements
	"A BlElement has one parent, so sharing one between two positions would let
	 the second occurrence steal it from the first."
	| owner adornments left right |
	owner := McMarkdownImageCacheTestOwner new.
	adornments := self
		adornmentsIn: (self style: '!![a](x.png) and !![a](x.png)' cursor: -1 owner: owner).
	self assert: adornments size equals: 2.
	self deny: adornments first cache == adornments second cache.
	left := self buildAdornment: adornments first.
	right := self buildAdornment: adornments second.
	self deny: left == right.
	self assert: owner calls equals: 2.
	self assert: owner imageAdornmentCache size equals: 2!

testImageAdornmentIsGivenTheOwnersPoolWhenBrickSupportsIt
	"withCache:key: stores one Brick pooled-cache object per occurrence in the
	 owner's dictionary; newly styled attributes recover those same objects."
	| owner adornments |
	owner := McMarkdownImageCacheTestOwner new.
	adornments := self
		adornmentsIn: (self style: '!![a](x.png) and !![b](y.png)' cursor: -1 owner: owner).
	self assert: adornments size equals: 2.
	self assert: owner imageAdornmentCache size equals: 2.
	adornments do: [ :each |
		self assert: (owner imageAdornmentCache values identityIncludes: each cache) ].
	adornments do: [ :each | self buildAdornment: each ].
	self assert: owner calls equals: 2!

testImageWithoutAnOwnerKeepsBuildingFreshElements
	"No owner means no pool, which is how this worked before pooling existed."
	| adornments |
	adornments := self adornmentsIn: (self style: '!![alt](image.png)' cursor: -1 owner: nil).
	self assert: adornments size equals: 1.
	self
		deny: (self buildAdornment: adornments first)
			== (self buildAdornment: adornments first)!

testImageElementSurvivesAnUnrelatedEditAboveIt
	"The point of the whole pool.  Typing before an image moves every position
	 after it; the key is an occurrence rather than a position, so the same
	 element comes back from the pool instead of the file being decoded again."
	| owner before after |
	owner := McMarkdownImageCacheTestOwner new.
	before := self adornmentsIn: (self style: 'intro !![a](x.png)' cursor: -1 owner: owner).
	after := self adornmentsIn:
		(self style: 'a considerably longer intro !![a](x.png)' cursor: -1 owner: owner).
	self assert: before size equals: 1.
	self assert: after size equals: 1.
	self assert: before first cache == after first cache.
	self buildAdornment: before first.
	self buildAdornment: after first.
	self assert: owner calls equals: 1.
	self assert: owner imageAdornmentCache size equals: 1!

testDuplicateImagesStayDistinctAcrossAnUnrelatedEdit
	"Stability must not be bought with aliasing: two identical images are two
	 occurrences, and a BlElement has one parent, so the second sharing the
	 first's element would take it away from the first."
	| owner before after |
	owner := McMarkdownImageCacheTestOwner new.
	before := self adornmentsIn:
		(self style: 'x !![a](p.png) and !![a](p.png)' cursor: -1 owner: owner).
	self assert: before size equals: 2.
	self deny: before first cache == before second cache.
	after := self adornmentsIn:
		(self style: 'xxxxxxxxxxxx !![a](p.png) and !![a](p.png)' cursor: -1 owner: owner).
	self assert: after size equals: 2.
	self deny: after first cache == after second cache.
	self assert: before first cache == after first cache.
	self assert: before second cache == after second cache.
	before do: [ :each | self buildAdornment: each ].
	after do: [ :each | self buildAdornment: each ].
	self assert: owner calls equals: 2.
	self assert: owner imageAdornmentCache size equals: 2!

testImageOccurrenceOrdinalsCountIdenticalTargetsAndCaptions
	"The count is per target-and-caption pair and keyed by where the token
	 starts, which is what makes it an ordinal rather than a position."
	| ordinals |
	ordinals := McMarkdownInlineStyler
		imageOrdinalsIn: '!![a](p.png) !![b](q.png) !![a](p.png)'.
	self assert: ordinals size equals: 3.
	self assert: (ordinals at: 1) equals: 1.
	self assert: (ordinals at: 13) equals: 1.
	self assert: (ordinals at: 25) equals: 2!

testIdenticalCellImagesAtDifferentDocumentPositionsDoNotAlias
	"A cell counts occurrences in its own rope, so two identical cells would
	 both answer one; the cell's document start is what keeps them apart."
	| owner one two |
	owner := McMarkdownImageCacheTestOwner new.
	one := self adornmentsIn: (self styleCell: '!![a](p.png)' at: 10 owner: owner).
	two := self adornmentsIn: (self styleCell: '!![a](p.png)' at: 40 owner: owner).
	self assert: one size equals: 1.
	self assert: two size equals: 1.
	self deny: one first cache == two first cache.
	self buildAdornment: one first.
	self buildAdornment: two first.
	self assert: owner calls equals: 2.
	self assert: owner imageAdornmentCache size equals: 2!

testEditorKeepsTheImagePoolAcrossSourceEditsAndRotatesItOnLifecycle
	"A source edit no longer retires the pool, because a key is no longer a
	 position: the same occurrence addresses the same element on the other side
	 of an edit.  What still rotates it is a change that invalidates the
	 elements themselves -- a theme, which bakes colours into them, and an
	 explicit reset, which is what opening another document does."
	| instance pool |
	instance := McRichEdit new.
	instance noteImageCacheSource: 'one'.
	pool := instance imageAdornmentCache.
	instance noteImageCacheSource: 'one'.
	self assert: instance imageAdornmentCache == pool.
	instance noteImageCacheSource: 'two'.
	self assert: instance imageAdornmentCache == pool.
	instance darkMode: true.
	self deny: instance imageAdornmentCache == pool.
	pool := instance imageAdornmentCache.
	instance resetImageAdornmentCache.
	self deny: instance imageAdornmentCache == pool! !

!McMarkdownLinkTest methodsFor: 'tests - resolution'!
testRelativeFileResolvesBesideTheCurrentDocument
	| current target instance link |
	current := self write: '# current' to: 'notes/current.md'.
	target := self write: '# next' to: 'notes/next.md'.
	instance := McRichEdit new.
	instance instVarNamed: 'documentFile' put: current.
	link := self linkTarget: 'next.md'.
	self assert: (instance resolvedFileForLink: link) equals: target.
	self assert: (instance linkStateFor: link) equals: #local!

testWikiTargetGetsAMarkdownExtension
	| current target instance |
	current := self write: '# current' to: 'current.md'.
	target := self write: '# next' to: 'Next.md'.
	instance := McRichEdit new.
	instance instVarNamed: 'documentFile' put: current.
	self assert: (instance resolvedFileForLink: (self linkTarget: 'Next')) equals: target!

testMissingLocalTargetIsDead
	| current instance |
	current := self write: '# current' to: 'current.md'.
	instance := McRichEdit new.
	instance instVarNamed: 'documentFile' put: current.
	self assert: (instance linkStateFor: (self linkTarget: 'missing.md')) equals: #dead!

testValidWebTargetIsExternalWithoutBeingProbed
	| instance |
	instance := McRichEdit new.
	self assert: (instance linkStateFor: (self linkTarget: 'https://example.com/a')) equals: #web.
	self assert: (instance linkStateFor: (self linkTarget: 'https://')) equals: #dead!

testDocumentStampChangesWhenTheFileChanges
	| ref instance first |
	ref := self write: 'one' to: 'current.md'.
	instance := McRichEdit new.
	instance instVarNamed: 'documentFile' put: ref.
	first := instance documentStamp.
	ref writeStreamDo: [ :stream | stream nextPutAll: 'longer' ].
	self deny: instance documentStamp equals: first!

testDocumentPathIsRelativeToTheProject
	| instance |
	instance := McRichEdit new.
	instance
		instVarNamed: 'documentFile'
		put: instance projectRoot / 'samples/demo.md'.
	self assert: instance relativeDocumentPath equals: 'samples/demo.md'! !

!McMarkdownLinkTest methodsFor: 'tests - navigation'!
testCurrentDocumentSpellingsDoNotReopenTheFile
	| current instance targets |
	current := self write: '# current' to: 'current.md'.
	targets := {
		'current.md'.
		current asAbsolute pathString.
		'file://' , current asAbsolute pathString }.
	targets do: [ :target |
		instance := McRichEditNavigationTestDouble new.
		instance instVarNamed: 'documentFile' put: current.
		instance activateLink: (self linkTarget: target).
		self assert: instance openedFile isNil description: target.
		self assert: (instance statusMessage beginsWith: 'Already open:') description: target ]!

testCurrentDocumentFragmentIsRetainedWithoutReopening
	| current instance |
	current := self write: '# current' to: 'current.md'.
	instance := McRichEditNavigationTestDouble new.
	instance instVarNamed: 'documentFile' put: current.
	instance activateLink: (self linkTarget: 'current.md#section-one').
	self assert: instance openedFile isNil.
	self assert: instance statusMessage equals:
		'Already open; anchor navigation pending: #section-one'!

testDifferentLocalDocumentStillOpens
	| current next instance |
	current := self write: '# current' to: 'current.md'.
	next := self write: '# next' to: 'next.md'.
	instance := McRichEditNavigationTestDouble new.
	instance instVarNamed: 'documentFile' put: current.
	instance activateLink: (self linkTarget: 'next.md').
	self assert: instance openedFile equals: next! !

!McMarkdownLinkTest methodsFor: 'tests - environment'!
testEnvironmentReferenceExpandsFromTheProcessEnvironment
	| expanded |
	expanded := McRichEdit new expandEnvironmentIn: '$HOME/notes/current.md'.
	self deny: (expanded includesSubstring: '$HOME').
	self assert: (expanded beginsWith: '/').
	self assert: (expanded endsWith: '/notes/current.md')!

testUnsetEnvironmentReferenceIsLeftStanding
	"Substituting an empty string would turn an absolute target into a
	 relative one and resolve it beside the document instead of failing."
	self
		assert: (McRichEdit new expandEnvironmentIn: '$MC_NO_SUCH_VARIABLE/current.md')
		equals: '$MC_NO_SUCH_VARIABLE/current.md'!

testTildeExpandsOnlyAtTheStart
	| instance |
	instance := McRichEdit new.
	self
		assert: (instance expandEnvironmentIn: 'notes/~/current.md')
		equals: 'notes/~/current.md'.
	self deny: ((instance expandEnvironmentIn: '~/current.md') beginsWith: '~').
	self assert: ((instance expandEnvironmentIn: '~/current.md') endsWith: '/current.md')!

testAbsoluteTargetWithAnEnvironmentReferenceResolves
	"Proves the expansion runs before resolution: unexpanded, the target is
	 relative and gets looked for beside the document, where it is not."
	| current instance prefix |
	current := self write: '# current' to: 'current.md'.
	instance := McRichEdit new.
	instance instVarNamed: 'documentFile' put: current.
	(self homeDir / 'note.md') writeStreamDo: [ :stream | stream nextPutAll: '# note' ].
	prefix := '$HOME/' , self homeDir basename.
	self
		assert: (instance resolvedFileForLink: (self linkTarget: prefix , '/note.md')) contents
		equals: '# note'.
	self
		assert: (instance linkStateFor: (self linkTarget: 'file://' , prefix , '/note.md'))
		equals: #local.
	self
		assert: (instance linkStateFor:
			(self linkTarget: '$MC_NO_SUCH_VARIABLE/' , self homeDir basename , '/note.md'))
		equals: #dead! !
