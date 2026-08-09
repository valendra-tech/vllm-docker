#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
push_script="${script_dir}/../push-r2.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

layout_dir="${work}/layout"
blobs="${layout_dir}/blobs/sha256"
mkdir -p "${blobs}"

cat > "${layout_dir}/index.json" <<'EOF'
{
  "schemaVersion": 2,
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.index.v1+json",
      "digest": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
      "size": 1,
      "annotations": {"org.opencontainers.image.ref.name": "test-tag"}
    }
  ]
}
EOF

cat > "${blobs}/1111111111111111111111111111111111111111111111111111111111111111" <<'EOF'
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:2222222222222222222222222222222222222222222222222222222222222222",
      "size": 1
    }
  ]
}
EOF

cat > "${blobs}/2222222222222222222222222222222222222222222222222222222222222222" <<'EOF'
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": {"mediaType": "application/vnd.oci.image.config.v1+json", "digest": "sha256:3333333333333333333333333333333333333333333333333333333333333333", "size": 1},
  "layers": []
}
EOF

echo "config" > "${blobs}/3333333333333333333333333333333333333333333333333333333333333333"

# Mock AWS CLI: records every invocation, behaves as a success.
cat > "${work}/aws" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >> "${AWS_MOCK_LOG}"
exit 0
MOCK
chmod +x "${work}/aws"

export AWS_MOCK_LOG="${work}/calls.log"
export R2_ENDPOINT="https://account.r2.cloudflarestorage.com"
export R2_BUCKET="public-docker-registry"
export AWS_ACCESS_KEY_ID="test-id"
export AWS_SECRET_ACCESS_KEY="test-secret"
export PING_FILE="${work}/ping"
export PATH="${work}:${PATH}"

"${push_script}" "${layout_dir}" "test-tag"

expected="${work}/expected.txt"
cat > "${expected}" <<EOF
s3
cp
${work}/ping
s3://public-docker-registry/v2
--endpoint-url
https://account.r2.cloudflarestorage.com
--region
auto
--content-type
application/json
s3
cp
${blobs}/3333333333333333333333333333333333333333333333333333333333333333
s3://public-docker-registry/v2/vllm/blobs/sha256:3333333333333333333333333333333333333333333333333333333333333333
--endpoint-url
https://account.r2.cloudflarestorage.com
--region
auto
--content-type
application/octet-stream
--cache-control
public, max-age=31536000, immutable
s3
cp
${blobs}/2222222222222222222222222222222222222222222222222222222222222222
s3://public-docker-registry/v2/vllm/manifests/sha256:2222222222222222222222222222222222222222222222222222222222222222
--endpoint-url
https://account.r2.cloudflarestorage.com
--region
auto
--content-type
application/vnd.oci.image.manifest.v1+json
--cache-control
no-cache
s3
cp
${blobs}/1111111111111111111111111111111111111111111111111111111111111111
s3://public-docker-registry/v2/vllm/manifests/sha256:1111111111111111111111111111111111111111111111111111111111111111
--endpoint-url
https://account.r2.cloudflarestorage.com
--region
auto
--content-type
application/vnd.oci.image.index.v1+json
--cache-control
no-cache
s3
cp
${blobs}/1111111111111111111111111111111111111111111111111111111111111111
s3://public-docker-registry/v2/vllm/manifests/test-tag
--endpoint-url
https://account.r2.cloudflarestorage.com
--region
auto
--content-type
application/vnd.oci.image.index.v1+json
--cache-control
no-cache
s3
cp
${work}/ping
s3://public-docker-registry/v2
--endpoint-url
https://account.r2.cloudflarestorage.com
--region
auto
--content-type
application/json
EOF

diff "${expected}" "${AWS_MOCK_LOG}"

test ! -f "${blobs}/3333333333333333333333333333333333333333333333333333333333333333" \
  && echo "push-r2: blob deleted after upload: OK"
test -f "${blobs}/1111111111111111111111111111111111111111111111111111111111111111" \
  && echo "push-r2: manifest kept after upload: OK"

echo "push-r2: OK"

# --- Failure case 1: aws fails on the second upload; script must exit non-zero
# --- and keep the blob file (never delete an unuploaded blob).

fail_layout="${work}/fail-layout"
fail_blobs="${fail_layout}/blobs/sha256"
mkdir -p "${fail_blobs}"

cat > "${fail_layout}/index.json" <<'EOF'
{
  "schemaVersion": 2,
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:4444444444444444444444444444444444444444444444444444444444444444",
      "size": 1,
      "annotations": {"org.opencontainers.image.ref.name": "fail-tag"}
    }
  ]
}
EOF

cat > "${fail_blobs}/4444444444444444444444444444444444444444444444444444444444444444" <<'EOF'
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": {"mediaType": "application/vnd.oci.image.config.v1+json", "digest": "sha256:5555555555555555555555555555555555555555555555555555555555555555", "size": 1},
  "layers": []
}
EOF

echo "config" > "${fail_blobs}/5555555555555555555555555555555555555555555555555555555555555555"

mkdir -p "${work}/fail-bin"
cat > "${work}/fail-bin/aws" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >> "${AWS_MOCK_LOG}"
count="$(grep -c '^cp$' "${AWS_MOCK_LOG}")"
if [[ "${count}" -eq 2 ]]; then
  exit 1
fi
exit 0
MOCK
chmod +x "${work}/fail-bin/aws"

export AWS_MOCK_LOG="${work}/fail-calls.log"
export PING_FILE="${work}/fail-ping"
export PATH="${work}/fail-bin:${PATH}"

if ! "${push_script}" "${fail_layout}" "fail-tag" >/dev/null 2>&1; then
  echo "push-r2: fails on upload error: OK"
else
  echo "push-r2: expected failure on upload error" >&2
  exit 1
fi

test -f "${fail_blobs}/5555555555555555555555555555555555555555555555555555555555555555" \
  && echo "push-r2: failed blob retained: OK"
