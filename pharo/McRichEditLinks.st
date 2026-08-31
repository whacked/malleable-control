"
McRichEditLinks -- target resolution and actions for projected links/images.

McMarkdownInlineStyler discovers syntax and installs UI attributes, but it
does no filesystem or network work.  This owner-side extension supplies that
boundary: classify a target, resolve local candidates relative to the current
document and project, open web URLs on explicit clicks, switch local documents,
and build image elements.

Remote targets are not probed while styling.  Doing so would make a restyle
perform network I/O, disclose every URL merely by opening a document, and make
an unavailable site freeze or churn the editor.  They are shown as external
and unverified.  Missing or malformed local targets are shown as dead.

Chunk format: load with fileIn.
"!

!McRichEdit methodsFor: 'links - classification'!
linkStateFor: aLink
	(self webUrlForTarget: aLink target) ifNotNil: [ ^ #web ].
	(self looksLikeWebTarget: aLink target) ifTrue: [ ^ #dead ].
	(self resolvedFileForLink: aLink) ifNotNil: [ ^ #local ].
	^ #dead!

looksLikeWebTarget: aString
	| lower |
	lower := aString trimBoth asLowercase.
	^ (lower beginsWith: 'http://') or: [ lower beginsWith: 'https://' ]!

webUrlForTarget: aString
	(self looksLikeWebTarget: aString) ifFalse: [ ^ nil ].
	^ [ | url |
		url := aString trimBoth asZnUrl.
		((#(http https) includes: url scheme)
			and: [ url host notNil and: [ url host asString notEmpty ] ])
			ifTrue: [ url ]
			ifFalse: [ nil ] ]
		on: Error
		do: [ :e | nil ]! !

!McRichEdit methodsFor: 'links - local resolution'!
resolvedFileForLink: aLink
	| target |
	target := aLink target trimBoth.
	(target asLowercase beginsWith: 'file://') ifTrue: [
		^ [ | ref |
			ref := target asZnUrl asFileReference.
			(ref exists and: [ ref isFile ]) ifTrue: [ ref ] ifFalse: [ nil ] ]
			on: Error
			do: [ :e | nil ] ].
	(self localCandidatesForTarget: target) do: [ :candidate |
		(candidate exists and: [ candidate isFile ]) ifTrue: [ ^ candidate ] ].
	^ nil!

localCandidatesForTarget: aString
	| raw direct base candidates needsMarkdown |
	raw := self localPathPartOf: aString.
	raw isEmpty ifTrue: [ ^ { self documentFile } ].
	raw := raw copyReplaceAll: '%20' with: ' '.
	direct := raw asFileReference.
	direct isAbsolute ifTrue: [ ^ self withMarkdownVariantOf: direct ].
	base := self documentFile parent.
	candidates := OrderedCollection new.
	needsMarkdown := (direct basename includes: $.) not.
	candidates add: base / raw.
	needsMarkdown ifTrue: [ candidates add: base / (raw , '.md') ].
	self projectRoot = base ifFalse: [
		candidates add: self projectRoot / raw.
		needsMarkdown ifTrue: [ candidates add: self projectRoot / (raw , '.md') ] ].
	^ candidates asArray!

withMarkdownVariantOf: aFileReference
	(aFileReference basename includes: $.) ifTrue: [ ^ { aFileReference } ].
	^ { aFileReference. (aFileReference parent / (aFileReference basename , '.md')) }!

localPathPartOf: aString
	| hash query stop |
	hash := aString indexOf: $#.
	query := aString indexOf: $?.
	stop := aString size + 1.
	hash > 0 ifTrue: [ stop := stop min: hash ].
	query > 0 ifTrue: [ stop := stop min: query ].
	stop = 1 ifTrue: [ ^ '' ].
	^ (aString copyFrom: 1 to: stop - 1) trimBoth! !

!McRichEdit methodsFor: 'links - actions'!
activateLink: aLink
	| state file url |
	state := self linkStateFor: aLink.
	state = #web ifTrue: [
		url := self webUrlForTarget: aLink target.
		self showStatus: 'Opening ' , aLink target.
		[ [ WebBrowser openOn: url ]
			on: Error
			do: [ :e | self showStatus: 'Cannot open link: ' , e messageText ] ]
			forkAt: Processor userBackgroundPriority.
		^ self ].
	state = #local ifTrue: [
		file := self resolvedFileForLink: aLink.
		file ifNotNil: [ ^ self openDocument: file ] ].
	self showStatus: 'Dead link: ' , aLink target! !

!McRichEdit methodsFor: 'links - images'!
imageElementFor: aLink
	| state image container caption tooltip file |
	state := self linkStateFor: aLink.
	state = #dead ifTrue: [ ^ self missingImageElementFor: aLink ].
	image := BrAsyncFileWidget new.
	image size: 520 @ 280.
	state = #web
		ifTrue: [ image url: (self webUrlForTarget: aLink target) ]
		ifFalse: [
			file := self resolvedFileForLink: aLink.
			file ifNil: [ ^ self missingImageElementFor: aLink ].
			image file: file ].
	tooltip := BrGlamorousWithExplicitTooltipAptitude new.
	tooltip text: aLink target.
	image addAptitude: tooltip.
	container := BlElement new.
	container layout: BlLinearLayout vertical.
	container constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
	container padding: (BlInsets all: 6).
	container margin: (BlInsets top: 4 bottom: 4).
	container geometry: (BlRoundedRectangleGeometry cornerRadius: 4).
	container background: (self palette at: 'codeBg').
	container border: (BlBorder paint: (self palette at: 'tableBorder') width: 1).
	container addChild: image.
	caption := aLink caption trimBoth.
	caption ifNotEmpty: [
		| label |
		label := BlTextElement new.
		label text: (caption asRopedText
			foreground: (self palette at: 'status');
			fontSize: 12).
		label margin: (BlInsets top: 5).
		container addChild: label ].
	^ container!

missingImageElementFor: aLink
	| box label |
	box := BlElement new.
	box layout: BlLinearLayout vertical.
	box constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ].
	box padding: (BlInsets all: 10).
	box margin: (BlInsets top: 4 bottom: 4).
	box geometry: (BlRoundedRectangleGeometry cornerRadius: 4).
	box background: ((self palette at: 'codeBg') mixed: 0.08 with: Color red).
	box border: (BlBorder paint: ((self palette at: 'deadLink') alpha: 0.65) width: 1).
	label := BlTextElement new.
	label text: (('Missing image: ' , aLink target) asRopedText
		foreground: (self palette at: 'deadLink');
		fontSize: 12).
	box addChild: label.
	^ box! !
