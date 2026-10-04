#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
INSTALLER_ROOT=${SCRIPT_DIR:h}
REPO_ROOT=${INSTALLER_ROOT:h}

"$SCRIPT_DIR/fetch-dependencies.sh"
"$SCRIPT_DIR/prepare-resources.sh"

cd "$INSTALLER_ROOT"
mkdir -p .build/module-cache .build/swiftpm-cache
SDKROOT=$(xcrun --sdk macosx --show-sdk-path) \
CLANG_MODULE_CACHE_PATH="$INSTALLER_ROOT/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$INSTALLER_ROOT/.build/module-cache" \
XDG_CACHE_HOME="$INSTALLER_ROOT/.build/swiftpm-cache" \
/usr/bin/swift build -c release --disable-sandbox

STAGE=$(mktemp -d "$INSTALLER_ROOT/.app-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Xia Yizhou Codex Pet.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
/usr/bin/ditto --norsrc --noqtn "$INSTALLER_ROOT/.build/release/XiaYizhouCodexPet" "$APP/Contents/MacOS/XiaYizhouCodexPet"
/usr/bin/ditto --norsrc --noqtn "$INSTALLER_ROOT/.build/release/xia-yizhou-codex-pet" "$APP/Contents/Resources/bin/xia-yizhou-codex-pet"
/usr/bin/ditto --norsrc --noqtn "$INSTALLER_ROOT/.generated-resources" "$APP/Contents/Resources"
/usr/bin/ditto --norsrc --noqtn "$INSTALLER_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/bin/chmod 755 "$APP/Contents/MacOS/XiaYizhouCodexPet" "$APP/Contents/Resources/bin/xia-yizhou-codex-pet" "$APP/Contents/Resources/runtime/node"
/usr/bin/strip -S "$APP/Contents/MacOS/XiaYizhouCodexPet" "$APP/Contents/Resources/bin/xia-yizhou-codex-pet"
CODE_SIGN_IDENTITY=${CODE_SIGN_IDENTITY:--} "$SCRIPT_DIR/sign-candidate.sh" "$APP"

mkdir -p "$REPO_ROOT/dist"
TARGET="$REPO_ROOT/dist/Xia Yizhou Codex Pet.app"
[[ ! -e "$TARGET" ]] || { print -u2 "Refusing to overwrite existing candidate: $TARGET"; exit 1; }
/bin/mv "$APP" "$TARGET"
trap - EXIT
print "$TARGET"
