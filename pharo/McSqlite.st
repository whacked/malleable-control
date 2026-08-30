"
McSqlite -- execute a read-only SQLite query and answer an McRelation.

Runs sqlite3 -readonly -header -ascii through GtSubprocessWithInMemoryOutput.
The -ascii mode frames columns with 0x1F (Unit Separator) and rows with 0x1E
(Record Separator), so there is no quoting or escaping to parse.  -readonly
makes the read-only decision the driver's rather than our discipline.

The database path is resolved relative to McHome (the project root) when it is
not absolute.

Chunk format: load with fileIn.
"!

Object subclass: #McSqliteSource
	instanceVariableNames: 'dbPath'
	classVariableNames: 'QueryCache'
	package: 'MalleableControl'!

!McSqliteSource class methodsFor: 'instance creation'!
on: aPath
	^ self new setDbPath: aPath! !

!McSqliteSource class methodsFor: 'cache'!
queryCache
	^ QueryCache ifNil: [ QueryCache := Dictionary new ]!

clearCache
	QueryCache := nil! !

!McSqliteSource methodsFor: 'initialization'!
setDbPath: aString
	dbPath := aString! !

!McSqliteSource methodsFor: 'accessing'!
dbPath
	^ dbPath!

resolvedDbPath
	"Resolve the database path against the project root when relative."
	| ref root |
	ref := dbPath asFileReference.
	ref isAbsolute ifTrue: [ ^ ref ].
	root := (Smalltalk at: #McHome ifAbsent: [ nil ])
		ifNil: [ FileLocator workingDirectory resolve ]
		ifNotNil: [ :path | path asFileReference ].
	^ root / dbPath! !

!McSqliteSource methodsFor: 'querying'!
query: aSqlString
	"Execute aSqlString against the database and answer an McRelation.
	 Results are cached by (dbPath, sql, file modification time) so the
	 styler -- which runs on every keystroke -- does not shell out to
	 sqlite3 on every restyle.  Signals an Error on failure."
	| resolved cacheKey modTime cached |
	resolved := self resolvedDbPath.
	resolved exists ifFalse: [
		Error signal: 'Database not found: ' , resolved pathString ].
	modTime := resolved modificationTime.
	cacheKey := dbPath , '|' , aSqlString , '|' , modTime printString.
	cached := self class queryCache at: cacheKey ifAbsent: [ nil ].
	cached ifNotNil: [ ^ cached ].
	^ self class queryCache at: cacheKey put: (self executeQuery: aSqlString on: resolved)!

executeQuery: aSqlString on: aResolvedPath
	"Run the query and parse the result.  Separated from query: so the
	 cache logic stays in one place."
	| process exitCode stdout stderr |
	process := GtSubprocessWithInMemoryOutput new
		command: 'sqlite3';
		arguments: {
			'-readonly'. '-header'. '-ascii'.
			aResolvedPath pathString.
			aSqlString };
		runAndWait.
	exitCode := process exitCode.
	stdout := process stdout.
	stderr := process stderr.
	exitCode = 0 ifFalse: [
		Error signal: (stderr ifEmpty: [ 'sqlite3 exited with code ' , exitCode printString ]) ].
	^ self parseAsciiOutput: stdout!

parseAsciiOutput: aString
	"Parse the -ascii framed output into an McRelation.  The first record
	 is the header row; subsequent records are data rows."
	| unitSep recordSep records columns rows |
	unitSep := Character value: 16r1F.
	recordSep := Character value: 16r1E.
	aString isEmpty ifTrue: [
		^ McRelation columns: #() rows: #()
			directives: McTableDirectives forQuery ].
	records := aString splitOn: recordSep.
	"A trailing record separator leaves one empty element at the end."
	records := records reject: [ :each | each isEmpty ].
	records isEmpty ifTrue: [
		^ McRelation columns: #() rows: #()
			directives: McTableDirectives forQuery ].
	columns := (records first splitOn: unitSep) collect: [ :name |
		McRelationColumn name: name trimBoth alignment: #left ].
	rows := (2 to: records size) collect: [ :index |
		| fields cells |
		fields := (records at: index) splitOn: unitSep.
		cells := (1 to: columns size) collect: [ :col |
			McRelationCell
				source: ((fields at: col ifAbsent: [ '' ]) trimBoth)
				interval: nil ].
		McRelationRow cells: cells columns: columns interval: nil ].
	"Derive alignment: right-align columns where every non-empty cell is numeric."
	columns doWithIndex: [ :col :idx |
		| allNumeric |
		allNumeric := rows allSatisfy: [ :row |
			| cell |
			cell := row at: idx.
			cell source trimBoth isEmpty or: [ cell number notNil ] ].
		allNumeric ifTrue: [ col alignment: #right ] ].
	^ McRelation columns: columns rows: rows
		directives: McTableDirectives forQuery! !
