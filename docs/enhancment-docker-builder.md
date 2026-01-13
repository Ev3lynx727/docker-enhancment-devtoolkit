# Docker Builder Enhancement Guide

## Table of Contents

1. [Overview](#overview)
2. [Current Architecture Analysis](#current-architecture-analysis)
3. [Problem Identification](#problem-identification)
4. [Builder Research & Comparison](#builder-research--comparison)
5. [Recommended Solution](#recommended-solution)
6. [Optional Enhancement: Docker Buildx](#optional-enhancement-docker-buildx)
7. [Implementation Steps](#implementation-steps)
8. [Configuration Examples](#configuration-examples)
9. [Verification & Testing](#verification--testing)
10. [Troubleshooting](#troubleshooting)
11. [Best Practices](#best-practices)

---

## Overview

This guide provides a comprehensive approach to optimizing Docker builds in a CI/CD environment with VM-based GitHub Actions runners and GitHub Container Registry (GHCR).

### Goals

- Reduce build times significantly
- Improve reliability of image pulls
- Optimize layer caching
- Minimize network dependencies
- Maintain security and compliance

---

## Current Architecture Analysis

### Infrastructure Stack

```
┌─────────────────┐
│   GitHub Repo   │
└────────┬────────┘
         │ Triggers
         ▼
┌─────────────────┐     ┌─────────────────┐
│  GitHub Actions │────▶│   Self-Hosted   │
│   Workflow      │     │   VM Runner     │
└─────────────────┘     └────────┬────────┘
                                 │ Builds
                                 ▼
                          ┌─────────────┐
                          │    Docker   │
                          │  BuildKit   │
                          └──────┬──────┘
                                 │ Pushes
                                 ▼
                          ┌─────────────┐
                          │     GHCR    │
                          │  Registry   │
                          └─────────────┘
```

### Current Configuration

| Component | Specification |
|-----------|---------------|
| CI/CD Platform | GitHub Actions |
| Runner Type | Self-hosted VM |
| Container Registry | GitHub Container Registry (GHCR) |
| Architecture | amd64 |
| Builder | Docker BuildKit (default) |
| Network Issue | Slow internet connection affecting pulls |

---

## Problem Identification

### Primary Issues

1. **Slow Build Times**
   - Base image pulls take excessive time
   - Package downloads (apt, npm, pip) are slow
   - Layer pulls from GHCR are delayed

2. **Network Latency**
   - Remote registry access over poor connection
   - Repeated downloads of same layers
   - No local caching mechanism

3. **Resource Utilization**
   - Inefficient cache invalidation
   - No persistent build cache across runs
   - Suboptimal layer ordering

### Root Cause Analysis

The VM's internet connection struggles to efficiently pull remote Docker images and packages, causing:
- Extended build times during CI/CD runs
- Increased failure rates due to timeouts
- Wasted bandwidth on repeated identical downloads

---

## Builder Research & Comparison

### BuildKit (Recommended ✓)

**Pros:**
- Built into Docker since 23.0+ (no additional setup)
- Advanced layer caching
- Parallel build execution
- Registry mirror support
- Secure build secrets
- Multi-platform builds
- Extensive community support

**Cons:**
- Requires Docker installation
- Limited to Docker ecosystem

### Buildah

**Pros:**
- Daemonless builds
- Podman compatible
- Supports custom base images
- Scriptable CLI

**Cons:**
- Steeper learning curve
- Less mature caching than BuildKit
- Requires additional setup
- Limited GitHub Actions integration

### Kaniko

**Pros:**
- Runs in unprivileged containers
- Kubernetes native
- No Docker daemon required
- Good for cloud-native setups

**Cons:**
- Not optimal for VM runners
- Limited caching options
- More complex configuration
- Slower than BuildKit for simple builds

### DockerSlim

**Pros:**
- Reduces image size significantly
- Analyzes dependencies
- Removes unused files

**Cons:**
- Post-processor, not a replacement
- Can introduce runtime issues
- Requires testing after optimization
- Adds build step

---

## Recommended Solution

### Architecture: BuildKit + Registry Mirror + Persistent Cache

```
┌─────────────────────────────────────────────────────┐
│                    CI/CD Workflow                    │
└────────────────────────┬────────────────────────────┘
                         │
        ┌────────────────┴────────────────┐
        │                                 │
        ▼                                 ▼
┌─────────────────┐              ┌─────────────────┐
│  Layer Cache    │◀─────────────│  GitHub Actions │
│  (Persistent)   │  Cache Reuse │  GitHub Cache   │
└────────┬────────┘              └─────────────────┘
         │
         ▼
┌─────────────────┐              ┌─────────────────┐
│  Local Mirror   │◀─────────────│   BuildKit      │
│  (Base Images)  │   Pull From   │   Builder       │
└────────┬────────┘              └────────┬────────┘
         │                                │
         ▼                                ▼
┌─────────────────┐              ┌─────────────────┐
│  GHCR Registry  │              │  Final Image    │
│  (Upstream)     │──────────────▶│  Pushed to GHCR │
└─────────────────┘              └─────────────────┘
```

### Why This Approach?

1. **BuildKit**: Already available, best-in-class caching
2. **Local Mirror**: Pre-pull base images to eliminate network dependency
3. **Persistent Cache**: Store layers locally across builds
4. **GitHub Actions Cache**: Share cache between workflow runs

---

## Optional Enhancement: Docker Buildx

### Overview

Docker Buildx is an extended Docker CLI with build capabilities that provide access to features not available in the standard `docker build` command. Buildx is the next-generation builder for Docker and supports:

- Multi-platform builds (amd64, arm64, arm/v7, etc.)
- Multiple builder instances (docker, kubernetes, remote)
- GPU-enabled builders for CUDA-enabled builds
- Advanced cache management
- Distributed builds across multiple workers
- Better integration with BuildKit features

### Buildx vs Standard BuildKit

| Feature | Standard BuildKit | Docker Buildx |
|---------|-------------------|---------------|
| Single Platform | Yes | Yes |
| Multi-Platform | No | Yes |
| GPU Builder Support | Limited | Full (Buildx v0.22+) |
| Builder Instances | Default only | Multiple builders |
| Remote Builder | No | Yes |
| CDI Support | Limited | Full |
| Cache Import/Export | Basic | Advanced |

### When to Use Buildx

Use Docker Buildx if you need:

- **Multi-platform images**: Build for amd64, arm64, Apple Silicon simultaneously
- **GPU-accelerated builds**: Compile CUDA code or run GPU tests during build
- **Remote builders**: Distribute builds across multiple machines
- **Advanced caching**: Cross-runner cache sharing with registry caching
- **Better CI/CD integration**: More control over builder configuration

### Buildx Setup

#### Install Buildx (Docker 23.0+ includes it by default)

Verify Buildx is installed:

```bash
docker buildx version
```

Expected output: `github.com/docker/buildx v0.x.x`

#### Create a Custom Builder

Create a builder with specific settings:

```bash
# Create a new builder instance
docker buildx create \
  --name my-builder \
  --driver docker-container \
  --bootstrap \
  --buildkitd-flags '--allow-insecure-entitlement=security.insecure' \
  --use

# Verify builder
docker buildx inspect --bootstrap

# List all builders
docker buildx ls
```

#### Create a GPU-Enabled Builder

For builds requiring GPU access (CUDA compilation, GPU testing):

```bash
# Create GPU-enabled builder (Buildx v0.22+)
docker buildx create \
  --name gpu-builder \
  --driver docker-container \
  --buildkitd-flags '--allow-insecure-entitlement=security.insecure' \
  --use

# Or use the official GPU-enabled buildkit image
docker buildx create \
  --name gpu-builder \
  --driver-opt image=moby/buildkit:buildx-stable-1-gpu \
  --use
```

Note: GPU builds require `--security=insecure` flag in Dockerfile steps that access GPU.

#### Create a Multi-Platform Builder

```bash
# Create builder for cross-platform builds
docker buildx create \
  --name multi-platform-builder \
  --platform linux/amd64,linux/arm64 \
  --use
```

### Buildx Configuration

#### Configure Buildx with CDI (Container Device Interface)

Add CDI configuration to `/etc/docker/daemon.json` for GPU support:

```json
{
  "features": {
    "cdi": "enabled"
  }
}
```

Restart Docker:

```bash
sudo systemctl restart docker
```

#### Builder Instance Configuration

View builder details:

```bash
docker buildx inspect my-builder --bootstrap
```

Set default builder:

```bash
docker buildx use my-builder
```

### Multi-Platform Builds

#### Build for Multiple Platforms

```bash
# Build for multiple architectures
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  -t ghcr.io/${{ github.repository }}:latest \
  .
```

#### Use QEMU for Emulation

Enable QEMU for cross-platform emulation:

```bash
# Install QEMU (if not available)
docker run --rm --privileged tonistiigi/binfmt:install

# Build with emulation
docker buildx build \
  --platform linux/amd64,linux/arm64,linux/arm/v7 \
  --push \
  -t ghcr.io/${{ github.repository }}:multiarch \
  .
```

### GPU-Enabled Builds with Buildx

#### Dockerfile with GPU Support

```dockerfile
# syntax=docker/dockerfile:1.5

FROM nvidia/cuda:12.2.0-devel-ubuntu22.04 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY . /app
WORKDIR /app

# Build with GPU access (requires --security=insecure flag)
RUN --security=insecure nvidia-smi

# Compile CUDA code
RUN --security=insecure make

# Runtime stage
FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04

COPY --from=builder /app/build /app/build

WORKDIR /app
CMD ["./build/application"]
```

#### Build with GPU

```bash
# Build with GPU builder
docker buildx build \
  --builder gpu-builder \
  --security=insecure \
  -t my-cuda-app:latest \
  .
```

### GitHub Actions with Buildx

#### Basic Buildx Workflow

```yaml
name: Docker Buildx Build

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: self-hosted
    
    steps:
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
        with:
          driver-opts: |
            image=moby/buildkit:latest
            network=host
      
      - name: Cache Docker layers
        uses: actions/cache@v3
        with:
          path: /tmp/.buildx-cache
          key: ${{ runner.os }}-buildx-${{ hashFiles('**/Dockerfile') }}
          restore-keys: |
            ${{ runner.os }}-buildx-
      
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ghcr.io/${{ github.repository }}:latest
            ghcr.io/${{ github.repository }}:${{ github.sha }}
          cache-from: type=local,src=/tmp/.buildx-cache
          cache-to: type=local,dest=/tmp/.buildx-cache,mode=max
          platforms: linux/amd64
```

#### Multi-Platform Buildx Workflow

```yaml
name: Multi-Platform Build

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: self-hosted
    
    steps:
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v2
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Cache Buildx cache
        uses: actions/cache@v3
        with:
          path: /tmp/.buildx-cache
          key: ${{ runner.os }}-buildx-${{ hashFiles('**/Dockerfile') }}
      
      - name: Login to GHCR
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Build and push multi-platform
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ghcr.io/${{ github.repository }}:latest
            ghcr.io/${{ github.repository }}:${{ github.sha }}
          platforms: linux/amd64,linux/arm64
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

#### GPU-Enabled Buildx Workflow

```yaml
name: GPU Build

on:
  push:
    branches: [ main ]

jobs:
  gpu-build:
    runs-on: [self-hosted, gpu]
    
    steps:
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
        with:
          driver-opts: |
            image=moby/buildkit:buildx-stable-1-gpu
            network=host
      
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Build with GPU
        run: |
          docker buildx build \
            --builder gpu-builder \
            --load \
            --security=insecure \
            -t my-cuda-app:${{ github.sha }} \
            .
      
      - name: Test GPU access
        run: |
          docker run --rm --gpus all my-cuda-app:${{ github.sha }} nvidia-smi
```

### Buildx Cache Strategies

#### Local Cache

```bash
docker buildx build \
  --cache-from type=local,src=/path/to/cache \
  --cache-to type=local,dest=/path/to/cache,mode=max \
  -t myapp:latest \
  .
```

#### Registry Cache

```bash
docker buildx build \
  --cache-from type=registry,ref=ghcr.io/${{ github.repository }}/cache:latest \
  --cache-to type=registry,ref=ghcr.io/${{ github.repository }}/cache:latest,mode=max \
  -t ghcr.io/${{ github.repository }}:latest \
  .
```

#### GitHub Actions Cache

```bash
docker buildx build \
  --cache-from type=gha \
  --cache-to type=gha,mode=max \
  -t myapp:latest \
  .
```

#### Inline Cache

```bash
docker buildx build \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  --cache-from ghcr.io/${{ github.repository }}:latest \
  -t ghcr.io/${{ github.repository }}:newtag \
  .
```

### Buildx Best Practices

1. **Use Buildx for multi-platform builds**: Leverage QEMU for emulation
2. **Create separate builders**: One for standard builds, one for GPU builds
3. **Use registry caching**: Share cache across multiple runners
4. **Test GPU builds locally**: Verify GPU access before CI/CD
5. **Monitor build times**: Buildx may have overhead for single-platform builds
6. **Use appropriate cache type**: Local for speed, registry for sharing

### Buildx vs Standard BuildKit: When to Choose What

| Scenario | Recommended Approach |
|----------|---------------------|
| Simple single-platform builds | Standard BuildKit (`docker build`) |
| Multi-platform images | Buildx (`docker buildx`) |
| GPU compilation during build | Buildx with GPU builder |
| Cross-runner cache sharing | Buildx with registry cache |
| Local development | Standard BuildKit (faster) |
| CI/CD with multiple platforms | Buildx |

---

## Implementation Steps

### Step 1: Verify BuildKit and Buildx Installation

Check if BuildKit is enabled:

```bash
docker version
```

Look for `BuildKit: true` in the output.

Check if Buildx is available:

```bash
docker buildx version
```

Expected output: `github.com/docker/buildx v0.x.x`

### Step 1a (Optional): Set Up Docker Buildx

If you need multi-platform builds, GPU-accelerated builds, or advanced caching:

```bash
# Create a custom builder
docker buildx create \
  --name my-builder \
  --driver docker-container \
  --bootstrap \
  --use

# Verify builder
docker buildx inspect --bootstrap

# For GPU-enabled builds
docker buildx create \
  --name gpu-builder \
  --driver-opt image=moby/buildkit:buildx-stable-1-gpu \
  --use
```

### Step 2: Set Up BuildKit Configuration

Enable BuildKit if needed:

```bash
export DOCKER_BUILDKIT=1
```

### Step 2: Set Up BuildKit Configuration

Create directory structure:

```bash
sudo mkdir -p /etc/docker
```

Create or edit `/etc/docker/daemon.json`:

```json
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "10GB"
    }
  },
  "features": {
    "containerd-snapshotter": false
  },
  "registry-mirrors": [],
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10
}
```

Restart Docker:

```bash
sudo systemctl restart docker
```

### Step 3: Pre-pull Base Images

Identify your base images and pre-pull them:

```bash
docker pull node:18-alpine
docker pull node:20-alpine
docker pull python:3.11-slim
docker pull nginx:alpine

# Verify images
docker images
```

### Step 4: Configure BuildKit Cache

Set up cache directories:

```bash
sudo mkdir -p /var/lib/buildkit/cache
sudo chown -R runner:runner /var/lib/buildkit/cache
```

### Step 5: Configure GitHub Actions Cache

In your GitHub Actions workflow file:

```yaml
name: Docker Build and Push

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: self-hosted
    
    steps:
      - name: Cache Docker layers
        uses: actions/cache@v3
        with:
          path: /var/lib/buildkit/cache
          key: ${{ runner.os }}-docker-${{ hashFiles('**/Dockerfile') }}
          restore-keys: |
            ${{ runner.os }}-docker-
      
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Build with BuildKit
        run: |
          docker build \
            --build-arg BUILDKIT_INLINE_CACHE=1 \
            --cache-from type=local,src=/var/lib/buildkit/cache \
            --cache-to type=local,dest=/var/lib/buildkit/cache,mode=max \
            -t ghcr.io/${{ github.repository }}:latest \
            .
      
      - name: Push to GHCR
        run: |
          echo ${{ secrets.GITHUB_TOKEN }} | docker login ghcr.io -u ${{ github.actor }} --password-stdin
          docker push ghcr.io/${{ github.repository }}:latest
```

### Step 6: Optimize Dockerfile for Caching

Key principles:

**DO:**
```dockerfile
FROM node:18-alpine

# Install dependencies first (less likely to change)
COPY package*.json ./
RUN npm ci --only=production

# Copy source code (more likely to change)
COPY . .

# Build application
RUN npm run build

# Final stage
CMD ["npm", "start"]
```

**DON'T:**
```dockerfile
FROM node:18-alpine

# Copy everything first
COPY . .

# Install dependencies
RUN npm ci

# This invalidates cache on ANY file change
```

### Step 7: Set Up Registry Mirror (Optional but Recommended)

For production deployments, set up a local registry mirror:

```json
{
  "registry-mirrors": [
    "https://your-local-mirror.example.com"
  ]
}
```

Or use a pull-through cache registry like:
- **Docker Registry** with nginx proxy
- **Harbor**
- **Nexus Repository**
- **AWS ECR Public Gallery** (if in AWS)

---

## Configuration Examples

### Example 1: Simple Node.js Application

**Dockerfile:**

```dockerfile
FROM node:18-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .
RUN npm run build

FROM node:18-alpine

WORKDIR /app

COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist

EXPOSE 3000

CMD ["node", "dist/index.js"]
```

**GitHub Actions Workflow:**

```yaml
name: Build and Deploy

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: self-hosted
    
    steps:
      - name: Cache Docker layers
        uses: actions/cache@v3
        with:
          path: /var/lib/buildkit/cache
          key: docker-${{ hashFiles('Dockerfile', 'package*.json') }}
          restore-keys: docker-
      
      - uses: actions/checkout@v3
      
      - name: Build image
        run: |
          docker build \
            --build-arg BUILDKIT_INLINE_CACHE=1 \
            --cache-from type=local,src=/var/lib/buildkit/cache \
            --cache-to type=local,dest=/var/lib/buildkit/cache,mode=max \
            -t myapp:${{ github.sha }} \
            -t myapp:latest \
            .
      
      - name: Log in to GHCR
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Push images
        run: |
          docker tag myapp:${{ github.sha }} ghcr.io/${{ github.repository }}:${{ github.sha }}
          docker tag myapp:latest ghcr.io/${{ github.repository }}:latest
          docker push ghcr.io/${{ github.repository }}:${{ github.sha }}
          docker push ghcr.io/${{ github.repository }}:latest
```

### Example 2: Multi-stage Python Application

**Dockerfile:**

```dockerfile
FROM python:3.11-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --user -r requirements.txt

COPY . .
RUN python -m py_compile src/*.py

FROM python:3.11-slim

WORKDIR /app

COPY --from=builder /root/.local /root/.local
COPY --from=builder /app /app

ENV PATH=/root/.local/bin:$PATH

CMD ["python", "src/main.py"]
```

### Example 3: Advanced BuildKit Features

```dockerfile
# syntax=docker/dockerfile:1.5

FROM node:18-alpine AS base

# Mount cache for npm packages
RUN --mount=type=cache,target=/root/.npm \
    npm install -g pnpm

WORKDIR /app

FROM base AS deps

COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,target=/root/.npm \
    pnpm install --frozen-lockfile

FROM base AS build

COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN --mount=type=cache,target=/root/.npm \
    pnpm run build

FROM node:18-alpine AS runtime

WORKDIR /app

ENV NODE_ENV=production

COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./

EXPOSE 3000

CMD ["node", "dist/index.js"]
```

---

## Verification & Testing

### Test 1: Verify BuildKit is Active

```bash
docker build --progress=plain .
```

Look for BuildKit logs (not legacy builder output).

### Test 2: Test Cache Reuse

```bash
# First build (should be slower)
time docker build -t test:1 .

# Touch a file
touch README.md

# Second build (should be faster due to cache)
time docker build -t test:2 .
```

### Test 3: Check Cache Size

```bash
du -sh /var/lib/buildkit/cache
```

### Test 4: Verify GitHub Actions Cache

Check Actions tab in GitHub repository:
1. Go to repository
2. Click "Actions"
3. Click "Caches"
4. Verify cache entries exist

### Test 5: Test Pull from Cache

```bash
docker build \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  --cache-from type=local,src=/var/lib/buildkit/cache \
  -t test:cached \
  .
```

Monitor build output for "CACHED" layers.

---

## Troubleshooting

### Issue: BuildKit not enabled

**Symptom:** Builds use legacy builder

**Solution:**

```bash
export DOCKER_BUILDKIT=1
# Or add to ~/.bashrc
echo 'export DOCKER_BUILDKIT=1' >> ~/.bashrc
```

### Issue: Cache not persisting

**Symptom:** Every build is slow

**Solution:**

1. Check cache directory permissions:

```bash
ls -la /var/lib/buildkit/cache
```

2. Ensure runner has write access:

```bash
sudo chown -R runner:runner /var/lib/buildkit/cache
```

3. Verify cache is being written:

```bash
docker build --progress=plain -t test . 2>&1 | grep -i cache
```

### Issue: GitHub Actions cache not restoring

**Symptom:** Cache misses in Actions

**Solution:**

1. Verify cache key is correct
2. Check if cache size exceeds GitHub's 10GB limit
3. Ensure path matches exactly between save and restore

### Issue: Pull timeouts

**Symptom:** `Error: context deadline exceeded`

**Solution:**

Increase timeout in daemon.json:

```json
{
  "max-concurrent-downloads": 5,
  "max-concurrent-uploads": 5
}
```

Or set per-build timeout:

```bash
docker build --timeout 7200s -t test .
```

### Issue: Disk space filling up

**Symptom:** `no space left on device`

**Solution:**

1. Clean unused images:

```bash
docker image prune -a
```

2. Configure BuildKit GC in daemon.json:

```json
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "5GB"
    }
  }
}
```

3. Restart Docker:

```bash
sudo systemctl restart docker
```

---

## Best Practices

### 1. Layer Ordering

Order Dockerfile instructions from least to most frequently changed:

```dockerfile
# 1. Base image (rarely changes)
FROM node:18-alpine

# 2. System dependencies (rarely changes)
RUN apk add --no-cache git

# 3. Dependencies files (occasionally changes)
COPY package*.json ./
RUN npm ci --only=production

# 4. Application code (frequently changes)
COPY . .

# 5. Build command (every change)
RUN npm run build
```

### 2. Use Multi-stage Builds

Reduce final image size:

```dockerfile
FROM node:18-alpine AS builder
# Build steps here

FROM node:18-alpine
COPY --from=builder /app/dist ./dist
# Only copy what's needed
```

### 3. Leverage BuildKit Cache Mounts

Speed up package installation:

```dockerfile
RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache git

RUN --mount=type=cache,target=/root/.npm \
    npm install

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
```

### 4. Use .dockerignore

Exclude unnecessary files:

```
node_modules
.git
.env
*.log
coverage
dist
```

### 5. Tag Images Strategically

Use semantic versioning:

```bash
docker build -t app:1.0.0 -t app:latest .
docker push app:1.0.0
docker push app:latest
```

### 6. Monitor Build Performance

Track build times:

```yaml
- name: Build image
  id: build
  run: |
    START=$(date +%s)
    docker build -t app:${{ github.sha }} .
    END=$(date +%s)
    echo "duration=$((END - START))" >> $GITHUB_OUTPUT
```

### 7. Regular Maintenance

Set up cron job for cleanup:

```bash
# Run weekly cleanup
0 3 * * 0 docker system prune -f --volumes
```

### 8. Security Scanning

Integrate security scans:

```yaml
- name: Scan image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ghcr.io/${{ github.repository }}:latest
    format: 'sarif'
    output: 'trivy-results.sarif'
```

---

## Next Steps

### Immediate Actions

1. [ ] Verify BuildKit installation on VM
2. [ ] Configure Docker daemon with recommended settings
3. [ ] Pre-pull frequently used base images
4. [ ] Set up persistent cache directory
5. [ ] Update GitHub Actions workflow with cache steps
6. [ ] Optimize Dockerfiles for better caching
7. [ ] Test cache effectiveness
8. [ ] Monitor build times

### Optional: Docker Buildx Setup

- [ ] Evaluate if multi-platform or GPU builds are needed
- [ ] Set up Docker Buildx builder instance
- [ ] Configure GPU-enabled builder if compiling CUDA code
- [ ] Test Buildx with multi-platform builds (if needed)
- [ ] Update GitHub Actions workflows to use Buildx (if chosen)

### Future Enhancements

- Consider setting up local registry mirror for base images
- Implement multi-platform builds with Buildx
- Add GPU-accelerated builds for AI/ML workloads
- Add automated security scanning
- Set up image signing for production
- Implement canary deployments

---

## Resources

### Official Documentation

- [Docker BuildKit](https://docs.docker.com/build/buildkit/)
- [Docker Buildx](https://docs.docker.com/buildx/working-with-buildx/)
- [Buildx Multi-platform Builds](https://docs.docker.com/build/building/multi-platform/)
- [Container Device Interface (CDI)](https://docs.docker.com/build/building/cdi/)
- [GitHub Actions Cache](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

### Useful Tools

- [dive](https://github.com/wagoodman/dive) - Docker image analyzer
- [Trivy](https://github.com/aquasecurity/trivy) - Security scanner
- [slim](https://github.com/slimtoolkit/slim) - Image optimizer

### Community Resources

- [Dockerfile Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [BuildKit Examples](https://github.com/moby/buildkit/tree/master/frontend/dockerfile/docs/experimental)

---

**Document Version:** 1.1  
**Last Updated:** January 12, 2026  
**Maintainer:** DevOps Team
