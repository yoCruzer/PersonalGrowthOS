# Formal Development batch preparer

This tool prepares a reviewable synthetic batch for the proposed isolated macOS client `com.yocruzer.PersonalGrowthOS.FormalSyncProbe`, targeting `iCloud.com.yocruzer.PersonalGrowthOS` / **Development** / Team `83SKX2PM7B`. That client identifier, registration, profile and container association are **proposed, not created or verified**. It is distinct from both the installed product and G1 SyncLab.

The executable has three local commands and **no CKContainer or network code**. It does not sign, install, create Apple resources, change accounts or write to CloudKit. This is a batch preparer and offline SDK replay, not a completed live or dual-device client. Current v2 schema stays pinned to `6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003`.

```sh
swift build --package-path Packages/SyncFoundation --scratch-path /private/tmp/pgos-sync-foundation-build --product FormalDevelopmentProbe
# Use the built executable; all output directories must be NEW and use physical paths (e.g. /private/tmp).
FormalDevelopmentProbe plan NEW_PLAN_DIRECTORY
FormalDevelopmentProbe replay PLAN_DIRECTORY EXPECTED_PLAN_SHA256 NEW_REPLAY_DIRECTORY
FormalDevelopmentProbe preflight PLAN_DIRECTORY EXPECTED_PLAN_SHA256 APP_OR_BINARY NEW_PREFLIGHT_DIRECTORY
```

`plan` returns SHA256 and retains `plan.json`, `plan.sha256`, a valid fixed 1×1 synthetic PNG, two fixed text payloads and create/edit/tombstone manifests. Run/dataset are fresh UUIDs; other identities derive from the run. Six exact planned records cover all existing v2 record types and fields: original, create chunk, create mutation, edit chunk, edit mutation and tombstone. No arbitrary text/image/business file input is supported. A candidate schema declaration change fails the pinned hash check instead of silently creating a new plan.

`replay` requires an explicit expected plan hash. It reconstructs the built-in fixture from run/dataset and rejects any difference in fixed environment/identity, full record list/order, files or bytes, even if a modified plan is rehashed. It rejects unknown/extra/missing files, symlinks, traversal and pre-existing output. It actually reads each source file, creates a private output lease, invokes the native v2 CKRecord/CKAsset codec, compares exact readback bytes and verifies asset closure and the known parent chain. Results are retained in `report.json`, always `mode=OFFLINE_ONLY`, `networkOperations=0`, `serverSchemaChecked=false`, `p0Passed=false`. Individual commands use `OFFLINE_PASS`; failures preserve completed commands and the active failed command/index, or identify schema/plan-load/final-reread as the failing stage. The source is reread before success. Exit 0 means only offline success; rejection exits 2.

`preflight` reads the **actual** selected artifact using system `codesign --verify --deep --strict --all-architectures`, then combined code metadata/entitlements. It reads an embedded macOS provisioning profile when present, decodes it with system `security cms`, compares required technical fields/expiry, rechecks profile bytes, signature, CDHash/identity/entitlement bytes, artifact metadata and directory identity afterward. Profile device lists, names, raw CMS bytes and raw command output are never written to the report. Output `report.json` records only the plan-bound technical result, code/profile hashes and fixed rejection codes. Unsigned, ad-hoc/wrong-identity, absent-profile or mismatched artifacts return `NOT_READY` and exit **2**.

Even a full field match reports `STATIC_SIGNING_MATCH_REQUIRES_OWNER_GATE`: `readyForCloudRun=false`, `networkAuthorized=false`, certificate/profile/device eligibility **NOT_VERIFIED**, real service access **NOT_RUN**, P0 false. This check does not prove certificate membership in the profile, valid registered-device eligibility, installation or CloudKit access. Pure signature-positive unit tests inject metadata and are never counted as actual signed-artifact evidence.

Directory traversal uses fd-relative `openat`/`mkdirat` with `O_NOFOLLOW` for every component, fd-relative reads/writes, and fd-based enumeration. SDK CKAsset URLs necessarily require a path; output directory identity is checked around SDK use and files are private caller-owned leases. Plan/output/artifact must stay immutable during their operation; before/after checks detect observed changes, but are not a claim of resistance to arbitrary malicious ABA replacement. Do not mutate the private output leases while replay runs.

The shared `FormalProbeCore` target is buildable for iOS17; the command-line signing inspection is macOS-only. Future authorized transport can reuse the fixed plan and exact expected records, but no transport, CKSyncEngine, persistent outbox, production entitlement change, domain projection, migration or device test is implemented here. Signed live Development validation and server schema comparison remain separate Owner-gated work.
