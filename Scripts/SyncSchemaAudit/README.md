# Offline CloudKit schema audit

This standard-library Python CLI reads two explicitly assigned CKDB exports and the pinned codec artifact. It produces **review-only JSON**, never an import file, deployment statement, network request, or deletion recommendation. Exit 0 means the comparison completed; it does not pass P0/P1/P2. All three gates remain false even when the observed fields match the candidate.

```sh
python3 Scripts/SyncSchemaAudit/audit.py \
  --development /absolute/path/development.ckdb \
  --development-sha256 <lowercase-original-sha256> \
  --production /absolute/path/production.ckdb \
  --production-sha256 <lowercase-original-sha256> \
  --candidate /absolute/path/schema.json \
  --candidate-sha256 6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003 \
  --output /absolute/path/new-report.json

python3 -m unittest discover -s Scripts/SyncSchemaAudit -p 'test_*.py' -v
```

Relative paths resolve from the current directory. Inputs must be regular files no larger than 1 MiB, match their declared SHA256, and remain unchanged during the read. Every ancestor and the leaf are opened with `O_NOFOLLOW`; dot traversal and symlinks are rejected. Use `/private/tmp`, not the macOS `/tmp` symlink. Output requires an existing real parent and a previously nonexistent leaf; exclusive creation prevents concurrent overwrite. After writing, the requested parent/leaf are re-resolved and checked against held inode identities. An I/O failure retains any partial file as failed evidence, without deleting or overwriting a different inode. Exit 2 means rejection; do not treat a partial file as a successful report.

Supported grammar is deliberately a closed subset:

```text
schema := DEFINE SCHEMA record+
record := RECORD TYPE name ( entry (, entry)* );
entry  := name type modifier* | GRANT (READ | WRITE | CREATE) TO name
modifier := QUERYABLE | SEARCHABLE | SORTABLE
type   := scalar | LIST<scalar>
scalar := INT64 | DOUBLE | STRING | BYTES | TIMESTAMP | REFERENCE | ASSET | LOCATION
name   := ASCII identifier, optionally double-quoted, without escapes
```

Identifiers contain at most 128 ASCII letters/digits/underscores and start with a letter/underscore. Keywords are uppercase. Whitespace is accepted between tokens; comments, standalone index declarations, nested lists, escapes, unknown types/clauses, duplicate declarations/modifiers, and trailing syntax are rejected rather than guessed. Names beginning with `__` are reserved for the six explicitly known system fields. Future export grammar or a changed candidate requires an explicit parser/pin review.

The candidate pin binds the exact 1,032-byte, three-type/eleven-field v2 SDK codec artifact under `Docs/Evidence/iCloudSyncFoundation/20261107/ci-foundation-72f5d3d/schema/schema.json`. An attacker-supplied replacement plus its recomputed hash is not a new trusted candidate.

Reports retain the full observed structures, including extra business types/fields, system fields, Users.roles, and each observed grant. The three supported field modifiers are retained as sorted `fieldIndexes`; index-only changes affect structural equality. Missing modifiers are not invented, and the unindexed report shape remains unchanged. They separate byte identity from normalized structural identity. Missing candidate types count all their missing fields. Users permissions are not copied to candidate types: custom permissions and candidate system fields stay `NOT_SPECIFIED`. Matching schemas say nothing about record counts. Assigning files to Development/Production is an Owner-provided association, not content-level attestation; Team/container/environment and schema deployment are not verified by this tool.

Tests use freshly constructed temporary files and the pinned public artifact. The independent fixture contains invented `auditSyntheticLabel` and `auditSyntheticScores` fields plus `SyntheticAuditWriter`/`SyntheticAuditReader` roles; it is not a reformatted or re-encoded Owner export. Reserved system-field names are exercised individually in separate one-field records; the baseline contains no system-field block or `roles` field. They cover Users grammar, reorder/whitespace equality, changed grants, additional types/fields, wrong field types, complete-field matches with closed gates, all supported scalars/lists, malformed and duplicate grammar with recomputed hashes, candidate substitution, FIFO/directory/oversize rejection, symlink ancestors/leaves, concurrent input modification, output-parent substitution, competing publishers, and original-byte preservation.

The active independent CLI reviewer is `Scripts/SyncSchemaAudit/review_schema.py`. It retains the original 20 threat/binding checks and adds 3 field-index positive/negative checks. The dated 20261108 reviewer and its outputs remain immutable historical evidence; its old QUERYABLE-as-unknown fixture no longer represents the explicitly supported grammar.
