# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker image project for the Network UPS Tools (NUT) CGI web interface, built on Alpine Linux 3.23 with security hardening and multi-architecture support. The project provides a lightweight (~50MB) containerized web interface for monitoring UPS (Uninterruptible Power Supply) systems across a network.

**Key Technologies:**
- Alpine Linux 3.23 (base image)
- lighttpd (web server)
- nut-cgi (Network UPS Tools CGI programs)
- Docker multi-stage builds
- GitHub Actions (CI/CD)
- Renovate (automated dependency management)

## Build and Development Commands

### Local Docker Build

```bash
# Build single-architecture image for local testing
docker build -t nut-cgi:test .

# Build multi-architecture image (requires buildx)
docker buildx build --platform linux/amd64,linux/arm64 -t nut-cgi:multi-arch .

# Build and load for specific architecture
docker buildx build --platform linux/arm64 -t nut-cgi:arm64-test --load .
```

### Testing

```bash
# Create test configuration
echo 'MONITOR testups@localhost "Test UPS"' > hosts.conf

# Run container locally
docker run -d --name nut-cgi-test -p 8080:80 \
  -v $(pwd)/hosts.conf:/etc/nut/hosts.conf:ro nut-cgi:test

# Check health status
docker ps --filter name=nut-cgi-test

# Execute health check manually
docker exec nut-cgi-test /healthcheck.sh

# Test web interface
curl -f http://localhost:8080/upsstats.cgi

# View logs
docker logs nut-cgi-test

# Cleanup
docker stop nut-cgi-test && docker rm nut-cgi-test
```

### Linting (Pre-commit Checks)

```bash
# Dockerfile linting
docker run --rm -i hadolint/hadolint < Dockerfile

# Shell script linting (requires shellcheck installed)
shellcheck healthcheck.sh

# YAML linting (requires yamllint installed via pip)
yamllint .github/workflows/
```

## Architecture

### Multi-Stage Dockerfile Design

The Dockerfile uses a two-stage build approach:

1. **Builder Stage**: Minimal Alpine 3.23 base for future build-time operations (currently minimal)
2. **Runtime Stage**: Final minimal image with only required packages

**Key Architectural Decisions:**

- **Version Pinning**: Alpine base image is digest-pinned; APK package versions are locked by the base image
  - APK packages are NOT individually version-pinned (versions are determined by the Alpine release)
  - Renovate manages the base image version and digest updates

- **Non-Root User**: Runs as UID 1000 (user `nut`) by default
  - Supports `--user` override for custom UID/GID requirements
  - World-readable configs (mode 0644) enable UID flexibility
  - Writable locations use `/tmp` which is world-writable

- **Security Hardening**:
  - No new privileges allowed
  - All capabilities dropped in production deployments
  - Read-only root filesystem (with tmpfs for `/tmp`)
  - Minimal package footprint (no build tools in runtime)

### Health Check System

Three-tier validation approach in `healthcheck.sh`:

1. **Tier 1**: Web server responding (HTTP 200)
2. **Tier 2**: CGI execution working (non-empty response)
3. **Tier 3**: Valid CGI output (no error content)

Configuration: 30s interval, 10s timeout, 15s start period, 3 retries

### CI/CD Pipeline

Four GitHub Actions workflows provide comprehensive automation:

1. **`lint.yml`**: Pre-build validation
   - Dockerfile linting (hadolint)
   - Shell script linting (shellcheck)
   - YAML validation (yamllint)
   - Triggers: Push to main, pull requests

2. **`build.yml`**: Multi-architecture builds
   - Platforms: linux/amd64, linux/arm64
   - Publishes to GitHub Container Registry (GHCR)
   - Layer caching for faster builds
   - SBOM and provenance attestations
   - Multiple tag variants (semantic versioning)
   - Triggers: Push to main, tag push (v*.*.*), PRs (build only)

3. **`security.yml`**: Vulnerability scanning
   - Trivy scanner for HIGH/CRITICAL vulnerabilities
   - Runs after successful builds + weekly schedule
   - Uploads results to GitHub Security tab
   - Fails on critical vulnerabilities

4. **`release.yml`**: Automated weekly releases
   - Claude Code analyzes unreleased commits and determines semver bump
   - Updates CHANGELOG.md, commits, tags, and creates GitHub Release
   - Tag push triggers `build.yml` automatically via GitHub App token
   - Schedule: Tuesday 4am CST (10:00 UTC), or manual `workflow_dispatch`
   - Supports dry-run mode for testing without creating a release
   - Requires three repository secrets (see workflow file for details)

### Dependency Management

Renovate bot automatically manages updates with this strategy:

- **Alpine base image**: Auto-merge patch/digest updates (APK versions follow the base image)
- **GitHub Actions**: Auto-merge minor/patch updates
- **Non-major dependencies**: Catch-all group for remaining deps, auto-merge minor/patch
- **NUT source**: Manual review required
- **Schedule**: Weekly on Mondays (ahead of Tuesday automated release)
- **Security overrides**: Immediate processing regardless of schedule

All auto-merges require passing CI/CD checks.

### Automated Releases

The `release.yml` workflow runs every Tuesday at 4am CST and uses Claude Code to:

1. Gather all commits since the last git tag
2. Analyze them against the project's semver policy
3. Determine the appropriate version bump (patch/minor/major)
4. Generate CHANGELOG.md entries and release notes
5. Commit, tag, and push (triggering `build.yml` automatically)
6. Create a GitHub Release

The workflow requires three repository secrets for Claude Code API access and a GitHub App token. The GitHub App is needed because `GITHUB_TOKEN` events do not trigger other workflows. See the workflow file for secret names and configuration details.

**Testing**: Use `workflow_dispatch` with `dry-run: true` to validate the analysis without creating a release.

## Image Tagging Strategy

Published to `ghcr.io/owine/nut-cgi` with multiple tag variants:

- `v1.0.0` - Exact semantic version (production pinning)
- `v1.0` - Latest patch in v1.0.x series
- `v1` - Latest minor in v1.x series
- `latest` - Latest build from main branch
- `sha-<commit>` - Commit-specific builds
- `main` - Main branch builds

**Production best practice**: Pin to exact versions (e.g., `v1.0.0`)

## File Structure

```
nut-cgi/
├── .github/
│   ├── workflows/
│   │   ├── build.yml       # Multi-arch build & GHCR publishing
│   │   ├── lint.yml        # Pre-build validation
│   │   ├── release.yml     # Automated weekly releases (Claude Code)
│   │   └── security.yml    # Trivy vulnerability scanning
│   └── renovate.json       # Dependency automation config
├── docs/
│   └── plans/              # Design documents and migration plans
├── Dockerfile              # Multi-stage Alpine 3.23 build
├── docker-compose.yml      # Example deployment (security hardened)
├── healthcheck.sh          # Three-tier health validation script
├── .dockerignore           # Build context optimization
├── LICENSE                 # MIT license
└── README.md               # User-facing documentation
```

## Important Implementation Details

### UID/GID Flexibility

The image supports runtime UID override while maintaining security:

- Default user: `nut` (UID 1000, GID 1000)
- Override example: `docker run --user 1001:1001 ...`
- Configs at `/etc/nut/*` are mode 0644 (world-readable)
- lighttpd PID file in `/tmp/lighttpd.pid` (world-writable location)
- Health check script executable by any UID

**Rationale**: UPS host configurations are non-sensitive network data, so relaxed config permissions are acceptable for deployment flexibility.

### Lighttpd Configuration

The Dockerfile configures lighttpd via sed commands:

- Document root: `/usr/lib/cgi-bin/nut`
- Default index: `upsstats.cgi`
- CGI enabled for `.cgi` files
- PID file: `/tmp/lighttpd.pid` (any UID can write)
- Logging: stdout/stderr (Docker best practice)

### Version Pinning Philosophy

The Alpine base image is digest-pinned (e.g., `alpine:3.23.3@sha256:...`) for exact reproducibility. APK packages are **not** individually version-pinned because their versions are determined by the Alpine release — pinning them would break when the base image updates. Renovate manages the base image version and digest.

## Configuration

### hosts.conf Format

The container requires a `hosts.conf` file mounted at `/etc/nut/hosts.conf`:

```conf
# Monitor local UPS
MONITOR myups@localhost "Living Room UPS"

# Monitor remote UPS systems
MONITOR serverups@192.168.1.100 "Server Rack UPS"
MONITOR officeups@192.168.1.101 "Office UPS"
```

**Deployment Example:**
```bash
docker run -d -p 8000:80 \
  -v /path/to/hosts.conf:/etc/nut/hosts.conf:ro \
  ghcr.io/owine/nut-cgi:v1.0.0
```

### Production Security Hardening

Recommended docker-compose.yml security options:

```yaml
services:
  nut-cgi:
    image: ghcr.io/owine/nut-cgi:v1.0.0  # Version pinned
    user: "1000:1000"                     # Explicit UID
    read_only: true                       # Read-only root filesystem
    tmpfs:
      - /tmp:mode=1777                   # Writable temp space
    security_opt:
      - no-new-privileges:true           # Prevent privilege escalation
    cap_drop:
      - ALL                              # Drop all capabilities
    volumes:
      - ./hosts.conf:/etc/nut/hosts.conf:ro
    ports:
      - "8000:80"
    restart: unless-stopped
```

## Migration Context

This project is forked from `danielb7390/nut-cgi` with these improvements:

- **Base image**: Debian → Alpine 3.23 (~200MB → ~50MB)
- **Multi-architecture**: Added ARM64 support
- **Security**: Non-root user, vulnerability scanning, hardened configs
- **Automation**: CI/CD pipeline with GitHub Actions
- **Dependency management**: Renovate bot for automatic updates
- **Enhanced health checks**: Three-tier validation vs. simple HTTP check

The migration maintains backward compatibility with `hosts.conf` format and UPS monitoring functionality.

## Semantic Versioning Policy

**Patch (v1.0.x):**
- Alpine package updates within same minor version
- Security fixes (CVE patches)
- Health check refinements
- Documentation updates

**Minor (v1.x.0):**
- Alpine minor version updates (3.23 → 3.24)
- New features (additional health check options)
- Non-breaking configuration enhancements
- Lighttpd configuration improvements

**Major (vx.0.0):**
- Breaking configuration changes
- Alpine major version updates (3.x → 4.x)
- Incompatible API/interface changes
- Changes requiring compose file modifications

## Troubleshooting Common Issues

### Container unhealthy

Check logs: `docker logs <container-name>`

Common causes:
- `lighttpd not responding`: Web server crashed or config error
- `nut-cgi not executing`: CGI permissions or missing binary
- `nut-cgi returned error content`: Invalid hosts.conf configuration

### Permission errors with volume mounts

```bash
# Check container's UID/GID
docker exec <container> id

# Run with matching UID/GID
docker run --user $(id -u):$(id -g) ...
```

### hosts.conf not loading

```bash
# Verify mount
docker exec <container> ls -la /etc/nut/hosts.conf

# Check file contents
docker exec <container> cat /etc/nut/hosts.conf
```

## Development Workflow

1. **Make changes**: Edit Dockerfile, healthcheck.sh, or workflows
2. **Lint locally**: Run hadolint, shellcheck, yamllint
3. **Test build**: `docker build -t nut-cgi:test .`
4. **Test functionality**: Run container with test hosts.conf
5. **Commit**: Use conventional commit format (e.g., `feat:`, `fix:`, `chore:`)
6. **Push**: Triggers CI/CD pipeline automatically
7. **Review**: Check GitHub Actions for workflow results

## Related Documentation

- **Design document**: `docs/plans/2026-01-05-nut-cgi-fork-design.md` - Complete architectural decisions and trade-offs
- **Migration plan**: `docs/plans/2026-01-05-alpine-migration.md` - Step-by-step implementation plan
- **NUT documentation**: https://networkupstools.org/docs/
- **Alpine packages**: https://pkgs.alpinelinux.org/packages
