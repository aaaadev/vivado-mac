#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$script_dir/container_exec.sh" vivado "$@"
