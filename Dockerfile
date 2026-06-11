# 采用 NVIDIA 官方 CUDA 13.0 运行时镜像 (基于 Ubuntu 24.04)
FROM nvidia/cuda:13.0.0-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# 安装系统级依赖与 Python 3.12
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3-pip \
    git wget build-essential ffmpeg libgl1 libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/* && \
    ln -s /usr/bin/python3.12 /usr/bin/python

WORKDIR /app

# 突破 PEP 668 限制，强制在容器全局环境安装指定版本 (cu130) 的 PyTorch 生态
RUN pip install --break-system-packages torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu130

# 克隆最新 ComfyUI 核心代码，安装主线依赖，并同步安装 V4 架构的原生 Manager 依赖包
RUN git clone https://github.com/Comfy-Org/ComfyUI.git . && \
    pip install --break-system-packages -r requirements.txt && \
    pip install --break-system-packages -r manager_requirements.txt

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8188
ENTRYPOINT ["/entrypoint.sh"]