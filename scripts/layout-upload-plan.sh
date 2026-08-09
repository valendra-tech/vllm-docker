#!/usr/bin/env bash
# Resolve an OCI layout into an R2 static registry upload plan.
# Usage: layout-upload-plan.sh <oci-layout-dir> <tag>
# Prints tab-separated lines to stdout:
#   BLOB|<path>|<s3-key>|<content-type>|<cache-control>
#   MANIFEST|<path>|<s3-key>|<content-type>|<cache-control>
#   TAG|<path>|<s3-key>|<content-type>|<cache-control>
# Requires: jq
set -euo pipefail

layout_dir="${1:?usage: layout-upload-plan.sh <oci-layout-dir> <tag>}"
tag="${2:?usage: layout-upload-plan.sh <oci-layout-dir> <tag>}"

blobs_dir="${layout_dir}/blobs/sha256"
index_file="${layout_dir}/index.json"

if [[ ! -f "${index_file}" ]]; then
  echo "index.json not found in ${layout_dir}" >&2
  exit 1
fi

manifest_seen=()
plan_blobs=()
plan_manifests=()
plan_tags=()

die() {
  echo "$*" >&2
  exit 1
}

contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

manifest_media_type() {
  local file="$1"
  jq -r '.mediaType // empty' "${file}"
}

resolve_manifest() {
  local digest="$1"
  local hex="${digest#sha256:}"
  local file="${blobs_dir}/${hex}"

  [[ -f "${file}" ]] || die "manifest blob missing: ${file}"

  local media_type
  media_type="$(manifest_media_type "${file}")"
  [[ -n "${media_type}" ]] || die "manifest ${digest} has no mediaType"

  case "${media_type}" in
    *"index.v1+json" | *"manifest.list.v2+json")
      local child
      while IFS= read -r child; do
        [[ -n "${child}" ]] && resolve_manifest "${child}"
      done < <(jq -r '.manifests[]?.digest // empty' "${file}")
      ;;
    *"manifest.v1+json" | *"image.manifest.v1+json" | *"image.manifest.v2+json" | *"manifest.v2+json") ;;
    *) die "unexpected manifest media type: ${media_type} (${digest})" ;;
  esac

  if ! contains "${digest}" ${manifest_seen[@]+"${manifest_seen[@]}"}; then
    manifest_seen+=("${digest}")
    plan_manifests+=("${file}|${digest}|${media_type}")
  fi
}

root_digest="$(jq -r --arg t "${tag}" \
  'first(.manifests[] | select(.annotations["org.opencontainers.image.ref.name"] == $t) | .digest)' \
  "${index_file}")"

if [[ -z "${root_digest}" ]]; then
  die "tag ${tag} not found in ${index_file}"
fi

resolve_manifest "${root_digest}"

root_hex="${root_digest#sha256:}"
root_file="${blobs_dir}/${root_hex}"
root_media_type="$(manifest_media_type "${root_file}")"
plan_tags+=("${root_file}|${tag}|${root_media_type}")

while IFS= read -r -d '' file; do
  hex="$(basename "${file}")"
  if ! contains "sha256:${hex}" ${manifest_seen[@]+"${manifest_seen[@]}"}; then
    plan_blobs+=("${file}|sha256:${hex}")
  fi
done < <(find "${blobs_dir}" -maxdepth 1 -type f -print0 | sort -z)

for entry in ${plan_blobs[@]+"${plan_blobs[@]}"}; do
  IFS='|' read -r local_path digest <<< "${entry}"
  printf 'BLOB\t%s\tv2/vllm/blobs/%s\tapplication/octet-stream\tpublic, max-age=31536000, immutable\n' \
    "${local_path}" "${digest}"
done

for entry in "${plan_manifests[@]}"; do
  IFS='|' read -r local_path digest media_type <<< "${entry}"
  printf 'MANIFEST\t%s\tv2/vllm/manifests/%s\t%s\tno-cache\n' \
    "${local_path}" "${digest}" "${media_type}"
done

for entry in "${plan_tags[@]}"; do
  IFS='|' read -r local_path digest media_type <<< "${entry}"
  printf 'TAG\t%s\tv2/vllm/manifests/%s\t%s\tno-cache\n' \
    "${local_path}" "${digest}" "${media_type}"
done
