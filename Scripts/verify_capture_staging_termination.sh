#!/bin/sh
set -eu
repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture_root=$(mktemp -d /tmp/PGOS-StagingTermination.XXXXXX)
fixture_binary="$fixture_root/StagingFixture"
xcrun swiftc -module-cache-path /tmp/PGOSCaptureStagingModuleCache -parse-as-library "$repository/SharedCapture/ShareInbox.swift" "$repository/PersonalGrowthOSTests/Fixtures/CaptureStagingTerminationFixture.swift" -o "$fixture_binary"
mkfifo "$fixture_root/ready"
"$fixture_binary" hold "$fixture_root" > "$fixture_root/ready" &
holder_pid=$!
trap 'kill -KILL "$holder_pid" 2>/dev/null || true' EXIT
IFS= read -r session_name < "$fixture_root/ready"
"$fixture_binary" reap "$fixture_root" 0
kill -KILL "$holder_pid"
wait "$holder_pid" 2>/dev/null || true
trap - EXIT
"$fixture_binary" reap "$fixture_root" 1
printf 'Evidence root: %s\n' "$fixture_root"
