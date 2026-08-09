#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plan_script="${script_dir}/../layout-upload-plan.sh"

layout_dir="$(mktemp -d)"
trap 'rm -rf "${layout_dir}"' EXIT

blobs="${layout_dir}/blobs/sha256"
mkdir -p "${blobs}"

cat > "${layout_dir}/index.json" <<'EOF'
{
  "schemaVersion": 2,
  "manifests": [
    {
      "mediaType": "application/vnd.docker.distribution.manifest.list.v2+json",
      "digest": "sha256:aaa",
      "size": 1,
      "annotations": {
        "org.opencontainers.image.ref.name": "test-tag"
      }
    }
  ]
}
EOF

cat > "${blobs}/aaa" <<'EOF'
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.docker.distribution.manifest.list.v2+json",
  "manifests": [
    {"mediaType": "application/vnd.docker.distribution.manifest.v2+json", "digest": "sha256:bbb", "size": 1},
    {"mediaType": "application/vnd.docker.distribution.manifest.v2+json", "digest": "sha256:eee", "size": 1}
  ]
}
EOF

cat > "${blobs}/bbb" <<'EOF'
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
  "config": {"mediaType": "application/vnd.docker.container.image.v1+json", "digest": "sha256:ccc", "size": 1},
  "layers": [{"mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip", "digest": "sha256:ddd", "size": 1}]
}
EOF

cat > "${blobs}/eee" <<'EOF'
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
  "config": {"mediaType": "application/vnd.docker.container.image.v1+json", "digest": "sha256:ccc", "size": 1},
  "layers": [{"mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip", "digest": "sha256:fff", "size": 1}]
}
EOF

echo "not json" > "${blobs}/ccc"
echo "not json" > "${blobs}/ddd"
echo "not json" > "${blobs}/fff"

expected="${layout_dir}/expected.txt"
cat > "${expected}" <<EOF
BLOB	${blobs}/ccc	v2/vllm/blobs/sha256:ccc	application/octet-stream	public, max-age=31536000, immutable
BLOB	${blobs}/ddd	v2/vllm/blobs/sha256:ddd	application/octet-stream	public, max-age=31536000, immutable
BLOB	${blobs}/fff	v2/vllm/blobs/sha256:fff	application/octet-stream	public, max-age=31536000, immutable
MANIFEST	${blobs}/bbb	v2/vllm/manifests/sha256:bbb	application/vnd.docker.distribution.manifest.v2+json	no-cache
MANIFEST	${blobs}/eee	v2/vllm/manifests/sha256:eee	application/vnd.docker.distribution.manifest.v2+json	no-cache
MANIFEST	${blobs}/aaa	v2/vllm/manifests/sha256:aaa	application/vnd.docker.distribution.manifest.list.v2+json	no-cache
TAG	${blobs}/aaa	v2/vllm/manifests/test-tag	application/vnd.docker.distribution.manifest.list.v2+json	no-cache
EOF

diff "${expected}" <("${plan_script}" "${layout_dir}" "test-tag")

empty_dir="$(mktemp -d)"
trap 'rm -rf "${layout_dir}" "${empty_dir}"' EXIT

empty_blobs="${empty_dir}/blobs/sha256"
mkdir -p "${empty_blobs}"

cat > "${empty_dir}/index.json" <<'EOF'
{
  "schemaVersion": 2,
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:111",
      "size": 1,
      "annotations": {
        "org.opencontainers.image.ref.name": "empty-tag"
      }
    }
  ]
}
EOF

cat > "${empty_blobs}/111" <<'EOF'
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json"
}
EOF

expected_empty="${empty_dir}/expected.txt"
cat > "${expected_empty}" <<EOF
MANIFEST	${empty_blobs}/111	v2/vllm/manifests/sha256:111	application/vnd.oci.image.manifest.v1+json	no-cache
TAG	${empty_blobs}/111	v2/vllm/manifests/empty-tag	application/vnd.oci.image.manifest.v1+json	no-cache
EOF

diff "${expected_empty}" <("${plan_script}" "${empty_dir}" "empty-tag")
echo "layout-upload-plan: OK"
