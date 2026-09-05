# syntax=docker/dockerfile:1.7

ARG UBUNTU_VERSION=24.04
ARG UBUNTU_DIGEST=sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517
ARG PYTHON_VERSION=3.12
ARG TORCH_VERSION=2.14.0
ARG TORCHVISION_VERSION=0.29.0
ARG TORCHAUDIO_VERSION=2.11.0
ARG PYTORCH_EXTRA_INDEX_URL=https://download.pytorch.org/whl/cu130
ARG UV_VERSION=0.8.15
ARG COMFYUI_COMMIT=250b2e9551a7bc7a8ebb5beb07e0fecd2983e04a

FROM ubuntu:${UBUNTU_VERSION}@${UBUNTU_DIGEST} AS python-runtime

ARG PYTHON_VERSION
ARG UV_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_LINK_MODE=copy

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        ffmpeg \
        git \
        libglib2.0-0 \
        libgl1 \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-venv \
        python3-pip \
        util-linux \
        wget && \
    ln -sf /usr/bin/python${PYTHON_VERSION} /usr/local/bin/python && \
    ln -sf /usr/bin/python${PYTHON_VERSION} /usr/local/bin/python3

RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --ignore-installed pip setuptools wheel "uv==${UV_VERSION}"

WORKDIR /app

FROM python-runtime AS torch-runtime

ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION
ARG PYTORCH_EXTRA_INDEX_URL

RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install \
        --extra-index-url "${PYTORCH_EXTRA_INDEX_URL}" \
        --prefer-binary \
        "torch==${TORCH_VERSION}" \
        "torchvision==${TORCHVISION_VERSION}" \
        "torchaudio==${TORCHAUDIO_VERSION}" && \
    printf 'torch==%s\ntorchvision==%s\ntorchaudio==%s\n' \
        "${TORCH_VERSION}" \
        "${TORCHVISION_VERSION}" \
        "${TORCHAUDIO_VERSION}" \
        > /tmp/torch-constraints.txt

FROM torch-runtime AS comfyui-source

ARG COMFYUI_COMMIT

RUN git init . && \
    git remote add origin https://github.com/Comfy-Org/ComfyUI.git && \
    git fetch --depth=1 origin "${COMFYUI_COMMIT}" && \
    git checkout --detach FETCH_HEAD && \
    test "$(git rev-parse HEAD)" = "${COMFYUI_COMMIT}" && \
    rm -rf .git

COPY --chmod=755 entrypoint.sh /entrypoint.sh

EXPOSE 8188
ENTRYPOINT ["/entrypoint.sh"]

FROM comfyui-source AS runtime

RUN --mount=type=cache,target=/root/.cache/pip \
    grep -Eiq '^comfyui-workflow-templates([<>=!~]|$)' requirements.txt && \
    grep -Eiq '^comfyui-embedded-docs([<>=!~]|$)' requirements.txt && \
    python -m pip install -c /tmp/torch-constraints.txt -r requirements.txt && \
    python -m pip install -r manager_requirements.txt && \
    python -m pip show comfyui-workflow-templates comfyui-embedded-docs comfyui-frontend-package comfy-kitchen transformers torchaudio && \
    python -m pip check

FROM comfyui-source AS lite

RUN --mount=type=cache,target=/root/.cache/pip \
    awk 'BEGIN { IGNORECASE = 1 } \
    /^[[:space:]]*($|#)/ { print; next } \
    { name = $1; sub(/[<>=!~].*/, "", name); lowered = tolower(name); \
      if (lowered == "comfyui-workflow-templates" || lowered == "comfyui-embedded-docs") next; \
      print }' requirements.txt > /tmp/requirements-lite.txt && \
    mv /tmp/requirements-lite.txt requirements.txt && \
    ! grep -Eiq '^comfyui-workflow-templates([<>=!~]|$)' requirements.txt && \
    ! grep -Eiq '^comfyui-embedded-docs([<>=!~]|$)' requirements.txt && \
    python -m pip install -c /tmp/torch-constraints.txt -r requirements.txt && \
    python -m pip install -r manager_requirements.txt && \
    python -m pip show comfyui-frontend-package comfy-kitchen transformers torchaudio && \
    ! python -m pip show comfyui-workflow-templates comfyui-embedded-docs >/tmp/lite-omitted-packages.txt 2>&1 && \
    python -m pip check

FROM runtime AS compile

ARG PYTHON_VERSION

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        ninja-build \
        python${PYTHON_VERSION}-dev

FROM compile AS cuda-devel

ARG CUDA_KEYRING_VERSION=1.1-1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    wget -qO /tmp/cuda-keyring.deb \
        "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_${CUDA_KEYRING_VERSION}_all.deb" && \
    dpkg -i /tmp/cuda-keyring.deb && \
    rm -f /tmp/cuda-keyring.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        cuda-cudart-dev-13-0 \
        cuda-driver-dev-13-0 \
        cuda-nvcc-13-0

ENV CUDA_HOME=/usr/local/cuda-13.0 \
    PATH=/usr/local/cuda-13.0/bin:${PATH}

FROM runtime AS default
