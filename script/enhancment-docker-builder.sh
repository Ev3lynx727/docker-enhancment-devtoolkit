#!/bin/bash

# Docker Deployment Configuration Script
# Purpose: Configure DevOps VM as pull-only deployment target with BuildKit cache
# Architecture: Cloud-native CI/CD (GitHub Actions + GHCR)
# Author: opencode
# Date: 2025-01-12
# Version: 3.0

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEPLOYMENT_MODE="${DEPLOYMENT_MODE:-production}"
IMAGE_NAME="${IMAGE_NAME:-}"
CONTAINER_NAME="${CONTAINER_NAME:-app-prod}"
PORT="${PORT:-80}"
CRON_INTERVAL="${CRON_INTERVAL:-*/5 * * * *}"
AUTO_DEPLOY="${AUTO_DEPLOY:-false}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
SKIP_AUTH="${SKIP_AUTH:-false}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes)
                NON_INTERACTIVE=true
                ;;
            --skip-auth)
                SKIP_AUTH=true
                ;;
            --image)
                IMAGE_NAME="$2"
                shift
                ;;
            --port)
                PORT="$2"
                shift
                ;;
            --auto-deploy)
                AUTO_DEPLOY=true
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  -y, --yes          Non-interactive mode (use defaults)"
                echo "  --skip-auth        Skip GHCR authentication"
                echo "  --image IMAGE      Set GHCR image name"
                echo "  --port PORT        Set host port"
                echo "  --auto-deploy      Enable auto-deploy"
                echo "  --help             Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
        shift
    done
}

# Load environment variables from .env file
load_env() {
    local env_file="$1"

    if [[ -f "$env_file" ]]; then
        log_info "Loading environment from $env_file"
        set -a
        source "$env_file"
        set +a
        log_success "Environment loaded"
    else
        log_warning "Environment file not found: $env_file"
        log_warning "Using default values"
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root. Please run as a regular user with sudo access."
        exit 1
    fi
}

# Check sudo access
check_sudo() {
    log_info "Checking sudo access..."
    if sudo -n true 2>/dev/null; then
        log_success "Sudo access confirmed (passwordless)"
        return 0
    fi
    log_info "Sudo requires password - will prompt as needed"
    if sudo true 2>/dev/null; then
        log_success "Sudo access confirmed"
        return 0
    fi
    log_error "This script requires sudo access."
    exit 1
}

# Check Docker installation
check_docker() {
    log_info "Checking Docker installation..."
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
    log_success "Docker is installed (version: $DOCKER_VERSION)"
}

# Check BuildKit
check_buildkit() {
    log_info "Checking BuildKit..."
    BUILDKIT_STATUS=$(docker buildx version 2>/dev/null || docker build --version2>/dev/null || echo "Not found")
    if echo "$BUILDKIT_STATUS" | grep -q "buildx"; then
        BUILDKIT_VERSION=$(echo "$BUILDKIT_STATUS" | head -n1 | awk '{print $3}')
        log_success "BuildKit is installed via Buildx (version: $BUILDKIT_VERSION)"
    elif echo "$BUILDKIT_STATUS" | grep -q "build"; then
        log_success "BuildKit is installed (version: $BUILDKIT_VERSION)"
    else
        log_warning "BuildKit may not be properly installed"
    fi
}

# Check Docker daemon status
check_docker_daemon() {
    log_info "Checking Docker daemon status..."
    if ! sudo systemctl is-active --quiet docker; then
        log_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    log_success "Docker daemon is running"
}

# Check available disk space
check_disk_space() {
    log_info "Checking available disk space..."
    AVAILABLE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $AVAILABLE_SPACE -lt 10 ]]; then
        log_warning "Low disk space: ${AVAILABLE_SPACE}GB available. Recommended: at least 10GB free."
    else
        log_success "Sufficient disk space: ${AVAILABLE_SPACE}GB available"
    fi
}

# Check NVIDIA runtime (optional)
check_nvidia_runtime() {
    log_info "Checking NVIDIA runtime..."
    if command -v nvidia-container-runtime &> /dev/null; then
        log_success "NVIDIA Container Runtime is installed"
    else
        log_warning "NVIDIA Container Runtime not found (optional)"
    fi
}

# Check BuildKit cache directory
check_cache_directory() {
    log_info "Checking BuildKit cache directory..."
    CACHE_DIR="/var/lib/buildkit/cache"
    if [[ -d "$CACHE_DIR" ]]; then
        log_warning "Cache directory already exists: $CACHE_DIR"
    else
        log_success "Cache directory will be created: $CACHE_DIR"
    fi
    return 0
}

# Prompt for deployment mode
prompt_deployment_mode() {
    if [[ "$NON_INTERACTIVE" == true ]]; then
        DEPLOYMENT_MODE="production"
        CONTAINER_NAME="app-prod"
        log_info "Using default deployment mode: production"
        return 0
    fi

    log_header "Deployment Mode Selection"
    echo "Select deployment mode:"
    echo "  1) Production (app-prod)"
    echo "  2) Staging (app-staging)"
    echo ""
    read -rp "Select mode [1-2] (default: 1): " MODE_CHOICE
    MODE_CHOICE=${MODE_CHOICE:-1}

    case $MODE_CHOICE in
        1)
            DEPLOYMENT_MODE="production"
            CONTAINER_NAME="app-prod"
            log_info "Selected: Production mode"
            ;;
        2)
            DEPLOYMENT_MODE="staging"
            CONTAINER_NAME="app-staging"
            log_info "Selected: Staging mode"
            ;;
        *)
            log_error "Invalid selection"
            exit 1
            ;;
    esac
}

# Prompt for GHCR image name
prompt_image_name() {
    if [[ -n "$IMAGE_NAME" ]]; then
        log_success "Image name configured: $IMAGE_NAME"
        return 0
    fi

    if [[ "$NON_INTERACTIVE" == true ]]; then
        log_warning "No image name provided. You'll need to configure it later."
        IMAGE_NAME=""
        return 0
    fi

    log_header "GHCR Image Configuration"
    echo "Enter the GHCR image name to pull from."
    echo "Example: ghcr.io/your-org/your-repo:latest"
    echo ""
    read -rp "Image name: " IMAGE_NAME

    if [[ -z "$IMAGE_NAME" ]]; then
        log_warning "No image name provided. You'll need to configure it later."
    else
        log_success "Image name configured: $IMAGE_NAME"
    fi
}

# Prompt for port configuration
prompt_port_config() {
    if [[ "$NON_INTERACTIVE" == true ]]; then
        log_success "Port configured: $PORT (default)"
        return 0
    fi

    log_header "Port Configuration"
    echo "Enter the host port for the container."
    echo "The container will expose port 8080 internally."
    echo ""
    read -rp "Host port (default: $PORT): " PORT_INPUT
    PORT=${PORT_INPUT:-$PORT}
    log_success "Port configured: $PORT"
}

# Prompt for auto-deploy cron interval
prompt_auto_deploy() {
    if [[ "$NON_INTERACTIVE" == true ]]; then
        if [[ "$AUTO_DEPLOY" == true ]]; then
            log_success "Auto-deploy enabled with interval: $CRON_INTERVAL"
        else
            log_info "Auto-deploy disabled. You'll need to manually pull and deploy."
        fi
        return 0
    fi

    log_header "Auto-Deploy Configuration"
    echo "Enable automatic deployment checks via cron job?"
    echo "This will automatically pull and deploy new images."
    echo ""
    read -p "Enable auto-deploy? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        AUTO_DEPLOY=true
        echo ""
        log_info "Cron interval format: */N * * * * (check every N minutes)"
        read -rp "Cron interval (default: */5 * * * *): " CRON_INPUT
        CRON_INTERVAL=${CRON_INPUT:-"*/5 * * * *"}
        log_success "Auto-deploy enabled with interval: $CRON_INTERVAL"
    else
        AUTO_DEPLOY=false
        log_info "Auto-deploy disabled. You'll need to manually pull and deploy."
    fi
}

# Create backups
create_backup() {
    log_header "Creating Backups"

    DAEMON_JSON="/etc/docker/daemon.json"
    BACKUP_DIR="/home/ev3lynx/guide/backup/config"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)

    # Create backup directory if it doesn't exist
    sudo mkdir -p "$BACKUP_DIR"

    if [[ -f "$DAEMON_JSON" ]]; then
        sudo cp "$DAEMON_JSON" "$BACKUP_DIR/daemon.json.$TIMESTAMP.bak"
        sudo cp "$DAEMON_JSON" "$BACKUP_DIR/daemon.json.current"
        log_success "Backed up daemon.json to $BACKUP_DIR/"
    else
        log_warning "daemon.json does not exist yet"
    fi
}

# Create persistent cache directory
create_cache_directory() {
    log_header "Creating Persistent Cache Directory"

    CACHE_DIR="/var/lib/buildkit/cache"

    if [[ -d "$CACHE_DIR" ]]; then
        log_warning "Cache directory already exists: $CACHE_DIR"
        read -p "Do you want to remove and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo rm -rf "$CACHE_DIR"
        else
            log_info "Keeping existing cache directory"
            return 0
        fi
    fi

    sudo mkdir -p "$CACHE_DIR"
    sudo chown -R root:root "$CACHE_DIR"
    sudo chmod -R 755 "$CACHE_DIR"
    log_success "Created cache directory: $CACHE_DIR"
}

# Setup GHCR authentication
setup_ghcr_auth() {
    if [[ "$SKIP_AUTH" == true ]]; then
        log_info "Skipping GHCR authentication (--skip-auth flag set)"
        return 0
    fi

    log_header "GHCR Authentication"

    # Check if credentials are already set in environment
    if [[ -n "$GITHUB_USERNAME" && -n "$GITHUB_TOKEN" ]]; then
        log_info "Using credentials from environment"
        log_info "Logging in to GHCR..."
        if echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin; then
            log_success "Successfully logged in to GHCR"
            return 0
        else
            log_error "Failed to login to GHCR with environment credentials"
            log_warning "You can configure this later manually:"
            log_info "  echo 'PAT' | docker login ghcr.io -u USERNAME --password-stdin"
            return 1
        fi
    fi

    if [[ "$NON_INTERACTIVE" == true ]]; then
        log_warning "No credentials found in environment"
        log_warning "Skipping interactive GHCR login"
        log_info "To authenticate, run:"
        log_info "  echo 'PAT' | docker login ghcr.io -u USERNAME --password-stdin"
        return 0
    fi

    log_info "You need to authenticate with GitHub Container Registry (GHCR)."
    log_info "This requires a GitHub Personal Access Token (PAT)."
    echo ""
    log_warning "PAT requires: 'read:packages' and 'write:packages' scopes"
    echo ""

    read -rp "Enter your GitHub username: " GITHUB_USERNAME
    read -rsp "Enter your GitHub PAT: " GITHUB_TOKEN
    echo ""

    if [[ -z "$GITHUB_USERNAME" || -z "$GITHUB_TOKEN" ]]; then
        log_warning "Incomplete credentials. Skipping GHCR login."
        return 0
    fi

    log_info "Logging in to GHCR..."
    if echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin; then
        log_success "Successfully logged in to GHCR"
        return 0
    else
        log_error "Failed to login to GHCR"
        log_warning "You can configure this later manually:"
        log_info "  echo 'PAT' | docker login ghcr.io -u USERNAME --password-stdin"
        return 1
    fi
}

# Stop Docker daemon
stop_docker() {
    log_info "Stopping Docker daemon..."

    if sudo systemctl is-active --quiet docker; then
        sudo systemctl stop docker
        log_success "Docker daemon stopped"
    else
        log_info "Docker daemon was not running"
    fi

    # Wait for Docker to fully stop
    log_info "Waiting for Docker to fully stop..."
    local retry_count=0
    local max_retries=10

    while [[ $retry_count -lt $max_retries ]]; do
        if ! sudo systemctl is-active --quiet docker; then
            log_success "Docker daemon has stopped"
            return 0
        fi
        sleep 1
        retry_count=$((retry_count + 1))
    done

    log_warning "Docker daemon may still be running, attempting force stop..."
    sudo systemctl kill docker
    sleep 2

    if sudo systemctl is-active --quiet docker; then
        log_error "Failed to stop Docker daemon"
        return 1
    fi
}

# Rollback daemon.json to original configuration
rollback_daemon_json() {
    log_header "Rolling Back Configuration"

    BACKUP_DIR="/home/ev3lynx/guide/backup/config"
    DAEMON_JSON="/etc/docker/daemon.json"

    if [[ -f "$BACKUP_DIR/daemon.json.current" ]]; then
        log_info "Restoring original daemon.json..."
        sudo cp "$BACKUP_DIR/daemon.json.current" "$DAEMON_JSON"
        log_success "Restored original daemon.json"
    else
        log_warning "No backup found, cannot rollback"
        return 1
    fi
}

# Update daemon.json
update_daemon_json() {
    log_header "Updating Docker Daemon Configuration"

    DAEMON_JSON="/etc/docker/daemon.json"

    RECOMMENDED_CONFIG='{
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
        "cdi": true
    },
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 10
}'

    if [[ -f "$DAEMON_JSON" ]]; then
        log_info "Current daemon.json exists"
        log_info "Recommended configuration:"
        echo "$RECOMMENDED_CONFIG"
        log_info ""
        log_warning "You will need to manually merge configurations"

        log_info "Current configuration:"
        sudo cat "$DAEMON_JSON"

        if [[ "$NON_INTERACTIVE" == true ]]; then
            log_info "Non-interactive mode: applying recommended configuration"
            if ! stop_docker; then
                log_error "Failed to stop Docker daemon. Cannot proceed with configuration update."
                return 1
            fi

            sudo bash -c "echo '$RECOMMENDED_CONFIG' > $DAEMON_JSON"
            log_success "Updated daemon.json with recommended configuration"
            log_success "Docker daemon is stopped. It will be started in the next step."
            return 0
        fi

        echo ""
        read -p "Do you want to apply recommended configuration? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if ! stop_docker; then
                log_error "Failed to stop Docker daemon. Cannot proceed with configuration update."
                return 1
            fi

            sudo bash -c "echo '$RECOMMENDED_CONFIG' > $DAEMON_JSON"
            log_success "Updated daemon.json with recommended configuration"
            log_success "Docker daemon is stopped. It will be started in the next step."
            return 0
        else
            log_warning "Skipped daemon.json update. You'll need to update it manually."
            return 1
        fi
    else
        log_info "Creating new daemon.json with recommended configuration"
        if ! stop_docker; then
            log_error "Failed to stop Docker daemon. Cannot proceed with configuration update."
            return 1
        fi

        sudo bash -c "echo '$RECOMMENDED_CONFIG' > $DAEMON_JSON"
        log_success "Created daemon.json with recommended configuration"
        log_success "Docker daemon is stopped. It will be started in the next step."
        return 0
    fi
}

# Start Docker daemon
start_docker() {
    log_header "Starting Docker Daemon"

    log_info "Starting Docker daemon..."
    sudo systemctl start docker

    # Wait for Docker to be ready
    log_info "Waiting for Docker to be ready..."
    local retry_count=0
    local max_retries=30

    while [[ $retry_count -lt $max_retries ]]; do
        if sudo systemctl is-active --quiet docker; then
            # Additional check if docker command works
            if docker info &> /dev/null; then
                log_success "Docker daemon is running and ready"
                return 0
            fi
        fi
        sleep 1
        retry_count=$((retry_count + 1))
    done

    log_error "Docker daemon failed to start or is not responding"
    return 1
}

# Restart Docker daemon (with rollback on failure)
restart_docker() {
    log_header "Restarting Docker Daemon"

    if [[ "$NON_INTERACTIVE" == true ]]; then
        log_info "Starting Docker daemon..."
        if ! start_docker; then
            log_error "Docker daemon failed to start"
            log_info "Checking for errors..."
            sudo journalctl -u docker --no-pager -n 20
            return 1
        fi
        return 0
    fi

    read -p "Do you want to start Docker now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if ! start_docker; then
            log_error "Docker daemon failed to start"
            log_info "Checking for errors..."
            sudo journalctl -u docker --no-pager -n 20

            echo ""
            read -p "Do you want to rollback to original configuration? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rollback_daemon_json
                log_info "Attempting to start Docker with original configuration..."
                if start_docker; then
                    log_success "Docker daemon started with original configuration"
                else
                    log_error "Docker daemon still failing to start. Please check manually."
                fi
            fi
            return 1
        fi
    else
        log_warning "Docker daemon not started. You'll need to start it manually: sudo systemctl start docker"
        return 1
    fi
}

# Create deployment scripts
create_deployment_scripts() {
    log_header "Creating Deployment Scripts"

    # Create pull-and-deploy script
    PULL_DEPLOY_SCRIPT="/usr/local/bin/pull-and-deploy.sh"
    log_info "Creating pull-and-deploy script: $PULL_DEPLOY_SCRIPT"

    sudo tee "$PULL_DEPLOY_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
set -e

# Configuration (can be overridden by environment variables)
IMAGE="${IMAGE_NAME:-ghcr.io/your-org/your-repo:latest}"
CONTAINER="${CONTAINER_NAME:-app-prod}"
PORT="${PORT:-80}"

# Logging functions
log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

log_header() {
    echo -e "\n\033[0;34m=== $1 ===\033[0m\n"
}

log_header "Deployment: $(date)"
log_info "Image: $IMAGE"
log_info "Container: $CONTAINER"
log_info "Port: $PORT"

# Pull latest image
log_info "Pulling latest image..."
if ! docker pull "$IMAGE"; then
    log_error "Failed to pull image: $IMAGE"
    exit 1
fi

# Get current image digest
CURRENT_DIGEST=$(docker inspect --format='{{.Image}}' "$CONTAINER" 2>/dev/null || echo "")
NEW_DIGEST=$(docker inspect --format='{{.Id}}' "$IMAGE" 2>/dev/null || echo "")

# Skip if image hasn't changed
if [[ "$CURRENT_DIGEST" = "$NEW_DIGEST" ]]; then
    log_info "Image unchanged, skipping deployment"
    exit 0
fi

# Stop and remove old container
log_info "Stopping existing container..."
docker stop "$CONTAINER" 2>/dev/null || true
docker rm "$CONTAINER" 2>/dev/null || true

# Start new container
log_info "Starting new container..."
docker run -d \
    --name "$CONTAINER" \
    --restart unless-stopped \
    -p "$PORT:8080" \
    -e ENV=${DEPLOYMENT_ENV:-production} \
    --log-driver json-file \
    --log-opt max-size=10m \
    --log-opt max-file=3 \
    "$IMAGE"

# Wait for container to start
log_info "Waiting for container to start..."
sleep 10

# Health check
log_info "Running health check..."
if curl -f http://localhost:$PORT/health 2>/dev/null; then
    log_success "Health check passed"
else
    log_warning "Health check failed, showing logs:"
    docker logs "$CONTAINER" --tail 50
    exit 1
fi

log_success "Deployment complete!"
EOF

    sudo chmod +x "$PULL_DEPLOY_SCRIPT"
    log_success "Created pull-and-deploy script"

    # Create health check script
    HEALTH_CHECK_SCRIPT="/opt/scripts/health-check.sh"
    sudo mkdir -p "$(dirname "$HEALTH_CHECK_SCRIPT")"
    log_info "Creating health check script: $HEALTH_CHECK_SCRIPT"

    sudo tee "$HEALTH_CHECK_SCRIPT" > /dev/null << 'EOF'
#!/bin/bash
set -e

CONTAINER="${CONTAINER_NAME:-app-prod}"
PORT="${PORT:-80}"

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

# Check if container is running
if ! docker inspect --format='{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true; then
    log_error "Container $CONTAINER is not running!"
    exit 1
fi

# Check if container is healthy
if docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null | grep -q "unhealthy"; then
    log_error "Container $CONTAINER is unhealthy!"
    exit 1
fi

# Check HTTP endpoint
if ! curl -f http://localhost:$PORT/health 2>/dev/null; then
    log_error "Health check endpoint failed!"
    exit 1
fi

log_success "Container $CONTAINER is healthy"
exit 0
EOF

    sudo chmod +x "$HEALTH_CHECK_SCRIPT"
    log_success "Created health check script"

    # Create log directory
    sudo mkdir -p /var/log/deploy
    log_success "Created log directory: /var/log/deploy"
}

# Setup cron job for auto-deploy
setup_cron_job() {
    if [[ "$AUTO_DEPLOY" != true ]]; then
        log_info "Auto-deploy disabled, skipping cron setup"
        return 0
    fi

    log_header "Setting Up Auto-Deploy Cron Job"

    CRON_FILE="/etc/cron.d/auto-deploy"
    ENV_FILE="/etc/default/deploy-config"

    # Create environment file for configuration
    log_info "Creating configuration file: $ENV_FILE"

    sudo tee "$ENV_FILE" > /dev/null << EOF
# Deployment Configuration
# These variables are sourced by the deployment script

IMAGE_NAME="$IMAGE_NAME"
CONTAINER_NAME="$CONTAINER_NAME"
PORT="$PORT"
DEPLOYMENT_ENV="$DEPLOYMENT_MODE"
EOF

    log_success "Created configuration file"

    # Create cron file
    log_info "Creating cron file: $CRON_FILE"

    sudo tee "$CRON_FILE" > /dev/null << EOF
# Auto-deploy cron job
# Runs: $CRON_INTERVAL
# Logs to: /var/log/deploy/auto-deploy.log

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

$CRON_INTERVAL root /usr/local/bin/pull-and-deploy.sh >> /var/log/deploy/auto-deploy.log 2>&1
EOF

    log_success "Created cron file"
    log_success "Auto-deploy enabled with interval: $CRON_INTERVAL"
    log_info "Logs will be written to: /var/log/deploy/auto-deploy.log"
}

# Pre-pull base images
pre_pull_images() {
    log_header "Pre-pulling Images"

    if [[ -z "$IMAGE_NAME" ]]; then
        log_warning "No image name configured. Skipping pre-pull."
        return 0
    fi

    log_info "Pulling image: $IMAGE_NAME"
    if docker pull "$IMAGE_NAME"; then
        log_success "Pulled: $IMAGE_NAME"
    else
        log_error "Failed to pull: $IMAGE_NAME"
        return 1
    fi
}

# Display post-implementation summary
display_summary() {
    log_header "Implementation Summary"

    echo "The following changes have been made:"
    echo ""
    echo "1. ✅ Created persistent cache directory: /var/lib/buildkit/cache"
    echo "2. ✅ Updated daemon.json with BuildKit optimizations"
    echo "3. ✅ Backed up original configuration to: /home/ev3lynx/guide/backup/config/"
    echo "4. ✅ Created deployment scripts:"
    echo "     - /usr/local/bin/pull-and-deploy.sh"
    echo "     - /opt/scripts/health-check.sh"
    if [[ "$AUTO_DEPLOY" == true ]]; then
        echo "5. ✅ Setup auto-deploy cron job: /etc/cron.d/auto-deploy"
    fi
    echo ""

    echo "Configuration:"
    echo "  - Deployment Mode: $DEPLOYMENT_MODE"
    echo "  - Container Name: $CONTAINER_NAME"
    echo "  - Host Port: $PORT"
    echo "  - Image Name: $IMAGE_NAME"
    echo "  - Auto-Deploy: $AUTO_DEPLOY"
    echo ""

    echo "Next steps:"
    echo ""
    echo "1. Test deployment manually:"
    if [[ -z "$IMAGE_NAME" ]]; then
        echo "   IMAGE_NAME=ghcr.io/your-org/repo:latest /usr/local/bin/pull-and-deploy.sh"
    else
        echo "   /usr/local/bin/pull-and-deploy.sh"
    fi
    echo ""
    echo "2. Check container status:"
    echo "   docker ps"
    echo "   docker logs $CONTAINER_NAME"
    echo ""
    echo "3. Run health check:"
    echo "   /opt/scripts/health-check.sh"
    echo ""
    if [[ "$AUTO_DEPLOY" == true ]]; then
        echo "4. Monitor auto-deploy logs:"
        echo "   tail -f /var/log/deploy/auto-deploy.log"
        echo ""
    fi
    echo "5. Verify BuildKit configuration:"
    echo "   docker system df"
    echo "   docker info | grep -A 10 'BuildKit'"
    echo ""
    echo "6. View cache usage:"
    echo "   du -sh /var/lib/buildkit/cache"
    echo ""

    log_success "Setup completed successfully!"
}

# Display architecture overview
display_architecture_overview() {
    log_header "Architecture Overview"

    echo "This VM is configured as a Deployment Target in the cloud-native CI/CD pipeline:"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                     CI/CD Pipeline                          │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│                                                             │"
    echo "│  1. Developer pushes code to GitHub                         │"
    echo "│     └─▶ Triggers GitHub Actions workflow                     │"
    echo "│                                                             │"
    echo "│  2. GitHub Actions (Cloud Runner)                             │"
    echo "│     └─▶ Builds image with BuildKit                           │"
    echo "│     └─▶ Pushes to GHCR                                     │"
    echo "│     └─▶ Runs vulnerability scan                              │"
    echo "│                                                             │"
    echo "│  3. GitHub Container Registry (GHCR)                         │"
    echo "│     └─▶ Stores image layers and cache                        │"
    echo "│                                                             │"
    echo "│  4. This VM (Deployment Target)                             │"
    echo "│     └─▶ Pulls image from GHCR                               │"
    echo "│     └─▶ Deploys container                                    │"
    echo "│     └─▶ Uses BuildKit cache for faster pulls                  │"
    echo "│                                                             │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
}

# Display optional enhancements
display_optional_enhancements() {
    log_header "Optional Enhancements"

    echo "The following enhancements are optional and not implemented by this script:"
    echo ""
    echo "1. GPU-enabled deployment (if your app needs GPU)"
    echo "   Add '--gpus all' to docker run command in pull-and-deploy.sh"
    echo ""
    echo "2. Multi-container deployment (Docker Compose)"
    echo "   Create docker-compose.yml and use 'docker compose up -d'"
    echo ""
    echo "3. Load balancer integration"
    echo "   Configure NGINX or HAProxy in front of containers"
    echo ""
    echo "4. Monitoring and alerting (Prometheus + Grafana)"
    echo "   Set up metrics collection and alerting rules"
    echo ""
    echo "5. Database migrations"
    echo "   Add migration script to pull-and-deploy.sh"
    echo ""
    echo "6. Blue/Green deployments"
    echo "   Implement zero-downtime deployment strategy"
    echo ""
    log_info "See /home/ev3lynx/guide/overview.md for details"
}

# Main function
main() {
    parse_args "$@"

    # Load environment variables from .env file
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local env_file="$(dirname "$script_dir")/.env"
    load_env "$env_file"

    log_header "Docker Deployment Configuration Script"
    log_info "This script configures your DevOps VM as a pull-only deployment target"
    log_info "Architecture: Cloud-native CI/CD (GitHub Actions + GHCR)"
    echo ""

    display_architecture_overview

    if [[ "$NON_INTERACTIVE" != true ]]; then
        read -p "Do you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Script cancelled by user"
            exit 0
        fi
    fi

    # Prerequisite checks
    log_header "Prerequisite Checks"
    check_root
    check_sudo
    check_docker
    check_buildkit
    check_docker_daemon
    check_disk_space
    check_nvidia_runtime
    check_cache_directory

    # Configuration prompts (only in interactive mode)
    if [[ "$NON_INTERACTIVE" != true ]]; then
        prompt_deployment_mode
        prompt_image_name
        prompt_port_config
        prompt_auto_deploy
    fi

    # Implementation steps
    create_backup
    create_cache_directory
    setup_ghcr_auth

    if update_daemon_json; then
        restart_docker
    fi

    create_deployment_scripts
    setup_cron_job

    # Optional steps
    pre_pull_images

    # Summary
    display_summary
    display_optional_enhancements
}

# Run main function
main
