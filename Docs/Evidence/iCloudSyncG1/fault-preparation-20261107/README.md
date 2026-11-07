# Remaining test entrypoint engineering — 2026-11-07

Local-only engineering evidence. Real Development fault/dependency/account runs remain **NOT_RUN**. No Production operation or product integration.

Commands: `swift test --package-path Experiments/iCloudSyncG1 --scratch-path /private/tmp/g1-fault-swift`; Python unittest discovery under the experiment Tools directory; `LabReplay offline-fault seed/before/verify-before` and `seed/after/verify-after` on separate new temporary synthetic roots; signed Debug iOS/macOS and unsigned Simulator Release xcodebuild; strict `verify_signing.py` on both actual apps.

Initial cache/loopback/signature sandbox failures and initial test compile errors are retained in private `/private/tmp/g1-fault-*` logs; they were not relabelled PASS. The summaries distinguish subsequent successful checks. Independent review red controls are retained separately. The exact native before/after save path uses real process exits, but it is **LOCAL_ONLY**, not a CloudKit callback result.

See `Docs/ICLOUD_SYNC_G1_FAULT_WINDOW_ZH.md` for the bounded launcher, process/identity provenance, incomplete-image recovery, operator window and acceptance limits. Source/build hashes and final independent review are added at the stable checkpoint.
