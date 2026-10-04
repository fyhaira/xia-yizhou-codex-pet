#!/bin/zsh
set -euo pipefail
SCRIPT_DIR=${0:A:h}
INSTALLER_ROOT=${SCRIPT_DIR:h}
REPO_ROOT=${INSTALLER_ROOT:h}
. "$SCRIPT_DIR/runtime-resource-policy.sh"
APP=${1:-"$REPO_ROOT/dist/Xia Yizhou Codex Pet.app"}
[[ -d "$APP" ]] || { print -u2 "Candidate not found"; exit 1; }
RESOURCES="$APP/Contents/Resources"
NODE="$RESOURCES/runtime/node"
TOOLKIT="$RESOURCES/toolkit"
MANIFEST="$RESOURCES/metadata/toolkit-files.sha256"

verify_no_non_runtime_pnpm_artifacts "$TOOLKIT/node_modules"
verify_no_machine_local_paths "$RESOURCES" "$REPO_ROOT" "${HOME:-}"
verify_toolkit_file_manifest "$TOOLKIT" "$MANIFEST"
[[ -f "$TOOLKIT/node_modules/@electron/asar/package.json" && \
   -f "$TOOLKIT/node_modules/@electron/asar/lib/asar.js" ]] || {
  print -u2 "Pinned @electron/asar runtime entry point is missing"
  exit 1
}
[[ "$("$NODE" -e "const fs=require('fs');const p=process.argv[1];process.stdout.write(JSON.parse(fs.readFileSync(p,'utf8')).version)" "$TOOLKIT/node_modules/@electron/asar/package.json")" == "4.1.0" ]] || {
  print -u2 "Pinned @electron/asar runtime version mismatch"
  exit 1
}
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
"$NODE" --version
"$RESOURCES/bin/xia-yizhou-codex-pet" dry-run --resources "$RESOURCES"
