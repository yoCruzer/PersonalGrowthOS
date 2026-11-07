# Seed-only CK_4 recovery verifier patch

Implementation participation, not an independent self-review. Parent must review this patch. Only verifier and its focused tests changed. No App/cloud/device operations.

The original seed remains a failed report: exactly connect plus 12 successful saves, then first sync FAIL CK_4, completed=false. Every successful prefix snapshot must equal the cumulative fixed mutations, initially empty. A fixed supplemental plan with exactly connect/sync/sync/snapshot and the approved IDs may recover this seed only. It must use the same dataset/run/account, a different process nonce, exact seed facts in every snapshot, and a drained final queue. The canonical 27-stage manifest and all other checks remain unchanged. Summary metadata records the original FAIL/CK_4 and original/recovery report hashes.

Validation: 14 focused unittest methods PASS; original full 27-stage synthetic positive plus 24 rejection controls and 8 mocked launcher tests PASS; full synthetic recovery branch PASS; CK_4 failure in the phone dependency stage still rejected. First unit run had 13 PASS/1 ERROR because the missing-file test expected FileNotFoundError while the existing reader intentionally raises ValueError; corrected test expectation, no implementation weakening. Both logs retained.

Read-only actual saved reports: original 13 PASS plus CK_4 verified; four recovered results have a fresh process nonce and the same account, retain all 12 exact seed facts in every snapshot, and end with pending empty. Original copied failure bytes equal the previous directory. No private account/nonce values exported. This does not verify unexecuted phone/fault stages or pass full G1.

Commands: `python3 -m unittest -v test_verify_fault_window` from Tools; prior independent scripts/run_review.py with repo/plans and fresh output `/private/tmp/g1-seed-recovery-regression`; synthetic integration script in this directory. Source hashes retained.
