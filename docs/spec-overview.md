# VM Hardware Specification Overview

## System Information

| Property | Value |
|----------|-------|
| **Hostname** | DESKTOP-VQN0VVJ |
| **Operating System** | Ubuntu 22.04.5 LTS |
| **Kernel** | Linux 6.6.87.2-microsoft-standard-WSL2 |
| **Architecture** | x86_64 (amd64) |
| **Platform** | WSL2 (Windows Subsystem for Linux) |

## CPU Specifications

| Property | Value |
|----------|-------|
| **CPU Model** | 12th Gen Intel(R) Core(TM) i5-12500H |
| **Total CPUs** | 2 vCPUs |
| **Cores per Socket** | 1 |
| **Threads per Core** | 2 |
| **Architecture** | x86_64 |

## Memory Specifications

| Property | Value |
|----------|-------|
| **Total RAM** | 5.8 GiB |
| **Used RAM** | 3.2 GiB (55%) |
| **Free RAM** | 2.4 GiB |
| **Swap** | Not configured |

## Storage Specifications

| Property | Value |
|----------|-------|
| **Disk Size** | 1007 GB |
| **Used Space** | 94 GB (10%) |
| **Available Space** | 863 GB |
| **Mount Point** | / (root) |
| **Filesystem** | /dev/sdc |

## GPU Specifications

| Property | Value |
|----------|-------|
| **GPU Model** | NVIDIA GeForce RTX 2050 |
| **GPU ID** | 00000000:01:00.0 |
| **Total VRAM** | 4096 MiB (4 GB) |
| **Free VRAM** | 3965 MiB (~3.9 GB) |
| **Compute Capability** | 8.6 |
| **CUDA Version** | 13.1 |
| **Driver Version** | 591.44 |
| **Persistence Mode** | Enabled |
| **Current Temp** | 50°C |
| **Power Usage** | 9W / 54W |
| **GPU Utilization** | 0% (idle) |

## NVIDIA Container Toolkit

| Property | Value |
|----------|-------|
| **Toolkit Version** | 1.18.1 |
| **CLI Version** | 1.18.1 |
| **Build Date** | 2025-11-24 |
| **Docker Runtime** | nvidia (available) |
| **GPU Access** | `--gpus all` flag supported |

## Docker Configuration

| Property | Value |
|----------|-------|
| **Docker Version** | 29.1.3 |
| **API Version** | 1.52 |
| **Docker Root Dir** | /var/lib/docker |
| **Containerd Version** | v2.2.1 |
| **Runc Version** | 1.3.4 |
| **BuildKit Status** | Enabled (default in Docker 23.0+) |
| **Docker CPUs Allocated** | 2 |
| **Docker Memory Allocated** | 5.789 GiB |
| **GPU Runtime** | nvidia (available) |
| **Available Runtimes** | io.containerd.runc.v2, nvidia, runc |

## GitHub CLI

| Property | Value |
|----------|-------|
| **GitHub CLI** | Installed (v2.83.2) |

## Performance Considerations for Docker Builds

### Current Limitations
- **CPU**: 2 vCPUs may limit parallel build performance
- **RAM**: 5.8 GB is sufficient for most builds, but large node_modules may cause memory pressure
- **Storage**: 863 GB available is excellent for caching and Docker layer storage
- **GPU**: 4 GB VRAM sufficient for inference and small training, but not large models

### Optimization Recommendations

1. **CPU Optimization**
   - Set `--jobs=2` in BuildKit to match available vCPUs
   - Use `BUILDKIT_STEP_LOG_MAX_SIZE` to reduce memory overhead during builds

2. **Memory Optimization**
   - For Node.js builds: Consider using `.dockerignore` to exclude unnecessary files
   - Set Docker build cache limits to prevent memory exhaustion
   - Example: `--build-arg BUILDKIT_STEP_LOG_MAX_SIZE=-1` to disable step logging

3. **Storage Optimization**
   - Ample space for persistent BuildKit cache at `/var/lib/buildkit/cache`
   - Recommended cache size: 50-100 GB for active development

4. **Network Optimization** (if WSL2 is the bottleneck)
   - WSL2 may have network overhead; consider using local Docker Desktop cache if available

5. **GPU Optimization**
   - Use NVIDIA Container Toolkit for GPU-accelerated builds
   - Pin to specific CUDA versions for reproducibility
   - Use multi-stage builds to separate GPU-dependent layers
   - Pre-warm GPU by running lightweight containers before builds
   - Monitor GPU memory: `nvidia-smi --query-gpu=memory.used,memory.free --format=csv`

## GitHub Actions Runner Status

| Property | Value |
|----------|-------|
| **Status** | Self-hosted runner (configuration not found in standard location) |
| **Platform** | Ubuntu 22.04.5 LTS on WSL2 |
| **GPU Available** | Yes (RTX 2050 with NVIDIA Container Toolkit) |

## GPU Optimization Recommendations

### For Docker Builds with GPU Support
- Use `--gpus all` flag to enable GPU access in containers
- Build CUDA-enabled images: `FROM nvidia/cuda:12.x-devel-ubuntu22.04`
- Set `NVIDIA_VISIBLE_DEVICES` to control GPU access
- Monitor GPU memory usage with `nvidia-smi` during builds

### For AI/ML Workflows
- Available compute capability: 8.6 (supports CUDA 8.0 - 13.x)
- Sufficient VRAM (4GB) for inference and small training workloads
- Consider using TensorRT for optimized inference
- Use `--shm-size` to increase shared memory for data loaders

### CI/CD GPU Utilization
- Use GPU runners only for workflows requiring GPU (inference, training)
- Tag GPU runners: `self-hosted gpu` for workflow targeting
- Example workflow label: `runs-on: [self-hosted, gpu]`

---

*Last Updated: 2026-01-12*
