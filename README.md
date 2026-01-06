# nut-cgi

Lightweight Docker image for [Network UPS Tools (NUT)](https://networkupstools.org/) CGI web interface,
built on Alpine Linux with security hardening and multi-architecture support.

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

See [`hosts.conf.example`](hosts.conf.example) for comprehensive examples and configuration tips.

For complete `hosts.conf` syntax, see [NUT documentation](https://networkupstools.org/docs/man/hosts.conf.html).

### Health Check Modes

The container supports two health check modes via the `HEALTHCHECK_MODE` environment variable:

- **`basic`** (default): Validates infrastructure only (web server + CGI execution)
- **`strict`**: Validates infrastructure + UPS connectivity (fails if no UPS reachable)

```yaml
environment:
  - HEALTHCHECK_MODE=strict  # Require UPS connectivity for healthy status
```

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
- `:latest` - Latest tested release (recommended for production)
- `:v1.0.0` - Specific semantic version (exact version pinning)
- `:v1.0` - Latest patch in v1.0.x series
- `:v1` - Latest minor in v1.x series
- `:main` - Latest tested build from main branch (passes all tests)
- `:sha-<commit>` - Specific commit build (for debugging/pinning)

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

## Documentation

- **[CHANGELOG.md](CHANGELOG.md)** - Version history and release notes
- **[SECURITY.md](SECURITY.md)** - Security policy and vulnerability reporting
- **[CLAUDE.md](CLAUDE.md)** - Development guide and architectural decisions
- **[hosts.conf.example](hosts.conf.example)** - Configuration examples
- **[docs/BUILD_OPTIMIZATION.md](docs/BUILD_OPTIMIZATION.md)** - Multi-architecture build optimization guide

## Links

- **GitHub:** https://github.com/owine/nut-cgi
- **Container Registry:** https://github.com/owine/nut-cgi/pkgs/container/nut-cgi
- **Issue Tracker:** https://github.com/owine/nut-cgi/issues
- **Security Advisories:** https://github.com/owine/nut-cgi/security/advisories
