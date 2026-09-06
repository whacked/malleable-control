"
McWeatherView -- Weather station UI for Glamorous Toolkit.

Driven from Emacs over the NATS bus.  On button click, auto-detects location
via IP geolocation, fetches current weather from Open-Meteo (free, no API key),
renders temperature and conditions with vector icons, and publishes the
reading back to Emacs as a gt.event.weather event.

Chunk format: load with fileIn, reach the class with
	(Smalltalk at: #McWeatherView).
"!

Object subclass: #McWeatherView
	instanceVariableNames: 'space container statusLabel temperatureLabel detailsLabel iconContainer'
	classVariableNames: ''
	package: 'MalleableControl'!

!McWeatherView class methodsFor: 'opening'!
open
	"One window per tool: a panel that is already up comes forward and
	 re-fetches rather than being duplicated.  See McWindow."
	^ (McWindow front: self) ifNil: [ self new openView ]! !

!McWeatherView methodsFor: 'opening'!
openView
	| titleLabel button separator |
	space := BlSpace new.
	space title: 'Weather Station'.
	space extent: 440@520.

	container := BlElement new.
	container layout: BlLinearLayout vertical.
	container constraintsDo: [:c | c horizontal matchParent. c vertical matchParent].
	container padding: (BlInsets all: 28).
	container background: (Color fromHexString: '#0f0e17').

	titleLabel := BrLabel new.
	titleLabel text: ('Weather Station' asRopedText
		foreground: (Color fromHexString: '#fffffe');
		fontSize: 24;
		bold).
	titleLabel constraintsDo: [:c | c linear horizontal alignCenter].
	titleLabel margin: (BlInsets bottom: 20).

	iconContainer := BlElement new.
	iconContainer size: 140@140.
	iconContainer layout: BlFrameLayout new.
	iconContainer constraintsDo: [:c | c linear horizontal alignCenter].
	iconContainer margin: (BlInsets bottom: 12).
	iconContainer addChild: self placeholderIcon.

	temperatureLabel := BrLabel new.
	temperatureLabel text: ('--' asRopedText
		foreground: (Color fromHexString: '#fffffe');
		fontSize: 64;
		bold).
	temperatureLabel constraintsDo: [:c | c linear horizontal alignCenter].
	temperatureLabel margin: (BlInsets bottom: 4).

	detailsLabel := BrLabel new.
	detailsLabel text: ('' asRopedText
		foreground: (Color fromHexString: '#a7a9be');
		fontSize: 14).
	detailsLabel constraintsDo: [:c | c linear horizontal alignCenter].
	detailsLabel margin: (BlInsets bottom: 8).

	statusLabel := BrLabel new.
	statusLabel text: ('Press Fetch Weather to begin' asRopedText
		foreground: (Color fromHexString: '#a7a9be');
		fontSize: 13).
	statusLabel constraintsDo: [:c | c linear horizontal alignCenter].
	statusLabel margin: (BlInsets bottom: 20).

	separator := BlElement new.
	separator constraintsDo: [:c | c horizontal matchParent. c vertical exact: 1].
	separator background: (Color fromHexString: '#2e2e3e').
	separator margin: (BlInsets top: 4 right: 0 bottom: 16 left: 0).

	button := BrButton new.
	button label: 'Fetch Weather'.
	button aptitude: BrGlamorousButtonWithLabelAptitude new.
	button constraintsDo: [:c | c linear horizontal alignCenter].
	button action: [ self fetchWeather ].

	container addChild: titleLabel.
	container addChild: iconContainer.
	container addChild: temperatureLabel.
	container addChild: detailsLabel.
	container addChild: statusLabel.
	container addChild: separator.
	container addChild: button.

	space root addChild: container.
	space show.
	^ self! !

!McWeatherView methodsFor: 'fetching'!
refreshView
	"Re-fetch.  fetchWeather forks its HTTP calls, so this answers at once and
	 the panel is already in front by the time the reading lands."
	^ self fetchWeather!

fetchWeather
	"Detect location, fetch weather, update display, and notify Emacs.
	 Forked so the HTTP calls do not block the Bloc UI pulse."
	self updateStatus: 'Detecting location...'.
	[
		[ | lat lon location url wxResponse wxJson current temp feelsLike humidity wind code desc detailStr |
			"Step 1: auto-detect coordinates via IP geolocation."
			[ | geoResponse geoJson |
			  geoResponse := ZnClient new
				url: 'https://ipapi.co/json/';
				timeout: 10;
				get.
			  geoJson := NeoJSONReader fromString: geoResponse.
			  lat := geoJson at: 'latitude' ifAbsent: [ 37.77 ].
			  lon := geoJson at: 'longitude' ifAbsent: [ -122.42 ].
			  location := (geoJson at: 'city' ifAbsent: [ '?' ]) , ', ' ,
				(geoJson at: 'region' ifAbsent: [ '' ]) ]
					on: Error
					do: [ :e |
						lat := 37.77. lon := -122.42.
						location := 'San Francisco, CA (fallback)' ].

			self updateStatus: 'Fetching weather for ' , location , '...'.

			"Step 2: fetch current weather from Open-Meteo (free, no API key)."
			url := 'https://api.open-meteo.com/v1/forecast?latitude=' , lat printString ,
				'&longitude=' , lon printString ,
				'&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m' ,
				'&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto'.
			wxResponse := ZnClient new url: url; timeout: 10; get.
			wxJson := NeoJSONReader fromString: wxResponse.
			current := wxJson at: 'current'.

			temp := current at: 'temperature_2m'.
			feelsLike := current at: 'apparent_temperature'.
			humidity := current at: 'relative_humidity_2m'.
			wind := current at: 'wind_speed_10m'.
			code := current at: 'weather_code'.
			desc := self descriptionForCode: code.

			"Step 3: update the display."
			detailStr := desc , '  |  Feels like ' , feelsLike printString , '°F  |  '
				, humidity printString , '%  |  ' , wind printString , ' mph'.
			self showWeather: temp printString , '°F'
				details: detailStr
				location: location
				code: code.

			"Step 4: publish to Emacs via the bus."
			self publishTemp: temp location: location description: desc
				feelsLike: feelsLike humidity: humidity wind: wind
		] on: Error do: [ :e |
			self updateStatus: 'Error: ' , e messageText printString ]
	] fork! !

!McWeatherView methodsFor: 'display'!
updateStatus: aString
	space ifNil: [ ^ self ].
	space enqueueTask: (BlTaskAction new action: [
		statusLabel text: (aString asRopedText
			foreground: (Color fromHexString: '#a7a9be');
			fontSize: 13) ])!

showWeather: tempStr details: detailStr location: location code: code
	"Replace temperature, details, status, and icon in one UI pulse."
	space ifNil: [ ^ self ].
	space enqueueTask: (BlTaskAction new action: [
		temperatureLabel text: (tempStr asRopedText
			foreground: (Color fromHexString: '#fffffe');
			fontSize: 64;
			bold).
		detailsLabel text: (detailStr asRopedText
			foreground: (Color fromHexString: '#a7a9be');
			fontSize: 13).
		statusLabel text: (location asRopedText
			foreground: (Color fromHexString: '#7f5af0');
			fontSize: 14;
			bold).
		iconContainer removeChildren.
		iconContainer addChild: (self iconForCode: code) ])! !

!McWeatherView methodsFor: 'icons'!
placeholderIcon
	"Gray circle shown before any weather is fetched."
	| el |
	el := BlElement new.
	el size: 80@80.
	el geometry: BlCircleGeometry new.
	el background: (Color fromHexString: '#2e2e3e').
	el constraintsDo: [:c | c frame horizontal alignCenter. c frame vertical alignCenter].
	^ el!

iconForCode: code
	"Return a vector weather icon element for the given WMO weather code."
	code = 0 ifTrue: [ ^ self sunIcon ].
	(code between: 1 and: 2) ifTrue: [ ^ self partlyCloudyIcon ].
	code = 3 ifTrue: [ ^ self cloudIcon ].
	(code between: 45 and: 48) ifTrue: [ ^ self cloudIcon ].
	(code between: 51 and: 67) ifTrue: [ ^ self rainIcon ].
	(code between: 71 and: 77) ifTrue: [ ^ self snowIcon ].
	(code between: 80 and: 82) ifTrue: [ ^ self rainIcon ].
	(code between: 95 and: 99) ifTrue: [ ^ self thunderIcon ].
	^ self sunIcon!

sunIcon
	"Glowing sun: bright circle with a translucent halo."
	| group glow sun |
	group := BlElement new.
	group size: 120@120.
	group layout: BlFrameLayout new.

	glow := BlElement new.
	glow size: 110@110.
	glow geometry: BlCircleGeometry new.
	glow background: (Color fromHexString: '#FFD93D').
	glow opacity: 0.15.
	glow constraintsDo: [:c | c frame horizontal alignCenter. c frame vertical alignCenter].

	sun := BlElement new.
	sun size: 60@60.
	sun geometry: BlCircleGeometry new.
	sun background: (Color fromHexString: '#FFD93D').
	sun constraintsDo: [:c | c frame horizontal alignCenter. c frame vertical alignCenter].

	group addChild: glow.
	group addChild: sun.
	^ group!

cloudIcon
	"Overcast cloud from overlapping circles and a rounded base."
	| group base bump1 bump2 |
	group := BlElement new.
	group size: 120@80.
	group layout: BlBasicLayout new.

	base := BlElement new.
	base size: 100@36.
	base position: 10@44.
	base geometry: (BlRoundedRectangleGeometry cornerRadius: 18).
	base background: (Color fromHexString: '#b0b3c5').

	bump1 := BlElement new.
	bump1 size: 52@52.
	bump1 position: 18@10.
	bump1 geometry: BlCircleGeometry new.
	bump1 background: (Color fromHexString: '#c4c7d6').

	bump2 := BlElement new.
	bump2 size: 40@40.
	bump2 position: 55@18.
	bump2 geometry: BlCircleGeometry new.
	bump2 background: (Color fromHexString: '#b8bccf').

	group addChild: base.
	group addChild: bump1.
	group addChild: bump2.
	^ group!

partlyCloudyIcon
	"Sun peeking behind a cloud."
	| group sun cloud |
	group := BlElement new.
	group size: 140@110.
	group layout: BlBasicLayout new.

	sun := BlElement new.
	sun size: 50@50.
	sun position: 75@5.
	sun geometry: BlCircleGeometry new.
	sun background: (Color fromHexString: '#FFD93D').

	cloud := self cloudIcon.
	cloud position: 5@25.

	group addChild: sun.
	group addChild: cloud.
	^ group!

rainIcon
	"Cloud with rain drops."
	| group cloud |
	group := BlElement new.
	group size: 120@110.
	group layout: BlBasicLayout new.

	cloud := self cloudIcon.
	group addChild: cloud.

	#(28 52 76) do: [:x |
		| drop |
		drop := BlElement new.
		drop size: 6@14.
		drop position: x@88.
		drop geometry: (BlRoundedRectangleGeometry cornerRadius: 3).
		drop background: (Color fromHexString: '#48bfe3').
		group addChild: drop].
	^ group!

snowIcon
	"Cloud with snowflakes."
	| group cloud |
	group := BlElement new.
	group size: 120@110.
	group layout: BlBasicLayout new.

	cloud := self cloudIcon.
	group addChild: cloud.

	#(25 50 80) do: [:x |
		| flake |
		flake := BlElement new.
		flake size: 10@10.
		flake position: x@88.
		flake geometry: BlCircleGeometry new.
		flake background: (Color fromHexString: '#e0e5ec').
		group addChild: flake].
	^ group!

thunderIcon
	"Cloud with a lightning bolt."
	| group cloud bolt |
	group := BlElement new.
	group size: 120@115.
	group layout: BlBasicLayout new.

	cloud := self cloudIcon.
	group addChild: cloud.

	bolt := BlElement new.
	bolt size: 14@28.
	bolt position: 52@82.
	bolt geometry: (BlRoundedRectangleGeometry cornerRadius: 2).
	bolt background: (Color fromHexString: '#FFD93D').
	group addChild: bolt.
	^ group! !

!McWeatherView methodsFor: 'weather codes'!
descriptionForCode: code
	"WMO Weather Interpretation Code to human description."
	code = 0 ifTrue: [ ^ 'Clear sky' ].
	code = 1 ifTrue: [ ^ 'Mainly clear' ].
	code = 2 ifTrue: [ ^ 'Partly cloudy' ].
	code = 3 ifTrue: [ ^ 'Overcast' ].
	(code between: 45 and: 48) ifTrue: [ ^ 'Fog' ].
	(#(51 53 55) includes: code) ifTrue: [ ^ 'Drizzle' ].
	(#(56 57) includes: code) ifTrue: [ ^ 'Freezing drizzle' ].
	(#(61 63 65) includes: code) ifTrue: [ ^ 'Rain' ].
	(#(66 67) includes: code) ifTrue: [ ^ 'Freezing rain' ].
	(#(71 73 75) includes: code) ifTrue: [ ^ 'Snowfall' ].
	code = 77 ifTrue: [ ^ 'Snow grains' ].
	(code between: 80 and: 82) ifTrue: [ ^ 'Rain showers' ].
	(#(85 86) includes: code) ifTrue: [ ^ 'Snow showers' ].
	code = 95 ifTrue: [ ^ 'Thunderstorm' ].
	(#(96 99) includes: code) ifTrue: [ ^ 'Thunderstorm with hail' ].
	^ 'Unknown'! !

!McWeatherView methodsFor: 'bus'!
publishTemp: temp location: location description: desc feelsLike: feelsLike humidity: humidity wind: wind
	"Send the weather reading back to Emacs as a gt.event.weather event."
	| service |
	service := Smalltalk at: #McGtService ifAbsent: [ nil ].
	(service notNil and: [ service isRunning ]) ifFalse: [ ^ self ].
	service current publishEvent: 'gt.event.weather' data: (OrderedDictionary new
		at: 'temperature' put: temp;
		at: 'feelsLike' put: feelsLike;
		at: 'humidity' put: humidity;
		at: 'wind' put: wind;
		at: 'description' put: desc;
		at: 'location' put: location;
		yourself)! !
