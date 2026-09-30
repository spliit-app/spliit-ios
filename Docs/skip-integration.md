# Android integration with Skip

Status: phases 1 and 2 complete in `skip-integration-plan`, based on upstream commit
`80b2e984b3dc07782983f24586d7e4568ada2a02`. Phases 1 and 2 are pushed. Phase 3 is in progress.
The shared expense flow works on Android and iOS. Phase 3 product coverage and the
platform libraries remain to be verified.

## Recommendation

Prototype **Skip Fuse + SkipFuseUI**, sharing the existing API, business logic, and ordinary
screens. Use Skip's platform libraries for camera/media selection, QR scanning, and review
prompts. Keep Apple's integrations on iOS and add Android implementations only where needed.

This is a practical porting candidate, but adding the Skip dependency alone will not make the
current app compile for Android. The first milestone is one working expense flow on both
platforms; use that result to decide whether to proceed with the rest.

## Why Fuse fits this codebase

[SpliitKit](../Packages/SpliitKit/Package.swift) already separates `SpliitAPI` and `SpliitCore`
from the UI, with no third-party dependencies. They contain roughly 5,200 lines of Swift,
including networking, superjson coding, validation, expense splitting, currency handling,
local storage, and receipt-text parsing. `Spliit/` contains roughly 8,200 lines, including
views and Apple integrations. Counts include comments and exclude tests and resources.

Fuse compiles Swift natively for Android; Lite transpiles Swift into Kotlin. Prefer native
Swift here to retain language and arithmetic behavior: `ExpenseShares` uses `Int128`,
UTF-16 ordering, and wrapping FNV-1a hashing to match the server's allocation of leftover
minor units. `MoneyFormatter` uses `Decimal` and Foundation formatters. These deserve tests
on Android, not rewrites to accommodate a transpiler.

Fuse supports the Swift standard library and Foundation, but does not supply Apple's entire
framework ecosystem. Its UI is rendered through the Skip compatibility layer and Jetpack
Compose. Tradeoffs include larger Android binaries, slower builds, and harder native Swift
debugging. Lite modules can coexist with Fuse through bridging, which is useful for platform
libraries. See [Skip modes](https://skip.dev/docs/modes/).

## Libraries to use

| Library | Application here | Boundary to verify |
| --- | --- | --- |
| [SkipFuse / SkipFuseUI](https://skip.dev/docs/modules/skip-fuse-ui/) | Compile Swift for Android and share supported SwiftUI views and state. | Verify `@Observable` updates across module boundaries; use the documented conditional imports and configuration. This is not complete SwiftUI API parity. |
| [SkipKit](https://skip.dev/docs/modules/skip-kit/) | Camera capture, photo-library selection, and permissions for receipt attachments. | A picker does not replace document edge detection, OCR, image normalization, or the custom zoomable gallery. Check the selected APIs' Fuse bridging and Android manifest requirements. |
| [SkipQRCode](https://skip.dev/docs/modules/skip-qrcode/) | Replace the Android side of `ScanGroupQRCodeView` with its scanner. | Uses VisionKit on iOS and ML Kit + CameraX on Android; documents Fuse bridging. Test permissions, cancellation, repeated scans, and existing group-link validation. |
| [SkipMarketplace](https://skip.dev/docs/modules/skip-marketplace/) | Display a platform review prompt after `ReviewPromptStore` decides to ask. | Its review API wraps App Store and Google Play prompts. Reconcile its throttling with the existing store; keep the decision logic and tests. |

Add each optional dependency when implementing its feature. Do not add Firebase, Supabase,
authentication, or a replacement database just to port the app. The existing Spliit server
and local persistence remain the starting point. Pin compatible versions after a successful
prototype; examples in documentation are not a tested dependency set for this repository.

## Code that needs attention

| Current code | Planned treatment |
| --- | --- |
| [SpliitAPI](../Packages/SpliitKit/Sources/SpliitAPI) | Reuse the tRPC client, DTOs, superjson handling, and signed document-upload protocol. Check Android networking imports and `URLSessionConfiguration` behavior. |
| [SpliitCore](../Packages/SpliitKit/Sources/SpliitCore) | Reuse validation, money, splits, receipt parser, and file-backed stores. Isolate Apple-only cloud and legacy-migration code. Verify localization and persistence paths. |
| [AppModel](../Spliit/AppModel.swift), [GroupDetailModel](../Spliit/GroupDetailModel.swift) | Retain coordination logic. Make platform startup conditional and verify Observation, main-actor behavior, cancellation, and lifecycle callbacks. |
| [GroupDetailView](../Spliit/Views/GroupDetailView.swift), [ExpenseSearchView](../Spliit/Views/ExpenseSearchView.swift), [GroupsListView](../Spliit/Views/GroupsListView.swift), [UndoBar](../Spliit/Views/DesignSystem/UndoBar.swift) | Share screen logic while adapting iOS 26 presentation: glass effects, `safeAreaBar`, toolbar spacers, search-tab role, and tab minimization. Check exact support against pinned Skip versions. |
| [Documents](../Spliit/Documents), [ReceiptPhoto](../Spliit/Receipts/ReceiptPhoto.swift) | Integrate media selection and implement Android image handling. `UIImage`, `CGImage`, `UIGraphicsImageRenderer`, and the UIKit zoom view need alternatives. |
| [ReceiptScanner](../Spliit/Receipts/ReceiptScanner.swift) | Keep Vision/FoundationModels on iOS. Feed Android OCR output into the existing `ReceiptText` parser. |
| [Intents](../Spliit/Intents), [ReviewPrompt](../Spliit/Views/ReviewPrompt.swift) | Keep Siri/AppIntents on iOS. Route Android links through existing parsing; use SkipMarketplace for review presentation. |

### Receipt reading and attachments

No general OCR wrapper was found in Skip's documented module catalog during this review.
Use [ML Kit text recognition](https://developers.google.com/ml-kit/vision/text-recognition/v2/android)
through a small Android integration. Map recognized lines and their bounding boxes into
`ReceiptText.Block`, normalizing orientation, coordinates, and the vertical axis before
calling `ReceiptText.rows(of:)`. A plain concatenated transcript can separate prices from
their labels and produce an incorrect total.

Start with OCR plus the existing deterministic parser. Apple's optional FoundationModels
enhancement remains iOS-only initially. For offline scanning from first use, evaluate the
bundled ML Kit model rather than assuming a downloaded model is already present. Test
French and English receipts, decimal separators, layout reconstruction, and unreadable photos.

Preserve the existing image contract: normalize orientation, cap the longest side at 2048
pixels, encode JPEG within 5 MiB, report the encoded dimensions, and remove location/other
unnecessary EXIF metadata. Preserve upload-before-save behavior and unsupported-storage
handling. Scanning stays on device; attaching the photo still uploads it to the selected
Spliit instance's bucket. A new implementation must keep that distinction clear.

### Group recovery and migration

`NSUbiquitousKeyValueStore` is Apple-only. The existing `RecentGroupsCloudStorage` boundary
already allows `nil`, so the prototype can use the current local file with cloud disabled
on Android. Do not add an account system for the prototype.

A release needs a deliberate recovery path, such as tested Android backup/restore or explicit
export/import. These are proposals to validate, not substitutes already implemented. Group
IDs and instance URLs are essential access information; losing the list can strand users.
Android backup is also not live iPhone-to-Android synchronization. If cross-platform sync
becomes a requirement, design it separately and retain the existing merge/tombstone semantics.

[LegacyAsyncStorage](../Packages/SpliitKit/Sources/SpliitCore/LegacyAsyncStorage.swift) reads
the iOS React Native layout and imports CryptoKit for legacy filenames. Exclude that path
from Android rather than adding crypto solely for an irrelevant migration. If replacing a
previous Android app, first inspect its actual storage, application ID, and signing ownership;
implement and test its migration separately. Preserve legacy data and never overwrite a
successfully recovered list with an empty one.

## Implementation sequence

### 1. Establish the toolchain and compile the core

- Work in a branch/worktree as required by [CLAUDE.md](../CLAUDE.md).
- Verify the current iOS baseline with `make test` and `make build`.
- Follow Skip's [package porting guide](https://skip.dev/docs/porting/), checking the installed
  Xcode, Swift Android SDK, JDK, and Android SDK versions together. Record working versions.
- In `Packages/SpliitKit`, try `skip android build`, then `skip android test` after the SDK
  is installed. Keep the existing Swift Testing suites; resolve unsupported tests explicitly.
- Address Foundation networking imports, Apple cloud code, and legacy migration conditionally.
  Check file paths, `UserDefaults`, `Bundle.module` resources, formatting, and cancellation.

Exit criterion: the portable core builds and its applicable tests pass on Android and macOS,
including money, split allocation, superjson, and persistence tests.

### 2. Build one complete shared UI flow

Use Skip's [existing-app migration guidance](https://skip.dev/docs/project-types/) to add
a shared UI SwiftPM module and Android host. Retain `SpliitAPI` and `SpliitCore`; move shared
views into one source location instead of copying them into a second app. Keep platform app
entry points thin. Carry the app target's Swift actor/concurrency settings into the shared
module where needed; they currently live in `project.yml` and will not transfer automatically.

Keep XcodeGen as the iOS project's source of truth and express required integration changes
in `project.yml`; do not hand-edit the generated `.xcodeproj`. The prototype must prove that
this build arrangement works before a broad source move. Package the string catalogs and
assets with their owning module and check bundle lookups after moving them.

Implement: paste a group link, load its expenses, create an expense, inspect balances, restart
the app, and reopen the remembered group. Use local storage and omit scanner/intent controls
until their implementations exist. Preserve the existing iOS appearance; use suitable Android
navigation and surfaces for APIs the compatibility layer does not implement.

Exit criterion: this flow works on an Android emulator against the disposable Spliit server
and still works on iOS. Proceed only if compatibility changes remain localized and state,
navigation, and persistence are reliable. Record actual build size and release performance.

### 3. Complete the core product

Port group management, expense editing/deletion and undo, all split modes, currency conversion,
search, balances/settlement, statistics, activity, settings, and multiple instances. Reuse
the existing server-compatibility fallbacks. Test Android Back, keyboard/insets, rotation,
process recreation, and cancellation of work when leaving a screen.

Configure Android links and sharing. Reuse `IncomingLink`/`GroupLink` validation and per-group
instance routing. Verified App Links require the relevant host association; a fork cannot
assume control of `spliit.app`. Retain paste-link entry for self-hosted instances.

### 4. Integrate platform features

Add SkipKit for media selection, SkipQRCode for group scanning, and SkipMarketplace for
reviews. Implement and test Android image normalization, attachment viewing, and OCR separately.
Keep manual expense entry usable when a camera permission is refused or recognition fails.
Implement and exercise the chosen recovery/migration behavior before calling the port ready
for existing users.

### 5. Validate and prepare distribution

- Keep the existing iOS tests. Reuse API fixtures and the disposable backend; XCUITest cannot
  run Android flows. Add a small Android end-to-end smoke flow using a suitable tool such as
  Maestro, and expand only for platform-specific regressions. See [Skip testing](https://skip.dev/docs/testing/).
- Cover zero-, two-, and three-decimal currencies, negative amounts, uneven splits, stable
  expense IDs, UTF-16 hash behavior, and server/client share agreement.
- Exercise supported and unsupported document storage, self-hosted instance URLs, network
  failures, and reload after process death. Emulator localhost is not the Mac host: configure
  a reachable backend address and deliberate cleartext policy for local development.
- Check English/French catalogs, plurals, localized number entry, large text, TalkBack,
  navigation semantics, and missing icons. Supply Android assets for symbols without usable
  fallbacks; see [SkipUI symbols](https://skip.dev/docs/modules/skip-ui/#system-symbols).
- Test a real Android device for camera behavior, permission denial, photo orientation,
  repeated presentation, and background/foreground transitions. Inspect a release build.
- Add Android CI, artifact generation, manifest metadata, and signing configuration. Determine
  the Android application ID and release ownership explicitly. Never reuse an assumed store
  identity or check signing credentials into the repository.

## Scope, estimates, and open decisions

The first Android beta should cover the core expense-sharing flow. Siri parity, an Android
language-model enhancement, and cross-platform cloud sync are deferred. Photo/QR libraries
make those integrations smaller; they do not remove the need for device validation.

Planning allowance for one experienced developer: 2–5 working days for the initial proof,
and roughly 2–4 weeks total for a core beta if that proof succeeds. Attachments, OCR,
migration/recovery, and release polish add further work. These are source-review estimates,
not commitments; revise them after compiling and testing the prototype.

Before distribution, resolve whether this is a new Android listing or an update to an
existing one, what group recovery guarantees it offers, and whether OCR/attachments are
required in the first release. Maintain a small, explicit set of platform differences so
future upstream changes remain practical to merge.

## Implementation log — 2026-09-30

Phase 1 keeps the core as native Swift with no new package dependencies.

- Added conditional `FoundationNetworking` imports to the API, exchange-rate client, and
  network tests; kept the Darwin-only `waitsForConnectivity` setting on Apple platforms.
- Excluded the iCloud adapter and iOS React Native migration from Android compilation.
  The local store and portable cloud merge protocol remain available. Legacy migration
  tests remain enabled on Apple platforms only.
- Replaced the core catalog with native English/French `.strings` tables and portable
  `NSLocalizedString` calls. All 19 keys and French translations are preserved; the string
  checker now covers these tables as well as the app catalogs.
- Receipt date detection remains Apple-only because `NSDataDetector` is unavailable on
  Android. The Android parser returns no date and leaves the form date unchanged; add
  recognition with the phase 4 OCR integration. Merchant/total/category parsing remains shared.
- Added `make android-build` and `make android-test`. The latter uses the existing Swift
  Testing suites on a connected Android device/emulator.
- Initial iOS simulator build: passed (`make build`, iOS 27.0 runtime).
- Final host run: **402 tests passed** (324 core, 78 API; live-server tests disabled).
- Final Android emulator run: **388 tests passed** across 36 suites, including money,
  currency conversion, split allocation, superjson, transport cancellation, file persistence,
  settings, receipt parsing, and packaged English/French localization. The 14 Apple legacy
  migration tests are intentionally excluded; Android tests verify the receipt-date fallback.
- Final iOS simulator rebuild passed; native string extraction and the Python checker
  regression tests passed with all app/core messages translated.
- The full Android suite exposed incorrect currency precision from corelibs
  `NumberFormatter.maximumFractionDigits` (JPY/KWD both reported two). `MoneyFormatter`
  now reads the platform currency metadata through `CFNumberFormatterGetDecimalInfoForCurrencyCode`
  and applies it to both scaling and display. Existing zero-/three-decimal tests caught
  the issue; malformed-code cases also cover the CoreFoundation string-length precondition.

Installed toolchain used for the prototype:

| Tool | Version |
| --- | --- |
| Xcode / Apple Swift | 27.0 (`27A266a`) / 6.4 |
| Skip CLI | 1.9.11 |
| Swift Android toolchain and SDK | `6.4.0-RELEASE`, target `aarch64-unknown-linux-android28` |
| Android NDK | r30 (bundled with the Swift Android SDK) |
| Android SDK | platform 36, build-tools 36.0.0, platform-tools 37.0.1 |
| Emulator | 37.1.11, Android 16 / API 36, arm64-v8a |
| Installed JDK | OpenJDK 26.0.2.1 (not needed by these native core builds; Gradle compatibility unverified) |

Run from the repository root with Skip on `PATH`, the matching Swift Android SDK installed,
and an emulator/device connected for tests. If multiple devices are connected, run
`skip android test --testing-library testing --android-serial <serial> --build-system native` inside
`Packages/SpliitKit`. These commands build/test the shared core, not an Android APK.

With Skip 1.9.11 and Swift 6.4, the default `swiftbuild` backend emits one test runner per
target, but Skip executes only the first (78 API tests). `make android-test` explicitly
selects the `native` build backend so a single executable includes both test targets.
Recheck this workaround when upgrading Skip/Swift; a successful exit alone does not prove
the core suite ran.

Phase 1's core build/test exit criterion is met. Next is phase 2: a thin Android host and
one shared UI flow, retaining XcodeGen for iOS. No Android UI, APK size/performance result,
Gradle/JDK compatibility result, app-private storage-path validation, or app restart test is
claimed by these native command-line tests. Validate those with the host before broader
UI migration. Receipt date recognition, OCR/media, Android recovery, and distribution
remain in their later phases.

### Phase 2 — complete

- Added a native Skip UI package and thin Android host under the separate prototype ID
  `app.spliit.android.prototype`. The existing iOS identity remains unchanged.
- Gradle 9.4.1 and JDK 21 build the Android host. The resolved Android Gradle Plugin requires
  Gradle 9.4.1; the initially installed Gradle 9.0 is insufficient.
- A minimal host launched on Android 16. A native core store persisted to the app's private
  `files/Spliit/recent-groups.json`, survived process restart, and updated the UI immediately
  after enabling Skip's Observation bridge in the core module.
- Core resources require the core Skip plugin. Swift 6.4's generated `.bundle` URL lookup
  also bypasses the pinned Android bridge's `.resources` mapping; `CoreResources` explicitly
  uses that mapping inside the Android JVM while preserving native command-line resources.
  French validation in the shared UI is verified below.
- Shared screens now belong to the `SpliitUI` package under `Spliit/`; the iOS host lives in
  `iOS/`. XcodeGen remains the project source of truth. Apple camera, documents, review prompts,
  and intents stay conditional; unsupported presentation APIs have Android alternatives.
  Builds and the complete shared flow are verified below.
- The user-provided `sudo -n -H -u srv /usr/local/bin/docker compose` starts the existing
  `e2e/compose.yaml` database and app. Both are healthy; **14 live API checks pass** with
  document upload excluded. MinIO's configured image could not be pulled, so attachment
  checks remain unavailable. The shared server is left running.
- Final affected core suite results: **402 host tests**, **388 Android tests**, including
  the new resource helper. The host requires the native build backend described below.
- The shared UI builds for iOS and Android. Three iOS UI checks pass against the local
  backend: adding a group by link, creating an expense and checking balances, and retaining
  the active user after relaunch. UI tests select English/US explicitly because their money
  assertions use that locale. Native string extraction and its checker regression tests pass.
- The ARM64 Android debug APK is **252,245,964 bytes (240.6 MiB)**. The generated localization
  bridge passed the English/French runtime check below. The welcome and group-link screens
  render. Initial emulator runs suffered system-wide ANRs, stock Settings launch timeouts,
  and shared-storage FUSE failures, including on fresh images before Spliit was installed.
  The confirmed cause was CPU/disk policies inherited from T3's launch daemon with
  `ProcessType=Background`. Launching through `taskpolicy -a -d default -g default` raised
  process priority from 4 to 46: the AOSP API 36 control booted in **12.76 seconds**, Settings
  launched in **174 ms**, and the integer benchmark used **0.249 seconds wall / 0.248 seconds
  CPU**. The original Google Play AVD then booted in **12.18 seconds** and Spliit cold-launched
  in **1.457 seconds**, without ANRs in these checks. Idle iOS simulators and the older
  shared Android emulator were shut down with permission; their data was preserved.
- The ARM64 release APK also builds successfully: **156,692,907 bytes (149.4 MiB)**, with
  native debug symbols retained by the Skip host configuration. Both final archives contain
  only ARM64 libraries, including `libSpliitUI.so`. The initial multi-ABI release build took
  **1 h 24 s** and produced a 402.8 MiB APK, but included x86 dependencies without an x86 app
  library. The prototype now packages only the architecture covered by its core tests.
  The first combined debug/release rebuild passed in **12 min 13 s**. With corrected host
  scheduling, the final incremental debug/release rebuild passed in **1 min 18 s**. These
  are prototype APK sizes; production download size remains unverified.

- Saving the first Android expense exposed a missing `android.permission.VIBRATE` in the
  host manifest. Added it for the existing save/refusal/undo feedback; successful saves and
  refused invalid forms now stay in the app.
- French expense entry exposed Skip formatting the static `%` translation as a printf
  string. The native localization bridge now returns argument-free translations directly,
  and split labels render resolved text verbatim. Group, expense, and participant names
  also render verbatim so user data cannot become catalog keys. The debug runtime check
  covers literal percent labels and escaped fallback keys as well as the existing plurals.
- **Android shared flow passed against the disposable backend.** English: add the Lisbon
  group by link, load expenses, save a €30 expense, verify balance deltas of +€20/−€10/−€10,
  force-stop, and reopen the remembered group and expense. Final French release: add Book
  club by link, load its empty state, save `30,00` GBP for two people, verify +£15/−£15,
  force-stop, and reopen. Its expense title `Percent` remains literal in French, exercising
  the catalog-key regression. Native Swift validation displays the French required-title
  and required-amount messages, and the `%` split label renders without crashing.
- Final iOS rebuild and string extraction pass: 261 app, 19 core, 4 shortcut, and 46 category
  keys, all translated. The three iOS shared-flow checks reported above remain the UI baseline.
- Final ARM64 release cold starts after force-stop, with compilation finished, were
  **130 / 142 / 126 ms** (`am start -W`, median **130 ms**) on the dedicated API 36 emulator.
  These measure Activity Manager launch time on this host, not network loading, frame-time
  performance, or physical-device startup. No ANR occurred during the recovered-device checks.

Phase 2's shared-flow exit criterion is **met**. Next is phase 3's broader product and
Android lifecycle coverage. Distribution readiness is not claimed. The missing Android
symbols, Search translation, and English Foundation formatting observed at this milestone
are addressed by the phase 3 polish below. Attachments/OCR, recovery, accessibility, and
physical-device coverage remain outstanding.

The host `make test` and `make test-live` commands also select the native SwiftPM build
system: Swift 6.4's default swiftbuild backend rejects the pinned Skip graph for duplicated
static `SkipLib`/`SkipUnit` products. Recheck this workaround with dependency upgrades.
The UI keeps default main-actor isolation on Apple platforms; Android models use explicit
`@MainActor` because Skip's generated generic-view helper classes require nonisolated defaults.

To build the UI prototype, select JDK 21 with `JAVA_HOME`, put Gradle 9.4.1 and Skip on
`PATH`, set `ANDROID_HOME` to the Android SDK, and run `make android-app`. The APK is
`.build/Android/app/outputs/apk/debug/app-debug.apk`. The native core commands above remain
separate. Use `http://10.0.2.2:3009/` for the shared backend from the Android emulator.
The APK is limited to ARM64 until other architectures receive device coverage. With the
pinned Skip version, `SKIP_EXPORT_ARCHS=aarch64` also avoids unnecessary native compilations;
the Gradle ABI filter controls packaging, including third-party JNI libraries.

When starting the emulator from T3's background launch daemon, reset the inherited task
policies on the emulator process. For the existing prototype AVD:

```sh
taskpolicy -a -d default -g default "$ANDROID_HOME/emulator/emulator" \
  -avd spliit-skip-integration-plan -cores 4 -memory 4096 \
  -gpu host -feature -Vulkan -no-snapshot -no-audio
```

Apply the same wrapper to Gradle when it inherits this background policy. The flags were
tested together; no global launch-daemon settings were changed.

The debug host includes a small check against the actual generated localization bridge,
packaged string tables, and Android ICU. After installing the APK, run:

```sh
adb -s emulator-5556 shell am start -S \
  -n app.spliit.android.prototype/spliit.ui.MainActivity --ez checkLocalization true
adb -s emulator-5556 logcat -d -s SpliitLocalizationCheck:I '*:S'
```

A successful run logs `PASS`; failed assertions stop the debug launch. The check covers
English/French plural counts 0, 1, and 2, reordered arguments, and escaped percent signs.
Native Swift participant interpolation, French validation, and normal UI locale selection
were also exercised in the shared-flow checks above.

### Phase 3 — product and lifecycle coverage

The Android host now declares the inherited `app.spliit.spliitmobile` scheme and unverified
`https://spliit.app/groups/…` links. `singleTask` delivers subsequent links to the existing
activity. Skip's existing `onOpenURL` implementation consumes the cold-launch intent and
listens for `ComponentActivity.onNewIntent`; the shared `IncomingLink`/`GroupLink` validation
and per-group instance routing remain the only URL parser. Self-hosted instances retain
**Add by link**; the manifest does not register arbitrary web hosts or inbound text shares.

These are not verified App Links. The prototype cannot publish `spliit.app`'s association,
and Android 12+ normally sends unapproved HTTPS links to the browser. A package-targeted
test exercises dispatch without claiming ordinary browser links open the app by default.
The existing group menu's `ShareLink` already uses Skip's Android `ACTION_SEND` text/plain
chooser, with the URL derived from that group's instance, including its subdirectory.

The installed debug APK passes this check of its actual resolver and launch mode:

```sh
adb -s emulator-5556 shell am start -S \
  -n app.spliit.android.prototype/spliit.ui.MainActivity --ez checkLinks true
adb -s emulator-5556 logcat -d -s SpliitLinkCheck:I '*:S'
```

The check asserts that the custom scheme and official HTTPS group path resolve to the
single-task activity, while unrelated paths, insecure official URLs, and lookalike hosts
do not. Existing `IncomingLinkTests` and `GroupLinkTests` cover payload validation. For cold
and warm delivery, set these to two group IDs on the app's configured default instance:

```sh
SPLIIT_FIRST_GROUP_ID=replace-with-first-group-id
SPLIIT_SECOND_GROUP_ID=replace-with-second-group-id
adb -s emulator-5556 shell am start -S -W -a android.intent.action.VIEW \
  -d "app.spliit.spliitmobile://groups/$SPLIIT_FIRST_GROUP_ID" app.spliit.android.prototype
adb -s emulator-5556 shell am start -W -a android.intent.action.VIEW \
  -d "app.spliit.spliitmobile://groups/$SPLIIT_SECOND_GROUP_ID" app.spliit.android.prototype
```

Cold launch, warm delivery, repeated custom-scheme links, and the native share chooser
pass on the dedicated Android emulator. The shared text retains the group’s selected local
instance. Ordinary browser dispatch for unverified HTTPS links is not claimed.


The repeatable Android UI/API smoke check uses Python's standard library and the existing
server seeder. Install the debug APK, keep the e2e server on port 3009 running, then run:

```sh
python3 Scripts/android-smoke.py --serial emulator-5556
```

It creates isolated groups and restores the original app locale. It does not clear app data
or stop the server. `--lifecycle-only` runs the delayed-response checks; `--navigation-only`
runs group management, links, search, and sharing. Use this prototype's dedicated emulator.

Verified so far against the real local backend:

- All four split modes save the expected integer amounts and participant shares.
- Editing preserves the changed title and amount; list-swipe Undo retains the expense;
  editor deletion removes it. Balances agree before and after deletion and process restart.
- Android Back during a delayed add-by-link lookup leaves the group list unchanged.
- Totals loads after switching away during a delayed response and returning. The proxy
  forwards HTTP errors too, preserving the server's stats endpoint fallback.
- Create and edit group work on a selected self-hosted instance; Totals, activity navigation,
  search, cold/warm/repeated links, and native sharing pass.
- The expense draft survives an actual landscape rotation. A GBP 5 expense at a manual
  rate of 1.25 saves as USD 6.25, retaining GBP 500 original minor units and the chosen rate.
- Participant selection works, and marking the suggested payment as paid saves a reimbursement
  and returns the balances to settled.

Leaving a Compose screen does not currently forward Skip's cooperative task cancellation
through the native Swift `.task` bridge. Do not infer canceled networking from tab changes.
Expense-form activity recreation and process death are covered by the recovery work below.
Group-form restoration and delayed out-of-order exchange-rate responses still need device
coverage. Android Back during a failed save is covered below.


The shared models now retain pagination cursors on cancellation, allow a canceled Totals
request to retry, reject stale Totals completions, and invalidate superseded search debounces
before their equality shortcut. Exchange-rate lookup and Add by link own native task handles;
rate replacement/disappearance cancels both automatic and manual requests, and completion
checks the selected pair/date before updating the form. Cancel buttons are disabled while
saving group and expense forms. Android debug/release and iOS builds pass after these changes;
all app/core/shortcut/category strings remain translated in French.


`Scripts/check-group-model.swift` compiles the actual shared model against the existing host
core build (commands are at the top of the file). It fails against the previous model and
passes with these changes: canceled Totals retry, older success/error/cancellation arriving
last, pagination cursor preservation, and uncanceled search debounce/response ordering.
It also covers immediate pagination reentry before the previous loader unwinds, for expense,
activity, and search pages. Each loader accepts the replacement read and only its request ID
may update the cursor, results, or loading flag. First-page refreshes invalidate pages started
before or during the refresh. The previous implementation fails this expanded check.

Opening a currency or participant picker also exposed a native stack overflow: the pinned
Skip accessibility-traits empty initializer recursively constructs itself through an array
literal. Both pickers now use an explicit zero raw value on Android and retain the selected
trait; Apple platforms use their normal empty value.


Android save forms now register a small Back callback on their own dialog's dispatcher,
using the existing Compose bridge. The callback is enabled only while saving and removed
when its view leaves composition; normal idle Back and the existing gesture guard remain.
The lifecycle smoke check delays a deliberately failed write without creating an expense:
Back leaves the pending form visible, the error appears, the draft survives, and Back dismisses
the idle form after acknowledging the error. The pending form and failure dialog are also
verified in the optimized release APK on the dedicated API 36 emulator.
The same guard is applied to create/edit group forms. Android debug/release builds and
iOS builds/string checks pass.

### Android symbols and app-locale formatting

The Android host bundles 52 Google Material icons as Skip-readable symbol assets. They use
the existing system-image lookup, so shared views retain their SF Symbol names and iOS
keeps its native symbols. Assets are pinned to the revision in `Android/MaterialIcons.json`;
the Apache-2.0 license and source/change notice ship alongside them. No icon library is added.

```sh
python3 Scripts/android-icons.py          # offline asset and shape-conversion checks
python3 Scripts/android-icons.py --update # regenerate from the pinned upstream SVGs
```

Skip's SVG reader accepts filled paths; the importer expands rectangles, circles, and
polygons before wrapping them as symbolsets. The emulator loads the packaged assets through
`Bundle.main`; tab and expense icons render without missing-symbol warnings in the exercised
screens. This does not claim every icon has been visually reviewed.

The shared UI now passes its environment locale to native Foundation formatting. This is
necessary because native Swift's process locale can differ from Android's per-app language.
Dates, participant lists, currency names, money, percentages, rates, and new/edit/reimbursement drafts
use the selected app locale. Drafts receive the locale at construction, before their amount
strings are formatted. Search has an explicit catalog label while retaining its iOS role.

French emulator checks show `Rechercher`, French currency names and month abbreviations,
`Dana et Eli`, and comma-decimal expenses and Totals. The existing model check also asserts
French money formatting. Android debug/release and iOS builds pass; the string check reports
262 app, 19 core, 4 shortcut, and 46 category keys, all translated in French.

The French UI/API regression check is repeatable against isolated groups:

```sh
python3 Scripts/android-smoke.py --serial emulator-5556 --locale-only
```

It checks the new-group EUR default, French currency selection/summary and Search label,
participant lists, `12,34` entry saved as 1234 minor units, edit prefill, a `72,34` total,
localized percentages, and the `30,17` settlement saved as 3017 minor units. The original
app locale is restored when the check finishes. The previously supplied `fdf403b` APK is
retained separately so physical-device feedback can identify which build was tested.

### Expense draft recovery

Actual `Activity.recreate()` and a background `am kill` both exposed lost expense drafts;
the earlier rotation test did not recreate the activity. Android now checkpoints the raw
expense form in one local atomic JSON file beside the recent-groups file. It preserves
unfinished input, participant shares, conversion fields, locale, edit identity, the minted
expense ID, and the full instance URL. It does not copy native Swift pointers or Compose
state into Android bundles; the existing saveable-state suppression remains necessary.

A restored activity reconstructs the matching expense form. Cancel/Back and successful writes
clear only their owned recovery UUID; activity destruction leaves it intact. A write still
running in the same process keeps the restored form disabled until its result arrives.
Inputs and automatic rate replacement are held while saving. Pending writes are checkpointed
before the request and are never automatically resubmitted after process death. A manual
retry requires confirmation and gives a new create attempt a fresh ID. Older servers can
ignore supplied IDs, so recovery cannot infer that a missing ID means nothing was saved.
An edit fetch owns a native task canceled on disappearance, preventing a late response from
checkpointing an edit the user already dismissed.

Unreadable or conflicting drafts remain intact until explicitly discarded. Failure to write
the checkpoint prevents a new request; storage errors are surfaced. Recovery is local to this
Android prototype, not cloud sync or the planned cross-install group migration. Group-form
drafts, scroll position, keyboard focus, and the selected tab are not restored by this change.
Android cloud-backup and device-transfer rules exclude this temporary checkpoint so a stale
backup cannot resurrect an already completed expense; the recent-group backup policy is
unchanged. The rules use the platform's [backup exclusions](https://developer.android.com/identity/data/autobackup).

The store's eight tests and existing form tests pass (63 selected host tests). Repeat the
Android lifecycle check using the debug APK and dedicated emulator:

```sh
python3 Scripts/android-smoke.py --serial emulator-5556 --recreation-only
```

The debug host exposes the `recreateActivity` launch extra and logs the old/new activity's
process ID, so the check distinguishes activity recreation from process death. The release
host ignores that extra. The smoke flow checks new/edit draft recovery, normal dismissal,
pending-write retention, and explicit retry after interrupted writes against isolated groups.
The delayed-response check also cancels an edit before its response arrives and verifies that
the dismissed form does not reappear after process death (`--lifecycle-only`).
The dedicated debug emulator also retained an injected malformed draft until the explicit
discard action, created a readable replacement, and removed that replacement on Cancel.
The iOS build/string check passes with 268 app, 19 core, 4 shortcut, and 46 category keys,
all translated in French. The release APK contains both backup-exclusion resources.
The final release APK also restored a new draft after background process death and saved
exactly one expense with the expected amount against the local backend.

After adding a core source file, the root SwiftPM iOS-device build retained an old source list
even though the Android and Xcode builds saw the file. Touching `Packages/SpliitKit/Package.swift`
refreshed that graph. Check the native prebuild output as well as Gradle's final status: Skip's
prebuild command can print Swift errors while Gradle still reports success.
