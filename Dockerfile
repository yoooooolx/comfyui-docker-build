# 采用 NVIDIA 官方 CUDA 13.0 运行时镜像 (基于 Ubuntu 24.04)
FROM nvidia/cuda:13.0.0-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# 安装系统级依赖与 Python 3.12
# 注：Ubuntu 24.04 默认搭载 Python 3.12，需同步安装 venv 模块与多媒体处理库
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3-pip \
    git wget build-essential ffmpeg libgl1 libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/* && \
    ln -s /usr/bin/python3.12 /usr/bin/python

WORKDIR /app

# 突破 PEP 668 限制，强制在容器全局环境安装指定版本 (cu130) 的 PyTorch 生态
# RUN pip install --break-system-packages torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu130
# 将核心依赖comfyui-frontend写入镜像，防止物理机意外关机导致的假死
RUN pip install --break-system-packages torch torchvision torchaudio comfyui-frontend --extra-index-url https://download.pytorch.org/whl/cu130

# 克隆最新 ComfyUI 核心代码并安装自身依赖
RUN git clone https://github.com/Comfy-Org/ComfyUI.git . && \
    pip install --break-system-packages -r requirements.txt

# 克隆 Manager 插件至暂存区
RUN mkdir -p /staging && cd /staging && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && \
    pip install --break-system-packages -r requirements.txt

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8188
ENTRYPOINT ["/entrypoint.sh"]
