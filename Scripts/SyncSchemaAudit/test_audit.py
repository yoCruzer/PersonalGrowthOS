import json
import itertools
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import audit

ROOT = Path(__file__).resolve().parents[2]
CANDIDATE = ROOT / "Docs/Evidence/iCloudSyncFoundation/20261107/ci-foundation-72f5d3d/schema/schema.json"
# Independently constructed fixture: invented fields and roles intentionally differ
# from any supplied CloudKit export. Reserved system fields are tested separately.
SYNTHETIC_SCHEMA = b'''DEFINE SCHEMA
RECORD TYPE Users (
auditSyntheticLabel STRING,
auditSyntheticScores LIST<DOUBLE>,
GRANT WRITE TO "SyntheticAuditWriter",
GRANT READ TO "SyntheticAuditReader"
);
'''


class SchemaAuditTests(unittest.TestCase):
    def setUp(self):
        self.base = Path(os.path.realpath(tempfile.mkdtemp(prefix="pgos-schema-audit-")))
        self.dev, self.prod, self.candidate = [self.base / x for x in ("dev.ckdb", "prod.ckdb", "candidate.json")]
        self.dev.write_bytes(SYNTHETIC_SCHEMA)
        self.prod.write_bytes(SYNTHETIC_SCHEMA)
        self.candidate.write_bytes(CANDIDATE.read_bytes())
        self.assertEqual(audit.digest(self.candidate.read_bytes()), audit.CANDIDATE_SHA256)

    def tearDown(self):
        shutil.rmtree(self.base)

    def run_audit(self):
        return audit.audit(str(self.dev), audit.digest(self.dev.read_bytes()), str(self.prod),
                           audit.digest(self.prod.read_bytes()), str(self.candidate), audit.CANDIDATE_SHA256)

    def cli(self, output):
        return [sys.executable, str(Path(audit.__file__).resolve()),
                "--development", str(self.dev), "--development-sha256", audit.digest(self.dev.read_bytes()),
                "--production", str(self.prod), "--production-sha256", audit.digest(self.prod.read_bytes()),
                "--candidate", str(self.candidate), "--candidate-sha256", audit.CANDIDATE_SHA256,
                "--output", str(output)]

    def test_synthetic_schema_preserves_users_permissions_and_missing_business_types(self):
        report = self.run_audit()
        self.assertEqual(report["status"], "REVIEW_ONLY_NOT_DEPLOYABLE")
        self.assertEqual(report["gatesPassed"], {"P0": False, "P1": False, "P2": False})
        self.assertEqual(report["developmentProduction"], {"byteIdentical": True, "structureIdentical": True})
        diff = report["development"]["diff"]
        self.assertEqual(diff["counts"]["missingRecordTypes"], 3)
        self.assertEqual(diff["counts"]["missingFields"], 11)
        self.assertEqual(diff["users"]["fields"]["auditSyntheticLabel"], "STRING")
        self.assertEqual(diff["users"]["fields"]["auditSyntheticScores"], "LIST<DOUBLE>")
        self.assertEqual(diff["systemFieldsByType"], {"Users": {}})
        self.assertEqual(diff["users"]["grants"], [{"permission": "READ", "role": "SyntheticAuditReader"}, {"permission": "WRITE", "role": "SyntheticAuditWriter"}])
        self.assertEqual(report["candidate"]["customPermissions"], "NOT_SPECIFIED")
        self.assertFalse(report["candidate"]["permissionsCopiedFromUsers"])
        self.assertIsNone(report["sourceBinding"]["team"])
        self.assertIsNone(report["sourceBinding"]["container"])
        self.assertFalse(report["sourceBinding"]["environmentVerified"])
        self.assertEqual(report["recordCountAssessment"], "NOT_INFERRED_FROM_SCHEMA")

    def test_whitespace_and_order_equality_are_distinct_from_byte_identity(self):
        self.prod.write_bytes(SYNTHETIC_SCHEMA.replace(b'GRANT WRITE TO "SyntheticAuditWriter",\nGRANT READ TO "SyntheticAuditReader"',
                                           b'GRANT READ TO "SyntheticAuditReader", GRANT WRITE TO "SyntheticAuditWriter"'))
        self.assertEqual(self.run_audit()["developmentProduction"], {"byteIdentical": False, "structureIdentical": True})

    def test_changed_grant_and_extra_type_are_preserved_not_guessed(self):
        self.prod.write_bytes(SYNTHETIC_SCHEMA.replace(b'READ TO "SyntheticAuditReader"', b'CREATE TO "SyntheticAuditProvisioner"') +
                              b'RECORD TYPE Unrelated (amount DOUBLE, location LOCATION, GRANT READ TO customRole);')
        report = self.run_audit()
        self.assertFalse(report["developmentProduction"]["structureIdentical"])
        self.assertEqual(report["production"]["diff"]["extraRecordTypes"], ["Unrelated"])
        self.assertEqual(report["production"]["observedSchema"]["Unrelated"]["fields"], {"amount": "DOUBLE", "location": "LOCATION"})
        self.assertEqual(report["production"]["diff"]["observedGrantsByType"]["Unrelated"], [{"permission": "READ", "role": "customRole"}])
        self.assertFalse(report["deployable"])

    def test_exact_candidate_fields_still_do_not_pass_gates(self):
        text = SYNTHETIC_SCHEMA
        for name, fields in audit.EXPECTED_TYPES.items():
            text += ("RECORD TYPE " + name + " (" + ", ".join(k + " " + v for k, v in fields.items()) + ");").encode()
        self.dev.write_bytes(text)
        result = self.run_audit()
        self.assertEqual(result["development"]["diff"]["missingFields"], [])
        self.assertEqual(result["development"]["diff"]["missingRecordTypes"], [])
        self.assertFalse(result["deployable"])
        self.assertFalse(any(result["gatesPassed"].values()))

    def test_wrong_type_and_extra_field_report_complete_differences(self):
        self.dev.write_bytes(SYNTHETIC_SCHEMA + b'RECORD TYPE PGMutationV2 (manifest STRING, sha256 STRING, wireVersion INT64, debug LIST<BYTES>);')
        diff = self.run_audit()["development"]["diff"]
        self.assertEqual(diff["counts"]["missingFields"], 8)
        self.assertEqual(diff["fieldTypeMismatches"], [{"recordType": "PGMutationV2", "field": "manifest", "candidateType": "BYTES", "observedType": "STRING"}])
        self.assertEqual(diff["extraFieldsOnCandidateTypes"], [{"recordType": "PGMutationV2", "field": "debug", "observedType": "LIST<BYTES>"}])

    def test_all_known_scalar_and_list_types_are_consumed(self):
        fields = ["s" + str(i) + " " + kind + ", l" + str(i) + " LIST<" + kind + ">" for i, kind in enumerate(sorted(audit.SCALARS))]
        parsed = audit.Parser(("DEFINE SCHEMA RECORD TYPE ScalarProbe (" + ",".join(fields) + ");").encode()).parse()
        self.assertEqual(len(parsed["ScalarProbe"]["fields"]), 16)
        # Exercise reserved names independently, without assembling an export-shaped Users block.
        for name, kind in audit.SYSTEM_FIELDS.items():
            with self.subTest(system_field=name):
                source = ("DEFINE SCHEMA RECORD TYPE SyntheticSystemProbe (" + name + " " + kind + ");").encode()
                self.assertEqual(audit.Parser(source).parse()["SyntheticSystemProbe"]["fields"], {name: kind})

    def test_unknown_or_ambiguous_grammar_rejected_even_with_new_hash(self):
        cases = {
            "comment": SYNTHETIC_SCHEMA + b"// ignored?",
            "second-schema": SYNTHETIC_SCHEMA + SYNTHETIC_SCHEMA,
            "trailing-token": SYNTHETIC_SCHEMA + b"IMPORT SCHEMA",
            "unknown-type": SYNTHETIC_SCHEMA.replace(b"LIST<DOUBLE>", b"BOOL"),
            "nested-list": SYNTHETIC_SCHEMA.replace(b"LIST<DOUBLE>", b"LIST<LIST<INT64>>"),
            "unknown-system": SYNTHETIC_SCHEMA.replace(b"auditSyntheticLabel", b"___future"),
            "unknown-grant": SYNTHETIC_SCHEMA.replace(b"GRANT READ", b"GRANT ADMIN"),
            "index-clause": SYNTHETIC_SCHEMA.replace(b"auditSyntheticScores LIST<DOUBLE>", b"auditSyntheticScores LIST<DOUBLE> FUTURE_INDEX"),
            "trailing-comma": SYNTHETIC_SCHEMA.replace(b'"SyntheticAuditReader"\n)', b'"SyntheticAuditReader",\n)'),
            "missing-semicolon": SYNTHETIC_SCHEMA.rstrip()[:-1],
            "invalid-utf8": SYNTHETIC_SCHEMA + b"\xff",
            "quoted-escape": SYNTHETIC_SCHEMA.replace(b"auditSyntheticLabel", b'"synthetic\\label"'),
            "empty": b"DEFINE SCHEMA",
        }
        for label, data in cases.items():
            with self.subTest(label=label):
                self.dev.write_bytes(data)
                with self.assertRaises(audit.AuditError): self.run_audit()

    def test_index_modifier_permutations_have_canonical_set_semantics(self):
        expected = {"SyntheticIndexProbe": {
            "fields": {"alpha": "STRING", "beta": "LIST<DOUBLE>", "plain": "BYTES"},
            "grants": [{"permission": "READ", "role": "SyntheticIndexReader"}],
            "fieldIndexes": {"alpha": ["QUERYABLE", "SEARCHABLE", "SORTABLE"],
                             "beta": ["QUERYABLE", "SORTABLE"]}}}
        for flags in itertools.permutations(["QUERYABLE", "SEARCHABLE", "SORTABLE"]):
            for list_flags in ["QUERYABLE SORTABLE", "SORTABLE QUERYABLE"]:
                with self.subTest(flags=flags, list_flags=list_flags):
                    source = ("DEFINE SCHEMA RECORD TYPE SyntheticIndexProbe ("
                              "beta LIST<DOUBLE> " + list_flags + ", plain BYTES, "
                              "alpha STRING " + " ".join(flags) + ", "
                              "GRANT READ TO SyntheticIndexReader);").encode()
                    self.assertEqual(audit.Parser(source).parse(), expected)

    def test_index_only_difference_survives_report_and_remains_review_only(self):
        source = b"DEFINE SCHEMA RECORD TYPE SyntheticIndexProbe (label STRING QUERYABLE SEARCHABLE, scores LIST<DOUBLE> SORTABLE);"
        self.dev.write_bytes(source)
        self.prod.write_bytes(source.replace(b"QUERYABLE SEARCHABLE", b"SEARCHABLE QUERYABLE"))
        result = self.run_audit()
        self.assertEqual(result["developmentProduction"], {"byteIdentical": False, "structureIdentical": True})
        self.assertEqual(result["development"]["observedSchema"]["SyntheticIndexProbe"]["fieldIndexes"],
                         {"label": ["QUERYABLE", "SEARCHABLE"], "scores": ["SORTABLE"]})
        self.prod.write_bytes(source.replace(b" QUERYABLE", b""))
        result = self.run_audit()
        self.assertFalse(result["developmentProduction"]["structureIdentical"])
        self.assertEqual(result["production"]["observedSchema"]["SyntheticIndexProbe"]["fieldIndexes"]["label"], ["SEARCHABLE"])
        self.assertFalse(result["deployable"])
        self.assertFalse(any(result["gatesPassed"].values()))
        self.assertEqual(result["candidate"]["customIndexes"], [])

    def test_duplicate_unknown_and_misplaced_modifiers_fail_closed(self):
        clauses = ["label STRING QUERYABLE QUERYABLE", "label STRING SEARCHABLE SEARCHABLE",
                   "label STRING SORTABLE SORTABLE", "label STRING QUERYABLE SORTABLE QUERYABLE",
                   "label STRING INDEXED", "label STRING queryable", 'label STRING "QUERYABLE"',
                   "label STRING QUERYABLE FUTURE_INDEX", "label QUERYABLE STRING",
                   "label LIST<DOUBLE QUERYABLE>", "label STRING, QUERYABLE",
                   "label STRING GRANT READ TO SyntheticReader",
                   "label STRING, GRANT READ TO SyntheticReader SORTABLE"]
        for clause in clauses:
            with self.subTest(clause=clause):
                self.dev.write_bytes(("DEFINE SCHEMA RECORD TYPE SyntheticIndexProbe (" + clause + ");").encode())
                with self.assertRaises(audit.AuditError):
                    self.run_audit()
        output = self.base / "invalid-index-report.json"
        result = subprocess.run(self.cli(output), capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(output.exists())

    def test_unindexed_report_shape_unchanged_and_system_index_preserved(self):
        legacy = audit.Parser(SYNTHETIC_SCHEMA).parse()
        self.assertEqual(set(legacy["Users"]), {"fields", "grants"})
        # Single reserved system field in an invented type, not an Owner export fixture.
        parsed = audit.Parser(b"DEFINE SCHEMA RECORD TYPE SyntheticSystemIndex (___recordID REFERENCE QUERYABLE);").parse()
        self.assertEqual(parsed["SyntheticSystemIndex"]["fieldIndexes"], {"___recordID": ["QUERYABLE"]})
        self.assertEqual(parsed["SyntheticSystemIndex"]["fields"], {"___recordID": "REFERENCE"})

    def test_candidate_fields_with_indexes_do_not_assert_server_readiness(self):
        source = b"DEFINE SCHEMA "
        for name, fields in audit.EXPECTED_TYPES.items():
            source += ("RECORD TYPE " + name + " (" + ", ".join(
                field + " " + kind + (" QUERYABLE SORTABLE" if field == "wireVersion" else "")
                for field, kind in fields.items()) + ");").encode()
        self.dev.write_bytes(source)
        report = self.run_audit()
        self.assertEqual(report["development"]["diff"]["missingFields"], [])
        self.assertEqual(report["development"]["diff"]["fieldTypeMismatches"], [])
        for name in audit.EXPECTED_TYPES:
            self.assertEqual(report["development"]["observedSchema"][name]["fieldIndexes"],
                             {"wireVersion": ["QUERYABLE", "SORTABLE"]})
        self.assertFalse(report["deployable"])
        self.assertEqual(report["gatesPassed"], {"P0": False, "P1": False, "P2": False})

    def test_duplicate_type_field_and_grant_rejected(self):
        for data in [SYNTHETIC_SCHEMA + b"RECORD TYPE Users (x INT64);",
                     SYNTHETIC_SCHEMA.replace(b"auditSyntheticScores LIST<DOUBLE>", b"auditSyntheticScores LIST<DOUBLE>, auditSyntheticScores STRING"),
                     SYNTHETIC_SCHEMA.replace(b'GRANT READ TO "SyntheticAuditReader"', b'GRANT READ TO "SyntheticAuditReader", GRANT READ TO SyntheticAuditReader')]:
            with self.subTest(data=data[-65:]):
                with self.assertRaises(audit.AuditError): audit.Parser(data).parse()

    def test_wrong_hash_and_changed_candidate_never_produce_report(self):
        with self.assertRaises(audit.AuditError): audit.read_bound(self.dev, "0" * 64)
        with self.assertRaises(audit.AuditError): audit.read_bound(self.dev, "A" * 64)
        changed = self.candidate.read_bytes().replace(b"PGMutationV2", b"PGMutationV9")
        with self.assertRaises(audit.AuditError): audit.candidate(changed, audit.digest(changed))
        with self.assertRaises(audit.AuditError): audit.candidate(self.candidate.read_bytes(), "0" * 64)
        self.candidate.write_bytes(changed)
        with self.assertRaises(audit.AuditError): self.run_audit()

    def test_special_files_and_size_limit_fail_without_blocking(self):
        pipe = self.base / "pipe"
        os.mkfifo(pipe)
        with self.assertRaises(audit.AuditError): audit.read_bound(pipe, "0" * 64)
        with self.assertRaises(audit.AuditError): audit.read_bound(self.base, "0" * 64)
        self.dev.write_bytes(b" " * (audit.MAX_BYTES + 1))
        with self.assertRaises(audit.AuditError): audit.read_bound(self.dev, audit.digest(self.dev.read_bytes()))

    def test_leaf_and_ancestor_symlinks_rejected(self):
        link = self.base / "link"
        link.symlink_to(self.dev)
        with self.assertRaises(OSError): audit.read_bound(link, audit.digest(SYNTHETIC_SCHEMA))
        directory = self.base / "directory"
        directory.symlink_to(self.base, target_is_directory=True)
        with self.assertRaises(OSError): audit.read_bound(directory / "dev.ckdb", audit.digest(SYNTHETIC_SCHEMA))
        with self.assertRaises(OSError): audit.write_new(directory / "output.json", {})
        with self.assertRaises(OSError): audit.write_new(link, {})
        self.assertEqual(self.dev.read_bytes(), SYNTHETIC_SCHEMA)

    def test_same_byte_rewrite_during_read_is_detected(self):
        read = os.read
        changed = False
        def change(fd, count):
            nonlocal changed
            value = read(fd, count)
            if not changed:
                changed = True
                self.dev.write_bytes(SYNTHETIC_SCHEMA)
                info = os.stat(self.dev)
                os.utime(self.dev, ns=(info.st_atime_ns, info.st_mtime_ns + 1_000_000))
            return value
        with mock.patch.object(audit.os, "read", side_effect=change):
            with self.assertRaises(audit.AuditError): audit.read_bound(self.dev, audit.digest(SYNTHETIC_SCHEMA))

    def test_output_exclusive_and_cli_inputs_unchanged(self):
        before = {p: p.read_bytes() for p in (self.dev, self.prod, self.candidate)}
        output = self.base / "report.json"
        process = subprocess.run(self.cli(output), capture_output=True, text=True, timeout=10)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(json.loads(output.read_bytes())["status"], "REVIEW_ONLY_NOT_DEPLOYABLE")
        existing = output.read_bytes()
        process = subprocess.run(self.cli(output), capture_output=True, text=True, timeout=10)
        self.assertEqual(process.returncode, 2)
        self.assertEqual(output.read_bytes(), existing)
        self.assertEqual(before, {p: p.read_bytes() for p in before})

    def test_two_cli_publishers_have_one_winner(self):
        output = self.base / "race.json"
        processes = [subprocess.Popen(self.cli(output), stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
        for p in processes: p.communicate(timeout=10)
        self.assertEqual(sorted(p.returncode for p in processes), [0, 2])
        self.assertEqual(json.loads(output.read_bytes())["status"], "REVIEW_ONLY_NOT_DEPLOYABLE")

    def test_output_ancestor_replacement_is_not_reported_as_success(self):
        parent = self.base / "parent"
        parent.mkdir()
        displaced = self.base / "displaced"
        fsync = os.fsync
        moved = False
        def replace(fd):
            nonlocal moved
            fsync(fd)
            if not moved:
                moved = True
                parent.rename(displaced)
                parent.mkdir()
        with mock.patch.object(audit.os, "fsync", side_effect=replace):
            with self.assertRaises(audit.AuditError): audit.write_new(parent / "out.json", {"synthetic": True})
        self.assertFalse((parent / "out.json").exists())
        self.assertEqual(json.loads((displaced / "out.json").read_bytes()), {"synthetic": True})

    def test_traversal_and_invalid_input_leave_no_output(self):
        with self.assertRaises(audit.AuditError): audit.read_bound(str(self.base) + "/../x", "0" * 64)
        output = self.base / "must-not-exist.json"
        self.dev.write_bytes(SYNTHETIC_SCHEMA + b"BAD")
        p = subprocess.run(self.cli(output), capture_output=True, text=True, timeout=10)
        self.assertEqual(p.returncode, 2)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
