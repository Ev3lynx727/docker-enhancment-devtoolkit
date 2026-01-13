# DevOps Setup Documentation

## Overview

This directory contains comprehensive documentation for the DevOps setup and orchestration system.

**Version:** 4.0  
**Last Updated:** 2025-01-12

---

## Quick Start

### Full Setup with TUI (Recommended)

```bash
cd /home/ev3lynx/guide
cp .env.example .env
nano .env  # Edit with your credentials
go run main.go  # Or: sudo go run main.go
```

### Manual Setup

See [introduction.md](introduction.md) for detailed step-by-step instructions.

---

## Documentation Files

| File | Purpose | Last Updated |
|------|---------|--------------|
| [README.md](README.md) | This file - documentation index | 2025-01-12 |
| [introduction.md](introduction.md) | DevOps team guide & architecture overview | 2025-01-12 |
| [ghcr-auth-troubleshooting.md](ghcr-auth-troubleshooting.md) | GHCR authentication troubleshooting | 2025-01-12 |
| [spec-overview.md](spec-overview.md) | VM hardware specifications | 2025-01-12 |
| [enhancment-docker-builder.md](enhancment-docker-builder.md) | Docker daemon configuration guide | 2025-01-12 |

---

## Project Structure

```
guide/
├── main.go                          ← TUI orchestration script (Go)
├── .env                            ← Environment configuration
├── .env.example                    ← Template
├── implement-with-go.md             ← TUI implementation spec
├── logs/                           ← Setup logs
├── script/                         ← CENTRALIZED SCRIPTS
│   ├── loginall.sh
│   ├── logoutall.sh
│   ├── enhancment-docker-builder.sh
│   └── restore-default-config.sh
├── backup/
│   └── config/                    ← Configuration backups
└── docs/                           ← This directory
    ├── README.md                   ← This file
    └── ...
```

---

## Scripts Reference

### main.go (Go Orchestration)

Text User Interface (TUI) application for orchestrating all setup phases.

```bash
go run main.go                    # Run all phases
go run main.go --verbose          # Verbose output
go run main.go --dry-run          # Preview without executing
go run main.go --logout           # Logout mode
sudo go run main.go               # Auto-restart Docker
```

### script/loginall.sh

Authenticates to all registries:
- GitHub Container Registry (GHCR)
- Docker Hub (optional)
- Google Container Registry (GCR)
- GitHub CLI

```bash
./script/loginall.sh
```

### script/logoutall.sh

Logs out from all registries and optionally cleans caches:

```bash
./script/logoutall.sh              # Basic logout
./script/logoutall.sh --clean-cache  # + clean build cache
./script/logoutall.sh --clean-all    # + clean everything
```

### script/enhancment-docker-builder.sh

Configures Docker daemon with optimized BuildKit settings:

```bash
sudo ./script/enhancment-docker-builder.sh       # Interactive
sudo ./script/enhancment-docker-builder.sh --yes  # Non-interactive
```

### script/restore-default-config.sh

Restores Docker daemon to default settings:

```bash
sudo ./script/restore-default-config.sh
```

---

## Configuration

### Environment Variables (.env)

```bash
# Authentication (Required)
GITHUB_USERNAME=your_github_username
GITHUB_TOKEN=ghp_your_github_pat

# Docker Hub (Optional)
DOCKER_USERNAME=your_dockerhub_username
DOCKER_PASSWORD=your_dockerhub_token

# Docker Configuration
DEPLOYMENT_MODE=production       # production or staging
CONTAINER_NAME=app-prod
PORT=80
IMAGE_NAME=ghcr.io/your-org/repo:latest
AUTO_DEPLOY=false
CRON_INTERVAL="*/5 * * * *"

# Script Options
DOCKER_AUTO_RESTART=true
VERIFICATION_ENABLED=true
VERBOSE=false
DRY_RUN=false
```

---

## Architecture

### Cloud-Native CI/CD (v4.0)

```
┌─────────────────────────────────────────┐
│      GitHub Cloud Runners              │
│  ┌───────────────────────────────────┐  │
│  │  GitHub Actions (Cloud)          │  │
│  │  - Builds images on cloud       │  │
│  │  - Uses GitHub Actions cache     │  │
│  │  - Pushes to GHCR              │  │
│  └──────────────────────┬──────────┘  │
└───────────────────────────│─────────────┘
                          │ Pull images
                          │
┌───────────────────────────▼─────────────┐
│         DevOps Team VM                  │
│  ┌───────────────────────────────────┐  │
│  │  Pull-and-Deploy Scripts       │  │
│  │  - Auto-deploy (cron)         │  │
│  │  - Health checks               │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │  Docker Daemon (Pull-only)      │  │
│  │  - Low resource usage           │  │
│  │  - Deployment target           │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

### Key Changes from v3.0

| Feature | v3.0 | v4.0 |
|---------|-------|-------|
| Script Location | `setup-account/` and `script/` | Centralized in `script/` |
| Configuration | Multiple locations | Single `.env` file |
| Interactive | Scripts prompt individually | TUI with clickable interface |
| Docker Config | Script prompts | Configured via `.env` |
| Automation | Manual script execution | Go orchestration |

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Authentication fails | Check PAT scopes, see [ghcr-auth-troubleshooting.md](ghcr-auth-troubleshooting.md) |
| Docker won't start | Check daemon.json: `sudo journalctl -u docker` |
| Permission denied | Run with sudo: `sudo go run main.go` |
| Script not found | Verify you're in `/home/ev3lynx/guide` |

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

## Maintenance

### Regular Tasks

| Task | Frequency | Command |
|------|-----------|----------|
| Rotate PATs | Every 90 days | Create new PAT in GitHub settings |
| Check disk usage | Weekly | `docker system df` |
| Prune unused resources | Monthly | `docker system prune -a` |
| Review logs | Weekly | `ls -lh logs/` |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-01-12 | Initial documentation structure |
| 2.0 | 2025-01-12 | Added GHCR troubleshooting guide |
| 3.0 | 2025-01-12 | Updated for cloud-native architecture |
| 4.0 | 2025-01-12 | Centralized scripts, added TUI, non-interactive mode |

---

## Additional Resources

- [Parent README](../README.md) - Complete project documentation
- [Overview](../overview.md) - Detailed architecture documentation
- [implement-with-go.md](../implement-with-go.md) - TUI implementation spec
- [CHANGELOG.md](../CHANGELOG.md) - Version history

---

**Last Updated:** 2025-01-12  
**Maintained by:** DevOps Team
