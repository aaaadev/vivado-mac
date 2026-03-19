#!/usr/bin/env bash

if [[ -n "${VIVADO_MAC_LIB_SH:-}" ]]; then
    return 0
fi
readonly VIVADO_MAC_LIB_SH=1

readonly SCRIPT_DIR="$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly GREY='\033[0;90m'
readonly NC='\033[0m'

readonly IMAGE_NAME="${VIVADO_MAC_IMAGE_NAME:-yoketh/vivado-mac:local}"
readonly STATE_DIR="${VIVADO_MAC_STATE_DIR:-$HOME/.vivado-mac}"
readonly XILINX_INSTALL_DIR="${VIVADO_MAC_XILINX_DIR:-$STATE_DIR/Xilinx}"
readonly XILINX_CONFIG_DIR="${VIVADO_MAC_CONFIG_DIR:-$HOME/.Xilinx}"
readonly INSTALLATION_BIN_LOG_PATH="${STATE_DIR}/installation_location.txt"

readonly CONTAINER_HOME="/home/user"
readonly CONTAINER_TOOL_ROOT="/opt/vivado-mac"
readonly CONTAINER_PROJECT_ROOT="/workspace"
readonly CONTAINER_XILINX_ROOT="/opt/Xilinx"

error() {
    printf '%b\n' "${RED}[ERROR] $*${NC}" >&2
}

success() {
    printf '%b\n' "${GREEN}[SUCCESS] $*${NC}"
}

warning() {
    printf '%b\n' "${YELLOW}[WARNING] $*${NC}"
}

info() {
    printf '%b\n' "${BLUE}[INFO] $*${NC}"
}

debug() {
    printf '%b\n' "${GREY}[DEBUG] $*${NC}"
}

step() {
    printf '%b\n' "${CYAN}[STEP] $*${NC}"
}

important() {
    printf '%b\n' "${PURPLE}[IMPORTANT] $*${NC}"
}

ensure_host_dirs() {
    mkdir -p "$STATE_DIR" "$XILINX_INSTALL_DIR" "$XILINX_CONFIG_DIR"
}

require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        error "docker is required but was not found in PATH."
        exit 1
    fi
}

docker_image_exists() {
    docker image inspect "$IMAGE_NAME" >/dev/null 2>&1
}

resolve_path() {
    local input_path="$1"
    local abs_dir
    local base_name

    if [[ -d "$input_path" ]]; then
        (
            cd -- "$input_path"
            pwd -P
        )
        return 0
    fi

    abs_dir="$(
        cd -- "$(dirname "$input_path")"
        pwd -P
    )"
    base_name="$(basename "$input_path")"
    printf '%s/%s\n' "$abs_dir" "$base_name"
}

current_host_dir() {
    pwd -P
}

host_project_root() {
    local git_root

    if git_root="$(git -C "$(current_host_dir)" rev-parse --show-toplevel 2>/dev/null)"; then
        resolve_path "$git_root"
    else
        current_host_dir
    fi
}

host_relative_subdir() {
    local project_root="$1"
    local working_dir="$2"

    if [[ "$working_dir" == "$project_root" ]]; then
        printf '.\n'
        return 0
    fi

    case "$working_dir" in
        "$project_root"/*)
            printf '%s\n' "${working_dir#$project_root/}"
            ;;
        *)
            error "working directory is outside the detected project root"
            return 1
            ;;
    esac
}

container_workdir_for_pwd() {
    local project_root="$1"
    local working_dir="$2"
    local relative_subdir

    relative_subdir="$(host_relative_subdir "$project_root" "$working_dir")"
    if [[ "$relative_subdir" == "." ]]; then
        printf '%s\n' "$CONTAINER_PROJECT_ROOT"
    else
        printf '%s/%s\n' "$CONTAINER_PROJECT_ROOT" "$relative_subdir"
    fi
}

docker_tty_args() {
    DOCKER_TTY_ARGS=(-i)
    if [[ -t 1 ]]; then
        DOCKER_TTY_ARGS+=(-t)
    fi
}

host_vivado_install_present() {
    [[ -d "$XILINX_INSTALL_DIR" ]] && find "$XILINX_INSTALL_DIR" -mindepth 3 -maxdepth 4 -type f -name vivado -path '*/bin/vivado' | grep -q .
}

run_host_tool() {
    local tool="$1"
    local project_root
    local working_dir
    local container_workdir
    local docker_args=()
    shift

    require_docker
    ensure_host_dirs

    if ! docker_image_exists; then
        error "Docker image $IMAGE_NAME was not found. Run $REPO_ROOT/scripts/setup.sh first."
        exit 1
    fi

    if ! host_vivado_install_present; then
        error "Vivado installation was not found under $XILINX_INSTALL_DIR. Run $REPO_ROOT/scripts/setup.sh first."
        exit 1
    fi

    project_root="$(host_project_root)"
    working_dir="$(current_host_dir)"
    container_workdir="$(container_workdir_for_pwd "$project_root" "$working_dir")"

    docker_tty_args
    docker_args+=(
        run
        --rm
        --platform
        linux/amd64
        "${DOCKER_TTY_ARGS[@]}"
        -e
        "TERM=${TERM:-xterm-256color}"
        -v
        "$REPO_ROOT:$CONTAINER_TOOL_ROOT:ro"
        -v
        "$project_root:$CONTAINER_PROJECT_ROOT"
        -v
        "$XILINX_INSTALL_DIR:$CONTAINER_XILINX_ROOT"
        -v
        "$XILINX_CONFIG_DIR:$CONTAINER_HOME/.Xilinx"
        -w
        "$container_workdir"
        "$IMAGE_NAME"
        "$CONTAINER_TOOL_ROOT/scripts/container_exec.sh"
        "$tool"
    )

    if [[ "$tool" == "vivado" && "$#" -eq 0 ]]; then
        set -- -mode tcl
    fi

    docker "${docker_args[@]}" "$@"
}
