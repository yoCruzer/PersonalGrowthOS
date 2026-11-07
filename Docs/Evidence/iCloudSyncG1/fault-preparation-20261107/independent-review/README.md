# Independent fault-preparation review — 2026-11-07

**Engineering review: no remaining must-fix found in the reviewed candidate. Actual 27-stage device/CloudKit execution: NOT_RUN. This is not G1 acceptance.**

Reviewer: independent child agent, separate from implementation. Implementation was read only. Evidence scripts and synthetic files were the only writes. No actual App launch, cloud, device, account settings, private signing logs, or actual account identifiers were accessed.

## Reproduction

Requires macOS and Python 3; no Apple signing/network/device access. Supply the generated 27-stage plans directory (manifest plus original per-stage plans) and a new, nonexistent output directory:

```sh
python3 scripts/run_review.py --repo /path/to/PersonalGrowthOS --plans /path/to/generated-27-stage-plans --output /tmp/new-independent-review-output
```

The script generates fabricated reports, runs the current repository oracle, mutates copies, and mocks all launcher subprocesses and the home/UID. It never runs an App. It fails when a must-reject mutation is accepted. Every generated result directory is explicitly labelled SYNTHETIC_ONLY. Keep these files separate from real runtime evidence.

Actual final command used `--repo /private/tmp/PersonalGrowthOS-icloud-g1 --plans /private/tmp/g1-fault-plans-final3 --output /private/tmp/g1-fault-review-portable-final`. Version, manifest hash, source hashes and script hashes are retained alongside this report.

## Results

| Independent verification | Final result |
| --- | --- |
| Full fabricated 27-stage positive fixture | Accepted |
| Original 24-stage oracle controls (dependency subroutine explicitly excluded in this group only) | 14/14 bad inputs rejected |
| Full 27-stage dependency controls | 8/8 bad inputs rejected |
| Full 27-stage checkpoint/lease controls | 2/2 bad inputs rejected |
| Mock launcher positive and adversarial tests | 8/8 passed |

The initial logs are retained, including actual red results. Initial oracle admitted 11 of 14 bad inputs; dependency addition admitted 7 of 8; final checkpoint/lease probes admitted both. Initial window suite had two failures. All these reported must-fix cases are now rejected. `red-window-02.log` is the older harness: three demonstrated vulnerabilities, permission case already fixed, followed by its intentional assertion; it must not be described as four product failures.

Closed cases cover command/dataset/run/plan association; fresh process/plan identity; missing phase observations; immutable collection; symlink/FIFO imported-file reads; stale report/marker replay; actual-vs-local provenance; fixed mutation truth at crash boundaries; new edit present before old ACK; account-event fencing; complete restore target; image missing/truncated/repair phases; dependency candidate/preview/complete truth including no old-head fallback; expected image pending/ACK and precise final PNG; required state checkpoint; and exact prepared/leased image record digest.

Source review also checked private authoritative journals, cached-account isolation and connect identity ordering, cancellation/driver shutdown before releasing locks, fixed file paths and bounded imports, explicitly selected phone bundle execution, explicit test-user window opt-in, and DEBUG-only fault/manual entrypoints. The bundle picker imports at most 16 plans/512 KiB, validates each existing command allowlist, rejects duplicate plan IDs and cannot grant authorization by document content.

## Limits

- Synthetic oracle acceptance tests verifier behavior, not genuine CloudKit callbacks or process recovery. Mock launcher tests cannot certify real ACL, GUI launch, signing, SDK timing, or mobile execution. Parent's 62 native/19 tool checks and builds were not independently rerun here.
- `open -W` does not provide the App's crash exit status. Runtime proof must retain the boundary, new-process nonce and pre-network recovery observations, not claim an observed numeric exit code from this tool.
- `actualCloudKitCallback` is a source-provenance label, not a cryptographic attestation. Actual runtime originals, immutable journals, reviewed binary and paired device evidence remain necessary. Fully coordinated fabricated inputs can satisfy any such unsigned oracle.
- Source account hash and salted per-run account fingerprint have no derivable cross-field relation without the private identifier. A diagnostic replacing all observation source hashes consistently is accepted; this is documented, not counted among rejection tests. The implementation binds both at connection and rejects cached observations from another store account; retain and privately compare runtime originals. Public redaction must remove both fields recursively.
- A prepared batch plus verified asset lease proves the SDK batch/lifetime boundary, not that bytes had reached Apple's servers. A state event after install does not reveal which internal opaque token includes which server changes.
- Physical network-off and manual account switching require separate Owner action records. Fresh CKAsset conclusions require a previously unused dataset/zone plus pending/ACK/download evidence; an empty visible snapshot alone cannot rule out orphaned remote assets.
- This review does not pass the full G1 matrix, Production deployment, unrelated product CI, or any unexecuted real fault stage.

## Regression suggestion

Keep the eight mocked launcher tests in the Python tool suite. Keep the synthetic 27-stage oracle positive and 24 mutations as a bounded verifier regression suite at stable checkpoints; do not substitute them for actual paired runtime evidence.
