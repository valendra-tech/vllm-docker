#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mock_dir="$(mktemp -d)"
trap 'rm -rf "${mock_dir}"' EXIT

cat > "${mock_dir}/curl" <<'MOCK'
#!/usr/bin/env bash
set -eu
case "${!#}" in
  */tags/v0.32.0-ubuntu2404/ | */tags/v0.32.0-cu129-ubuntu2404/ | */tags/v0.33.0/ | */tags/v0.34.0/)
    printf '200'
    ;;
  */tags/v0.34.0-ubuntu2404/ | */tags/v0.34.0-cu129-ubuntu2404/ | */tags/v0.33.0-ubuntu2404/ | */tags/v0.33.0-cu129-ubuntu2404/ | */tags/v1.0.0-ubuntu2404/ | */tags/v1.0.0/)
    printf '404'
    ;;
  */tags/v2.0.0-ubuntu2404/ | */tags/v3.0.0-cu129-ubuntu2404/)
    printf '503'
    ;;
  */tags/v3.0.0-ubuntu2404/)
    printf '200'
    ;;
  *'&page=2')
    printf '%s\n' '{"next":null,"results":[{"name":"v0.34.0"},{"name":"v0.8.9-ubuntu2404"}]}'
    ;;
  */tags/?name=v\&*)
    printf '%s\n' '{"next":"https://hub.docker.com/v2/repositories/vllm/vllm-openai/tags/?name=v&page=2","results":[{"name":"v0.32.0-ubuntu2404"},{"name":"v0.35.0-rc1"},{"name":"v0.36.0-efa"}]}'
    ;;
  *) printf 'Unexpected Docker Hub request: %s\n' "${!#}" >&2; exit 1 ;;
esac
MOCK
chmod +x "${mock_dir}/curl"
export PATH="${mock_dir}:${PATH}"

resolve() { bash "${script_dir}/resolve-mirror-tags.sh" "$1"; }
matrix() { sed -n 's/^matrix=//p'; }

legacy="$(resolve v0.32.0)"
matrix <<< "${legacy}" | jq -e '
  .include | length == 2 and
  any(.[]; .cuda == "cu129" and .source_tag == "v0.32.0-cu129-ubuntu2404" and .dest_tag == .source_tag) and
  any(.[]; .cuda == "cu13" and .source_tag == "v0.32.0-ubuntu2404" and .dest_tag == .source_tag)
' > /dev/null
grep -Fxq 'build_cu129=false' <<< "${legacy}"

current="$(resolve 0.34.0)"
matrix <<< "${current}" | jq -e '
  .include | length == 1 and
  .[0].cuda == "cu13" and .[0].source_tag == "v0.34.0" and .[0].dest_tag == "v0.34.0-ubuntu2404"
' > /dev/null
grep -Fxq 'vllm_ref=0.34.0' <<< "${current}"
grep -Fxq 'build_cu129=true' <<< "${current}"
other="$(resolve 0.33.0)"
grep -Fxq 'build_cu129=false' <<< "${other}"

sha='0123456789abcdef0123456789abcdef01234567'
nightly="$(resolve "${sha}")"
matrix <<< "${nightly}" | jq -e --arg sha "${sha}" '
  .include | length == 2 and all(.[]; .source_tag == .dest_tag) and
  any(.[]; .source_tag == "cu129-nightly-" + $sha) and any(.[]; .source_tag == "nightly-" + $sha)
' > /dev/null
grep -Fxq 'build_cu129=false' <<< "${nightly}"

for ref in not-a-release 1.0.0 2.0.0 3.0.0; do
  if resolve "${ref}" > /dev/null 2>&1; then
    printf 'Expected resolution to fail for %s\n' "${ref}" >&2
    exit 1
  fi
done

latest="$(bash "${script_dir}/find-latest-vllm-ref.sh")"
[[ "${latest}" == '0.34.0' ]]
echo 'CUDA tag resolution and stable release discovery: OK'
