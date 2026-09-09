"
McFloaty -- floaty directive parsing for the corkboard.

A floaty directive is a comment, alone on its line, that gives a card its
geometry:

    <!!-- f@330x230+420-120 -->
    ;;; f@50%x25%+5%+2%

The form is that of whacked/floaty-edit-mode -- COMMENT_PREFIX f@WWWxHHH
followed by an optional offset -- with two deliberate differences.

Offsets are signed.  floaty writes +XXX+YYY because an Emacs child frame sits
inside its parent, but the corkboard's whole premise is a signed document
plane, so -120 has to be sayable.  And the numbers are document pixels rather
than character cells: they are the same units the coordinate fields already
show, which makes a drag writeback lossless instead of a rounding.

Any of the four numbers may independently carry a percent sign, in which case
it resolves against the parent card's box -- width and x against its width,
height and y against its height.  A root card's parent box is the canvas
viewport, so the rule needs no special case at the top.

Hierarchy comes from the document, not from the directives.  A directive on
the first non-blank line of the file is the host, and governs the whole
document -- being the top comment is what makes it the host, so a directive
further down is always a child however early it appears.  Every other
directive governs a heading section: the one it introduces, when a heading is
the next non-blank line after it, and otherwise the one it sits inside.
Heading levels alone then decide what nests inside what, and a section with no
directive is simply not a card.

A card's text always begins at its own directive line.  That is what settles
whether a heading belongs to the card or to its host: a directive placed above
a heading takes that heading into the card, and one placed below it leaves the
heading behind.  It also means the first line a card shows is the directive
that positions it, which keeps it legible in a card too short to scroll.

Outside markdown there are no headings to read, so every directive is at the
same level and only the host rule nests anything.

Headings are read with McMarkdownParser rather than by scanning for a leading
hash, because that parser already knows a hash inside a fenced code block is
not a heading, and it records the source range of every node -- which is what
lets a directive be rewritten in place after a drag.

Source ranges are stamped once against the text as parsed and never move.
Writeback edits the directive objects, and #renderedSource replays every
directive onto the original string back to front, so the ranges stay valid for
the life of the document however often a card is dragged.

Chunk format: load with fileIn.
"!

Object subclass: #McFloatyMeasure
	instanceVariableNames: 'value unit'
	classVariableNames: ''
	package: 'MalleableControl'!

Object subclass: #McFloatyGeometry
	instanceVariableNames: 'width height x y'
	classVariableNames: ''
	package: 'MalleableControl'!

Object subclass: #McFloatyDirective
	instanceVariableNames: 'geometry range indent prefix suffix label level regionStart regionStop parent children'
	classVariableNames: ''
	package: 'MalleableControl'!

Object subclass: #McFloatyDocument
	instanceVariableNames: 'source markdown roots'
	classVariableNames: ''
	package: 'MalleableControl'!

!McFloatyMeasure class methodsFor: 'instance creation'!
value: aNumber unit: aSymbol
	^ self new setValue: aNumber unit: aSymbol; yourself!

px: aNumber
	^ self value: aNumber unit: #px!

percent: aNumber
	^ self value: aNumber unit: #percent! !

!McFloatyMeasure class methodsFor: 'parsing'!
parse: aString
	"A signed integer with an optional trailing percent, and nothing else.
	 Answers nil rather than signalling, because a line that fails to parse is
	 not a directive at all -- it is ordinary text that happens to start with a
	 comment marker."
	| size index sign digitStart magnitude unit |
	size := aString size.
	size = 0 ifTrue: [ ^ nil ].
	index := 1.
	sign := 1.
	"Indexed access answers Characters; enumerating a String in this image
	 answers codepoints, which have no #isDigit."
	(((aString at: index) = $+) or: [ (aString at: index) = $- ]) ifTrue: [
		(aString at: index) = $- ifTrue: [ sign := -1 ].
		index := index + 1 ].
	digitStart := index.
	magnitude := 0.
	[ index <= size and: [ (aString at: index) isDigit ] ] whileTrue: [
		magnitude := magnitude * 10 + (aString at: index) digitValue.
		index := index + 1 ].
	index = digitStart ifTrue: [ ^ nil ].
	unit := #px.
	(index <= size and: [ (aString at: index) = $% ]) ifTrue: [
		unit := #percent.
		index := index + 1 ].
	index <= size ifTrue: [ ^ nil ].
	^ self value: sign * magnitude unit: unit!

parseDimension: aString
	"A width or a height: never signed, so it must open with a digit."
	(aString isEmpty or: [ (aString at: 1) isDigit not ]) ifTrue: [ ^ nil ].
	^ self parse: aString!

parseOffset: aString
	"An offset always carries its sign, which is what separates the x part of
	 +420-120 from the y part."
	aString isEmpty ifTrue: [ ^ nil ].
	(((aString at: 1) = $+) or: [ (aString at: 1) = $- ]) ifFalse: [ ^ nil ].
	^ self parse: aString! !

!McFloatyMeasure methodsFor: 'initialization'!
setValue: aNumber unit: aSymbol
	value := aNumber.
	unit := aSymbol! !

!McFloatyMeasure methodsFor: 'accessing'!
value
	^ value!

unit
	^ unit!

isPercent
	^ unit = #percent! !

!McFloatyMeasure methodsFor: 'resolving'!
resolveAgainst: aBase
	"Pixels for aBase pixels of parent box."
	self isPercent ifFalse: [ ^ value ].
	^ (value / 100 * aBase) rounded!

withPixels: aNumber against: aBase
	"The same measure expressed so that it resolves to aNumber pixels, keeping
	 the unit the author wrote.  A percent directive stays a percent directive
	 across a drag, which is the whole point of writing one; the cost is that
	 the drag lands on the nearest whole percent of the parent box."
	self isPercent ifFalse: [ ^ self class px: aNumber rounded ].
	aBase = 0 ifTrue: [ ^ self class percent: 0 ].
	^ self class percent: (aNumber / aBase * 100) rounded! !

!McFloatyMeasure methodsFor: 'printing'!
unitSuffix
	^ self isPercent ifTrue: [ '%' ] ifFalse: [ '' ]!

dimensionString
	^ value printString , self unitSuffix!

offsetString
	^ (value < 0 ifTrue: [ '-' ] ifFalse: [ '+' ]) , value abs printString , self unitSuffix!

= anObject
	^ self class = anObject class
		and: [ value = anObject value and: [ unit = anObject unit ] ]!

hash
	^ value hash bitXor: unit hash!

printOn: aStream
	aStream nextPutAll: self dimensionString! !

!McFloatyGeometry class methodsFor: 'instance creation'!
width: aWidth height: aHeight x: anX y: aY
	^ self new setWidth: aWidth height: aHeight x: anX y: aY; yourself! !

!McFloatyGeometry class methodsFor: 'parsing'!
parse: aString
	"aString is what follows f@ -- for example 330x230+420-120 or 50%x25%+5%+2%.
	 The offsets are optional and default to the parent origin."
	| xIndex widthPart rest splitIndex heightPart offsets width height yIndex x y |
	xIndex := aString indexOf: $x.
	xIndex < 2 ifTrue: [ ^ nil ].
	widthPart := aString copyFrom: 1 to: xIndex - 1.
	rest := aString copyFrom: xIndex + 1 to: aString size.
	rest isEmpty ifTrue: [ ^ nil ].
	"The first sign at or after the second character opens the offset part.
	 It cannot be at the first, because a height is never signed."
	splitIndex := self signIndexIn: rest from: 2.
	splitIndex = 0
		ifTrue: [ heightPart := rest. offsets := '' ]
		ifFalse: [
			heightPart := rest copyFrom: 1 to: splitIndex - 1.
			offsets := rest copyFrom: splitIndex to: rest size ].
	width := McFloatyMeasure parseDimension: widthPart.
	height := McFloatyMeasure parseDimension: heightPart.
	(width isNil or: [ height isNil ]) ifTrue: [ ^ nil ].
	offsets isEmpty ifTrue: [
		^ self
			width: width
			height: height
			x: (McFloatyMeasure px: 0)
			y: (McFloatyMeasure px: 0) ].
	yIndex := self signIndexIn: offsets from: 2.
	yIndex = 0 ifTrue: [ ^ nil ].
	x := McFloatyMeasure parseOffset: (offsets copyFrom: 1 to: yIndex - 1).
	y := McFloatyMeasure parseOffset: (offsets copyFrom: yIndex to: offsets size).
	(x isNil or: [ y isNil ]) ifTrue: [ ^ nil ].
	^ self width: width height: height x: x y: y!

signIndexIn: aString from: anIndex
	anIndex to: aString size do: [ :each |
		(((aString at: each) = $+) or: [ (aString at: each) = $- ])
			ifTrue: [ ^ each ] ].
	^ 0! !

!McFloatyGeometry methodsFor: 'initialization'!
setWidth: aWidth height: aHeight x: anX y: aY
	width := aWidth.
	height := aHeight.
	x := anX.
	y := aY! !

!McFloatyGeometry methodsFor: 'accessing'!
width
	^ width!

height
	^ height!

x
	^ x!

y
	^ y!

hasPercent
	^ width isPercent or: [
		height isPercent or: [ x isPercent or: [ y isPercent ] ] ]! !

!McFloatyGeometry methodsFor: 'resolving'!
extentIn: aParentExtent
	^ (width resolveAgainst: aParentExtent x) @ (height resolveAgainst: aParentExtent y)!

positionIn: aParentExtent
	^ (x resolveAgainst: aParentExtent x) @ (y resolveAgainst: aParentExtent y)!

withPosition: aPoint in: aParentExtent
	"The same geometry moved to aPoint, each offset still written in the unit
	 the author chose."
	^ self class
		width: width
		height: height
		x: (x withPixels: aPoint x against: aParentExtent x)
		y: (y withPixels: aPoint y against: aParentExtent y)! !

!McFloatyGeometry methodsFor: 'printing'!
asDirectiveString
	^ 'f@' , width dimensionString , 'x' , height dimensionString
		, x offsetString , y offsetString!

= anObject
	^ self class = anObject class
		and: [ width = anObject width
			and: [ height = anObject height
				and: [ x = anObject x and: [ y = anObject y ] ] ] ]!

hash
	^ width hash bitXor: (height hash bitXor: (x hash bitXor: y hash))!

printOn: aStream
	aStream nextPutAll: self asDirectiveString! !

!McFloatyDirective class methodsFor: 'instance creation'!
geometry: aGeometry range: anInterval indent: anIndent prefix: aPrefix suffix: aSuffix
	^ self new
		setGeometry: aGeometry range: anInterval indent: anIndent prefix: aPrefix suffix: aSuffix;
		yourself! !

!McFloatyDirective methodsFor: 'initialization'!
setGeometry: aGeometry range: anInterval indent: anIndent prefix: aPrefix suffix: aSuffix
	geometry := aGeometry.
	range := anInterval.
	indent := anIndent.
	prefix := aPrefix.
	suffix := aSuffix.
	children := OrderedCollection new.
	label := ''.
	level := 0! !

!McFloatyDirective methodsFor: 'accessing'!
geometry
	^ geometry!

geometry: aGeometry
	geometry := aGeometry!

range
	"The source interval of the directive line itself, indentation included.
	 This is what writeback replaces."
	^ range!

regionStart
	^ regionStart!

regionStop
	^ regionStop!

regionStart: aStart stop: aStop
	regionStart := aStart.
	regionStop := aStop!

regionRange
	"The source interval of the text this card shows."
	^ regionStart to: regionStop!

label
	^ label!

label: aString
	label := aString!

level
	^ level!

level: anInteger
	level := anInteger!

parent
	^ parent!

children
	^ children asArray!

isRoot
	^ parent isNil! !

!McFloatyDirective methodsFor: 'tree'!
addChild: aDirective
	children add: aDirective.
	aDirective setParent: self.
	^ aDirective!

setParent: aDirective
	parent := aDirective!

withAllChildrenDo: aBlock
	aBlock value: self.
	children do: [ :each | each withAllChildrenDo: aBlock ]! !

!McFloatyDirective methodsFor: 'printing'!
directiveLine
	"The line this directive would be written as now.  Indentation and comment
	 style are the author's and are preserved; only the geometry is ours."
	^ suffix isEmpty
		ifTrue: [ indent , prefix , ' ' , geometry asDirectiveString ]
		ifFalse: [ indent , prefix , ' ' , geometry asDirectiveString , ' ' , suffix ]!

printOn: aStream
	aStream nextPutAll: 'McFloatyDirective('; nextPutAll: self directiveLine; nextPut: $)! !

!McFloatyDocument class methodsFor: 'instance creation'!
on: aString markdown: aBoolean
	^ self new setSource: aString markdown: aBoolean; parse; yourself!

onFile: aFileReference
	| ref |
	ref := aFileReference asFileReference.
	^ self
		on: ref contents
		markdown: (#('md' 'markdown' 'mdown') includes: ref extension asLowercase)! !

!McFloatyDocument class methodsFor: 'prefixes'!
markdownPrefixes
	"Only the HTML comment.  In a markdown document ## opens a heading, and a
	 line cannot be both the heading that creates a section and the comment
	 that configures it."
	^ #('<!!--')!

flatPrefixes
	^ #(';;;' '##' '<!!--')!

suffixes
	^ #('-->' '*/')! !

!McFloatyDocument methodsFor: 'initialization'!
setSource: aString markdown: aBoolean
	source := aString.
	markdown := aBoolean.
	roots := OrderedCollection new! !

!McFloatyDocument methodsFor: 'accessing'!
source
	^ source!

isMarkdown
	^ markdown!

roots
	^ roots asArray!

allDirectives
	| all |
	all := OrderedCollection new.
	roots do: [ :each | each withAllChildrenDo: [ :one | all add: one ] ].
	^ all asArray!

directiveLabelled: aString
	^ self allDirectives detect: [ :each | each label = aString ] ifNone: [ nil ]! !

!McFloatyDocument methodsFor: 'rendering'!
renderedSource
	^ self renderRange: (1 to: source size)!

renderRange: anInterval
	"anInterval of the source with every directive inside it replaced by what
	 that directive says now.  Replacing back to front keeps the untouched
	 ranges valid as the text changes length, which is why the ranges recorded
	 at parse time never need updating."
	| text inside |
	anInterval last < anInterval first ifTrue: [ ^ '' ].
	text := source copyFrom: anInterval first to: anInterval last.
	inside := (self allDirectives select: [ :each |
		each range first >= anInterval first
			and: [ each range last <= anInterval last ] ])
		asSortedCollection: [ :a :b | a range first > b range first ].
	inside do: [ :each |
		| start stop |
		start := each range first - anInterval first + 1.
		stop := each range last - anInterval first + 1.
		text := (text copyFrom: 1 to: start - 1) , each directiveLine
			, (text copyFrom: stop + 1 to: text size) ].
	^ text! !

!McFloatyDocument methodsFor: 'parsing'!
parse
	| records |
	records := self scanDirectives.
	markdown
		ifTrue: [
			self
				placeAsMarkdown: records
				headings: (self headingsIn: (self maskedSourceFrom: records)) ]
		ifFalse: [ self placeAsFlat: records ].
	^ self! !

!McFloatyDocument methodsFor: 'parsing - private'!
lineIntervals
	| intervals start index size |
	intervals := OrderedCollection new.
	size := source size.
	start := 1.
	index := 1.
	[ index <= size ] whileTrue: [
		(source at: index) = Character lf ifTrue: [
			intervals add: (start to: index - 1).
			start := index + 1 ].
		index := index + 1 ].
	intervals add: (start to: size).
	^ intervals asArray!

lineAt: anInterval
	anInterval last < anInterval first ifTrue: [ ^ '' ].
	^ source copyFrom: anInterval first to: anInterval last!

prefixesInUse
	^ markdown
		ifTrue: [ self class markdownPrefixes ]
		ifFalse: [ self class flatPrefixes ]!

prefixOf: aTrimmedLine
	self prefixesInUse do: [ :each |
		(aTrimmedLine beginsWith: each) ifTrue: [ ^ each ] ].
	^ nil!

directiveOn: aLine
	"An Array of prefix, body and suffix when aLine is a directive and nothing
	 else, otherwise nil.  The body is whatever followed f@, which is either a
	 geometry or the word end."
	| trimmed prefix rest suffix |
	trimmed := aLine trimBoth.
	prefix := self prefixOf: trimmed.
	prefix ifNil: [ ^ nil ].
	rest := (trimmed allButFirst: prefix size) trimBoth.
	suffix := ''.
	self class suffixes do: [ :each |
		(suffix isEmpty and: [ rest endsWith: each ]) ifTrue: [
			suffix := each.
			rest := (rest copyFrom: 1 to: rest size - each size) trimBoth ] ].
	(rest beginsWith: 'f@') ifFalse: [ ^ nil ].
	^ { prefix. (rest allButFirst: 2) trimBoth. suffix }!

indentOf: aLine
	| index |
	index := 1.
	[ index <= aLine size and: [ (aLine at: index) isSeparator ] ]
		whileTrue: [ index := index + 1 ].
	^ aLine copyFrom: 1 to: index - 1!

scanDirectives
	"Every directive line in document order, each as an Array of its source
	 interval, the parsed prefix/body/suffix, and the line's indentation.
	 An f@end carries a nil geometry and only ever closes a region."
	| found |
	found := OrderedCollection new.
	self lineIntervals do: [ :interval |
		| line parsed |
		line := self lineAt: interval.
		parsed := self directiveOn: line.
		parsed ifNotNil: [
			| body geometry |
			body := parsed second.
			geometry := body asLowercase = 'end'
				ifTrue: [ nil ]
				ifFalse: [ McFloatyGeometry parse: body ].
			(geometry notNil or: [ body asLowercase = 'end' ]) ifTrue: [
				found add: {
					interval.
					geometry.
					(self indentOf: line).
					parsed first.
					parsed third } ] ] ].
	^ found!

directiveFrom: aRecord
	^ McFloatyDirective
		geometry: (aRecord at: 2)
		range: (aRecord at: 1)
		indent: (aRecord at: 3)
		prefix: (aRecord at: 4)
		suffix: (aRecord at: 5)!

buildTreeFrom: aCollection
	"aCollection is directives in document order, each already carrying its
	 level.  A directive nests inside the last one shallower than itself, which
	 is the only rule either layout needs."
	| stack |
	stack := OrderedCollection new.
	aCollection do: [ :each |
		[ stack notEmpty and: [ stack last level >= each level ] ]
			whileTrue: [ stack removeLast ].
		stack isEmpty
			ifTrue: [ roots add: each ]
			ifFalse: [ stack last addChild: each ].
		stack addLast: each ]! !

!McFloatyDocument methodsFor: 'parsing - markdown'!
maskedSourceFrom: aCollection
	"The source with every directive line overwritten by spaces.

	 Microdown reads <!! as the opener of an environment block, so an HTML
	 comment does not merely fail to be a heading -- it swallows the rest of
	 the document, and no heading after the first directive reaches the AST at
	 all.  Blanking the directive lines removes them from Microdown's view.

	 The mask is the same length as what it replaces, so every offset the
	 parser stamps still addresses the real source."
	| text |
	text := source copy.
	aCollection do: [ :record |
		(record at: 1) do: [ :index | text at: index put: Character space ] ].
	^ text!

headingsIn: aString
	"Start, level and title of every heading, read from the markdown AST rather
	 than from the raw lines so that a hash inside a fenced code block is not
	 mistaken for one."
	| parser found |
	parser := McMarkdownParser parseSource: aString.
	found := OrderedCollection new.
	parser root children do: [ :each |
		each class name asString = 'MicHeaderBlock' ifTrue: [
			| range |
			range := parser rangeOf: each.
			range ifNotNil: [
				found add: {
					range first.
					each level.
					(self headingLabelFrom: (parser sourceOf: each)) } ] ] ].
	^ found asArray!

headingLabelFrom: aString
	| line index |
	line := aString lines isEmpty ifTrue: [ '' ] ifFalse: [ aString lines first ].
	index := 1.
	[ index <= line size and: [ (line at: index) = $# ] ]
		whileTrue: [ index := index + 1 ].
	^ (line copyFrom: index to: line size) trimBoth!

placeAsMarkdown: aCollection headings: aHeadingCollection
	"The top comment is the host and owns the whole file.  Every other
	 directive governs the section it introduces, or failing that the one it
	 sits inside, and always starts its card at its own line."
	| all placed governed host |
	all := aHeadingCollection.
	placed := OrderedCollection new.
	governed := OrderedCollection new.
	host := self hostRecordIn: aCollection.
	aCollection do: [ :record |
		(record at: 2) ifNotNil: [
			| directive owner key |
			directive := self directiveFrom: record.
			record == host
				ifTrue: [
					key := -1.
					directive
						level: 0;
						label: 'document';
						regionStart: 1 stop: source size ]
				ifFalse: [
					"A heading on the next non-blank line is the one being
					 introduced, so it belongs to this card.  Otherwise the
					 directive is inside a section already under way, and that
					 section's heading stays behind in the host."
					owner := self headingIndexFollowing: (record at: 1) in: all.
					owner = 0 ifTrue: [
						owner := self headingIndexEnclosing: (record at: 1) first in: all ].
					key := owner.
					directive
						level: (owner = 0 ifTrue: [ 0 ] ifFalse: [ (all at: owner) second ]);
						label: (owner = 0
							ifTrue: [ 'document' ]
							ifFalse: [ (all at: owner) third ]);
						regionStart: (record at: 1) first
							stop: ((self sectionStopFor: owner in: all)
								min: (self endStopFor: (record at: 1) last in: aCollection)) ].
			"Two directives governing one section would describe the same card
			 twice.  The first wins; the second is left as ordinary text."
			(governed includes: key) ifFalse: [
				governed add: key.
				placed add: directive ] ] ].
	self buildTreeFrom: placed!

hostRecordIn: aCollection
	"The record on the first non-blank line of the file, or nil.  Being the top
	 comment is the whole of what makes a directive the host."
	| first |
	first := self lineIntervals
		detect: [ :each | (self lineAt: each) trimBoth notEmpty ]
		ifNone: [ nil ].
	first ifNil: [ ^ nil ].
	^ aCollection
		detect: [ :each | (each at: 1) first = first first ]
		ifNone: [ nil ]!

headingIndexFollowing: anInterval in: aHeadingCollection
	"The heading beginning on the next non-blank line after anInterval, or 0."
	| next |
	next := self lineIntervals
		detect: [ :each |
			each first > anInterval last
				and: [ (self lineAt: each) trimBoth notEmpty ] ]
		ifNone: [ nil ].
	next ifNil: [ ^ 0 ].
	aHeadingCollection withIndexDo: [ :each :index |
		each first = next first ifTrue: [ ^ index ] ].
	^ 0!

headingIndexEnclosing: aStart in: aHeadingCollection
	| owner |
	owner := 0.
	aHeadingCollection withIndexDo: [ :each :index |
		each first <= aStart ifTrue: [ owner := index ] ].
	^ owner!

sectionStopFor: anIndex in: aCollection
	"A section runs to the next heading at or above its own level."
	| level |
	anIndex = 0 ifTrue: [ ^ source size ].
	level := (aCollection at: anIndex) second.
	(anIndex + 1 to: aCollection size) do: [ :each |
		(aCollection at: each) second <= level
			ifTrue: [ ^ (aCollection at: each) first - 1 ] ].
	^ source size!

endStopFor: aStart in: aCollection
	"An f@end closes whatever region is open, so a card stops on the line
	 before the first one that follows its directive.  It can only shorten a
	 section, never carry it past the heading that ends it."
	aCollection do: [ :each |
		((each at: 2) isNil and: [ (each at: 1) first > aStart ])
			ifTrue: [ ^ (each at: 1) first - 1 ] ].
	^ source size! !

!McFloatyDocument methodsFor: 'parsing - flat'!
placeAsFlat: aCollection
	"Outside markdown every directive is at the same level, so the document
	 itself supplies the only nesting there is: a directive on the first
	 non-blank line governs the whole file and everything after it is a child.
	 A region runs to the next directive, an f@end, or the end of the file."
	| opens hosted placed |
	opens := aCollection select: [ :each | (each at: 2) notNil ].
	opens isEmpty ifTrue: [ ^ self ].
	hosted := self firstNonBlankLineIsDirective: opens.
	placed := OrderedCollection new.
	opens withIndexDo: [ :record :index |
		| directive isHost |
		isHost := hosted and: [ index = 1 ].
		directive := self directiveFrom: record.
		directive
			level: (isHost ifTrue: [ 0 ] ifFalse: [ hosted ifTrue: [ 1 ] ifFalse: [ 0 ] ]);
			label: (isHost
				ifTrue: [ 'document' ]
				ifFalse: [ self flatLabelFor: record in: aCollection ]);
			regionStart: (isHost ifTrue: [ 1 ] ifFalse: [ (record at: 1) first ])
				stop: (isHost
					ifTrue: [ source size ]
					ifFalse: [ self flatStopFor: record in: aCollection ]).
		placed add: directive ].
	self buildTreeFrom: placed!

firstNonBlankLineIsDirective: aCollection
	| first |
	first := self lineIntervals
		detect: [ :each | (self lineAt: each) trimBoth notEmpty ]
		ifNone: [ nil ].
	first ifNil: [ ^ false ].
	^ aCollection anySatisfy: [ :each | (each at: 1) first = first first ]!

flatStopFor: aRecord in: aCollection
	"The next directive of any kind closes this one, f@end included."
	| start |
	start := (aRecord at: 1) first.
	aCollection do: [ :each |
		(each at: 1) first > start ifTrue: [ ^ (each at: 1) first - 1 ] ].
	^ source size!

flatLabelFor: aRecord in: aCollection
	"The first line of the region that is neither blank nor a directive, which
	 is the closest thing a plain file has to a section title."
	| stop |
	stop := self flatStopFor: aRecord in: aCollection.
	self lineIntervals do: [ :interval |
		| line |
		(interval first > (aRecord at: 1) first and: [ interval first <= stop ]) ifTrue: [
			line := (self lineAt: interval) trimBoth.
			(line notEmpty and: [ (self directiveOn: line) isNil ]) ifTrue: [
				^ line size > 40
					ifTrue: [ (line copyFrom: 1 to: 40) , '...' ]
					ifFalse: [ line ] ] ] ].
	^ 'section'! !
