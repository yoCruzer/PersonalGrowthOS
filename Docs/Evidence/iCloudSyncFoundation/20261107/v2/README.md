# Candidate v2: capacity correction and chunked payload evidence

Candidate v1 had a 16 MiB payload asset cap. The separately validated real V16 `NetWorthSnapshotValue` fixture has 10,000 valid synthetic rows and encodes to **49,190,297 bytes**; it cannot fit that cap. No candidate v1 schema was deployed. v2 changes to a small mutation manifest + independent 4 MiB payload chunk records, a 128 MiB explicit aggregate budget, and a 25 MiB original-media record. Unsupported versions and over-budget inputs reject without truncating their source. P0 remains `CANDIDATE_NOT_FROZEN`.

The actual V16 source fixture was produced by `Scripts/Fixtures/MeasureSyncV16Payload.swift` on the fixed product baseline. See the adjacent `capacity/` reports for domain validation and its execution command. Input SHA256 for this run: `9e97f46caef1fb89babb217a5cb7e25ee223beec74d6ce71408f211672fb9b13`. The 49 MB fixture and chunk binaries are local only; they are not committed. A fresh fixture must use the hash/count from its own generated report (the initial generator uses a new snapshot UUID).

Final implementation snapshot and replay evidence are in **`post-pool/`**. Root-level `native-final.log`, `budget-final.log`, source hashes and `SyncPayloadProbe.swift` are preserved **pre-pool history**, despite their original filenames. They are not the final source/memory result. `commands.json` explicitly marks that historical status.

Final checks on macOS 27.0.1 (26A434), arm64, Xcode 27.2 (27B52):

- 24/24 package native tests PASS, including 49,210,071-byte synthetic item shape, 12 chunks, exact chunk bounds, 25 MiB image, missing/extra/reordered/repeated indices, legitimate repeated content, per-chunk and total hash mismatches, identity/epoch and SDK record validation.
- iOS17 deployment-target library compilation PASS with iOS Simulator 27.2 SDK. No simulator/device runtime invoked.
- Actual V16 fixture → bounded preparation → individual CKRecord/CKAsset encode/decode → streamed asset closure → independent final source scan PASS. 12 ordered chunks: eleven 4,194,304-byte chunks and one 3,052,953-byte chunk. The 1,584-byte manifest binds every chunk and the full original hash. Source hash/count remain unchanged.
- Candidate schema generated from actual SDK records: `6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003`. Two new-directory generations are byte-identical; an existing output directory returns failure and preserves every existing hash.

## Retained failures and resource evidence

Independent review caught source truncation/growth during preparation and Foundation autoreleased buffer retention. Final preparation requires the already encoded aggregate's expected SHA256/count, rejects mismatching final bytes, and checks source metadata changes as an additional defense. It never returns a manifest on failure. Emitted partial staging remains caller-owned.

The initial full 49 MB SDK replay was correct but peaked at **267,239,424 bytes RSS**. Per-chunk autorelease pools now surround preparation, verification, original validation and the probe's final source scan. The same full SDK/CLI replay then peaked at **116,523,008 bytes RSS**, footprint **107,873,072**; this includes CloudKit/Foundation/process overhead and is not a 4 MiB total-memory claim. The first `/usr/bin/time -l` run in the sandbox completed replay but could not read `kern.clockrate`, returning exit 1; that limitation is retained separately.

Independent `review-v2/` isolates preparation: 128 MiB input RSS fell from **170,606,592** to **40,058,880** bytes; a 4 MiB input measured **44,236,800** bytes. This closes the observed source-size-proportional temporary-buffer retention. It is a bounded local measurement, not a universal device memory ceiling or background execution benchmark.

## Reproduction

`post-pool/commands.json` records exact test, iOS build and replay commands. `post-pool/SyncPayloadProbe.swift` freezes the replay source; package source hashes bind the rest. The maintained executable is `Packages/SyncFoundation/Sources/SyncPayloadProbe/main.swift`:

```sh
swift run --package-path Packages/SyncFoundation --scratch-path /private/tmp/pgos-sync-foundation-build SyncPayloadProbe /path/to/synthetic-v16.json EXPECTED_SHA256 EXPECTED_BYTE_COUNT /private/tmp/pgos-v2-replay-NEW
```

It reads only the supplied synthetic source; the new directory retains the chunk files, manifest and summary. Never use daily private business data for this evidence. Only the compact summary and manifest belong in public evidence.

No CloudKit network, server schema inspection, Production write/deployment, product persistence integration, migration, domain projection or signed-device synchronization was exercised. Existing G1 device evidence is unaffected. More than 128 MiB fails explicitly; Swift grapheme-count limits do not establish a finite encoded-byte maximum.
