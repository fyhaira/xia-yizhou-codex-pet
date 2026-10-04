#!/bin/zsh
set -euo pipefail
SCRIPT_DIR=${0:A:h}
INSTALLER_ROOT=${SCRIPT_DIR:h}
REPO_ROOT=${INSTALLER_ROOT:h}
APP=${1:-"$REPO_ROOT/dist/Xia Yizhou Codex Pet.app"}
[[ -d "$APP" ]] || { print -u2 "Candidate not found"; exit 1; }
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
"$APP/Contents/Resources/runtime/node" --version
"$APP/Contents/Resources/bin/xia-yizhou-codex-pet" dry-run --resources "$APP/Contents/Resources"
