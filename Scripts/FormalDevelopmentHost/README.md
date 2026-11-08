# Isolated Mac locked-host packaging

This script creates a new **UNPROVISIONED_NO_DEVELOPER_SIGNATURE** `.app` from the
reviewed repository source. It does not sign, provision, register, install, access
CloudKit, or enable a live execution path. It does not modify the formal product,
SyncLab, entitlements, Apple accounts or existing output. The source Swift remains
unchanged. A linker-generated ad-hoc signature, if present, is preserved; that is
not an Apple Development identity or provisioning qualification.

```
python3 Scripts/FormalDevelopmentHost/package_locked_host.py --output /private/tmp/NEW_LOCKED_APP
python3 Scripts/FormalDevelopmentHost/verify_packaging.py \
  --package-output /private/tmp/NEW_LOCKED_APP \
  --probe-binary /absolute/path/to/FormalDevelopmentProbe \
  --evidence-output /private/tmp/NEW_VALIDATION
```

Requires macOS14+, the configured Xcode Swift toolchain, Python3.9+, and an existing
real parent directory. Use absolute paths with no symlink or `.`/`..` components.
Output must not exist and must not be within the source package. Failure leaves
available logs/partial output for inspection; no removal or automatic retry occurs.
No arbitrary `--package-path`, prebuilt binary, entitlement, Bundle ID or environment
input exists. The source location is the script's own repository's
`Packages/SyncFoundation`. `trusted-source-sha256.json` binds the exact reviewed
Package.swift and all Swift source/test files. Any changed/additional/missing Swift
source rejects before building or creating output; updating this allowlist requires
reviewing the changed source, not blindly regenerating it. The manifest is separately
pinned in the script and contains **no external package dependencies or plugins**.
The build uses `--disable-automatic-resolution`, the fixed locked host product, and
a new finite source snapshot. Original sources are reread afterward and changes reject. The actual compiler-input
snapshot retains an open directory fd and is rehashed with directory-identity checks
before/after building, after product-path lookup and before writing the receipt;
modified, added or missing source files reject instead of claiming a source binding.

Output contains `FormalSyncProbe.app`, external `candidate.entitlements`,
`packaging.json`, `build.log`, source snapshot and build scratch. The Info.plist uses
MacOSX/macOS14, executable `FormalDevelopmentHost` and the separate candidate ID
`com.yocruzer.PersonalGrowthOS.FormalSyncProbe`. The outside entitlement file proposes
the configured team and formal CloudKit container in Development, sandbox and client
network capability. It is **not applied or embedded**. No AppGroup, Push entitlement,
Production branch, profile or signing certificate is selected. The formal app's
capability association does not establish registration/profile availability for this
separate candidate client.

The receipt proves source/Info/entitlement/binary hashes and build completion only.
`appExecutionPerformed: false` means packaging itself does not prove runtime behavior.
The separate verifier runs the built executable's `inspect`, expects exit2 and
`NOT_READY` with no authority, then invokes actual existing signing preflight on the
`.app`. It expects identity/profile failures and NOT_READY; it does not assume a
particular `signatureVerified` value from a linker ad-hoc signature. Verifier negative
cases cover wrong plan hash, absent live option, existing output, input/output/parent
symlinks, changed manifest/Swift source and output inside the source package. It only
changes disposable synthetic fixture copies. Reports do not include raw profiles.

The `.app` is a command-line helper packaged for future manual signing preparation,
not a graphical client; use `Contents/MacOS/FormalDevelopmentHost inspect ...`, not a
Finder launch. Future actual Mac signing/profile qualification and real authority
factory remain external gates. This does not authorize signing or network execution.

The additional `inspect-runtime BASE64_REQUEST` command performs offline self-signing
inspection and returns a report, never a capability. Its canonical JSON input has
`mode: OFFLINE_RUNTIME_INSPECTION`, the five reviewed hashes in `runtime`, and base64
`packagingReceipt` / `sourcePins` bytes. It reads its own sealed app; no caller artifact
path or CloudKit/account operation is accepted. An unqualified app or unavailable
device evidence returns exit2 / NOT_READY. Even a SELF_QUALIFICATION_PASS does not
authorize a cloud request. `inspect-fixture` remains a parameterless, fixed synthetic
offline test. The separate `enroll-guard BASE64_APPROVAL EXPECTED_SHA` and `run-approved BASE64_APPROVAL EXPECTED_SHA` commands require a canonical, explicitly approved purpose/window and real self qualification. They must not be invoked without the corresponding Owner authorization; malformed/template inputs reject before storage or CloudKit. Enrollment is the only path allowed to initialize the local guard. Each process permits one production attempt, and the durable ledger forbids replay across processes. Actual provisioning and
offline signed observations are recorded separately in the project execution evidence.

`export-run RUN_UUID` reads only the matching run and execution ledger under this
probe's OS-selected Application Support directory. It never opens the Keychain,
constructs a CloudKit container, acquires a ledger lock, repairs state, or executes a
window. Output is private JSON with exact file bytes and SHA256 values. Keep it out
of public Git/PR attachments. A complete export does not authenticate ledger HMACs
or establish P0 success; rejected/missing sections are explicitly listed. File
allowlists, ownership, no-follow/single-link checks and bounded reads reject unsafe
inputs. A failed cloud window remains consumed after export.

File access uses held directory fds, exclusive creation and no-follow flags. Before
and after external build operations it verifies directory identities. Caller-owned
immutable source/output leases are still required: URL-based compiler paths cannot
claim protection against a malicious same-user ABA replacement. This is a repeatable
build workflow with source hashes, not a promise of bit-for-bit builds across Xcode,
architectures, directory paths or compiler versions.
