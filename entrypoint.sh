#!/bin/bash
set -euo pipefail

VENV_DIR="/app/user/venv"
STATE_DIR="/app/user/.dependency-state"
CACHE_DIR="/app/user/.cache"
LOCK_FILE="/app/user/.dependency-install.lock"
RUNTIME_FINGERPRINT_FILE="/app/.runtime-fingerprint"
SAVED_RUNTIME_FINGERPRINT_FILE="${STATE_DIR}/runtime.sha256"
DEPENDENCY_MARKER_FILE="${STATE_DIR}/custom-nodes.sha256"
TORCH_CONSTRAINTS_FILE="/tmp/torch-constraints.txt"

export HOME="/app/user"
export XDG_CACHE_HOME="$CACHE_DIR"
export XDG_CONFIG_HOME="/app/user/.config"
export XDG_DATA_HOME="/app/user/.local/share"
export XDG_STATE_HOME="/app/user/.local/state"
export PIP_CACHE_DIR="${CACHE_DIR}/pip"
export UV_CACHE_DIR="${CACHE_DIR}/uv"
export HF_HOME="${CACHE_DIR}/huggingface"
export TORCH_HOME="${CACHE_DIR}/torch"
export TORCHINDUCTOR_CACHE_DIR="${CACHE_DIR}/torchinductor"
export TRITON_CACHE_DIR="${CACHE_DIR}/triton"

echo "[Runtime] Preparing persistent package state..."
mkdir -p \
    "$PIP_CACHE_DIR" \
    "$UV_CACHE_DIR" \
    "$HF_HOME" \
    "$TORCH_HOME" \
    "$TORCHINDUCTOR_CACHE_DIR" \
    "$TRITON_CACHE_DIR" \
    "$XDG_CONFIG_HOME" \
    "$XDG_DATA_HOME" \
    "$XDG_STATE_HOME" \
    "$STATE_DIR"

venv_is_valid() {
    [ -x "$VENV_DIR/bin/python" ] && [ -r "$VENV_DIR/bin/activate" ]
}

reset_dependency_markers() {
    find "$STATE_DIR" -maxdepth 1 -type f -name "*.sha256" -delete 2>/dev/null || true
    find "$STATE_DIR" -maxdepth 1 -type f -name "*.tmp.*" -delete 2>/dev/null || true
}

prepare_venv() {
    local runtime_fingerprint
    local saved_runtime_fingerprint=""

    find "$STATE_DIR" -maxdepth 1 -type f -name "*.tmp.*" -delete 2>/dev/null || true

    runtime_fingerprint="$(sha256sum "$RUNTIME_FINGERPRINT_FILE" | cut -d ' ' -f 1)"
    if [ -f "$SAVED_RUNTIME_FINGERPRINT_FILE" ]; then
        saved_runtime_fingerprint="$(<"$SAVED_RUNTIME_FINGERPRINT_FILE")"
    fi

    if [ -d "$VENV_DIR" ] && [ "$saved_runtime_fingerprint" != "$runtime_fingerprint" ]; then
        echo "[Runtime] Base runtime changed; rebuilding the persistent virtual environment."
        rm -rf "$VENV_DIR"
        reset_dependency_markers
    fi

    if [ -d "$VENV_DIR" ]; then
        echo "[Runtime] Checking persistent venv for stale locks..."
        find "$VENV_DIR" -type f -name "*.lock" -delete 2>/dev/null || true
        find "$VENV_DIR" -type f -name "*.pending" -delete 2>/dev/null || true
    fi

    if venv_is_valid; then
        return
    fi

    if [ -e "$VENV_DIR" ]; then
        echo "[Runtime] Persistent virtual environment is missing bin/python or bin/activate; rebuilding and clearing dependency markers."
        rm -rf "$VENV_DIR"
        reset_dependency_markers
    else
        echo "[Runtime] Initializing persistent virtual environment in volume..."
    fi

    python -m venv "$VENV_DIR" --system-site-packages
    reset_dependency_markers

    printf '%s\n' "$runtime_fingerprint" > "${SAVED_RUNTIME_FINGERPRINT_FILE}.tmp.$$"
    mv -f "${SAVED_RUNTIME_FINGERPRINT_FILE}.tmp.$$" "$SAVED_RUNTIME_FINGERPRINT_FILE"
}

install_custom_node_requirements() {
    local force_install="${COMFYUI_FORCE_REQUIREMENTS:-0}"
    local dependency_hash
    local marker_tmp
    local req_file
    local -a pip_args
    local -a requirements_files

    mapfile -d '' -t requirements_files < <(
        find /app/custom_nodes -mindepth 2 -maxdepth 2 -type f -name "requirements.txt" -print0 | sort -z
    )

    if [ "${#requirements_files[@]}" -eq 0 ]; then
        echo "[Runtime] No custom node requirements found; skipping."
        return
    fi

    dependency_hash="$({
        cat "$RUNTIME_FINGERPRINT_FILE" "$TORCH_CONSTRAINTS_FILE"
        for req_file in "${requirements_files[@]}"; do
            printf '\0%s\0' "$req_file"
            cat "$req_file"
        done
    } | sha256sum | cut -d ' ' -f 1)"
    marker_tmp="${DEPENDENCY_MARKER_FILE}.tmp.$$"

    if [ "$force_install" != "1" ] && [ -f "$DEPENDENCY_MARKER_FILE" ] && [ "$(<"$DEPENDENCY_MARKER_FILE")" = "$dependency_hash" ]; then
        echo "[Runtime] Custom node dependency environment unchanged; skipping."
        return
    fi

    pip_args=(-c "$TORCH_CONSTRAINTS_FILE")
    for req_file in "${requirements_files[@]}"; do
        pip_args+=(-r "$req_file")
    done

    echo "[Runtime] Resolving all custom node dependencies as one environment..."
    if python -m pip install "${pip_args[@]}" && \
        python -m pip check && \
        python -c 'import torch, torchvision, torchaudio'; then
        printf '%s\n' "$dependency_hash" > "$marker_tmp"
        mv -f "$marker_tmp" "$DEPENDENCY_MARKER_FILE"
        echo "[Runtime] Custom node dependency marker updated."
    else
        rm -f "$marker_tmp"
        echo "[Warning] Custom node dependency resolution failed; marker was not updated; ComfyUI will continue; next startup retries."
    fi
}

run_dependency_setup() {
    prepare_venv

    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"

    echo "[Runtime] Checking for custom node dependencies..."
    if [ -d /app/custom_nodes ]; then
        install_custom_node_requirements
    else
        echo "[Runtime] No custom_nodes directory found; skipping dependency scan."
    fi
}

configure_manager_package_installer() {
    local manager_config_dir="/app/user/__manager"

    mkdir -p "$manager_config_dir"
    python - "${manager_config_dir}/config.ini" <<'PY'
import configparser
import sys

config_path = sys.argv[1]
config = configparser.ConfigParser(strict=False)
config.read(config_path)
if not config.has_section("default"):
    config.add_section("default")
config.set("default", "use_uv", "false")
with open(config_path, "w", encoding="utf-8") as config_file:
    config.write(config_file)
PY
}

exec 9>"$LOCK_FILE"
echo "[Runtime] Waiting for dependency installation lock..."
flock 9
run_dependency_setup
configure_manager_package_installer
flock -u 9
exec 9>&-

echo "[Runtime] Executing ComfyUI Core Services..."
exec python main.py --enable-manager --listen "${COMFYUI_LISTEN:-127.0.0.1}" "$@"
