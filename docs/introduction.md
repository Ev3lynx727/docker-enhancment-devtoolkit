# DevOps Team Introduction

## Overview

**Version:** 4.0
**Last Updated:** 2025-01-12
**Status:** Centralized Scripts, Ready for Implementation

This guide provides DevOps teams with comprehensive documentation for implementing a **cloud-native Docker build optimization architecture** using GitHub Actions and GitHub Container Registry (GHCR).

The architecture transforms traditional self-hosted runner build environments into a modern, scalable CI/CD pipeline that leverages cloud infrastructure for builds while maintaining local deployment capabilities.

---

## Architecture Summary

### Before: Self-Hosted Build Runner

```
┌─────────────────────────────────────────┐
│         DevOps Team VM                   │
│  ┌───────────────────────────────────┐  │
│  │  GitHub Actions Self-Hosted Runner│  │
│  │  - Builds Docker images locally  │  │
│  │  - Uses local cache              │  │
│  │  - Pushes to GHCR                │  │
│  └───────────────────────────────────┘  │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │  Docker Daemon                    │  │
│  │  - High resource usage           │  │
│  │  - Maintenance overhead          │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### After: Cloud-Native CI/CD

```
┌─────────────────────────────────────────┐
│      GitHub Cloud Runners               │
│  ┌───────────────────────────────────┐  │
│  │  GitHub Actions (Cloud)            │  │
│  │  - Builds images on cloud runners │  │
│  │  - Uses GitHub Actions cache      │  │
│  │  - Pushes to GHCR                 │  │
│  │  - Optional registry cache        │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
                    │
                    │ Pull images
                    │
┌─────────────────────────────────────────┐
│         DevOps Team VM                   │
│  ┌───────────────────────────────────┐  │
│  │  Deployment Scripts              │  │
│  │  - Pull-and-deploy               │  │
│  │  - Health checks                 │  │
│  │  - Auto-deploy (cron)            │  │
│  └───────────────────────────────────┘  │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │  Docker Daemon (Pull-only)       │  │
│  │  - Low resource usage            │  │
│  │  - Deployment target only         │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

---

## Purpose and Objectives

### Primary Goals

1. **Optimize Docker Build Performance**
   - Reduce build times through efficient caching
   - Minimize resource usage on local infrastructure
   - Enable scalable parallel builds

2. **Modernize CI/CD Architecture**
   - Move from self-hosted to cloud-native builds
   - Leverage GitHub Actions native cache
   - Implement secure authentication with GHCR

3. **Simplify Operations**
   - Reduce maintenance overhead
   - Automate deployment workflows
   - Improve security practices

### Benefits

| Benefit | Impact |
|---------|--------|
| **Faster builds** | Cloud resources scale on demand |
| **Reduced costs** | Only pay for actual build time |
| **Simplified maintenance** | No self-hosted runner management |
| **Better security** | GHCR with scoped PATs |
| **Scalability** | Unlimited parallel builds |
| **Reliability** | Managed infrastructure |

---

## Guide Structure

### Documentation Files

| File | Purpose |
|------|---------|
| `docs/introduction.md` | This file - overview for DevOps teams |
| `overview.md` | Complete architecture documentation (2000+ lines) |
| `ghcr-auth-troubleshooting.md` | GHCR authentication troubleshooting guide |
| `enhancment-docker-builder.md` | Docker daemon configuration enhancements |
| `implement-with-go.md` | TUI orchestration implementation guide |

### Configuration Files

| File | Purpose |
|------|---------|
| `.env` | Environment configuration (auth + Docker settings) |
| `.env.example` | Template for environment configuration |

### Centralized Scripts

| File | Purpose |
|------|---------|
| `script/loginall.sh` | Authentication to all registries |
| `script/logoutall.sh` | Logout from all registries |
| `script/enhancment-docker-builder.sh` | Docker daemon configuration |
| `script/restore-default-config.sh` | Restore default Docker config |
| `main.go` | TUI orchestration script (Go) |

### Backup Location

```
guide/backup/config/
└── daemon.json
```

---

## Quick Start for DevOps Teams

### Prerequisites

1. **GitHub Account** with appropriate permissions
2. **GitHub Container Registry (GHCR)** access
3. **DevOps Team VM** with Docker installed
4. **GitHub Actions** enabled for your repository

### Option 1: Full Setup (Recommended - with TUI)

```bash
cd /home/ev3lynx/guide

# Copy environment template
cp .env.example .env

# Edit with your credentials and Docker settings
nano .env

# Run TUI orchestration
go run main.go
# Or with sudo for Docker restart
sudo go run main.go
```

The TUI will guide you through:
- Authentication (loginall.sh)
- Docker Configuration (enhancment-docker-builder.sh)
- Verification

### Option 2: Manual Step-by-Step

```bash
cd /home/ev3lynx/guide

# Step 1: Setup .env file
cp .env.example .env
nano .env

# Step 2: Authentication
./script/loginall.sh

# Step 3: Configure Docker daemon
sudo ./script/enhancment-docker-builder.sh --yes
```

### Option 3: Individual Operations

```bash
# Authentication only
./script/loginall.sh

# Logout from all registries
./script/logoutall.sh

# Configure Docker only
sudo ./script/enhancment-docker-builder.sh

# Restore default configuration
sudo ./script/restore-default-config.sh
```

### Step 3: Verify Configuration

```bash
# Check Docker daemon status
sudo systemctl status docker.service

# Verify Docker configuration
docker info | grep -E "(max-concurrent|Storage Driver)"

# Check authentication
cat ~/.docker/config.json | jq '.auths."ghcr.io"'
```

### Verify Configuration

```bash
# Check Docker daemon status
sudo systemctl status docker.service

# Verify Docker configuration
docker info | grep -E "(max-concurrent|Storage Driver)"

# Check authentication
cat ~/.docker/config.json | jq '.auths."ghcr.io"'

# Test pull from GHCR
docker pull ghcr.io/actions/runner:latest

# Verify pull worked
docker images | grep ghcr.io
```

---

## Architecture Deep Dive

### BuildKit Configuration

The Docker daemon is configured with optimized BuildKit settings:

| Setting | Value | Benefit |
|---------|-------|---------|
| Garbage Collection | Enabled | Prevents uncontrolled growth |
| Max Cache Size | 10GB | Balances speed and disk usage |
| Concurrent Downloads | 10 | 3.3x faster than default (3) |
| Concurrent Uploads | 10 | 2x faster than default (5) |

### GitHub Actions Cache Strategy

```yaml
# Primary cache (GitHub Actions native)
cache-from: type=gha
cache-to: type=gha,mode=max

# Optional cache (registry - cross-runner)
cache-from: type=registry,ref=ghcr.io/org/repo:buildcache
cache-to: type=registry,ref=ghcr.io/org/repo:buildcache,mode=max
```

### Deployment Workflow

1. **GitHub Actions** builds image on cloud runner
2. **Image** pushed to GHCR
3. **DevOps VM** pulls image via cron or manual trigger
4. **Deployment script** manages container lifecycle
5. **Health check** verifies service availability

---

## Security Considerations

### Authentication

- Use **GitHub Personal Access Tokens (PATs)** with minimal scopes
- Rotate tokens regularly (recommended: every 90 days)
- Store credentials in `.env` files (never commit to git)
- Use `read:packages` for pull-only, `write:packages` for push

### Best Practices

| Practice | Implementation |
|----------|----------------|
| Token rotation | Set expiration on PATs |
| Scope limitation | Only grant necessary permissions |
| Credential storage | Use environment variables, not code |
| Audit logging | Monitor GHCR access logs |
| Rate limiting | Authenticate even for public images |

---

## Troubleshooting

### Common Issues

1. **GHCR Authentication Fails**
   - See `ghcr-auth-troubleshooting.md`
   - Verify PAT has correct scopes
   - Clear cached credentials

2. **Build Cache Issues**
   - Check BuildKit GC settings
   - Verify cache configuration
   - Monitor disk usage

3. **Deployment Failures**
   - Check health check endpoint
   - Verify image pulled successfully
   - Review container logs

### Quick Diagnostics

```bash
# Docker daemon status
sudo systemctl status docker.service

# Authentication status
docker login ghcr.io --dry-run

# BuildKit info
docker buildx inspect

# Container status
docker ps -a
```

---

## Scripts Reference

### Go Orchestration Script (`main.go`)

TUI-based orchestration with clickable interface. Automates all phases:

```bash
cd /home/ev3lynx/guide

# Run with TUI
go run main.go

# With auto-restart Docker
sudo go run main.go

# Skip phases
go run main.go --skip-auth
go run main.go --skip-docker
go run main.go --skip-verify

# Logout mode
go run main.go --logout
go run main.go --logout --clean-all
```

### Authentication Script (`script/loginall.sh`)

Automates authentication to:
- GitHub Container Registry (GHCR)
- Docker Hub (optional)
- GitHub CLI (optional)

```bash
cd /home/ev3lynx/guide
./script/loginall.sh
```

### Logout Script (`script/logoutall.sh`)

Logs out from all registries and optionally cleans caches:

```bash
cd /home/ev3lynx/guide
./script/logoutall.sh
./script/logoutall.sh --clean-cache
./script/logoutall.sh --clean-all
```

### Docker Daemon Configuration Script (`script/enhancment-docker-builder.sh`)

Configures Docker daemon with:
- Optimized BuildKit settings
- NVIDIA runtime support
- CDI for GPU devices
- Performance tuning
- Deployment scripts

```bash
cd /home/ev3lynx/guide/script

# Interactive mode
sudo ./enhancment-docker-builder.sh

# Non-interactive mode (reads .env)
sudo ./enhancment-docker-builder.sh --yes

# Skip authentication
sudo ./enhancment-docker-builder.sh --yes --skip-auth
```

### Restore Default Configuration (`script/restore-default-config.sh`)

Restores Docker daemon to default settings:

```bash
cd /home/ev3lynx/guide
sudo ./script/restore-default-config.sh
```

---

## Maintenance Tasks

### Regular Tasks

| Task | Frequency | Command |
|------|-----------|---------|
| Rotate PATs | Every 90 days | Create new PAT in GitHub settings |
| Check disk usage | Weekly | `docker system df` |
| Prune unused resources | Monthly | `docker system prune -a` |
| Update Docker | Quarterly | `sudo apt update && sudo apt upgrade docker-ce` |

### Monitoring

- **Build times:** Monitor GitHub Actions workflow duration
- **Cache hit rate:** Check BuildKit cache efficiency
- **Pull times:** Track image download performance
- **Resource usage:** Monitor Docker daemon CPU/memory

---

## Additional Resources

### Official Documentation

- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [GitHub Actions Cache](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows)
- [Docker BuildKit](https://github.com/moby/buildkit)
- [Docker Daemon Configuration](https://docs.docker.com/engine/reference/commandline/dockerd/)

### Related Guides

- `overview.md` - Complete architecture documentation
- `ghcr-auth-troubleshooting.md` - Authentication troubleshooting
- `enhancment-docker-builder.md` - Docker configuration details

---

## Getting Help

### Internal Resources

1. **Documentation:** Review relevant guides in `/home/ev3lynx/guide/`
2. **Scripts:** Check `script/` directory for configuration tools
3. **Examples:** Reference backup configs in `backup/config/`

### External Resources

1. **GitHub Support:** https://support.github.com/
2. **Docker Forums:** https://forums.docker.com/
3. **Stack Overflow:** Tag with `github`, `docker`, `ghcr`

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-01-12 | Initial introduction for DevOps teams |
| 2.0 | 2025-01-12 | Added centralized scripts, removed setup-account/ |
| 3.0 | 2025-01-12 | Added TUI orchestration with main.go |
| 4.0 | 2025-01-12 | Added non-interactive mode, Docker config in .env |

---

## Contact & Support

For questions or issues with this guide, contact your DevOps team or create an issue in the repository.

---

**Last Updated:** 2025-01-12
**Maintained by:** DevOps Team
