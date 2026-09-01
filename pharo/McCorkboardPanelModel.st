Object subclass: #McCorkboardPanelModel
	instanceVariableNames: 'id x y draftX draftY text'
	classVariableNames: ''
	package: 'MalleableControl'!

!McCorkboardPanelModel class methodsFor: 'instance creation'!
id: anId x: anX y: anY text: aString
	^ self new id: anId; x: anX y: anY; text: aString; yourself! !

!McCorkboardPanelModel methodsFor: 'accessing'!
id
	^ id!

id: anId
	id := anId!

x
	^ x!

y
	^ y!

text
	^ text!

text: aString
	text := aString!

draftX
	^ draftX!

draftY
	^ draftY!

x: anX y: anY
	x := anX asInteger. y := anY asInteger.
	draftX := x printString. draftY := y printString!

draftX: aString draftY: anotherString
	draftX := aString asString. draftY := anotherString asString!

commitDraft
	| parsedX parsedY |
	parsedX := self coordinateFrom: draftX. parsedY := self coordinateFrom: draftY.
	(parsedX isNil or: [ parsedY isNil ]) ifTrue: [ ^ false ].
	self x: parsedX y: parsedY. ^ true!

discardDraft
	draftX := x printString. draftY := y printString!

moveToX: anX y: anY
	self x: anX y: anY!

isDirty
	^ draftX ~= x printString or: [ draftY ~= y printString ]!

coordinateFrom: aString
	| trimmed |
	trimmed := aString trimBoth.
	trimmed isEmpty ifTrue: [ ^ nil ].
	^ [ trimmed asInteger ] on: Error do: [ :error | nil ]! !
