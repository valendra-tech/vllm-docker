#!/usr/bin/env bash
set -euo pipefail

workflow="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.github/workflows/mirror-vllm-daily.yml"
reusable_workflow="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.github/workflows/mirror-vllm-reusable.yml"

awk '
  BEGIN { found = 0 }
  $0 ~ /^[[:space:]]*uses: \.\/\.github\/workflows\/mirror-vllm-reusable\.yml[[:space:]]*$/ { in_call = 1; next }
  in_call && $0 ~ /^[[:space:]]*secrets: inherit[[:space:]]*$/ { found = 1; exit }
  in_call && $0 ~ /^  [^ ]/ { exit }
  END { exit !found }
' "${workflow}"
echo "mirror-vllm-daily: reusable workflow secrets inherited: OK"

grep -Fq 'R2_ACCESS_KEY_ID: ${{ secrets.R2_ACCESS_KEY_ID }}' "${reusable_workflow}"
grep -Fq 'R2_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}' "${reusable_workflow}"
if grep -Fq 'AWS_ACCESS_KEY_ID: ${{ secrets.R2_ACCESS_KEY_ID }}' "${reusable_workflow}" || \
  grep -Fq 'AWS_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}' "${reusable_workflow}"; then
  echo "reusable workflow must expose R2 credentials with their R2_* names" >&2
  exit 1
fi
echo "mirror-vllm-reusable: R2 credential names match uploader: OK"
