#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
ROOT=${SCRIPT_DIR:h}
. "$ROOT/installer/scripts/runtime-resource-policy.sh"

passes=0
failures=0
pass() { print "PASS $1"; passes=$((passes + 1)); }
fail() { print -u2 "FAIL $1"; failures=$((failures + 1)); }

TMP=$(mktemp -d "${TMPDIR:-/private/tmp}/xia-packaging-test.XXXXXX")
trap '/bin/rm -rf "$TMP"' EXIT
TOOLKIT="$TMP/resources/toolkit"
NODE_MODULES="$TOOLKIT/node_modules"
mkdir -p "$NODE_MODULES/.bin" "$NODE_MODULES/.pnpm/@electron+asar@4.1.0/node_modules/@electron/asar/lib" "$NODE_MODULES/@electron" "$TMP/resources/metadata"
print '#!/bin/sh\nexec node /private/tmp/build/node_modules/@electron/asar/bin/asar.mjs "$@"' > "$NODE_MODULES/.bin/asar"
print '{"storeDir":"/Users/example/Library/pnpm/store/v11"}' > "$NODE_MODULES/.modules.yaml"
print '{}' > "$NODE_MODULES/.package-map.json"
print '{"lastValidatedTimestamp":1}' > "$NODE_MODULES/.pnpm-workspace-state-v1.json"
print 'lockfileVersion: 9' > "$NODE_MODULES/.pnpm/lock.yaml"
print '{"name":"@electron/asar","version":"4.1.0","exports":"./lib/asar.js"}' > "$NODE_MODULES/.pnpm/@electron+asar@4.1.0/node_modules/@electron/asar/package.json"
print 'export const getRawHeader = () => {};' > "$NODE_MODULES/.pnpm/@electron+asar@4.1.0/node_modules/@electron/asar/lib/asar.js"
ln -s ../.pnpm/@electron+asar@4.1.0/node_modules/@electron/asar "$NODE_MODULES/@electron/asar"

remove_non_runtime_pnpm_artifacts "$NODE_MODULES"
if verify_no_non_runtime_pnpm_artifacts "$NODE_MODULES"; then pass "path-bound pnpm artifacts excluded"; else fail "path-bound pnpm artifacts excluded"; fi
if [[ -f "$NODE_MODULES/.package-map.json" && -f "$NODE_MODULES/.pnpm/lock.yaml" ]]; then pass "deterministic package metadata retained"; else fail "deterministic package metadata retained"; fi

ASAR_ROOT="$NODE_MODULES/.pnpm/@electron+asar@4.1.0/node_modules/@electron/asar"
if [[ -L "$NODE_MODULES/@electron/asar" && -f "$NODE_MODULES/@electron/asar/package.json" && -f "$ASAR_ROOT/lib/asar.js" ]]; then
  pass "@electron/asar package link and runtime files preserved"
else
  fail "@electron/asar package link and runtime files preserved"
fi

MANIFEST="$TMP/resources/metadata/toolkit-files.sha256"
(cd "$TOOLKIT" && /usr/bin/find . -type f -print0 | /usr/bin/sort -z | /usr/bin/xargs -0 /usr/bin/shasum -a 256) > "$MANIFEST"
if verify_toolkit_file_manifest "$TOOLKIT" "$MANIFEST"; then pass "manifest matches final toolkit tree"; else fail "manifest matches final toolkit tree"; fi

print 'const leaked = "/private/tmp/injected-build/input";' > "$TOOLKIT/injected.mjs"
if verify_no_machine_local_paths "$TMP/resources" >/dev/null 2>"$TMP/path-error"; then
  fail "machine-path gate rejects injected path"
elif /usr/bin/grep -F 'injected.mjs' "$TMP/path-error" >/dev/null; then
  pass "machine-path gate rejects injected path with filename"
else
  fail "machine-path gate names injected file"
fi

if verify_toolkit_file_manifest "$TOOLKIT" "$MANIFEST" >/dev/null 2>"$TMP/manifest-error"; then
  fail "manifest rejects post-generation toolkit mutation"
else
  pass "manifest rejects post-generation toolkit mutation"
fi
/bin/rm -f "$TOOLKIT/injected.mjs"

printf '\0/private/tmp/injected-binary/input\0' > "$TOOLKIT/injected.bin"
if verify_no_machine_local_paths "$TMP/resources" >/dev/null 2>"$TMP/binary-path-error"; then
  fail "machine-path gate scans binary resources"
elif /usr/bin/grep -F 'injected.bin' "$TMP/binary-path-error" >/dev/null; then
  pass "machine-path gate scans binary resources"
else
  fail "binary machine-path diagnostic names injected file"
fi

print "RESULT passed=$passes failed=$failures total=$((passes + failures))"
(( failures == 0 ))
