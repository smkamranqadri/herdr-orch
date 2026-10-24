#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
for t in "$here"/test-*.sh; do
  echo "== $(basename "$t")"
  "$t"
done
