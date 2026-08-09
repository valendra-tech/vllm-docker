#!/usr/bin/env bash
set -euo pipefail

workflow="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.github/workflows/mirror-vllm-daily.yml"

awk '
  BEGIN { found = 0 }
  $0 == "    uses: ./.github/workflows/mirror-vllm-reusable.yml" { in_call = 1; next }
  in_call && $0 == "    secrets: inherit" { found = 1; exit }
  in_call && $0 ~ /^  [^ ]/ { exit }
  END { exit !found }
' "${workflow}"
echo "mirror-vllm-daily: reusable workflow secrets inherited: OK"
