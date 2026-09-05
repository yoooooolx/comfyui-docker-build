# ComfyUI Docker Build

面向 NVIDIA CUDA 13.0 的 ComfyUI 容器镜像，提供分层运行能力、持久化数据目录和自定义节点依赖缓存。

## 镜像标签

| 标签 | 用途 |
| --- | --- |
| `latest` / `runtime` | 完整运行环境，包含工作流模板、内嵌文档和 ComfyUI Manager |
| `lite` | 精简运行环境，不包含工作流模板媒体和内嵌文档 |
| `compile` | 在 runtime 上增加 GCC、G++、CMake、Ninja 和 Python headers，供 Torch Inductor/Triton 与本地扩展编译 |
| `cuda-devel` | 在 compile 上增加 CUDA 13.0 NVCC 和开发头文件 |

这些标签表示能力分层，不是 CPU、ROCm 或其他 CUDA 版本的硬件矩阵。目前发布镜像仅面向 Linux amd64 和 NVIDIA CUDA 13.0。

## 启动

本地源码构建并启动：

```bash
docker compose up -d --build
```

使用已发布镜像时，复制示例配置：

```bash
cp docker-compose.yml.example docker-compose.yml
docker compose up -d
```

默认仅可从宿主机访问：

```text
http://127.0.0.1:8188/
```

不要直接使用 `-p 8188:8188` 将 ComfyUI 暴露到公网。需要远程访问时，应使用带身份认证和 TLS 的反向代理，或仅在可信私网中开放。

## 持久化目录

Compose 将以下目录绑定到项目现有的 `data/`：

| 宿主机目录 | 容器目录 | 内容 |
| --- | --- | --- |
| `data/models` | `/app/models` | Checkpoint、VAE、LoRA、ControlNet 等模型 |
| `data/custom_nodes` | `/app/custom_nodes` | 自定义节点 |
| `data/input` | `/app/input` | 输入文件 |
| `data/output` | `/app/output` | 生成结果 |
| `data/user` | `/app/user` | 工作流、数据库、Manager 配置、日志、venv 和运行缓存 |

`data/user` 必须可写。容器当前以 root 运行，因此在共享主机或多用户环境中，应提前按部署策略设置目录所有者和权限。升级镜像后，入口脚本会根据 Python、ComfyUI、Torch 和 CUDA 运行时指纹判断是否重建持久 venv，不会删除模型、节点、输入、输出或用户配置。

## 自定义节点依赖

启动时会扫描 `data/custom_nodes/*/requirements.txt`，将所有节点依赖作为一个环境统一解析，并使用固定的 Torch 版本约束。只有完整安装、`pip check` 和 Torch 导入检查全部成功后才更新持久化标记。

依赖未变化时会跳过安装。需要强制重新解析时：

```bash
COMFYUI_FORCE_REQUIREMENTS=1 docker compose up -d --force-recreate
```

pip、uv、Hugging Face、Torch、Torch Inductor 和 Triton 缓存保存在 `data/user/.cache`，容器重建后继续复用。

## GPU 要求

- NVIDIA 驱动需支持 CUDA 13.0。
- 宿主机需要安装 NVIDIA Container Toolkit。
- Compose 默认请求全部 GPU，并启用 `compute,utility,video` 驱动能力。

查看运行状态：

```bash
docker compose ps
docker compose logs -f
curl http://127.0.0.1:8188/system_stats
```
