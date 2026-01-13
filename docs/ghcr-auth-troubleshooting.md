# GHCR Authentication Troubleshooting Guide

## Table of Contents

1. [Overview](#overview)
2. [Authentication Methods](#authentication-methods)
3. [Common Errors and Solutions](#common-errors-and-solutions)
4. [Docker CLI Authentication](#docker-cli-authentication)
5. [GitHub CLI Authentication](#github-cli-authentication)
6. [Diagnostic Commands](#diagnostic-commands)
7. [Creating and Managing PATs](#creating-and-managing-pats)
8. [Advanced Troubleshooting](#advanced-troubleshooting)
9. [Best Practices](#best-practices)
10. [Quick Reference](#quick-reference)

---

## Overview

GitHub Container Registry (GHCR) requires proper authentication for:
- Pushing images
- Pulling private images
- Pulling public images (recommended for rate limiting)

This guide covers comprehensive troubleshooting for GHCR authentication issues.

---

## Authentication Methods

### Method 1: Docker CLI (Recommended for Production)
- Direct authentication with Docker daemon
- Works with all Docker tools
- Required for build/push operations

### Method 2: GitHub CLI (gh)
- Modern GitHub authentication
- Automatic token management
- Easier for multiple accounts
- Can delegate to Docker

### Method 3: GitHub Actions (CI/CD)
- Uses GITHUB_TOKEN automatically
- No manual configuration needed
- Best for automated workflows

---

## Common Errors and Solutions

### Error 1: "denied: denied"

**Cause:** Invalid credentials or no credentials stored

**Solutions:**
```bash
# Check current auth
cat ~/.docker/config.json | jq '.auths | keys'

# If ghcr.io is missing, login
echo "ghp_PAT" | docker login ghcr.io -u USERNAME --password-stdin
```

### Error 2: "no basic auth credentials"

**Cause:** Credentials not found in Docker config

**Solutions:**
```bash
# Check config exists
ls -la ~/.docker/config.json

# If missing or corrupted, logout and login again
docker logout ghcr.io
echo "ghp_PAT" | docker login ghcr.io -u USERNAME --password-stdin
```

### Error 3: "unauthorized: authentication required"

**Cause:** PAT missing required scope

**Solutions:**
- Verify PAT has `write:packages` scope for push
- Verify PAT has `read:packages` scope for pull
- Create new PAT with correct scopes (see [Creating PATs](#creating-and-managing-pats))

### Error 4: "toomanyrequests: You have reached your pull rate limit"

**Cause:** Pulling public images without authentication

**Solutions:**
```bash
# Always login even for public images
echo "ghp_PAT" | docker login ghcr.io -u USERNAME --password-stdin
```

### Error 5: "Error saving credentials: error storing credentials"

**Cause:** Credential helper issue

**Solutions:**
```bash
# Check credential helper
cat ~/.docker/config.json | jq '.credsStore'

# Reset credential helper
sudo apt-get remove -y docker-credential-helper
docker logout ghcr.io
echo "ghp_PAT" | docker login ghcr.io -u USERNAME --password-stdin
```

---

## Docker CLI Authentication

### Step 1: Create PAT

See [Creating and Managing PATs](#creating-and-managing-pats)

### Step 2: Login

```bash
# Method 1: Echo PAT (recommended for automation)
echo "ghp_your_pat_here" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# Method 2: Interactive (will prompt for password)
docker login ghcr.io -u YOUR_GITHUB_USERNAME

# Method 3: From environment variable
docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin <<< "$GITHUB_TOKEN"
```

### Step 3: Verify Authentication

```bash
# Check config
cat ~/.docker/config.json | jq '.auths."ghcr.io"'

# Should see something like:
# {
#   "auth": "base64_encoded_credentials"
# }

# Test authentication by pulling any GHCR image
docker pull ghcr.io/actions/runner:latest
```

### Step 4: Verify with Docker Info

```bash
# Check Docker info for registry configuration
docker info | grep -A 5 "Registry"

# Expected output should include ghcr.io
```

### Docker Config Location

- **Linux:** `~/.docker/config.json`
- **macOS:** `~/.docker/config.json`
- **Windows:** `%USERPROFILE%\.docker\config.json`

---

## GitHub CLI Authentication

### Prerequisites

```bash
# Install gh CLI
# Ubuntu/Debian
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh

# Verify installation
gh --version
```

### Step 1: Authenticate with GitHub

```bash
# Method 1: Interactive authentication (opens browser)
gh auth login

# Follow prompts:
# 1. What account do you want to log into? → GitHub.com
# 2. What is your preferred protocol? → HTTPS
# 3. Authenticate Git with your GitHub credentials? → Yes
# 4. How would you like to authenticate? → Login with a web browser
# 5. Open browser to authenticate

# Method 2: With token
gh auth login --with-token <<< "ghp_your_pat_here"
```

### Step 2: Verify Authentication

```bash
# Check current user
gh auth status

# Check token scopes
gh auth token

# Test GHCR access
gh repo view
```

### Step 3: Login to GHCR Using gh CLI

#### Option A: Use `gh auth login` (Recommended)

```bash
# gh CLI automatically configures Docker for GHCR
gh auth login

# When prompted:
# - Choose: GitHub.com
# - Choose: HTTPS
# - Authenticate: Yes
# - Choose: Login with a web browser
```

After authentication, gh CLI automatically stores credentials in `~/.docker/config.json`.

#### Option B: Manual Delegation

```bash
# Get current token
TOKEN=$(gh auth token)

# Use token for Docker login
echo "$TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

#### Option C: Use gh CLI Container Registry Commands

```bash
# List packages
gh package list --owner USERNAME --type container

# View package details
gh package view OWNER/REPO --type container

# Pull image using gh (delegates to Docker)
gh cache list  # Uses Docker under the hood
```

### Step 4: Verify Docker Configuration

```bash
# Verify gh CLI configured Docker auth
cat ~/.docker/config.json | jq '.auths."ghcr.io"'

# Should see credentials set by gh CLI
```

### gh CLI Authentication Storage

- **Token storage:** `~/.config/gh/hosts.yml`
- **Docker config:** `~/.docker/config.json` (updated by gh CLI)
- **Token refresh:** Automatic when using gh CLI

---

## Diagnostic Commands

### Basic Diagnostics

```bash
# 1. Check Docker daemon is running
sudo systemctl status docker.service

# 2. Check Docker version
docker --version
docker info

# 3. Check current Docker authentication
cat ~/.docker/config.json

# 4. Verify GHCR is reachable
curl -I https://ghcr.io/v2/

# Expected: 401 Unauthorized (this is correct, means GHCR is reachable)
```

### Advanced Diagnostics

```bash
# 5. Check Docker network connectivity
docker run --rm alpine ping -c 3 ghcr.io

# 6. Check DNS resolution
docker run --rm alpine nslookup ghcr.io

# 7. Check Docker registry configuration
docker info | grep -A 10 "Registry"

# 8. Check credential helper
cat ~/.docker/config.json | jq '.credsStore'

# 9. Test actual pull with verbose output
docker pull ghcr.io/actions/runner:latest --debug

# 10. Check auth token expiry
# Decode base64 auth token
AUTH=$(cat ~/.docker/config.json | jq -r '.auths."ghcr.io".auth')
echo "$AUTH" | base64 -d
```

### gh CLI Diagnostics

```bash
# 1. Check gh CLI version
gh --version

# 2. Check current auth status
gh auth status

# 3. Check available extensions
gh extension list

# 4. Check GHCR access
gh api /user/packages

# 5. Test token permissions
gh auth token
```

---

## Creating and Managing PATs

### Step-by-Step PAT Creation

1. **Go to GitHub Settings**
   - Visit: https://github.com/settings/tokens
   - Click "Generate new token" → "Generate new token (classic)"

2. **Configure Token**
   - **Note:** Enter descriptive name (e.g., "GHCR Docker Auth")
   - **Expiration:** Choose appropriate expiration (90 days or no expiration)
   - **Scopes:**
     - `read:packages` - Required for pulling images
     - `write:packages` - Required for pushing images
     - `delete:packages` - Required for deleting images (optional)
     - `repo` - Required if images are in private repos

3. **Generate and Copy**
   - Click "Generate token"
   - **Important:** Copy token immediately (won't be shown again)

4. **Store Securely**
   ```bash
   # Add to environment (not recommended for production)
   export GITHUB_TOKEN="ghp_your_pat_here"

   # Add to .env file (with proper permissions)
   echo "GITHUB_TOKEN=ghp_your_pat_here" >> .env
   chmod 600 .env

   # Or use a secrets manager (recommended for production)
   ```

### PAT Scopes Reference

| Scope | Purpose | Required For |
|-------|---------|--------------|
| `read:packages` | Read container packages | Pulling images |
| `write:packages` | Write container packages | Pushing images |
| `delete:packages` | Delete container packages | Deleting images |
| `repo` | Full repo access | Private repo images |
| `public_repo` | Public repo access | Public repo images |

### Using Fine-Grained Tokens (Newer Method)

Fine-grained personal access tokens offer more security:

1. **Go to:** https://github.com/settings/tokens?type=beta
2. **Click:** "Generate new token"
3. **Configure:**
   - **Token name:** Descriptive name
   - **Expiration:** Choose expiration
   - **Resource owner:** Your username or organization
   - **Repository access:** Select repositories or "All repositories"
   - **Permissions:**
     - Contents: Read only (or Read and write)
     - Packages: Read and write (or Read only for pulls)
4. **Generate and copy**

---

## Advanced Troubleshooting

### Issue: Docker Daemon Cached Credentials

**Symptoms:** Login succeeds but authentication still fails

**Solution:**
```bash
# 1. Logout from GHCR
docker logout ghcr.io

# 2. Stop Docker daemon
sudo systemctl stop docker.service

# 3. Clear credential cache
rm -f ~/.docker/config.json

# 4. Restart Docker daemon
sudo systemctl start docker.service

# 5. Login again
echo "ghp_PAT" | docker login ghcr.io -u USERNAME --password-stdin
```

### Issue: Credential Helper Conflicts

**Symptoms:** Authentication works but credentials aren't persisted

**Solution:**
```bash
# 1. Check current credential helper
cat ~/.docker/config.json | jq '.credsStore'

# 2. If set to a helper that's not working, remove it
jq 'del(.credsStore)' ~/.docker/config.json > /tmp/config.json
mv /tmp/config.json ~/.docker/config.json

# 3. Login again
echo "ghp_PAT" | docker login ghcr.io -u USERNAME --password-stdin
```

### Issue: Token Expired

**Symptoms:** Authentication suddenly fails after working fine

**Solution:**
```bash
# 1. Create new PAT (see section above)

# 2. Logout and login with new token
docker logout ghcr.io
echo "ghp_NEW_PAT" | docker login ghcr.io -u USERNAME --password-stdin
```

### Issue: Multiple GitHub Accounts

**Symptoms:** Wrong account being used for authentication

**Solution:**
```bash
# 1. Logout from all
docker logout ghcr.io
gh auth logout

# 2. Re-authenticate with correct account
gh auth login

# 3. Verify
gh auth status
cat ~/.docker/config.json | jq '.auths."ghcr.io"'
```

### Issue: Proxy or Network Issues

**Symptoms:** Can't reach GHCR

**Solution:**
```bash
# 1. Test direct connectivity
curl -v https://ghcr.io/v2/

# 2. Check Docker proxy settings
docker info | grep -i proxy

# 3. Configure Docker proxy if needed
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo nano /etc/systemd/system/docker.service.d/http-proxy.conf

# Add:
# [Service]
# Environment="HTTP_PROXY=http://proxy.example.com:8080"
# Environment="HTTPS_PROXY=http://proxy.example.com:8080"
# Environment="NO_PROXY=localhost,127.0.0.1"

# 4. Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart docker.service
```

---

## Best Practices

### Security

1. **Never commit PATs to git**
   ```bash
   # Add to .gitignore
   echo ".env" >> .gitignore
   echo "*.token" >> .gitignore
   ```

2. **Use environment variables**
   ```bash
   export GITHUB_TOKEN="ghp_PAT"
   docker login ghcr.io -u USERNAME --password-stdin <<< "$GITHUB_TOKEN"
   ```

3. **Use fine-grained tokens** when possible for better security

4. **Set token expiration** to limit exposure

5. **Rotate tokens regularly** every 90 days

### Authentication

1. **Always authenticate** even for public images to avoid rate limits

2. **Use gh CLI** for easier management when possible

3. **Verify authentication** before critical operations

4. **Logout from public systems** after use

### Automation

1. **Use GitHub Actions GITHUB_TOKEN** for CI/CD
   ```yaml
   - name: Login to GHCR
     uses: docker/login-action@v3
     with:
       registry: ghcr.io
       username: ${{ github.actor }}
       password: ${{ secrets.GITHUB_TOKEN }}
   ```

2. **Store PATs in secrets managers** for production

3. **Automate token refresh** for long-running systems

### Performance

1. **Enable BuildKit cache** for faster builds
2. **Use layer caching** appropriately
3. **Minimize image size** to reduce pull times

---

## Quick Reference

### Docker CLI Quick Commands

```bash
# Login
echo "ghp_PAT" | docker login ghcr.io -u USERNAME --password-stdin

# Logout
docker logout ghcr.io

# Check auth
cat ~/.docker/config.json | jq '.auths."ghcr.io"'

# Test pull
docker pull ghcr.io/OWNER/REPO:TAG

# Test push
docker tag IMAGE ghcr.io/OWNER/REPO:TAG
docker push ghcr.io/OWNER/REPO:TAG
```

### gh CLI Quick Commands

```bash
# Authenticate
gh auth login

# Check status
gh auth status

# Logout
gh auth logout

# List packages
gh package list --owner OWNER --type container

# View package
gh package view OWNER/REPO --type container
```

### Common Error Fixes

```bash
# Error: denied: denied
echo "ghp_PAT" | docker login ghcr.io -u USERNAME --password-stdin

# Error: no basic auth credentials
docker logout ghcr.io
echo "ghp_PAT" | docker login ghcr.io -u USERNAME --password-stdin

# Error: unauthorized: authentication required
# Check PAT has correct scopes: read:packages and/or write:packages

# Error: toomanyrequests
# Login even for public images
echo "ghp_PAT" | docker login ghcr.io -u USERNAME --password-stdin

# Cached credentials issue
docker logout ghcr.io
sudo systemctl restart docker.service
echo "ghp_PAT" | docker login ghcr.io -u USERNAME --password-stdin
```

### Diagnostic Sequence

```bash
# 1. Check Docker
sudo systemctl status docker.service
docker --version

# 2. Check GHCR connectivity
curl -I https://ghcr.io/v2/

# 3. Check auth
cat ~/.docker/config.json | jq '.auths."ghcr.io"'

# 4. Test pull
docker pull ghcr.io/actions/runner:latest

# 5. Check gh CLI
gh --version
gh auth status
```

---

## Summary

- **Docker CLI:** Best for production and automation
- **gh CLI:** Best for development and management
- **GitHub Actions:** Best for CI/CD
- **Always:** Use authentication even for public images
- **Security:** Never commit tokens, rotate regularly
- **Diagnostics:** Check config, connectivity, and auth status
- **Most common issue:** Expired or invalid PAT → Create new PAT and login again

---

## Related Documentation

- [GitHub Container Registry Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [GitHub CLI Documentation](https://cli.github.com/manual/)
- [Docker Documentation](https://docs.docker.com/)
- [BuildKit Documentation](https://github.com/moby/buildkit)

---

**Version:** 1.0
**Last Updated:** 2025-01-12
**Author:** DevOps Team
