# Working on Spliit for iOS

A SwiftUI rewrite of the Spliit iOS app, shipping as an in-place update to the existing App
Store listing under the same bundle ID. See [ROADMAP.md](ROADMAP.md) for what's planned and
[README.md](README.md) for the full picture.

## How work happens here

**Never commit to `main`, and never edit the main worktree.** Every change — however small —
starts in a git worktree and lands through a pull request.

```sh
git worktree add .claude/worktrees/<short-name> -b <short-name> origin/main
```

Work there, push the branch, open a PR with `gh pr create`. Open it as a **draft** while it's
in progress; mark it ready for review when it's actually ready, because that is what triggers
the end-to-end suite (see below). When the PR merges, run `make sim-clean` and remove the
worktree.

Several worktrees can build and test at the same time. Each drives a simulator of its own,
named after its directory, and they share one Spliit server — see *Testing* below.

## Commands

Xcode is never required — everything runs from the Makefile. Run `make` for the full list.

```sh
make test         # unit suites on the host, ~2s, no simulator
make build        # build for the simulator
make e2e-up       # the shared Spliit server on :3009 (Docker), if it isn't already up
make test-live    # API client against that server, including writes
make e2e          # UI tests against it; leaves the server running
make e2e-down     # stop the server — only when nothing else is testing
make run          # install and launch on this worktree's simulator
make device       # build signed, install and launch on a connected iPhone
make shot         # screenshot this worktree's simulator
make sim-clean    # delete this worktree's simulator, and any leftover clones
make fixtures     # re-record the API fixtures the unit tests decode
```

`Spliit.xcodeproj` is **generated from `project.yml`** and is not in version control. Run
`make generate` after changing a target, a build setting or a resource. Adding a source file
needs nothing — the whole `Spliit/` folder is picked up. Never hand-edit the `.xcodeproj`.

## Layout

```
Spliit/              app target: SwiftUI views, assets, string catalog, analytics
Shared/              code shared with the UI test bundle (accessibility identifiers)
Packages/SpliitKit/
  SpliitAPI/         tRPC client, superjson coding, models, endpoints
  SpliitCore/        stores, the React Native migration, form drafts, formatting
SpliitUITests/       XCUITest end-to-end suites
e2e/                 the disposable server: compose file and seed script
```

Logic that can live in `SpliitKit` should: those suites run in seconds without a simulator.
Form validation lives in `SpliitCore` as pure `*FormDraft` types for exactly this reason.

## Things that will bite you

These all cost real debugging time already. They are in priority order of how silently they
fail.

**`accessibilityIdentifier` on a container stamps every descendant and overrides inner ones.**
A screen-level identifier on a `NavigationStack` erases the identifier of every button beneath
it, and the elements simply stop matching. Put identifiers on leaves only. They all live in
`Shared/AccessibilityID.swift`, and go in the same commit as the view.

**A `NavigationStack` nested inside a `TabView` tab silently refuses to push.** No error, no
crash — the link just no-ops. The pushed screen already owns the navigation bar; tab contents
must not create their own stack.

**Never write an unbounded loop in a UI test.** `while !element.isHittable { app.swipeUp() }`
turned a missing element into a CI job that swiped for 40 minutes. Bound the loop and assert.
Test runs pass `-maximum-test-execution-time-allowance 180` as a backstop.

**`simctl … booted` is a coin toss.** A test run has clones of its own booted, and another
worktree may have a simulator up as well, so `booted` can resolve to any of them — you get a
screenshot of the wrong device, or install into a clone that is about to be deleted. Name the
device: the Makefile targets `$(SIM_NAME)`, this worktree's own.

**Do not `make e2e-down` while another worktree is testing.** The server is shared and its
database lives in tmpfs, so stopping it discards the data of every run in flight. `make e2e`
deliberately leaves it up.

**Money is always integer minor units.** `amount == 1234` means 12.34. And `paidFor[].shares`
changes meaning with the split mode: the share value ×100 for `EVENLY`, `BY_SHARES` and
`BY_PERCENTAGE`, but a **raw minor-unit amount** for `BY_AMOUNT`.

**Decoding ignores superjson's `meta.values`.** Our models are statically typed, so a field the
server annotates as a `Date` is already declared `Date`. This is not a shortcut: `groups.list`
sends `createdAt` with no annotation at all, so trusting the metadata would break exactly one
endpoint. Encoding *does* emit annotations, and `make test-live` is what proves the server
accepts them.

**`Category`, `Group` and `Tab` all collide with system types.** The model is `ExpenseCategory`;
`SpliitAPI.Group` needs spelling out in files that also use SwiftUI's `Group`.

**Version numbers come from App Store Connect, not from `../spliit-mobile`.** That checkout
says 1.1.0; the App Store has 1.2.0 (build 20). `CURRENT_PROJECT_VERSION` must exceed the
shipped build.

**The migration from the React Native app must never throw.** It runs once, unattended, and a
group is only reachable by its ID — a user who loses their list cannot get it back. It also
must never delete the legacy files. `LegacyDataMigration` returns problems rather than
throwing; keep it that way.

## Testing

Three layers. Add to whichever is cheapest for what you're covering.

| Layer | Covers | Needs |
|---|---|---|
| `make test` | coding, decoding, request building, migration, money, validation | nothing |
| `make test-live` | the API client against a real server, including writes | `make e2e-up` |
| `make e2e` | the app itself, in a simulator, against a real server | Docker |

API fixtures under `Packages/SpliitKit/Tests/SpliitAPITests/Fixtures` are **recorded from a
real server** by `make fixtures`, never hand-written — hand-written fixtures only prove the
decoder agrees with our own assumptions.

**Keep UI test classes small and similar in size.** XCUITest parallelises by class, cloning a
simulator per worker, so a single large class is a long pole no worker count can shorten. Put a
new flow in the suite it belongs to, and split a suite once it grows past five or six tests.
Override the worker count with `make e2e WORKERS=n`; more workers than cores is slower, not
faster.

**Several worktrees can test at once.** Each drives a simulator named after its directory, so
runs never share a device — or the clones XCUITest makes from it. They do share the server, and
that is fine: every group is addressed by the ID the server assigned, and `groups.list` takes
those IDs as input, so no run can see another's data. Bring it up once with `make e2e-up`;
`make e2e` leaves it running. Lower `WORKERS` when several runs are in flight, because the sum
of their clones is what has to fit on the machine.

## CI

`unit` and `build` run on every push and every pull request. **`e2e` runs only on pull requests
that are not drafts**, because it takes 10–20 minutes; marking a PR ready for review triggers
it. `upstream-drift` runs nightly against the latest Spliit server to catch API changes.

GitHub's macOS runners cannot run Docker — they are VMs and cannot nest virtualization — so CI
runs Postgres from Homebrew and the Spliit server from source in dev mode. Docker stays the
local path.

## Style

Match the surrounding code. Comments explain *why*, not what; a comment that restates the line
above it should be deleted. Doc comments on public API earn their place by saying something the
signature does not.

No third-party dependencies without a good reason — it keeps builds fast, CI simple and the
review surface small.

All user-facing strings are `LocalizedStringKey` or `String(localized:)`. In `SpliitCore` they
need `bundle: Bundle.module`, or they resolve against the app bundle and can never be
translated.
