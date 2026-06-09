#!/bin/bash
set -e

# 修正 1：将 venv 部署到挂载的 user 目录，彻底避开 custom_nodes 的递归扫描陷阱
VENV_DIR="/app/user/venv"

if [ ! -d "$VENV_DIR" ]; then
    echo "[Runtime] Initializing persistent virtual environment in volume..."
    python -m venv "$VENV_DIR" --system-site-packages
fi

source "$VENV_DIR/bin/activate"

# 修正 2：修复相对路径错位，将 Manager 准确投放至 /app/custom_nodes
if [ ! -d "/app/custom_nodes/ComfyUI-Manager" ]; then
    echo "[Runtime] Deploying ComfyUI-Manager to custom_nodes volume..."
    cp -r /staging/ComfyUI-Manager /app/custom_nodes/
fi

# 修正 3：扫描正确的 custom_nodes 目录以安装依赖
echo "[Runtime] Checking for custom node dependencies..."
find /app/custom_nodes -mindepth 2 -maxdepth 2 -name "requirements.txt" | while read req_file; do
    echo "[Runtime] Resolving $req_file ..."
    pip install --no-cache-dir -r "$req_file" || echo "[Warning] Dependency resolution skipped for $req_file"
done

echo "[Runtime] Executing ComfyUI Core Services..."
exec python main.py --listen 0.0.0.0 "$@"
