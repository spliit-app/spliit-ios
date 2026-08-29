# Spliit for iOS — SwiftUI rewrite roadmap

A ground-up rewrite of the Spliit mobile app in SwiftUI, shipped as an in-place
update to the existing App Store listing.

- **Replaces:** `../spliit-mobile` (Expo / React Native 0.74, v1.1.0)
- **Reference implementation:** `../spliit` (Next.js web app)
- **Ships as:** bundle ID `app.spliit.spliitmobile`, version `2.0.0`

---

## 1. Goals

1. **Feature parity with the current mobile app** — the first shippable milestone.
2. **A UI that feels like iOS**, not like a web app in a wrapper. Native
   navigation, native controls, Liquid Glass, dark mode, Dynamic Type.
3. **End-to-end tests from day one**, not bolted on later.
4. **Eventually, feature parity with the web version.**

Non-goals for now: Android, iPad-optimised layouts (should not *break* on iPad,
but no split-view design work until M4), offline-first sync.

---

## 2. Decisions

| Decision | Choice | Consequence |
|---|---|---|
| Backend contract | Hand-written tRPC client over URLSession | No changes needed in the web repo; works against `spliit.app` and every self-hosted instance today. Models must be kept in sync by hand. |
| E2E harness | XCUITest against a real local backend | Faithful, first-party, no runtime deps. Needs Postgres + the Next.js app running in CI. |
| Minimum iOS | **iOS 26** | Full access to Liquid Glass, the newest SwiftUI, Swift 6.2 concurrency defaults, on-device Foundation Models and Vision document recognition. Users below iOS 26 keep receiving 1.1.0 via the App Store's last-compatible-version fallback — their data is untouched and they are not broken, just not updated. |
| Localization | String Catalog from the first commit; English and French | No large retrofit later; importing the rest of the web's 35 locales is a catalogue edit and nothing else. |

---

## 3. Constraints inherited from the shipped app

### 3.1 Identity

The new app must reuse the existing App Store record, so:

- `CFBundleIdentifier` = `app.spliit.spliitmobile` (unchanged)
- `CFBundleShortVersionString` → `2.0.0`, `CFBundleVersion` → `21` or higher.
  The App Store has **1.2.0 (build 20)**, not the 1.1.0 that `../spliit-mobile`
  claims — that checkout is behind what shipped, so treat App Store Connect as
  the source of truth for version numbers.
- Keep the custom URL scheme `app.spliit.spliitmobile`
- Port `PrivacyInfo.xcprivacy` (the RN app ships one)
- Keep `ITSAppUsesNonExemptEncryption = false`
- The Expo-specific bits (`exp+spliit-mobile` scheme, `NSUserActivityTypes`
  entry for `…expo.index_route`) can be dropped

### 3.2 Local storage that must survive the update

The RN app writes exactly **two** AsyncStorage keys:

| Key | Shape |
|---|---|
| `recent-groups` | `[{ "groupId": String, "groupName": String }]` |
| `spliit-settings` | `{ "baseUrl": String }` — defaults to `https://spliit.app/` |

On iOS, `@react-native-async-storage/async-storage@1.23.1` persists these to:

```
<container>/Library/Application Support/app.spliit.spliitmobile/RCTAsyncLocalStorage_V1/
├── manifest.json      → { "recent-groups": "<json string>", "spliit-settings": "<json string>" }
└── <md5(key)>         → sidecar file, only when a value exceeds 1024 characters
```

Rules, straight from `RNCAsyncStorage.mm`:

- Values **≤ 1024 characters** are stored **inline** in `manifest.json` as a
  JSON string.
- Values **> 1024 characters** have `null` as their manifest value, and the real
  content lives in a sibling file named the **lowercase hex MD5 of the key**:
  - `md5("recent-groups")` = `1cbcb324ae1107e8720de37fcf7616c1`
  - `md5("spliit-settings")` = `2109ef73d295fd69ac535e9f1380245a`
- A user with roughly 15+ recent groups will cross the threshold, so **both
  paths must be implemented** — this is not a theoretical branch.
- Belt and braces: also probe the deprecated locations
  (`Documents/RCTAsyncLocalStorage_V1`, `Documents/RNCAsyncLocalStorage_V1`,
  `Documents/RCTAsyncLocalStorage`) in case an install never ran a version that
  migrated them.

**Migration policy:** on first launch of 2.0.0, if the new store is absent and a
legacy manifest is present, import both keys, write the new store, and set a
`didMigrateFromReactNative` flag. **Do not delete the legacy files** — leave them
for at least one release.

### 3.3 Backend contract

The web app exposes tRPC v11 with the **superjson** transformer at
`{baseUrl}api/trpc`. Verified against production:

```
GET {base}/api/trpc/categories.list?input={"json":null,"meta":{"values":["undefined"]}}
→ {"result":{"data":{"json":{"categories":[…]}}}}
```

Unbatched requests work, so the Swift client does not need to implement
batching. Queries are `GET` with a URL-encoded `input`; mutations are `POST`
with `{"json": …}` as the body. Responses may carry a `meta.values` map marking
which fields were `Date`, `undefined`, or `Decimal` — the decoder has to apply
it, since `expenseDate` and `createdAt` arrive as ISO strings tagged this way.

Router surface available today:

```
groups.list / get / getDetails / create / update
groups.expenses.list / get / create / update / delete
groups.balances.list
groups.stats.get
groups.activities.list
categories.list
```

There is **no delete-group procedure** — the web app cannot delete groups
either, only remove them from the local recent list.

**Money is integer minor units** (`amount = 1234` means 12.34). One sharp edge
worth encoding in a test: `paidFor[].shares` is stored as the share value ×100
for `EVENLY`, `BY_SHARES` and `BY_PERCENTAGE`, but as a **raw minor-unit amount**
for `BY_AMOUNT`.

---

## 4. Architecture

```
spliit-new-mobile/
├── Spliit.xcodeproj
├── Spliit/                    # app target — SwiftUI views, assets, Info.plist
├── Packages/
│   ├── SpliitAPI/             # TRPCClient, DTOs, endpoint definitions
│   └── SpliitCore/            # domain models, storage, formatting, migration
├── SpliitTests/               # unit tests (Swift Testing)
├── SpliitUITests/             # XCUITest end-to-end suites
└── e2e/                       # backend harness: compose file, seed scripts
```

Keeping `SpliitAPI` and `SpliitCore` as local SwiftPM packages means the
protocol, the money maths and the AsyncStorage migration are all unit-testable
without launching a simulator.

**State:** `@Observable` stores, `async`/`await`, Swift 6.2 with
`MainActor`-by-default isolation. No third-party dependencies — it keeps builds
fast, CI simple, and the App Store review surface small.

**Navigation:**

- Root `NavigationStack` → groups list
- Group screen hosts a group-scoped `TabView` (Expenses, Balances) with
  `.tabBarMinimizeBehavior(.onScrollDown)`; it grows naturally into the web's
  six tabs later
- Sheets for create/edit expense, group settings, about
- ~~`.navigationTransition(.zoom(sourceID:in:))` from a group row into the
  group~~ — built, then taken back out: it read as showy next to a push, which
  is the movement iOS uses to say "deeper in". See [DESIGN.md](DESIGN.md) §6

**Persistence:**

- Settings → `UserDefaults`, so XCUITest can override them with launch
  arguments for free (`-baseURL http://localhost:3000/`)
- Recent groups → a small JSON file in Application Support, seedable in tests
  via a launch argument

**Design language:** brand `#059669` as the accent (secondary `#be185d`),
system materials everywhere else. Three of the specifics guessed at here did not
survive contact: empty states are the app's own `EmptyState` rather than
`ContentUnavailableView`, the balances view keeps its hand-rolled bars rather
than adopting `Charts`, and `.green`/`.red` gave way to a branded money axis.
What shipped is described in [DESIGN.md](DESIGN.md).

---

## 5. Testing strategy

Three layers, all present from M0:

**Unit (`SpliitTests`, Swift Testing)** — superjson encode/decode round-trips,
the `meta.values` date handling, currency formatting against a
symbol-not-code currency, split-mode share arithmetic, and the AsyncStorage
migration against checked-in fixture manifests (inline *and* sidecar variants).

**End-to-end (`SpliitUITests`, XCUITest)** — the real app driving a real
backend:

```
docker compose up            →  http://localhost:3000
        │
        ▼
seed script (tRPC mutations) →  known groups, participants, expenses
        │
        ▼
app launched with:  -baseURL http://localhost:3000/
                    -resetLocalStore YES
                    -seedRecentGroups fixtures/two-groups.json
        │
        ▼
assertions on accessibilityIdentifiers
```

Seeding through the tRPC API rather than the database keeps the harness
decoupled from Prisma migrations.

**Practical rule:** every interactive view gets an
`accessibilityIdentifier` in the same commit that creates it. Retrofitting them
is the thing that makes UI test suites get abandoned.

**CI.** GitHub Actions macOS runners can't run Docker, so CI installs Postgres
via Homebrew and runs the Next.js app directly with `npm start`; the compose
file stays for local development. A fast PR smoke configuration in the test plan
can run the same XCUITest flows against a `URLProtocol` stub replaying recorded
tRPC fixtures, with the full backend suite on merge.

### E2E flows to cover by end of M1

1. Cold start with no groups → empty state → create group → land in the group
2. Add group by URL → appears in recents; invalid URL → error message
3. Create expense split evenly → appears in the list with the right amount
4. Create expense split by amount that doesn't add up → validation error
5. Balances reflect a new expense; "Mark as paid" prefills the reimbursement
6. Edit an expense; delete an expense
7. Edit group: rename, add a participant, blocked deletion of a participant
   who has expenses
8. Change base URL in settings → app talks to the new instance
9. **Upgrade test:** launch with a legacy AsyncStorage manifest planted in the
   container (both inline and sidecar variants) → recent groups appear

---

## 6. Milestones

### M0 — Foundations · size M · ✅ done

The point of M0 is that by the end of it, a feature can be built test-first.

- Xcode project, app target, two local SwiftPM packages, Swift 6.2 strict
  concurrency, iOS 26 deployment target
- `TRPCClient`: superjson envelope encoding/decoding, `meta.values` handling,
  typed errors, base-URL injection
- DTOs for the full router surface listed in §3.3
- AsyncStorage migration + the new stores, with fixture-based unit tests
- String Catalog wired up; all strings localised from the start
- XCUITest target, launch-argument plumbing, `e2e/` backend harness, seed script
- GitHub Actions: build, unit tests, E2E against a local backend
- App icon and assets ported from the RN app

**Exit:** an empty app launches, reads migrated recent groups, and one
end-to-end test goes green in CI.

### M1 — Parity with the current mobile app · size L · **ship as 2.0.0** · 🟡 in progress

Everything the RN app does today, and nothing more.

**Groups list**
- Recent groups from local storage, enriched with `groups.list` (participant
  count, creation date)
- Row context menu: open, remove from list
- Empty state: welcome, create group, add group by URL
- Settings entry point

**Create group / group settings**
- Name, currency symbol, information, participants
- Add/remove participants; participants with expenses cannot be removed
- Validation: 2–50 chars, no duplicate names, at least one participant

**Add group by URL**
- Parse `/groups/:id` out of a pasted URL, verify against the server, add to
  recents, error state for anything invalid

**Group screen**
- Title from the group, overflow menu: edit group, share group
  (`{baseUrl}groups/{groupId}` via the system share sheet)
- Expenses / Balances tabs

**Expense list**
- Paginated, 20 per page, infinite scroll
- Date-bucket sections: Upcoming, This week, Earlier this month, Last month,
  Earlier this year, Last year, Older
- Row: title (italic for reimbursements), "Paid by X for A, B", amount, date
- Swipe actions and context menu: edit, delete
- Empty state

**Balances**
- Diverging bar per participant, scaled to the largest absolute balance
- Suggested reimbursements, with "Mark as paid" prefilling a reimbursement
  expense
- Empty state when nothing is owed

**Expense form (create + edit)**
- Title, date, amount, reimbursement toggle, category, paid-by, notes
- Split mode: Evenly / Shares / Percentage / Amount
- Per-participant paid-for list with mode-appropriate share inputs
- Full validation parity with `expenseFormSchema`

**Settings / About**
- About text, website and GitHub links, version and build
- Base URL for self-hosted instances

**Cross-cutting**
- Plausible analytics: same screen names and events as today
  (`home`, `create-group`, `add-group-by-url`, `about`, `group-settings`,
  `group-expenses`, `group-balances`, `group-create-expense`,
  `group-edit-expense`; events `create-group`, `create-expense`) — a plain
  `POST https://plausible.io/api/event`, no library needed
- Dark mode (the RN app is light-only; this comes free and should not be
  deferred)

**Exit:** TestFlight build, the nine E2E flows green, migration verified on a
device upgrading from 1.1.0.

**Status.** Everything above is built and covered by tests: 136 unit tests, 8
write round-trips against a real server, and 40 UI flows driving the app in a
simulator. The only thing left before this can ship is not code — see the App
Store Connect line below.

- ~~Verify the migration on a physical device~~ — **done**. A signed build
  installed *over* App Store 1.2.0 on an iPhone 16 Pro (iOS 26.6.1) without
  deleting it, and the migration read the real `RCTAsyncLocalStorage_V1`
  manifest: 4 groups carried across with matching IDs and names, and the legacy
  files were left in place. Worth knowing: iOS accepted the re-signed install as
  an upgrade, so the container survived — deleting the app first would have been
  both destructive and pointless
- App Store Connect: **the listing is written and the screenshots are generated**
  — [Docs/app-store/metadata.md](Docs/app-store/metadata.md) holds the copy in
  both languages, the review notes and the App Privacy answers, and
  `make screenshots` produces six pictures per language for both the 6.9" iPhone
  and the 13" iPad the universal build obliges us to supply. `PrivacyInfo.xcprivacy`
  now declares what actually leaves the device — participant names, the group's
  own content, and the Plausible events — because a group kept on the public
  instance is data the developer's server holds, account or no account, and the
  manifest had only ever mentioned the analytics. The questionnaire in App Store
  Connect has to be filled in to match, and since the manifest ships inside the
  binary, that is the one outstanding item that needs a build. Two things are
  still open: **there is no privacy policy to link to** (spliit.app has no such
  page, and App Store Connect will not accept a submission without the URL), and
  nobody has checked how much of the installed base is below iOS 26 — they stay
  on 1.2.0
- ~~A pass over Dynamic Type and VoiceOver~~ — **done**. Rows that pair a name
  with an amount now stack once the text reaches the accessibility sizes, and
  three things that were only ever said visually are said out loud: whether a
  balance is owed or owing (it was colour and a minus sign), which payment a
  "Mark as paid" button settles, and whether a participant is in the split — the
  paid-for checkboxes are a custom `ToggleStyle` built from a `Button`, so they
  announced as buttons with no state at all. Covered by `AccessibilityTests`,
  which launches at AX5 through a launch argument
- ~~Empty and error states for an instance that can't be reached mid-flow~~ —
  **done**. `LoadState` tells "nothing yet" apart from "nothing there" apart from
  "it failed", every screen that loads has an error state with a way to retry,
  all three forms report a save that could not be sent, and
  `testUnreachableServerOffersRetryInsteadOfSpinning` covers it end to end

### M2 — Make it feel native · size M · ✅ done

Things the RN app could not reasonably do. This is what justifies the rewrite
to a user opening it for the first time.

- ~~Liquid Glass treatment~~ — **done, and smaller than it looked.** Toolbars and
  the tab bar are glass because iOS 26 draws them that way; there was nothing to
  add. What was real: `GlassEffectContainer` around the search field and its cancel
  button, and `tabBarMinimizeBehavior(.onScrollDown)`, which §4 asked for and
  nothing had applied. The zoom transition landed with the motion pass.
  Deliberately **not** done: glass on the balance and expense rows. Those are
  content, the design pass made them solid cards on purpose, and glass belongs to
  what floats above content rather than to the content itself
- ~~Pull-to-refresh~~ — **done**, landed with the design pass
- ~~Expense search~~ — **done**. A search tab in the group's tab bar, with the field
  docked at the bottom above the keyboard, and `groups.expenses.list`'s `filter`
  argument doing the matching server-side. Not `.searchable`: that modifier hosts its
  field in a navigation bar, and its iOS 26 bottom-docked form only when the `TabView`
  owning the search tab is the root of the scene. This one is pushed onto the groups
  list, so the field is the app's own — see the note in `ExpenseSearchView`
- ~~Swipe-to-delete with undo~~ — **done**. The row leaves at once and the request
  waits five seconds. The window closes on whichever comes first: the timer, another
  delete, or leaving the group — that last one detached, because the model dies with
  the screen and a delete already asked for must not die with it
- ~~Haptics~~ — **done**, four of them, all tied to outcomes rather than gestures:
  saved, refused, deleted, undone. Named in `Haptics` so the next one has to argue
  its way into that list. (The Dynamic Type and VoiceOver audits were done in M1)
- Universal Links for `spliit.app/groups/…` — **app side done**, and inert until
  spliit.app serves an `apple-app-site-association` file naming the app. The exact
  file, and the App ID capability it needs, are in
  [Docs/universal-links.md](Docs/universal-links.md). Incoming group links already
  work over the custom scheme and against the configured instance
- ~~Share extension / share sheet target~~ — **dropped, not deferred.** It was a
  second road to a place there are already two roads to: a shared group link now
  opens the app and joins the group on its own, and "Add by link" takes a pasted URL
  for everything else. An extension target to reach the same screen is a build
  target, a review surface and a second parser to keep in step, for a journey that
  is already one tap
- ~~App Intents + Spotlight~~ — **done**. *Open Group* and *Add Expense*, both
  surfaced by Siri, Spotlight and Shortcuts. Add Expense opens the form rather than
  posting the expense: an expense needs a payer and the app has no idea who its user
  is in a group, so guessing would put someone else's name against a payment in a
  shared ledger. Revisit when M3.1 lands the active user — that is what makes a
  headless "add £12 for coffee to Lisbon" safe. **The active user has since landed** (M3.1),
  so that is now possible in any group somebody has said who they are in; what is still missing
  is the split, which is what "saved default splitting options" below is for
- **Widget** — moved to M3.1. It was specced as "balances at a glance for a starred
  group", and starring is itself an M3.1 feature. Building it against the
  most-recent group instead would ship it twice: once now with the wrong subject,
  once again when starring arrives. It waits for the thing it is about

### M3 — Toward web parity · size L, delivered in waves · 🟡 in progress

Ordered by value to a phone user, not by web-app order.

**Wave 1 — the gaps that hurt most**
- ~~Currency **code** (ISO-4217) alongside the free-text symbol, with a proper
  currency picker~~ — **done**. A searchable list of every currency the system can
  name, the device's own currency first, and "Custom symbol" for anything not in
  it. The list is Foundation's — names, symbols and minor units all come from the
  platform, so it is translated wherever iOS is and there is no generated table to
  keep in step the way the web repo has to. Two things it turned up. **Money is not
  always hundredths**: 34 of the 159 currencies have no minor unit and 6 have three,
  and the web app has always scaled by the currency's own — so a yen group created
  on the web was already being shown to our users at a hundredth of its value.
  `MoneyFormatter` now takes the precision from the ISO code and the expense form
  parses against it, which fixes those groups and makes the new ones right. And
  **clearing a code has to be an empty string, not a missing one**: a nil optional
  is left out of the JSON, reaches the server as `undefined` and tells Prisma to
  leave the column alone, so a group moved to a custom symbol would have kept
  claiming to be in dollars. The web writes `''` there for the same reason
- ~~Multi-currency expenses: original amount, original currency, conversion rate~~ — **done**.
  A *Currency* section on the expense form: what it was paid in, what was paid, and the rate.
  The rate comes from [Frankfurter](https://frankfurter.dev), which is what the web app calls,
  so an expense converted on a phone and the same one converted in a browser agree; it is
  filled in for you and yours to overwrite, because the rate a card was actually charged at
  beats a published one and a lookup that lands afterwards must not undo it. Nothing about the
  user is sent — a date and two currency codes — and every failure recovers by letting you type
  the rate. UI tests stub it through a launch argument rather than reaching the real service.
  The section is absent for a group with only a free-text symbol: a conversion needs an ISO
  code on both sides, and the group form's currency picker is where that is explained.
  Three things it turned up. **The total is derived, not typed** — under a conversion the Amount
  row shows what the payment comes to and cannot be edited, since a total able to disagree with
  the rate beside it is a total that rate does not explain. **The two amounts are on different
  scales**: `originalAmount` is in the currency paid, `amount` in the group's, and a €40.00
  dinner in a yen group is 4000 and 6540. And **`null` is not a general way to clear a
  column**: the schema takes one for `originalCurrency` and rejects it for `originalAmount` and
  `conversionRate`, so an expense that stops being converted keeps those two with nothing
  reading them — `make test-live` caught that, and nothing local would have.
  Deliberately not built: per-participant shares typed in the original currency, which the web
  offers for by-amount splits. That is a second conversion inside the split section for a case
  the group's own currency already covers
- ~~Active user ("who are you in this group?") and the personal balance summary~~ — **done**.
  Asked and answered per group, and stored on the group in `recent-groups.json` beside the
  star and the archive flag, for the same reason those are: one file, one write, and no way to
  be somebody in a group the list has forgotten. Three states rather than two — never asked,
  a participant, and an explicit "nobody" for a phone the whole group shares — because a
  question that keeps being asked after it has been answered is a worse feature than no
  question. Two things it changes: the balances tab leads with **your** balance, unsigned under
  a sentence that says which way it goes ("You are owed" / "You owe"); and a new expense
  arrives already paid by you. Deliberately
  **not** the web's modal on first opening a group: that is a toll gate in front of the
  expenses somebody just tapped to see, and the question only pays off on the balances tab —
  which is where it is offered, beside the answer it unlocks. A participant who is later
  removed from the group reads as unanswered rather than as a missing person, so the invitation
  comes back rather than a balance quietly disappearing. It is one number and not three, which
  is a finding worth carrying into wave 2: **`groups.balances.list` returns the web app's
  *public* balances**, computed from the suggested payments rather than from the expenses, so
  `paid` is what a participant will be handed and `paidFor` what they will hand over — one of
  the two is always zero, and neither is what anybody paid. "You paid X, and Y was spent on
  you" was written on that pair and was false. The real figures are `groups.stats.get`'s
  `totalParticipantSpendings` and `totalParticipantShare`, which the stats tab below brings in;
  the section footer on that screen claimed the same wrong thing and has been corrected too
- ~~Select all / none in the paid-for list~~ — **done**. One control in the "Paid for"
  header rather than two, because with everyone already in the split "select all" has
  nothing left to offer. It flips the `isIncluded` flags and touches nothing else, so the
  rows never leave the draft and a share typed before an accidental "select none" comes
  back with its owner — the web app rebuilds the list instead, and gives anyone re-added a
  share of 1
- Saved default splitting options
- ~~Starred and archived groups on the home screen~~ — **done**. Both flags live on
  the group in `recent-groups.json` rather than in two lists of IDs the way the web
  app keeps them: one file, one write, and no way to end up starring a group the
  list has forgotten. Starring and archiving each undo the other, and `remember`
  carries both across a rename — the path that would otherwise unstar a group the
  moment it was renamed. On screen they are three sections and nothing else: no
  badge on the row, because the header already said it. Star is a leading swipe,
  archive and remove are trailing, and archive is the outermost of those, so a full
  swipe archives rather than removes — removing a group has no way back but the
  original link. All three are in a long-press menu too, since a swipe action nobody
  swipes for is a feature nobody has. Archived groups also stop being offered by
  Siri and Spotlight; asking for one by name still finds it
- The balances widget, which M2 left here because it is about a starred group and
  there was nothing to star. There is now

**Wave 2 — the missing tabs**
- ~~Information tab~~ — **done**, and deliberately wider than the web's. There the tab is the
  group's note and nothing else; on a phone that is a whole tab-bar slot that stays empty for
  every group whose note was never filled in — which is most of them. So it also lists the
  participants, which is the only place outside the editor that names who is in the group, and
  the currency and creation date. The note is still edited in the group form: it is a field on
  the group, and a second editor for one field is a second thing to keep in step
- Stats tab (total group spending, your spending, your share). `groups.stats.get` takes a
  `participantId` and answers the last two, so it is the active user that makes them
  answerable — and it is the only endpoint that knows what anybody actually paid. Note that
  `totalParticipantShare` is not an integer: an evenly split expense divides in the server's
  own floating-point arithmetic, so the DTO cannot be `Int` the way every other amount is
- ~~Activity log~~ — **done**, though not as a tab: it is pushed from the information tab, which
  is where the things you consult rather than work in already live, and four tabs plus the search
  capsule already fill the bar. `groups.activities.list` pages on an offset cursor the way the
  expense list does, and its entries are bucketed more finely than expenses are: an expense is
  dated by the day it happened, an activity is stamped to the second, and most of a log is from
  the last day or two — where "This week" would be the whole screen. It is also what made the app
  start sending `participantId`, which all four mutating procedures accept and none requires.
  Without it every line of every log reads "Someone", including lines about expenses this app
  wrote itself
- Export to CSV / JSON via the share sheet

**Wave 3 — media and automation**
- Expense documents: attach photos, S3 upload, gallery viewer
- Receipt scanning. The web version calls OpenAI server-side; on iOS 26 this can
  run **on device** with Vision's document recognition plus Foundation Models —
  faster, free, private, and works against self-hosted instances that have no
  OpenAI key configured
- Category auto-suggestion, same approach
- Recurring expenses (`NONE` / `DAILY` / `WEEKLY` / `MONTHLY`)

**Wave 4 — localization**
- French shipped; import the rest of the web repo's `messages/*.json` into the
  String Catalogs. `make strings` names what each new language still owes
- RTL layout pass (the web app supports Arabic and Hebrew)

### M4 — Beyond the web · size TBD

Candidates, not commitments: offline reading with background refresh, Live
Activity for a trip in progress, iPad `NavigationSplitView` layout, Apple Watch
complication for a group balance, Splitwise import.

---

## 7. Feature inventory

Legend: ✅ present · ➖ absent · 🔜 planned milestone

| Feature | RN app | Web | New app |
|---|:--:|:--:|:--:|
| Recent groups list | ✅ | ✅ | M1 |
| Create / edit group | ✅ | ✅ | M1 |
| Add group by URL | ✅ | ✅ | M1 |
| Share group | ✅ | ✅ | M1 |
| Expense list, paginated + date buckets | ✅ | ✅ | M1 |
| Create / edit / delete expense | ✅ | ✅ | M1 |
| Split evenly / shares / percentage / amount | ✅ | ✅ | M1 |
| Reimbursement expenses | ✅ | ✅ | M1 |
| Categories | ✅ | ✅ | M1 |
| Notes on expenses | ✅ | ✅ | M1 |
| Balances + suggested reimbursements | ✅ | ✅ | M1 |
| Self-hosted base URL | ✅ | n/a | M1 |
| Analytics | ✅ | ✅ | M1 |
| Dark mode | ➖ | ✅ | M1 |
| Group notes field | ✅ | ✅ | M1 (edit), ✅ M3.2 (shown) |
| Expense search | ➖ | ✅ | ✅ M2 |
| Universal Links | ➖ | n/a | ✅ M2 (needs the web-side file) |
| App Intents / Spotlight | ➖ | ➖ | ✅ M2 |
| Widget | ➖ | ➖ | M3.1, with starring |
| Currency code + picker | ➖ | ✅ | ✅ M3.1 |
| Multi-currency expenses | ➖ | ✅ | ✅ M3.1 |
| Active user / personal balance | ➖ | ✅ | ✅ M3.1 |
| Select all-or-none participants | ➖ | ✅ | ✅ M3.1 |
| Default splitting options | ➖ | ✅ | M3.1 |
| Starred / archived groups | ➖ | ✅ | ✅ M3.1 |
| Group information tab | ➖ | ✅ | ✅ M3.2 |
| Stats | ➖ | ✅ | M3.2 |
| Activity log | ➖ | ✅ | ✅ M3.2 |
| Export CSV / JSON | ➖ | ✅ | M3.2 |
| Expense documents | ➖ | ✅ | M3.3 |
| Receipt scanning | ➖ | ✅ | M3.3 |
| Recurring expenses | ➖ | ✅ | M3.3 |
| French | ➖ | ✅ | ✅ |
| The other 34 locales | ➖ | ✅ | M3.4 |
| Delete a group | ➖ | ➖ | — (no API) |

---

## 8. Risks

**Model drift.** Hand-written DTOs will fall out of sync with the web repo's Zod
schemas. Mitigation: a CI job that runs the E2E suite against `spliit.app`
nightly, so a server-side shape change fails loudly rather than in the field.

**iOS 26 floor.** Some share of the installed base stays on 1.1.0 indefinitely.
This is an accepted cost of the choice, but worth checking actual App Store
Connect version-adoption numbers before shipping M1, and worth a line in the
release notes.

**Migration is one-shot and unattended.** If the AsyncStorage import fails, a
user silently loses their group list — and since groups are only reachable by
ID, that is unrecoverable for them. Mitigation: the migration must never throw,
must log its outcome to analytics, and the legacy files must not be deleted. The
upgrade E2E test is the highest-value test in the suite.

**Self-hosted instances lag.** Older self-hosted deployments may not have every
procedure the app calls. Mitigation: treat unknown-procedure errors as a
feature-unavailable state rather than a crash, and degrade the affected screen.

**E2E flakiness in CI.** UI tests that depend on network timing rot fast.
Mitigation: seed deterministically, never assert on animations, and keep the
smoke configuration (stubbed network) as the required PR check with the full
backend suite on merge.

---

## 9. Immediate next steps

1. Create the Xcode project and the two SwiftPM packages
2. Write `TRPCClient` + superjson coding, with round-trip unit tests, against
   recorded fixtures from `spliit.app`
3. Write the AsyncStorage migration with fixture manifests for both the inline
   and the sidecar case
4. Stand up `e2e/` and get one trivial XCUITest green in GitHub Actions
5. Then start M1 at the groups list
