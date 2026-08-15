# Spliit for iOS

A SwiftUI rewrite of the [Spliit](https://spliit.app) mobile app, shipping as an in-place
update to the existing App Store listing.

It replaces the Expo / React Native app (v1.1.0) under the same bundle ID,
`app.spliit.spliitmobile`, and migrates the data that app left on disk. See
[ROADMAP.md](ROADMAP.md) for what's planned and why.

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
make run          # build, install and launch on a simulator
make shot         # screenshot whatever is on screen
```

To point the app at a specific instance, pass `-baseURL`:

```sh
xcrun simctl launch booted app.spliit.spliitmobile -baseURL https://spliit.app/
```

## Testing

Three layers, all runnable from the command line.

| Command | What it covers | Needs |
|---|---|---|
| `make test` | superjson coding, response decoding, request building, the storage migration, money formatting, date bucketing | nothing |
| `make test-live` | the API client against a real server, including writes | `make e2e-up` |
| `make e2e` | the app itself, in a simulator, against a real server | Docker |

`make e2e` starts the server, runs the UI suite and tears the server down again, so it is
also what CI does.

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
Spliit/              the app: SwiftUI views, assets, the string catalog
Shared/              code shared with the UI test bundle (accessibility identifiers)
Packages/SpliitKit/
  SpliitAPI/         tRPC client, superjson coding, models, endpoints
  SpliitCore/        stores, the React Native migration, formatting
SpliitUITests/       XCUITest end-to-end suites
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

**Money is always integer minor units.** `amount == 1234` means 12.34. One sharp edge:
`paidFor[].shares` is the share value ×100 for `EVENLY`, `BY_SHARES` and `BY_PERCENTAGE`, but
a raw minor-unit amount for `BY_AMOUNT`.

## Migrating from the React Native app

The old app stored two keys — `recent-groups` and `spliit-settings` — through AsyncStorage, in
`Application Support/app.spliit.spliitmobile/RCTAsyncLocalStorage_V1/`. Values of 1024
characters or fewer sit inline in `manifest.json`; longer ones have `null` there and live in a
sibling file named the lowercase hex MD5 of the key. A user with roughly fifteen or more
recent groups crosses that threshold, so both paths are implemented and both are tested.

This runs once, unattended, and groups are only reachable by ID — a user who loses their list
cannot get it back. So the migration never throws, never overwrites data this app already has,
and never deletes the legacy files.
