#!/usr/bin/env bash
# Resolve source and destination tags for the shared mirror workflow.
set -euo pipefail

tag_url='https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags'

tag_exists() {
  local tag="$1" status
  status="$(curl --silent --show-error --location --retry 3 --max-time 30 \
    --output /dev/null --write-out '%{http_code}' "${tag_url}/${tag}/")" || exit 1
  case "${status}" in
    200) return 0 ;;
    404) return 1 ;;
    *) printf 'Docker Hub returned HTTP %s for %s\n' "${status}" "${tag}" >&2; exit 1 ;;
  esac
}

reference="${1:?usage: resolve-mirror-tags.sh <release-or-commit>}"
reference="${reference#v}"
build_cu129=false

if [[ "${reference}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  ref_type=release
  cu13_dest="v${reference}-ubuntu2404"
  cu13_source="${cu13_dest}"
  if ! tag_exists "${cu13_source}"; then
    cu13_source="v${reference}"
    if ! tag_exists "${cu13_source}"; then
      printf 'No CUDA 13 release tag found for v%s on Docker Hub\n' "${reference}" >&2
      exit 1
    fi
  fi

  cu129_tag="v${reference}-cu129-ubuntu2404"
  if ! tag_exists "${cu129_tag}"; then
    printf 'Docker Hub does not publish %s\n' "${cu129_tag}" >&2
    cu129_tag=''
    if [[ "${reference}" == '0.34.0' ]]; then
      build_cu129=true
    fi
  fi
elif [[ "${reference}" =~ ^[0-9a-f]{40}$ ]]; then
  ref_type=nightly
  cu13_source="nightly-${reference}"
  cu13_dest="${cu13_source}"
  cu129_tag="cu129-nightly-${reference}"
else
  echo 'vllm_ref must match X.Y.Z, vX.Y.Z, or a 40-character lowercase commit SHA' >&2
  exit 1
fi

matrix="$(jq -cn --arg cu13_source "${cu13_source}" --arg cu13_dest "${cu13_dest}" \
  --arg cu129 "${cu129_tag}" '{include: [
    {cuda: "cu13", source_tag: $cu13_source, dest_tag: $cu13_dest},
    (if $cu129 != "" then {cuda: "cu129", source_tag: $cu129, dest_tag: $cu129} else empty end)
  ]}')"
printf 'vllm_ref=%s\nref_type=%s\nmatrix=%s\nbuild_cu129=%s\n' \
  "${reference}" "${ref_type}" "${matrix}" "${build_cu129}"
