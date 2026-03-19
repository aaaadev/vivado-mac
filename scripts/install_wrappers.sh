#!/usr/bin/env bash
set -euo pipefail

source "$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

install_dir="${1:-}"

if [[ -z "$install_dir" ]]; then
    if [[ -d "$HOME/bin" ]]; then
        install_dir="$HOME/bin"
    else
        install_dir="$HOME/.local/bin"
    fi
fi

mkdir -p "$install_dir"

ln -sfn "$REPO_ROOT/bin/vivado" "$install_dir/vivado"
ln -sfn "$REPO_ROOT/bin/fusesoc" "$install_dir/fusesoc"

success "Installed wrapper symlinks into $install_dir"

if [[ ":$PATH:" != *":$install_dir:"* ]]; then
    important "Add $install_dir to your PATH to use vivado and fusesoc directly."
fi
