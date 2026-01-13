#!/bin/bash
set -e

# =============================================================================
# Docker Default Configuration Restore Script
# =============================================================================
# This script restores default Docker daemon configurations from the
# backup/config/default/ directory to the actual Docker paths:
# - /etc/docker/daemon.json (Docker daemon configuration)
# - ~/.docker/config.json (Docker client credentials)
#
# Usage:
#   sudo ./restore-default-config.sh
#
# See: ../docs/introduction.md for more information
# =============================================================================

echo "========================================"
echo "  Docker Default Configuration Restore"
echo "========================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/../backup/config/default"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)"
    echo "Usage: sudo $0"
    exit 1
fi

# Verify backup files exist
DAEMON_BACKUP="$BACKUP_DIR/daemon.json"
CLIENT_BACKUP="$BACKUP_DIR/config.json"

echo "Checking backup files..."
if [ ! -f "$DAEMON_BACKUP" ]; then
    echo -e "${RED}[ERROR]${NC} Daemon backup not found: $DAEMON_BACKUP"
    exit 1
fi

if [ ! -f "$CLIENT_BACKUP" ]; then
    echo -e "${RED}[ERROR]${NC} Client config backup not found: $CLIENT_BACKUP"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Backup files found"
echo ""

# =============================================================================
# Restore Docker Daemon Configuration
# =============================================================================

echo "========================================"
echo "  Restoring Docker Daemon Configuration"
echo "========================================"
echo ""

echo "Source: $DAEMON_BACKUP"
echo "Target: /etc/docker/daemon.json"
echo ""

# Create backup of existing daemon.json
if [ -f "/etc/docker/daemon.json" ]; then
    echo "Creating backup of existing daemon.json..."
    sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$(date +%Y%m%d_%H%M%S)
    echo -e "${GREEN}[OK]${NC} Backup created: /etc/docker/daemon.json.backup.$(date +%Y%m%d_%H%M%S)"
    echo ""
else
    echo -e "${YELLOW}[INFO]${NC} No existing daemon.json to backup"
    echo ""
fi

# Copy default daemon.json
echo "Copying default daemon configuration..."
sudo cp "$DAEMON_BACKUP" /etc/docker/daemon.json
echo -e "${GREEN}[OK]${NC} Daemon configuration restored"
echo ""

# =============================================================================
# Restore Docker Client Configuration
# =============================================================================

echo "========================================"
echo "  Restoring Docker Client Configuration"
echo "========================================"
echo ""

echo "Source: $CLIENT_BACKUP"
echo "Target: ~/.docker/config.json"
echo ""

# Create backup of existing client config
if [ -f "$HOME/.docker/config.json" ]; then
    echo "Creating backup of existing config.json..."
    cp "$HOME/.docker/config.json" "$HOME/.docker/config.json.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${GREEN}[OK]${NC} Backup created: ~/.docker/config.json.backup.$(date +%Y%m%d_%H%M%S)"
    echo ""
else
    echo -e "${YELLOW}[INFO]${NC} No existing config.json to backup"
    echo ""
fi

# Copy default client config
echo "Copying default client configuration..."
cp "$CLIENT_BACKUP" "$HOME/.docker/config.json"
echo -e "${GREEN}[OK]${NC} Client configuration restored"
echo ""

# =============================================================================
# Restart Docker Daemon
# =============================================================================

echo "========================================"
echo "  Restarting Docker Daemon"
echo "========================================"
echo ""

echo "Restarting Docker daemon to apply new configuration..."
sudo systemctl restart docker.service

# Wait for Docker daemon to be ready
echo "Waiting for Docker daemon to start..."
sleep 3

# Verify Docker daemon is running
if docker info &> /dev/null; then
    echo -e "${GREEN}[OK]${NC} Docker daemon is running"
else
    echo -e "${RED}[ERROR]${NC} Docker daemon failed to start"
    echo "Check logs: sudo journalctl -u docker.service -n 50"
    exit 1
fi
echo ""

# =============================================================================
# Verify Configuration
# =============================================================================

echo "========================================"
echo "  Verifying Configuration"
echo "========================================"
echo ""

# Verify daemon.json syntax
echo "Verifying daemon.json syntax..."
if sudo jq empty /etc/docker/daemon.json > /dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} daemon.json is valid JSON"
else
    echo -e "${RED}[ERROR]${NC} daemon.json has invalid syntax"
    sudo cat /etc/docker/daemon.json
    exit 1
fi
echo ""

# Verify client config.json syntax
echo "Verifying client config.json syntax..."
if jq empty ~/.docker/config.json > /dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} Client config.json is valid JSON"
else
    echo -e "${YELLOW}[WARN]${NC} Client config.json has invalid syntax (but may still work)"
    cat ~/.docker/config.json
fi
echo ""

# Check configuration applied
echo "Checking Docker daemon configuration..."
DAEMON_INFO=$(docker info --format '{{json .}}')

if echo "$DAEMON_INFO" | jq -e '.max_concurrent_downloads == "10"' 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Concurrent downloads: 10 (as expected)"
else
    echo -e "${YELLOW}[WARN]${NC} Concurrent downloads: $(echo "$DAEMON_INFO" | jq -r '.max_concurrent_downloads // empty')"
fi

if echo "$DAEMON_INFO" | jq -e '.max_concurrent_uploads == "10"' 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Concurrent uploads: 10 (as expected)"
else
    echo -e "${YELLOW}[WARN]${NC} Concurrent uploads: $(echo "$DAEMON_INFO" | jq -r '.max_concurrent_uploads // empty')"
fi

echo ""

# =============================================================================
# Summary
# =============================================================================

echo "========================================"
echo "  Restore Summary"
echo "========================================"
echo ""

echo "Restored Configurations:"
echo "  - Docker Daemon: /etc/docker/daemon.json"
echo "  - Docker Client: ~/.docker/config.json"
echo ""

echo "Applied Settings:"
echo "  - BuildKit GC: Enabled (if configured in backup)"
echo "  - Concurrent downloads: 10 (if configured in backup)"
echo "  - Concurrent uploads: 10 (if configured in backup)"
echo ""

echo "Next Steps:"
echo "  1. Run: docker info (to verify configuration)"
echo "  2. Run: sudo systemctl status docker.service (to check daemon status)"
echo "  3. Re-authenticate with: ../../setup-account/loginall.sh"
echo ""

echo "========================================"
echo "  Restore Complete"
echo "========================================"
echo ""

echo -e "${GREEN}[SUCCESS]${NC} Default configurations restored successfully"
echo ""
