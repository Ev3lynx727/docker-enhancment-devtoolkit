#!/bin/bash
set -e

# =============================================================================
# Docker Registry & GitHub Authentication Setup Script
# =============================================================================
# This script authenticates Docker with multiple registries and tools:
# - GitHub Container Registry (GHCR)
# - Docker Hub (optional)
# - GitHub CLI (optional)
# =============================================================================

echo "========================================"
echo "  Docker Authentication Setup Script"
echo "========================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load environment variables
ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    echo "Loading environment from $ENV_FILE..."
    export $(grep -v '^#' "$ENV_FILE" | grep -v '^$' | xargs)
    echo -e "${GREEN}[OK]${NC} Environment loaded"
else
    echo -e "${YELLOW}[WARN]${NC} $ENV_FILE not found, using existing environment variables"
fi
echo ""

# Check if Docker is running
echo "Checking Docker daemon..."
if ! docker info &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Docker daemon is not running or not accessible"
    echo "Please start Docker and try again"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Docker daemon is running"
echo ""

# Summary of authentication targets
echo "Authentication Targets:"
echo "  1. GitHub Container Registry (GHCR) - REQUIRED"
echo "  2. Docker Hub - OPTIONAL"
echo "  3. GitHub CLI (gh) - OPTIONAL"
echo ""

# =============================================================================
# GHCR Authentication (CRITICAL)
# =============================================================================
echo "========================================"
echo "  GHCR Authentication"
echo "========================================"

# Use GITHUB_TOKEN if GHCR_TOKEN not set
GHCR_USER="${GHCR_USERNAME:-$GITHUB_USERNAME}"
GHCR_TOKEN="${GHCR_TOKEN:-$GITHUB_TOKEN}"

if [ -z "$GHCR_USER" ] || [ -z "$GHCR_TOKEN" ]; then
    echo -e "${RED}[ERROR]${NC} GHCR credentials not found"
    echo ""
    echo "Required variables:"
    echo "  - GITHUB_USERNAME: $([ -n "$GITHUB_USERNAME" ] && echo "${GREEN}[SET]${NC}" || echo "${RED}[NOT SET]${NC}")"
    echo "  - GITHUB_TOKEN: $([ -n "$GITHUB_TOKEN" ] && echo "${GREEN}[SET]${NC}" || echo "${RED}[NOT SET]${NC}")"
    echo ""
    echo "Please set these in .env or environment variables and try again"
    exit 1
fi

echo "Authenticating to GHCR as user: $GHCR_USER"
if echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin; then
    echo -e "${GREEN}[OK]${NC} GHCR authentication successful"
else
    echo -e "${RED}[ERROR]${NC} GHCR authentication failed"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify GITHUB_TOKEN has 'read:packages' scope"
    echo "  2. Verify GITHUB_TOKEN has 'write:packages' scope (for push)"
    echo "  3. Check if token is expired"
    echo "  4. Run: docker logout ghcr.io && try again"
    exit 1
fi

# Verify GHCR authentication
GHCR_AUTH=$(docker info 2>/dev/null | grep -i "ghcr.io" || true)
if [ -n "$GHCR_AUTH" ]; then
    echo -e "${GREEN}[OK]${NC} GHCR configured in Docker"
else
    echo -e "${YELLOW}[WARN]${NC} GHCR not visible in docker info (may still work)"
fi
echo ""

# =============================================================================
# Docker Hub Authentication (OPTIONAL)
# =============================================================================
echo "========================================"
echo "  Docker Hub Authentication"
echo "========================================"

if [ -n "$DOCKER_USERNAME" ] && [ -n "$DOCKER_PASSWORD" ]; then
    echo "Authenticating to Docker Hub as user: $DOCKER_USERNAME"
    if echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin; then
        echo -e "${GREEN}[OK]${NC} Docker Hub authentication successful"
    else
        echo -e "${RED}[ERROR]${NC} Docker Hub authentication failed"
        echo "Check your DOCKER_USERNAME and DOCKER_PASSWORD"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} Docker Hub credentials not set"
    echo "  Set DOCKER_USERNAME and DOCKER_PASSWORD in .env if needed"
fi
echo ""

# =============================================================================
# GitHub CLI Authentication (OPTIONAL)
# =============================================================================
echo "========================================"
echo "  GitHub CLI Authentication"
echo "========================================"

if [ -n "$GITHUB_TOKEN" ]; then
    if command -v gh &> /dev/null; then
        echo "GitHub CLI found, checking authentication status..."
        if gh auth status &> /dev/null; then
            echo -e "${GREEN}[OK]${NC} GitHub CLI already authenticated"
            gh auth status
        else
            echo "Authenticating GitHub CLI..."
            if echo "$GITHUB_TOKEN" | gh auth login --with-token; then
                echo -e "${GREEN}[OK]${NC} GitHub CLI authentication successful"
                gh auth status
            else
                echo -e "${RED}[ERROR]${NC} GitHub CLI authentication failed"
            fi
        fi
    else
        echo -e "${YELLOW}[SKIP]${NC} GitHub CLI (gh) not installed"
        echo "  Install with: https://cli.github.com/"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} GitHub CLI token not set"
    echo "  Set GITHUB_TOKEN in .env if needed"
fi
echo ""

# =============================================================================
# Authentication Summary
# =============================================================================
echo "========================================"
echo "  Authentication Summary"
echo "========================================"

# Check GHCR auth
GHCR_CREDENTIALS=$(cat ~/.docker/config.json 2>/dev/null | jq -r '.auths."ghcr.io"' || echo "null")
if [ "$GHCR_CREDENTIALS" != "null" ]; then
    echo -e "GHCR (ghcr.io):     ${GREEN}[AUTHENTICATED]${NC}"
else
    echo -e "GHCR (ghcr.io):     ${RED}[NOT AUTHENTICATED]${NC}"
fi

# Check Docker Hub auth
HUB_CREDENTIALS=$(cat ~/.docker/config.json 2>/dev/null | jq -r '.auths."https://index.docker.io/v1/"' || echo "null")
if [ "$HUB_CREDENTIALS" != "null" ]; then
    echo -e "Docker Hub:        ${GREEN}[AUTHENTICATED]${NC}"
else
    echo -e "Docker Hub:        ${YELLOW}[NOT AUTHENTICATED]${NC}"
fi

# Check GitHub CLI auth
if command -v gh &> /dev/null && gh auth status &> /dev/null; then
    echo -e "GitHub CLI (gh):    ${GREEN}[AUTHENTICATED]${NC}"
else
    echo -e "GitHub CLI (gh):    ${YELLOW}[NOT AUTHENTICATED]${NC}"
fi

echo ""
echo "========================================"
echo "  Setup Complete"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Test pull from GHCR: docker pull ghcr.io/actions/runner:latest"
echo "  2. Test GitHub CLI: gh repo view"
echo "  3. View all auth: cat ~/.docker/config.json | jq '.auths'"
echo ""
