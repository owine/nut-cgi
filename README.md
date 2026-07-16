# nut-cgi

Lightweight Docker image for [Network UPS Tools (NUT)](https://networkupstools.org/) CGI web interface,
built on Alpine Linux with security hardening and multi-architecture support.

## Features

- **Alpine Linux** - Minimal base image, well under 100 MB
- **Multi-architecture** - Native support for `linux/amd64` and `linux/arm64`
- **Security hardened** - Non-root user, pinned dependencies, vulnerability scanning
- **Flexible UID support** - Works with `--user` override for volume mount permissions
- **Enhanced health checks** - Tiered validation of web server and CGI functionality
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
docker compose up -d
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

### Enabling upsset.cgi

NUT ships `upsset.cgi`, an administrative interface that can change UPS settings and
issue commands such as shutdown. **The image blocks it with a 403 by default.**

To enable it, set `ENABLE_UPSSET=true`:

```yaml
environment:
  - ENABLE_UPSSET=true
```

Only do this behind a reverse proxy that enforces authentication. `upsset.cgi` has no
authentication of its own, so anything that can reach it can power off your hardware.

### Content Security Policy

The container sends a strict `Content-Security-Policy` by default:

```
default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'
```

This suits the stock interface, which loads no external resources.

The policy is not decorative. `upsstats.cgi` renders UPS variables (`ups.model`,
`device.mfr`, `ups.status`, …) into the page **without HTML-escaping them**, and this
image talks to upsd over plaintext NUT protocol. A hostile UPS, a spoofed upsd, or a
MITM on port 3493 can therefore inject markup into the status page. Because the
default policy allows no inline or external scripts, it blocks that injection from
executing. Keep `script-src` as restrictive as your deployment permits.

Override the policy with the `CSP_POLICY` environment variable when something
downstream of the container injects content into the page:

```yaml
environment:
  - CSP_POLICY: "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' https://static.cloudflareinsights.com; connect-src 'self' https://cloudflareinsights.com"
```

`CSP_POLICY` replaces the whole header rather than adding to it, so restate the
directives you want to keep. Two things catch people out:

- **Naming a directive overrides `default-src` for that type.** Adding
  `script-src https://example.com` without `'self'` blocks the page's own scripts.
  Repeat `'self'` in every directive you introduce.
- **A CDN often loads from one host and reports to another.** The Cloudflare beacon
  above is fetched from `static.cloudflareinsights.com` but posts results to
  `cloudflareinsights.com` — the apex, no `static.`. It needs both `script-src` and
  `connect-src`; allowing only the script leaves the beacon loading but unable to report.

Set `CSP_POLICY=none` to send no CSP header at all. This is appropriate only when a
reverse proxy sets an equivalent policy in its place — given the unescaped rendering
above, a deployment with no CSP from either layer is genuinely exposed. Prefer `none`
over configuring both layers: two CSP headers are intersected by the browser rather
than one overriding the other, which is rarely what you want.

The container refuses to start if `CSP_POLICY` contains a double quote or newline,
since the value is interpolated into the lighttpd config.

#### Reverse proxies that inject content

The policy is sent by lighttpd, which cannot know about markup added after a
response leaves the container. Cloudflare Web Analytics, for example, injects its
beacon `<script>` at the edge — downstream of the origin, the reverse proxy, and the
tunnel — so `default-src 'self'` blocks it and the browser reports a CSP violation
for a script the container never served. `CSP_POLICY` exists for exactly this case.

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
# Pin to an exact version (recommended) -- replace with the current release
docker pull ghcr.io/owine/nut-cgi:vX.Y.Z

# Pin to a minor series (receives patch updates)
docker pull ghcr.io/owine/nut-cgi:vX.Y

# Pin to a major series (receives minor/patch updates)
docker pull ghcr.io/owine/nut-cgi:vX
```

Find the current release on the
[Releases page](https://github.com/owine/nut-cgi/releases) or under
[Packages](https://github.com/owine/nut-cgi/pkgs/container/nut-cgi).

**Available tags:**
- `:vX.Y.Z` - Specific semantic version (exact pinning; **recommended for production**)
- `:vX.Y` - Latest patch in that minor series
- `:vX` - Latest minor in that major series
- `:latest` - Latest released version
- `:main` - Latest build from the main branch
- `:sha-<commit>` - Specific commit build (for debugging)

Tags are published only after a build passes its Trivy scan and functional tests.
Releases before v1.2.0 were published without the `v` prefix (e.g. `1.1.2`).

## Architecture

### Multi-Stage Build

- **Stage 1 (builder):** Compiles NUT from the upstream release tarball (SHA256-verified),
  building only the CGI programs, then strips debug symbols and the W3C validator badges
  from NUT's HTML templates
- **Stage 2 (runtime):** Alpine with lighttpd, curl, gd, and openssl, plus the compiled
  NUT CGI programs and libraries copied from the builder

### Package Versions

Direct APK packages are explicitly version-pinned for reproducibility; the pinned versions
live in the `Dockerfile` and are kept current by Renovate. Transitive packages are resolved
by apk, which installs the repository's current build.

Runtime stage:

- `lighttpd` - Lightweight web server
- `curl` - Health check utility
- `gd` - Graphics library used by NUT's CGI programs
- `openssl` - Pinned explicitly because the base image can lag its own repository

Builder stage:

- `build-base`, `gd-dev`, `curl` - Toolchain and headers for compiling NUT

`nut-cgi` itself is not an APK package here — it is compiled from source, pinned via
`ARG NUT_VERSION` in the Dockerfile.

Package versions are automatically updated by Renovate bot with semantic versioning.

### Health Check

Validation runs in tiers:

1. **Tier 1:** Web server responding (HTTP success status)
2. **Tier 2:** CGI execution working (non-empty response)
3. **Tier 3:** Valid CGI infrastructure (no template or server errors)
4. **Tier 4:** Valid HTTP response headers (`Content-Type` present)
5. **Tier 5:** UPS connectivity — only when `HEALTHCHECK_MODE=strict`

Tiers 1-4 validate the container itself and always run. Tier 5 is opt-in because an
unreachable UPS is usually a network or UPS problem rather than a container problem,
and failing the health check would restart a perfectly healthy web server.

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

- **Lint** (`lint.yml`): Dockerfile (hadolint), shell scripts (shellcheck), YAML
  (yamllint), and GitHub Actions (actionlint)
- **Build** (`build.yml`): Multi-arch builds, publish to GHCR, then Trivy scanning
  and functional tests before promoting tags
- **Release** (`release.yml`): Automated releases via release-please

Trivy runs as the `Security Scan` job inside `build.yml` after a successful build on
`main` or a version tag. It does not run on pull requests, and there is no scheduled
scan.

### Dependency Management

Renovate bot automatically creates PRs for:

- Alpine base image updates (auto-merge patch versions; minor versions need review,
  since they require updating the APK pins and Renovate's `depNameTemplate` together)
- Alpine package updates, tracked via Repology — all APK bumps share a single PR so
  they stay mutually buildable, and auto-merge once CI passes
- GitHub Actions updates (auto-merge minor/patch)
- NUT source version updates (manual review required)

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

## Links

- **GitHub:** https://github.com/owine/nut-cgi
- **Container Registry:** https://github.com/owine/nut-cgi/pkgs/container/nut-cgi
- **Issue Tracker:** https://github.com/owine/nut-cgi/issues
- **Security Advisories:** https://github.com/owine/nut-cgi/security/advisories
