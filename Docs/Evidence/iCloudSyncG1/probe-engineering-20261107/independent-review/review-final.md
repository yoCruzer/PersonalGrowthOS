# Independent Debug probe / loopback bridge review

Final review date: 2026-11-07. Reviewer: independent child agent g1_independent_review. Implementation was read-only; independent synthetic probes and report live outside the worktree.

## Conclusion

No remaining must-fix issue found in the reviewed final six-file snapshot. The previously reported identity, replay, concurrency, packaging access, atomic publication and token-argv issues are closed by source inspection and the paired checks below. This is an offline engineering gate, not CloudKit/G1 acceptance.

## Independent evidence

- `independent-native.log`: separate Swift test package, 3 tests / 0 failures. Tests include real cross-process flock exclusion and release, symlink rejection, journal duplicate bytes/cached result, changed raw request rejection, wrong run result rejection, interrupted claim => explicit blocked, immutable result preservation, dataset isolation, opt-in default rejection before any base directory or cloud connection, and malformed/non-loopback URLs. Command: `swift test --package-path /private/tmp/g1-probe-review/swift --scratch-path /private/tmp/g1-probe-review-swift-build`.
- `initial-probes-02.log` and `recheck-01.log`: initial actual HTTP wrong-result identity returned 200 and published evidence; fixed version returns 409 and publishes nothing. Under simulated umask 077, initial package directory 700 / scripts 600 were inaccessible to target user; fixed directory 755 / scripts 644 / token 600. Signing, ditto and chmod ACL subprocesses mocked in this packaging test; actual signature/ACL and cross-user execution were not independently tested.
- `repository-bridge-final.log`: final repository bridge tests 5 / 5 pass against real loopback server. Covers auth, routes, unknown ID/traversal, exact retry immutability, dataset/run/raw digest binding, queue preservation on invalid result, command allowlist. Command: `python3 -m unittest test_probe_bridge.py` from Tools.
- `launcher-final-02.log`: independent synthetic launcher test verifies wrong UID rejects before subprocess; correct UID verifies signed copy before open; open argv contains only fixed options/app path and never token; fixed opt-in/dataset/run/token passed through environment. ACL argument targets only test user. Signature verification, ACL application and app launch are mocked. The first log `launcher-final.log` retains a test-harness path assertion failure caused by macOS /var versus /private/var canonicalization; fixing the harness path resolved it without implementation changes.

## Source checks and issue closure

- `DevelopmentProbe.swift:1`, `SyncLabApp.swift:75`: DEBUG compilation boundary; default opt-in checked before lock/base/cloud work. Fixed command enum, mutation validation, probe IDs, SYNTHETIC text and exact PNG hash/size. Container comes from Binding.container, never command data.
- `DevelopmentProbe.swift:80-121`: run/dataset journal stores raw request before execution, compares exact bytes, refuses claimed-but-unfinished replay, validates result identity and digest, publishes by hardlink without replacement. iOS and Mac share journal semantics.
- `DevelopmentProbe.swift:6-18,136-143`, `SyncLabApp.swift:90-93`: dataset-scoped process flock; shutdown awaits cloud stop before releasing process lock in normal and thrown paths.
- `DevelopmentProbe.swift:222-239`: exact 127.0.0.1 HTTP endpoint allowlist; redirects denied by URLSession delegate and proxies disabled; bounded request/resource timeouts; token not accepted from command payload.
- `probe_bridge.py:91-127`: authenticated result validates request existence plus dataset/run/raw-command digest; exact retries return original bytes and changed retries reject; fsync temporary plus hardlink prevents partial replacement. Command enqueue uses the same atomic no-overwrite publication. Content-Length truncation rejects.
- `prepare_probe_package.py:27-65`: explicit traversable package modes and executable launcher; private token 600 plus designated-user read ACL; launch checks UID and signing; latest open invocation passes token only via environment, never command-line arguments.
- `DevelopmentProbe.swift:63`: result scope explicitly says command execution only. PASS can coexist with pending/partial cloud outcomes; it cannot be used as convergence verdict.

## Boundaries / NOT_RUN

Actual cloud service, two-client convergence, real account equality, iPhone devicectl result retrieval, actual dedicated-user GUI launch, Apple signing verification and effective ACL access were NOT_RUN by this reviewer. No private signing log, real account or device identifier was accessed. Parent-reported native/build/signing checks are not counted as independent evidence here. Real run must separately compare dataset, runID, exact raw-command digest, expected salted account fingerprint, full mutation identities/content/ancestry, image byte equality, projections and pending queue outcomes. An interrupted journal claim remains indeterminate and must never be reinterpreted as a successful cloud write or silently replayed with the same ID.

The controlled local file roots, signed package and designated owner/test user remain trusted; this temporary bridge is not a hostile multi-user service or attestation protocol. It authenticates token possession and preserves received evidence; it does not itself prove cloud convergence.

## Reproducibility

`final-source-sha256.json` binds this report to the final reviewed six files; `final-source/` contains those exact read-only copies. Independent probe source: `probe_review_initial.py`, `probe_review.py`, `launcher_review.py`, `swift/Tests/ProbeReviewTests/ProbeReviewTests.swift`. Initial failures and recheck logs are retained.
