# Current Docker BuildKit and Buildx Configuration

## Date: 2026-01-12

---

## Docker BuildKit Status

| Property | Current Value |
|----------|---------------|
| **BuildKit Version** | v0.26.2 |
| **Status** | Enabled and Active |
| **Driver** | overlayfs |
| **Cgroup Driver** | systemd |

---

## Docker Buildx Status

| Property | Current Value |
|----------|---------------|
| **Buildx Version** | v0.30.1 |
| **Active Builder** | default (docker driver) |
| **Builder Status** | running |
| **Last Activity** | 2026-01-09 11:59:50 UTC |

---

## Available Builders

| Name | Driver | Status | Platforms |
|------|--------|--------|-----------|
| default | docker | running | linux/amd64, linux/amd64/v2, linux/amd64/v3 |

---

## BuildKit Worker Configuration

### Node: default

| Property | Value |
|----------|-------|
| **Executor** | containerd |
| **Network** | host |
| **Snapshotter** | overlayfs |
| **Hostname** | DESKTOP-VQN0VVJ |
| **Containerd Namespace** | moby |

---

## BuildKit Garbage Collection Policy

| Rule | All | Keep Duration | Max Used Space | Min Free Space | Reserved Space | Filters |
|------|-----|---------------|----------------|----------------|----------------|---------|
| 0 | No | 48h | 13GiB | - | - | type==source.local,type==exec.cachemount,type==source.git.checkout |
| 1 | No | 1440h (60 days) | 750.6GiB | 188.1GiB | 94.06GiB | - |
| 2 | No | - | 750.6GiB | 188.1GiB | 94.06GiB | - |
| 3 | Yes | - | 750.6GiB | 188.1GiB | 94.06GiB | - |

---

## Docker Daemon Configuration

### `/etc/docker/daemon.json`

```json
{
    "runtimes": {
        "nvidia": {
            "args": [],
            "path": "nvidia-container-runtime"
        }
    }
}
```

### Configuration Summary

| Setting | Current Value |
|---------|---------------|
| **NVIDIA Runtime** | Configured and available |
| **Registry Mirrors** | Not configured |
| **Insecure Registries** | None |

---

## Docker Storage Usage

| Type | Total | Active | Size | Reclaimable |
|------|-------|--------|------|-------------|
| Images | 23 | 12 | 43.79GB | 21.94GB (50%) |
| Containers | 12 | 6 | 224.2MB | 71.83MB (32%) |
| Local Volumes | 23 | 7 | 16.37GB | 358.8MB (2%) |
| **Build Cache** | 52 | 0 | **1.032GB** | **1.028GB (99%)** |

---

## BuildKit Cache Status

| Property | Status |
|----------|--------|
| **Persistent Cache Directory** | `/var/lib/buildkit/` - Not configured |
| **Docker Build Cache** | 1.032GB (52 cache entries) |
| **Reclaimable Cache** | 1.028GB (99%) |

---

## GPU Configuration

| Property | Status |
|----------|--------|
| **NVIDIA Container Runtime** | Configured (`nvidia-container-runtime`) |
| **GPU Builder** | Not configured |
| **CDI Support** | Not explicitly enabled |

---

## Analysis and Recommendations

### Current State

✅ **Good:**
- BuildKit is enabled and running with latest version
- Buildx is available and functional
- NVIDIA runtime is configured for GPU support
- Build cache is active (1.032GB)
- Docker storage driver is overlayfs (recommended)

⚠️ **Needs Improvement:**
- No persistent BuildKit cache directory configured
- Docker daemon.json lacks BuildKit-specific optimizations
- No registry mirrors configured (slow network issue not addressed)
- No dedicated GPU builder instance
- High cache reclaimable percentage (99% = not being used effectively)

---

## Recommended Configuration Changes

### 1. Create Persistent BuildKit Cache

```bash
sudo mkdir -p /var/lib/buildkit/cache
sudo chown -R $(whoami):$(whoami) /var/lib/buildkit/cache
```

### 2. Update Docker Daemon Configuration

Update `/etc/docker/daemon.json`:

```json
{
    "runtimes": {
        "nvidia": {
            "args": [],
            "path": "nvidia-container-runtime"
        }
    },
    "builder": {
        "gc": {
            "enabled": true,
            "defaultKeepStorage": "10GB"
        }
    },
    "features": {
        "cdi": "enabled"
    },
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 10
}
```

### 3. Restart Docker Daemon

```bash
sudo systemctl restart docker
```

### 4. Create GPU-Enabled Builder (Optional)

```bash
docker buildx create \
  --name gpu-builder \
  --driver docker-container \
  --driver-opt image=moby/buildkit:buildx-stable-1-gpu \
  --use
```

### 5. Clean Up Unused Cache

```bash
docker builder prune
```

---

## Next Steps Based on Enhancement Guide

1. **Configure persistent cache** - Create `/var/lib/buildkit/cache` directory
2. **Update daemon.json** - Add BuildKit optimizations and CDI support
3. **Restart Docker** - Apply configuration changes
4. **Pre-pull base images** - Speed up initial builds
5. **Set up registry mirror** - (Optional but recommended for slow network)
6. **Create GPU builder** - If GPU builds are needed
7. **Test cache effectiveness** - Build with cache flags
8. **Update GitHub Actions** - Add cache steps to workflows

---

## Current vs Recommended Configuration

| Setting | Current | Recommended |
|---------|---------|-------------|
| Persistent Cache | No | Yes (/var/lib/buildkit/cache) |
| Registry Mirrors | None | Configure if possible |
| CDI Support | Not enabled | Yes |
| Max Concurrent Downloads | Default (3) | 10 |
| Max Concurrent Uploads | Default (5) | 10 |
| GPU Builder | Not configured | Optional (if needed) |
| BuildKit GC | Default (751GB max) | 10GB recommended for cache management |

---

## Commands to Verify Configuration

### Check BuildKit Status
```bash
docker info | grep -A 20 "Builder:"
```

### Check Buildx Builders
```bash
docker buildx ls
docker buildx inspect --bootstrap
```

### Check Cache Usage
```bash
docker system df
docker builder du
```

### Test GPU Runtime
```bash
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi
```

---

**Document Created:** 2026-01-12  
**Configuration Snapshot:** DEV VM (DESKTOP-VQN0VVJ)
