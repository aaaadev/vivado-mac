#!/usr/bin/env bash
set -euo pipefail

source "$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

declare -A VERSIONS=(
    ["202502"]="abe838aa2e2d3d9b10fea94165e9a303"
    ["202402"]="20c806793b3ea8d79273d5138fbd195f"
    ["202401"]="8b0e99a41b851b50592d5d6ef1b1263d"
    ["202302"]="b8c785d03b754766538d6cde1277c4f0"
)

get_version_from_hash() {
    local hash="$1"

    for version in "${!VERSIONS[@]}"; do
        if [ "${VERSIONS[$version]}" == "$hash" ]; then
            echo "$version"
            return 0
        fi
    done

    echo ""
    return 1
}

get_credentials() {
    local secret_file="$1"
    local secret_dir=$(dirname "$secret_file")

    # Create directory if it doesn't exist
    mkdir -p "$secret_dir"

    # Prompt for credentials
    printf 'Enter your email address: '
    read -r email
    printf 'Enter your password: '
    read -r -s password
    echo  # New line after password input

    # Save credentials to file
    echo "$email" > "$secret_file"
    echo "$password" >> "$secret_file"

    echo "Credentials saved to $secret_file"
}

readonly SECRET_FILE="${VIVADO_MAC_STATE_DIR:-/state}/secret.txt"
readonly INSTALLATION_FILE_PATH="${VIVADO_INSTALLER_PATH:?VIVADO_INSTALLER_PATH is required}"
readonly INSTALL_ROOT="${VIVADO_INSTALL_ROOT:-/state/Xilinx}"
readonly EXTRACT_DIR="${VIVADO_MAC_STATE_DIR:-/state}/installer"

INSTALLER_HASH="$(md5sum "$INSTALLATION_FILE_PATH" | awk '{print $1}')"
VERSION="$(get_version_from_hash "$INSTALLER_HASH")"

if [[ -z "$VERSION" ]]; then
    error "The installer $INSTALLATION_FILE_PATH hash does not match a supported Linux installer."
    exit 1
fi

if [[ "$VERSION" == "202401" ]]; then
    error "Version $VERSION is not supported. Please use the latest release for that year."
    exit 1
fi

info "The installer is version $VERSION"

step "Checking installer path $INSTALLATION_FILE_PATH"

if [[ -f "$INSTALLATION_FILE_PATH" ]]; then
    success "File exists: $INSTALLATION_FILE_PATH"
else
    error "File does not exist: $INSTALLATION_FILE_PATH"
    exit 1
fi

if [[ ! -d "$EXTRACT_DIR" ]]; then
    step "Extracting installer"
    chmod u+x "$INSTALLATION_FILE_PATH"
    "$INSTALLATION_FILE_PATH" --target "$EXTRACT_DIR" --noexec
else
    debug "The installer was already extracted"
fi

step "Generating AuthTokenGen"

GENERATED_TOKEN=false

if [[ -f "$SECRET_FILE" ]]; then
        info "Credentials file found."
        if ! expect -f "$SCRIPT_DIR/auth_token_gen.exp" "$EXTRACT_DIR/xsetup" "$SECRET_FILE"; then
            error "secret.txt is invalid; removing $SECRET_FILE"
            rm -f "$SECRET_FILE"
        else
            GENERATED_TOKEN=true
        fi
fi

if ! $GENERATED_TOKEN && ! "$EXTRACT_DIR/xsetup" -b AuthTokenGen
then
    warning "Can't Generate AuthTokenGen"
    step "now using expect method"
    step "Checking for credentials..."
    if [[ ! -f "$SECRET_FILE" ]]; then
        warning "Credentials file not found."
        get_credentials "$SECRET_FILE"
    fi

    # Check if secret.txt is readable and not empty
    if [[ ! -r "$SECRET_FILE" || ! -s "$SECRET_FILE" ]]; then
        warning "Cannot read credentials file or file is empty"
        get_credentials "$SECRET_FILE"
    fi

    step "Generate AuthTokenGen"

    expect -f "$SCRIPT_DIR/auth_token_gen.exp" "$EXTRACT_DIR/xsetup" "$SECRET_FILE"
else
    GENERATED_TOKEN=true
fi

if $GENERATED_TOKEN; then
    local_settings_file="$(mktemp)"
    trap 'rm -f "$local_settings_file"' EXIT
    sed "s#^Destination=.*#Destination=$INSTALL_ROOT#" "$SCRIPT_DIR/vivado_settings_${VERSION}.txt" > "$local_settings_file"
    step "Start download and installation into $INSTALL_ROOT"
    "$EXTRACT_DIR/xsetup" -c "$local_settings_file" -b Install -a XilinxEULA,3rdPartyEULA
fi
