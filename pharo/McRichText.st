"
malleable-control -- swapping markdown blocks for live components, and back.

A demonstration, not part of the bus. It answers one question: can a chat
message's text be parsed, have its blocks replaced by interactive components,
and still be the same text underneath?

It can, and the reason is structural. In Bloc, a component is not a
replacement for text -- it is an *attribute over* text. The string is never
consumed. So the forward direction is a styler, and the backward direction is
free: the source is still there, byte for byte, under whatever is drawn on top
of it. Nothing has to be converted back.

That also makes the component set swappable. A styler is a one-argument block
over the text (BlPluggableStyler), and a view takes one with `styler:'. Two
styler objects over the same string give two renderings of the same document.

The chat's own styler parses with LeParser, which has no productions for
tables or lists. This one uses MicrodownParser, which has both, plus quotes,
strikethrough and math.
"!

Object subclass: #McRichText
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McRichText class methodsFor: 'sample'!
sample
	"A document exercising the blocks the chat cannot currently render."
	^ String streamContents: [ :s |
		s nextPutAll: '# Release checklist'; lf; lf;
			nextPutAll: 'The same **string** underneath, whichever set is used.'; lf; lf;
			nextPutAll: '| block | rendered today as | rendered here as |'; lf;
			nextPutAll: '| --- | --- | --- |'; lf;
			nextPutAll: '| table | literal pipes | a grid |'; lf;
			nextPutAll: '| list | literal dashes | checkboxes |'; lf; lf;
			nextPutAll: '- a list item becomes a checkbox'; lf;
			nextPutAll: '- and stays a list item in the source'; lf;
			nextPutAll: '- tick one: the text is unchanged'; lf; lf;
			nextPutAll: '```smalltalk'; lf;
			nextPutAll: 'McLlm status'; lf;
			nextPutAll: '```'; lf ]! !

!McRichText class methodsFor: 'splitting'!
lineIntervalsOf: aString
	"start -> stop of every line, stop < start for an empty one."
	| result start index |
	result := OrderedCollection new.
	start := 1.
	index := 1.
	[ index <= aString size ] whileTrue: [
		(aString at: index) = Character lf
			ifTrue: [ result add: start -> (index - 1). start := index + 1 ].
		index := index + 1 ].
	start <= aString size ifTrue: [ result add: start -> aString size ].
	^ result asArray! !

!McRichText class methodsFor: 'splitting'!
lineAt: anInterval in: aString
	^ anInterval value < anInterval key
		ifTrue: [ '' ]
		ifFalse: [ (aString copyFrom: anInterval key to: anInterval value) trimRight ]! !

!McRichText class methodsFor: 'splitting'!
blocksIn: aString
	"Source intervals of the top-level blocks, in order.

	 Microdown's AST carries no source positions, so they are recovered here by
	 the rule the parser itself uses: a block runs to the next blank line,
	 except a fenced block, which runs to its closing fence. Intervals are what
	 makes this reversible -- every component knows exactly which characters it
	 stands for."
	| lines groups current inFence |
	lines := self lineIntervalsOf: aString.
	groups := OrderedCollection new.
	current := nil.
	inFence := false.
	lines do: [ :each |
		| line |
		line := self lineAt: each in: aString.
		(line beginsWith: '```')
			ifTrue: [
				inFence
					ifTrue: [
						groups add: current key -> each value.
						current := nil.
						inFence := false ]
					ifFalse: [
						current ifNotNil: [ groups add: current ].
						current := each key -> each value.
						inFence := true ] ]
			ifFalse: [
				inFence
					ifTrue: [ current := current key -> each value ]
					ifFalse: [
						line isEmpty
							ifTrue: [ current ifNotNil: [ groups add: current. current := nil ] ]
							ifFalse: [
								current
									ifNil: [ current := each key -> each value ]
									ifNotNil: [ current := current key -> each value ] ] ] ] ].
	current ifNotNil: [ groups add: current ].
	^ groups asArray! !

!McRichText class methodsFor: 'splitting'!
kindOf: aSource
	"Which component a block wants. Cheap on purpose -- the full AST is only
	 built for the blocks a component actually renders."
	| first |
	first := aSource lines
			ifEmpty: [ '' ]
			ifNotEmpty: [ :all | all first trimBoth ].
	(first beginsWith: '```') ifTrue: [ ^ #code ].
	(first beginsWith: '|') ifTrue: [ ^ #table ].
	((first beginsWith: '- ') or: [ first beginsWith: '* ' ]) ifTrue: [ ^ #list ].
	(first beginsWith: '#') ifTrue: [ ^ #header ].
	^ #paragraph! !

!McRichText class methodsFor: 'parsing'!
astFor: aSource
	"The Microdown node for one block. Not used to find the block -- used to
	 read it once found."
	^ [ (MicrodownParser new parse: aSource) children
			ifEmpty: [ nil ]
			ifNotEmpty: [ :all | all first ] ]
		on: Error do: [ :e | nil ]! !

!McRichText class methodsFor: 'components'!
tableElementFor: aSource
	"A markdown table as a grid of cells."
	| container rows |
	container := BrVerticalPane new
			hMatchParent; vFitContent;
			cellSpacing: 2;
			padding: (BlInsets all: 6);
			background: (Color gray alpha: 0.06);
			yourself.
	rows := aSource lines
			select: [ :line | (line trimBoth beginsWith: '|')
					and: [ (line select: [ :c | c isAlphaNumeric ]) notEmpty ] ].
	rows doWithIndex: [ :line :rowIndex |
		| row |
		row := BrHorizontalPane new hMatchParent; vFitContent; cellSpacing: 8; yourself.
		((line trimBoth) substrings: '|') do: [ :cell |
			row addChild: ((BrLabel new
					aptitude: (BrGlamorousLabelAptitude new
							foreground: (rowIndex = 1
									ifTrue: [ BrGlamorousColors defaultButtonTextColor ]
									ifFalse: [ Color gray darker ]));
					text: cell trimBoth;
					hExact: 150;
					yourself)) ].
		container addChild: row ].
	^ container! !

!McRichText class methodsFor: 'components'!
listElementFor: aSource
	"A markdown list as checkboxes -- an interactive component standing in for
	 text, which is the whole point of the exercise."
	| container |
	container := BrVerticalPane new
			hMatchParent; vFitContent;
			cellSpacing: 4;
			padding: (BlInsets all: 6);
			yourself.
	(aSource lines select: [ :line |
			(line trimBoth beginsWith: '- ') or: [ line trimBoth beginsWith: '* ' ] ])
		do: [ :line |
			| row |
			row := BrHorizontalPane new
					hMatchParent; vFitContent;
					alignCenterLeft;
					cellSpacing: 8;
					yourself.
			row addChild: (BrCheckbox new
					aptitude: BrGlamorousCheckboxAptitude new;
					beSmallSize;
					checked: false;
					yourself).
			row addChild: (BrLabel new
					aptitude: BrGlamorousLabelAptitude new;
					text: (line trimBoth allButFirst: 2);
					yourself).
			container addChild: row ].
	^ container! !

!McRichText class methodsFor: 'components'!
codeElementFor: aSource
	"A fenced block. Smalltalk becomes a live coder -- the same thing the chat
	 already does -- and anything else becomes a monospace editor labelled with
	 its language, which is what the chat does not do."
	| lines language body |
	lines := aSource lines.
	language := lines isEmpty
			ifTrue: [ '' ]
			ifFalse: [ (lines first trimBoth allButFirst: 3) trimBoth ].
	body := String streamContents: [ :s |
			2 to: (lines size - 1) do: [ :index |
				s nextPutAll: (lines at: index); lf ] ].
	(language isEmpty or: [ language = 'smalltalk' or: [ language = 'pharo' ] ])
		ifTrue: [ ^ [ GtPharoSnippetCoder new
					forSource: body trimBoth;
					subscribeToSystem;
					asExpandedOnlyElement ]
				on: Error do: [ :e | self monospaceElementFor: body language: language ] ].
	^ self monospaceElementFor: body language: language! !

!McRichText class methodsFor: 'components'!
monospaceElementFor: aBody language: aLanguage
	| container |
	container := BrVerticalPane new
			hMatchParent; vFitContent;
			cellSpacing: 2;
			padding: (BlInsets all: 6);
			background: (Color gray alpha: 0.06);
			yourself.
	aLanguage isEmpty ifFalse: [
		container addChild: (BrLabel new
				aptitude: (BrGlamorousLabelAptitude new foreground: Color gray);
				text: aLanguage;
				yourself) ].
	container addChild: (BrEditor new
			aptitude: BrGlamorousCodeEditorAptitude new;
			text: aBody trimBoth;
			hMatchParent; vFitContent;
			yourself).
	^ container! !

!McRichText class methodsFor: 'component sets'!
componentSetNames
	^ #(#asChat #asComponents)! !

!McRichText class methodsFor: 'component sets'!
componentSetNamed: aSymbol
	"A component set is a map from block kind to a block answering an element,
	 or nothing, in which case the block stays as styled text.

	 #asChat is what the chat renders today: live code for Smalltalk fences,
	 plain text for everything else. #asComponents renders tables and lists as
	 elements too. Same document, same string, two sets."
	aSymbol = #asChat ifTrue: [
		^ Dictionary newFrom: {
			#code -> [ :source | self codeElementFor: source ] } ].
	^ Dictionary newFrom: {
		#code -> [ :source | self codeElementFor: source ].
		#table -> [ :source | self tableElementFor: source ].
		#list -> [ :source | self listElementFor: source ] }! !

!McRichText class methodsFor: 'styling'!
stylerFor: aSetName
	"A styler is a block over the text. Swapping the component set is swapping
	 this object -- nothing else in a view has to change."
	^ BlPluggableStyler new
		block: [ :aText | self style: aText with: aSetName ];
		yourself! !

!McRichText class methodsFor: 'styling'!
style: aText with: aSetName
	"Replace each block that has a component with that component.

	 The block's characters are hidden rather than removed, and the element is
	 hung off the last one. That is why this is reversible: aText asString is
	 the document it started as, whatever is drawn over it."
	| source set |
	source := aText asString.
	set := self componentSetNamed: aSetName.
	(self blocksIn: source) do: [ :interval |
		| body stencil |
		body := source copyFrom: interval key to: interval value.
		stencil := set at: (self kindOf: body) ifAbsent: [ nil ].
		stencil ifNotNil: [
			(aText from: interval key to: interval value)
				attributes: { BrTextHideAttribute new }.
			(aText from: interval value to: interval value)
				attributes: { BrTextAdornmentDynamicAttribute new
						beAppend;
						stencil: [ stencil value: body ] } ] ].
	^ aText! !

!McRichText class methodsFor: 'opening'!
editorFor: aSetName on: aString
	^ BrEditor new
		aptitude: BrGlamorousRegularEditorAptitude new;
		styler: (self stylerFor: aSetName);
		text: aString asRopedText;
		hMatchParent; vMatchParent;
		padding: (BlInsets all: 12);
		yourself! !

!McRichText class methodsFor: 'opening'!
captionFor: aSetName
	^ aSetName = #asChat
		ifTrue: [ 'what the chat does today: only a Smalltalk fence becomes a component. The table and the list stay as the characters the model wrote.' ]
		ifFalse: [ 'the table is a grid, the list is real checkboxes, the fence is a live coder. Same string, different component set.' ]! !

!McRichText class methodsFor: 'opening'!
titleLabel: aString foreground: aColor
	^ BrLabel new
		aptitude: (BrGlamorousLabelAptitude new foreground: aColor);
		text: aString;
		hMatchParent;
		yourself! !

!McRichText class methodsFor: 'opening'!
columnFor: aSetName
	| column |
	column := BrVerticalPane new
			matchParent;
			cellSpacing: 6;
			yourself.
	column addChild: (self titleLabel: aSetName asString foreground: Color black).
	column addChild: (self titleLabel: (self captionFor: aSetName) foreground: Color gray).
	column addChild: (self editorFor: aSetName on: self sample).
	^ column! !

!McRichText class methodsFor: 'opening'!
open
	"Two renderings of one document, side by side.

	 Left is what the chat renders today. Right is the same string with a
	 different component set. Nothing about the document differs between them --
	 only the styler passed to the editor."
	| space page row |
	page := BrVerticalPane new
			matchParent;
			cellSpacing: 10;
			padding: (BlInsets all: 14);
			yourself.
	page addChild: (self
			titleLabel: 'One document, two component sets. Same characters underneath both.'
			foreground: Color black).
	page addChild: (self
			titleLabel: 'Each column is a text editor over the identical string. They differ only in the styler given to it.'
			foreground: Color gray).
	row := BrHorizontalPane new
			matchParent;
			cellSpacing: 20;
			yourself.
	self componentSetNames do: [ :each | row addChild: (self columnFor: each) ].
	page addChild: row.
	space := BlSpace new.
	space title: 'McRichText'.
	space extent: 1200 @ 760.
	space root addChild: page.
	space show.
	^ 'opened -- ' , self componentSetNames printString! !

!McRichText class methodsFor: 'opening'!
close
	"Close the demo window, if it is open."
	^ ((Smalltalk at: #McGtPatches) openSpaces
		select: [ :each | [ each title asString = 'McRichText' ] on: Error do: [ :e | false ] ])
		inject: 0
		into: [ :count :space | [ space close. count + 1 ] on: Error do: [ :e | count ] ]! !

!McRichText class methodsFor: 'proving'!
proveRoundTrip
	"What the demonstration claims, checked rather than asserted.

	 Run it with: bin/gt-eval '(Smalltalk at: #McRichText) proveRoundTrip'"
	| source report |
	source := self sample.
	report := OrderedCollection new.
	report add: 'source: ' , source size printString , ' characters, '
			, (self blocksIn: source) size printString , ' blocks'.
	(self blocksIn: source) do: [ :interval |
		| body |
		body := source copyFrom: interval key to: interval value.
		report add: '  chars ' , interval key printString , '-' , interval value printString
				, '  ' , (self kindOf: body) asString
				, ' -> ' , ((self astFor: body)
						ifNil: [ 'unparsed' ]
						ifNotNil: [ :node | node class name asString ]) ].
	self componentSetNames do: [ :setName |
		| text seen built covered |
		text := source asRopedText.
		self style: text with: setName.
		seen := IdentitySet new.
		built := OrderedCollection new.
		covered := 0.
		1 to: text size do: [ :index |
			(text attributesAt: index) do: [ :attribute |
				(attribute isKindOf: BrTextHideAttribute) ifTrue: [ covered := covered + 1 ].
				((attribute respondsTo: #stencil) and: [ (seen includes: attribute) not ])
					ifTrue: [
						seen add: attribute.
						built add: ([ attribute stencil asElement class name asString ]
								on: Error do: [ :e | 'FAILED ' , e messageText asString ]) ] ] ].
		report add: ''.
		report add: setName asString , ':'.
		report add: '  components built: ' , built asArray printString.
		report add: '  source characters replaced by a component: ' , covered printString
				, ' of ' , source size printString.
		report add: '  text asString still equals the source: '
				, (text asString = source) printString ].
	^ String streamContents: [ :s |
		report do: [ :line | s nextPutAll: line; lf ] ]! !
