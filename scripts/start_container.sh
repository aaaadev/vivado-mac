#!/usr/bin/env bash
set -euo pipefail

source "$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

warning "start_container.sh is deprecated. GUI support was removed; forwarding to the CLI vivado wrapper."
exec "$REPO_ROOT/bin/vivado" "$@"
