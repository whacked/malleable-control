"
McSearch -- the source-addressed search model behind rich-edit incremental
search: query, matcher protocol, literal matcher, and session.

Search is an ephemeral overlay over the editor's source rope, not a concern of
Microdown parsing or of McMarkdownStylerVisitor.  Nothing in this file knows
about text attributes, adornments or the editor; it answers source ranges and
nothing else, so it can be tested headlessly and so no single matcher
implementation can become the editor's only search model.

  source string -> McSearchMatcher -> ordered source ranges -> McSearchSession

The three objects divide as follows:

  McSearchQuery     what was asked for (text plus case/whole-word options).
                    An empty query matches nothing, by definition and not by
                    accident.
  McSearchMatcher   how it is looked for.  Abstract; the protocol is the single
                    message matchesFor:in:.  McLiteralSearchMatcher is the only
                    implementation that exists today -- see the extension seam
                    documented on the class.
  McSearchSession   which match is current.  It owns recomputation, active
                    retention across query revisions and wraparound navigation.

Ranges are Intervals over one-based source positions, ordered by start and
never overlapping (see McLiteralSearchMatcher for why that policy is a choice
rather than a side effect).

Chunk format: load with fileIn.
"!

Object subclass: #McSearchQuery
	instanceVariableNames: 'text caseSensitive wholeWord'
	classVariableNames: ''
	package: 'MalleableControl'!

"
McSearchQuery -- an immutable search request.

Immutable because a session recomputes on every query revision and must be able
to compare the revision it answered against the one it was handed; a query that
could be mutated underneath the session makes that comparison meaningless.
Options are added by copying (withText:, withCaseSensitive:, withWholeWord:).
"!

!McSearchQuery class methodsFor: 'instance creation'!
empty
	^ self text: ''!

text: aString
	^ self text: aString caseSensitive: false wholeWord: false!

text: aString caseSensitive: aBoolean wholeWord: anotherBoolean
	^ self new setText: aString caseSensitive: aBoolean wholeWord: anotherBoolean! !

!McSearchQuery methodsFor: 'initialization'!
setText: aString caseSensitive: aBoolean wholeWord: anotherBoolean
	text := aString ifNil: [ '' ].
	caseSensitive := aBoolean = true.
	wholeWord := anotherBoolean = true! !

!McSearchQuery methodsFor: 'accessing'!
text
	^ text!

isCaseSensitive
	^ caseSensitive!

isWholeWord
	^ wholeWord!

isEmpty
	"An empty query is not a query for everything.  Matchers answer no ranges
	 for it, so clearing the field clears the overlay without a separate cancel."
	^ text isEmpty!

isNotEmpty
	^ self isEmpty not! !

!McSearchQuery methodsFor: 'copying'!
withText: aString
	^ self class text: aString caseSensitive: caseSensitive wholeWord: wholeWord!

withCaseSensitive: aBoolean
	^ self class text: text caseSensitive: aBoolean wholeWord: wholeWord!

withWholeWord: aBoolean
	^ self class text: text caseSensitive: caseSensitive wholeWord: aBoolean! !

!McSearchQuery methodsFor: 'comparing'!
= anObject
	^ self class = anObject class
		and: [ text = anObject text
			and: [ caseSensitive = anObject isCaseSensitive
				and: [ wholeWord = anObject isWholeWord ] ] ]!

hash
	^ (text hash bitXor: caseSensitive hash) bitXor: wholeWord hash! !

!McSearchQuery methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: self class name asString; nextPut: $(.
	text printOn: aStream.
	caseSensitive ifTrue: [ aStream nextPutAll: ' case' ].
	wholeWord ifTrue: [ aStream nextPutAll: ' word' ].
	aStream nextPut: $)! !

Object subclass: #McSearchMatcher
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

"
McSearchMatcher -- the matching protocol, and only that.

Subclasses implement one message:

  matchesFor: aQuery in: aString
      Answer an Array of Intervals over one-based positions in aString,
      ordered by start.  Answer an empty Array for an empty query.  Do no I/O,
      mutate nothing, and answer the same ranges for the same arguments.

## Extension seam

The editor is written against this protocol and against McSearchSession, never
against McLiteralSearchMatcher, so an added matcher needs no editor change: file
in a subclass, implement matchesFor:in:, and hand an instance to the session.

Three subclasses are anticipated by the plan and *none of them exist yet*.
There are deliberately no stub classes for them: a stub that answers no matches
is indistinguishable, from the editor, from a query that found nothing, and
that is the failure mode this comment exists to prevent.  What a future author
needs to know:

  McRegexSearchMatcher       aQuery text read as a regular expression.  It must
                             decide what an invalid pattern does -- the session
                             has no error channel, so the choice is between
                             answering no ranges and signalling; make it
                             explicit rather than letting the regex engine's
                             exception escape into a keystroke handler.
  McGlobSearchMatcher        aQuery text read as a glob.  Note that a glob is
                             ordinarily anchored to a whole name while search
                             is unanchored; that mapping is a decision, not a
                             detail.
  McMultiStringSearchMatcher several needles at once.  It inherits the
                             non-overlap question across *different* needles,
                             which the literal matcher never faces.

implementedMatchers answers the subclasses that actually implement the
protocol, so a chooser cannot offer a matcher that does not match.
"!

McSearchMatcher subclass: #McLiteralSearchMatcher
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

"
McLiteralSearchMatcher -- plain substring search, the default matcher.

Two policies worth stating because both are choices:

  Non-overlapping.  Searching 'aa' in 'aaa' answers one range, 1 to 2, not two
  overlapping ones.  Scanning resumes after the end of an accepted match.  The
  overlay could not draw an active match distinctly if two matches shared
  characters, and next/previous over overlapping ranges cannot wrap
  deterministically.

  Whole-word rejection resumes at start + 1, not at the end of the rejected
  candidate.  Resuming at the end would lose the match in 'cats cat': the
  candidate at 1 is rejected, and the real match starts inside it.

Case insensitivity folds both sides with asLowercase, which is one-to-one on
Character and so leaves every position aligned with the original source; the
answered ranges therefore address aString, not the folded copy.

One left-to-right pass per query revision, resuming after each accepted match,
so the work is proportional to the source rather than to the number of matches
found in it.
"!

!McSearchMatcher class methodsFor: 'instance creation'!
default
	"Literal search is the default the editor gets when nobody chose."
	^ McLiteralSearchMatcher new! !

!McSearchMatcher class methodsFor: 'accessing'!
implementedMatchers
	"The subclasses that implement the protocol -- asked, not hardcoded, so a
	 matcher added later is offered without editing this method, and a subclass
	 that has not implemented matchesFor:in: yet is never offered at all."
	^ (self allSubclasses select: [ :each | each includesSelector: #matchesFor:in: ]) asArray! !

!McSearchMatcher methodsFor: 'matching'!
matchesFor: aQuery in: aString
	"Answer ordered, non-overlapping Intervals over aString.  See the class
	 comment for the contract this must satisfy."
	^ self subclassResponsibility! !

!McSearchMatcher methodsFor: 'accessing'!
label
	"Shown wherever a matcher is named in the UI."
	^ self class name asString! !

!McSearchMatcher methodsFor: 'private'!
isWordCharacter: aCharacter
	^ aCharacter isAlphaNumeric or: [ aCharacter = $_ ]!

in: aString isWholeWordFrom: start to: stop
	"A match is a whole word when neither neighbouring character is a word
	 character.  Document edges count as boundaries."
	(start > 1 and: [ self isWordCharacter: (aString at: start - 1) ])
		ifTrue: [ ^ false ].
	(stop < aString size and: [ self isWordCharacter: (aString at: stop + 1) ])
		ifTrue: [ ^ false ].
	^ true! !

!McLiteralSearchMatcher methodsFor: 'matching'!
matchesFor: aQuery in: aString
	| needle haystack matches index limit width |
	(aQuery isNil or: [ aQuery isEmpty ]) ifTrue: [ ^ #() ].
	(aString isNil or: [ aString isEmpty ]) ifTrue: [ ^ #() ].
	needle := aQuery isCaseSensitive
		ifTrue: [ aQuery text ]
		ifFalse: [ aQuery text asLowercase ].
	haystack := aQuery isCaseSensitive
		ifTrue: [ aString ]
		ifFalse: [ aString asLowercase ].
	width := needle size.
	matches := OrderedCollection new.
	index := 1.
	limit := haystack size - width + 1.
	[ index <= limit ] whileTrue: [
		| found stop |
		found := haystack indexOfSubCollection: needle startingAt: index.
		found = 0 ifTrue: [ ^ matches asArray ].
		stop := found + width - 1.
		(aQuery isWholeWord not
			or: [ self in: aString isWholeWordFrom: found to: stop ])
			ifTrue: [
				matches add: (found to: stop).
				index := stop + 1 ]
			ifFalse: [ index := found + 1 ] ].
	^ matches asArray! !

Object subclass: #McSearchSession
	instanceVariableNames: 'source query matcher matches activeIndex direction'
	classVariableNames: ''
	package: 'MalleableControl'!

"
McSearchSession -- query, matcher, match ranges, active index and direction.

The session is the whole of the search state the editor keeps.  It recomputes
whenever the query, the matcher or the source changes, and holds two rules:

  Active retention.  A recomputation keeps the active result when that exact
  range survives, and otherwise falls back to the first result.  Typing one more
  character usually shortens the match list, and a caret that jumped to the top
  of the document on every keystroke would make incremental search unusable.

  Wraparound.  next and previous cycle, and answer the newly active range, so
  repeated navigation is deterministic in both directions.

The session never touches the document.  Highlighting and scrolling belong to
the presentation and navigator layers; asking a session for its active range
has no effect on text, undo stack or caret.
"!

!McSearchSession class methodsFor: 'instance creation'!
on: aString
	^ self on: aString matcher: McSearchMatcher default!

on: aString matcher: aMatcher
	^ self source: aString query: McSearchQuery empty matcher: aMatcher!

source: aString query: aQuery matcher: aMatcher
	^ self new setSource: aString query: aQuery matcher: aMatcher! !

!McSearchSession methodsFor: 'initialization'!
setSource: aString query: aQuery matcher: aMatcher
	source := aString ifNil: [ '' ].
	query := aQuery ifNil: [ McSearchQuery empty ].
	matcher := aMatcher ifNil: [ McSearchMatcher default ].
	direction := #forward.
	matches := #().
	activeIndex := 0.
	self recompute! !

!McSearchSession methodsFor: 'accessing'!
source
	^ source!

query
	^ query!

matcher
	^ matcher!

matches
	^ matches!

matchCount
	^ matches size!

hasMatches
	^ matches isEmpty not!

activeIndex
	"Zero when there is no active match."
	^ activeIndex!

activeMatch
	^ (activeIndex between: 1 and: matches size)
		ifTrue: [ matches at: activeIndex ]
		ifFalse: [ nil ]!

direction
	"The direction of the last navigation, #forward or #backward."
	^ direction! !

!McSearchSession methodsFor: 'updating'!
query: aQuery
	query := aQuery ifNil: [ McSearchQuery empty ].
	self recompute!

queryText: aString
	"Revise the text and keep the options the user already chose."
	self query: (query withText: aString)!

matcher: aMatcher
	matcher := aMatcher ifNil: [ McSearchMatcher default ].
	self recompute!

source: aString
	"Called after a document edit.  Retention applies here too: an edit far from
	 the active match must not move it."
	source := aString ifNil: [ '' ].
	self recompute!

clear
	"Cancel search without discarding the session.  Answers no matches because
	 an empty query matches nothing."
	self query: McSearchQuery empty! !

!McSearchSession methodsFor: 'private'!
recompute
	| previous found |
	previous := self activeMatch.
	matches := (matcher matchesFor: query in: source) asArray.
	matches isEmpty ifTrue: [ ^ activeIndex := 0 ].
	found := previous
		ifNil: [ 0 ]
		ifNotNil: [ matches indexOf: previous ].
	activeIndex := found = 0 ifTrue: [ 1 ] ifFalse: [ found ]! !

!McSearchSession methodsFor: 'navigating'!
next
	"Advance one match, wrapping past the last.  Answers the active range."
	direction := #forward.
	matches isEmpty ifTrue: [ ^ nil ].
	activeIndex := activeIndex \\ matches size + 1.
	^ self activeMatch!

previous
	"Step back one match, wrapping past the first.  Answers the active range."
	direction := #backward.
	matches isEmpty ifTrue: [ ^ nil ].
	activeIndex := activeIndex <= 1
		ifTrue: [ matches size ]
		ifFalse: [ activeIndex - 1 ].
	^ self activeMatch!

activateIndex: anInteger
	"Make the anInteger'th match active.  Out-of-range indices are ignored
	 rather than clamped, so a stale index cannot silently activate a
	 neighbour."
	(anInteger between: 1 and: matches size) ifFalse: [ ^ self activeMatch ].
	activeIndex := anInteger.
	^ self activeMatch! !

!McSearchSession methodsFor: 'printing'!
printOn: aStream
	aStream
		nextPutAll: self class name asString;
		nextPut: $(;
		print: query;
		nextPutAll: ' ';
		print: activeIndex;
		nextPut: $/;
		print: matches size;
		nextPut: $)! !

Object subclass: #McSearchPresentation
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!

!McSearchPresentation class methodsFor: 'applying'!
applyTo: aText session: aSession palette: aPalette
	"Search is emitted after markdown styling.  Underlay attributes are
	 deliberately ordinary styler attributes: the next style pass replaces this
	 overlay instead of allowing stale matches to survive a document edit."
	aSession ifNil: [ ^ aText ].
	aSession matches do: [ :range |
		| color |
		color := range = aSession activeMatch
			ifTrue: [ aPalette at: 'searchActiveMatch' ifAbsent: [ Color yellow ] ]
			ifFalse: [ aPalette at: 'searchMatch' ifAbsent: [ Color yellow alpha: 0.35 ] ].
		aText attribute: (BlTextUnderlayAttribute paint: color)
			from: (range first max: 1) to: (range last min: aText size) ].
	^ aText! !
