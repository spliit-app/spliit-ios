# Design handoff — give Spliit a face

**For:** whoever picks up the visual design pass.
**Status:** answered. A design system was built from this brief and lives in Claude Design as
*Spliit Design System*; §8's four decisions came back decided and are recorded there. The
implementation is landing in the four stages of §5.
**Read first:** [CLAUDE.md](CLAUDE.md) for how work lands, [ROADMAP.md](ROADMAP.md) §4 for the
navigation shape this has to live inside.

---

## 1. The ask

> Make the UI a bit more original than the default iOS look.

The app today is honest, competent and completely anonymous. It is `List`, `Form`,
`ContentUnavailableView` and SF Symbols with a green tint applied globally. Screenshot any
screen, crop the title, and nobody could tell you which app it is — it could be a to-do app, a
podcast client or a hardware-store inventory. That is a fair place to be at the end of a
feature-parity milestone. It is not where this should ship.

The job is to make it recognisably **Spliit** without making it un-iOS.

### Calibrating "a bit"

| | |
|---|---|
| **Too little** | Pick a nicer accent colour and ship. Already done — the accent is already the brand emerald, and it changed nothing. |
| **The target** | Someone who uses the app weekly could pick its screenshot out of ten expense apps. Every control still behaves exactly as iOS taught them. Nothing surprising under the thumb. |
| **Too far** | Custom navigation bars, a hand-rolled tab bar, bespoke button shapes, a display font for body copy, motion as decoration. This is a utility people open for twenty seconds at a restaurant table with one hand. |

There is a real tension to hold, and it is worth naming: [ROADMAP.md](ROADMAP.md) goal #2 is *"a
UI that feels like iOS, not a web app in a wrapper"*. Originality bought by abandoning native
affordances would be a regression against the whole point of the rewrite. **Originality goes
into the content, not the chrome.**

That is also where the opportunity is. The app's subject matter is money, people, and who owes
whom — three things with enormous visual potential, currently rendered as left-aligned text in
a grouped list.

---

## 2. Where the default shows

Every surface, what it is today, and the flat spot. Line numbers are from `main` at the time of
writing.

| Surface | File | Today | The flat spot |
|---|---|---|---|
| Groups list (home) | `Spliit/Views/GroupsListView.swift:105` | `List` + `Section("Recent groups")`, rows are a headline plus two grey `Label`s | The app's top-level object gets the least visual weight of anything in the app. No sense of a group's size, money or activity. |
| Groups list, empty | `GroupsListView.swift:88` | `ContentUnavailableView` + `person.2` | The literal first thing a new user sees, and it is the system template. |
| Group detail | `GroupDetailView.swift:38` | `TabView` with two tabs, inline title | Fine and load-bearing. Leave the structure alone (see §4). |
| Expense list | `ExpenseListView.swift:49` | `List`, date-bucketed sections, row = title/payer left, amount/date right | Amounts are `.semibold` `.monospacedDigit()` and nothing else. Category is fetched and never shown. Reimbursements are marked with *italics*. |
| Balances | `BalancesView.swift:87` | Hand-rolled diverging capsule bar, `.green`/`.red` | **The single most promising screen in the app** and the only place that already draws something. `import Charts` sits at line 1, unused. |
| Suggested payments | `BalancesView.swift:139` | "X owes Y", amount, a `.bordered` button | The one genuinely delightful moment available — the app telling you the shortest way out — rendered as a table row. |
| Expense form | `ExpenseFormView.swift:76` | `Form`, segmented split picker, custom checkbox toggle at `:350` | Correctly conservative. The split section is the interesting part. |
| Group form | `GroupFormView.swift:23` | `Form` | Leave largely alone. |
| Add by URL / Settings | `AddGroupByURLView.swift`, `SettingsView.swift` | `Form` | Leave alone. |

### Three things found while writing this

1. **`Logo.imageset` ships in the asset catalogue and is referenced from nowhere.** `grep -rn
   Logo Spliit/ --include='*.swift'` returns nothing. The app has a brand mark and never shows
   it.
2. **`import Charts` in `BalancesView.swift:1` is unused** — the roadmap intended Swift Charts
   for balances and the hand-rolled bar won. That is arguably the right call; the import should
   go one way or the other.
3. **None of the iOS 26 signature APIs are in the code yet.** No `glassEffect`, no
   `navigationTransition(.zoom)`, no `tabBarMinimizeBehavior`, no `sensoryFeedback`, no
   `symbolEffect`, no `contentTransition`, no `searchable`. The deployment target was set to 26
   specifically to buy these. They are all still on the table.

---

## 3. Brand anchors that already exist

Do not invent a palette from scratch — Spliit has one, spread across three places.

**The iOS accent** (`Spliit/Resources/Assets.xcassets/AccentColor.colorset`) — the only branded
colour in the app today, and it is applied globally by
`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`:

- Light `#059669` (Tailwind emerald-600)
- Dark `#10B981` (emerald-500)

**The web app** (`../spliit/src/app/globals.css`) — the reference implementation:

- `--primary` light `hsl(163 94% 24%)` ≈ `#047756`, dark `hsl(161 90% 45%)` — same emerald family, a shade deeper than iOS
- `--destructive` `hsl(0 84.2% 60.2%)` ≈ `#ef4444`
- `--radius` `0.5rem` (8pt)
- Muted foreground `hsl(240 3.8% 46.1%)`

**The logo mark** (`../spliit/src/app/icon.svg`, and the unused `Logo.imageset`) — a mint funnel
splitting into two coral halves:

- Coral `#ed5167`
- Mint `#72d3b8`, deeper mint `#55bc9c`
- Near-black `#333538`

**Open question worth resolving early:** [ROADMAP.md](ROADMAP.md) names `#be185d` (pink-700) as
the secondary, but the logo's second colour is coral `#ed5167`. Those are different pinks. Pick
one, write down which, and use it consistently — the "money owed vs money owing" axis is the
obvious place a second colour earns its keep, and today that axis is plain `.green` / `.red`.

---

## 4. Hard constraints

These fail **silently** — no crash, no warning, just a broken app or a broken test suite. They
have all cost real debugging time already.

**`accessibilityIdentifier` on a container stamps every descendant and overrides inner ones.**
Wrapping a row in a styled card container and putting an identifier on the card erases every
identifier inside it, and the UI suite stops matching. Identifiers go on leaves only. They live
in `Shared/AccessibilityID.swift`; do not rename them.

**A `NavigationStack` nested inside a `TabView` tab silently refuses to push.** The group detail
screen's two tabs must not create their own stacks.

**The UI suite pins some visual structure.** These assertions constrain what you can change:

| Assertion | What it pins |
|---|---|
| `GroupSettingsAndBalanceTests.swift:12` — `app.staticTexts[rowTitle(id)].tap()` | The group row's title must stay a tappable *static text* carrying that identifier |
| `ExpenseTests.swift:88` — `app.staticTexts["Coffee"].tap()`, and `:113` | Same for expense rows: tapping the title text opens the editor |
| `ExpenseTests.swift:26`, `GroupSettingsAndBalanceTests.swift:15` — `app.buttons["Balances"].tap()` | The Expenses/Balances switcher must expose a *button* labelled "Balances" |
| `ExpenseTests.swift:57` — `app.buttons["Amount"].tap()` | The split-mode segments must stay buttons labelled by `SplitMode.title` |
| `ExpenseTests.swift:34`, `:37` — `.label == "$20.00"` / `"-$20.00"` | The balance amount's accessibility label must be exactly `MoneyFormatter` output — do not split the symbol into its own view, add a `+`, or abbreviate |
| `GroupSettingsAndBalanceTests.swift:77` — `app.buttons["Remove"].firstMatch` | The participant swipe action stays labelled "Remove" |

Changing any of these is allowed — but change the test in the same commit, deliberately, not by
discovering red CI.

**Money is integer minor units** and formatting goes through `SpliitCore/MoneyFormatter.swift`.
Never format an amount in a view. If a new treatment needs the digits without the symbol,
`plainString(minorUnits:)` already exists.

**Every user-facing string is `LocalizedStringKey` or `String(localized:)`.** New copy goes in
`Spliit/Resources/Localizable.xcstrings`. Anything added in `SpliitCore` needs
`bundle: Bundle.module`.

**No third-party dependencies.** No Lottie, no icon package, no colour library. Swift Charts and
SF Symbols are in the box and count as free.

**Dynamic Type and VoiceOver are not optional.** A fixed-height card breaks at accessibility
sizes. Test at XXL before opening the PR. Decorative elements get `.accessibilityHidden(true)` —
`BalancesView.swift:127` already does this for the bar.

**`Spliit.xcodeproj` is generated.** Adding a colour set, an image or a font needs `make
generate`. Never hand-edit the project file.

---

## 5. Suggested shape of the work

Four stages, each its own PR. Stage 1 is the only one with a required order.

**Stage 1 — tokens, no visible change.** A small design-system file (suggest
`Spliit/Views/DesignSystem/`) holding the palette, the money type treatment, corner radii and
spacing scale. Colour sets go in the asset catalogue with light and dark variants, not as
hard-coded `Color(red:green:blue:)`. Nothing else changes; this PR should be reviewable in five
minutes and produce identical screenshots.

**Stage 2 — the identity screens.** Groups list and Balances. These two carry the app's
character; they are also the two with the most headroom.

**Stage 3 — the expense list and the money type.** Rows, date-bucket headers, and whatever the
amount treatment turns out to be, applied consistently everywhere amounts appear.

**Stage 4 — restraint pass on the forms.** Probably just the split section and the empty states.
`Form` is doing its job; do not fight it.

Ship stage 2 on its own if time runs out. Half the app looking considered beats all of it
looking half-done.

---

## 6. Raw material

**Non-binding.** These are prompts, not a spec — ideas that are cheap in SwiftUI and tied to
this app's actual data. Ignore any of them for something better.

- **Give participants an identity.** Initials in a monogram, with a colour derived
  deterministically from the participant ID. Participants appear on four surfaces (balances,
  paid-by lines, the split list, suggested payments) and are currently plain text everywhere.
  This is the single highest ratio of recognisability to effort in the app, and it makes the
  balances screen scannable rather than readable.

- **Make money a typographic system, not a font weight.** One treatment — weight, tracking,
  rounded design, sign colour — used for every amount in the app, sized by importance. Amounts
  are the reason the app exists and currently they are `.semibold`.

- **The balances screen is the app's one visual moment.** `BalancesView.swift:109-126` is a
  hand-rolled diverging bar with a hairline at centre. Everything from "polish this" to "replace
  it with something that reads at a glance" is in scope, and it is the screen most likely to
  end up in an App Store screenshot.

- **Suggested payments should feel like an answer, not a row.** "The fewest payments that settle
  the group" is a genuinely good piece of work the UI currently whispers.

- **Six `ContentUnavailableView`s** across the app (`GroupsListView.swift:89`,
  `ExpenseListView.swift:23` and `:35`, `BalancesView.swift:22`, `ExpenseFormView.swift:36`,
  `GroupFormView.swift:215`). The empty and welcome states are the most template-looking moments
  and the first a new user meets. The unused logo asset might belong on one of them.

- **The expense list already knows the category and never shows it.** `model.categories` is
  fetched and only used to populate a picker.

- **A signature transition, once.** `.navigationTransition(.zoom(sourceID:in:))` from a group row
  into the group is already in the roadmap, costs about ten lines, and is the kind of thing
  people notice without being able to say why. One signature moment is a voice; five is a
  costume.

- **`glassEffect` / `GlassEffectContainer`** on the balance and expense surfaces is roadmap M2
  and is genuinely distinctive on iOS 26 — but it is *platform* character, not *brand*
  character. Worth using; not sufficient on its own.

### Explicitly out of scope

- The tRPC client, models, or anything under `Packages/SpliitKit/Sources/SpliitAPI`
- The `*FormDraft` validation types — form *logic* is deliberately outside the views
- The navigation structure (§4)
- Accessibility identifier names
- Copy, unless a copy change is part of a design change — then update the string catalogue

---

## 7. Seeing it, and proving it

Get the app running with real data:

```sh
make e2e-up      # throwaway Spliit server on :3009 (needs Docker)
make e2e-seed    # groups, participants, expenses worth looking at
make run         # build, install, launch on the simulator
make shot        # → build/screenshot.png
```

Before touching anything, capture the current state of every surface in §2. Before/after pairs
are what makes this reviewable — put them in the PR description.

Also look at the app in dark mode, at Dynamic Type XXL, and with a group that has one
participant and no expenses. Four of the six `ContentUnavailableView`s are error states that
only appear when the server is unreachable; `make e2e-down` mid-session is the fastest way to
see them.

**The gate before marking a PR ready for review:**

```sh
make test        # ~2s, no simulator
make build
make e2e         # 10–20 min — this is what "ready for review" triggers in CI
```

Per [CLAUDE.md](CLAUDE.md): work in a worktree, open the PR as a **draft**, and mark it ready
only when you want the end-to-end suite to run.

---

## 8. Decisions — answered

These four were open when this brief was written. The design system decided them:

1. **The second colour is `#be185d`** (pink-700, per ROADMAP), not the logo's coral `#ed5167`.
   Coral stays in the logo palette and in the derivation of the money-negative tone.
2. **Owed/owing leave `.green`/`.red`.** They are a branded pair derived from the emerald accent
   and the logo coral, tuned per theme to clear WCAG AA: light `#047857` / `#c2334a`, dark
   `#34d399` / `#ff8a9b`.
3. **The logo appears on the welcome and empty states only** — never in a navigation bar.
4. **The hand-rolled bar wins over Swift Charts.** Charts is a dependency-sized concept for a
   shape that is twenty lines of layout; drop the unused `import Charts`.

One decision was added in implementation, because the API forced it: **the groups list gets a
group monogram rather than the design system's stack of participant monograms.**
`Spliit.groups(ids:)` returns `participantCount` and `createdAt` and no participant names, so a
stack would cost one extra request per group on every launch. Seeding a single monogram on the
group ID gives the row its weight for nothing. Revisit if the home screen ever needs balances
too — that is the same extra request.

When the last stage lands, this file should be replaced by a `DESIGN.md` describing what was
actually built — a handoff is worth keeping only until it is answered.
