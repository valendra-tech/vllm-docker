#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="${repo_dir}/.github/workflows/build-vllm-cu129.yml"

grep -Fxq '    runs-on: [self-hosted, linux, x64]' "${workflow}" || {
  echo "CUDA 12.9 must run on a self-hosted Linux x64 runner" >&2
  exit 1
}
grep -Fxq '  workflow_dispatch:' "${workflow}"
grep -Fxq '  workflow_call:' "${workflow}"
grep -Fq "github.repository == 'valendra-tech/vllm-docker'" "${workflow}"
grep -Fq "github.ref == 'refs/heads/main'" "${workflow}"
grep -Fq "github.event_name == 'workflow_dispatch'" "${workflow}"
grep -Fq 'bash scripts/check-cu129-runner.sh' "${workflow}"
grep -Fq 'max-parallelism = 1' "${workflow}"
grep -Fq -- "--build-arg \"max_jobs=\${CUDA_MAX_JOBS}\"" "${workflow}"
if grep -Eq '^[[:space:]]+(push|pull_request(_target)?|schedule):|^[[:space:]]+sudo |docker system prune' "${workflow}"; then
  echo "CUDA 12.9 must not run automatically or modify the host" >&2
  exit 1
fi

fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT
mkdir "${fixture}/bin"
cat > "${fixture}/bin/host-tool" <<'MOCK'
#!/usr/bin/env bash
set -eu
case "${0##*/}" in
  aws) echo 'aws-cli/2.34.0' ;;
  docker) echo '/fixture/docker-root' ;;
  df)
    kib="${DISK_KIB:-120000000}"
    if [[ "${!#}" == '/fixture/docker-root' ]]; then
      kib="${DOCKER_DISK_KIB:-${kib}}"
    fi
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/test 150000000 0 %s 0%% /fixture\n' "${kib}"
    ;;
  free)
    printf '              total used free shared buff/cache available\nMem:          65536    0    0      0          0     %s\n' "${RAM_MIB:-60000}"
    ;;
  nproc) printf '%s\n' "${CPUS:-16}" ;;
  skopeo) ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "${fixture}/bin/host-tool"
for tool in aws docker df free nproc skopeo; do
  ln -s host-tool "${fixture}/bin/${tool}"
done
export PATH="${fixture}/bin:${PATH}"
export RUNNER_TEMP="${fixture}" GITHUB_OUTPUT="${fixture}/outputs"

check_jobs() {
  local expected="$1"
  shift
  : > "${GITHUB_OUTPUT}"
  env "$@" bash "${repo_dir}/scripts/check-cu129-runner.sh" > /dev/null
  [[ "$(cat "${GITHUB_OUTPUT}")" == "max_jobs=${expected}" ]]
}

check_failure() {
  local expected="$1" result
  shift
  : > "${GITHUB_OUTPUT}"
  if result="$(env "$@" bash "${repo_dir}/scripts/check-cu129-runner.sh" 2>&1)"; then
    echo "Expected the CUDA build preflight to fail" >&2
    exit 1
  fi
  [[ "${result}" == *"${expected}"* ]]
  [[ ! -s "${GITHUB_OUTPUT}" ]]
}

check_jobs 16 CPUS=24
check_jobs 8 CPUS=8
check_jobs 10 RAM_MIB=35840
check_failure 'at least 8 logical CPUs and 28 GiB' CPUS=4
check_failure 'at least 8 logical CPUs and 28 GiB' RAM_MIB=16000
check_failure 'at least 100 GiB free' DISK_KIB=30000000
check_failure 'at least 100 GiB free' DOCKER_DISK_KIB=30000000
echo 'CUDA 12.9 runner routing and capacity checks: OK'
