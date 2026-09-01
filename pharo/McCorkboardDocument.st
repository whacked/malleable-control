Object subclass: #McCorkboardDocument
	instanceVariableNames: 'panels'
	classVariableNames: ''
	package: 'MalleableControl'!

!McCorkboardDocument methodsFor: 'initialization'!
initialize
	super initialize. panels := Dictionary new! !

!McCorkboardDocument methodsFor: 'panels'!
addPanel: aPanel
	panels at: aPanel id put: aPanel. ^ aPanel!

panelAt: anId
	^ panels at: anId ifAbsent: [ nil ]!

panels
	^ panels values asArray!

coordinateOf: anId
	| panel |
	panel := self panelAt: anId. panel ifNil: [ ^ nil ]. ^ panel x @ panel y! !
