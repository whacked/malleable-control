"
McCache -- one bounded, least-recently-used cache, shared by every caller
that memoises something on the render path.

Three of them exist in this codebase and they all wanted the same three
properties, which is why this is a class rather than three Dictionaries:

  1. A bound.  A styler runs on every keystroke, so anything keyed by what
     the user has typed grows once per keystroke.  The query cache this
     replaces was an unbounded class-side Dictionary keyed by the SQL text,
     so editing a query left one entry per prefix behind, forever.

  2. Recency.  The bound has to evict something, and the entry least
     recently asked for is the one least likely to be asked for next --
     the table being edited stays warm while the one scrolled past falls
     out.

  3. Counters.  Hits and misses are the only way to test that a fast path
     is actually being taken.  A wall-clock assertion is a flaky test; an
     assertion that the second call to the same key did not recompute is
     not.

Recency is kept as an OrderedCollection of keys, oldest first, and touching
a key is a linear removal from it.  That is deliberate: the caches here hold
tens of entries, and a linear scan over tens of elements is cheaper than the
doubly-linked list that would make it constant time.

Chunk format: load with fileIn.
"!

Object subclass: #McBoundedCache
	instanceVariableNames: 'limit entries order hits misses evictions'
	classVariableNames: ''
	package: 'MalleableControl'!

!McBoundedCache class methodsFor: 'instance creation'!
limit: anInteger
	^ self new setLimit: anInteger!

default
	"The size every caller here wants unless it says otherwise: big enough
	 that a document's tables and queries all stay resident, small enough
	 that nothing is retained by accident."
	^ self limit: 64! !

!McBoundedCache methodsFor: 'initialization'!
setLimit: anInteger
	limit := anInteger max: 1.
	entries := Dictionary new.
	order := OrderedCollection new.
	hits := 0.
	misses := 0.
	evictions := 0! !

!McBoundedCache methodsFor: 'accessing'!
limit
	^ limit!

size
	^ entries size!

isEmpty
	^ entries isEmpty!

includesKey: aKey
	"Membership without recording a hit or a miss, and without promoting the
	 key.  Statistics are about the render path, and an existence check is
	 not on it."
	^ entries includesKey: aKey!

keysInOrder
	"The keys, least recently used first -- which is eviction order."
	^ order asArray! !

!McBoundedCache methodsFor: 'lookup'!
at: aKey ifAbsent: aBlock
	(entries includesKey: aKey) ifFalse: [
		misses := misses + 1.
		^ aBlock value ].
	hits := hits + 1.
	self touch: aKey.
	^ entries at: aKey!

at: aKey ifAbsentPut: aBlock
	"aBlock is evaluated when aKey is absent, and its value stored and
	 answered.  A block answering nil is evaluated again next time -- nil
	 is how absence is spelled here, so it cannot also be a value."
	| found |
	found := self at: aKey ifAbsent: [ nil ].
	found ifNotNil: [ ^ found ].
	^ self at: aKey put: aBlock value!

at: aKey put: aValue
	"A value already under aKey is replaced, not added again: touch: removes
	 the key from the recency list before appending it, so the list holds
	 each key once and its size is the cache's size."
	entries at: aKey put: aValue.
	self touch: aKey.
	self evictWhileOverLimit.
	^ aValue!

removeKey: aKey ifAbsent: aBlock
	(entries includesKey: aKey) ifFalse: [ ^ aBlock value ].
	order remove: aKey ifAbsent: [ nil ].
	^ entries removeKey: aKey!

removeAll
	entries := Dictionary new.
	order := OrderedCollection new! !

!McBoundedCache methodsFor: 'private'!
touch: aKey
	order remove: aKey ifAbsent: [ nil ].
	order addLast: aKey!

evictWhileOverLimit
	[ order size > limit ] whileTrue: [
		| oldest |
		oldest := order removeFirst.
		entries removeKey: oldest ifAbsent: [ nil ].
		evictions := evictions + 1 ]! !

!McBoundedCache methodsFor: 'statistics'!
hits
	^ hits!

misses
	^ misses!

evictions
	^ evictions!

resetStatistics
	hits := 0.
	misses := 0.
	evictions := 0! !

!McBoundedCache methodsFor: 'printing'!
printOn: aStream
	aStream
		<< 'McBoundedCache(';
		print: entries size;
		<< '/';
		print: limit;
		<< ' hits ';
		print: hits;
		<< ' misses ';
		print: misses;
		<< ')'! !
