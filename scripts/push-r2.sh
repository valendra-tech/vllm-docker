#!/usr/bin/env bash
# Upload an OCI layout to the R2 static registry.
# Usage: push-r2.sh <oci-layout-dir> <tag>
# Requires: AWS CLI, and env vars R2_ENDPOINT, R2_BUCKET,
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY.
set -euo pipefail

layout_dir="${1:?usage: push-r2.sh <oci-layout-dir> <tag>}"
tag="${2:?usage: push-r2.sh <oci-layout-dir> <tag>}"

: "${R2_ENDPOINT:?R2_ENDPOINT is required}"
: "${R2_BUCKET:?R2_BUCKET is required}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID is required}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY is required}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ping_file="${PING_FILE:-$(mktemp)}"
trap '[[ -z "${PING_FILE:-}" ]] && rm -f "${ping_file}"' EXIT

ensure_ping() {
  : > "${ping_file}"
  aws s3 cp "${ping_file}" "s3://${R2_BUCKET}/v2" \
    --endpoint-url "${R2_ENDPOINT}" \
    --region auto \
    --content-type application/json
}

ensure_ping

"${script_dir}/layout-upload-plan.sh" "${layout_dir}" "${tag}" |
while IFS=$'\t' read -r kind local_path s3_key content_type cache_control; do
  case "${kind}" in
    BLOB)
      aws s3 cp "${local_path}" "s3://${R2_BUCKET}/${s3_key}" \
        --endpoint-url "${R2_ENDPOINT}" \
        --region auto \
        --content-type "${content_type}" \
        --cache-control "${cache_control}"
      rm -f "${local_path}"
      ;;
    MANIFEST | TAG)
      aws s3 cp "${local_path}" "s3://${R2_BUCKET}/${s3_key}" \
        --endpoint-url "${R2_ENDPOINT}" \
        --region auto \
        --content-type "${content_type}" \
        --cache-control "${cache_control}"
      ;;
    *)
      echo "unknown plan kind: ${kind}" >&2
      exit 1
      ;;
  esac
done

ensure_ping
