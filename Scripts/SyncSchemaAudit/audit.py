#!/usr/bin/env python3
"""Bounded, offline, review-only CKDB comparison. Never emits import/deploy DDL."""
import argparse
import hashlib
import json
import os
import re
import stat
import sys

MAX_BYTES = 1024 * 1024
CANDIDATE_SHA256 = "6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003"
SCALARS = {"INT64", "DOUBLE", "STRING", "BYTES", "TIMESTAMP", "REFERENCE", "ASSET", "LOCATION"}
SYSTEM_FIELDS = {
    "___createTime": "TIMESTAMP", "___createdBy": "REFERENCE", "___etag": "STRING",
    "___modTime": "TIMESTAMP", "___modifiedBy": "REFERENCE", "___recordID": "REFERENCE",
}
EXPECTED_TYPES = {
    "PGMutationV2": {"manifest": "BYTES", "sha256": "STRING", "wireVersion": "INT64"},
    "PGOriginalV2": {"byteCount": "INT64", "original": "ASSET", "sha256": "STRING", "wireVersion": "INT64"},
    "PGPayloadChunkV2": {"byteCount": "INT64", "chunk": "ASSET", "sha256": "STRING", "wireVersion": "INT64"},
}
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]{0,127}\Z")
TOKEN = re.compile(r'\s+|"[A-Za-z_][A-Za-z0-9_]{0,127}"|[A-Za-z_][A-Za-z0-9_]{0,127}|[(),;<>]')


class AuditError(ValueError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def checked_hash(value):
    if re.fullmatch(r"[0-9a-f]{64}", value) is None:
        raise AuditError("Expected a lowercase SHA256")
    return value


def open_parent(path):
    """Open every ancestor relative to its held FD; never follow a symlink."""
    value = os.fspath(path)
    if not os.path.isabs(value):
        value = os.getcwd() + "/" + value
    parts = value.split("/")[1:]
    if not parts or any(x in ("", ".", "..") for x in parts):
        raise AuditError("Path must have nonempty components without dot traversal")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    parent = os.open("/", flags)
    try:
        for component in parts[:-1]:
            child = os.open(component, flags, dir_fd=parent)
            os.close(parent)
            parent = child
        return parent, parts[-1]
    except BaseException:
        os.close(parent)
        raise


def read_bound(path, expected_sha):
    checked_hash(expected_sha)
    parent, leaf = open_parent(path)
    try:
        fd = os.open(leaf, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
        try:
            before = os.fstat(fd)
            if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_BYTES:
                raise AuditError("Input must be a bounded regular file")
            pieces, length = [], 0
            while True:
                piece = os.read(fd, min(65536, MAX_BYTES + 1 - length))
                if not piece:
                    break
                pieces.append(piece)
                length += len(piece)
                if length > MAX_BYTES:
                    raise AuditError("Input exceeds byte limit")
            after = os.fstat(fd)
            keys = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
            if any(getattr(before, k) != getattr(after, k) for k in keys):
                raise AuditError("Input changed while reading")
            data = b"".join(pieces)
            if digest(data) != expected_sha:
                raise AuditError("Input SHA256 mismatch")
            return data
        finally:
            os.close(fd)
    finally:
        os.close(parent)


class Parser:
    def __init__(self, data):
        if len(data) > MAX_BYTES:
            raise AuditError("Schema exceeds byte limit")
        try:
            text = data.decode("utf-8")
        except UnicodeError as exc:
            raise AuditError("Schema must be UTF-8") from exc
        self.tokens = []
        offset = 0
        while offset < len(text):
            match = TOKEN.match(text, offset)
            if match is None:
                raise AuditError("Unsupported CKDB token at character " + str(offset))
            token = match.group()
            if not token.isspace():
                self.tokens.append(token)
            offset = match.end()
        self.index = 0

    def take(self, expected=None):
        if self.index == len(self.tokens):
            raise AuditError("Unexpected end of CKDB")
        token = self.tokens[self.index]
        self.index += 1
        if expected is not None and token != expected:
            raise AuditError("Unsupported CKDB grammar; expected " + expected)
        return token

    def name(self):
        token = self.take()
        value = token[1:-1] if token.startswith('"') else token
        if IDENTIFIER.fullmatch(value) is None:
            raise AuditError("Unsupported identifier")
        return value

    def field_type(self):
        name = self.take()
        if name == "LIST":
            self.take("<")
            name = self.take()
            if name not in SCALARS:
                raise AuditError("Unsupported list element type")
            self.take(">")
            return "LIST<" + name + ">"
        if name not in SCALARS:
            raise AuditError("Unsupported scalar field type")
        return name

    def parse(self):
        self.take("DEFINE")
        self.take("SCHEMA")
        records = {}
        while self.index < len(self.tokens):
            self.take("RECORD")
            self.take("TYPE")
            name = self.name()
            if name in records:
                raise AuditError("Duplicate record type")
            self.take("(")
            fields, grants = {}, set()
            while True:
                if self.index < len(self.tokens) and self.tokens[self.index] == "GRANT":
                    self.take("GRANT")
                    permission = self.take()
                    if permission not in {"READ", "WRITE", "CREATE"}:
                        raise AuditError("Unsupported grant permission")
                    self.take("TO")
                    role = self.name()
                    if (permission, role) in grants:
                        raise AuditError("Duplicate grant")
                    grants.add((permission, role))
                else:
                    field = self.name()
                    if field in fields:
                        raise AuditError("Duplicate field")
                    if field.startswith("__") and field not in SYSTEM_FIELDS:
                        raise AuditError("Unknown system field")
                    fields[field] = self.field_type()
                separator = self.take()
                if separator == ")":
                    break
                if separator != ",":
                    raise AuditError("Expected comma or record terminator")
            self.take(";")
            records[name] = {"fields": dict(sorted(fields.items())), "grants": [
                {"permission": p, "role": r} for p, r in sorted(grants)]}
        if not records:
            raise AuditError("No record declarations in supported schema")
        return dict(sorted(records.items()))


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise AuditError("Duplicate candidate JSON key")
        result[key] = value
    return result


def candidate(data, expected_sha):
    if expected_sha != CANDIDATE_SHA256 or digest(data) != CANDIDATE_SHA256:
        raise AuditError("Candidate is not the pinned codec artifact")
    try:
        value = json.loads(data, object_pairs_hook=unique_object,
                           parse_constant=lambda _: (_ for _ in ()).throw(AuditError("Nonfinite JSON")))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise AuditError("Invalid candidate JSON") from exc
    if (value.get("recordTypes") != EXPECTED_TYPES or value.get("wireVersion") != 2
            or value.get("database") != "private" or value.get("customIndexes") != []
            or value.get("serverSchemaChecked") is not False
            or value.get("status") != "CANDIDATE_NOT_FROZEN"):
        raise AuditError("Unexpected pinned candidate semantics")
    return value


def compare(observed, expected):
    missing_types = sorted(set(expected) - set(observed))
    missing, wrong, extra = [], [], []
    for type_name, fields in sorted(expected.items()):
        actual = observed.get(type_name, {"fields": {}})["fields"]
        for field, field_type in sorted(fields.items()):
            if field not in actual:
                missing.append({"recordType": type_name, "field": field, "candidateType": field_type})
            elif actual[field] != field_type:
                wrong.append({"recordType": type_name, "field": field,
                              "candidateType": field_type, "observedType": actual[field]})
        for field in sorted(set(actual) - set(fields) - set(SYSTEM_FIELDS)):
            extra.append({"recordType": type_name, "field": field, "observedType": actual[field]})
    return {"missingRecordTypes": missing_types, "missingFields": missing,
            "fieldTypeMismatches": wrong, "extraFieldsOnCandidateTypes": extra,
            "extraRecordTypes": sorted(set(observed) - set(expected) - {"Users"}),
            "systemFieldsByType": {t: {f: v for f, v in record["fields"].items() if f in SYSTEM_FIELDS}
                                   for t, record in observed.items()},
            "observedGrantsByType": {t: record["grants"] for t, record in observed.items()},
            "users": observed.get("Users"),
            "systemFieldTypeMismatches": [
                {"recordType": t, "field": f, "observedType": v, "knownSystemType": SYSTEM_FIELDS[f]}
                for t, record in observed.items() for f, v in record["fields"].items()
                if f in SYSTEM_FIELDS and v != SYSTEM_FIELDS[f]],
            "counts": {"missingRecordTypes": len(missing_types), "missingFields": len(missing),
                       "fieldTypeMismatches": len(wrong), "extraFieldsOnCandidateTypes": len(extra)}}


def audit(development, development_sha, production, production_sha, candidate_path, candidate_sha):
    dev_data = read_bound(development, development_sha)
    prod_data = read_bound(production, production_sha)
    candidate_data = read_bound(candidate_path, candidate_sha)
    expected = candidate(candidate_data, candidate_sha)
    dev, prod = Parser(dev_data).parse(), Parser(prod_data).parse()
    return {"status": "REVIEW_ONLY_NOT_DEPLOYABLE", "networkOperations": 0,
            "deployable": False, "gatesPassed": {"P0": False, "P1": False, "P2": False},
            "sourceBinding": {"method": "OWNER_SUPPLIED_FILE_ASSOCIATION_NOT_ATTESTED_BY_CONTENT",
                              "team": None, "container": None, "environmentVerified": False},
            "inputs": {"development": {"sha256": digest(dev_data), "bytes": len(dev_data)},
                       "production": {"sha256": digest(prod_data), "bytes": len(prod_data)},
                       "candidate": {"sha256": digest(candidate_data), "bytes": len(candidate_data)}},
            "developmentProduction": {"byteIdentical": dev_data == prod_data, "structureIdentical": dev == prod},
            "candidate": {"recordTypes": expected["recordTypes"], "wireVersion": 2,
                          "customPermissions": "NOT_SPECIFIED", "systemFields": "NOT_SPECIFIED",
                          "permissionsCopiedFromUsers": False, "customIndexes": []},
            "development": {"observedSchema": dev, "diff": compare(dev, expected["recordTypes"])},
            "production": {"observedSchema": prod, "diff": compare(prod, expected["recordTypes"])},
            "recordCountAssessment": "NOT_INFERRED_FROM_SCHEMA",
            "actions": "REVIEW_ONLY_NO_DDL_NO_IMPORT_NO_DEPLOY_NO_DELETION_RECOMMENDATION"}


def write_new(path, report):
    data = (json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()
    parent, leaf = open_parent(path)
    try:
        fd = os.open(leaf, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=parent)
        try:
            # O_EXCL prevents replacement of existing evidence. On a write failure,
            # retain the partial file as failed evidence; never unlink another inode.
            identity = os.fstat(fd)
            view = memoryview(data)
            while view:
                size = os.write(fd, view)
                if size <= 0:
                    raise AuditError("Output write did not progress")
                view = view[size:]
            os.fsync(fd)
            published = os.stat(leaf, dir_fd=parent, follow_symlinks=False)
            if ((identity.st_dev, identity.st_ino) != (published.st_dev, published.st_ino)
                    or not stat.S_ISREG(published.st_mode)):
                raise AuditError("Output path changed during publication")
            os.fsync(parent)
            # Rewalk the requested name as well as checking the held directory:
            # an ancestor could have been renamed/replaced during the write.
            current_parent, current_leaf = open_parent(path)
            try:
                held, current = os.fstat(parent), os.fstat(current_parent)
                if (held.st_dev, held.st_ino) != (current.st_dev, current.st_ino):
                    raise AuditError("Output ancestor changed during publication")
                named = os.stat(current_leaf, dir_fd=current_parent, follow_symlinks=False)
                if ((identity.st_dev, identity.st_ino) != (named.st_dev, named.st_ino)
                        or not stat.S_ISREG(named.st_mode)):
                    raise AuditError("Output name changed during publication")
            finally:
                os.close(current_parent)
        finally:
            os.close(fd)
    finally:
        os.close(parent)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for label in ("development", "production", "candidate"):
        parser.add_argument("--" + label, required=True)
        parser.add_argument("--" + label + "-sha256", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    try:
        report = audit(args.development, args.development_sha256, args.production,
                       args.production_sha256, args.candidate, args.candidate_sha256)
        write_new(args.output, report)
    except (AuditError, OSError, ValueError) as exc:
        print("SCHEMA_AUDIT_REJECTED: " + type(exc).__name__ + ": " + str(exc), file=sys.stderr)
        return 2
    print("REVIEW_ONLY_NOT_DEPLOYABLE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
