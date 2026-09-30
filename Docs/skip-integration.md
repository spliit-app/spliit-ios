# Android integration with Skip

Status: phase 1 complete in `skip-integration-plan`, based on upstream
commit `80b2e984b3dc07782983f24586d7e4568ada2a02`. The Android UI and platform libraries
remain proposed; their capabilities below are documented capabilities, not verified
integration with Spliit.

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
