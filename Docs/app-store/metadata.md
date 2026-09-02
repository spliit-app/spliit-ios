# App Store Connect — Spliit 2.2.0

Everything the listing needs, in the two languages it is published in, plus the screenshots and
the script that regenerates them.

Every fenced block below is meant to be copied whole. Their lines are long on purpose: App Store
Connect keeps the newlines it is given, so a description wrapped to fit this file would ship with
the wrap in it. The counts beside each heading are the limits App Store Connect enforces, and
they are checked, not estimated.

- **App**: Spliit — `app.spliit.spliitmobile`
- **Version**: 2.2.0, build 24, uploaded and attached to the 2.2 record. 2.1.0 is approved,
  which *closes* that train — a further build for it is refused with 90186, and 90062 beside it
  asking for a higher marketing version. So the first upload after a release moves both numbers,
  not just the build
- **Filed already**: everything in §2 and §3 is in App Store Connect on the 2.2 record, and the
  framed screenshots from §4 are uploaded against both device sizes in both languages. What is
  left before submitting is §8
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

### Promotional text — 160 / 170

Editable without shipping a build, so it is the place to say what is true this month.

```
Your groups follow you to a new phone, kept in iCloud. Join one by scanning its QR code. Split what you spent, see who owes whom, settle up — no account needed.
```

It does not survive a new version: App Store Connect carries the description and the keywords
forward when a version record is created and leaves this one empty, so a release that does not
rewrite it drops it from the live page instead of keeping the old one.

### Keywords — 93 / 100

Commas, no spaces — a space costs a character and buys nothing. The app name is indexed already,
so "Spliit" is not repeated here, and neither is anything already in the subtitle.

"receipt" and "scan" cost "ledger" and "iou" their places: the two of them together do not fit
under 100 otherwise, and what people type when they want this feature is the noun on the paper.

```
bill,split,shared,cost,expense,group,trip,roommate,travel,settle,debt,budget,receipt,scan,tab
```

### Description

```
Spliit splits shared expenses without asking anyone to sign up.

Create a group, add the people in it, and send the link. Everyone who opens it sees the same expenses and the same balances — no accounts, no invitations, and no waiting for the slowest person in the group to install something.

WHAT IT DOES

• Groups for anything shared — a weekend away, a flatshare, a running tab at the office
• Expenses with a payer, a date, a category and a note
• Point your phone at a receipt and the expense fills itself in — the total, the date and the category are read on the device, and yours to correct before anything is saved
• Keep receipts and other documents with the expense they belong to
• Four ways to split: evenly, by shares, by percentage, or by exact amounts
• Balances showing who is up and who is down, and the fewest payments that settle the group
• Totals for the group and for you, and where the money actually went, by category
• Mark a suggested payment as paid and it becomes a reimbursement, in one tap
• An activity log for every group: what has happened to it, and who did it
• Search a group's expenses by title instead of scrolling for them
• Star the groups you are in the middle of; archive the ones that are over
• Every currency the system knows, each counted the way it is actually counted — yen has no decimals, dinars have three

BUILT FOR iOS

Spliit for iOS is a complete rewrite in SwiftUI. It uses the system's own navigation, materials and typography, and it supports Dark Mode, Dynamic Type at every size, and VoiceOver. Receipts are read on the device itself. Ask Siri to open a group or start an expense in one, and find your groups from Spotlight. A shared spliit.app link opens the app and joins the group.

YOUR OWN SERVER, IF YOU WANT ONE

Spliit is open source. The app talks to spliit.app out of the box, and every group can be on a Spliit instance you host yourself — one list, whichever servers your groups are on.

NOTHING TO SIGN IN TO

There is no account, no subscription and no trial. A group is reachable by its link, and the app remembers the groups you have opened. If you are upgrading from an earlier version, your groups come with you.

Free and open source: github.com/spliit-app
```

### What's New in This Version

```
Your list of groups now follows you to a new phone.

• The groups you have opened are kept in iCloud, so a new phone opens on the same list as the old one — nothing to export, and nothing to set up again
• Join a group by holding up its QR code, and show yours from the group's information tab
• Groups can now live on different Spliit servers — the public one and your own — side by side in the same list
• A clearer home screen, with settings moved down within reach of your thumb

Still no account, and still nothing to sign in to.
```

---

## 3. French (France)

### Sous-titre — 29 / 30

```
Dépenses partagées entre amis
```

### Texte promotionnel — 162 / 170

```
Vos groupes vous suivent sur un nouveau téléphone, gardés dans iCloud. Rejoignez-en un avec son QR code. Partagez les dépenses, voyez qui doit quoi — sans compte.
```

### Mots-clés — 93 / 100

Comme en anglais, "reçu" et "scanner" prennent la place de deux autres — ici "ami" et "compte".

```
addition,partager,dépense,frais,groupe,voyage,coloc,rembourser,dette,budget,reçu,scanner,note
```

### Description

```
Spliit partage les dépenses communes sans demander à personne de créer un compte.

Créez un groupe, ajoutez les personnes qui en font partie, envoyez le lien. Tous ceux qui l'ouvrent voient les mêmes dépenses et les mêmes soldes — pas de compte, pas d'invitation, et personne à attendre.

CE QU'ELLE FAIT

• Un groupe pour tout ce qui se partage : un week-end, une colocation, les déjeuners du bureau
• Des dépenses avec un payeur, une date, une catégorie et une note
• Photographiez un reçu et la dépense se remplit d'elle-même : le montant, la date et la catégorie sont lus sur l'appareil, et vous les corrigez avant d'enregistrer quoi que ce soit
• Gardez les reçus et les autres documents avec la dépense à laquelle ils appartiennent
• Quatre façons de partager : équitablement, en parts, en pourcentage ou en montants exacts
• Des soldes qui montrent qui est à découvert et qui est en avance, et le plus petit nombre de paiements pour solder le groupe
• Des totaux pour le groupe et pour vous, et où l'argent est vraiment passé, par catégorie
• Un paiement suggéré devient un remboursement d'un seul geste
• Un journal d'activité pour chaque groupe : ce qui lui est arrivé, et qui l'a fait
• Une recherche dans les dépenses du groupe, au lieu de les faire défiler
• Épinglez les groupes en cours, archivez ceux qui sont terminés
• Toutes les devises que le système connaît, chacune comptée comme elle se compte vraiment : le yen n'a pas de décimales, le dinar en a trois

PENSÉE POUR iOS

Spliit pour iOS est une réécriture complète en SwiftUI. Elle utilise la navigation, les matières et la typographie du système, et prend en charge le mode sombre, le texte dynamique à toutes les tailles et VoiceOver. Les reçus sont lus sur l'appareil lui-même. Demandez à Siri d'ouvrir un groupe ou d'y commencer une dépense, et retrouvez vos groupes depuis Spotlight. Un lien spliit.app partagé ouvre l'app et rejoint le groupe.

VOTRE PROPRE SERVEUR, SI VOUS EN VOULEZ UN

Spliit est un logiciel libre. L'app se connecte à spliit.app par défaut, et chaque groupe peut vivre sur une instance que vous hébergez vous-même — une seule liste, quels que soient les serveurs de vos groupes.

RIEN À QUOI SE CONNECTER

Aucun compte, aucun abonnement, aucune période d'essai. Un groupe s'atteint par son lien, et l'app se souvient de ceux que vous avez ouverts. Si vous venez d'une version précédente, vos groupes vous suivent.

Libre et open source : github.com/spliit-app
```

### Nouveautés de cette version

```
Votre liste de groupes vous suit désormais sur un nouveau téléphone.

• Les groupes que vous avez ouverts sont conservés dans iCloud : un nouveau téléphone retrouve la même liste que l'ancien — rien à exporter, rien à reconfigurer
• Rejoignez un groupe en scannant son QR code, et affichez le vôtre depuis l'onglet Informations du groupe
• Les groupes peuvent maintenant vivre sur différents serveurs Spliit — le public et le vôtre — côte à côte dans la même liste
• Un écran d'accueil plus clair, avec les réglages à portée de pouce

Toujours pas de compte, et toujours rien à quoi se connecter.
```

---

## 4. Screenshots

Five per language, per device size, in this order. The file names carry the order, so uploading
them sorted is enough.

| # | File | Shows | Headline |
|---|---|---|---|
| 1 | `01-groups` | The home screen: starred, recent and archived groups, with participant counts | Every trip, every flatshare, in one place |
| 2 | `02-expenses` | A group's expenses in date buckets, each with its category and payer | Add what you spent, in seconds |
| 3 | `03-split` | One expense divided by exact amounts, with the four split modes above it | Split it the way it actually happened |
| 4 | `04-balances` | Who is up, who is down, and the fewest payments that settle it | Know exactly who owes whom |
| 5 | `05-totals` | What the group spent, how much of it is yours, and the breakdown by category | See what it really cost |

Five rather than every screen the app has: the group information tab, the activity log and the
search field are all real features and none of them is why anybody installs an expense splitter.
The first two or three appear in search results at thumbnail size, which is the whole argument
for a short set with a large headline on each.

Receipt scanning is the one headline feature with no picture, and there is no honest way to take
one: a simulator has no camera, and the stand-in the suite uses is the OCR fixture — monospaced
black on white, drawn to be easy to recognise rather than to be looked at. A shot of it would
read as a bug. Photographing it properly needs receipt artwork made for the purpose, which is a
design decision rather than a mechanical one.

The pictures exist twice. `screenshots/` is what the simulator photographed — the app, and
nothing else. `marketing/` is the same picture wrapped in the listing's artwork, and **that is
the tree to upload**.

```
Docs/app-store/
├── captions.json                     the headline on each shot, per locale
├── screenshots/                      raw captures — the source of truth
│   ├── en-US/
│   │   ├── iphone-6.9/   1320 × 2868   (iPhone 17 Pro Max)
│   │   └── ipad-13/      2064 × 2752   (iPad Pro 13-inch)
│   └── fr-FR/…
└── marketing/                        the same, framed — upload these
    ├── en-US/…
    └── fr-FR/…
```

Keeping both is what makes the artwork cheap to change: `Scripts/frame-screenshots.swift` draws
the gradient, the headline and the device over a capture in about three seconds for the whole
set, so a new headline or a different green never means photographing the app again. It is
AppKit and nothing else — no dependency, and the same SF the screenshots inside the frame were
drawn with.

Two details in there that are not arbitrary. The gradient runs *dark at the top* because white
display type on `#10B981` is about 2.5:1, under the 3:1 floor for large text, and the headline
sits at the top. And a headline whose longest line would run past the margin shrinks to fit,
which French needs on three of the five — but the grid it sits on stays the size English uses,
so the device below starts at the same height in both languages.

Both sizes are required: the app builds for `TARGETED_DEVICE_FAMILY = 1,2`, so App Store Connect
asks for a 6.9" iPhone set *and* a 13" iPad set. Apple derives every smaller size from these.

### Regenerating them

```sh
make screenshots                                    # capture and frame everything, ~25 min
make frames                                         # re-frame what is already captured, ~3 s
Scripts/screenshots.sh --languages fr               # just French
Scripts/screenshots.sh --devices iphone-6.9         # just the iPhone set
```

`make frames` is the one to reach for nine times out of ten: the headlines in `captions.json`
and everything about how a shot is dressed are its input, and none of it needs the simulator.

The script drives `SpliitUITests/ScreenshotTests` against the throwaway instance from
`make e2e-up`, once per language, with `-testLanguage` so that both the interface *and* the
seeded data are in that language — the demo group is called "Weekend in Lisbon" in one and
"Week-end à Lisbonne" in the other. It boots a simulator of its own, sets **the device** to that
language too, pins it to light appearance and a 9:41 status bar, and exports the pictures out of
the result bundle into the tree above, then frames the lot.

Two things it refuses to ship rather than warn about: a picture that is not the size App Store
Connect accepts, and a device that did not come up in the language that was asked for. The
second one matters because the app obeys `-testLanguage` while the status bar obeys the device,
so the failure looks like a correct screenshot until someone reads the date in the corner — and
on iPad the date is right there.

`make e2e` skips `ScreenshotTests`, and so does CI: it is not a test, and it would cost a minute
on every pull request to assert nothing.

**One thing the screenshots settled.** The split-mode segments read "Équitable / Parts / % /
Montant" in French, and two of those words were changed to get there. "Également" is the adverb
*also*; it is what the web app uses and it works there, because its dropdown spells the options
out in full and "Également" stands against "Inégalement – Par parts". Alone in a segmented
control the contrast is gone. And "Pourcent" is not a French word — but "Pourcentage" truncates
to "Pourcent…" on a 375pt iPhone, which is worse than what it replaced, so the segment carries
the symbol the share fields already use.

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

By default a group is created on the public instance at https://spliit.app. Each group can instead be on a Spliit instance the user hosts themselves — chosen when the group is created, or taken from the link they paste to add one — and Spliit is open source, with self-hosting a documented, supported setup. No content is loaded from anywhere the user has not entered.

A group is addressed by an unguessable ID and shared as a link. There are no user accounts, no public feed, and no way to browse anyone else's group.

Receipt scanning, new in this version: open a group, add an expense, and choose "Scan receipt". The camera permission is requested there and nowhere else, and a photo already in the library works just as well as a new one — any till receipt will do. The picture is read entirely on the device: Vision recognises the text, and Apple's on-device model reads the layout where the hardware supports it. Nothing about the image is sent anywhere to be recognised. On a device without Apple Intelligence the same screen works from the text recognition alone, so the feature can be exercised on any supported device. Whatever it finds is filled into the form for the tester to correct before anything is saved.

Attaching the receipt to the expense is a separate and optional step. That step, and only that step, uploads the image — to the same instance the group is on.

Source: https://github.com/spliit-app
```

**Worth knowing before the build goes up.** Universal Links (`applinks:spliit.app`) are declared
in the entitlements but stay inert until spliit.app serves an `apple-app-site-association` file
naming the App ID — see [Docs/universal-links.md](../universal-links.md). Nothing fails review
over it; the link simply opens the website instead of the app until that file is published.

---

## 6. App Privacy

Four answers. File exactly these, because they are what
[`Spliit/PrivacyInfo.xcprivacy`](../../Spliit/PrivacyInfo.xcprivacy) now declares, and the
questionnaire and the manifest are supposed to be two statements of the same fact.

| Questionnaire section | Data type | Used for | Linked to identity | Tracking |
|---|---|---|---|---|
| Contact Info | Name | App Functionality | No | No |
| User Content | Other User Content | App Functionality | No | No |
| User Content | Photos or Videos | App Functionality | No | No |
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

**Photos or Videos** is receipts, and any other document attached to an expense. The picture is
uploaded to the instance's object storage and the expense keeps only the address it landed at,
so it leaves the device and is kept — which is what makes it collected, on the same reasoning as
the group itself.

*Reading* a receipt is not what puts it on this list. Vision and the on-device model both run on
the phone, and a scan the user abandons rather than attaches uploads nothing at all. Attaching is
what transmits, and the two are separate actions in the app.

**Nothing is linked to identity**, in all four cases, because there is nothing to link it to.
Spliit has no accounts, no user identifier, and no way to list the groups a person belongs to —
a group is reachable by its link and by nothing else.

**Product Interaction** is the Plausible screen views and the two events (a group created, an
expense created). Plausible is cookieless and stores no per-person identifier; the screen name
is the whole payload, with no group or expense ID attached. Nothing is sent from debug builds
or under UI tests.

**Exchange rates are not a data type.** An expense recorded in a currency the group is not
counted in asks frankfurter.dev for that day's published rate. The request carries a date and
two currency codes and nothing else — no identifier, no user content, nothing kept on the other
end that belongs to anyone — so there is nothing to declare. It is named in the privacy policy
because a request leaving the device is worth saying out loud, not because it collects anything.

Everything else is a clean no: no tracking, no advertising identifier, no data brokers, no data
shared with third parties, no email address or phone number, no location, no identifiers, no
health, financial-account or purchase data.

**One system permission, as of 2.1.0.** The camera, asked for the first time a receipt is
photographed, with `NSCameraUsageDescription` — "Spliit reads receipts you photograph, on your
iPhone" — declared in `project.yml` and translated in `Spliit/Resources/InfoPlist.xcstrings`.
That string is one of the few `make strings` cannot check, because the compiler never extracts
it, so its French goes in by hand and stays that way. There is deliberately no photo-library
counterpart: `PhotosPicker` runs out of process and hands back only what was chosen, and nothing
in the app writes to the library, so neither `NSPhotoLibraryUsageDescription` nor
`NSPhotoLibraryAddUsageDescription` applies.

**Required-reason APIs.** One: `UserDefaults`, under `CA92.1` — read and write only this app's
own data, never another app's. That is `SettingsStore` keeping which instance a new group starts
on. The app touches none of the other required-reason categories (file timestamps, disk space, boot time,
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

Receipts and documents. If you attach a receipt or another document to an expense, the file is
uploaded to the storage belonging to the server you are using, and the expense records where it
was put. Anyone with the group's link can open it, as they can the rest of the group.

Reading a receipt is not the same as attaching one. When you scan a receipt, the picture is read
on your device — the text recognition and the model that interprets it both run on your iPhone,
and the image is not sent anywhere to be read. If you do not attach it, it is never uploaded at
all.

What stays on your device. The list of groups you have opened, and the address of the server
you use. Neither leaves the device.

Analytics. The app reports which screens are opened, and two events — a group created and an
expense created — to Plausible Analytics. The name of the screen is all that is sent: no group
or expense identifier goes with it, so a report cannot be traced back to a group of yours.
Plausible is cookieless, sets no identifier, and collects no personal data. There is no advertising, no tracking across apps or websites, and no
data sold or shared with brokers.

Exchange rates. When you record an expense in a currency your group is not counted in, the app
asks frankfurter.dev for that day's published rate. The request carries a date and two currency
codes, and nothing about you or your group. You can type the rate yourself instead.

Self-hosting. Spliit is open source. A group on an instance you host yourself is stored on your
server, and nothing about it reaches spliit.app.

Deleting your data. A group can be removed from the list on your device at any time. To have a
group deleted from the spliit.app server, write to <contact address>.

Removing a document from an expense removes the link to it, but does not delete the stored file:
the app has no permission to delete from the server's storage, and neither has the website. A
file you have uploaded can only be removed by whoever runs the server, so write to the address
below if you need one taken down.

Contact. <contact address>
```

The contact address is the one gap the app cannot fill in for itself.

App Store Connect takes a privacy policy URL **per localization**, so the French listing needs
either a translated page of its own or the same URL pointing at a page that carries both. That
follows the decision about where the page lives, so it is not drafted here.

---

## 8. Before you submit

- [x] ~~Publish a privacy policy and put its URL in App Store Connect (§7).~~ `https://spliit.app/privacy-policy` is live and set on both localizations
- [ ] File the four App Privacy answers in §6. The questionnaire is filed per version, so 2.2.0
      needs it again even though nothing about the answers changed since 2.1.0 — the manifest
      declares all four and build 24 carries it, so this is filling the questionnaire in to
      match, not a decision
- [ ] Answer the age-rating questionnaire's AI questions honestly rather than by reflex. Spliit's
      only model use is reading a receipt you photographed, on the device, into four fields you
      then correct — it generates nothing, shows the user no free-form text, and is not a
      chatbot. Apple has been revising these questions, so read what is actually asked at the
      time rather than trusting this line
- [ ] Look at the iPad screenshots. SwiftUI does adapt: the tabs become a pill in the navigation
      bar and the rows go full width, so it is a real iPad layout rather than a blown-up phone.
      But nothing has been *designed* for the size — the roadmap defers that to M4 — and it
      shows: a row runs the full thirteen inches with the amount stranded at the far end, and a
      list of nine expenses leaves the bottom half of the screen empty. It will pass review.
      Whether it is the first impression the listing wants is a judgement call, and the
      alternative — dropping `TARGETED_DEVICE_FAMILY` to iPhone only — is a product decision
      with a cost of its own
- [x] ~~Upload a build.~~ **2.2.0 (24) is uploaded, processed and attached to the 2.2 record** —
      the groups list in iCloud, joining by QR code, a server address per group and the reworked
      home screen. Both numbers moved together, 2.1.0 being approved having closed that train.
      Apple mails you if processing fails after an upload that reported success
- [x] ~~Fill in the listing.~~ Release notes, promotional text and the five framed screenshots
      are on the 2.2 record in both languages, and the description and keywords carried forward
      from 2.1.0 untouched
- [ ] Check what share of the installed base is below iOS 26; they stay on 1.2.0
- [ ] Serve `apple-app-site-association` from spliit.app if Universal Links should work on day
      one ([Docs/universal-links.md](../universal-links.md))
