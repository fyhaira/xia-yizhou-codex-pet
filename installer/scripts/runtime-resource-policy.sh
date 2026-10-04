#!/bin/zsh

# Shared release-resource policy. Callers are responsible for set -euo pipefail.

remove_non_runtime_pnpm_artifacts() {
  local node_modules=$1
  /bin/rm -rf "$node_modules/.bin"
  /bin/rm -f \
    "$node_modules/.modules.yaml" \
    "$node_modules/.pnpm-workspace-state-v1.json"
}

verify_no_non_runtime_pnpm_artifacts() {
  local node_modules=$1
  local forbidden=(
    "$node_modules/.bin"
    "$node_modules/.modules.yaml"
    "$node_modules/.pnpm-workspace-state-v1.json"
  )
  local path
  for path in "${forbidden[@]}"; do
    [[ ! -e "$path" ]] || {
      print -u2 "Forbidden non-runtime pnpm artifact: $path"
      return 1
    }
  done
}

verify_no_machine_local_paths() {
  local resources=$1
  shift
  local offender=""
  local pattern='(/Users/[^/[:space:]]+/|/private/tmp/|file:///(Users/[^/[:space:]]+/|private/tmp/))'
  local pinned_node="$resources/runtime/node"
  local raw_node_sha256='e4b5a3af0e05c75de2eae013904145f40fe7fc2a6e6f17510128bf45cca4e79b'
  local signed_node_sha256='b0460928e33cbc946046357f75dfebc707f8940a035efdcd3f29b3aa547cd834'

  # The official Node binary contains Node's immutable upstream build path.
  # Exempt only that exact raw or ad-hoc-signed binary; scan every other file,
  # including binaries, for generic machine-path classes.
  if [[ -f "$pinned_node" ]]; then
    local node_sha256
    node_sha256=$(/usr/bin/shasum -a 256 "$pinned_node" | /usr/bin/awk '{print $1}')
    if [[ "$node_sha256" != "$raw_node_sha256" && "$node_sha256" != "$signed_node_sha256" ]]; then
      print -u2 "Bundled Node hash is not eligible for the upstream-path exemption: $pinned_node"
      return 1
    fi
  fi

  offender=$(/usr/bin/find "$resources" -type f ! -path "$pinned_node" -print0 | \
    /usr/bin/xargs -0 /usr/bin/grep -aEl "$pattern" 2>/dev/null | /usr/bin/head -n 1) || true
  if [[ -n "$offender" ]]; then
    print -u2 "Machine-local absolute path found in packaged resource: $offender"
    return 1
  fi

  local literal
  for literal in "$@"; do
    [[ -n "$literal" ]] || continue
    offender=$(/usr/bin/find "$resources" -type f -print0 | \
      /usr/bin/xargs -0 /usr/bin/grep -alF "$literal" 2>/dev/null | /usr/bin/head -n 1) || true
    if [[ -n "$offender" ]]; then
      print -u2 "Active build/store path found in packaged resource: $offender"
      return 1
    fi
  done
}

verify_toolkit_file_manifest() {
  local toolkit=$1
  local manifest=$2
  local generated
  generated=$(mktemp "${TMPDIR:-/private/tmp}/xia-toolkit-manifest.XXXXXX")
  (cd "$toolkit" && /usr/bin/find . -type f -print0 | /usr/bin/sort -z | \
    /usr/bin/xargs -0 /usr/bin/shasum -a 256) > "$generated"
  if ! /usr/bin/cmp -s "$generated" "$manifest"; then
    print -u2 "Toolkit file manifest does not describe the final packaged file tree"
    /usr/bin/diff -u "$manifest" "$generated" >&2 || true
    /bin/rm -f "$generated"
    return 1
  fi
  /bin/rm -f "$generated"
}
