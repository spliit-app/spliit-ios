# Working on Spliit for iOS

A SwiftUI rewrite of the Spliit iOS app, shipping as an in-place update to the existing App
Store listing under the same bundle ID. See [ROADMAP.md](ROADMAP.md) for what's planned,
[DESIGN.md](DESIGN.md) before touching a view, and [README.md](README.md) for the full picture.

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
make strings      # check the string catalogues against the strings in the source
make e2e-up       # the shared Spliit server on :3009 (Docker), if it isn't already up
make test-live    # API client against that server, including writes
make e2e          # UI tests against it; leaves the server running
make e2e-down     # stop the server — only when nothing else is testing
make run          # install and launch on this worktree's simulator
make device       # build signed, install and launch on a connected iPhone
make shot         # screenshot this worktree's simulator
make sim-clean    # delete this worktree's simulator, and any leftover clones
make fixtures     # re-record the API fixtures the unit tests decode
make screenshots  # regenerate the App Store screenshots, in both languages
make testflight   # archive, export and upload a build to TestFlight
```

## Releasing

`make testflight` archives in Release, exports an App Store `.ipa` to `build/export/` and
uploads it. The two halves are separate targets — `make archive` and `make ipa` — so a
rejected upload retries in seconds instead of rebuilding.

The upload authenticates with the App Store Connect API key in
`~/.appstoreconnect/private_keys/`. `altool` finds the `.p8` itself from `ASC_KEY_ID`, but the
issuer ID pairs with it and lives only in App Store Connect, so it comes from the environment:

```sh
export ASC_ISSUER_ID=<uuid>   # appstoreconnect.apple.com/access/integrations/api
make testflight
```

**Bump `CURRENT_PROJECT_VERSION` in `project.yml` before every upload.** App Store Connect
rejects a build number it has already seen, and it rejects it *after* the upload finishes
rather than before it starts. `ExportOptions.plist` sets `manageAppVersionAndBuildNumber` to
false on purpose: left true, Xcode bumps the number inside the `.ipa` and `project.yml` — the
source of truth — silently stops matching what shipped.

`Spliit.xcodeproj` is **generated from `project.yml`** and is not in version control. Run
`make generate` after changing a target, a build setting or a resource. Adding a source file
needs nothing — the whole `Spliit/` folder is picked up. Never hand-edit the `.xcodeproj`.

## Layout

```
Spliit/              app target: SwiftUI views, assets, string catalogues, analytics
Shared/              code shared with the UI test bundle (accessibility identifiers)
Packages/SpliitKit/
  SpliitAPI/         tRPC client, superjson coding, models, endpoints
  SpliitCore/        stores, the React Native migration, form drafts, formatting
SpliitUITests/       XCUITest end-to-end suites
Scripts/             what the Makefile reaches for that isn't one line of shell
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

**Money is integer minor units — and minor units are not always hundredths.** `amount == 1234`
is 12.34 in a two-decimal currency and ¥1,234 in a group denominated in yen. The group's ISO
code is what decides, and 34 of the 159 currencies in the picker have no minor unit at all
while 6 have three. Never divide by 100: ask `MoneyFormatter.minorUnitDigits(forCurrencyCode:)`,
or use the formatter, which already has. A group with only a symbol and no code is hundredths,
because that is what it was stored as.

`paidFor[].shares` changes meaning with the split mode: the share value ×100 for `EVENLY`,
`BY_SHARES` and `BY_PERCENTAGE` — whatever the currency — but a **raw minor-unit amount** for
`BY_AMOUNT`, which does scale with it.

An expense paid in another currency carries **two amounts on two different scales**:
`originalAmount` is in `originalCurrency`'s minor units and `amount` is in the group's. A €40.00
dinner in a yen group is `originalAmount == 4000` and `amount == 6540`. `ExpenseFormDraft` asks
each currency for its own precision; only the group's belongs to the group.

**A nil optional is omitted from the request, and the server then leaves that column alone.**
Swift's synthesised encoding uses `encodeIfPresent`, so nil never reaches the wire; tRPC reads
it as `undefined` and Prisma skips the field. Clearing something therefore means sending an
empty value, not nil — `GroupFormDraft.formValues` sends `""` for a currency code the user
dropped, which is what the web app writes too.

**And what counts as an empty value is per field.** `ExpenseFormValues` writes an explicit
`null` for `originalCurrency`, the only one of the three conversion fields whose zod schema
takes one; `originalAmount` and `conversionRate` accept a number, a numeric string or `''`, and
reject null with a 400. So an expense that stops being converted keeps those two in the database
with nothing reading them — the currency is what says an expense was paid in another one, and
`ExpenseFormDraft(editing:)` ignores the other two without it. `make test-live` is what found
this; nothing local would have.

**A recurrence you switch off does not always switch off.** Nothing repeats on a timer: the
server makes the next expense in a series lazily, inside `groups.expenses.list`, and stamps
`nextExpenseCreatedAt` on the `RecurringExpenseLink` it just acted on. From that moment the link
is frozen. `groups.expenses.update` will only create, move or delete a schedule while the link is
*unstamped* — against a stamped one it writes the `recurrenceRule` column and changes nothing
that is scheduled. So setting last month's rent to "Never" succeeds, looks right, and next
month's rent still arrives, because the series is being carried by the newest expense and its own
pending link. `ExpenseFormDraft.hasAlreadyRepeated` is that distinction, and the form says it out
loud rather than letting somebody find out in four weeks.

**And the next date is not simply the rule applied to the date on screen.** Three different
answers, all from `calculateNextDate`. Creating an expense, or giving one a recurrence it never
had, counts from the date being saved. Changing the *rule* on a pending link recounts from the
date the expense **already had** — `existingExpense.expenseDate`, not the one in the same
request. And changing only the date, leaving the rule alone, does not move the schedule at all,
because the update is gated on the rule having changed. `nextRecurrenceDate` reproduces all
three; `make test` pins them.

**A monthly series gives up a day it cannot fit, and never gets it back.** Each step is measured
from the expense before it rather than from the first one, so the 31st of January comes round on
the 28th of February — and then the 28th of March, not the 31st. `RecurrenceRule.nextDate(after:)`
mirrors it with `Calendar.date(byAdding: .month)`, which clamps identically, **in UTC**, which is
where the server counts. The web app records the drift as a limitation of its own arithmetic
rather than a decision, but it is the behaviour, and `make test-live` is what proved the two
agree — nothing local would have.

**`groups.balances.list` does not tell you what anyone paid.** It returns the web app's
*public* balances — derived from the suggested payments, not from the expenses — so `paid` is
what a participant will be handed when the group settles and `paidFor` is what they will hand
over. One of the two is always zero and the other is `abs(total)`; the recorded fixture shows
it. Only `total` means anything. What was actually paid, and what was actually spent on
someone, comes from `groups.stats.get` with a `participantId`.

**`totalParticipantShare` is the one amount that is not an `Int`, and has to stay that way.**
Today's server sends a whole number of minor units — the web app's *Shares* change apportions
every share in whole units and stops rounding the sum. An instance older than that sums
floating-point thirds and rounds to two decimals, so it sends `1416.67`, and `Int` does not
decode that: it throws, and takes the whole totals tab with it. The DTO is `Double?` and the
rounding happens on the way to the display. `Int(exactly:)` on the way, never `Int(_:)` — that
one traps rather than returning nil.

**A procedure the instance has never heard of is not a failure to report.** `TRPCServerError`
has `isUnknownProcedure` for it, and the totals tab is what uses it: a self-hosted instance too
old for `groups.stats.get` — or, when upstream deploys what its `main` already has, too new for
it — gets a screen that says so, rather than an error with a "Try again" that can never work.
Any new endpoint should degrade the same way.
**Who did it is something you have to tell the server.** `groups.update` and all three
`groups.expenses.*` mutations take an optional `participantId`, and it is the only thing the
activity log has to name anybody with. Leave it out and the call still succeeds, the expense is
still written, and every line about it reads "Someone" — for good, since nothing backfills it.
`RecentGroupsStore.actorID(inGroup:participants:)` is what resolves it; a write that does not
pass one is a write nobody will ever be able to attribute.

**An activity's `data` is the expense's title as it was, not as it is.** That is deliberate — a
rename must not rewrite the line describing the creation — so the log is the one place in the
app showing a title the expense no longer has. The `expense` sent beside each activity is `null`
once it has been deleted, and that, not `expenseId`, is what says whether a row can be opened.

**A presentation belongs to a view that keeps its identity.** `.sheet`, `.fullScreenCover` and
`.photosPicker` attached to a row whose content swaps — a menu that becomes a progress indicator
while the work runs — rebuild the presenter in the same update that dismisses it, and the
stranded dismissal lands on the *next* thing presented. The receipt scanner shipped like this:
photograph a receipt, open the camera again, and it closed itself immediately; a third attempt
worked. Keep one view for the row and let state change what it says, not which view it is. Let
presented content close itself with `@Environment(\.dismiss)` rather than writing the caller's
`isPresented` binding from a delegate, so only one thing can dismiss it. A simulator has no
camera, so no UI test will catch this for you.

**A `Binding` is only as fresh as its getter.** `Binding(get: { form }, set: { self.form = $0 })`
over an unwrapped `if let` constant looks like a binding and is a snapshot: the getter closes over
the value the body was built with, so it keeps answering with that one however many times it is
written to in between. Anything that writes and then reads back within the same turn reads its own
write away. It cost two bugs in one screen — two receipts uploaded together landed as one, because
the second `append` started from an array without the first, and the document viewer removed a
document, asked whether any were left, was told yes and stayed open on nothing. `ExpenseFormView`
now hands down `liveForm`, whose getter reads `self.form`.

**Expense documents are the one thing that doesn't go through tRPC.** The instance signs an upload
at `POST /api/s3-upload` — a REST route `next-s3-upload` puts beside the tRPC one — and the bytes
go from the phone straight to the bucket; tRPC only ever sees the URL the object ended up at.
Three things follow. The **upload happens before the expense is saved**, so an abandoned form
leaves an object nothing points at, and **removing a document only forgets its URL**, because
neither this app nor the web app has credentials to delete anything. And the **address is derived,
not returned**: `endpoint` set means `<endpoint>/<bucket>/<key>`, otherwise
`https://<bucket>.s3.<region>.amazonaws.com/<key>`. Both products have to derive the same one,
because either may have been the one that attached it.

**Document storage is optional, and there is no way to ask.** The signing route is compiled in
whether or not a bucket is configured, and the flag saying so is server-side and never exposed
over tRPC — so the answer only ever arrives as a failed upload: 500 with an empty body, which is
what `NextResponse.error()` produces. `DocumentUploader.Failure.unsupported` is that, and it is
not an error to retry; `AppModel.noteDocumentStorageIsUnavailable()` remembers it for the session
so the next expense doesn't offer the same dead end. A self-hosted instance without a bucket is
entirely ordinary.

**Vision's `transcript` is not the receipt's layout.** `RecognizeDocumentsRequest` reads a
receipt the way it reads a page — as blocks in reading order — so a two-column till slip comes
back as a column of labels followed by a column of prices, and `TOTAL` lands nine lines from the
`15,95` printed beside it. Reading that as text finds the wrong number, or the right one by luck.
`ReceiptText.rows(of:)` rebuilds the rows from where each run of text actually sits: two runs are
on the same row when their vertical middles are closer than half the height of the shorter one.
Its fixture is recorded from real Vision output, not invented.

**Nothing the on-device model says is taken on trust.** A receipt is untrusted text — anything at
all can be printed on one — so `ReceiptScanner` re-checks every field it answers with: the total
goes back through the same number parser the receipt's own numbers do, the date through the same
plausibility window, and the category has to be one `categories.list` actually returned. The model
is also never the only reader: `ReceiptText` parses the transcript unaided, which is the whole
feature on a phone without Apple Intelligence and the fallback under the model everywhere else.

**Decoding ignores superjson's `meta.values`.** Our models are statically typed, so a field the
server annotates as a `Date` is already declared `Date`. This is not a shortcut: `groups.list`
sends `createdAt` with no annotation at all, so trusting the metadata would break exactly one
endpoint. Encoding *does* emit annotations, and `make test-live` is what proves the server
accepts them.

**`Category`, `Group` and `Tab` all collide with system types.** The model is `ExpenseCategory`;
`SpliitAPI.Group` needs spelling out in files that also use SwiftUI's `Group`.

**Version numbers come from App Store Connect, not from `../spliit-mobile`.** That checkout
says 1.1.0 and is years behind; 2.0.0 is approved on the App Store. `CURRENT_PROJECT_VERSION`
must exceed the shipped build.

**And a bumped build number is only enough while the train is open.** Once a
`MARKETING_VERSION` is *approved*, App Store Connect closes it: every further build for it is
refused with 90186, "the train version is closed for new build submissions", alongside 90062
saying `CFBundleShortVersionString` must exceed the approved version. So the first upload after
a release bumps both numbers — and, like a duplicate build number, it is rejected only after
the whole `.ipa` has finished uploading. `make ipa` then `xcrun altool --upload-app` retries the
upload alone; `make testflight` re-archives from scratch.

**The recent-groups list is in iCloud, and that costs an App ID capability.**
`Spliit.entitlements` claims `com.apple.developer.ubiquity-kvstore-identifier`, so an archive is
refused until iCloud with *Key-value storage* is enabled on the App ID —
`make build-device` passes `-allowProvisioningUpdates` and will add it, but `make testflight`
will not. Simulator builds and CI never notice: they build with `CODE_SIGNING_ALLOWED=NO`, the
entitlement is not applied, and `NSUbiquitousKeyValueStore` then stores nothing at all. That is
also the behaviour on a phone signed out of iCloud, and it is deliberate — every path here
degrades to the local file rather than to an error.

**And a synced list cannot simply be replaced by the newer one.** Two phones with two lists have
no obvious loser: a group is reachable only by its ID, so dropping one drops it for good.
`RecentGroupsSnapshot.merging` keeps the union, settles a group both sides have by
`RecentGroup.updatedAt` — which is why **every mutation has to stamp it**, including the ones
that don't change the order — and orders by `lastOpenedAt`, which only opening a group touches.
Deletions are the exception the union can't express, so `forget` leaves a tombstone; without
one, the other phone puts the group straight back. Tombstones live in the iCloud payload only,
never in the file, and expire after 90 days. UI tests run with no cloud at all
(`-uiTestRun`, added on every launch), because a simulator signed into a real account would
merge somebody's actual groups into a seeded list.

**The migration from the React Native app must never throw.** It runs once, unattended, and a
group is only reachable by its ID — a user who loses their list cannot get it back. It also
must never delete the legacy files. `LegacyDataMigration` returns problems rather than
throwing; keep it that way.

**Nothing adds a new string to the catalogue for you.** Xcode does it on its own builds; this
project is built by `xcodebuild`, which does not write back to the source `.xcstrings`. So a
`Text("…")` you add today compiles, ships and displays — in English, in every language, with no
warning anywhere. The catalogue had 21 of its 166 keys by the time anyone looked. **Run `make
strings`**: it diffs the catalogues against what the compiler actually extracted and names
every string that is missing, stale or untranslated. It is in CI on every push, so a new string
without French fails the build rather than shipping silently.

## Testing

Three layers. Add to whichever is cheapest for what you're covering.

| Layer | Covers | Needs |
|---|---|---|
| `make test` | coding, decoding, request building, migration, money, validation | nothing |
| `make test-live` | the API client against a real server, including writes | `make e2e-up` |
| `make e2e` | the app itself, in a simulator, against a real server | Docker |

`make e2e-up` brings object storage up beside the server, because expense documents do not live in
Spliit's database and a stubbed upload would only prove the app can talk to itself. CI starts the
same thing from pinned binaries, Docker being unavailable there. An instance without a bucket is
still worth pointing at: the document suites then cover the path where the app says so.

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
translated. The app ships English and French, so **a new string needs its French in the same
commit** — `make strings` is what tells you which ones are outstanding.

Never build a sentence by concatenation, and never pick a plural form with a ternary: word
order and plural categories are both the translation's business, not the call site's. Interpolate
the whole thing (`String(localized: "\(count) participants")`) and let the catalogue vary it.

Leave to Foundation anything a locale already decides — currency names and symbols, money,
dates, and lists (`.formatted(.list(type: .and))`). None of it belongs in a catalogue. Sort
anything a person reads with `localizedStandardCompare`, not `<`.

**Expense categories are server data, and the server does not translate them.** They are
translated on the client from `Categories.xcstrings`, with the French taken from the web app's
`messages/fr-FR.json` so both products say the same thing. `ExpenseCategoryName` is keyed the
way `ExpenseCategoryIcon` is and `CategoryIconTests` keeps the two maps level; an unknown
category falls back to the server's own English rather than to nothing.
