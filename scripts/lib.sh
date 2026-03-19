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
readonly CONTAINER_XILINX_ROOT="/state/Xilinx"

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

translate_host_path_prefix() {
    local value="$1"
    local host_root="$2"
    local container_root="$3"

    case "$value" in
        "$host_root")
            printf '%s\n' "$container_root"
            ;;
        "$host_root"/*)
            printf '%s%s\n' "$container_root" "${value#$host_root}"
            ;;
        *)
            printf '%s\n' "$value"
            ;;
    esac
}

translate_host_tool_args() {
    local project_root="$1"
    shift

    TRANSLATED_TOOL_ARGS=()

    local arg
    for arg in "$@"; do
        arg="$(translate_host_path_prefix "$arg" "$project_root" "$CONTAINER_PROJECT_ROOT")"
        arg="$(translate_host_path_prefix "$arg" "$REPO_ROOT" "$CONTAINER_TOOL_ROOT")"
        arg="$(translate_host_path_prefix "$arg" "$XILINX_INSTALL_DIR" "$CONTAINER_XILINX_ROOT")"
        arg="$(translate_host_path_prefix "$arg" "$XILINX_CONFIG_DIR" "$CONTAINER_HOME/.Xilinx")"
        TRANSLATED_TOOL_ARGS+=("$arg")
    done
}

docker_tty_args() {
    DOCKER_TTY_ARGS=(-i)
    # Docker refuses -t when stdin is not a tty, which happens under
    # make/fusesoc even if stdout is still attached to the terminal.
    if [[ -t 0 && -t 1 ]]; then
        DOCKER_TTY_ARGS+=(-t)
    fi
}

license_container_mac() {
    local configured_mac="${VIVADO_MAC_DOCKER_MAC:-}"
    local license_file="${XILINX_CONFIG_DIR}/Xilinx.lic"
    local hostid

    if [[ "$configured_mac" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]; then
        printf '%s\n' "${configured_mac,,}"
        return 0
    fi

    [[ -f "$license_file" ]] || return 1

    hostid="$(
        sed -nE 's/.*HOSTID=([[:xdigit:]]{12}).*/\1/p' "$license_file" | head -n 1
    )"

    [[ "$hostid" =~ ^[[:xdigit:]]{12}$ ]] || return 1

    printf '%s:%s:%s:%s:%s:%s\n' \
        "${hostid:0:2}" "${hostid:2:2}" "${hostid:4:2}" \
        "${hostid:6:2}" "${hostid:8:2}" "${hostid:10:2}" | tr '[:upper:]' '[:lower:]'
}

docker_network_args() {
    local container_mac
    DOCKER_NETWORK_ARGS=()

    if container_mac="$(license_container_mac)"; then
        DOCKER_NETWORK_ARGS=(--mac-address "$container_mac")
    fi
}

host_cpu_count() {
    local cpu_count="${VIVADO_MAC_CPU_COUNT:-}"

    if [[ -z "$cpu_count" ]] && command -v getconf >/dev/null 2>&1; then
        cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
    fi

    if [[ -z "$cpu_count" ]] && command -v sysctl >/dev/null 2>&1; then
        cpu_count="$(sysctl -n hw.logicalcpu 2>/dev/null || true)"
    fi

    if [[ -z "$cpu_count" ]] && command -v nproc >/dev/null 2>&1; then
        cpu_count="$(nproc 2>/dev/null || true)"
    fi

    if [[ "$cpu_count" =~ ^[1-9][0-9]*$ ]]; then
        printf '%s\n' "$cpu_count"
        return 0
    fi

    return 1
}

docker_cpu_args() {
    local cpu_count
    DOCKER_CPU_ARGS=()

    if cpu_count="$(host_cpu_count)"; then
        DOCKER_CPU_ARGS=(--cpus "$cpu_count")
    fi
}

host_memory_limit() {
    local memory_limit="${VIVADO_MAC_MEMORY:-}"
    local page_size
    local phys_pages

    if [[ -n "$memory_limit" ]]; then
        printf '%s\n' "$memory_limit"
        return 0
    fi

    if command -v sysctl >/dev/null 2>&1; then
        memory_limit="$(sysctl -n hw.memsize 2>/dev/null || true)"
    fi

    if [[ -z "$memory_limit" ]] && command -v getconf >/dev/null 2>&1; then
        page_size="$(getconf PAGESIZE 2>/dev/null || true)"
        phys_pages="$(getconf _PHYS_PAGES 2>/dev/null || true)"
        if [[ "$page_size" =~ ^[1-9][0-9]*$ ]] && [[ "$phys_pages" =~ ^[1-9][0-9]*$ ]]; then
            memory_limit="$((page_size * phys_pages))"
        fi
    fi

    if [[ "$memory_limit" =~ ^[1-9][0-9]*$ ]]; then
        printf '%s\n' "$memory_limit"
        return 0
    fi

    return 1
}

docker_memory_args() {
    local memory_limit
    DOCKER_MEMORY_ARGS=()

    if memory_limit="$(host_memory_limit)"; then
        DOCKER_MEMORY_ARGS=(--memory "$memory_limit")
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
    translate_host_tool_args "$project_root" "$@"
    set -- "${TRANSLATED_TOOL_ARGS[@]}"

    docker_tty_args
    docker_network_args
    docker_cpu_args
    docker_memory_args
    docker_args+=(
        run
        --rm
        --platform
        linux/amd64
        "${DOCKER_TTY_ARGS[@]}"
        "${DOCKER_NETWORK_ARGS[@]}"
        "${DOCKER_CPU_ARGS[@]}"
        "${DOCKER_MEMORY_ARGS[@]}"
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
