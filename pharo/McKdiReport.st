"
McKdiReport -- the last step of the chain, in the explorer rather than a terminal.

    revision -> passage -> context block -> selection -> prompt packet -> REPORT

`kdi report build --slice NAME' composes five cached layers -- materialize the
slice, build the packet, interpret it, draft it, render it -- and reports what
each one did.  A dry run resolves all five and calls nothing, which is the only
honest way to look at a build before paying for it.

Three facts this file keeps visible.  A build says how many model calls it made
and which stage made them.  A blocked stage names the command that would unblock
it, and that is a result rather than an error.  And `report verify' re-renders
the report and, with --authoritative, re-decodes every cited source revision --
so the citations in a drafted report resolve back to the same passages the rest
of this explorer walks.

Chunk format: load with fileIn.
"!

McKdiObject subclass: #McKdiReportBuild
	instanceVariableNames: 'store recipe content contentAnswer verification verifyAnswer'
	classVariableNames: ''
	package: 'MalleableControl'!

McKdiObject subclass: #McKdiReportStage
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'MalleableControl'!


!McKdiReportBuild class methodsFor: 'instance creation'!
recipe: aRecipe dryRun: aBoolean
	"kdi report build --slice NAME.  With --dry-run it writes nothing, calls no
	 model and resolves no embedding; without it, the draft stage calls the
	 backend the tier gate routes the PACKET's tier to."
	^ self recipe: aRecipe dryRun: aBoolean forceDraft: false!

recipe: aRecipe dryRun: aBoolean forceDraft: forceDraft
	"--force-draft is the remedy a blocked interpretation names for itself: draft
	 over a candidate the interpretation rejected."
	| argv a |
	argv := OrderedCollection new.
	argv add: 'report'; add: 'build'; add: '--slice'; add: aRecipe name.
	aBoolean ifTrue: [ argv add: '--dry-run' ].
	forceDraft ifTrue: [ argv add: '--force-draft' ].
	argv addAll: aRecipe reportArguments.
	a := aRecipe binding runJson: argv asArray.
	a hasValue ifFalse: [ ^ a ].
	^ (self json: a value answer: a) setRecipe: aRecipe! !


!McKdiReportBuild methodsFor: 'initialization'!
setRecipe: aRecipe
	recipe := aRecipe.
	store := aRecipe store.
	^ self! !


!McKdiReportBuild methodsFor: 'accessing'!
store
	^ store!

binding
	^ store binding!

isDryRun
	^ (self at: 'dry_run') = true!

produced
	^ (self at: 'produced') = true!

reportId
	^ self at: 'report_id'!

sliceId
	^ self at: 'slice_id'!

sliceName
	^ self at: 'slice_name'!

packetId
	^ self at: 'packet_id'!

inferenceId
	^ self at: 'inference_id'!

path
	^ self at: 'path'!

modelCalls
	^ (self at: 'model_calls') ifNil: [ 0 ]!

blockedStage
	^ self at: 'blocked_stage'!

reason
	^ (self at: 'reason') ifNil: [ '' ]!

remedy
	^ (self at: 'remedy') ifNil: [ '' ]!

stages
	^ ((self at: 'stages') ifNil: [ #() ])
		collect: [ :each | McKdiReportStage json: each answer: answer ]!

callsDescription
	self isDryRun ifTrue: [ ^ 'none -- a dry run makes no external call' ].
	self modelCalls = 0 ifTrue: [
		^ self produced
			ifTrue: [ '0 -- every stage was served from its own cache' ]
			ifFalse: [ '0 -- no model was called' ] ].
	^ self modelCalls printString, ' -- made by: ',
		(', ' join: ((self stages select: [ :each | each modelCalls > 0 ])
			collect: [ :each | each stage asString ]))!

summaryRows
	^ {
		{ 'slice'. self sliceName }.
		{ 'slice (EvidenceSet)'. self sliceId }.
		{ 'packet'. self packetId }.
		{ 'inference'. self inferenceId }.
		{ 'report'. self reportId }.
		{ 'file'. self path }.
		{ 'model calls'. self callsDescription }.
		{ 'produced a report'. self produced }.
		{ 'blocked at'. self blockedStage }.
		{ 'reason'. self reason ifEmpty: [ nil ] }.
		{ 'what would unblock it'. self remedy ifEmpty: [ nil ] }.
		{ 'wrote'. self wroteDescription } }!

wroteDescription
	"What this build actually left behind.  A blocked build still wrote the
	 stage that blocked it -- the interpretation's rejection is a durable result,
	 not a discarded attempt -- and claiming a rendered file that does not exist
	 would be the same lie as claiming none was written at all."
	self isDryRun ifTrue: [ ^ 'nothing -- dry run' ].
	self produced ifTrue: [ ^ 'an inference, a report record and a rendered file' ].
	self blockedStage ifNil: [ ^ 'nothing -- the build produced no report' ].
	^ 'the ', self blockedStage asString,
		' stage''s own result, stored durably; no report was rendered'!

summaryLine
	self isDryRun ifTrue: [ ^ 'dry run -- ', self stages size printString, ' stage(s) planned, nothing written' ].
	^ (self reportId ifNil: [ 'no report' ]) asString, ' -- ', self callsDescription! !


!McKdiReportBuild methodsFor: 'content'!
loadContent
	"kdi report show ID --content: the rendered file itself.  The backend carries
	 it in the --json answer on purpose, so a workbench needs no second,
	 unparsed invocation."
	| a |
	self reportId ifNil: [ ^ nil ].
	a := self binding runJson: { 'report'. 'show'. self reportId. '--content' }.
	contentAnswer := a.
	content := a hasValue ifTrue: [ a valueAt: 'content' ] ifFalse: [ nil ].
	^ content!

contentText
	^ content ifNil: [ self loadContent ]! !


!McKdiReportBuild methodsFor: 'verification'!
verify
	"kdi report verify ID --authoritative: re-render and compare, then re-decode
	 every cited source revision and re-check its selectors.  Reads only."
	| a |
	self reportId ifNil: [ ^ nil ].
	a := self binding runJson: { 'report'. 'verify'. self reportId. '--authoritative' }.
	verifyAnswer := a.
	verification := a hasValue ifTrue: [ a value ] ifFalse: [ nil ].
	^ verification!

verificationAt: aKey
	^ verification ifNil: [ nil ] ifNotNil: [ :v | v at: aKey ifAbsent: [ nil ] ]!

verificationRows
	| auth |
	verification ifNil: [ ^ #() ].
	auth := (self verificationAt: 'authoritative') ifNil: [ Dictionary new ].
	^ {
		{ 'report'. self verificationAt: 'report_id' }.
		{ 'reproduced'. (self verificationAt: 'reproduced') = true
			ifTrue: [ 'yes -- re-rendering gives byte-identical output' ]
			ifFalse: [ 'NO -- re-rendering differs from what was recorded' ] }.
		{ 'file on disk'. (self verificationAt: 'file_present') = true
			ifTrue: [ (self verificationAt: 'file_matches') = true
				ifTrue: [ 'present and unchanged' ] ifFalse: [ 'present but EDITED' ] ]
			ifFalse: [ 'absent -- the record stands, the file does not' ] }.
		{ 'stored hash'. self verificationAt: 'stored_content_hash' }.
		{ 'rendered hash'. self verificationAt: 'rendered_content_hash' }.
		{ 'revisions re-decoded'. auth at: 'revisions_redecoded' ifAbsent: [ nil ] }.
		{ 'selector statuses'. (auth at: 'status_counts' ifAbsent: [ nil ])
			ifNil: [ nil ] ifNotNil: [ :c | ', ' join: ((c associations asSortedCollection: [ :x :y | x key <= y key ])
				collect: [ :each | each key asString, ' ', each value asString ]) ] }.
		{ 'semantic support'. ((self verificationAt: 'validation') ifNil: [ Dictionary new ])
			at: 'semantic_support' ifAbsent: [ nil ] } }! !


!McKdiReportBuild methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiReportBuild(', self summaryLine, ')'! !


!McKdiReportBuild methodsFor: 'views'!
gtStagesFor: aView
	<gtView>
	^ aView columnedList
		title: 'Stages';
		priority: 10;
		items: [ self stages ];
		column: 'stage' text: [ :each | each stage asString ] width: 100;
		column: 'decision' text: [ :each | each decision asString ] width: 100;
		column: 'subject' text: [ :each | each subject asString ] width: 200;
		column: 'calls' text: [ :each | each modelCalls asString ] width: 60;
		column: 'detail' text: [ :each | each detail asString ];
		send: [ :each | each ]!

gtBuildFor: aView
	<gtView>
	^ aView columnedList
		title: 'Build';
		priority: 20;
		items: [ self summaryRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtContentFor: aView
	<gtView>
	self reportId ifNil: [ ^ aView empty ].
	^ aView textEditor
		title: 'Report';
		priority: 30;
		text: [ self contentText ifNil: [
			'The rendered file could not be read. ',
			((contentAnswer ifNil: [ nil ]) ifNil: [ '' ] ifNotNil: [ :a | a errorMessage asString ]) ] ]!

gtVerificationFor: aView
	<gtView>
	verification ifNil: [ ^ aView empty ].
	^ aView columnedList
		title: 'Verification';
		priority: 40;
		items: [ self verificationRows ];
		column: 'field' text: [ :each | each first ];
		column: 'value' text: [ :each | (each second ifNil: [ '--' ]) asString ]!

gtVerifyFailureFor: aView
	<gtView>
	(verification notNil or: [ verifyAnswer isNil ]) ifTrue: [ ^ aView empty ].
	^ aView textEditor
		title: 'Verification';
		priority: 40;
		text: [ verifyAnswer failureReport: 'The report was not verified.' ]! !


!McKdiReportBuild methodsFor: 'actions'!
gtVerifyActionFor: anAction
	<gtAction>
	self reportId ifNil: [ ^ anAction noAction ].
	^ anAction button
		label: (store actionLabel: 'Verify citations (reads only)');
		priority: 10;
		tooltip: 'kdi report verify ID --authoritative: re-render and compare, then re-decode every cited source revision and re-check its selectors';
		action: [ :aButton | store runOffUi: [ self verify ] from: aButton labelled: 'Verify' ]! !


!McKdiReportStage methodsFor: 'accessing'!
stage
	^ self at: 'stage'!

decision
	^ self at: 'decision'!

subject
	^ (self at: 'subject') ifNil: [ '' ]!

detail
	^ (self at: 'detail') ifNil: [ '' ]!

modelCalls
	^ (self at: 'model_calls') ifNil: [ 0 ]! !


!McKdiReportStage methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'McKdiReportStage(', self stage asString, ' ', self decision asString, ')'! !
