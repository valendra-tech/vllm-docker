#!/usr/bin/env bash
set -euo pipefail

workflow="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.github/workflows/mirror-vllm-daily.yml"

grep -q '^    secrets: inherit$' "${workflow}"
echo "mirror-vllm-daily: reusable workflow secrets inherited: OK"
