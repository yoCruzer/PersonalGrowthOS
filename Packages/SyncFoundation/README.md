# SyncFoundation candidate v2

Offline native Swift/CloudKit codec preparation after G1. This package is **not linked to the product**, does not open a database or CloudKit container, and does not authorize deployment. P0 remains `CANDIDATE_NOT_FROZEN`; server schema, signed Development/Production access and real transport are NOT_RUN.

Each `PGMutationV2` is one immutable aggregate revision (stable typed object UUID + mutation UUID). Its small canonical manifest carries dataset, causal parents, current-object dependencies, logical deletion, domain payload version, ordered payload chunk descriptors and original-media descriptors. It contains no payload asset or growing object history. `PGPayloadChunkV2` uses dataset-scoped content-addressed CKAssets of at most 4 MiB; the ordered manifest binds every chunk hash/byte count and the full aggregate hash/byte count. `PGOriginalV2` independently carries up to 25 MiB per original, matching the current product limit.

Candidate v1's 16 MiB payload asset cap failed the actual product capacity requirement: 10,000 legal snapshot rows can exceed 40 MiB. It was never deployed. This v2 intentionally changes the candidate schema and rejects v1 manifests; old test/schema evidence remains historical, never relabeled as v2. Tests cover a 49 MB synthetic snapshot shape; the separately generated real V16 fixture can be replayed through `SyncPayloadProbe` below.

Causal closure, supported domain decoding, business-key deduplication and atomic aggregate projection remain required before publication. `verifyAssetsComplete` means asset closure only. Receipt of a mutation record is insufficient; missing, extra, out-of-order or repeated chunk **indices** fail, as do per-chunk or aggregate digest/length mismatches. Identical content at two distinct positions is legal and can reuse one content-addressed chunk record. The consumer joins those records against the manifest's ordered indices; it must not infer order from network arrival.

Local `SyncBinding` includes container/environment/accountHash/dataset/generation. It is deliberately not serializable. Every fence instance issues a fresh nonce, including A→B→A and cold reopen; it cannot authorize another instance. Check on the commit actor after any await. This primitive does not cancel operations, persist partitions, manage outbox/ACK, or replace SDK identity verification.

Canonical JSON rejects unknown fields, duplicate/unsorted set collections, unsupported wire versions and alternate byte encodings. Chunk order is semantic and never sorted. Domain payload is opaque original bytes; future domain decoders must explicitly support its kind/version. Existing manifest bytes must be compared with `verifyReplay` inside the eventual persistence transaction before insertion. Same mutation identity with changed bytes is a collision, never an update. Caller retains rejected raw input separately; this codec does not silently rewrite it.

Resource limits are candidate policy, not CloudKit service limits: 64 KiB manifest, 128 MiB aggregate payload, 4 MiB chunks (at most 32), 25 MiB original, 256 parents, 1,024 dependencies/media references. Limits reject explicitly without truncation. The 128 MiB budget is not a claim that Swift grapheme-count limits imply a finite byte maximum: combining sequences can exceed it. Above-budget inputs retain their source and fail explicitly; segmentation or another version policy would be required before those inputs can sync.

Use `PayloadManifest.prepare(fileURL:expected:emit:)` with the **hash and byte count of the already encoded domain aggregate**, and a caller-owned immutable source lease. It streams chunks, verifies final whole bytes against that expected descriptor, and additionally rejects source length/mtime/ctime changes. An error never returns a publishable manifest; partially emitted staging files remain caller-owned for recovery/cleanup. A metadata check alone is not an integrity oracle. Outgoing chunk/original files must remain immutable staging leases until SDK completion. The codec refuses final-component symlinks and special files and bounds reads, but cannot prevent later caller writes.

`PayloadManifest.verifyChunks(next:)` and the streaming `MutationManifest.verifyAssetsComplete(nextPayloadChunk:originalBytes:)` consume one indexed chunk at a time and never assemble the entire aggregate in memory. Source preparation needs at most two 4 MiB payload buffers internally; SDK encode validation may simultaneously read one additional bounded chunk while the caller retains an emitted chunk. Caller retention, original media buffers (25 MiB), Foundation/SDK overhead and process RSS are separate. Do not publish consumer output until full verification returns. The Data convenience APIs assume the caller already holds bounded input; they do not provide a constant-memory encoder. Persist received bytes before advancing any engine checkpoint.

No custom query indexes: candidate transport is zone changes plus record IDs. Exact fields are exposed by `CloudRecordCodec.mutationFields`, `chunkFields`, and `originalFields`; these are expected schema, not a server export or deployment difference. Logical tombstones carry no active payload/media/dependencies. No physical deletion/GC is implemented.

Run tests:

```sh
swift test --package-path Packages/SyncFoundation --scratch-path /private/tmp/pgos-sync-foundation-build
```

Generate deterministic candidate schema from real local SDK records:

```sh
swift run --package-path Packages/SyncFoundation --scratch-path /private/tmp/pgos-sync-foundation-build SyncSchema /private/tmp/pgos-sync-schema-NEW
```

Output directory must be new. `schema.json` enumerates actual synthetic CKRecord fields, checks codec declarations, and is bound by `schema.sha256`. Synthetic fixture files remain in that directory. This is not a CloudKit Console export, server diff, permission audit or deployment artifact.

Replay a separately validated synthetic product fixture through preparation, per-chunk CKRecord/CKAsset encoding/decoding, streamed aggregate verification and an independent final source read:

```sh
swift run --package-path Packages/SyncFoundation --scratch-path /private/tmp/pgos-sync-foundation-build SyncPayloadProbe /path/to/synthetic.json EXPECTED_SHA256 EXPECTED_BYTE_COUNT /private/tmp/pgos-payload-replay-NEW
```

The probe reads source without modifying it and retains chunk files, canonical manifest and a compact summary in the new output directory. Do not use daily private business data for engineering evidence.

V16/v12 migration, persisted identity/epoch, same-transaction business/outbox writes, downloaded-file installation/leases, SDK scheduling/ACK/checkpoints, domain causal closure/conflict UI, media GC, backup/restore, notifications and Widget side effects are not implemented here.
