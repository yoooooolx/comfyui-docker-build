#!/bin/bash
set -e

VENV_DIR="/app/user/venv"

# 状态洗消机制：处理意外关机导致的各种锁死与脏缓存
echo "[Runtime] Sanitizing package manager caches and stale locks..."
rm -rf /root/.cache/uv/*
rm -rf /root/.cache/pip/*
rm -rf /tmp/*

if [ -d "$VENV_DIR" ]; then
    echo "[Runtime] Checking persistent venv for stale locks..."
    find "$VENV_DIR" -type f -name "*.lock" -delete 2>/dev/null || true
    find "$VENV_DIR" -type f -name "*.pending" -delete 2>/dev/null || true
fi

if [ ! -d "$VENV_DIR" ]; then
    echo "[Runtime] Initializing persistent virtual environment in volume..."
    python -m venv "$VENV_DIR" --system-site-packages
fi

source "$VENV_DIR/bin/activate"

# 扫描正确的 custom_nodes 目录以安装第三方增量依赖
echo "[Runtime] Checking for custom node dependencies..."
find /app/custom_nodes -mindepth 2 -maxdepth 2 -name "requirements.txt" | while read req_file; do
    echo "[Runtime] Resolving $req_file ..."
    pip install --no-cache-dir -r "$req_file" || echo "[Warning] Dependency resolution skipped for $req_file"
done

echo "[Runtime] Executing ComfyUI Core Services..."
exec python main.py --enable-manager --listen 127.0.0.1 "$@"