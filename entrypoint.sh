#!/bin/bash
set -euo pipefail

VENV_DIR="/app/user/venv"
STATE_DIR="/app/user/.dependency-state"
CACHE_DIR="/app/user/.cache"
LOCK_FILE="/app/user/.dependency-install.lock"

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
    find "$STATE_DIR" -maxdepth 1 -type f -name "*.tmp.*" -delete 2>/dev/null || true

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
}

install_requirements() {
    local req_file="$1"
    local force_install="${COMFYUI_FORCE_REQUIREMENTS:-0}"
    local requirements_hash
    local path_hash
    local marker_file
    local marker_tmp

    requirements_hash="$(sha256sum "$req_file" | cut -d ' ' -f 1)"
    path_hash="$(printf '%s' "$req_file" | sha256sum | cut -d ' ' -f 1)"
    marker_file="${STATE_DIR}/${path_hash}.sha256"
    marker_tmp="${marker_file}.tmp.$$"

    if [ "$force_install" != "1" ] && [ -f "$marker_file" ] && [ "$(<"$marker_file")" = "$requirements_hash" ]; then
        echo "[Runtime] Dependencies unchanged for $req_file; skipping."
        return
    fi

    echo "[Runtime] Installing dependencies from $req_file ..."
    if python -m pip install -r "$req_file"; then
        printf '%s\n' "$requirements_hash" > "$marker_tmp"
        mv -f "$marker_tmp" "$marker_file"
        echo "[Runtime] Dependency marker updated for $req_file."
    else
        rm -f "$marker_tmp"
        echo "[Warning] Dependency install failed for $req_file; marker was not updated; ComfyUI will continue; next startup retries."
    fi
}

run_dependency_setup() {
    prepare_venv

    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"

    echo "[Runtime] Checking for custom node dependencies..."
    if [ -d /app/custom_nodes ]; then
        while IFS= read -r -d '' req_file; do
            install_requirements "$req_file"
        done < <(find /app/custom_nodes -mindepth 2 -maxdepth 2 -type f -name "requirements.txt" -print0 | sort -z)
    else
        echo "[Runtime] No custom_nodes directory found; skipping dependency scan."
    fi
}

exec 9>"$LOCK_FILE"
echo "[Runtime] Waiting for dependency installation lock..."
flock 9
run_dependency_setup
flock -u 9
exec 9>&-

echo "[Runtime] Executing ComfyUI Core Services..."
exec python main.py --enable-manager --listen 0.0.0.0 "$@"
