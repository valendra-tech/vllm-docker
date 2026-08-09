#!/usr/bin/env bash
# Upload an OCI layout to the R2 static registry.
# Usage: push-r2.sh <oci-layout-dir> <tag>
# Consumes the tab-separated plan from layout-upload-plan.sh and uploads each
# object with the AWS CLI. Deletes uploaded blob files from the layout
# directory (runner disk); manifest/tag files are kept.
# Requires: AWS CLI, and env vars R2_ENDPOINT, R2_BUCKET,
# R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY.
set -euo pipefail

layout_dir="${1:?usage: push-r2.sh <oci-layout-dir> <tag>}"
tag="${2:?usage: push-r2.sh <oci-layout-dir> <tag>}"

: "${R2_ENDPOINT:?R2_ENDPOINT is required}"
: "${R2_BUCKET:?R2_BUCKET is required}"
: "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID is required}"
: "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY is required}"

export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ping_file="${PING_FILE:-$(mktemp)}"
trap '[[ -z "${PING_FILE:-}" ]] && rm -f "${ping_file}"' EXIT

upload() {
  local local_path="$1"
  local s3_key="$2"
  local content_type="$3"
  local cache_control="$4"
  if ! aws s3 cp "${local_path}" "s3://${R2_BUCKET}/${s3_key}" \
    --endpoint-url "${R2_ENDPOINT}" \
    --region auto \
    --no-progress \
    --content-type "${content_type}" \
    --cache-control "${cache_control}"; then
    echo "upload failed: s3://${R2_BUCKET}/${s3_key}" >&2
    exit 1
  fi
}

object_exists() {
  aws s3api head-object \
    --bucket "${R2_BUCKET}" \
    --key "$1" \
    --endpoint-url "${R2_ENDPOINT}" \
    --region auto \
    >/dev/null 2>&1
}

upload_blob() {
  local local_path="$1"
  local s3_key="$2"
  local content_type="$3"
  local cache_control="$4"

  if object_exists "${s3_key}"; then
    echo "Skipping existing blob: s3://${R2_BUCKET}/${s3_key}" >&2
  else
    upload "${local_path}" "${s3_key}" "${content_type}" "${cache_control}"
  fi

  rm -f "${local_path}"
}

ensure_ping() {
  : > "${ping_file}"
  if ! aws s3api put-object \
    --bucket "${R2_BUCKET}" \
    --key "v2/" \
    --body "${ping_file}" \
    --endpoint-url "${R2_ENDPOINT}" \
    --region auto \
    --content-type application/json \
    >/dev/null; then
    echo "upload failed: s3://${R2_BUCKET}/v2/" >&2
    exit 1
  fi
}

ensure_ping

"${script_dir}/layout-upload-plan.sh" "${layout_dir}" "${tag}" |
while IFS=$'\t' read -r kind local_path s3_key content_type cache_control; do
  case "${kind}" in
    BLOB)
      upload_blob "${local_path}" "${s3_key}" "${content_type}" "${cache_control}"
      ;;
    MANIFEST | TAG)
      upload "${local_path}" "${s3_key}" "${content_type}" "${cache_control}"
      ;;
    *)
      echo "unknown plan kind: ${kind}" >&2
      exit 1
      ;;
  esac
done

ensure_ping
