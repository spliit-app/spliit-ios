# End-to-end harness

A disposable Spliit instance for the UI tests, and the script that fills it with known data.

```sh
make e2e-up      # start it on :3009
make e2e-seed    # add fixture groups and expenses
make e2e-down    # stop it and discard everything
```

## What's here

**`compose.yaml`** runs the published `ghcr.io/spliit-app/spliit` image against Postgres. The
database lives in tmpfs, so every `up` starts from an empty schema and no test can inherit
state from a previous run. Port 3009 keeps it clear of a Spliit dev server on the usual 3000.

**`seed.mjs`** creates groups, participants and expenses through the public tRPC API rather
than through SQL. That keeps the harness decoupled from Prisma migrations, and means it works
against any instance — including a self-hosted one you want to smoke-test.

It prints a JSON map of fixture keys to the IDs the server assigned:

```sh
node seed.mjs --base-url http://localhost:3009/
```

The fixture set covers the cases the app has to get right: a group with all four split modes
including `BY_AMOUNT` and `BY_PERCENTAGE`, expenses spread across the date buckets (this week,
last month, last year), a two-person group, and a group with no expenses at all.

## Recording API fixtures

The unit tests decode real recorded responses rather than hand-written JSON:

```sh
make e2e-up
make fixtures
```

That rewrites `Packages/SpliitKit/Tests/SpliitAPITests/Fixtures/*.json` with raw, unmodified
responses. Assertions in those tests avoid the server-generated IDs, which change on every
re-record.

## Debugging a UI test without Xcode

When an element query doesn't match, don't guess — print the tree the app actually exposes.
Add a throwaway test:

```swift
final class TreeDumpTests: SpliitUITestCase {
    @MainActor
    func testDump() {
        let app = launchApp()
        sleep(2)
        print(app.debugDescription)
    }
}
```

```sh
make generate
xcodebuild test -project Spliit.xcodeproj -scheme Spliit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SpliitUITests/TreeDumpTests 2>&1 | grep -A 60 'Element subtree'
```

This is how the container-versus-leaf identifier problem described in the main README was
found: the identifiers were there, just stamped onto every descendant instead of one element.

## Launch arguments

The app reads these in `UITestSupport`, compiled only into debug builds.

| Argument | Effect |
|---|---|
| `-baseURL <url>` | Which instance to talk to. Read straight from `UserDefaults`, no test-only code involved. |
| `-uiTestResetState` | Clears recent groups, settings and any planted legacy store. |
| `-uiTestRecentGroups <json>` | Pre-populates the recent group list. |
| `-uiTestLegacyStore <json>` | Writes AsyncStorage key/values in the real on-disk format, so the migration path runs for real — including spilling long values to MD5-named sidecar files. |

One catch worth remembering: `-baseURL` lands in `UserDefaults`' **argument domain**, which
outranks every stored value. A test that checks which address the app *chose* — the migration
test, for instance — must not also be forcing that choice, so it passes
`overrideBaseURL: false`.
