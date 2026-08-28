# Design — what Spliit looks like, and why

**For:** anyone about to touch a view.
**Replaces:** `DESIGN-HANDOFF.md`, the brief that asked for this. It was answered by PRs
[#6](https://github.com/spliit-app/spliit-ios/pull/6),
[#7](https://github.com/spliit-app/spliit-ios/pull/7),
[#9](https://github.com/spliit-app/spliit-ios/pull/9),
[#10](https://github.com/spliit-app/spliit-ios/pull/10) and
[#11](https://github.com/spliit-app/spliit-ios/pull/11), and a handoff is worth keeping only
until it is. The design system itself was built in Claude Design as *Spliit Design System*;
where this app departs from it, §8 says so.

The ask was *"make the UI a bit more original than the default iOS look"*. The answer it settled
on, and the sentence the rest of this file elaborates:

> **Originality goes into the content, not the chrome.**

Nothing here replaces a navigation bar, a tab bar, a `List` or a `Form`. Every control still
behaves the way iOS taught people it would. What changed is the four things the system has no
opinion about — money, people, categories and emptiness — and those are exactly the four things
this app is about.

---

## 1. The pieces

All of it lives in `Spliit/Views/DesignSystem/`, except the two parts that have to be testable
without a simulator or shared with the test bundle.

| File | What it is |
|---|---|
| `Palette.swift` | The colours added on top of the system palette. The only place asset-catalogue colour names appear. |
| `Money.swift` | Every amount in the app, in one treatment. Plus `moneyInput()` for the fields. |
| `Monogram.swift` | `Monogram` — someone's initials in a colour that is theirs. `ParticipantDot` — the same colour with the letters dropped. |
| `EmptyState.swift` | The screen with nothing on it. Eleven of them exist; one is the first thing anyone ever sees of the app. |
| `CategoryIcon.swift` | The glyph slot that leads an expense row. |
| `DateBucketHeader.swift` | "THIS WEEK" — the rule between runs of expenses. |
| `CompactLabelStyle.swift` | `.labelStyle(.compact)`: an icon beside its text rather than in a reserved column. |
| `Motion.swift` | The one duration the app animates things with. |
| `Haptics.swift` | The four things the app is allowed to say through the Taptic Engine. |
| `UndoBar.swift` | What a delete leaves behind for five seconds. |
| `SpliitCore/MonogramPalette.swift` | Which colour and which letters. In the package so `make test` covers it. |
| `Shared/ExpenseCategoryIcon.swift` | Category → SF Symbol. In `Shared/` so the UI test bundle can resolve every one. |

---

## 2. Colour

Only three things are defined here: the money axis, the monogram palette, and a soft accent
tint. Backgrounds, separators and fills are deliberately **absent** — the system ones already
adapt to dark mode, to increased contrast, and to Apple's own drift between releases, and
matching them by hand is a debt that comes due every September.

| Colour set | Light | Dark | Used for |
|---|---|---|---|
| `AccentColor` | `#059669` | `#10B981` | Applied globally by `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`. |
| `MoneyPositive` | `#047857` | `#34D399` | Owed to you. |
| `MoneyNegative` | `#C2334A` | `#FF8A9B` | You owe. Derived from the logo's coral. |
| `BrandAccentSoft` | `#ECFDF5` | accent at 16% | The tile an empty state's icon sits in. |
| `BrandSecondary` | `#BE185D` | `#EC4899` | Pink-700, per ROADMAP. Rare by design — see §8. |
| `Monogram1…8` | emerald, cyan, indigo, pink, orange, amber, olive, violet | same | The eight participant colours. |

Two decisions worth restating because they get re-litigated:

**`.green` / `.red` are gone.** The money axis is a branded pair — the emerald accent and the
logo coral — tuned per theme to clear WCAG AA on the background it sits on. A balance bar takes
the same tint as the amount above it, so the two read as one statement rather than two
coincidentally coloured things.

**The second colour is `#be185d`, not the logo's coral `#ed5167`.** Coral stays in the logo and
in the derivation of `MoneyNegative`.

---

## 3. Money

Money is what Spliit is for, so it has a typeface of its own rather than the semibold body text
it used to be: **SF Rounded, tabular figures, `-0.2` tracking.**

```swift
Money(value: formatter.string(minorUnits: balance.total),
      sign: Money.Sign(balance: balance.total))
```

**Four sizes**, chosen by how much the number matters on the screen it is on — and they are
`Font.TextStyle`s, not point sizes, so every amount scales with Dynamic Type:

| Size | Style | For |
|---|---|---|
| `.hero` | `.largeTitle` | A balance headline or a total. |
| `.lead` | `.title2` | A suggested payment. |
| `.row` | `.body` | A list row. The default. |
| `.support` | `.footnote` | An inline aside. |

`.hero` is what the balances tab leads with: your own balance, once you have said which
participant you are. `.support` is still spare, and stays because the scale is the point —
inventing a fifth size later is worse than leaving one over.

**Sign is carried by colour, and only where the amount has a direction.** An expense amount has
none, so it is `.primary`. A balance is positive, negative or settled — `Money.Sign(balance:)`
does that mapping, and `.settled` is `.secondary` rather than a third colour, because zero is
not an outcome worth tinting.

**One amount is drawn unsigned: your own balance**, at the top of the balances tab. It sits
under a sentence that says which way the money goes — "You are owed", "You owe" — and a minus
sign under that sentence says it twice while contradicting itself. Everywhere else the sign
stays on the number, because nothing beside it is saying so in words. The colour is the same
either way: it comes from the real, signed total.

**Reimbursements** render regular-weight and italic, matching how the expense list has always
drawn their titles.

**`.contentTransition(.numericText())`** is what the tabular figures bought: digits already sit
in fixed columns, so a balance that changes rolls to its new value instead of flickering to it.
It only shows when whatever changed the amount did so inside an animation — see §6.

**`moneyInput()`** gives an *editable* amount the same rounded, tabular face, so the number does
not change shape at the moment it stops being an input and becomes a total. Deliberately not
coloured or emphasised: it is a value being entered, not a balance being reported. It is on the
Amount field and the per-participant share and amount fields.

Three rules, all of which have already cost debugging time:

- **Never format in a view.** `value` is preformatted by `MoneyFormatter`, which is the only
  thing that knows a currency's minor-unit digits. See [CLAUDE.md](CLAUDE.md) on why dividing by
  100 is wrong 40 currencies out of 159.
- **Never split the currency symbol into an element of its own.** The UI suite asserts an
  amount's accessibility label is exactly what the formatter produced, and a screen reader
  reading "dollar" and "20.00" as two labels is the bug that assertion exists to catch.
- **Meaning goes on the name, not the amount.** VoiceOver cannot hear a colour, which leaves a
  lone minus sign carrying direction — so `BalanceRow` hangs "is owed" / "owes" / "settled up"
  on the participant's name as an accessibility *value*. The amount's label stays untouched.

---

## 4. People

Spliit has no accounts and no avatars, so a participant had only ever been a name in a row. A
monogram gives the eye something to find: **the same person is the same colour in the balances,
in the expense list, in a suggested payment and on the information tab, on every device.**

`Monogram` draws one or two initials in white on a filled circle, and comes in two flavours
because the two things it colours have different identities:

| | Rule | Why |
|---|---|---|
| **A participant** | `Monogram(name:position:)` — colour from their **position in the group** | Hashing four people into eight buckets collides more often than not, and two people sharing a colour in one group defeats the whole point. Positions are distinct, so nobody collides until a group passes eight members. The order comes from the server, so it is still the same colour on every device. |
| **A group** | `Monogram(name:seed:)` — colour from its **ID**, FNV-1a | The home screen reorders itself as groups are opened, so a position here would mean a group changing colour for having been looked at. Seeding on the ID rather than the name keeps the colour across a rename. |

The hash is hand-rolled because Swift's `hashValue` is seeded per process — using it would hand
everyone a new colour on every launch. `MonogramPaletteTests` records the actual mapping, which
is what will catch someone swapping the hash later and silently reshuffling every participant in
every group.

`ParticipantDot` is the same colour with the letters dropped, for rows where the names are
already spelled out in a sentence — the expense list's "Paid by …" line, and the group form's
participant fields. A monogram there would repeat the text and shout over it.

Sizes in use: 40 (a group row), 26 (a balance row, a participant on the information tab), 24
(either side of a suggested payment's arrow), 7–9 for a dot.

**Both are `accessibilityHidden`.** They repeat the name beside them, and left visible they are
one more element to swipe past on every row.

**Both cap their Dynamic Type growth** (`@ScaledMetric`, ×1.6 max). Growing with the text keeps
the chip in proportion with the name; the cap is what stops it from becoming the row — at the
largest accessibility size an uncapped circle is wider than the screen.

---

## 5. Rows, headers and empty screens

**`CategoryIcon`** leads an expense row with the category the list has always known and never
showed — it has been fetched since the first version and spent its life populating a picker. The
map lives in `Shared/ExpenseCategoryIcon.swift`, keyed `"<grouping>/<name>"` exactly as the web
app's `category-icon.tsx` keys it, so a taxi looks like a taxi in both products; anything the
server adds later falls through to `banknote`, as it does on the web. The slot is a **neutral**
`tertiarySystemFill`, not an accent tint: the amount is the only saturated thing in the row, and
a coloured tile beside it would compete for the glance.

An SF Symbol name that does not exist draws nothing and reports nothing, which is why the map is
in `Shared/` and `CategoryIconTests` asks the system to resolve every entry.

**`DateBucketHeader`** sets "This week" in bold small caps with wide tracking, so a bucket reads
as a rule between the expenses rather than an entry among them. The trap it documents: **`textCase`
is an environment value**, so uppercasing the heading also uppercased its accessibility label —
and passing a `Text` to `accessibilityLabel` does *not* fix it, because that `Text` gets
uppercased too. It has to be a plain `String`, which is why `ExpenseDateGroup.title` is one.

**`EmptyState`** replaced all of the app's `ContentUnavailableView`s. Those did the job correctly
and anonymously — a grey SF Symbol, a title, a line of text, identical in every app that ships
one. This keeps the shape and gives it the app's voice: the rounded display face for the title,
and art that is either the brand mark or an SF Symbol in a 64pt tile tinted `BrandAccentSoft`.

- **The logo appears on the welcome screen only.** `Logo.imageset` had shipped since the first
  commit and been referenced from nowhere. An error is not an occasion for branding, so errors
  get an icon.
- **The art does not scale with Dynamic Type.** It is decoration; growing it alongside the text
  only pushes the button further out of reach while saying nothing extra.
- **It centres when it fits and scrolls when it does not.** At the largest accessibility sizes a
  title, a description and two buttons are taller than the phone, and an empty state whose only
  action has fallen off the bottom is worse than no empty state at all.
  `testWelcomeActionsAreReachableAtTheLargestTextSize` pins this.

---

## 6. Motion

The app had no animation of any kind before this — most iOS motion is the platform's, but the
places where state changed on its own simply cut.

`Motion.base` is `easeInOut(duration: 0.22)`, and it is the only one. The design system names
three durations; two of them (a press, a push) are already animated by iOS before anyone writes
a line, and restating them here would only invite someone to override them.

Three places use it, each bound to the narrowest value that should trigger it:

| Bound to | Effect |
|---|---|
| `model.balances` | Settling a payment moves every figure and bar at once, rather than the screen merely being different the next time you look. |
| `model.expenses.count` | A deleted expense leaves rather than vanishing — and editing one in place does not animate the whole list along with it. |
| `model.pendingDeletion` | The undo bar arrives and leaves from the bottom edge. |

**Nothing bounces.** A spring on a row that is disappearing reads as a toy, and this is an app
people open at a restaurant table with one hand.

**There is no zoom transition into a group**, though the roadmap asked for one and it was built.
`.matchedTransitionSource` + `.navigationTransition(.zoom)` was tried on the group rows and read
as showy: the push is the movement iOS uses to say "deeper in", and the group screen is exactly
that rather than an expansion of the row. The comment at `GroupsListView.swift:28` is there to
stop it being re-added by someone reading the roadmap.

---

## 7. Glass, and haptics

**Glass belongs to what floats above content, never to content itself.** iOS 26 already draws
toolbars and the tab bar that way, so there is nothing to add there. What the app adds:

- The **undo bar** — a capsule over the tab bar, applied to the tab's content rather than the
  `TabView`, where it would land in the tab bar's own strip and the two would draw on top of
  each other.
- The **search field and its cancel button**, inside a `GlassEffectContainer(spacing: 10)`. Two
  glass surfaces ten points apart is exactly what the container is for: inside one they sample
  the same backdrop and bend toward each other as the gap closes.
- `.tabBarMinimizeBehavior(.onScrollDown)` on the group screen — reading a long list of expenses
  is what that screen is for, and the tab bar is not needed while it happens.

Glass on the balance and expense rows was considered and rejected. Those are content; making
them glass would undo §5 for the sake of ticking a roadmap line.

Two things that cost real time here: `.glassEffect` does **not** eat taps (`safeAreaInset` did —
`safeAreaBar` is the iOS 26 variant that works), and `.buttonStyle(.glass)` pads so generously
that a 44pt glyph came out 68×58 beside a 44pt field, which is why the search cancel button is
`.glassEffect(.regular.interactive(), in: .circle)` on a plain button instead.

**Haptics are attached to outcomes, not to gestures** — the moments where something was
committed, undone or refused, and where the screen alone may not have said so yet. There are
exactly four: `saved`, `refused`, `deleted` (soft, because for five seconds it is not decided),
`undone`. Deliberately absent: tapping a row, switching tabs, opening a sheet, typing in the
search field. A phone that buzzes at every tap teaches people to ignore it, and the one buzz
that mattered goes with it.

---

## 8. Where this departs from the design system

Recorded so nobody re-derives them:

**The groups list gets a group monogram, not a stack of participant monograms.** The system
specifies a card carrying the participants and a per-group balance. `Spliit.groups(ids:)` returns
`participantCount` and `createdAt` and no participant names or totals, so the specified card
costs one extra request per group on every launch — a product and performance decision rather
than a design one. Revisit if the home screen ever needs balances too; it is the same request.

**No spacing or radius token file.** The system specifies an 8/12/16 radius scale and a 4pt
spacing scale. `List` and `Form` already supply all of it, and a constants file nothing reads is
dead code.

**The welcome screen draws the wordmark, not a square mark.** The system specifies a 72×72
`logo-128.png`; what ships in this repo is the 522×180 wordmark, drawn 60pt tall. It names the
product, which is what a welcome screen is for.

**The hand-rolled diverging bar beat Swift Charts.** Charts is a dependency-sized concept for a
shape that is twenty lines of layout. The unused `import Charts` is gone.

**`BrandSecondary` is defined and currently unused.** It is `Monogram4`'s value, so the pink is
on screen, but nothing references the colour by that name. It stays because the palette is a
statement about what the brand *is*, and the money axis has no business borrowing it.

---

## 9. Working on this

**Put logic in the right place.** A view formats nothing and derives nothing: money goes through
`MoneyFormatter`, colours through `MonogramPalette`, symbols through `ExpenseCategoryIcon`. All
three are in packages or `Shared/`, which is why `make test` covers them in two seconds.

**Accessibility identifiers go on leaves, never containers** — an identifier on a styled card
erases every identifier inside it and the UI suite silently stops matching. They live in
`Shared/AccessibilityID.swift` and go in the same commit as the view.

**Decorative things get `.accessibilityHidden(true)`** — bars, monograms, dots, arrows, category
glyphs. Whatever a picture says, some text beside it already says.

**Adding a colour set, an image or a font needs `make generate`.** So does adding a Swift file.

Before opening a PR, look at the change in **dark mode**, at **Dynamic Type XXL**, and on a group
with one participant and no expenses:

```sh
make e2e-up && make e2e-seed && make run
make shot                     # → build/screenshot.png
```

Then the usual gate — `make test`, `make build`, and `make e2e` when marking the PR ready for
review. Before/after screenshots in the PR description are what makes a visual change reviewable.

**The UI suite pins some of what is described here**: the exact accessibility label of an amount,
tappable static text on group and expense rows, buttons labelled "Balances", "Amount" and
"Remove". Changing any of them is allowed — change the assertion in the same commit, deliberately,
rather than by discovering red CI.
