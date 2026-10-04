#!/bin/zsh
set -euo pipefail

[[ $# -eq 1 ]] || { print -u2 "Usage: $0 <app-bundle>"; exit 64; }

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
APP=$1
IDENTITY=${CODE_SIGN_IDENTITY:--}
NODE="$APP/Contents/Resources/runtime/node"
HELPER="$APP/Contents/Resources/bin/xia-yizhou-codex-pet"
PIN="$APP/Contents/Resources/metadata/pin.json"
NODE_ENTITLEMENTS="$PROJECT_ROOT/Resources/signing/node.entitlements"

[[ -d "$APP" && -x "$NODE" && -x "$HELPER" && -f "$PIN" && -f "$NODE_ENTITLEMENTS" ]] || {
  print -u2 "Candidate signing inputs are incomplete"
  exit 1
}

# Production signing is deliberately inside-out. Developer ID builds set
# CODE_SIGN_IDENTITY; local structural-QA builds use an ad-hoc identity.
SIGN_ARGS=(--force --sign "$IDENTITY" --options runtime)
if [[ "$IDENTITY" != "-" ]]; then
  SIGN_ARGS+=(--timestamp)
fi

/usr/bin/codesign "${SIGN_ARGS[@]}" --entitlements "$NODE_ENTITLEMENTS" "$NODE"
[[ "$("$NODE" --version)" == "v24.21.0" ]] || { print -u2 "Signed bundled Node failed its version smoke test"; exit 1; }
"$NODE" -e "const c=require('crypto'); if(c.createHash('sha256').update('ok').digest('hex').length!==64) process.exit(1)"
/usr/bin/codesign --verify --strict --verbose=2 "$NODE"

SIGNED_NODE_SHA256=$(/usr/bin/shasum -a 256 "$NODE" | /usr/bin/awk '{print $1}')
"$NODE" -e "const fs=require('fs');const p=process.argv[1];const h=process.argv[2];const j=JSON.parse(fs.readFileSync(p,'utf8'));j.bundledNodeSHA256=h;fs.writeFileSync(p,JSON.stringify(j,null,2)+'\\n')" "$PIN" "$SIGNED_NODE_SHA256"

/usr/bin/codesign "${SIGN_ARGS[@]}" "$HELPER"
/usr/bin/codesign --verify --strict --verbose=2 "$HELPER"

# Sign the outer bundle last. --deep is intentionally not used for signing.
/usr/bin/codesign "${SIGN_ARGS[@]}" "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

print "Signed candidate inside-out with identity: $IDENTITY"
