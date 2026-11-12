# PoolKit for iOS

Give your app the context in a person's camera roll: the products, places,
events, recipes, links and more they photographed or screenshotted, with the
evidence behind every answer and a grant the person can take back.

Everything is read and indexed on the device, by the same engine that runs the
Pool app. No photo ever leaves the phone.

- iOS 18 and later, iPhone and iPad (the engine needs Core ML and the Neural Engine)
- Xcode 27 or later
- About 375 MB of models, downloaded on Wi-Fi after the first grant and checked
  against their SHA-256. Until they arrive, search uses recognized text, Vision
  labels and Apple's language models, so the first answers come right away.

## Install

In Xcode choose File, Add Package Dependencies, and add this package. In a
`Package.swift`:

```swift
.package(url: "https://github.com/ram-company/pool-kit", from: "0.2.0")
```

Add the photo library usage description to your `Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Find the things you saved, so we can suggest gifts you will like.</string>
```

## Quick start

```swift
import PoolKit

// 1. Open the client once, at launch. Get a key at pool.day/developers.
let pool = try await PoolClient.open(configuration: .init(appKey: "pk_live_…"))

// 2. Ask for the narrowest access your feature needs. The first call shows
//    the system photo library prompt. Indexing starts when the grant exists.
let grant = try await pool.authorization.requestAccess(
    AccessRequest(
        sources: [.screenshots, .photos],
        data: [.products, .places],
        purpose: "Suggest gifts from the things you saved"
    )
)

// 3. Ask in plain words, or with a typed query.
let result = try await pool.context.query("sneakers I saved last month", using: grant)

for match in result.matches {
    print(match.summary, match.provenance, match.confidence)
}

// 4. An empty answer only means "nothing there" when coverage is complete.
if result.matches.isEmpty, !result.coverage.isComplete {
    print("Still indexing: \(result.coverage.indexedAssets) of \(result.coverage.knownAssets)")
}
```

## Search photos

`search` returns the photos, screenshots and videos themselves, best first. It
fuses the words read from each capture with what the image looks like, using
the Pool engine's SigLIP 2 image and text model, and runs entirely on the device:

```swift
let result = try await pool.context.search("red sneakers", using: grant, limit: 50)
for hit in result.hits {
    // hit.asset.locator is the PHAsset local identifier.
    print(hit.asset.locator, hit.reasons, hit.labels)   // [.looksLike, .text], ["shoe"]
}
let more = try await pool.context.similar(to: result.hits[0].asset.id, using: grant)
```

`result.matchedVisually` is false until the models are installed.

`limit` is 500 by default and `nil` returns every match (up to 10,000); page
with `offset` or `nextCursor`, and read `totalCount`. Date words become a window
("last spring", "in March", "2025", "Christmas", "Easter", "Thanksgiving", "New
Year's"), media words a filter ("screenshots", "videos"), and singular and plural
find each other. `result.searchPlan` says how the words were read (operation,
intent, the words the image model saw, sort, a sentence of `details`), and
`seconds` and `timings` where the time went. Each hit carries `matchReasons`
(image, text, place), `matchedText`, `relevance` against the best match,
`retrievalScore`, and `duplicates`: other shots of the same moment, taken
seconds apart, which are shown once and counted once in facets.

Each hit's `details` add what Vision saw with its probability, `cuisines` read
from food labels, and for screenshots the kind of app, topic, action
(buy, visit, attend…), any event time and whether it is past or upcoming, and
whether a language model has named its things yet (`deferred` until one has).
`context` says the part of day, weekend, faces counted (never recognised),
selfie and, under `placesVisited`, whether it was taken away from home.
`activities` are the taxonomy topics it counts for and why; `isFavorite` and
`mediaType` come from Photos.

## Classify by a rule

`classify` turns a rule in plain words into a set: every capture the grant
covers, with how likely it is to belong.

```swift
let result = try await pool.context.classify(rule: "sneakers I might buy", using: grant)
for member in result.members {
    print(member.asset.locator, member.probability, member.decidedBy)   // 0.87, .onDevice
}

// The same rule as a live set: new captures join as they are indexed.
for try await update in pool.context.observeClassification(rule: "sneakers I might buy", using: grant) {
    render(update.members)
}
```

Stage one always runs on the device: how much each image looks like the rule
(the engine's auto-pool matcher, once its models are installed) plus matching
text, labels and named things. Stage two runs only when the configuration and
the grant allow cloud assist: Pool's cloud judge settles the borderline
captures from their derived text, labels and names, never an image or a
locator. If the judge asks to wait, the on-device result stands and
`cloudRetryAfter` says when to try again. Rules about people's traits or
identity are refused. On-device probabilities are fitted to the cloud judge's
verdicts (`isCalibrated` is true), on a small test library, so read values
between 0.2 and 0.8 as approximate. Words alone are weak evidence: without the
image model, a capture holding every word of the rule scores about 0.35, under
the default threshold. Ranking scores are not fitted yet.

## Read one capture

For bookmarking: read an image your app already has, from a picker, a share
extension or a paste. It needs no grant and no photo library access, and
nothing is kept.

```swift
let reading = try await pool.reader.read(imageData: pngData)
for thing in reading.things {
    print(thing.type, thing.name, thing.attributes["price"] ?? "", thing.provenance)
}
```

Apple's on-device model names things where it is available. With
`ReadOptions(allowsCloudAssist: true)` and cloud assist on in the
configuration, Pool's service names them otherwise, from the text only. A
capture that looks like an ID, a payment card, a credential or a health record
comes back with `isRestricted` and nothing in it.

## Signals

Signals turn new saves into events your app can act on: "saved that bag",
"saved a concert". They are delivered inside your app; forward them to your
own server.

```swift
// Every new capture where PoolKit finds a product.
for try await signal in pool.signals.subscribe(to: .saved(.product), using: grant) {
    send(signal.id, signal.thing?.name, signal.thing?.brand, signal.thing?.price, signal.capturedAt)
}

// Or a rule in plain words, matched like classify.
for try await signal in pool.signals.subscribe(rule: "songs or concerts", using: grant) { … }

// At launch or after a background wake: what arrived while you were away.
let missed = try await pool.signals.pending(.rule("songs or concerts"), using: grant)
try await pool.signals.acknowledge(missed)
```

Only captures taken after a subscription was first made count. Each
subscription keeps a delivery record on the device, so a stream never
delivers a signal twice, and captures indexed in the background wait in
`pending` until you acknowledge them. The same capture and subscription always
give the same `id`. A signal says what was saved, with evidence, never what
the person likes. Signals need the `observe` operation.

## Rank a catalog

Hand PoolKit the items you are about to show, such as a catalog page or a
starter grid, and get them back in the order that fits what the person saved.
Only your ids, scores and reasons come back.

```swift
let ranking = try await pool.context.rank([
    RankCandidate(id: "sku-1", text: "Leather tote, Polène", imageData: toteJPEG),
    RankCandidate(id: "sku-2", text: "Nike Air Max 90 White"),
], using: grant)
ranking.items   // [("sku-2", 0.84, [.sameThing]), ("sku-1", 0.61, [.looksLikeSaved])]
```

Ranking runs on the device with the `query` operation. To rank on your own
server instead, ask for the separate `exportTaste` operation and read
`tasteVectors(using:)`: a few weighted centres of what the person saved, in
the engine's embedding space, never a vector per capture.

## Trips

For travel apps: trips away from home, at city level, built from where photos
were taken.

```swift
let request = AccessRequest(data: DataCategory.things.union([.placesVisited]), purpose: "Suggest spots near places you loved")
let grant = try await pool.authorization.requestAccess(request)
let result = try await pool.context.trips(using: grant)
for trip in result.trips {
    print(trip.firstDay, trip.lastDay, trip.cities.map(\.name), trip.savedPlaceIDs)
}
```

`placesVisited` is a data category of its own that no default grant includes.
Only the nearest city of each photo is kept, never its coordinates, using a
city table bundled with PoolKit, so nothing is looked up online. Home, and a
second place almost as frequent such as work, is worked out on the device and
left out together with every city near it. When home is not clear (too few
photos with a location, or two places alike), `home` says so and no trips come
back. Days are whole days, never times. Screenshots and photos without a
location never count as a visit.

## Interests

```swift
for interest in try await pool.context.interests(using: grant) {
    print(interest.path.joined(separator: " › "), interest.status, interest.days, interest.timesTypical ?? 0)
}
let topics = PoolClient.interestTaxonomy   // every topic, with its IAB Audience Taxonomy ids
```

Interests are counts of the days the person saved captures about a topic of a
taxonomy built on the IAB Audience Taxonomy 1.1, without topics on health,
religion, politics, sexuality or children. A capture counts for a topic, and
every topic above it, when Vision labelled it with one of the topic's labels or
a thing in it names one of the topic's words. `.now` (the last 90 days) returns
`active` and `emerging` topics by `strength`; `.lifetime` adds `lapsed` ones by
`lifetimeStrength`; `includeAll` adds `typical` topics and single-day
`moment`s. `timesTypical` compares the topic's share of the person's capture
days with a typical person's, so taking more photos does not inflate it. An
interest never says what the person likes.

## Places

Under the `locations` category, which no other category implies and which you
ask for on its own, photos and videos carry where they were taken: coordinates,
neighbourhood, city, metro area, country and time zone, grouped into visits
(runs of photos close in time and place) with the venue Maps finds there and
the visit's context (away from home, people counted, part of day, weekend,
selfie). Search understands place words: "Lisbon", "Chiado", "museum", "ramen"
(`reasons` gains `.place`, hits carry `placeMatches` and `placeSimilarity`).
Under `placesVisited` only, results carry the city and country, never
coordinates. Nothing is shown for places near home.

Names come from Apple's geocoder and Maps, which see the coordinates; Pool's
servers never do. Lookups run once per area, at most one every 1.5 seconds and
never on cellular, and are kept on the device. Offline, the bundled city table
(cities over 15,000 people, within 75 km) names the city.

## People

Under the `people` category, which you ask for on its own and in plain words
(it is biometric data), and with `IndexOptions.people` on, PoolKit groups photos
of the same face on the device:

```swift
let people = try await pool.context.people(using: grant)        // unnamed PersonGroup values
let photos = try await pool.context.photos(of: people[0].id, using: grant)
```

Groups are never named by PoolKit; your app may let the person name them.
Nothing about a face ever leaves the device or reaches cloud assist. Grouping
errs towards keeping people apart, so one person can take more than one group.
`ageRange` and `apparentGender` are estimates of appearance from an optional
on-device model, given only when it is at least 0.7 sure, and `nil` until the
model is installed. Turning people off deletes every face and group.

## Recurring things and facets

```swift
// Things seen in two captures or more: how often, when, and whether it is
// rising, steady, fading or new. Counts and dates only, never "likes".
let recurring = try await pool.context.recurringThings(using: grant, types: [.product, .place])

// Counts for browse screens: entity types, Vision labels, brands and stores.
let facets = try await pool.context.facets(using: grant, limit: 16, samples: 4)
```

## Answers and profiles

```swift
let answer = try await pool.context.ask("Which sneakers did I look at most this month?", using: grant)
print(answer.text, answer.citations)    // citations are evidence IDs

let schema: JSONValue = [
    "type": "object",
    "properties": [
        "shoeSize": ["type": "string"],
        "favoriteCuisines": ["type": "array", "items": ["type": "string"]],
    ],
]
let profile = try await pool.context.profile(schema: schema, using: grant)
profile.value["shoeSize"]          // .string("44") or .null
profile.evidence["/shoeSize"]      // evidence IDs behind it
profile.refused["/favoriteCuisines"] // .noEvidence, .sensitive or .invalid
```

Retrieval runs on the device. `ask` writes its answer with Apple's on-device
model when it is available, and otherwise with Pool's service; `profile` always
uses the service. Both need cloud assist in the configuration and the grant
whenever the service is used, and send only derived text with opaque references,
never an image, a locator or a vector. Every answer is `inferred`, and fields
about health, religion, sexuality, ethnicity, politics, children, finances or
credentials are always refused.

Questions are up to 1,000 characters (`PoolContext.questionMaximumLength`). To
show the answer as it is written, use `askUpdates`, which runs the same checks and
retrieval:

```swift
var shown = ""
for try await update in pool.context.askUpdates("Which sneakers did I save most?", using: grant) {
    switch update {
    case .searching: showSpinner()
    case .writing: shown = ""            // a new writer starts over
    case .partial(let text): shown = text // the whole text so far
    case .answer(let answer): shown = answer.declined ? "" : answer.text
    }
}
```

On a device with App Attest, PoolKit attests its key with Apple once, on the
first cloud assist call, and signs every later call. Add the
`com.apple.developer.devicecheck.appattest-environment` entitlement
(`development`, or `production` for a store build) to your app. Without it, or
in the Simulator, calls go unsigned; on-device features never wait on it.

## What you get back

Every `Match` says how Pool knows it:

| `provenance` | Meaning |
| --- | --- |
| `explicit` | The person said or confirmed it. |
| `observed` | Read directly from the source: a link in the text, a QR code, a capture date. |
| `inferred` | A model or rule produced it. It comes with a confidence and evidence. |
| `unresolved` | Pool has a lead, for example "a product page with a price", but has not established what it is. |

Every `QueryResult` carries `evidence` (which asset, where in it, which
extractor), `coverage` (what Pool could see), `asOf`, a `plan` showing how the
question was read, a `nextCursor`, and a `traceID` with no personal content.

## Grants

A grant names sources, data categories, operations and a purpose. Pool indexes
only the sources an active grant names and answers only what the grant covers.
It is checked again on every call, so revoking takes effect immediately:

```swift
try await pool.authorization.revoke(grant)
```

When the last active grant is revoked, the whole index is deleted. When a photo
is deleted, or photo access is taken away, everything derived from it goes too,
and `context.changes(since:using:)` lists a tombstone for each removed record.

## Errors

Every call throws a `PoolError`, a case you can switch over. Each also says what to
do next: `retryable` (the same call may succeed later: offline, rate limited, the
service busy or failing, models still installing), `retryAfter` (seconds, when the
service said) and `serverCode` (the code the service and dashboard logs use, for
errors the service can return; a quota or plan limit shows as `rate_limited` with a
longer wait).

```swift
do {
    answer = try await pool.context.ask(question, using: grant)
} catch let error as PoolError where error.retryable {
    retry(after: .seconds(error.retryAfter ?? 30))
}
```

## Live queries

```swift
let request = AccessRequest(operations: [.query, .observe], purpose: "Keep your wishlist fresh")
let grant = try await pool.authorization.requestAccess(request)

for try await update in pool.context.observe(ContextQuery(types: [.product]), using: grant) {
    render(update.result.matches)
}
```

## How things are found

1. **On device, always.** Apple's Vision reads text, QR codes and barcodes,
   labels what a photo shows, and makes a visual fingerprint. Fixed rules turn
   that into links, objects and leads.
2. **On device, iOS 26 with Apple Intelligence.** The system language model
   names the product, place, event, recipe, book, music, movie, article or post
   a capture is about.
3. **Cloud assist, off by default.** On devices without the on-device model,
   the text Pool read (never the image) can be sent to Pool's service for the
   same naming step. It needs `allowsCloudAssist` in both the configuration and
   the grant.

Captures that look like identity documents, payment cards, credentials or
health records are held back before step 1 finishes: they are never returned
and never sent anywhere.

## Indexing, models and control

```swift
var options = IndexOptions(
    window: .growing(from: .months(3)),   // or .sliding(.weeks(6)), .everything
    mediaTypes: [.photos, .screenshots, .videos],
    focus: .everything,                    // or .food
    maxPhotos: 20_000,
    allowsCellular: false,
    places: true
)
let pool = try await PoolClient.open(configuration: .init(appKey: "pk_live_…", indexOptions: options))
options.focus = .food
try await pool.sources.setIndexOptions(options)   // applied in place
```

A growing window starts that far back from the first index and keeps everything
new; a sliding one drops what falls out of it. Videos are read from a still
frame and screen recordings are never indexed. `savedVideos: false` leaves out
videos without a location, which PhotoKit cannot otherwise tell from saved
ones. A food focus returns only food and drink photos and food screenshots;
changing the focus hides or reads again what it changes. Turning `places` off
deletes every coordinate, city and visit at once.

PoolKit checks its key with the service when it opens, before indexing runs (at
most every 15 minutes) and at most once a day when the app comes to the front.
Only a key the service calls invalid stops PoolKit; a network error never does.
An app turned off or waiting for approval in the dashboard loses cloud assist
and keeps everything on the device. While a rotated key is in its grace
period, PoolKit logs when it stops working. A key refused for 30 days in a row
deletes the local index; downloaded models stay.

With `sendsRunReports` on, each indexing run sends a short report to Pool's
service: its kind (first, update, background, rebuild), how it ended, a
`PoolError` case name when it failed, its duration, counts, step timings, peak
memory, and the SDK, iOS and device model. Never a photo id, text or place, and
never on cellular unless `allowsCellular`. Your dashboard and the developer MCP
server show them.

Indexing runs while your app is open. It slows down while the device is hot or
in Low Power Mode and keeps going. If a pass fails, `status.phase` is `paused`,
`status.pauseReason` is `failed` with a short `failureDescription` for your
logs, and Pool tries again by itself.

```swift
for await status in await pool.sources.statusUpdates() {
    print(status.indexedAssets, status.knownAssets, status.visuallyIndexedAssets, status.models)
}

await pool.sources.pause()      // until resume(), across launches; queries keep working
await pool.sources.resume()
try await pool.sources.deleteIndex()  // deletes the index; grants, settings and models stay
try await pool.reset()          // deletes the index, grants, models and install ID
```

`status.detail` says where indexing stands: the `step` (starting,
loadingModels, readingLibrary, indexing, finishing), `indexed`, `total` and
`fraction`, whether search is usable yet (`searchable`, true after the first
slice), what it is `waitingFor` (places, textModel, people, coolingDown,
retryingBatch, events), how many captures were `skipped` or `failed` to read,
`skippedSensitive` counts per kind (personalData, health, nudity,
financialInformation, authentication; counts only, never which captures),
`secondsRemaining` while a run is going, `searchUpdatedAt` and whether it runs
in the `background`. `status.lastRun` says how the last run ended (completed,
stopped, endedByIOS, failed, interrupted, waiting) and when it tries again.

```swift
for await batch in try await pool.sources.batches(using: grant) {
    // About a hundred new captures at a time: id, mediaType, date, labels.
}
```

Batches carry only the sources the grant covers, and labels only when it may
read evidence. Sensitive and out-of-focus captures are left out, and shots of
one moment appear once.

`PoolConfiguration` sets the rest: `modelDownloads` (`.unmeteredOnly` by
default, `.anyNetwork` or `.never`), `maximumAssets` to index only the newest
captures, and `indexWindow`.

To index while the app is closed, list an identifier under
`BGTaskSchedulerPermittedIdentifiers`, add `processing` to `UIBackgroundModes`,
and register it before launch finishes:

```swift
pool.sources.registerBackgroundIndexing(identifier: "com.example.app.pool.index")
// or, before a client exists, reading PoolKitBackgroundTaskIdentifier from Info.plist:
PoolSources.registerBackgroundTasks()
```

Also list `<bundle id>.pool.update`, which keeps an indexed library up to date, and
`<bundle id>.pool.continue.*`, which on iOS 26 lets the first index carry on after the
person leaves the app, with `IndexOptions.backgroundProgress` as the title and "n of m"
as the subtitle the system shows. Before iOS 26 PoolKit asks for the time iOS grants to
finish the current slice. A run iOS ends early shows as `endedByIOS` and the next one
resumes where it stopped; after a failed run the next background attempt waits ten minutes.
Tasks registered before a client exists wait up to 20 seconds for the app to open it.

## Testing

`FixtureSource` stands in for the photo library, so tests need no simulator
photos, no app key and no network:

```swift
let source = FixtureSource(assets: [
    FixtureAsset(text: ["Nike Air Max 90", "€149.99", "www.nike.com/air-max-90"]),
])
let pool = try await PoolClient.preview(source: source)
let grant = try await pool.authorization.requestAccess(AccessRequest(purpose: "Tests"))
await pool.sources.indexNow()
let result = try await pool.context.query("nike", using: grant)
```

## CocoaPods

```ruby
pod 'PoolKit', '~> 0.2.0'
```

## React Native and Expo

PoolKit for React Native wraps this framework as an Expo module,
`@randomaccessmemories/pool-kit` on npm:

```bash
npx expo install @randomaccessmemories/pool-kit
```

See https://docs.pool.day for setup.

## Preview

0.2.0 is a preview. Until Pool's production launch the hosted service runs on
staging: open the client with `environment: .staging` and a staging key from
https://pool.day/developers. Everything on the device works without the service.

## Licence

PoolKit is commercial software; see `LICENSE`. Third-party notices are in `NOTICE`.

Full documentation: https://docs.pool.day · Changelog: https://docs.pool.day/changelog
