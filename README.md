# Spliit for iOS

A SwiftUI rewrite of the [Spliit](https://spliit.app) mobile app, shipping as an in-place
update to the existing App Store listing.

It replaces the Expo / React Native app (v1.1.0) under the same bundle ID,
`app.spliit.spliitmobile`, and migrates the data that app left on disk. See
[ROADMAP.md](ROADMAP.md) for what's planned and why, and [DESIGN.md](DESIGN.md) for what the
app looks like and which of those choices are load-bearing.

**Requirements:** Xcode 26, iOS 26 deployment target, Docker for the end-to-end suite.

---

## Getting started

```sh
make setup        # installs XcodeGen
make test         # unit tests on the host — a couple of seconds, no simulator
make build        # build the app for the simulator
```

You never need to open Xcode. `Spliit.xcodeproj` is **generated** from
[`project.yml`](project.yml) and is not in version control — run `make generate` after
changing a target, a build setting or a resource. Adding a source file needs nothing: the
whole `Spliit/` folder is picked up.

Run `make` on its own to list every task.

## Running the app

```sh
make e2e-up       # a throwaway Spliit instance on :3009
make e2e-seed     # some groups and expenses to look at
make run          # build, install and launch on this worktree's simulator
make shot         # screenshot it
```

Every worktree gets a simulator of its own, named after its directory — `Spliit my-branch` —
so that runs in different worktrees stay out of each other's way. `make sim-clean` removes it
when you are done with the worktree.

To point the app somewhere else, override the address:

```sh
make run E2E_URL=https://spliit.app/
```

## Testing

Three layers, all runnable from the command line.

| Command | What it covers | Needs |
|---|---|---|
| `make test` | superjson coding, response decoding, request building, the storage migration, money formatting, date bucketing | nothing |
| `make strings` | every string in the source is in a catalogue, and translated | nothing |
| `make test-live` | the API client against a real server, including writes | `make e2e-up` |
| `make e2e` | the app itself, in a simulator, against a real server | Docker |

`make e2e` brings the server up if it isn't already, then runs the UI suite. It leaves the
server running — see below.

### Running several worktrees at once

```sh
make e2e-up            # once, from any worktree
make e2e WORKERS=2     # in each worktree, at the same time
```

Two things make that work. Each worktree drives **its own simulator**: two runs sharing one
device would install over each other, and XCUITest names its parallel clones after the device
they came from, so even the clones would collide.

And the **server is shared and long-lived**. One is enough — every group is addressed by the ID
the server assigned, and `groups.list` takes those IDs as input, so no run can see another's
data. What a run must not do is tear it down on its way out: the database lives in tmpfs, so
that would take every other run's data with it. `make e2e-down` stops it, deliberately, when
nothing is using it.

Nothing else is shared: build output goes to each worktree's own `build/`. Do watch `WORKERS`,
though — each run boots that many simulator clones, so the sum across runs is what has to fit
on the machine.

### Two things worth knowing

**Fixtures are recorded, not written.** The JSON under
`Packages/SpliitKit/Tests/SpliitAPITests/Fixtures` is captured from a real instance by
`make fixtures`. Hand-written fixtures only prove the decoder agrees with our own
assumptions; recorded ones prove it agrees with the server.

**Accessibility identifiers go on leaves, never containers.** SwiftUI's
`.accessibilityIdentifier` applies to every descendant of the view it modifies, and an outer
one silently replaces the identifiers set inside it — a screen-level identifier on a
`NavigationStack` erases the identifier of every button beneath it. All identifiers live in
[`Shared/AccessibilityID.swift`](Shared/AccessibilityID.swift), shared by the app and the test
bundle, and are added in the same commit as the view they belong to.

## Layout

```
Spliit/              the app: SwiftUI views, assets, the string catalogues
Shared/              code shared with the UI test bundle (accessibility identifiers)
Packages/SpliitKit/
  SpliitAPI/         tRPC client, superjson coding, models, endpoints
  SpliitCore/        stores, the React Native migration, formatting
SpliitUITests/       XCUITest end-to-end suites
Scripts/             what the Makefile reaches for that isn't one line of shell
e2e/                 the disposable server: compose file and seed script
```

`SpliitAPI` and `SpliitCore` are plain SwiftPM libraries with no third-party dependencies, so
the protocol handling, the money maths and the migration are all testable in seconds without
launching a simulator.

## How it talks to Spliit

Spliit's API is tRPC with the superjson transformer, at `{baseURL}api/trpc`. There is no REST
layer, so `SpliitAPI` speaks it directly: queries as `GET …?input=<envelope>`, mutations as
`POST`, both unbatched, which the server accepts.

Decoding ignores superjson's `meta.values` annotations — our models are statically typed, so a
field the server marks as a `Date` is already declared `Date` here. That is not a shortcut:
`groups.list` sends `createdAt` with no annotation at all, so relying on the metadata would
break exactly one endpoint.

Encoding does emit annotations, because the server rebuilds real `Date` instances before its
own validation runs. `make test-live` is what proves the envelopes we send are accepted.

**Money is integer minor units, and minor units are not always hundredths.** `amount == 1234`
is 12.34 in a two-decimal currency and ¥1,234 in a group counted in yen — the group's ISO
currency code decides, which is what `MoneyFormatter` reads it for. One more sharp edge:
`paidFor[].shares` is the share value ×100 for `EVENLY`, `BY_SHARES` and `BY_PERCENTAGE`
whatever the currency, but a raw minor-unit amount for `BY_AMOUNT`.

## Reading receipts

Photographing a receipt fills in the title, amount, date and category of a new expense, and it
all happens on the phone: Vision's `RecognizeDocumentsRequest` transcribes the picture and the
system language model reads the transcript. The web app posts the image to OpenAI from its
server instead, which costs money per scan, hands somebody's receipt to a third party, and does
nothing at all on a self-hosted instance with no API key. **No photo and no receipt leaves the
device**, and the feature works offline.

The model is never the only reader. `SpliitCore/ReceiptScan.swift` parses the transcript by the
rules receipts are printed by — no model and no network — which is the whole feature on a phone
without Apple Intelligence, the fallback under the model everywhere else, and the part `make
test` covers. Nothing the model answers is trusted verbatim either: every field it gives back is
re-checked by the same code that reads the receipt itself.

The photo is not kept. Attaching receipts to expenses is a separate feature the web app has and
this app does not yet.

## Languages

English and French. Both come from String Catalogs — `Spliit/Resources/Localizable.xcstrings`
for the app, `AppShortcuts.xcstrings` for the phrases Siri listens for, `Categories.xcstrings`
for the expense categories, and one inside `SpliitCore` for the form validation messages, which
needs to be its own because `String(localized:)` there resolves against `Bundle.module`.

**Categories are translated on the client**, because the server does not translate them:
`categories.list` returns "Groceries" to everyone. The web app has the same problem and solves
it the same way, so the French here is lifted from its `messages/fr-FR.json` — a category should
read the same in the app as on the site the group was made on. `ExpenseCategoryName` is keyed
exactly as `ExpenseCategoryIcon` is, and a test holds the two maps to the same set so a category
cannot keep its glyph while losing its word. One the app has never seen falls back to whatever
the server sent, which matters because instances are self-hosted and that table is seeded data.

Everything a locale decides is left to the system rather than translated: currency names and
symbols come from Foundation, so the 159-entry picker is in the user's language with no table
in this repo; amounts, dates and lists ("Ana et Bruno") are formatted by it too. Counted
strings are pluralised by the catalogue, not by a ternary in Swift — French counts zero as
singular, and English does not. Lists that people read are sorted with
`localizedStandardCompare`, or "Épicerie" sorts after "Vêtements" on the strength of its accent.

`make strings` is what keeps this honest. `xcodebuild` will not add a new string to a catalogue
the way the Xcode UI does, so a `Text("…")` added today would otherwise ship in English in
every language, silently. The check diffs the catalogues against the strings the compiler
actually extracted and fails on anything missing, stale or untranslated; CI runs it on every
push.

## The App Store listing

Everything App Store Connect asks for lives in
[`Docs/app-store/metadata.md`](Docs/app-store/metadata.md) — the copy in both languages, the
review notes, the App Privacy answers, and what is still outstanding before a build can be
submitted.

The screenshots beside it are generated, not taken by hand:

```sh
make screenshots                              # both languages, iPhone and iPad, ~6 min
Scripts/screenshots.sh --languages fr         # or one of them
```

It drives `SpliitUITests/ScreenshotTests` against the throwaway instance, once per language,
with `-testLanguage` — so the demo group is called "Weekend in Lisbon" in one run and
"Week-end à Lisbonne" in the next, and the interface agrees with it. The simulator is pinned to
9:41 and light appearance, and the run fails if a picture comes out at a size App Store Connect
would reject. `make e2e` skips that suite; it is not a test.

## Migrating from the React Native app

The old app stored two keys — `recent-groups` and `spliit-settings` — through AsyncStorage, in
`Application Support/app.spliit.spliitmobile/RCTAsyncLocalStorage_V1/`. Values of 1024
characters or fewer sit inline in `manifest.json`; longer ones have `null` there and live in a
sibling file named the lowercase hex MD5 of the key. A user with roughly fifteen or more
recent groups crosses that threshold, so both paths are implemented and both are tested.

This runs once, unattended, and groups are only reachable by ID — a user who loses their list
cannot get it back. So the migration never throws, never overwrites data this app already has,
and never deletes the legacy files.
