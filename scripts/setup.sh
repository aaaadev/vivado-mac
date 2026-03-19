#!/usr/bin/env bash
set -euo pipefail

source "$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

prompt_for_installer_path() {
    local installer_path

    printf 'Path to Vivado Linux installer (.bin): '
    read installer_path
    printf '%s\n' "$installer_path"
}

main() {
    local installer_path="${1:-}"
    local installer_dir
    local installer_name
    local docker_args=()

    require_docker
    ensure_host_dirs

    if host_vivado_install_present; then
        error "A Vivado installation already exists at $XILINX_INSTALL_DIR."
        exit 1
    fi

    if [[ -z "$installer_path" && -f "$INSTALLATION_BIN_LOG_PATH" ]]; then
        installer_path="$(<"$INSTALLATION_BIN_LOG_PATH")"
        info "Reusing installer path from $INSTALLATION_BIN_LOG_PATH"
    fi

    if [[ -z "$installer_path" ]]; then
        installer_path="$(prompt_for_installer_path)"
    fi

    installer_path="$(resolve_path "$installer_path")"
    if [[ ! -f "$installer_path" ]]; then
        error "Installer not found: $installer_path"
        exit 1
    fi

    printf '%s\n' "$installer_path" > "$INSTALLATION_BIN_LOG_PATH"

    step "Building Docker image $IMAGE_NAME"
    docker build --platform linux/amd64 -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile" "$REPO_ROOT"
    success "Docker image is ready."

    installer_dir="$(dirname "$installer_path")"
    installer_name="$(basename "$installer_path")"

    docker_tty_args
    docker_args+=(
        run
        --rm
        --platform
        linux/amd64
        "${DOCKER_TTY_ARGS[@]}"
        -v
        "$REPO_ROOT:$CONTAINER_TOOL_ROOT:ro"
        -v
        "$STATE_DIR:/state"
        -v
        "$XILINX_CONFIG_DIR:$CONTAINER_HOME/.Xilinx"
        -v
        "$installer_dir:/installer:ro"
        -e
        "VIVADO_MAC_STATE_DIR=/state"
        -e
        "VIVADO_INSTALL_ROOT=/state/Xilinx"
        -e
        "VIVADO_INSTALLER_PATH=/installer/$installer_name"
        "$IMAGE_NAME"
        "$CONTAINER_TOOL_ROOT/scripts/install.sh"
    )

    step "Starting Vivado installation"
    docker "${docker_args[@]}"
}

main "$@"
