#!/bin/sh
# Runs before Sources/Resources; reads build inputs only, never mutates the source checkout.
set -eu
pgos_source=$1
pgos_output=$2
pgos_commit=''
pgos_origin=unknown
pgos_dirty=false
pgos_tag=''
pgos_head=$(/usr/bin/git --no-optional-locks -C "$pgos_source" rev-parse HEAD 2>/dev/null || true)
valid_sha() {
    [ "${#1}" -eq 40 ] || return 1
    case "$1" in *[!0-9a-fA-F]*) return 1 ;; esac
}
if [ "${CI_COMMIT+x}" = x ]; then
    if ! valid_sha "$CI_COMMIT"; then
        echo 'error: CI_COMMIT must be a complete 40-digit Git SHA.' >&2; exit 1
    fi
    pgos_commit=$(printf '%s' "$CI_COMMIT" | tr 'A-F' 'a-f')
    if valid_sha "$pgos_head" && [ "$pgos_commit" != "$pgos_head" ]; then
        echo 'error: CI_COMMIT does not match the checked-out source HEAD.' >&2; exit 1
    fi
    pgos_origin=xcodeCloud
    pgos_tag=${CI_TAG-}
    if [ "${#pgos_tag}" -gt 256 ]; then echo 'error: CI_TAG exceeds the safe length.' >&2; exit 1; fi
    case "$pgos_tag" in *[!a-zA-Z0-9._/+-]*) echo 'error: CI_TAG contains unsupported characters.' >&2; exit 1 ;; esac
elif valid_sha "$pgos_head"; then
    pgos_commit=$pgos_head
    pgos_origin=localGit
    if [ -n "$(/usr/bin/git --no-optional-locks -C "$pgos_source" status --porcelain --untracked-files=normal 2>/dev/null)" ]; then pgos_dirty=true; fi
fi
mkdir -p "$(dirname "$pgos_output")"
# All inserted values are checked ASCII or fixed literals; there is no shell evaluation or XML injection.
printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>Commit</key><string>%s</string><key>Source</key><string>%s</string><key>Dirty</key><%s/><key>Tag</key><string>%s</string></dict></plist>\n' "$pgos_commit" "$pgos_origin" "$pgos_dirty" "$pgos_tag" > "$pgos_output"
/usr/bin/plutil -lint "$pgos_output" >/dev/null
