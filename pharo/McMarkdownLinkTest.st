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
	instanceVariableNames: 'tempDir'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownLinkTest methodsFor: 'running'!
tearDown
	tempDir ifNotNil: [
		[ tempDir ensureDeleteAll ] on: Error do: [ :e | nil ] ].
	super tearDown! !

!McMarkdownLinkTest methodsFor: 'helpers'!
scan: aString
	^ McMarkdownLinkScanner scan: aString!

tempDir
	^ tempDir ifNil: [
		tempDir := FileLocator temp / ('mc-link-test-' , UUID new asString).
		tempDir ensureCreateDirectory.
		tempDir ]!

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
	| text map |
	text := aString asRopedText.
	map := McMarkdownInlineStyler identityMapOfSize: aString size.
	(McMarkdownInlineStyler
		source: aString
		targetMap: map
		documentMap: map
		text: text
		cursor: anInteger
		palette: McRichEdit new palette
		owner: anOwner) styleAll.
	^ text!

hasAttribute: aClass in: aText at: anIndex
	^ (aText attributesAt: anIndex) anySatisfy: [ :each | each isKindOf: aClass ]! !

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
