#!/usr/bin/env bash
# Check the dedicated Linux x64 build runner without changing the host.
set -euo pipefail

die() {
  printf '::error::%s\n' "$*" >&2
  exit 1
}

for tool in aws curl df docker free git jq nproc skopeo; do
  command -v "${tool}" >/dev/null || die "Install ${tool} on the CUDA 12.9 runner."
done
aws_version="$(aws --version 2>&1)"
[[ "${aws_version}" == aws-cli/2.* ]] || die 'Install AWS CLI v2 on the CUDA 12.9 runner.'

docker_root="$(docker info --format '{{.DockerRootDir}}')" || die 'The runner cannot access its Docker daemon.'
[[ -n "${docker_root}" ]] || die 'Docker did not report its storage directory.'
for path in "${docker_root}" "${RUNNER_TEMP:?RUNNER_TEMP is required}"; do
  available_kib="$(df -Pk -- "${path}" | awk 'NR == 2 {print $4}')" ||
    die "Could not check the local filesystem for ${path}."
  [[ "${available_kib}" =~ ^[0-9]+$ ]] || die "Could not determine available disk space for ${path}."
  printf 'Available disk at %s: %s GiB\n' "${path}" "$((available_kib / 1024 / 1024))"
  (( available_kib >= 100 * 1024 * 1024 )) || die "The CUDA build needs at least 100 GiB free at ${path}."
done

cpus="$(nproc)"
ram_mib="$(free -m | awk '$1 == "Mem:" {print $7}')"
[[ "${cpus}" =~ ^[1-9][0-9]*$ && "${ram_mib}" =~ ^[0-9]+$ ]] || die 'Could not determine available CPU or RAM.'
printf 'Available logical CPUs: %s; available RAM: %s MiB\n' "${cpus}" "${ram_mib}"

# Budget 3.5 GiB per job. vLLM further divides its Ninja jobs by nvcc_threads=2.
max_jobs=$(( ram_mib / 3584 ))
if (( max_jobs > cpus )); then
  max_jobs="${cpus}"
fi
if (( max_jobs > 16 )); then
  max_jobs=16
fi
(( max_jobs >= 8 )) || die 'The CUDA build needs at least 8 logical CPUs and 28 GiB of available RAM.'

printf 'CUDA build max_jobs=%s, nvcc_threads=2\n' "${max_jobs}"
printf 'max_jobs=%s\n' "${max_jobs}" >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
