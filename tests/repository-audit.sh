#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
ROOT=${SCRIPT_DIR:h}
failures=0
passes=0

pass() { print "PASS $1"; passes=$((passes + 1)); }
fail() { print -u2 "FAIL $1"; failures=$((failures + 1)); }
hash_is() {
  local expected=$1 file=$2
  [[ "$(/usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{print $1}')" == "$expected" ]]
}

payload=("$ROOT"/package/xia-yizhou/*(N.))
if [[ ${#payload} -eq 3 && -f "$ROOT/package/xia-yizhou/pet.json" && -f "$ROOT/package/xia-yizhou/spritesheet.webp" && -f "$ROOT/package/xia-yizhou/sleep-strip.png" ]]; then pass "payload allowlist"; else fail "payload allowlist"; fi
hash_is 52ea69e7d57fe51f228fd27772f15c85e731105ebd330c7319197e515f3236ea "$ROOT/package/xia-yizhou/pet.json" && pass "pet.json hash" || fail "pet.json hash"
hash_is f832f37fc5e74d5189b4fc137d6c3897239ec01543d90d8c527dff74c0df37d5 "$ROOT/package/xia-yizhou/spritesheet.webp" && pass "spritesheet hash" || fail "spritesheet hash"
hash_is 3fd8f1ff8738751ee2a4b7b5cccc7306854c65713eb7405e1234d8099b5e9343 "$ROOT/package/xia-yizhou/sleep-strip.png" && pass "sleep strip hash" || fail "sleep strip hash"

if /usr/bin/find "$ROOT" -type l -print -quit | /usr/bin/grep -q .; then fail "no symlinks"; else pass "no symlinks"; fi
if /usr/bin/find "$ROOT" \( -name '*.app' -o -name '*.asar' -o -name '*.dmg' -o -name '*.pkg' -o -name '*.zip' -o -name '*.tar.gz' -o -name '*.log' -o -name '*.p12' -o -name '*.key' -o -name '*.pem' \) -print -quit | /usr/bin/grep -q .; then fail "no generated/private artifacts"; else pass "no generated/private artifacts"; fi
if /usr/bin/find "$ROOT" -type f -size +5M -print -quit | /usr/bin/grep -q .; then fail "no unexpected large files"; else pass "no unexpected large files"; fi

text_patterns='/'Users'/[A-Za-z0-9._-]+|aria''[.]huang|pet_[0-9a-f]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|Developer ID 'Application':|DEVELOPMENT_'TEAM'[[:space:]]*='
if /usr/bin/grep -RIE --exclude='repository-audit.sh' --exclude='spritesheet.webp' --exclude='sleep-strip.png' "$text_patterns" "$ROOT" >/dev/null 2>&1; then fail "private-state and credential scan"; else pass "private-state and credential scan"; fi

/usr/bin/grep -F '69818621da1c850a28ef9aa023126338d65ffc1b' "$ROOT/installer/scripts/fetch-dependencies.sh" >/dev/null && pass "enhancer commit pin" || fail "enhancer commit pin"
/usr/bin/grep -F 'bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057' "$ROOT/installer/scripts/fetch-dependencies.sh" >/dev/null && pass "Node archive pin" || fail "Node archive pin"
/usr/bin/grep -F '"version": "24.21.0"' "$ROOT/installer/Resources/metadata/node-provenance.json" >/dev/null && pass "Node provenance version" || fail "Node provenance version"
/usr/bin/grep -F '4.1.0' "$ROOT/installer/Sources/InstallerCore/Payload.swift" >/dev/null && pass "ASAR version pin" || fail "ASAR version pin"

print "RESULT passed=$passes failed=$failures total=$((passes + failures))"
(( failures == 0 ))
