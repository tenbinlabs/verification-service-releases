# verification-service — published builds

Expected build hashes for the Tenbin proof-of-reserves verification service.

Every deployed build of `verification-service` gets a release here recording the
**container image digest** of the binary running inside the TEE. Verifiers use
it to answer one question: *is the service answering me the audited build?*

This repository is public and holds no source — only digests, which are hashes
whose purpose is to be independently checkable. The source repository
(`tenbinlabs/verification-service`) is private; contact Tenbin for audit access.

## Fetching the expected digest

Each release attaches a `build.json`. Latest deployed build, no credentials
required:

```bash
curl -sL https://github.com/tenbinlabs/verification-service-releases/releases/latest/download/build.json
```

```json
{
  "release_tag": "deploy-<short-commit>",
  "source_repo": "tenbinlabs/verification-service",
  "commit": "<full source commit sha>",
  "short_commit": "<short sha>",
  "image": "<artifact registry image:tag>",
  "image_digest": "sha256:<64 hex>",
  "endpoint": "https://verify.tenbin.xyz"
}
```

Via the API:

```bash
curl -s https://api.github.com/repos/tenbinlabs/verification-service-releases/releases/latest \
  | jq -r .tag_name
```

## Using it

Compare `image_digest` against the `submods.container.image_digest` claim in
the Confidential Space attestation JWT returned by `/attest`:

```bash
# `set -euo pipefail` stops the script on any failure instead of letting an
# empty variable flow onward. `curl -f` and `jq -e` make a failed fetch or a
# missing field a hard error rather than an empty string.
set -euo pipefail

EXPECTED=$(curl -fsSL \
  https://github.com/tenbinlabs/verification-service-releases/releases/latest/download/build.json \
  | jq -er '.image_digest')

# The JWT payload is base64url ('-' and '_' instead of '+' and '/') and is
# unpadded, so it must be translated and re-padded before `base64 -d` can read
# it. Plain `base64 -d` fails on a real JWT and would yield an empty ACTUAL.
PAYLOAD=$(jq -r '.attestation.jwt' attest.json | cut -d. -f2 \
  | tr '_-' '/+' \
  | awk '{l=length($0)%4; if(l==2)$0=$0"=="; else if(l==3)$0=$0"="; print}')

# jq -e exits non-zero if the claim is missing, so an absent or malformed
# attestation cannot be mistaken for a passing check.
ACTUAL=$(printf '%s' "$PAYLOAD" | base64 -d 2>/dev/null | jq -er '.submods.container.image_digest')

# Both digests must be well-formed sha256 values before they are compared.
# Without this, two empty strings compare equal and the check passes vacuously.
case "$EXPECTED" in sha256:*) ;; *) echo "ERROR: malformed expected digest" >&2; exit 1 ;; esac
case "$ACTUAL"   in sha256:*) ;; *) echo "ERROR: malformed attestation digest" >&2; exit 1 ;; esac

[ "$EXPECTED" = "$ACTUAL" ] && echo "build hash OK" || { echo "MISMATCH - do not trust the response"; exit 1; }
```

A match shows the binary that produced the response was built from the
commit named in `build.json` and is running inside an attested TEE.

This is one step of the full procedure — the digest check is meaningless
unless the JWT signature, issuer, audience, expiry, and nonce binding are
validated too. Tenbin provides the complete verifier reference
(`docs/VERIFIER.md`) alongside repository access.

## Release naming

Releases are tagged `deploy-<short-commit>`, one per deployed build, published
by the deployment pipeline only after the build is live and answering
`/healthz`. Tags in this repository do not point at source commits — the source
lives in a separate private repository, and the commit is recorded in
`build.json`.
