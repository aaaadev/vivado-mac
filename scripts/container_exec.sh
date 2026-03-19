#!/usr/bin/env bash
set -euo pipefail

readonly XILINX_INSTALL_ROOT="${VIVADO_MAC_CONTAINER_XILINX_DIR:-/opt/Xilinx}"

find_vivado_dir() {
    local candidates=()
    local path

    while IFS= read -r path; do
        candidates+=("$path")
    done < <(compgen -G "$XILINX_INSTALL_ROOT/*/Vivado" || true)

    while IFS= read -r path; do
        candidates+=("$path")
    done < <(compgen -G "$XILINX_INSTALL_ROOT/Vivado/*" || true)

    if [[ "${#candidates[@]}" -eq 0 ]]; then
        return 1
    fi

    printf '%s\n' "${candidates[@]}" | sort -V | tail -n 1
}

main() {
    local tool="${1:?missing tool name}"
    local vivado_dir
    shift

    vivado_dir="$(find_vivado_dir)" || {
        printf 'Vivado installation not found under %s\n' "$XILINX_INSTALL_ROOT" >&2
        exit 1
    }

    export PATH="$HOME/.local/bin:$PATH"
    # shellcheck disable=SC1090
    source "$vivado_dir/settings64.sh"

    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Tool %s is not available in the container\n' "$tool" >&2
        exit 1
    fi

    exec "$tool" "$@"
}

main "$@"
