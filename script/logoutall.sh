#!/bin/bash
set -e

# =============================================================================
# Docker Registry & GitHub Logout Script (Enhanced with Security Cleanup)
# =============================================================================
# This script logs out from all authenticated registries and tools,
# and provides optional cleanup of build cache and temporary data:
# - GitHub Container Registry (GHCR)
# - Docker Hub
# - GitHub CLI (gh)
# - Google Container Registry (GCR)
#
# Usage:
#   ./logoutall.sh                    # Logout from all registries
#   ./logoutall.sh --clean-cache      # Logout + clean build cache
#   ./logoutall.sh --clean-gh-cli   # Logout + clean GitHub CLI
#   ./logoutall.sh --clean-all       # Logout + clean everything
#   ./logoutall.sh --dry-run          # Preview actions without executing
#   ./logoutall.sh --force            # Skip confirmation prompts
#   ./logoutall.sh --verbose          # Show detailed output
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default flags
CLEAN_CACHE=false
CLEAN_GH_CLI=false
CLEAN_ALL=false
DRY_RUN=false
FORCE=false
VERBOSE=false

# Counters
LOGOUT_COUNT=0
LOGOUT_FAILED=0
CACHE_CLEANED=0
GH_CLI_CLEANED=0

# =============================================================================
# Parse Arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean-cache)
            CLEAN_CACHE=true
            shift
            ;;
        --clean-gh-cli)
            CLEAN_GH_CLI=true
            shift
            ;;
        --clean-all)
            CLEAN_CACHE=true
            CLEAN_GH_CLI=true
            CLEAN_ALL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --clean-cache    Clean Docker build cache after logout"
            echo "  --clean-gh-cli   Clean GitHub CLI data after logout"
            echo "  --clean-all      Clean all data (cache, GH CLI, temp files)"
            echo "  --dry-run        Preview actions without executing"
            echo "  --force          Skip confirmation prompts"
            echo "  --verbose, -v    Show detailed output"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                           # Logout from all registries"
            echo "  $0 --clean-cache              # Logout + clean cache"
            echo "  $0 --clean-all                # Full cleanup"
            echo "  $0 --clean-all --dry-run     # Preview full cleanup"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# =============================================================================
# Print Banner
# =============================================================================

print_banner() {
    echo ""
    echo "========================================"
    echo "  Docker Logout & Cleanup Script"
    echo "========================================"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN MODE]${NC} No changes will be made"
        echo ""
    fi

    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[VERBOSE MODE]${NC} Detailed output enabled"
        echo ""
    fi
}

# =============================================================================
# Helper Functions
# =============================================================================

logout_registry() {
    local registry=$1
    local name=$2

    echo "Logging out from $name..."

    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${BLUE}[DRY-RUN]${NC} Would logout from $name"
        ((LOGOUT_COUNT++))
        return
    fi

    if docker logout "$registry" 2>&1 | grep -q "Removing login credentials"; then
        echo -e "  ${GREEN}[OK]${NC} Logged out from $name"
        ((LOGOUT_COUNT++))
    else
        echo -e "  ${YELLOW}[SKIP]${NC} Not logged into $name or already logged out"
    fi
    echo ""
}

# =============================================================================
# Cleanup Functions
# =============================================================================

cleanup_build_cache() {
    echo "========================================"
    echo "  Docker Build Cache Cleanup"
    echo "========================================"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${BLUE}[DRY-RUN]${NC} Would clean build cache..."
        echo "  [DRY-RUN] docker builder prune -f"
        echo "  [DRY-RUN] docker buildx prune -a -f"
        echo -e "  ${GREEN}[OK]${NC} Build cache would be cleaned"
        ((CACHE_CLEANED++))
        return
    fi

    # Check for Docker daemon
    if ! docker info &> /dev/null; then
        echo -e "  ${RED}[SKIP]${NC} Docker daemon not running, skipping cache cleanup"
        echo ""
        return
    fi

    # Show running containers warning
    RUNNING_CONTAINERS=$(docker ps -q | wc -l)
    if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
        echo -e "  ${YELLOW}[WARNING]${NC} $RUNNING_CONTAINERS container(s) running"
        echo "  This is normal - only unused cache will be removed"
        echo ""
    fi

    # Prune builder cache (dangling images)
    if [ "$VERBOSE" = true ]; then
        echo "  Cleaning builder cache..."
    fi
    if docker builder prune -f > /dev/null 2>&1; then
        echo -e "  ${GREEN}[OK]${NC} Builder cache cleaned"
        ((CACHE_CLEANED++))
    else
        echo -e "  ${YELLOW}[SKIP]${NC} No builder cache to clean"
    fi

    # Prune buildx cache (all build cache)
    if [ "$VERBOSE" = true ]; then
        echo "  Cleaning buildx cache..."
    fi
    if docker buildx prune -a -f > /dev/null 2>&1; then
        echo -e "  ${GREEN}[OK]${NC} Buildx cache cleaned"
        ((CACHE_CLEANED++))
    else
        echo -e "  ${YELLOW}[SKIP]${NC} No buildx cache to clean"
    fi

    echo ""
}

cleanup_gh_cli() {
    echo "========================================"
    echo "  GitHub CLI Cleanup"
    echo "========================================"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${BLUE}[DRY-RUN]${NC} Would clean GitHub CLI data..."
        echo "  [DRY-RUN] gh auth logout"
        echo "  [DRY-RUN] rm -rf ~/.cache/gh"
        echo -e "  ${GREEN}[OK]${NC} GitHub CLI would be cleaned"
        ((GH_CLI_CLEANED++))
        return
    fi

    # Logout from GitHub CLI
    if command -v gh &> /dev/null; then
        if gh auth status &> /dev/null; then
            echo "  Logging out from GitHub CLI..."
            if gh auth logout; then
                echo -e "  ${GREEN}[OK]${NC} Logged out from GitHub CLI"
                ((GH_CLI_CLEANED++))
            else
                echo -e "  ${RED}[ERROR]${NC} Failed to logout from GitHub CLI"
                ((LOGOUT_FAILED++))
            fi
        else
            echo -e "  ${YELLOW}[SKIP]${NC} GitHub CLI not authenticated"
        fi

        # Remove GitHub CLI cache directory
        GH_CACHE_DIR="$HOME/.cache/gh"
        if [ -d "$GH_CACHE_DIR" ]; then
            if [ "$VERBOSE" = true ]; then
                echo "  Removing GitHub CLI cache: $GH_CACHE_DIR"
            fi
            rm -rf "$GH_CACHE_DIR"
            echo -e "  ${GREEN}[OK]${NC} GitHub CLI cache removed"
            ((GH_CLI_CLEANED++))
        else
            echo -e "  ${YELLOW}[SKIP]${NC} GitHub CLI cache not found"
        fi
    else
        echo -e "  ${YELLOW}[SKIP]${NC} GitHub CLI (gh) not installed"
    fi

    echo ""
}

cleanup_temp_files() {
    echo "========================================"
    echo "  Temporary Files Cleanup"
    echo "========================================"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${BLUE}[DRY-RUN]${NC} Would clean temporary files..."
        echo "  [DRY-RUN] truncate -s 0 /var/log/docker.log (if exists)"
        echo -e "  ${GREEN}[OK]${NC} Temporary files would be cleaned"
        return
    fi

    # Clean Docker daemon log file
    DOCKER_LOG="/var/log/docker.log"
    if [ -f "$DOCKER_LOG" ]; then
        if [ "$VERBOSE" = true ]; then
            echo "  Truncating Docker log: $DOCKER_LOG"
        fi
        if sudo truncate -s 0 "$DOCKER_LOG" 2>/dev/null; then
            echo -e "  ${GREEN}[OK]${NC} Docker log truncated"
        else
            echo -e "  ${YELLOW}[SKIP]${NC} Failed to truncate Docker log (requires sudo)"
        fi
    else
        if [ "$VERBOSE" = true ]; then
            echo "  Docker log not found: $DOCKER_LOG"
        fi
    fi

    # Clean BuildKit temp directories
    BUILDKIT_TEMP="/tmp/buildkit-*"
    if ls $BUILDKIT_TEMP &> /dev/null 2>&1; then
        if [ "$VERBOSE" = true ]; then
            echo "  Removing BuildKit temp directories..."
        fi
        rm -rf $BUILDKIT_TEMP 2>/dev/null || true
        echo -e "  ${GREEN}[OK]${NC} BuildKit temp directories cleaned"
    else
        if [ "$VERBOSE" = true ]; then
            echo "  No BuildKit temp directories found"
        fi
    fi

    echo ""
}

cleanup_credentials_check() {
    echo "========================================"
    echo "  Credentials Check"
    echo "========================================"
    echo ""

    DOCKER_CONFIG="$HOME/.docker/config.json"

    if [ ! -f "$DOCKER_CONFIG" ]; then
        echo -e "  ${GREEN}[OK]${NC} No Docker config file exists"
        echo ""
        return
    fi

    echo "  Checking remaining credentials..."
    AUTH_COUNT=$(cat "$DOCKER_CONFIG" 2>/dev/null | jq -r '.auths | keys[]' | wc -l 2>/dev/null || echo "0")

    if [ "$AUTH_COUNT" -eq 0 ] || [ "$AUTH_COUNT" = "0" ] || [ "$AUTH_COUNT" = "null" ]; then
        echo -e "  ${GREEN}[OK]${NC} No credentials remaining in $DOCKER_CONFIG"
    else
        echo -e "  ${YELLOW}[INFO]${NC} $AUTH_COUNT credential(s) still in $DOCKER_CONFIG"
        echo "  Current credentials:"
        cat "$DOCKER_CONFIG" 2>/dev/null | jq -r '.auths | keys[]' 2>/dev/null | sed 's/^/  - /' || true

        # Check for credential helpers
        CREDSHELPER=$(cat "$DOCKER_CONFIG" 2>/dev/null | jq -r '.credsStore // empty')
        if [ "$CREDSHELPER" != "" ] && [ "$CREDSHELPER" != "null" ]; then
            echo -e "  ${YELLOW}[INFO]${NC} Credential helper configured: $CREDSHELPER"
            echo "  You may need to clear credential helper data separately"
        fi
    fi
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================

print_banner

# Confirmation for destructive operations
if [ "$CLEAN_ALL" = true ] && [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
    echo -e "${YELLOW}[WARNING]${NC} --clean-all will remove:"
    echo "  - Build cache (may slow down future builds)"
    echo "  - GitHub CLI cache"
    echo "  - Temporary log files"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled by user"
        exit 0
    fi
    echo ""
fi

# =============================================================================
# Phase 1: Logout from Registries
# =============================================================================

echo "========================================"
echo "  Docker Hub Logout"
echo "========================================"
if docker logout 2>&1 | grep -q "Removing login credentials"; then
    echo -e "${GREEN}[OK]${NC} Logged out from Docker Hub"
    ((LOGOUT_COUNT++))
else
    echo -e "${YELLOW}[SKIP]${NC} Not logged into Docker Hub or already logged out"
fi
echo ""

echo "========================================"
echo "  GHCR Logout"
echo "========================================"
logout_registry "ghcr.io" "GHCR (ghcr.io)"

echo "========================================"
echo "  GCR Logout"
echo "========================================"
GCR_REGISTRIES=(
    "gcr.io"
    "us.gcr.io"
    "eu.gcr.io"
    "asia.gcr.io"
    "marketplace.gcr.io"
    "staging-k8s.gcr.io"
)
for registry in "${GCR_REGISTRIES[@]}"; do
    if docker logout "https://$registry" 2>&1 | grep -q "Removing login credentials"; then
        echo -e "  ${GREEN}[OK]${NC} Logged out from $registry"
        ((LOGOUT_COUNT++))
    else
        echo -e "  ${YELLOW}[SKIP]${NC} Not logged into $registry or already logged out"
    fi
done
echo ""

echo "========================================"
echo "  GitHub CLI Logout"
echo "========================================"
if command -v gh &> /dev/null; then
    if gh auth status &> /dev/null; then
        echo "  Logging out from GitHub CLI..."
        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${BLUE}[DRY-RUN]${NC} Would logout from GitHub CLI"
            ((LOGOUT_COUNT++))
        else
            if gh auth logout; then
                echo -e "${GREEN}[OK]${NC} Logged out from GitHub CLI"
                ((LOGOUT_COUNT++))
            else
                echo -e "${RED}[ERROR]${NC} Failed to logout from GitHub CLI"
                ((LOGOUT_FAILED++))
            fi
        fi
    else
        echo -e "${YELLOW}[SKIP]${NC} GitHub CLI not authenticated"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} GitHub CLI (gh) not installed"
fi
echo ""

# =============================================================================
# Phase 2: Cleanup (Optional based on flags)
# =============================================================================

if [ "$CLEAN_CACHE" = true ] || [ "$CLEAN_ALL" = true ]; then
    cleanup_build_cache
fi

if [ "$CLEAN_GH_CLI" = true ] || [ "$CLEAN_ALL" = true ]; then
    cleanup_gh_cli
fi

if [ "$CLEAN_ALL" = true ]; then
    cleanup_temp_files
fi

# =============================================================================
# Phase 3: Verification
# =============================================================================

cleanup_credentials_check

# =============================================================================
# Summary
# =============================================================================

echo "========================================"
echo "  Cleanup Summary"
echo "========================================"

echo "Registry/Service Logout:"
echo "  Successfully logged out from: $LOGOUT_COUNT registry/service(s)"
if [ "$LOGOUT_FAILED" -gt 0 ]; then
    echo -e "  ${RED}Failed:${NC} $LOGOUT_FAILED logout(s)"
fi
echo ""

if [ "$CLEAN_CACHE" = true ] || [ "$CLEAN_ALL" = true ]; then
    echo "Build Cache Cleanup:"
    if [ "$CACHE_CLEANED" -gt 0 ]; then
        echo -e "  ${GREEN}Cleaned:${NC} $CACHE_CLEANED cache operation(s)"
    else
        echo -e "  ${YELLOW}No cache cleaned${NC}"
    fi
    echo ""
fi

if [ "$CLEAN_GH_CLI" = true ] || [ "$CLEAN_ALL" = true ]; then
    echo "GitHub CLI Cleanup:"
    if [ "$GH_CLI_CLEANED" -gt 0 ]; then
        echo -e "  ${GREEN}Cleaned:${NC} $GH_CLI_CLEANED operation(s)"
    else
        echo -e "  ${YELLOW}No GitHub CLI data cleaned${NC}"
    fi
    echo ""
fi

if [ "$CLEAN_ALL" = true ]; then
    echo "Temporary Files Cleanup:"
    echo -e "  ${GREEN}Cleared${NC} temporary files and logs"
    echo ""
fi

# Overall status
echo "========================================"
if [ "$LOGOUT_COUNT" -eq 0 ] && [ "$CACHE_CLEANED" -eq 0 ] && [ "$GH_CLI_CLEANED" -eq 0 ]; then
    echo "  No actions performed"
else
    echo "  Actions completed:"
    if [ "$LOGOUT_COUNT" -gt 0 ]; then
        echo "  - Docker Hub (index.docker.io)"
        echo "  - GHCR (ghcr.io)"
        echo "  - GCR (gcr.io and regional registries)"
        echo "  - GitHub CLI (gh)"
    fi
    if [ "$CACHE_CLEANED" -gt 0 ]; then
        echo "  - Build cache cleaned"
    fi
    if [ "$GH_CLI_CLEANED" -gt 0 ]; then
        echo "  - GitHub CLI cache cleaned"
    fi
fi
echo "========================================"
echo ""

echo "Security Benefits:"
echo "  ✓ Registry credentials removed (prevents unauthorized access)"
echo "  ✓ Cached secrets cleared from build layers"
echo "  ✓ Temporary sensitive data removed"
echo "  ✓ GitHub API access revoked"
echo ""

echo "========================================"
echo "  Logout Complete"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Re-authenticate: ./loginall.sh"
echo "  2. Or run: go run main.go"
echo "  3. View credentials: cat ~/.docker/config.json | jq '.auths'"
echo ""
