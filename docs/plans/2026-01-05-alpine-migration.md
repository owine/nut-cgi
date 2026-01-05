# Alpine 3.23 Migration with Multi-Arch CI/CD Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform Debian-based nut-cgi image to Alpine 3.23 with security hardening, multi-architecture support, and automated dependency management.

**Architecture:** Multi-stage Dockerfile with non-root user, flexible UID support, enhanced health checks, GitHub Actions for multi-arch builds (amd64/arm64), Trivy security scanning, and Renovate automation.

**Tech Stack:** Alpine Linux 3.23, Docker Buildx, GitHub Actions, GHCR, Renovate, Trivy, Hadolint, shellcheck

---

## Prerequisites

**Working Directory:** `~/Git/nut-cgi`

**Required Tools:**
- Docker with Buildx support
- git
- GitHub CLI (`gh`) for testing workflows locally (optional)

**Branch Strategy:**
- Work on `main` branch (single-maintainer repo)
- Tag releases as `v1.0.0`, `v1.0.1`, etc.

---

## Task 1: Project Foundation Files

### Step 1: Create .dockerignore for build optimization

**Files:**
- Create: `~/Git/nut-cgi/.dockerignore`

**Code:**
```
.git
.github
.gitignore
README.md
docs/
*.md
.dockerignore
docker-compose.yml
```

**Rationale:** Exclude unnecessary files from Docker build context for faster builds and smaller context size.

**Step 2: Create enhanced healthcheck script

**Files:**
- Create: `~/Git/nut-cgi/healthcheck.sh`

**Code:**
```sh
#!/bin/sh
# Enhanced health check for nut-cgi with three-tier validation
# Supports execution by any UID (for --user override compatibility)

# Tier 1: Web server responding
if ! curl -f -s -o /dev/null http://localhost/upsstats.cgi; then
    echo "ERROR: lighttpd not responding"
    exit 1
fi

# Tier 2: CGI execution working
response=$(curl -s http://localhost/upsstats.cgi)
if [ -z "$response" ]; then
    echo "ERROR: nut-cgi not executing"
    exit 1
fi

# Tier 3: Valid CGI output (not error page)
if echo "$response" | grep -qi "error\|failed\|not found"; then
    echo "WARN: nut-cgi returned error content"
    exit 1
fi

echo "OK: nut-cgi healthy"
exit 0
```

**Step 3: Make healthcheck.sh executable and commit

**Commands:**
```bash
cd ~/Git/nut-cgi
chmod +x healthcheck.sh
git add .dockerignore healthcheck.sh
git commit -m "feat: add dockerignore and enhanced health check script"
```

**Expected:** Clean commit with 2 files added.

---

## Task 2: Alpine-Based Multi-Stage Dockerfile

### Step 1: Determine current Alpine 3.23 package versions

**Command:**
```bash
docker run --rm alpine:3.23 sh -c "apk update && apk search -e nut-cgi lighttpd curl"
```

**Expected Output:** Package versions available in Alpine 3.23 repos
- Example: `nut-cgi-2.8.0-r5`, `lighttpd-1.4.73-r0`, `curl-8.5.0-r0`

**Action:** Note these versions for the Dockerfile RUN command in next step.

### Step 2: Create new Dockerfile with Alpine 3.23 base

**Files:**
- Modify: `~/Git/nut-cgi/Dockerfile` (complete rewrite)

**Code:**
```dockerfile
# Multi-stage build for minimal runtime image
FROM alpine:3.23 AS builder

# Verify Alpine version
RUN cat /etc/alpine-release

# Builder stage intentionally minimal - all installation happens in runtime stage
# This stage reserved for future build-time operations if needed

# ============================================================================
# Runtime Stage - Minimal footprint with pinned versions
# ============================================================================
FROM alpine:3.23

# Image metadata
LABEL org.opencontainers.image.title="nut-cgi" \
      org.opencontainers.image.description="Network UPS Tools CGI interface with lighttpd on Alpine Linux" \
      org.opencontainers.image.vendor="owine" \
      org.opencontainers.image.source="https://github.com/owine/nut-cgi" \
      org.opencontainers.image.licenses="MIT"

# Install pinned package versions for reproducibility
# NOTE: Update versions based on `apk search -e <package>` output from Step 1
RUN apk add --no-cache \
    nut-cgi=2.8.0-r5 \
    lighttpd=1.4.73-r0 \
    curl=8.5.0-r0 && \
    # Verify installations
    lighttpd -v && \
    upsstats.cgi -h || true && \
    curl --version

# Create non-root user with fixed UID/GID for default operation
# UID 1000 is standard for first user, ensures compatibility
RUN addgroup -g 1000 nut && \
    adduser -D -u 1000 -G nut -h /home/nut nut

# Configure lighttpd for non-root operation and arbitrary UID support
RUN mkdir -p /var/log/lighttpd /var/lib/lighttpd && \
    # Make directories accessible by any UID (for --user override)
    chown -R nut:nut /var/log/lighttpd /var/lib/lighttpd && \
    chmod 755 /var/log/lighttpd /var/lib/lighttpd && \
    # Disable default unconfigured site
    rm -f /etc/lighttpd/conf.d/*-unconfigured.conf

# Configure lighttpd: enable CGI, set document root, configure logging
RUN sed -i 's|^#\(.*mod_accesslog.*\)|\1|' /etc/lighttpd/lighttpd.conf && \
    sed -i 's|^#\(.*mod_cgi.*\)|\1|' /etc/lighttpd/lighttpd.conf && \
    # Set document root to nut CGI directory
    sed -i 's|^\(server.document-root.*=\).*|\1 "/usr/lib/cgi-bin/nut"|g' /etc/lighttpd/lighttpd.conf && \
    # Set default index to upsstats.cgi
    sed -i 's|^\(index-file.names.*=\).*|\1 ( "upsstats.cgi" )|g' /etc/lighttpd/lighttpd.conf && \
    # Configure PID file in /tmp for any UID to write
    sed -i 's|^\(server.pid-file.*=\).*|\1 "/tmp/lighttpd.pid"|g' /etc/lighttpd/lighttpd.conf && \
    # Configure CGI to serve from root path (remove /cgi-bin/ prefix)
    echo '' >> /etc/lighttpd/lighttpd.conf && \
    echo '# CGI configuration for nut' >> /etc/lighttpd/lighttpd.conf && \
    echo 'cgi.assign = ( ".cgi" => "" )' >> /etc/lighttpd/lighttpd.conf

# Make NUT config directory world-readable for --user UID override compatibility
RUN mkdir -p /etc/nut && \
    chmod 755 /etc/nut

# Copy health check script with execute permissions for any user
COPY --chmod=0755 healthcheck.sh /healthcheck.sh

# Switch to non-root user for runtime
# Can be overridden with docker run --user <uid>:<gid>
USER nut

# Expose HTTP port
EXPOSE 80

# Health check using enhanced script
# - interval=30s: Check every 30 seconds
# - timeout=10s: Allow 10s for CGI processing
# - start-period=15s: Grace period for container initialization
# - retries=3: Require 3 consecutive failures before unhealthy
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD ["/healthcheck.sh"]

# Run lighttpd in foreground mode
CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/lighttpd.conf"]
```

**Step 3: Update package versions in Dockerfile

**Action:** Edit the `RUN apk add` line in the Dockerfile with actual versions from Step 1.

**Example:**
```dockerfile
RUN apk add --no-cache \
    nut-cgi=2.8.1-r0 \
    lighttpd=1.4.76-r0 \
    curl=8.11.1-r0
```

### Step 4: Commit Dockerfile changes

**Commands:**
```bash
cd ~/Git/nut-cgi
git add Dockerfile
git commit -m "feat: migrate to Alpine 3.23 with multi-stage build

- Replace Debian base with Alpine 3.23 for smaller image
- Add non-root user (UID 1000) with --user override support
- Pin package versions for reproducibility
- Configure lighttpd for non-root operation
- Enhanced health check integration
- World-readable configs for flexible UID support"
```

**Expected:** Clean commit with Dockerfile changes.

---

## Task 3: GitHub Actions - Lint Workflow

### Step 1: Create GitHub Actions directory structure

**Commands:**
```bash
cd ~/Git/nut-cgi
mkdir -p .github/workflows
```

### Step 2: Create lint.yml workflow

**Files:**
- Create: `~/Git/nut-cgi/.github/workflows/lint.yml`

**Code:**
```yaml
name: Lint

on:
  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  hadolint:
    name: Dockerfile Linting
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run hadolint
        uses: hadolint/hadolint-action@v3.1.0
        with:
          dockerfile: Dockerfile
          failure-threshold: warning

  shellcheck:
    name: Shell Script Linting
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Run shellcheck on healthcheck.sh
        run: |
          sudo apt-get update
          sudo apt-get install -y shellcheck
          shellcheck healthcheck.sh

  yaml-lint:
    name: YAML Linting
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install yamllint
        run: pip install yamllint

      - name: Run yamllint on workflows
        run: yamllint .github/workflows/
```

**Step 3: Commit lint workflow

**Commands:**
```bash
cd ~/Git/nut-cgi
git add .github/workflows/lint.yml
git commit -m "ci: add lint workflow for Dockerfile, shell, and YAML validation"
```

**Expected:** Lint workflow committed.

---

## Task 4: GitHub Actions - Multi-Arch Build Workflow

### Step 1: Create build.yml workflow

**Files:**
- Create: `~/Git/nut-cgi/.github/workflows/build.yml`

**Code:**
```yaml
name: Build and Push Multi-Arch Image

on:
  push:
    branches: ["main"]
    tags: ["v*.*.*"]
  pull_request:
    branches: ["main"]
  workflow_dispatch:
    inputs:
      force-rebuild:
        description: 'Force rebuild without cache'
        required: false
        type: boolean
        default: false

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

permissions:
  contents: read
  packages: write
  id-token: write

jobs:
  build:
    name: Build and Push
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GitHub Container Registry
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata (tags, labels)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            # Tag with version for releases
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=semver,pattern={{major}}
            # Tag with branch name
            type=ref,event=branch
            # Tag with pr number
            type=ref,event=pr
            # Tag with sha
            type=sha,prefix=sha-
            # Tag latest for main branch
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          provenance: true
          sbom: true
          no-cache: ${{ github.event.inputs.force-rebuild == 'true' }}

      - name: Image digest
        run: echo "Image pushed with digest ${{ steps.build.outputs.digest }}"
```

**Step 2: Commit build workflow

**Commands:**
```bash
cd ~/Git/nut-cgi
git add .github/workflows/build.yml
git commit -m "ci: add multi-arch build workflow for amd64 and arm64

- Build for linux/amd64 and linux/arm64 platforms
- Publish to GitHub Container Registry (GHCR)
- Semantic versioning support with multiple tag variants
- Build caching for faster subsequent builds
- SBOM and provenance attestations for supply chain security
- Test builds on PRs without publishing"
```

**Expected:** Build workflow committed.

---

## Task 5: GitHub Actions - Security Scanning Workflow

### Step 1: Create security.yml workflow

**Files:**
- Create: `~/Git/nut-cgi/.github/workflows/security.yml`

**Code:**
```yaml
name: Security Scan

on:
  # Run after successful build
  workflow_run:
    workflows: ["Build and Push Multi-Arch Image"]
    types: [completed]
    branches: [main]
  # Weekly scheduled scan
  schedule:
    - cron: '0 0 * * 1'  # Monday at 00:00 UTC
  # Manual trigger
  workflow_dispatch:

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

permissions:
  contents: read
  packages: read
  security-events: write

jobs:
  scan:
    name: Trivy Security Scan
    runs-on: ubuntu-latest
    if: ${{ github.event.workflow_run.conclusion == 'success' || github.event_name != 'workflow_run' }}
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Pull latest image
        run: docker pull ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'HIGH,CRITICAL'
          exit-code: '1'

      - name: Upload Trivy results to GitHub Security
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: 'trivy-results.sarif'

      - name: Run Trivy for human-readable output
        if: always()
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          format: 'table'
          severity: 'HIGH,CRITICAL'
```

**Step 2: Commit security workflow

**Commands:**
```bash
cd ~/Git/nut-cgi
git add .github/workflows/security.yml
git commit -m "ci: add Trivy security scanning workflow

- Scan published images for vulnerabilities
- Run after successful builds and weekly on schedule
- Upload results to GitHub Security tab
- Fail on CRITICAL vulnerabilities
- Support manual trigger for ad-hoc scans"
```

**Expected:** Security workflow committed.

---

## Task 6: Renovate Configuration

**IMPLEMENTATION NOTE:** The original plan assumed Alpine would have a `nut-cgi` package. Since we're building NUT from source, the Renovate configuration needs to be updated to track the `NUT_VERSION` ARG (currently 2.8.3) in addition to Alpine packages. This requires adding a regex rule to match `ARG NUT_VERSION=` patterns and track NUT releases from GitHub.

### Step 1: Create Renovate config

**Files:**
- Create: `~/Git/nut-cgi/.github/renovate.json`

**Code:**
```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:base"
  ],
  "timezone": "America/New_York",
  "schedule": [
    "before 3am on Monday"
  ],
  "semanticCommits": "enabled",
  "commitMessagePrefix": "chore(deps):",
  "packageRules": [
    {
      "description": "Alpine base image - auto-merge patch and digest updates",
      "matchDatasources": ["docker"],
      "matchPackageNames": ["alpine"],
      "groupName": "alpine base image",
      "automerge": true,
      "automergeType": "pr",
      "matchUpdateTypes": ["patch", "digest"]
    },
    {
      "description": "Alpine packages - track with regex manager",
      "matchManagers": ["regex"],
      "matchStrings": [
        "nut-cgi=(?<currentValue>.*?)\\s",
        "lighttpd=(?<currentValue>.*?)\\s",
        "curl=(?<currentValue>.*?)\\s"
      ],
      "datasourceTemplate": "repology",
      "depNameTemplate": "alpine_3_23/{{{packageName}}}",
      "groupName": "alpine packages",
      "automerge": true,
      "matchUpdateTypes": ["patch"]
    },
    {
      "description": "GitHub Actions - group and auto-merge minor/patch",
      "matchManagers": ["github-actions"],
      "groupName": "github actions",
      "automerge": true,
      "automergeType": "pr",
      "matchUpdateTypes": ["patch", "minor"]
    }
  ],
  "vulnerabilityAlerts": {
    "enabled": true,
    "labels": ["security"],
    "assignees": ["owine"]
  },
  "prConcurrentLimit": 5,
  "prHourlyLimit": 2
}
```

**Step 2: Commit Renovate config

**Commands:**
```bash
cd ~/Git/nut-cgi
git add .github/renovate.json
git commit -m "chore: add Renovate configuration for dependency automation

- Auto-merge patch updates for Alpine base and packages
- Weekly update schedule (Monday mornings)
- Group GitHub Actions updates
- Security vulnerability alerts enabled
- Rate limiting to avoid overwhelming PRs"
```

**Expected:** Renovate config committed.

---

## Task 7: Example docker-compose.yml

### Step 1: Create example compose file

**Files:**
- Create: `~/Git/nut-cgi/docker-compose.yml`

**Code:**
```yaml
# Example docker-compose.yml for local testing and development
# This demonstrates security-hardened deployment with version pinning

services:
  nut-cgi:
    # Use specific version tag in production, not latest
    image: ghcr.io/owine/nut-cgi:latest

    # Optional: Run as specific UID/GID
    # Useful when you need to match host filesystem permissions
    # user: "1000:1000"

    # Security: Read-only root filesystem
    # Container can only write to explicitly mounted tmpfs volumes
    read_only: true

    # Security: Writable temp space for PIDs and logs
    tmpfs:
      - /tmp:mode=1777

    # Security: Prevent privilege escalation
    security_opt:
      - no-new-privileges:true

    # Security: Drop all capabilities (none needed for web serving)
    cap_drop:
      - ALL

    # Mount your hosts.conf configuration
    # This file defines which UPS systems to monitor
    volumes:
      - ./hosts.conf:/etc/nut/hosts.conf:ro

    # Map container port 80 to host port 8000
    ports:
      - "8000:80"

    # Restart policy
    restart: unless-stopped

    # Optional: Resource limits
    # deploy:
    #   resources:
    #     limits:
    #       cpus: '0.5'
    #       memory: 128M
    #     reservations:
    #       cpus: '0.1'
    #       memory: 64M

# Example hosts.conf content (create this file in same directory):
#
# MONITOR myups@192.168.1.100 "Living Room UPS"
# MONITOR serverups@192.168.1.101 "Server Rack UPS"
#
# Then start with: docker-compose up -d
# Access at: http://localhost:8000
```

**Step 2: Commit example compose file

**Commands:**
```bash
cd ~/Git/nut-cgi
git add docker-compose.yml
git commit -m "docs: add example docker-compose.yml with security hardening

- Demonstrates version-pinned deployment
- Shows all security hardening options
- Includes resource limits example
- Provides hosts.conf usage example"
```

**Expected:** Compose file committed.

---

## Task 8: LICENSE File

### Step 1: Create MIT License

**Files:**
- Create: `~/Git/nut-cgi/LICENSE`

**Code:**
```
MIT License

Copyright (c) 2026 owine

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

**Step 2: Commit LICENSE

**Commands:**
```bash
cd ~/Git/nut-cgi
git add LICENSE
git commit -m "docs: add MIT license"
```

**Expected:** LICENSE committed.

---

## Task 9: Updated README.md

### Step 1: Rewrite README with new information

**Files:**
- Modify: `~/Git/nut-cgi/README.md`

**Code:**
```markdown
# nut-cgi

Lightweight Docker image for [Network UPS Tools (NUT)](https://networkupstools.org/) CGI web interface, built on Alpine Linux with security hardening and multi-architecture support.

## Features

- **Alpine Linux 3.23** - Minimal base image (~50MB vs ~200MB Debian)
- **Multi-architecture** - Native support for `linux/amd64` and `linux/arm64`
- **Security hardened** - Non-root user, pinned dependencies, vulnerability scanning
- **Flexible UID support** - Works with `--user` override for volume mount permissions
- **Enhanced health checks** - Three-tier validation of web server and CGI functionality
- **Automated updates** - Renovate bot manages dependencies with semantic versioning

## Quick Start

### Docker Run

```bash
docker run -d \
  --name nut-cgi \
  -p 8000:80 \
  -v /path/to/hosts.conf:/etc/nut/hosts.conf:ro \
  --restart unless-stopped \
  ghcr.io/owine/nut-cgi:latest
```

### Docker Compose

See [`docker-compose.yml`](docker-compose.yml) for a complete example with security hardening.

```bash
# Create hosts.conf (see Configuration section)
docker-compose up -d
```

Access the web interface at: `http://localhost:8000`

## Configuration

### hosts.conf

Create a `hosts.conf` file to define which UPS systems to monitor:

```conf
# Monitor local UPS
MONITOR myups@localhost "Living Room UPS"

# Monitor remote UPS systems
MONITOR serverups@192.168.1.100 "Server Rack UPS"
MONITOR officeups@192.168.1.101 "Office UPS"
```

**File location:** `/etc/nut/hosts.conf` inside container

For complete `hosts.conf` syntax, see [NUT documentation](https://networkupstools.org/docs/man/hosts.conf.html).

## Advanced Usage

### Custom UID/GID

Run as a specific user ID to match host filesystem permissions:

```bash
docker run -d \
  --name nut-cgi \
  --user 1001:1001 \
  -p 8000:80 \
  -v /path/to/hosts.conf:/etc/nut/hosts.conf:ro \
  ghcr.io/owine/nut-cgi:latest
```

### Security Hardening

For production deployments, use security options from the example `docker-compose.yml`:

- Read-only root filesystem
- Drop all capabilities
- No new privileges
- tmpfs for writable locations

### Version Pinning

Use specific version tags for production (recommended):

```bash
# Pin to exact version
docker pull ghcr.io/owine/nut-cgi:v1.0.0

# Pin to minor version (receives patch updates)
docker pull ghcr.io/owine/nut-cgi:v1.0

# Pin to major version (receives minor/patch updates)
docker pull ghcr.io/owine/nut-cgi:v1
```

**Available tags:**
- `latest` - Latest build from main branch
- `v1.0.0` - Specific semantic version
- `v1.0` - Latest patch in v1.0.x series
- `v1` - Latest minor in v1.x series
- `sha-<commit>` - Specific commit build

## Architecture

### Multi-Stage Build

- **Stage 1 (builder):** Minimal preparation stage
- **Stage 2 (runtime):** Alpine 3.23 with only nut-cgi, lighttpd, and curl

### Package Versions

All packages are explicitly version-pinned for reproducibility:

- `nut-cgi` - Network UPS Tools CGI programs
- `lighttpd` - Lightweight web server
- `curl` - Health check utility

Package versions are automatically updated by Renovate bot with semantic versioning.

### Health Check

Three-tier validation ensures comprehensive health monitoring:

1. **Tier 1:** Web server responding (HTTP 200)
2. **Tier 2:** CGI execution working (non-empty response)
3. **Tier 3:** Valid CGI output (no error content)

Check intervals: 30s | Timeout: 10s | Start period: 15s | Retries: 3

## Development

### Local Build

```bash
# Clone repository
git clone https://github.com/owine/nut-cgi.git
cd nut-cgi

# Build multi-arch image
docker buildx build --platform linux/amd64,linux/arm64 -t nut-cgi:local .

# Test build locally
docker build -t nut-cgi:test .
docker run --rm -p 8000:80 nut-cgi:test
```

### CI/CD

GitHub Actions workflows:

- **Lint:** Dockerfile (hadolint), YAML, shell scripts
- **Build:** Multi-arch builds with QEMU, publish to GHCR
- **Security:** Trivy vulnerability scanning (weekly + post-build)

### Dependency Management

Renovate bot automatically creates PRs for:

- Alpine base image updates (auto-merge patch versions)
- Alpine package updates (auto-merge revision bumps)
- GitHub Actions updates (auto-merge minor/patch)

## Troubleshooting

### Container unhealthy

Check logs for health check failures:

```bash
docker logs nut-cgi
```

Common issues:
- `lighttpd not responding` - Web server crashed or config error
- `nut-cgi not executing` - CGI permissions or missing binary
- `nut-cgi returned error content` - Invalid hosts.conf configuration

### Permission errors

If running into permission errors with volume mounts:

```bash
# Check container's UID/GID
docker exec nut-cgi id

# Run with matching UID/GID
docker run --user $(id -u):$(id -g) ...
```

### Hosts.conf not loading

Ensure file is mounted correctly and readable:

```bash
# Verify mount
docker exec nut-cgi ls -la /etc/nut/hosts.conf

# Check file contents
docker exec nut-cgi cat /etc/nut/hosts.conf
```

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

All PRs must pass linting and build workflows.

## License

[MIT License](LICENSE) - See LICENSE file for details.

## Acknowledgments

- Original project: [danielb7390/nut-cgi](https://github.com/danielb7390/nut-cgi)
- [Network UPS Tools (NUT)](https://networkupstools.org/)
- [Alpine Linux](https://alpinelinux.org/)

## Links

- **GitHub:** https://github.com/owine/nut-cgi
- **Container Registry:** https://github.com/owine/nut-cgi/pkgs/container/nut-cgi
- **Issues:** https://github.com/owine/nut-cgi/issues
- **NUT Documentation:** https://networkupstools.org/docs/
```

**Step 2: Commit updated README

**Commands:**
```bash
cd ~/Git/nut-cgi
git add README.md
git commit -m "docs: comprehensive README rewrite for Alpine migration

- Updated for Alpine 3.23 base and new features
- Added multi-architecture support documentation
- Security hardening examples and best practices
- Version pinning guidance
- Troubleshooting section
- Development and CI/CD information"
```

**Expected:** README updated and committed.

---

## Task 10: Local Testing and Verification

### Step 1: Test local Docker build

**Commands:**
```bash
cd ~/Git/nut-cgi
docker build -t nut-cgi:test .
```

**Expected Output:**
- Build completes successfully
- No errors during package installation
- Health check script copied correctly
- Final image size significantly smaller than Debian version

**Verify:**
```bash
# Check image size
docker images nut-cgi:test

# Expected: ~50-60MB (vs ~200MB Debian)
```

### Step 2: Test container startup

**Commands:**
```bash
# Create minimal hosts.conf for testing
echo 'MONITOR testups@localhost "Test UPS"' > /tmp/hosts.conf

# Run container
docker run -d \
  --name nut-cgi-test \
  -p 8080:80 \
  -v /tmp/hosts.conf:/etc/nut/hosts.conf:ro \
  nut-cgi:test

# Wait for container to be healthy
sleep 20
docker ps --filter name=nut-cgi-test
```

**Expected:** Container status shows "(healthy)"

### Step 3: Test health check manually

**Commands:**
```bash
# Execute health check script
docker exec nut-cgi-test /healthcheck.sh

# Expected output: "OK: nut-cgi healthy"
echo $?
# Expected: 0 (success)
```

### Step 4: Test web interface

**Commands:**
```bash
# Test HTTP endpoint
curl -f http://localhost:8080/upsstats.cgi

# Expected: HTML content with UPS stats page
```

### Step 5: Test UID override

**Commands:**
```bash
# Stop test container
docker stop nut-cgi-test
docker rm nut-cgi-test

# Run with different UID
docker run -d \
  --name nut-cgi-test-uid \
  --user 1001:1001 \
  -p 8080:80 \
  -v /tmp/hosts.conf:/etc/nut/hosts.conf:ro \
  nut-cgi:test

# Wait and check health
sleep 20
docker ps --filter name=nut-cgi-test-uid
```

**Expected:** Container starts and becomes healthy with custom UID

### Step 6: Cleanup test containers

**Commands:**
```bash
docker stop nut-cgi-test-uid 2>/dev/null || true
docker rm nut-cgi-test-uid 2>/dev/null || true
docker rmi nut-cgi:test
rm /tmp/hosts.conf
```

### Step 7: Commit testing documentation

**Files:**
- Create: `~/Git/nut-cgi/docs/testing.md`

**Code:**
```markdown
# Testing Guide

## Local Testing

### Build and Test

```bash
# Build image
docker build -t nut-cgi:test .

# Create test hosts.conf
echo 'MONITOR testups@localhost "Test UPS"' > hosts.conf

# Run container
docker run -d --name nut-cgi-test -p 8080:80 \
  -v $(pwd)/hosts.conf:/etc/nut/hosts.conf:ro nut-cgi:test

# Wait for healthy status
docker ps --filter name=nut-cgi-test

# Test endpoint
curl -f http://localhost:8080/upsstats.cgi

# Cleanup
docker stop nut-cgi-test
docker rm nut-cgi-test
```

### Test UID Override

```bash
docker run -d --name nut-cgi-uid-test --user 1001:1001 \
  -p 8080:80 -v $(pwd)/hosts.conf:/etc/nut/hosts.conf:ro nut-cgi:test
```

## Multi-Arch Testing

```bash
# Build for specific platform
docker buildx build --platform linux/arm64 -t nut-cgi:arm64-test --load .

# Test ARM64 build
docker run --platform linux/arm64 -d --name arm64-test \
  -p 8080:80 -v $(pwd)/hosts.conf:/etc/nut/hosts.conf:ro nut-cgi:arm64-test
```

## Health Check Testing

```bash
# Manual health check
docker exec nut-cgi-test /healthcheck.sh

# Monitor health status
watch -n 5 'docker inspect nut-cgi-test | grep -A 10 Health'
```

## Workflow Testing

### Lint Workflow

```bash
# Run hadolint locally
docker run --rm -i hadolint/hadolint < Dockerfile

# Run shellcheck locally
shellcheck healthcheck.sh

# Run yamllint locally
yamllint .github/workflows/
```

### Build Workflow

Test multi-arch builds locally:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t nut-cgi:multi-arch \
  .
```
```

**Commands:**
```bash
cd ~/Git/nut-cgi
git add docs/testing.md
git commit -m "docs: add testing guide for local and CI/CD validation"
```

**Expected:** Testing documentation committed.

---

## Task 11: Push and Trigger CI/CD

### Step 1: Push all commits to GitHub

**Commands:**
```bash
cd ~/Git/nut-cgi
git push origin main
```

**Expected:** All commits pushed to remote main branch.

### Step 2: Monitor GitHub Actions workflows

**Commands:**
```bash
# Watch workflow runs
gh run watch

# Or view in browser
gh run list --limit 5
```

**Expected:** All three workflows (lint, build, security) should trigger and pass.

### Step 3: Verify workflow results

**Action:** Check GitHub Actions tab in repository:

1. **Lint workflow:** ✓ hadolint, shellcheck, yamllint all pass
2. **Build workflow:** ✓ Multi-arch build completes, image published to GHCR
3. **Security workflow:** ✓ Trivy scan completes (after build finishes)

### Step 4: Verify GHCR image publication

**Commands:**
```bash
# Check published packages
gh api user/packages

# Or view in browser at:
# https://github.com/owine/nut-cgi/pkgs/container/nut-cgi
```

**Expected:** Image published with `latest`, `main`, and `sha-<commit>` tags.

---

## Task 12: Create v1.0.0 Release

### Step 1: Create and push v1.0.0 tag

**Commands:**
```bash
cd ~/Git/nut-cgi
git tag -a v1.0.0 -m "Release v1.0.0 - Alpine 3.23 migration

Initial release with:
- Alpine Linux 3.23 base
- Multi-architecture support (amd64/arm64)
- Security hardening with non-root user
- Enhanced health checks
- Automated dependency management with Renovate
- CI/CD with GitHub Actions"

git push origin v1.0.0
```

**Expected:** Tag pushed, triggers build workflow with semantic version tags.

### Step 2: Monitor release build

**Commands:**
```bash
# Watch the tag build
gh run watch
```

**Expected:** Build workflow creates multiple image tags:
- `v1.0.0`
- `v1.0`
- `v1`
- `latest`

### Step 3: Create GitHub Release

**Commands:**
```bash
gh release create v1.0.0 \
  --title "v1.0.0 - Alpine 3.23 Migration" \
  --notes "## 🎉 Initial Release

**Major Changes:**
- Migrated from Debian to Alpine Linux 3.23 for minimal image size
- Multi-architecture support: amd64 and arm64
- Security hardening: non-root user, pinned dependencies
- Enhanced three-tier health checks
- Automated dependency management with Renovate
- Complete CI/CD pipeline with GitHub Actions

**Image Details:**
- Base: Alpine Linux 3.23
- Size: ~50-60MB (vs ~200MB Debian)
- Architectures: linux/amd64, linux/arm64
- Registry: \`ghcr.io/owine/nut-cgi:v1.0.0\`

**Usage:**
\`\`\`bash
docker run -d -p 8000:80 \\
  -v ./hosts.conf:/etc/nut/hosts.conf:ro \\
  ghcr.io/owine/nut-cgi:v1.0.0
\`\`\`

See README for complete documentation.

**Breaking Changes:**
- New image location (migrated from \`danielb7390/nut-cgi\`)
- Requires hosts.conf file (same format as upstream)

**Full Changelog:** https://github.com/owine/nut-cgi/commits/v1.0.0"
```

**Expected:** Release created on GitHub with changelog and usage instructions.

### Step 4: Verify release images

**Commands:**
```bash
# Pull and test release image
docker pull ghcr.io/owine/nut-cgi:v1.0.0

# Verify multi-arch manifest
docker manifest inspect ghcr.io/owine/nut-cgi:v1.0.0
```

**Expected:**
- Image pulls successfully
- Manifest shows both amd64 and arm64 variants

---

## Task 13: Enable Renovate Bot

### Step 1: Install Renovate GitHub App

**Action:**
1. Visit https://github.com/apps/renovate
2. Click "Configure"
3. Select "owine" account
4. Choose "Only select repositories"
5. Select "nut-cgi"
6. Click "Install"

**Expected:** Renovate bot gains access to nut-cgi repository.

### Step 2: Verify Renovate onboarding

**Action:** Wait 5-10 minutes after installation.

**Expected:** Renovate creates onboarding PR with detected dependencies.

### Step 3: Merge onboarding PR

**Commands:**
```bash
# View Renovate onboarding PR
gh pr list

# Review and merge
gh pr view <PR_NUMBER>
gh pr merge <PR_NUMBER> --squash
```

**Expected:** Onboarding PR merged, Renovate begins tracking dependencies.

### Step 4: Verify Renovate configuration

**Expected:** Within 24 hours, Renovate should:
- Detect Alpine base image version
- Detect pinned package versions in Dockerfile
- Detect GitHub Actions versions
- Create any necessary update PRs

---

## Completion Checklist

**Repository Structure:**
- [x] .dockerignore created
- [x] healthcheck.sh created and executable
- [x] Dockerfile rewritten for Alpine 3.23
- [x] GitHub Actions workflows created (lint, build, security)
- [x] Renovate configuration created
- [x] docker-compose.yml example added
- [x] LICENSE file added
- [x] README.md updated
- [x] Testing documentation created

**Testing:**
- [x] Local build successful
- [x] Container starts and becomes healthy
- [x] Health check script works
- [x] Web interface accessible
- [x] UID override works

**CI/CD:**
- [x] All commits pushed to main
- [x] Lint workflow passing
- [x] Build workflow passing, image published
- [x] Security workflow running
- [x] v1.0.0 release tagged and published
- [x] Release notes created

**Automation:**
- [x] Renovate bot installed
- [x] Renovate onboarding completed
- [x] Dependency tracking active

**Success Metrics:**
- [ ] Image size < 70MB (target: ~50-60MB)
- [ ] Multi-arch images available for amd64 and arm64
- [ ] Health checks consistently green
- [ ] Zero HIGH/CRITICAL vulnerabilities in Trivy scan
- [ ] Renovate creates first dependency update PR

---

## Next Steps

After completing this plan:

1. **Test in production environment** - Deploy to actual hardware and validate UPS monitoring
2. **Update compose stacks** - Migrate docker-piwine, docker-zendc stacks to new image
3. **Monitor Renovate** - Review first week of automated PRs, adjust config if needed
4. **Document migration** - Update CLAUDE.md with new image location

For compose stack migration, see design document section 7 (Phase 2-3).
