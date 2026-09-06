"
McCommandKeymap -- a small in-memory command and key-binding registry.

Commands and bindings are separate on purpose: UI code names an action once,
while users or later preference loaders can remap the key combination without
changing the command implementation. Reinstalling a context atomically
replaces the shortcuts previously installed by this registry on that element.
"!

Object subclass: #McCommandKeymap
	instanceVariableNames: 'commands bindings installations'
	classVariableNames: ''
	package: 'MalleableControl'!

!McCommandKeymap class methodsFor: 'instance creation'!
richEditDefaults
	^ self new
		registerCommand: #openSearch action: [ :owner | owner openSearch ];
		registerCommand: #nextSearch action: [ :owner | owner nextSearch ];
		registerCommand: #previousSearch action: [ :owner | owner previousSearch ];
		registerCommand: #cancelSearch action: [ :owner | owner closeSearch ];
		registerCommand: #rerunAtCursor action: [ :owner | owner rerunAtCursor ];
		bind: #openSearch in: #editor to: BlKeyCombination primaryF;
		bind: #rerunAtCursor in: #editor to: (BlKeyCombination builder primary shift key: BlKeyboardKey e; build);
		bind: #nextSearch in: #searchInput to: BlKeyCombination return;
		bind: #previousSearch in: #searchInput to: BlKeyCombination shiftReturn;
		bind: #cancelSearch in: #searchInput to: BlKeyCombination escape;
		yourself! !

!McCommandKeymap methodsFor: 'initialization'!
initialize
	super initialize.
	commands := Dictionary new.
	bindings := Dictionary new.
	installations := IdentityDictionary new! !

!McCommandKeymap methodsFor: 'commands'!
registerCommand: aSymbol action: aBlock
	commands at: aSymbol put: aBlock!

perform: aSymbol for: anOwner
	^ (commands at: aSymbol ifAbsent: [ ^ nil ]) value: anOwner!

commandNames
	^ commands keys asArray! !

!McCommandKeymap methodsFor: 'bindings'!
bind: aCommand in: aContext to: aCombination
	(commands includesKey: aCommand) ifFalse: [
		^ self error: 'Unknown command: ' , aCommand asString ].
	(bindings at: aContext ifAbsentPut: [ Dictionary new ])
		at: aCommand put: aCombination!

unbind: aCommand in: aContext
	(bindings at: aContext ifAbsent: [ ^ self ])
		removeKey: aCommand ifAbsent: [ ]!

bindingFor: aCommand in: aContext
	^ (bindings at: aContext ifAbsent: [ ^ nil ])
		at: aCommand ifAbsent: [ nil ]!

bindingsIn: aContext
	^ (bindings at: aContext ifAbsent: [ Dictionary new ]) copy!

remap: aCommand in: aContext to: aCombination on: anElement owner: anOwner
	self bind: aCommand in: aContext to: aCombination.
	self installContext: aContext on: anElement owner: anOwner! !

!McCommandKeymap methodsFor: 'installation'!
installContext: aContext on: anElement owner: anOwner
	| prior installed contextBindings |
	prior := installations at: anElement ifAbsent: [ #() ].
	prior do: [ :shortcut | anElement removeShortcut: shortcut ].
	installed := OrderedCollection new.
	contextBindings := bindings at: aContext ifAbsent: [ Dictionary new ].
	contextBindings keysAndValuesDo: [ :command :combination |
		| shortcut |
		shortcut := BlShortcutWithAction new
			name: command asString;
			combination: combination;
			overrideChildren: true;
			action: [ :event :ignored |
				self perform: command for: anOwner.
				event consumed: true ];
			yourself.
		anElement addShortcut: shortcut.
		installed add: shortcut ].
	installations at: anElement put: installed asArray! !
