#!/usr/bin/env bash
# Print the newest stable Docker Hub CUDA release using either tag scheme.
set -euo pipefail

tags_file="$(mktemp)"
trap 'rm -f "${tags_file}"' EXIT
next_url='https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/?name=v&page_size=100&ordering=last_updated'

while [[ -n "${next_url}" ]]; do
  page="$(curl --fail --silent --show-error --location --retry 3 --max-time 30 "${next_url}")"
  jq -r '.results[].name' <<< "${page}" >> "${tags_file}"
  next_url="$(jq -r '.next // empty' <<< "${page}")"
done

latest="$(sed -En 's/^v([0-9]+\.[0-9]+\.[0-9]+)(-ubuntu2404)?$/\1/p' "${tags_file}" \
  | sort -t. -k1,1n -k2,2n -k3,3n -u | tail -n 1)"
if [[ -z "${latest}" ]]; then
  echo 'No stable vLLM CUDA release was found on Docker Hub' >&2
  exit 1
fi
printf '%s\n' "${latest}"
