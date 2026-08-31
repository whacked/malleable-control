"
McMarkdownLink and McMarkdownLinkScanner -- tolerant inline navigation tokens.

Microdown recognises ordinary links and figures, but an incomplete opening
bracket makes its inline parser treat the rest of a line as opaque text.  That
is reasonable for a batch renderer and a poor fit for an editor, where every
intermediate keystroke is parsed.  This scanner is deliberately small and
forgiving: it walks one inline block, accepts complete tokens, and leaves
anything incomplete untouched.

The scanner owns syntax only.  It never resolves a path, stats a file, opens a
browser, or loads an image.  Those operations belong to the McRichEdit owner
and therefore stay out of the per-keystroke parsing path.

Supported forms:
  ordinary markdown links and images
  links and images may also carry a quoted title or caption
  <https://example.com>        https://example.com
  [[target]]                   [[target|label]]
  embedded wiki images, optionally with captions

Chunk format: load with fileIn.
"!

Object subclass: #McMarkdownLink
	instanceVariableNames: 'kind start stop labelStart labelStop target label caption'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownLink class methodsFor: 'instance creation'!
kind: aKind start: aStart stop: aStop labelStart: aLabelStart labelStop: aLabelStop target: aTarget label: aLabel caption: aCaption
	^ self new
		setKind: aKind
		start: aStart
		stop: aStop
		labelStart: aLabelStart
		labelStop: aLabelStop
		target: aTarget
		label: aLabel
		caption: aCaption! !

!McMarkdownLink methodsFor: 'initialization'!
setKind: aKind start: aStart stop: aStop labelStart: aLabelStart labelStop: aLabelStop target: aTarget label: aLabel caption: aCaption
	kind := aKind.
	start := aStart.
	stop := aStop.
	labelStart := aLabelStart.
	labelStop := aLabelStop.
	target := aTarget.
	label := aLabel.
	caption := aCaption! !

!McMarkdownLink methodsFor: 'accessing'!
kind
	^ kind!

start
	^ start!

stop
	^ stop!

labelStart
	^ labelStart!

labelStop
	^ labelStop!

target
	^ target!

label
	^ label!

caption
	^ caption!

range
	^ start to: stop!

labelRange
	^ labelStart to: labelStop!

isImage
	^ kind = #image or: [ kind = #wikiImage ]! !

Object subclass: #McMarkdownLinkScanner
	instanceVariableNames: 'source links'
	classVariableNames: ''
	package: 'MalleableControl'!

!McMarkdownLinkScanner class methodsFor: 'scanning'!
scan: aString
	^ self new scan: aString! !

!McMarkdownLinkScanner methodsFor: 'scanning'!
scan: aString
	| index found |
	source := aString.
	links := OrderedCollection new.
	index := 1.
	[ index <= source size ] whileTrue: [
		found := self linkAt: index.
		found
			ifNil: [ index := index + 1 ]
			ifNotNil: [
				links add: found.
				index := found stop + 1 ] ].
	^ links asArray!

linkAt: anIndex
	(self beginsWith: '!![[' at: anIndex) ifTrue: [
		^ self wikiAt: anIndex image: true ].
	(self beginsWith: '[[' at: anIndex) ifTrue: [
		^ self wikiAt: anIndex image: false ].
	(self beginsWith: '!![' at: anIndex) ifTrue: [
		^ self markdownAt: anIndex image: true ].
	(self beginsWith: '[' at: anIndex) ifTrue: [
		^ self markdownAt: anIndex image: false ].
	(self beginsWith: '<https://' at: anIndex) ifTrue: [
		^ self autolinkAt: anIndex ].
	(self beginsWith: '<http://' at: anIndex) ifTrue: [
		^ self autolinkAt: anIndex ].
	(self beginsWith: 'https://' at: anIndex) ifTrue: [
		^ self bareUrlAt: anIndex ].
	(self beginsWith: 'http://' at: anIndex) ifTrue: [
		^ self bareUrlAt: anIndex ].
	^ nil! !

!McMarkdownLinkScanner methodsFor: 'scanning - wiki'!
wikiAt: anIndex image: isImage
	| contentStart close pipe targetStart targetStop labelStart labelStop targetString labelString kind |
	contentStart := anIndex + (isImage ifTrue: [ 3 ] ifFalse: [ 2 ]).
	close := self closingDoubleBracketFrom: contentStart.
	close ifNil: [ ^ nil ].
	contentStart >= close ifTrue: [ ^ nil ].
	pipe := self firstUnescaped: $| from: contentStart to: close - 1.
	targetStart := contentStart.
	targetStop := pipe ifNil: [ close - 1 ] ifNotNil: [ pipe - 1 ].
	labelStart := pipe ifNil: [ contentStart ] ifNotNil: [ pipe + 1 ].
	labelStop := close - 1.
	targetString := (source copyFrom: targetStart to: targetStop) trimBoth.
	labelString := (source copyFrom: labelStart to: labelStop) trimBoth.
	(targetString isEmpty or: [ labelString isEmpty ]) ifTrue: [ ^ nil ].
	kind := isImage ifTrue: [ #wikiImage ] ifFalse: [ #wiki ].
	^ McMarkdownLink
		kind: kind
		start: anIndex
		stop: close + 1
		labelStart: labelStart
		labelStop: labelStop
		target: targetString
		label: labelString
		caption: (isImage ifTrue: [ labelString ] ifFalse: [ '' ])! !

!McMarkdownLinkScanner methodsFor: 'scanning - markdown'!
markdownAt: anIndex image: isImage
	| open labelStart closeLabel openParen closeParen parsed labelString kind |
	open := anIndex + (isImage ifTrue: [ 1 ] ifFalse: [ 0 ]).
	labelStart := open + 1.
	closeLabel := self closingBracketFrom: labelStart.
	closeLabel ifNil: [ ^ nil ].
	(closeLabel + 1 <= source size and: [ (source at: closeLabel + 1) = $( ])
		ifFalse: [ ^ nil ].
	openParen := closeLabel + 1.
	closeParen := self closingParenthesisFrom: openParen + 1.
	closeParen ifNil: [ ^ nil ].
	labelStart >= closeLabel ifTrue: [ ^ nil ].
	parsed := self destinationAndTitleFrom: openParen + 1 to: closeParen - 1.
	parsed first isEmpty ifTrue: [ ^ nil ].
	labelString := source copyFrom: labelStart to: closeLabel - 1.
	kind := isImage ifTrue: [ #image ] ifFalse: [ #link ].
	^ McMarkdownLink
		kind: kind
		start: anIndex
		stop: closeParen
		labelStart: labelStart
		labelStop: closeLabel - 1
		target: parsed first
		label: labelString
		caption: (isImage
			ifTrue: [ parsed second ifEmpty: [ labelString ] ]
			ifFalse: [ parsed second ])! !

!McMarkdownLinkScanner methodsFor: 'scanning - urls'!
autolinkAt: anIndex
	| close target |
	close := source indexOf: $> startingAt: anIndex + 1.
	close = 0 ifTrue: [ ^ nil ].
	target := source copyFrom: anIndex + 1 to: close - 1.
	(target anySatisfy: [ :each | each isSeparator ]) ifTrue: [ ^ nil ].
	^ McMarkdownLink
		kind: #autolink
		start: anIndex
		stop: close
		labelStart: anIndex + 1
		labelStop: close - 1
		target: target
		label: target
		caption: ''!

bareUrlAt: anIndex
	| stop char target |
	(anIndex > 1 and: [ (source at: anIndex - 1) isAlphaNumeric ]) ifTrue: [ ^ nil ].
	stop := anIndex.
	[ stop <= source size ] whileTrue: [
		char := source at: stop.
		(char isSeparator or: [ '<>[\]"''' includes: char ]) ifTrue: [
			stop := stop - 1.
			^ self bareUrlFrom: anIndex to: stop ].
		stop := stop + 1 ].
	^ self bareUrlFrom: anIndex to: source size!

bareUrlFrom: startIndex to: stopIndex
	| stop target |
	stop := stopIndex.
	[ stop >= startIndex and: [ '.,;:!!?' includes: (source at: stop) ] ]
		whileTrue: [ stop := stop - 1 ].
	stop < startIndex ifTrue: [ ^ nil ].
	target := source copyFrom: startIndex to: stop.
	^ McMarkdownLink
		kind: #bare
		start: startIndex
		stop: stop
		labelStart: startIndex
		labelStop: stop
		target: target
		label: target
		caption: ''! !

!McMarkdownLinkScanner methodsFor: 'private - delimiters'!
beginsWith: aToken at: anIndex
	| last |
	last := anIndex + aToken size - 1.
	last > source size ifTrue: [ ^ false ].
	1 to: aToken size do: [ :offset |
		(source at: anIndex + offset - 1) = (aToken at: offset)
			ifFalse: [ ^ false ] ].
	^ true!

closingDoubleBracketFrom: anIndex
	| index |
	index := anIndex.
	[ index < source size ] whileTrue: [
		((source at: index) = $] and: [ (source at: index + 1) = $] ])
			ifTrue: [ ^ index ].
		index := index + 1 ].
	^ nil!

closingBracketFrom: anIndex
	| index depth char |
	index := anIndex.
	depth := 1.
	[ index <= source size ] whileTrue: [
		char := source at: index.
		char = $\ ifTrue: [ index := index + 2 ] ifFalse: [
			char = $[ ifTrue: [ depth := depth + 1 ].
			char = $] ifTrue: [
				depth := depth - 1.
				depth = 0 ifTrue: [ ^ index ] ].
			index := index + 1 ] ].
	^ nil!

closingParenthesisFrom: anIndex
	| index depth char |
	index := anIndex.
	depth := 1.
	[ index <= source size ] whileTrue: [
		char := source at: index.
		char = $\ ifTrue: [ index := index + 2 ] ifFalse: [
			char = $( ifTrue: [ depth := depth + 1 ].
			char = $) ifTrue: [
				depth := depth - 1.
				depth = 0 ifTrue: [ ^ index ] ].
			index := index + 1 ] ].
	^ nil!

firstUnescaped: aCharacter from: startIndex to: stopIndex
	| index |
	index := startIndex.
	[ index <= stopIndex ] whileTrue: [
		(source at: index) = $\
			ifTrue: [ index := index + 2 ]
			ifFalse: [
				(source at: index) = aCharacter ifTrue: [ ^ index ].
				index := index + 1 ] ].
	^ nil! !

!McMarkdownLinkScanner methodsFor: 'private - destination'!
destinationAndTitleFrom: startIndex to: stopIndex
	| raw target title split closeAngle |
	stopIndex < startIndex ifTrue: [ ^ { ''. '' } ].
	raw := (source copyFrom: startIndex to: stopIndex) trimBoth.
	raw isEmpty ifTrue: [ ^ { ''. '' } ].
	(raw first = $<) ifTrue: [
		closeAngle := raw indexOf: $> startingAt: 2.
		closeAngle > 0 ifTrue: [
			target := raw copyFrom: 2 to: closeAngle - 1.
			title := (raw copyFrom: closeAngle + 1 to: raw size) trimBoth.
			^ { target. self unquote: title } ] ].
	split := raw findFirst: [ :each | each isSeparator ].
	split = 0
		ifTrue: [ target := raw. title := '' ]
		ifFalse: [
			target := raw copyFrom: 1 to: split - 1.
			title := (raw copyFrom: split + 1 to: raw size) trimBoth ].
	^ { target. self unquote: title }!

unquote: aString
	| first last |
	aString size < 2 ifTrue: [ ^ aString ].
	first := aString first.
	last := aString last.
	((first = $" and: [ last = $" ])
		or: [ first = $' and: [ last = $' ] ])
		ifTrue: [ ^ aString copyFrom: 2 to: aString size - 1 ].
	^ aString! !
