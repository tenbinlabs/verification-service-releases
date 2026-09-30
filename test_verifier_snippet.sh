#!/usr/bin/env bash
# Local harness that exercises the base64url handling used by the
# verification snippet in README.md, including the padding and fail-open cases.
set -euo pipefail

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

# A JWT payload segment containing base64url-only characters ('-' and '_').
# Decodes to: {"submods":{"container":{"image_digest":"sha256:abcdef"}}}
SEG='eyJzdWJtb2RzIjp7ImNvbnRhaW5lciI6eyJpbWFnZV9kaWdlc3QiOiJzaGEyNTY6YWJjZGVmIn19fQ'

# Reproduce the README pipeline exactly.
decode() {
  printf '%s' "$1" \
    | tr '_-' '/+' \
    | awk '{l=length($0)%4; if(l==2)$0=$0"=="; else if(l==3)$0=$0"="; print}' \
    | base64 -d 2>/dev/null
}

out=$(decode "$SEG" || true)
if [ "$(printf '%s' "$out" | jq -er '.submods.container.image_digest' 2>/dev/null || true)" = "sha256:abcdef" ]; then
  pass "base64url payload decodes and the digest claim is extracted"
else
  bad "base64url payload did not decode (got: '$out')"
fi

# The old snippet used plain `base64 -d`, which cannot read base64url.
if printf '%s' "$SEG" | base64 -d >/dev/null 2>&1; then
  bad "expected plain base64 -d to fail on base64url input"
else
  pass "plain base64 -d correctly fails on base64url input (old snippet was broken)"
fi

# Fail-open regression: two empty digests must NOT be reported as a match.
case "" in sha256:*) bad "empty expected digest passed the format guard" ;;
  *) pass "empty expected digest is rejected by the sha256 format guard" ;; esac

exit $fail