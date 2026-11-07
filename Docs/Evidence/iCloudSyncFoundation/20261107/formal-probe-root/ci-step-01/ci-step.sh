set -o pipefail
evidence="$RUNNER_TEMP/sync-foundation-evidence"
swift run --package-path Packages/SyncFoundation --scratch-path "$RUNNER_TEMP/sync-foundation-build" FormalDevelopmentProbe plan "$evidence/formal-plan"
plan_sha=$(cat "$evidence/formal-plan/plan.sha256")
swift run --package-path Packages/SyncFoundation --scratch-path "$RUNNER_TEMP/sync-foundation-build" FormalDevelopmentProbe replay "$evidence/formal-plan" "$plan_sha" "$evidence/formal-replay"
probe_bin=$(swift build --package-path Packages/SyncFoundation --scratch-path "$RUNNER_TEMP/sync-foundation-build" --show-bin-path)/FormalDevelopmentProbe
set +e
"$probe_bin" preflight "$evidence/formal-plan" "$plan_sha" "$probe_bin" "$evidence/formal-preflight"
preflight_exit=$?
set -e
test "$preflight_exit" -eq 2
python3 - <<'PY'
import json, os, pathlib
root = pathlib.Path(os.environ['RUNNER_TEMP']) / 'sync-foundation-evidence'
replay = json.loads((root / 'formal-replay/report.json').read_text())
preflight = json.loads((root / 'formal-preflight/report.json').read_text())
assert replay['mode'] == 'OFFLINE_ONLY' and replay['status'] == 'OFFLINE_PASS'
assert len(replay['commands']) == 6 and all(x['status'] == 'OFFLINE_PASS' for x in replay['commands'])
assert replay['networkOperations'] == 0 and not replay['p0Passed'] and not replay['serverSchemaChecked']
assert preflight['mode'] == 'OFFLINE_ONLY' and preflight['operation'] == 'READ_ONLY_PREFLIGHT'
assert preflight['status'] == 'NOT_READY' and 'PROFILE_MISSING' in preflight['rejectionCodes']
assert not preflight['networkAuthorized'] and not preflight['readyForCloudRun'] and not preflight['p0Passed']
assert preflight['planSHA256'] == replay['planSHA256']
print('Six offline SDK checks passed; actual unprovisioned signing preflight correctly rejected.')
PY
