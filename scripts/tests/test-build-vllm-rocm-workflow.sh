#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="${repo_dir}/.github/workflows/build-vllm-rocm.yml"

test -f "${workflow}"

grep -Fq 'workflow_dispatch:' "${workflow}"
if grep -Eq '^[[:space:]]+(push|pull_request|schedule):' "${workflow}"; then
  echo "ROCm publication must not have an automatic trigger" >&2
  exit 1
fi

grep -Fq 'v0.29.0-rocm72-ubuntu2204' "${workflow}"
grep -Fq '98dff2a81d747d1dba01a47f939f48c3526d4206' "${workflow}"
grep -Fq '160eeee04715f3090f22ae31e7ff547a6210fad876c1459525c0da2694e54199' "${workflow}"
grep -Fq 'rocm/vllm-dev:base@sha256:3cead535c32c11c59b222bbaa502076b9c737fb969b70b7bc9bb8ce77da5698e' "${workflow}"
grep -Fq 'rocm/vllm-dev@sha256:3cead535c32c11c59b222bbaa502076b9c737fb969b70b7bc9bb8ce77da5698e' "${workflow}"
grep -Fq 'rocm/dev-ubuntu-22.04:7.2.3-complete@sha256:b64aecbed6cc2d8227407899831d5c53fa8450d4db08f6a2400c29587ce15be9' "${workflow}"
grep -Fq 'PYTORCH_ROCM_ARCH: gfx942;gfx950' "${workflow}"
grep -Fq -- '--platform linux/amd64' "${workflow}"
grep -Fq -- '--tag "vllm:${TAG}"' "${workflow}"
grep -Fq -- '--output "type=oci,dest=' "${workflow}"
grep -Fq -- '--build-arg "REMOTE_VLLM=1"' "${workflow}"
grep -Fq -- '--build-arg "VLLM_BRANCH=${VLLM_COMMIT}"' "${workflow}"
grep -Fq -- '--build-arg "ARG_PYTORCH_ROCM_ARCH=${PYTORCH_ROCM_ARCH}"' "${workflow}"
grep -Fq 'IMMUTABLE_TAG: "1"' "${workflow}"
grep -Fq './scripts/push-r2.sh' "${workflow}"
grep -Fq 'skopeo inspect --no-tags --retry-times 3' "${workflow}"
grep -Fq 'refs/heads/main' "${workflow}"
grep -Fq 'local_digest' "${workflow}"
grep -Fq 'remote_digest' "${workflow}"
grep -Fq ': "${R2_ENDPOINT:?R2_ENDPOINT is required}"' "${workflow}"
grep -Fq ': "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID is required}"' "${workflow}"
grep -Fq ': "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY is required}"' "${workflow}"
grep -Fq 'R2_ENDPOINT: ${{ vars.R2_ENDPOINT }}' "${workflow}"
grep -Fq 'R2_ACCESS_KEY_ID: ${{ secrets.R2_ACCESS_KEY_ID }}' "${workflow}"
grep -Fq 'R2_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}' "${workflow}"
grep -Fq 'docker://${BASE_IMAGE_INSPECT}' "${workflow}"
if grep -Fq 'docker://${BASE_IMAGE})' "${workflow}"; then
  echo "skopeo must inspect the digest-only base image reference" >&2
  exit 1
fi

echo "build-vllm-rocm: manual, pinned, amd64, immutable publication: OK"
