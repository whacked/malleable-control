"
McMarkdownSnapshot -- immutable, addressed structural projections over a
McMarkdownParser result.

The parser remains the source-map authority.  These objects neither modify it
nor Microdown nodes; they provide the retained structural seam needed before a
renderer can reconcile and patch individual blocks.

Chunk format: load with fileIn.
"!

Object subclass: #McMarkdownPath
	instanceVariableNames: 'steps'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownPath class methodsFor: 'instance creation'!
document
	^ self new setSteps: #()!

fromString: aString
	"Parse the canonical absolute-location subset used by snapshots.  Keeping
	 this strict makes malformed addresses fail before a render patch uses one."
	| parts parsed |
	aString = '/document' ifTrue: [ ^ self document ].
	(aString beginsWith: '/document/') ifFalse: [ ^ nil ].
	parts := (aString allButFirst: '/document/' size) substrings: '/'.
	parts isEmpty ifTrue: [ ^ nil ].
	parsed := OrderedCollection new.
	parts do: [ :part |
		| open close kind ordinalString ordinal |
		open := part indexOf: $[.
		close := part indexOf: $].
		(open <= 1 or: [ close ~= part size ]) ifTrue: [ ^ nil ].
		kind := part copyFrom: 1 to: open - 1.
		ordinalString := part copyFrom: open + 1 to: close - 1.
		ordinalString isEmpty ifTrue: [ ^ nil ].
		ordinalString do: [ :character | character isDigit ifFalse: [ ^ nil ] ].
		ordinal := [ ordinalString asNumber ] on: Error do: [ :error | ^ nil ].
		ordinal > 0 ifFalse: [ ^ nil ].
		parsed add: { kind. ordinal } ].
	^ self new setSteps: parsed asArray! !

!McMarkdownPath methodsFor: 'initialization'!
setSteps: aCollection
	steps := aCollection asArray! !

!McMarkdownPath methodsFor: 'accessing'!
steps
	^ steps copy!

appendKind: aKind ordinal: anInteger
	^ self class new setSteps: (steps copyWith: { aKind. anInteger })!

asString
	| stream |
	stream := String streamContents: [ :out |
		out nextPutAll: '/document'.
		steps do: [ :step |
			out nextPut: $/; nextPutAll: step first; nextPut: $[;
			nextPutAll: step second printString; nextPut: $] ] ].
	^ stream!

printOn: aStream
	aStream nextPutAll: self asString!

= anObject
	^ self class = anObject class and: [ steps = anObject steps ]!

hash
	^ steps hash! !

Object subclass: #McMarkdownProjectionNode
	instanceVariableNames: 'kind astNode parent children sourceRange address syntaxFingerprint subtreeFingerprint lineageId'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownProjectionNode methodsFor: 'initialization'!
kind: aString astNode: anAstNode parent: aParent sourceRange: aRange address: aPath syntaxFingerprint: aFingerprint
	kind := aString.
	astNode := anAstNode.
	parent := aParent.
	sourceRange := aRange.
	address := aPath.
	syntaxFingerprint := aFingerprint.
	children := OrderedCollection new!

addChild: aNode
	children add: aNode!

subtreeFingerprint: aString
	subtreeFingerprint := aString!

lineageId: anObject
	lineageId := anObject! !

!McMarkdownProjectionNode methodsFor: 'accessing'!
kind
	^ kind!

astNode
	^ astNode!

parent
	^ parent!

children
	^ children asArray!

sourceRange
	^ sourceRange!

address
	^ address!

addressString
	^ address asString!

syntaxFingerprint
	^ syntaxFingerprint!

subtreeFingerprint
	^ subtreeFingerprint!

lineageId
	^ lineageId! !

Object subclass: #McMarkdownDocumentSnapshot
	instanceVariableNames: 'source parser root addressIndex astIndex intervalIndex lineageIndex'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownDocumentSnapshot class methodsFor: 'instance creation'!
parseSource: aString
	^ self forParser: (McMarkdownParser parseSource: aString)!

forParser: aParser
	^ self new initializeForParser: aParser; yourself! !

!McMarkdownDocumentSnapshot methodsFor: 'initialization'!
initializeForParser: aParser
	parser := aParser.
	source := parser source copy.
	addressIndex := Dictionary new.
	astIndex := IdentityDictionary new.
	intervalIndex := OrderedCollection new.
	lineageIndex := Dictionary new.
	root := self buildRoot.
	self indexNode: root!

buildRoot
	| node |
	node := McMarkdownProjectionNode new.
	node
		kind: 'document'
		astNode: parser root
		parent: nil
		sourceRange: (source isEmpty ifTrue: [ nil ] ifFalse: [ 1 to: source size ])
		address: McMarkdownPath document
		syntaxFingerprint: 'document'.
	self buildChildrenOf: parser root into: node parentPath: node address.
	self computeSubtreeFingerprintFor: node.
	^ node!

buildChildrenOf: anAstNode into: aProjectionNode parentPath: aPath
	| ordinals |
	ordinals := Dictionary new.
	(self structuralChildrenOf: anAstNode) do: [ :child |
		| kind ordinal path node |
		kind := self kindFor: child.
		ordinal := (ordinals at: kind ifAbsent: [ 0 ]) + 1.
		ordinals at: kind put: ordinal.
		path := aPath appendKind: kind ordinal: ordinal.
		node := McMarkdownProjectionNode new.
		node
			kind: kind
			astNode: child
			parent: aProjectionNode
			sourceRange: (parser rangeOf: child)
			address: path
			syntaxFingerprint: (self syntaxFingerprintFor: child kind: kind).
		aProjectionNode addChild: node.
		self buildChildrenOf: child into: node parentPath: path ]!

structuralChildrenOf: anAstNode
	| children |
	(anAstNode respondsTo: #children) ifFalse: [ ^ #() ].
	children := anAstNode children.
	(children isNil or: [ children isString ]) ifTrue: [ ^ #() ].
	^ children select: [ :each | (parser rangeOf: each) notNil ]!

kindFor: anAstNode
	| className raw |
	className := anAstNode class name asString.
	raw := parser sourceOf: anAstNode.
	className = 'MicHeaderBlock' ifTrue: [ ^ 'header' ].
	className = 'MicQuoteBlock' ifTrue: [ ^ 'quote' ].
	className = 'MicUnorderedListBlock' ifTrue: [ ^ 'unordered-list' ].
	className = 'MicOrderedListBlock' ifTrue: [ ^ 'ordered-list' ].
	className = 'MicListItemBlock' ifTrue: [ ^ 'item' ].
	className = 'MicCodeBlock' ifTrue: [ ^ 'code-block' ].
	className = 'MicTableBlock' ifTrue: [ ^ 'table' ].
	className = 'MicHorizontalLineBlock' ifTrue: [ ^ 'horizontal-rule' ].
	(className = 'MicParagraphBlock' and: [ self isHorizontalRule: raw ]) ifTrue: [ ^ 'horizontal-rule' ].
	^ 'paragraph'!

isHorizontalRule: aString
	| trimmed |
	trimmed := aString trimBoth.
	(trimmed size < 3) ifTrue: [ ^ false ].
	^ (trimmed allSatisfy: [ :each | each = $- or: [ each = $_ or: [ each = $* ] ] ])!

syntaxFingerprintFor: anAstNode kind: aKind
	"This deliberately retains raw syntax instead of image-seeded #hash.
	 Equality, not digest compactness, is the phase-one correctness basis."
	^ aKind , ':' , (parser sourceOf: anAstNode)!

computeSubtreeFingerprintFor: aNode
	| stream |
	aNode children do: [ :child | self computeSubtreeFingerprintFor: child ].
	stream := String streamContents: [ :out |
		out nextPutAll: aNode syntaxFingerprint.
		aNode children do: [ :child | out nextPut: $(; nextPutAll: child subtreeFingerprint; nextPut: $) ] ].
	aNode subtreeFingerprint: stream!

indexNode: aNode
	addressIndex at: aNode addressString put: aNode.
	astIndex at: aNode astNode put: aNode.
	aNode sourceRange ifNotNil: [ intervalIndex add: aNode ].
	aNode lineageId ifNotNil: [ lineageIndex at: aNode lineageId put: aNode ].
	aNode children do: [ :child | self indexNode: child ]! !

!McMarkdownDocumentSnapshot methodsFor: 'accessing'!
source
	^ source!

parser
	^ parser!

root
	^ root!

nodeAtAddress: aPathOrString
	| path |
	path := aPathOrString isString
		ifTrue: [ McMarkdownPath fromString: aPathOrString ]
		ifFalse: [ aPathOrString ].
	path ifNil: [ ^ nil ].
	^ addressIndex at: path asString ifAbsent: [ nil ]!

nodeForAst: anAstNode
	^ astIndex at: anAstNode ifAbsent: [ nil ]!

nodesIntersecting: aRange
	^ intervalIndex select: [ :each |
		each sourceRange first <= aRange last and: [ each sourceRange last >= aRange first ] ]!

rootChildContainingPosition: anInteger
	^ root children detect: [ :each |
		each sourceRange notNil and: [
			anInteger >= each sourceRange first and: [ anInteger <= each sourceRange last ] ] ]
		ifNone: [ nil ]!

allNodes
	^ addressIndex values asArray!

resolve: aString
	^ self nodeAtAddress: aString! !

Object subclass: #McMarkdownPathResolver
	instanceVariableNames: 'snapshot'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownPathResolver class methodsFor: 'instance creation'!
on: aSnapshot
	^ self new snapshot: aSnapshot; yourself! !

!McMarkdownPathResolver methodsFor: 'initialization'!
snapshot: aSnapshot
	snapshot := aSnapshot! !

!McMarkdownPathResolver methodsFor: 'resolving'!
resolve: aString
	^ snapshot resolve: aString! !
