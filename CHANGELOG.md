# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Planned
- Implement `main.go` functions (`loadConfig`, `executeScript`, `autoRestartDocker`, `verifySetup`, `printSummary`)
- Create GitHub Actions workflow (`.github/workflows/docker-build.yml`)
- Implement deployment scripts (`pull-and-deploy.sh`, `health-check.sh`)
- Configure auto-deploy cron job for staging

### Added
- Created comprehensive `README.md` with project overview and quick start guide
- Created `docs/introduction.md` for DevOps team onboarding
- Created `DOCUMENTATION_UPDATE_SUMMARY.md` for tracking documentation changes
- Created `setup-account/logoutall.sh` v2.0 with security cleanup features:
  - Support for multiple registries (GHCR, GCR, Docker Hub)
  - Build cache cleanup (`--clean-cache` flag)
  - GitHub CLI cleanup (`--clean-gh-cli` flag)
  - Temporary files cleanup (`--clean-all` flag)
  - Dry-run mode (`--dry-run` flag)
  - Verbose output (`--verbose` flag)
  - Force mode (`--force` flag)
  - Help system (`--help` flag)
  - Added `CleanCache bool` flag
  - Added `CleanGhCli bool` flag
  - Added `CleanAll bool` flag
  - Added `Force bool` flag
  - Logout flow with cleanup phases
  - Cleanup function specifications
  - Updated usage examples
  - Security benefits documentation
- Enhanced `main.go` skeleton with cleanup configuration:
  - Added `CleanCache bool` flag
  - Added `CleanGhCli bool` flag
  - Added `CleanAll bool` flag
  - Added `Force bool` flag
  - Updated configuration struct with cleanup flags
  - Updated usage comments to include new flags
- Updated `implement-with-go.md` with v3.0 specification:
  - Logout flow with cleanup phases
  - Cleanup function specifications
  - Updated usage examples
- Updated all documentation to include v3.0 version headers:
  - `overview.md` - Added version and status headers
  - `docs/introduction.md` - Added version and status headers
  - `implement-with-go.md` - Added version and status headers
  - `main.go` - Added version and date headers

### Changed
- Implement `main.go` functions (`loadConfig`, `executeScript`, `autoRestartDocker`, `verifySetup`, `printSummary`)
- Create GitHub Actions workflow (`.github/workflows/docker-build.yml`)
- Implement deployment scripts (`pull-and-deploy.sh`, `health-check.sh`)
- Configure auto-deploy cron job for staging
- Add webhook support for external triggers
- Create CI/CD integration tests

---

## [3.0.0] - 2025-01-12

### Added
- Created comprehensive `README.md` with project overview and quick start guide
- Created `docs/introduction.md` for DevOps team onboarding
- Created `DOCUMENTATION_UPDATE_SUMMARY.md` for tracking documentation changes
- Created `setup-account/logoutall.sh` v2.0 with security cleanup features:
  - Support for multiple registries (GHCR, GCR, Docker Hub)
  - Build cache cleanup (`--clean-cache` flag)
  - GitHub CLI cleanup (`--clean-gh-cli` flag)
  - Temporary files cleanup (`--clean-all` flag)
  - Dry-run mode (`--dry-run` flag)
  - Verbose output (`--verbose` flag)
  - Force mode (`--force` flag)
  - Help system (`--help` flag)
- Enhanced `main.go` skeleton with cleanup configuration:
  - Added `CleanCache bool` flag
  - Added `CleanGhCli bool` flag
  - Added `CleanAll bool` flag
  - Added `Force bool` flag
- Updated `implement-with-go.md` with v3.0 specification:
  - Logout flow with cleanup phases
  - Cleanup function specifications
  - Updated usage examples
  - Security benefits documentation

### Changed
- Migrated from self-hosted runner architecture to cloud-native architecture:
  - GitHub Actions cloud runners for builds
  - GitHub Actions native cache (`type=gha`)
  - Optional registry cache for cross-runner sharing
  - DevOps VMs now pull-only deployment targets
- Updated all documentation to include v3.0 version headers:
  - `overview.md` - Added version and status headers
  - `docs/introduction.md` - Added version and status headers
  - `implement-with-go.md` - Added version and status headers
  - `main.go` - Added version and date headers

### Security
- Enhanced logout script with comprehensive security cleanup:
  - Registry credentials removal from `~/.docker/config.json`
  - Build cache cleanup (removes cached secrets in layers)
  - GitHub CLI cache removal (`~/.cache/gh`)
  - Docker daemon log truncation
  - BuildKit temp directory cleanup
- Added PAT scope guidance for GHCR:
  - `read:packages` (required for pulling)
  - `write:packages` (required for pushing)
  - `delete:packages` (optional for deleting)

### Documentation
- Created comprehensive `README.md` (486 lines) with:
  - Quick start guide
  - Project structure
  - Documentation index
  - Version history
  - Testing status
  - Troubleshooting section
  - Security considerations
  - Support resources
- Created `DOCUMENTATION_UPDATE_SUMMARY.md` (256 lines) for tracking changes
- Updated all documentation files with v3.0 version headers
- Added project health metrics and checkpoint reviews

### Improved
- Docker daemon configuration now includes:
  - BuildKit garbage collection (10GB limit)
  - Concurrent downloads: 10 (3.3x faster)
  - Concurrent uploads: 10 (2x faster)
  - NVIDIA runtime support for GPU containers
  - CDI devices enabled for better GPU handling

### Deprecated
- Self-hosted GitHub Actions runner architecture
  - Migrated to GitHub Actions cloud runners
  - Local VM builds no longer recommended

---

## [2.0.0] - 2025-01-12

### Added
- Created `setup-account/loginall.sh` v1.0:
  - Multi-registry authentication (GHCR, Docker Hub, GitHub CLI)
  - Environment variable loading from `.env` file
  - Pre-flight Docker daemon checks
  - Color-coded output for better UX
  - Authentication verification
- Created `script/enhancment-docker-builder.sh` v2.0:
  - Docker daemon configuration with BuildKit optimization
  - Automatic backup of existing configuration
  - BuildKit garbage collection (10GB limit)
  - Concurrent downloads/uploads optimization
  - NVIDIA runtime support
  - CDI device support
- Created `ghcr-auth-troubleshooting.md`:
  - Comprehensive GHCR authentication troubleshooting guide
  - Common errors and solutions
  - Docker CLI authentication
  - GitHub CLI authentication
  - Diagnostic commands
  - PAT creation and management guide
  - Advanced troubleshooting scenarios

### Changed
- Completely rewrote `enhancment-docker-builder.sh` from v1.0 to v2.0:
  - Reversed architecture: DevOps VM now pull-only (not build runner)
  - Removed local build execution
  - Focused on Docker daemon optimization
  - Added deployment mode configuration
- Updated Docker daemon configuration approach:
  - BuildKit GC enabled by default
  - Cache size limit set to 10GB
  - Performance tunings for downloads/uploads

### Fixed
- GHCR authentication issues with proper PAT scopes
- Docker daemon restart required for configuration changes

### Documentation
- Created `SCRIPT_UPDATE_SUMMARY.md` documenting v1.0 → v2.0 changes
- Created `current-buildkit-config.md` analyzing current BuildKit setup
- Created `enhancment-docker-builder.md` with configuration guide
- Created `spec-overview.md` with hardware/software specifications

---

## [1.0.0] - 2025-01-12

### Added
- Initial Docker daemon configuration
- Basic BuildKit setup
- Registry authentication support
- GitHub Container Registry (GHCR) support

### Documentation
- Initial project documentation
- Configuration examples
- Basic troubleshooting guide

---

## Version Guidelines

### Semantic Versioning

This project uses [Semantic Versioning](https://semver.org/):
- **MAJOR**: Incompatible API changes
- **MINOR**: Backwards-compatible functionality
- **PATCH**: Backwards-compatible bug fixes

### Version Format

```
MAJOR.MINOR.PATCH
```

Examples:
- `3.0.0` - Major architecture change (v2.0 → v3.0)
- `2.0.1` - Patch for bug fix
- `2.1.0` - New feature addition

---

## Change Categories

### Added
New features, functionality, or scripts.

### Changed
Changes to existing functionality, architecture, or configuration.

### Deprecated
Features removed in a future release (not recommended for use).

### Removed
Features removed in current release.

### Fixed
Bug fixes.

### Security
Security improvements, vulnerability fixes, or security best practices.

### Documentation
Documentation additions, updates, or improvements.

### Improved
Performance optimizations, code quality improvements, or refactoring.

---

## Contributors

- DevOps Team

---

## Support

For questions or issues related to specific versions, please refer to:
- Documentation in corresponding version
- Issue tracker (if available)
- Troubleshooting guides
- Support team

---

**Last Updated:** 2025-01-12
**Version:** 3.0.0

### Added
- Created comprehensive `README.md` with project overview and quick start guide
- Created `docs/introduction.md` for DevOps team onboarding
- Created `DOCUMENTATION_UPDATE_SUMMARY.md` for tracking documentation changes
- Created `setup-account/logoutall.sh` v2.0 with security cleanup features:
  - Support for multiple registries (GHCR, GCR, Docker Hub)
  - Build cache cleanup (`--clean-cache` flag)
  - GitHub CLI cleanup (`--clean-gh-cli` flag)
  - Temporary files cleanup (`--clean-all` flag)
  - Dry-run mode (`--dry-run` flag)
  - Verbose output (`--verbose` flag)
  - Force mode (`--force` flag)
  - Help system (`--help` flag)
  - Added `CleanCache bool` flag
  - Added `CleanGhCli bool` flag
  - Added `CleanAll bool` flag
  - Added `Force bool` flag
  - Logout flow with cleanup phases
  - Cleanup function specifications
  - Updated usage examples
  - Security benefits documentation
- Enhanced `main.go` skeleton with cleanup configuration:
  - Added `CleanCache bool` flag
  - Added `CleanGhCli bool` flag
  - Added `CleanAll bool` flag
  - Added `Force bool` flag
  - Updated configuration struct with cleanup flags
  - Updated usage comments to include new flags
- Updated `implement-with-go.md` with v3.0 specification:
  - Logout flow with cleanup phases
  - Cleanup function specifications
  - Updated usage examples
  - Security benefits documentation
- Updated all documentation to include v3.0 version headers:
  - `overview.md` - Added version and status headers
  - `docs/introduction.md` - Added version and status headers
  - `implement-with-go.md` - Added version and status headers
  - `main.go` - Added version and date headers
- Created `backup/config/` directory reorganized:
  - `default/` - Fresh install templates (`daemon.json`, `config.json`)
  - `dev/` - Historical backups (v1.0, v2.0, v3.0 configs)
  - `devops/` - DevOps Team configurations (specific-config.json)
- Created `script/restore-default-config.sh` (322 lines):
  - Restores default templates to system paths
  - Backups existing configurations
  - Restarts Docker daemon
  - Verifies configuration applied
- Created `backup/config/README.md` with complete documentation
  - Created `backup/config/default/daemon.json` - Minimal Docker config template
  - Created `backup/config/default/config.json` - Empty credentials template
  - Created `backup/config/devops/daemon.json.v3.0.bak` - DevOps-specific config
  - Created `backup/config/specific-config.json` - Merged config for DevOps Teams

### Changed
- Migrated from self-hosted runner architecture to cloud-native architecture:
  - GitHub Actions cloud runners for builds
  - GitHub Actions native cache (`type=gha`)
  - Optional registry cache for cross-runner sharing
  - DevOps VMs now pull-only deployment targets
- Updated Docker daemon configuration approach:
  - BuildKit GC enabled by default
  - Cache size limit set to 10GB
  - Performance tunings for downloads/uploads
- Reorganized `backup/config/` directory structure:
  - Separated historical configs from templates
  - Created DevOps-specific configurations
  - Added configuration documentation

