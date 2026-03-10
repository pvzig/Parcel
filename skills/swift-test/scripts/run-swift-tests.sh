#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if (($# > 0)); then
  case "$1" in
    --wasm-only)
      shift
      exec "$script_dir/run-wasm-tests.sh" "$@"
      ;;
    --host-only)
      shift
      exec "$script_dir/run-host-tests.sh" "$@"
      ;;
    --all)
      shift
      ;;
    *)
      exec "$script_dir/run-host-tests.sh" "$@"
      ;;
  esac
fi

"$script_dir/run-wasm-tests.sh"
"$script_dir/run-host-tests.sh"
