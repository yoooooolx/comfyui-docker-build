#!/bin/bash
set -e

VENV_DIR="/app/ComfyUI/custom_nodes/venv"

# 1. 自动初始化外部持久化卷中的独立虚拟环境（允许继承系统 site-packages 的 PyTorch/CUDA 库）
if [ ! -d "$VENV_DIR" ]; then
    echo "[Runtime] Initializing persistent virtual environment in volume..."
    python -m venv "$VENV_DIR" --system-site-packages
fi

# 2. 核心劫持：激活该虚拟环境，后续所有动态 pip 安装全部导流至宿主机
source "$VENV_DIR/bin/activate"

# 3. 解决挂载卷 Shadowing 冲突，将 Manager 搬运至挂载卷
if [ ! -d "/app/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
    echo "[Runtime] Deploying ComfyUI-Manager to custom_nodes volume..."
    cp -r /staging/ComfyUI-Manager /app/ComfyUI/custom_nodes/
fi

# 4. 依赖项防丢失扫描机制
echo "[Runtime] Checking for custom node dependencies..."
find /app/ComfyUI/custom_nodes -mindepth 2 -maxdepth 2 -name "requirements.txt" | while read req_file; do
    echo "[Runtime] Resolving $req_file ..."
    pip install --no-cache-dir -r "$req_file" || echo "[Warning] Dependency resolution skipped for $req_file"
done

echo "[Runtime] Executing ComfyUI Core Services..."
exec python main.py --listen 0.0.0.0 "$@"
