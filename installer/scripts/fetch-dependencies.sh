#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
INSTALLER_ROOT=${SCRIPT_DIR:h}
REPO_ROOT=${INSTALLER_ROOT:h}
INPUT_ROOT="$REPO_ROOT/.build-inputs"

NODE_VERSION="24.21.0"
NODE_ARCHIVE="node-v24.21.0-darwin-arm64.tar.gz"
NODE_ROOT="node-v24.21.0-darwin-arm64"
NODE_BASE_URL="https://nodejs.org/download/release/v24.21.0"
NODE_ARCHIVE_SHA256="bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057"
NODE_SHASUMS_SHA256="f410428039e2c922a14058df067a4482691c9304a5c01a75847f9f3f2d3307f6"
NODE_EXECUTABLE_SHA256="e4b5a3af0e05c75de2eae013904145f40fe7fc2a6e6f17510128bf45cca4e79b"

ENHANCER_REPOSITORY="https://github.com/fyhaira/codex-pet-interaction-enhancer.git"
ENHANCER_COMMIT="69818621da1c850a28ef9aa023126338d65ffc1b"
ENHANCER_TREE="97aa2128a035eeaa9be5bf87664999618fa0b2e7"
PNPM_VERSION="11.25.0"

mkdir -p "$INPUT_ROOT"
STAGE=$(mktemp -d "$INPUT_ROOT/.fetch-stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/downloads"
/usr/bin/curl --fail --location --proto '=https' --tlsv1.2 "$NODE_BASE_URL/$NODE_ARCHIVE" -o "$STAGE/downloads/$NODE_ARCHIVE"
/usr/bin/curl --fail --location --proto '=https' --tlsv1.2 "$NODE_BASE_URL/SHASUMS256.txt" -o "$STAGE/downloads/SHASUMS256.txt"

[[ "$(/usr/bin/shasum -a 256 "$STAGE/downloads/$NODE_ARCHIVE" | /usr/bin/awk '{print $1}')" == "$NODE_ARCHIVE_SHA256" ]] || { print -u2 "Node archive hash mismatch"; exit 1; }
[[ "$(/usr/bin/shasum -a 256 "$STAGE/downloads/SHASUMS256.txt" | /usr/bin/awk '{print $1}')" == "$NODE_SHASUMS_SHA256" ]] || { print -u2 "Node checksum metadata mismatch"; exit 1; }
[[ "$(/usr/bin/awk -v file="$NODE_ARCHIVE" '$2 == file {print $1}' "$STAGE/downloads/SHASUMS256.txt")" == "$NODE_ARCHIVE_SHA256" ]] || { print -u2 "Official Node checksum does not match archive"; exit 1; }

/usr/bin/tar -xzf "$STAGE/downloads/$NODE_ARCHIVE" -C "$STAGE"
NODE_DIST="$STAGE/$NODE_ROOT"
[[ "$(/usr/bin/shasum -a 256 "$NODE_DIST/bin/node" | /usr/bin/awk '{print $1}')" == "$NODE_EXECUTABLE_SHA256" ]] || { print -u2 "Extracted Node hash mismatch"; exit 1; }
[[ "$("$NODE_DIST/bin/node" --version)" == "v$NODE_VERSION" ]] || { print -u2 "Node version mismatch"; exit 1; }
[[ "$(/usr/bin/lipo -archs "$NODE_DIST/bin/node")" == "arm64" ]] || { print -u2 "Node architecture mismatch"; exit 1; }

mkdir -p "$STAGE/enhancer"
/usr/bin/git -C "$STAGE/enhancer" init
/usr/bin/git -C "$STAGE/enhancer" remote add origin "$ENHANCER_REPOSITORY"
/usr/bin/git -C "$STAGE/enhancer" fetch --depth 1 origin "$ENHANCER_COMMIT"
/usr/bin/git -C "$STAGE/enhancer" checkout --detach FETCH_HEAD
[[ "$(/usr/bin/git -C "$STAGE/enhancer" rev-parse HEAD)" == "$ENHANCER_COMMIT" ]] || { print -u2 "Enhancer commit mismatch"; exit 1; }
[[ "$(/usr/bin/git -C "$STAGE/enhancer" rev-parse HEAD^{tree})" == "$ENHANCER_TREE" ]] || { print -u2 "Enhancer tree mismatch"; exit 1; }

(cd "$STAGE/enhancer" && PATH="$NODE_DIST/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$NODE_DIST/bin/corepack" pnpm@"$PNPM_VERSION" install --frozen-lockfile --ignore-scripts)
[[ "$("$NODE_DIST/bin/node" -p "require('$STAGE/enhancer/node_modules/@electron/asar/package.json').version")" == "4.1.0" ]] || { print -u2 "Pinned ASAR dependency mismatch"; exit 1; }

mkdir -p "$STAGE/ready"
/usr/bin/ditto --norsrc --noqtn "$NODE_DIST" "$STAGE/ready/node-distribution"
/usr/bin/ditto --norsrc --noqtn "$STAGE/enhancer" "$STAGE/ready/enhancer"

for item in node-distribution enhancer; do
  [[ ! -e "$INPUT_ROOT/$item" ]] || /bin/mv "$INPUT_ROOT/$item" "$INPUT_ROOT/.old-$item-$$"
  /bin/mv "$STAGE/ready/$item" "$INPUT_ROOT/$item"
  [[ ! -e "$INPUT_ROOT/.old-$item-$$" ]] || /bin/rm -rf "$INPUT_ROOT/.old-$item-$$"
done

trap - EXIT
/bin/rm -rf "$STAGE"
print "Verified build inputs are ready under .build-inputs"
