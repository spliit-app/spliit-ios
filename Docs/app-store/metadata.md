# App Store Connect — Spliit 2.0.0

Everything the listing needs, in the two languages it is published in, plus the screenshots and
the script that regenerates them.

Every fenced block below is meant to be copied whole. Their lines are long on purpose: App Store
Connect keeps the newlines it is given, so a description wrapped to fit this file would ship with
the wrap in it. The counts beside each heading are the limits App Store Connect enforces, and
they are checked, not estimated.

- **App**: Spliit — `app.spliit.spliitmobile`
- **Version**: 2.0.0, build 21 (the store has 1.2.0 (20); the build number must exceed it)
- **Replaces**: the Expo / React Native app, in place, on the same listing
- **Localizations**: English (U.S.) — primary, French (France)
- **Minimum iOS**: 26.0. Everyone below it keeps 1.2.0 through the App Store's
  last-compatible-version fallback; their data is untouched.

> **The one thing that blocks a submission outright:** there is no privacy policy page to link
> to, and App Store Connect will not take a submission without the URL. A draft ready to host is
> in §7. Everything else outstanding is a judgement call rather than a blocker — §8 is the list
> to work through.

---

## 1. Fields that are not translated

| Field | Value |
|---|---|
| Bundle ID | `app.spliit.spliitmobile` |
| Primary category | Finance |
| Secondary category | Productivity |
| Age rating | 4+ — no objectionable content of any kind |
| Copyright | `2026 Sebastien Castiel` |
| Price | Free, no in-app purchases |
| Marketing URL | `https://spliit.app` |
| Support URL | `https://github.com/spliit-app/spliit/issues` |
| Privacy policy URL | **needs deciding — see §7** |
| Sign-in required | No |
| Contains third-party content | No |
| Export compliance | Uses no non-exempt encryption (`ITSAppUsesNonExemptEncryption = false`) |
| Content rights | Does not contain, show or access third-party content |
| Advertising identifier | Not used |

**On the app name.** The listing's name stays **Spliit**. It is the name the existing users
installed, the name on the website, and the name in every link they have already shared. The
descriptive half belongs in the subtitle, which is what the subtitle is for.

---

## 2. English (U.S.)

### Subtitle — 27 / 30

```
Split expenses with friends
```

### Promotional text — 161 / 170

Editable without shipping a build, so it is the place to say what is true this month.

```
Rewritten from the ground up for iOS 26: native navigation, dark mode, search, Siri, and every currency counted properly. Now in French. Still no account needed.
```

### Keywords — 91 / 100

Commas, no spaces — a space costs a character and buys nothing. The app name is indexed already,
so "Spliit" is not repeated here, and neither is anything already in the subtitle.

```
bill,split,shared,cost,expense,group,trip,roommate,travel,settle,debt,budget,ledger,tab,iou
```

### Description

```
Spliit splits shared expenses without asking anyone to sign up.

Create a group, add the people in it, and send the link. Everyone who opens it sees the same expenses and the same balances — no accounts, no invitations, and no waiting for the slowest person in the group to install something.

WHAT IT DOES

• Groups for anything shared — a weekend away, a flatshare, a running tab at the office
• Expenses with a payer, a date, a category and a note
• Four ways to split: evenly, by shares, by percentage, or by exact amounts
• Balances showing who is up and who is down, and the fewest payments that settle the group
• Mark a suggested payment as paid and it becomes a reimbursement, in one tap
• Search a group's expenses by title instead of scrolling for them
• Star the groups you are in the middle of; archive the ones that are over
• Every currency the system knows, each counted the way it is actually counted — yen has no decimals, dinars have three

BUILT FOR iOS

This version is a complete rewrite in SwiftUI. It uses the system's own navigation, materials and typography, and it supports Dark Mode, Dynamic Type at every size, and VoiceOver. Ask Siri to open a group or start an expense in one, and find your groups from Spotlight. A shared spliit.app link opens the app and joins the group.

YOUR OWN SERVER, IF YOU WANT ONE

Spliit is open source. The app talks to spliit.app out of the box, and Settings will point it at any instance you host yourself — the same app, your data, your machine.

NOTHING TO SIGN IN TO

There is no account, no subscription and no trial. A group is reachable by its link, and the app remembers the groups you have opened. If you are upgrading from an earlier version, your groups come with you.

Free and open source: github.com/spliit-app
```

### What's New in This Version

```
Spliit for iOS has been rewritten from scratch in SwiftUI.

• Native navigation, Dark Mode and Dynamic Type at every size
• Balances redrawn as bars, with the fewest payments that settle the group
• Search a group's expenses instead of scrolling for them
• Star the groups you're in the middle of, archive the ones that are over
• Swipe to delete an expense, with five seconds to change your mind
• Siri and Spotlight: open a group, or start an expense in one
• Shared spliit.app links now open the app and join the group
• Every currency counted properly. Groups kept in yen were previously shown at a hundredth of their value, and are now right
• The app is now available in French

Your groups carry over. Still nothing to sign in to.
```

---

## 3. French (France)

### Sous-titre — 29 / 30

```
Dépenses partagées entre amis
```

### Texte promotionnel — 168 / 170

```
Entièrement réécrite pour iOS 26 : navigation native, mode sombre, recherche, Siri, et chaque devise comptée comme il faut. Désormais en français. Toujours sans compte.
```

### Mots-clés — 91 / 100

```
addition,partager,dépense,frais,groupe,voyage,coloc,rembourser,dette,budget,ami,note,compte
```

### Description

```
Spliit partage les dépenses communes sans demander à personne de créer un compte.

Créez un groupe, ajoutez les personnes qui en font partie, envoyez le lien. Tous ceux qui l'ouvrent voient les mêmes dépenses et les mêmes soldes — pas de compte, pas d'invitation, et personne à attendre.

CE QU'ELLE FAIT

• Un groupe pour tout ce qui se partage : un week-end, une colocation, les déjeuners du bureau
• Des dépenses avec un payeur, une date, une catégorie et une note
• Quatre façons de partager : équitablement, en parts, en pourcentage ou en montants exacts
• Des soldes qui montrent qui est à découvert et qui est en avance, et le plus petit nombre de paiements pour solder le groupe
• Un paiement suggéré devient un remboursement d'un seul geste
• Une recherche dans les dépenses du groupe, au lieu de les faire défiler
• Épinglez les groupes en cours, archivez ceux qui sont terminés
• Toutes les devises que le système connaît, chacune comptée comme elle se compte vraiment : le yen n'a pas de décimales, le dinar en a trois

PENSÉE POUR iOS

Cette version est une réécriture complète en SwiftUI. Elle utilise la navigation, les matières et la typographie du système, et prend en charge le mode sombre, le texte dynamique à toutes les tailles et VoiceOver. Demandez à Siri d'ouvrir un groupe ou d'y commencer une dépense, et retrouvez vos groupes depuis Spotlight. Un lien spliit.app partagé ouvre l'app et rejoint le groupe.

VOTRE PROPRE SERVEUR, SI VOUS EN VOULEZ UN

Spliit est un logiciel libre. L'app se connecte à spliit.app par défaut, et les réglages permettent de la pointer vers l'instance que vous hébergez vous-même — la même app, vos données, votre machine.

RIEN À QUOI SE CONNECTER

Aucun compte, aucun abonnement, aucune période d'essai. Un groupe s'atteint par son lien, et l'app se souvient de ceux que vous avez ouverts. Si vous venez d'une version précédente, vos groupes vous suivent.

Libre et open source : github.com/spliit-app
```

### Nouveautés de cette version

```
Spliit pour iOS a été entièrement réécrite en SwiftUI.

• Navigation native, mode sombre et texte dynamique à toutes les tailles
• Des soldes redessinés en barres, avec le plus petit nombre de paiements pour solder le groupe
• Une recherche dans les dépenses du groupe, au lieu de les faire défiler
• Épinglez les groupes en cours, archivez ceux qui sont terminés
• Balayez pour supprimer une dépense, avec cinq secondes pour changer d'avis
• Siri et Spotlight : ouvrez un groupe, ou commencez-y une dépense
• Les liens spliit.app partagés ouvrent maintenant l'app et rejoignent le groupe
• Chaque devise comptée correctement. Les groupes tenus en yens étaient jusqu'ici affichés au centième de leur valeur, c'est corrigé
• L'application est maintenant disponible en français

Vos groupes vous suivent. Toujours rien à quoi se connecter.
```

---

## 4. Screenshots

Six per language, per device size, in this order. The file names carry the order, so uploading
them sorted is enough.

| # | File | Shows |
|---|---|---|
| 1 | `01-groups` | The home screen: starred, recent and archived groups, with participant counts |
| 2 | `02-expenses` | A group's expenses in date buckets, each with its category and payer |
| 3 | `03-split` | One expense divided by exact amounts, with the four split modes above it |
| 4 | `04-balances` | Who is up, who is down, and the fewest payments that settle it |
| 5 | `05-information` | What the group is: its note, its participants, its currency |
| 6 | `06-search` | Searching the group's expenses, field docked above the keyboard |

```
Docs/app-store/screenshots/
├── en-US/
│   ├── iphone-6.9/   1320 × 2868   (iPhone 17 Pro Max)
│   └── ipad-13/      2064 × 2752   (iPad Pro 13-inch)
└── fr-FR/
    ├── iphone-6.9/
    └── ipad-13/
```

Both sizes are required: the app builds for `TARGETED_DEVICE_FAMILY = 1,2`, so App Store Connect
asks for a 6.9" iPhone set *and* a 13" iPad set. Apple derives every smaller size from these.

### Regenerating them

```sh
make screenshots                                    # every language, both sizes, ~6 min
Scripts/screenshots.sh --languages fr               # just French
Scripts/screenshots.sh --devices iphone-6.9         # just the iPhone set
```

The script drives `SpliitUITests/ScreenshotTests` against the throwaway instance from
`make e2e-up`, once per language, with `-testLanguage` so that both the interface *and* the
seeded data are in that language — the demo group is called "Weekend in Lisbon" in one and
"Week-end à Lisbonne" in the other. It boots a simulator of its own, sets **the device** to that
language too, pins it to light appearance and a 9:41 status bar, and exports the pictures out of
the result bundle into the tree above.

Two things it refuses to ship rather than warn about: a picture that is not the size App Store
Connect accepts, and a device that did not come up in the language that was asked for. The
second one matters because the app obeys `-testLanguage` while the status bar obeys the device,
so the failure looks like a correct screenshot until someone reads the date in the corner — and
on iPad the date is right there.

`make e2e` skips `ScreenshotTests`, and so does CI: it is not a test, and it would cost a minute
on every pull request to assert nothing.

What changes between two runs: the demo groups are created fresh and the server assigns new IDs,
and a monogram's colour is seeded from the ID — so the coloured circles differ from one run to
the next. Within a run they agree, which is what matters, and everything else is fixed. Two
consequences: never regenerate a single screenshot, and expect the iPhone and iPad sets of the
same language to disagree on colour, because they are two runs.

---

## 5. App Review information

No demo account is needed, and there is nothing to unlock. Paste this into the review notes:

```
Spliit needs no account and no credentials. Open the app, tap +, create a group, and every screen is reachable from there.

By default the app talks to the public instance at https://spliit.app. Settings → Server can point it at a Spliit instance the user hosts themselves — Spliit is open source and self-hosting is a documented, supported setup. No content is loaded from anywhere the user has not entered.

A group is addressed by an unguessable ID and shared as a link. There are no user accounts, no public feed, and no way to browse anyone else's group.

Source: https://github.com/spliit-app
```

**Worth knowing before the build goes up.** Universal Links (`applinks:spliit.app`) are declared
in the entitlements but stay inert until spliit.app serves an `apple-app-site-association` file
naming the App ID — see [Docs/universal-links.md](../universal-links.md). Nothing fails review
over it; the link simply opens the website instead of the app until that file is published.

---

## 6. App Privacy

Three answers. File exactly these, because they are what
[`Spliit/PrivacyInfo.xcprivacy`](../../Spliit/PrivacyInfo.xcprivacy) now declares, and the
questionnaire and the manifest are supposed to be two statements of the same fact.

| Questionnaire section | Data type | Used for | Linked to identity | Tracking |
|---|---|---|---|---|
| Contact Info | Name | App Functionality | No | No |
| User Content | Other User Content | App Functionality | No | No |
| Usage Data | Product Interaction | Analytics | No | No |

**Why group data is "collected" at all.** Apple counts data as collected once it leaves the
device and is kept longer than the request needs — which a group is, because the whole point of
a group is that it is still there tomorrow for everyone holding the link. Against the public
instance the server keeping it is the developer's, so it is declared, account or no account.

**Name** is the participant names, typed by whoever set the group up. They are labels on a split
rather than contact details — the app has no address book access, and asks for no email or
phone number anywhere — but a first name is a first name, and it is better declared than
explained away.

**Other User Content** is the group's own name and information note, and the title, notes and
amount of every expense. Deliberately *not* filed as financial information: Apple means salary,
assets and debts by that, and putting "Financial Info" on the privacy label for what a dinner
cost would say something untrue about the app.

**Nothing is linked to identity**, in all three cases, because there is nothing to link it to.
Spliit has no accounts, no user identifier, and no way to list the groups a person belongs to —
a group is reachable by its link and by nothing else.

**Product Interaction** is the Plausible screen views and the two events (a group created, an
expense created). Plausible is cookieless and stores no per-person identifier, and nothing is
sent from debug builds or under UI tests.

Everything else is a clean no: no tracking, no advertising identifier, no data brokers, no data
shared with third parties, no email address or phone number, no location, no identifiers, no
health, financial-account or purchase data. The app asks for no system permissions at all — it
shows no permission prompt of any kind.

**Required-reason APIs.** One: `UserDefaults`, under `CA92.1` — read and write only this app's
own data, never another app's. That is `SettingsStore` keeping the instance address. The app
touches none of the other required-reason categories (file timestamps, disk space, boot time,
active keyboards), which is worth knowing because an undeclared one is rejected on **upload**,
by an automated mail, rather than at review.

---

## 7. The privacy policy URL

**App Store Connect will not accept a submission without one, and there is no page to point at.**
`spliit.app` has no privacy route — the Next.js app has `groups`, `api` and the marketing page,
and nothing else.

So one has to be published before submission. Below is a draft that describes what the app
actually does, ready to be hosted at `https://spliit.app/privacy` and reviewed by someone
qualified to sign it off. It is a description of behaviour, not legal advice.

```
Spliit — Privacy

Spliit has no user accounts. You are never asked for a name, an email address, or a password,
and nothing you do in the app is attached to an identity.

What is stored. The groups you create — their names, their participants' names, and the
expenses in them — are stored on the Spliit server the app is pointed at. By default that is
spliit.app. A group is reachable by its link and by nothing else: there is no directory, no
search across groups, and no way to list them.

What stays on your device. The list of groups you have opened, and the address of the server
you use. Neither leaves the device.

Analytics. The app reports which screens are opened, and two events — a group created and an
expense created — to Plausible Analytics. Plausible is cookieless, sets no identifier, and
collects no personal data. There is no advertising, no tracking across apps or websites, and no
data sold or shared with brokers.

Self-hosting. Spliit is open source. If you point the app at your own instance in Settings, your
groups are stored on your server and nothing about them reaches spliit.app.

Deleting your data. A group can be removed from the list on your device at any time. To have a
group deleted from the spliit.app server, write to <contact address>.

Contact. <contact address>
```

The contact address is the one gap the app cannot fill in for itself.

App Store Connect takes a privacy policy URL **per localization**, so the French listing needs
either a translated page of its own or the same URL pointing at a page that carries both. That
follows the decision about where the page lives, so it is not drafted here.

---

## 8. Before you submit

- [ ] Publish a privacy policy and put its URL in App Store Connect (§7)
- [ ] File the three App Privacy answers in §6. The manifest already declares them, so this is
      filling in the questionnaire to match — not a decision. **This is the change that needs a
      new build:** `PrivacyInfo.xcprivacy` ships inside the binary, so whatever is uploaded must
      be built after it
- [ ] Look at the iPad screenshots. SwiftUI does adapt: the tabs become a pill in the navigation
      bar and the rows go full width, so it is a real iPad layout rather than a blown-up phone.
      But nothing has been *designed* for the size — the roadmap defers that to M4 — and it
      shows: a row runs the full thirteen inches with the amount stranded at the far end, and a
      list of nine expenses leaves the bottom half of the screen empty. It will pass review.
      Whether it is the first impression the listing wants is a judgement call, and the
      alternative — dropping `TARGETED_DEVICE_FAMILY` to iPhone only — is a product decision
      with a cost of its own
- [ ] Decide whether **"Également"** is the word for the *Evenly* split mode. It is in
      `03-split` in both French sets, so the listing ships it. Beside "Parts", "Pourcent" and
      "Montant" it reads as *also* rather than *equally* — "Égal" or "Équitable" would fit the
      segment and say the thing. It is one string in `Localizable.xcstrings`, and it belongs to
      the French pass rather than to this change, so nothing here touched it
- [ ] Confirm the build number exceeds 20 — `project.yml` says 21. If build 21 has *already*
      been uploaded, the privacy-manifest change needs 22: a build number cannot be reused
- [ ] Check what share of the installed base is below iOS 26; they stay on 1.2.0
- [ ] Serve `apple-app-site-association` from spliit.app if Universal Links should work on day
      one ([Docs/universal-links.md](../universal-links.md))
