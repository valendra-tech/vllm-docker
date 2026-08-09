#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for test in "${script_dir}"/tests/test-*.sh; do
  echo "Running ${test}"
  bash "${test}"
done

echo "All tests passed"
