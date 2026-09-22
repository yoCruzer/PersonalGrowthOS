# External Capture v1

## Authority and boundary

2026-09-22 Owner request authorizes text, images, URL and Safari selected content through public iOS Share Sheet APIs. Owner explicitly selected Build 9 `ae14f10` as the baseline despite PR #6 remaining Draft. Starting branch: `feature/build9-today-entry-followups`; execution branch: `codex/external-capture-v1`. Draft PR base is the Build 9 branch. No merge, release tag, build-number increment, Archive or TestFlight. Stop at independent review; full article capture is excluded.

## Implementation plan / acceptance

1. Versioned shared payload + atomic file inbox: test validation, corruption, unsupported version and original attachment checksums.
2. Ordinary Entry import with optional related source and durable receipt: test attachment rollback, post-commit retry, duplicate scan, deletion/replay, V9 migration/reopen and source backup round trip.
3. Lightweight extension, Safari preprocessing, metadata fallback and source link: build both targets and exercise representative public Share Sheet behavior where available.
4. Run final Unit and existing UI smoke/regression gates once, inspect localized UI/configuration, document actual evidence, commit/push and create Draft PR. Device-only checks remain explicitly unverified.

## Architecture

`ShareExtension → group.com.yocruzer.PersonalGrowthOS / ExternalCapture → main app → ordinary Entry`.

Both targets compile `SharedCapture/ShareInbox.swift`; the extension has no SwiftData dependency. The main private database stays in its existing Application Support location. App Group entitlements are in both targets; a device provisioning profile must authorize this group and the new extension bundle ID `com.yocruzer.PersonalGrowthOS.ShareExtension`.

Payload v1 contains stable UUID, creation time, editable text, optional source and image descriptors. Images remain files (up to 9, each 25 MB / 80 million pixels, matching existing media limits), never UserDefaults. A private staging directory receives copies, verifies sizes/checksums and serializes JSON; a same-volume directory rename publishes the complete Pending package. Cancellation removes extension working files; termination before publication leaves an unconsumed staging directory, never a partial Entry. No automatic expiration of pending user content.

The app scans at initial view appearance and foreground activation. A serialized importer uses its own ModelContext, preserving editor drafts. It validates the payload and attachments, copies media via the existing MediaStore, and commits Entry, optional EntryExternalSource and CaptureImportReceipt together. Only after commit is the inbox package deleted. A committed receipt converts subsequent scans into cleanup-only; receipts survive permanent Entry deletion to avoid resurrection. Pre-commit failures retain the original package and remove copies. Process death leaves unreferenced copies handled by the existing startup recovery machinery; the intact inbox remains retryable. Corrupt/unsupported packages are retained and reported rather than silently deleted.

## Data compatibility

Schema V10 adds EntryExternalSource and CaptureImportReceipt, with a V9→V10 lightweight migration. No historical Entry/Image/Habit schema fields change. Optional source is linked by stable Entry ID, following the existing pin/follow-up pattern. Permanent deletion removes source in the same transaction; archive/edit/pin/follow-up retain source.

Backup v6 includes entrySources; importer accepts v1–v5 without them and rejects nonempty source data falsely labeled as older formats. Source identity, endpoint, URLs and size bounds are validated. Import receipts are local delivery bookkeeping, not user content, and are not backed up. Do not open an upgraded V10 store with an older app: rollback requires an appropriate pre-upgrade backup, never destructive fallback.

## Capture and metadata

Safari preprocessing reads only document URL/title, selected text, canonical link and site name. No DOM article extraction, login reuse, source app identification or private API. Source URL opens through the standard system Link UI and only accepts HTTP(S). Original URL is retained independently of canonical URL.

LPMetadataProvider has a three-second timeout with subresources disabled; Save is immediately enabled once core content is loaded and never waits for metadata. Available title/final URL are cached in the payload/source. Metadata failure leaves the core URL intact. The source card deliberately uses text; no remote preview image/icon loading or repeated display-time request.

Apple references: [Safari preprocessing](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html), [LP timeout](https://developer.apple.com/documentation/linkpresentation/lpmetadataprovider/timeout), [subresources](https://developer.apple.com/documentation/linkpresentation/lpmetadataprovider/shouldfetchsubresources).

## Privacy and diagnostics

OSLog category ExternalCapture records provider UTTypes/selection, IDs, byte/count statistics, serialization/publication, discovery/import/receipt, media copy and metadata states. It never logs text, titles, image contents or URLs; errors log fixed reason or error type only. No source-app bundle-ID discovery. The extension performs a metadata network request only for the URL explicitly shared by the user; core saving is local.

## Known boundaries / future

WeChat works only when its UI invokes the system Share Sheet and provides supported content. Its private forwarding/favorites menus cannot be intercepted. Selected text plus page metadata depends on the host supplying Safari preprocessing results. Future full-article capture can extend the versioned payload and capture mode, but v1 implements only metadataOnly/selectedContent.

## Verification checkpoint

Historical implementation checkpoint: first sandboxed build could not access CoreSimulator (exit 70); retried using the authorized simulator build permission. First real compile caught one argument-order error, corrected before focused tests. The final passing evidence is recorded below.

Owner Device Verification: actual signed App Group access; Safari URL and selected text; Photos image; supported WeChat share; extension termination/background/main app restart; offline metadata; inaccessible source link. All test writes use isolated synthetic stores; the physical Owner database is not accessed.

### Observed targeted results

- `/tmp/PGOS-Capture-Targeted.xcresult`: 5/5 focused Unit PASS, exit 0. Payload/atomic publication, commit interruption and deduplication, image rollback/fallback, corrupt/future payload retention, V9 migration/reopen.
- `/tmp/PGOS-Capture-ShareUI.xcresult`: source backup round trip 1/1 PASS; Safari UI failed before opening the extension because the system is Chinese and its share action is in More. Whole run exit 65, not a pass.
- `ShareUI2` and `ShareUI3`: failed only on actual system accessibility lookup (ShareButton label is 共享; app targets are shareCell cells). The test uses the observed identifiers/cell labels; no product rule or assertion was weakened.
- `/tmp/PGOS-Capture-ShareUI4.xcresult`: actual Safari → system Share Sheet → 随心log Extension → shared inbox → isolated main-app Entry → source link → relaunch PASS, exit 0. Screenshot `/tmp/PGOS-Capture-ShareUI4-Shots/04FDF515-BA0C-4787-BC3B-1A0D2C2DFFE1.png` visually verified: selected quote, title and original URL, Chinese Save/Cancel and import-on-next-open notice. Final gate adds explicit quote-equality assertions.
- `/tmp/PGOS-Capture-Release.log`: unsigned generic iOS arm64 Release build of app plus embedded extension PASS, exit 0; no Archive or distribution action. Simulator signed products use the expected simulated App Group entitlement; actual device provisioning remains external.
- Catalog: 468 keys, all en/zh-Hans. Plists parse and `git diff --check` pass.
- Remote baseline checked again: `ae14f107f7eebb89a1549e00de3d941e6a996281`; GitHub Actions workflow count 0.

The UI fixture is a loopback HTML page served by the test's NWListener. Safari is exercised through actual XCUI system controls. The DEBUG-only app test hook consumes only that exact fixture URL into the existing separate UITesting store; normal UI tests never consume shared user content. The final gate includes strengthened pre-save rollback, two-image partial-copy rollback, image-only import and deletion/source cleanup assertions.

The historical default simulator store's unknown-model-version startup warning remains present, as documented before this branch. It is not erased or rebuilt. Migration tests open isolated stores and the checked-in exact older fixtures. Device-data preservation is not inferred from the simulator warning or an empty-store fallback.

### Final automated gate and bounded closure

- `/tmp/PGOS-Capture-FinalGate.xcresult`: full Unit **218/218 PASS** and 3 selected existing/new UI smoke/regression tests **3/3 PASS**, exit 0. UI covers the semantic accessibility audit, normal Entry creation/edit/relaunch, and Safari selected text → extension → Entry/source → relaunch. Unit includes historical migrations/exact stored fixtures, all existing import/export/recovery suites and the six new capture tests.
- Review found a post-commit cleanup edge: an interrupted directory deletion could leave no JSON, so parsing before checking the receipt prevented cleanup. The importer now checks the directory UUID's durable receipt first. A test removes JSON after successful commit and verifies cleanup-only retry, no duplicate and no resurrection after actual permanent deletion/source cleanup.
- Publication also rejects JSON that expands beyond the reader's 2 MB bound (for example escaped control text); optional canonical URLs and provider metadata are bounded so enrichment cannot invalidate otherwise valid core content.
- `/tmp/PGOS-Capture-Closure.xcresult`: all 6 capture Unit tests plus the strengthened Safari UI **7/7 PASS**, exit 0. UI asserts exact selected text, title, original-source link, actually opens Safari via that link, and verifies restart persistence. This is the final product code; the broader gate is not redundantly rerun after these narrowly tested fixes.
- `/tmp/PGOS-Capture-ReleaseFinal.log`: final incremental unsigned Release app/extension build **PASS**, exit 0. Bundle inspection confirms both targets remain 1.0 (7), the extension is embedded and its Safari script is bundled.

Actual gate commands (same iPhone 16 / iOS 26.5 destination; no erase, clean, Archive or release upload):

```sh
xcodebuild test -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=5F04DE28-8329-4774-9488-076D6DDC5230' -derivedDataPath /tmp/PGOS-Capture-Derived -parallel-testing-enabled NO -only-testing:PersonalGrowthOSTests -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testExternalCaptureSafariShareAndImport -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTextCaptureAppearsInTimelineAndSurvivesRelaunch -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testCoreShellPassesAccessibilityAudit -resultBundlePath /tmp/PGOS-Capture-FinalGate.xcresult
xcodebuild test -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=5F04DE28-8329-4774-9488-076D6DDC5230' -derivedDataPath /tmp/PGOS-Capture-Derived -parallel-testing-enabled NO -only-testing:PersonalGrowthOSTests/ExternalCaptureTests -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testExternalCaptureSafariShareAndImport -resultBundlePath /tmp/PGOS-Capture-Closure.xcresult
xcodebuild build -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/PGOS-Capture-Release CODE_SIGNING_ALLOWED=NO
```

### Validation limits

The simulator's real host-provider integration covers Safari selected content and URL/title/source reopen. Text-only, image-only, image+URL, multi-image rollback, metadata-absent fallback and corrupt/future payload handling are validated at the payload/import boundary. Photos/WeChat provider variations, real network timeout/offline interaction, physical App Group provisioning, and system termination of a live extension remain Owner Device Verification. No simulator result is labeled a physical-device pass. The new schema's synthetic V9 fixture and the existing exact older fixtures prove automated compatibility; an overlay against the Owner's actual Build 9 database is still a device gate.

Unsupported images (e.g. GIF/WebP), video, full webpage bodies and source-app identity are outside this v1 implementation. Pending packages never expire automatically; uncommitted shared staging left by abrupt termination is not imported and may remain on disk. No saved share is silently deleted to reclaim space.


## Final delivery

**COMPLETE — READY_FOR_INDEPENDENT_REVIEW.** Tested product implementation: `068a27a`. Ordinary push succeeded; [Draft PR #7](https://github.com/yoCruzer/PersonalGrowthOS/pull/7) targets `feature/build9-today-entry-followups` from `codex/external-capture-v1`. Following documentation-only commit records the handoff; it does not change tested product code. Both current-context documents are updated. No merge, Ready-for-review conversion, tag, build-number change, Archive or TestFlight occurred. Stop here; independent review and Owner device checks are the next boundary.
