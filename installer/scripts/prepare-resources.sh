#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
INSTALLER_ROOT=${SCRIPT_DIR:h}
REPO_ROOT=${INSTALLER_ROOT:h}
INPUT_ROOT="$REPO_ROOT/.build-inputs"
OUTPUT_ROOT=${OUTPUT_ROOT_OVERRIDE:-"$INSTALLER_ROOT/.generated-resources"}
TOOLKIT_ROOT="$INPUT_ROOT/enhancer"
NODE_DIST="$INPUT_ROOT/node-distribution"
TEMPLATE_ROOT="$INSTALLER_ROOT/Resources"
PAYLOAD_ROOT="$REPO_ROOT/package/xia-yizhou"

EXPECTED_TOOLKIT_COMMIT="69818621da1c850a28ef9aa023126338d65ffc1b"
EXPECTED_TOOLKIT_TREE="97aa2128a035eeaa9be5bf87664999618fa0b2e7"
NODE_VERSION_EXPECTED="v24.21.0"
NODE_EXECUTABLE_SHA256="e4b5a3af0e05c75de2eae013904145f40fe7fc2a6e6f17510128bf45cca4e79b"
NODE_EXECUTABLE_SIZE="122129232"
NODE_LICENSE_SHA256="5888dbb9a1d2b18f2c3e6c5f6af1b39de658372b402a0577b002777f14c62ace"
PET_JSON_SHA256="52ea69e7d57fe51f228fd27772f15c85e731105ebd330c7319197e515f3236ea"
SPRITESHEET_SHA256="f832f37fc5e74d5189b4fc137d6c3897239ec01543d90d8c527dff74c0df37d5"
SLEEP_SHA256="3fd8f1ff8738751ee2a4b7b5cccc7306854c65713eb7405e1234d8099b5e9343"

[[ -d "$TOOLKIT_ROOT/.git" && -x "$NODE_DIST/bin/node" ]] || { print -u2 "Run fetch-dependencies.sh first"; exit 1; }
[[ "$(/usr/bin/git -C "$TOOLKIT_ROOT" rev-parse HEAD)" == "$EXPECTED_TOOLKIT_COMMIT" ]] || { print -u2 "Enhancer commit mismatch"; exit 1; }
[[ "$(/usr/bin/git -C "$TOOLKIT_ROOT" rev-parse HEAD^{tree})" == "$EXPECTED_TOOLKIT_TREE" ]] || { print -u2 "Enhancer tree mismatch"; exit 1; }
/usr/bin/git -C "$TOOLKIT_ROOT" diff --quiet --exit-code || { print -u2 "Enhancer checkout is modified"; exit 1; }
/usr/bin/git -C "$TOOLKIT_ROOT" diff --cached --quiet --exit-code || { print -u2 "Enhancer index is modified"; exit 1; }

[[ "$(/usr/bin/shasum -a 256 "$NODE_DIST/bin/node" | /usr/bin/awk '{print $1}')" == "$NODE_EXECUTABLE_SHA256" ]] || { print -u2 "Node executable hash mismatch"; exit 1; }
[[ "$(/usr/bin/stat -f %z "$NODE_DIST/bin/node")" == "$NODE_EXECUTABLE_SIZE" ]] || { print -u2 "Node executable size mismatch"; exit 1; }
[[ "$("$NODE_DIST/bin/node" --version)" == "$NODE_VERSION_EXPECTED" ]] || { print -u2 "Node version mismatch"; exit 1; }
[[ "$(/usr/bin/lipo -archs "$NODE_DIST/bin/node")" == "arm64" ]] || { print -u2 "Node architecture mismatch"; exit 1; }
[[ "$(/usr/bin/shasum -a 256 "$NODE_DIST/LICENSE" | /usr/bin/awk '{print $1}')" == "$NODE_LICENSE_SHA256" ]] || { print -u2 "Node license mismatch"; exit 1; }

[[ "$(/usr/bin/shasum -a 256 "$PAYLOAD_ROOT/pet.json" | /usr/bin/awk '{print $1}')" == "$PET_JSON_SHA256" ]] || { print -u2 "pet.json mismatch"; exit 1; }
[[ "$(/usr/bin/shasum -a 256 "$PAYLOAD_ROOT/spritesheet.webp" | /usr/bin/awk '{print $1}')" == "$SPRITESHEET_SHA256" ]] || { print -u2 "spritesheet mismatch"; exit 1; }
[[ "$(/usr/bin/shasum -a 256 "$PAYLOAD_ROOT/sleep-strip.png" | /usr/bin/awk '{print $1}')" == "$SLEEP_SHA256" ]] || { print -u2 "sleep strip mismatch"; exit 1; }

STAGE=$(mktemp -d "$INSTALLER_ROOT/.resources-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/toolkit/tests" "$STAGE/toolkit/local" "$STAGE/runtime" "$STAGE/payload/pet/xia-yizhou" "$STAGE/payload/capabilities/xia-yizhou" "$STAGE/metadata"

for item in src compatibility config fixtures package.json pnpm-lock.yaml LICENSE; do
  /usr/bin/ditto --norsrc --noqtn "$TOOLKIT_ROOT/$item" "$STAGE/toolkit/$item"
done
/usr/bin/ditto --norsrc --noqtn "$TOOLKIT_ROOT/node_modules" "$STAGE/toolkit/node_modules"
for item in unit fixture compatibility integration; do
  /usr/bin/ditto --norsrc --noqtn "$TOOLKIT_ROOT/tests/$item" "$STAGE/toolkit/tests/$item"
done
/usr/bin/ditto --norsrc --noqtn "$TEMPLATE_ROOT/toolkit-additions" "$STAGE/toolkit"

/usr/bin/ditto --norsrc --noqtn "$PAYLOAD_ROOT/pet.json" "$STAGE/payload/pet/xia-yizhou/pet.json"
/usr/bin/ditto --norsrc --noqtn "$PAYLOAD_ROOT/spritesheet.webp" "$STAGE/payload/pet/xia-yizhou/spritesheet.webp"
/usr/bin/ditto --norsrc --noqtn "$PAYLOAD_ROOT/sleep-strip.png" "$STAGE/payload/capabilities/xia-yizhou/sleep-strip.png"
/usr/bin/ditto --norsrc --noqtn "$TEMPLATE_ROOT/metadata/product.json" "$STAGE/metadata/product.json"

mkdir -p "$STAGE/toolkit/fixtures/xia-yizhou"
/usr/bin/ditto --norsrc --noqtn "$PAYLOAD_ROOT/pet.json" "$STAGE/toolkit/fixtures/xia-yizhou/pet.json"
/usr/bin/ditto --norsrc --noqtn "$PAYLOAD_ROOT/spritesheet.webp" "$STAGE/toolkit/fixtures/xia-yizhou/spritesheet.webp"
/usr/bin/ditto --norsrc --noqtn "$PAYLOAD_ROOT/sleep-strip.png" "$STAGE/toolkit/fixtures/xia-yizhou/sleep-strip.png"

/usr/bin/ditto --norsrc --noqtn "$NODE_DIST/bin/node" "$STAGE/runtime/node"
/usr/bin/ditto --norsrc --noqtn "$NODE_DIST/LICENSE" "$STAGE/runtime/NODE-LICENSE.txt"
/bin/chmod 755 "$STAGE/runtime/node"
/usr/bin/ditto --norsrc --noqtn "$TEMPLATE_ROOT/metadata/node-provenance.json" "$STAGE/metadata/node-provenance.json"
/usr/bin/ditto --norsrc --noqtn "$REPO_ROOT/THIRD-PARTY-NOTICES.txt" "$STAGE/THIRD-PARTY-NOTICES.txt"

TOOLKIT_TREE_SHA256=$(cd "$STAGE/toolkit" && /usr/bin/find . -type f -print0 | /usr/bin/sort -z | /usr/bin/xargs -0 /usr/bin/shasum -a 256 | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')
TOOLKIT_FILE_MANIFEST="$STAGE/metadata/toolkit-files.sha256"
(cd "$STAGE/toolkit" && /usr/bin/find . -type f -print0 | /usr/bin/sort -z | /usr/bin/xargs -0 /usr/bin/shasum -a 256) > "$TOOLKIT_FILE_MANIFEST"
TOOLKIT_FILE_MANIFEST_SHA256=$(/usr/bin/shasum -a 256 "$TOOLKIT_FILE_MANIFEST" | /usr/bin/awk '{print $1}')
NODE_SHA256=$(/usr/bin/shasum -a 256 "$STAGE/runtime/node" | /usr/bin/awk '{print $1}')
NODE_PROVENANCE_SHA256=$(/usr/bin/shasum -a 256 "$STAGE/metadata/node-provenance.json" | /usr/bin/awk '{print $1}')
THIRD_PARTY_NOTICES_SHA256=$(/usr/bin/shasum -a 256 "$STAGE/THIRD-PARTY-NOTICES.txt" | /usr/bin/awk '{print $1}')
ASAR_PACKAGE_VERSION=$("$STAGE/runtime/node" -p "require('$STAGE/toolkit/node_modules/@electron/asar/package.json').version")
ASAR_PACKAGE_INTEGRITY=$(/usr/bin/awk '/@electron\/asar@4[.]1[.]0/{found=1;next} found&&/resolution:/{print; exit}' "$STAGE/toolkit/pnpm-lock.yaml" | /usr/bin/sed -E 's/.*integrity: ([^}]+).*/\1/')
[[ "$ASAR_PACKAGE_VERSION" == "4.1.0" && -n "$ASAR_PACKAGE_INTEGRITY" ]] || { print -u2 "ASAR dependency validation failed"; exit 1; }

/usr/bin/sed -e "s/@TOOLKIT_COMMIT@/$EXPECTED_TOOLKIT_COMMIT/g" \
  -e "s/@TOOLKIT_GIT_TREE@/$EXPECTED_TOOLKIT_TREE/g" \
  -e "s/@TOOLKIT_TREE_SHA256@/$TOOLKIT_TREE_SHA256/g" \
  -e "s/@TOOLKIT_FILE_MANIFEST_SHA256@/$TOOLKIT_FILE_MANIFEST_SHA256/g" \
  -e "s#@ASAR_PACKAGE_VERSION@#$ASAR_PACKAGE_VERSION#g" \
  -e "s#@ASAR_PACKAGE_INTEGRITY@#$ASAR_PACKAGE_INTEGRITY#g" \
  -e "s/@NODE_VERSION@/$NODE_VERSION_EXPECTED/g" \
  -e "s/@NODE_UPSTREAM_SHA256@/$NODE_EXECUTABLE_SHA256/g" \
  -e "s/@NODE_SHA256@/$NODE_SHA256/g" \
  -e "s/@NODE_PROVENANCE_SHA256@/$NODE_PROVENANCE_SHA256/g" \
  -e "s/@THIRD_PARTY_NOTICES_SHA256@/$THIRD_PARTY_NOTICES_SHA256/g" \
  -e "s/@PET_JSON_SHA256@/$PET_JSON_SHA256/g" \
  -e "s/@SPRITESHEET_SHA256@/$SPRITESHEET_SHA256/g" \
  -e "s/@SLEEP_SHA256@/$SLEEP_SHA256/g" \
  -e "s/@PET_ID@/xia-yizhou/g" \
  -e "s/@SPRITESHEET_FILENAME@/spritesheet.webp/g" \
  "$TEMPLATE_ROOT/metadata/pin.template.json" > "$STAGE/metadata/pin.json"

[[ ! -e "$OUTPUT_ROOT" ]] || /bin/mv "$OUTPUT_ROOT" "$INSTALLER_ROOT/.resources-old.$$.tmp"
/bin/mv "$STAGE" "$OUTPUT_ROOT"
[[ ! -e "$INSTALLER_ROOT/.resources-old.$$.tmp" ]] || /bin/rm -rf "$INSTALLER_ROOT/.resources-old.$$.tmp"
trap - EXIT
print "Prepared verified offline resources"
