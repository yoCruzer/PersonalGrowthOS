# Independent review: loopback-v1 — 2026-11-07

No remaining must-fix found in the reviewed candidate. This verifies a transport replacement after the helper's legacy App-Documents access received EPERM. **It does not prove actual signed-App execution, CloudKit behavior, or the 27-stage G1 matrix.**

Implementation was read only. No actual SyncLab launch, signing command, protected App-container access, device access, account operation, or CloudKit request occurred. The receiver tests use synthetic data and mock every launcher subprocess. Network tests bind only 127.0.0.1.

## Results

- Collector direct tests: **9/9 PASS**. Identity/provenance/process checks, duplicate JSON rejection, identical retransmission, changed retransmission refusal, publication failure, exact ACK, unsafe plan path refusal.
- Real local sockets and mocked complete launcher: **7/7 PASS**. Token/launch authentication, route/encoding/size rejection, exact SHA ACK, explicit clean environment, no container access, repeated stage claim refusal.
- Copied current Swift transport against synthetic HTTP server: **7/7 PASS**. Exact ACK succeeds; wrong digest, HTTP 500, malformed/oversized response, redirect and timeout fail. Request token/launch headers checked; redirect target was not contacted.

The Swift harness compiles the actual `ProbeWindowTransport.swift` source. Minimal dependencies are stubbed: authorization value, digest utility, loopback URL validation and redirect delegate. It does not test the full App or decoder. Native integration/build results belong to the implementation owner's separate logs.

One reported must-fix was closed: the initial new Python branch omitted the legacy command-ID validation, permitting a matching synthetic command ID with path traversal to escape the stage's observation directory. `validate_plan` now rejects malformed identities, unsafe/duplicate command IDs, invalid actions/counts, raw-plan mismatch and unsupported crash exits before server creation or App launch. The original 8-PASS/1-FAIL log is retained as `receiver-01.log`; final constructor-level rejection is in `receiver-02.log`. The first HTTP attempt failed because the execution sandbox denied loopback bind; `swift-transport.log` records that environment restriction. The explicitly authorized loopback-only rerun passed; this was not a product failure.

## Ordering and evidence semantics

Source inspection confirms local private journal publication and directory fsync precede authenticated POST. The Swift call only succeeds on HTTP 200 plus the SHA256 of the exact sent bytes, within a bounded wait. Deliberate fault exits follow that successful call. Collector publication uses atomic hardlink, fsync and no replacement; identical retransmission acknowledges the existing bytes, while changed data is rejected. Every new stage has a fresh token and launch ID; results bind to the prepared plan, commands and one process nonce. The App refuses to send a cached manual-plan report as fresh execution and sends a fixed failure instead.

Observation files are retained separately, including pre-boundary phases. `boundary.json` is a copy of the expected boundary observation. A successful POST proves durable receipt, not that the process reached its deliberate `_exit` or that server data converged. An accidental interruption after receipt remains distinguishable only through retained boundary and subsequent fresh-process recovery evidence. `open -W` still does not expose the App's numeric exit status.

The new helper does not access the App container, request Full Disk Access or alter account settings. Tokens stay out of command arguments and retained transport metadata. Only the explicit signed Debug App path accepts the environment; Release excludes the new transport and App branch. The original file-based legacy branch remains for historical regression and is not silently claimed to work under the reported EPERM environment.

## Reproduce

On macOS with Swift and Python 3, from this directory:

```sh
python3 scripts/run_review.py --repo /path/to/PersonalGrowthOS --output /tmp/new-loopback-independent-output
```

The output directory must not exist. This command needs permission for local 127.0.0.1 sockets, but no external network, App, Apple credentials, device or CloudKit access. Source hashes and original/final logs are retained beside this report. The seven HTTP helper tests and nine direct collector tests are suitable additions to the bounded Python regression suite.
