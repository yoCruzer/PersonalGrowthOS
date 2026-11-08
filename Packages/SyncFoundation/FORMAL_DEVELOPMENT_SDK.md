# Formal Development SDK preparation (locked)

This package adds an **unexecuted CloudKit SDK adapter**, an internal single-flight
batch runner, and a host that cannot start network work. It does not establish any
Apple account, signing, container permission or environment qualification. No
actual CloudKit operation, resource creation, signing or installation was run.
The fixed container remains `iCloud.com.yocruzer.PersonalGrowthOS`; the only plan
environment accepted is Development. The existing v2 schema/fixture is unchanged.

## Host

```
swift run --package-path Packages/SyncFoundation FormalDevelopmentHost inspect PLAN_DIR EXPECTED_SHA NEW_OUTPUT_DIR
```

A valid fixed synthetic plan produces `report.json` with `NOT_READY`,
`EXTERNAL_GATE_NOT_COMPLETE`, `networkOperations: 0`, `networkAuthorized: false`,
`p0Passed: false`, and exits **2**. Invalid input exits 1; invalid usage exits 64.
There is no live flag, environment override or `CKContainer` initialization.
`FormalDevelopmentSDK` is not a public library product; its transport, ticket and
runner are internal. The sole public host API is offline inspection.

A future, separately reviewed change must implement the real authority factory:
actual signing/profile qualification, account binding, Development assurance,
precise Owner-authorized plan/window and one-shot durable execution controls.
Neither a caller-supplied `CKDatabase` nor the current in-memory ticket proves any
of these. No construction path to the SDK adapter exists in the shipped host.

## Prepared behavior, tested with injected fake transport only

The internal ticket binds the canonical plan SHA, container, environment, schema,
dataset, run and process-local epoch. It is consumed before filesystem/transport
work, including failures, and cannot be reused at another output path. The runner
is MainActor single-flight. Before and after every async transport operation it
checks cancellation, epoch/ticket validity, the original plan/files and private
asset leases. Returned outcomes are saved before rejecting a stale callback; they
remain unverified and never authorize subsequent work.

The sequence is: exact zone lookup; zone save; save three asset records; save three
immutable mutation records; fetch all six precise record IDs; validate every
returned field through the existing codec and compare all payload/PNG/manifest
bytes against the original fixed fixture. Missing/extra/failed results reject the
batch. Existing zones are refused. Saves use `ifServerRecordUnchanged`, with no
deletes, retries or overwrite policy. No queries, subscriptions or general sync
engine exist. Dependency closure is the already validated fixed create/edit/delete
fixture, not a general domain projection.

**Zone lookup followed by save is not atomic create-if-absent.** UUID freshness and
one process's ticket/single-flight do not solve another process/copy racing on the
same plan. Durable run consumption and authenticated cross-process exclusion are
not implemented; actual cloud execution remains locked. A failed/partial save may
have left server state; no rollback or cleanup is attempted.

Each intent and returned result is an exclusive, fsynced numbered file. The final
report is also exclusive. Failure to write evidence or final report throws and
cannot return success. Public evidence retains bounded technical error codes,
per-planned-synthetic-record outcomes and stages, not descriptions or arbitrary
CloudKit userInfo/account/server payloads. Unknown IDs are redacted. Even successful
fake transport reports say `INJECTED_TRANSPORT_VERIFIED`, `realAuthorityVerified:
false`, `p0Passed: false`; these are not actual CloudKit/schema acceptance evidence.

Caller-owned immutable plan/output leases remain required. The fd-relative helper
rejects symlinks and checks directory identity around URL-based CKAsset use, but
does not claim to defeat malicious same-user ABA replacement of paths. All source
assets are fixed synthetic fixtures; no arbitrary business/image input is accepted.

SDK APIs were checked in local Xcode macOS27.2 CloudKit.swiftinterface:
`recordZone(for:)`, `save(CKRecordZone)`, `modifyRecords(saving:deleting:savePolicy:atomically:)`,
`records(for:desiredKeys:)`; availability is iOS15/macOS12, below this package's
iOS17/macOS14 deployment targets. No public API behavior is inferred from an
actual cloud run. The SDK adapter itself is compile-checked, while fake transport
exercises sequencing and failure logic; it does not test Apple's transport.
