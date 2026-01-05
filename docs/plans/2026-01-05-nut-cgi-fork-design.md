# nut-cgi Docker Image Fork - Design Document

**Date**: 2026-01-05
**Status**: Validated
**Owner**: owine

## Overview

Transition from upstream `danielb7390/nut-cgi` to self-maintained fork with Alpine base, enhanced security, automated dependency management, and multi-architecture support.

## Context

**Current State:**
- Using `danielb7390/nut-cgi` based on `debian:latest`
- Monitoring multiple UPS systems across network
- Running in mixed ARM64/AMD64 environment
- No automated updates or security scanning

**Requirements:**
- Alpine 3.23 base image for smaller footprint
- Multi-architecture builds (linux/amd64, linux/arm64)
- Automated dependency management with Renovate
- Security hardening and vulnerability scanning
- Support for `--user` UID override at runtime
- Enhanced health checks validating actual nut-cgi functionality
- Version-pinned deployments in production

## Architecture Decisions

### 1. Repository Structure

```
nut-cgi/
├── .github/
│   ├── workflows/
│   │   ├── build.yml          # Multi-arch build & publish to GHCR
│   │   ├── security.yml       # Trivy vulnerability scanning
│   │   └── lint.yml           # Hadolint, YAML, shellcheck validation
│   └── renovate.json          # Dependency automation config
├── Dockerfile                 # Multi-stage Alpine 3.23 build
├── docker-compose.yml         # Local testing example
├── healthcheck.sh            # Enhanced nut-cgi health validation
├── .dockerignore             # Build optimization
├── LICENSE                   # Project license
└── README.md                 # Updated documentation
```

**Rationale:**
- Modular workflow separation for maintainability
- Security scanning decoupled from builds for scheduled scans
- Example compose file serves as living documentation

### 2. Multi-Stage Dockerfile Design

**Stage 1: Builder (temporary)**
- Alpine 3.23 base
- Install build dependencies
- Verify package integrity
- Prepare configuration templates

**Stage 2: Runtime (final)**
```dockerfile
FROM alpine:3.23

# Pinned package versions for reproducibility
RUN apk add --no-cache \
    nut-cgi=2.8.0-r5 \
    lighttpd=1.4.73-r0 \
    curl=8.5.0-r0

# Create default user but support --user override
RUN addgroup -g 1000 nut && \
    adduser -D -u 1000 -G nut nut

# World-readable configs for --user compatibility
COPY --chmod=0644 config/* /etc/nut/
COPY --chmod=0755 healthcheck.sh /healthcheck.sh

# Configure lighttpd for non-root + arbitrary UID:
# - PID file: /tmp/lighttpd.pid (world-writable location)
# - Logs: stdout/stderr (Docker best practice)
# - CGI binaries: system permissions (0755)

USER nut
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD ["/healthcheck.sh"]
CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/lighttpd.conf"]
```

**Security Hardening:**
- Non-root user execution (default UID 1000)
- Minimal packages (no build tools in final image)
- Explicit file permissions
- No unnecessary utilities

**UID Flexibility:**
- World-readable configs (0644) for `--user` override support
- Writable locations use `/tmp` (world-writable)
- Health check works with any UID
- Default user `nut` but runtime override supported

**Permission Strategy:**
| Location | Permission | Reason |
|----------|-----------|---------|
| `/etc/nut/*` | 0644 | Config needs read access by any UID |
| `/usr/lib/cgi-bin/nut/*` | 0755 | CGI binaries executable by all |
| `/tmp` | 1777 | PIDs and logs for any UID |
| `healthcheck.sh` | 0755 | Executable by any user |

### 3. Enhanced Health Check

**Three-tier validation approach:**

```bash
#!/bin/sh
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
if echo "$response" | grep -q "error\|failed\|not found"; then
    echo "WARN: nut-cgi returned error content"
    exit 1
fi

echo "OK: nut-cgi healthy"
exit 0
```

**Health Check Configuration:**
- Interval: 30s (fast failure detection)
- Timeout: 10s (reasonable for CGI processing)
- Start period: 15s (grace period for initialization)
- Retries: 3 (avoid false positives)

**Validation Tiers:**
1. **Tier 1**: Catches lighttpd crashes or port issues
2. **Tier 2**: Detects CGI execution failures (permissions, missing binary)
3. **Tier 3**: Identifies configuration errors (hosts.conf issues)

### 4. GitHub Actions CI/CD Pipeline

#### **build.yml - Multi-Architecture Publishing**

**Triggers:**
- Push to `main` → publish with version tags
- Pull request → test build only (no publish)
- Tag push (`v*.*.*`) → versioned release
- Manual dispatch → force rebuild option

**Build Matrix:**
- `linux/amd64` - x86_64 servers
- `linux/arm64` - Raspberry Pi, ARM servers

**Build Process:**
1. Checkout repository
2. Set up Docker Buildx (multi-platform support)
3. Login to GitHub Container Registry (GHCR)
4. Extract metadata (tags, labels from git ref)
5. Build and push with:
   - Layer caching for speed
   - Provenance and SBOM attestations (supply chain security)
   - Multiple tag variants

**Image Tagging Strategy:**
```
ghcr.io/owine/nut-cgi:v1.0.0          # Exact semantic version
ghcr.io/owine/nut-cgi:v1.0            # Latest v1.0.x patch
ghcr.io/owine/nut-cgi:v1              # Latest v1.x minor
ghcr.io/owine/nut-cgi:latest          # Latest overall
ghcr.io/owine/nut-cgi:sha-abc123      # Commit-specific
```

#### **security.yml - Vulnerability Scanning**

**Triggers:**
- After successful build completion
- Scheduled: Weekly Monday 00:00 UTC
- Manual dispatch for ad-hoc scans

**Scanning Process:**
1. Pull published image from GHCR
2. Run Trivy scanner:
   - OS package vulnerabilities (HIGH/CRITICAL severity)
   - Exposed secrets detection
   - Configuration misconfigurations
3. Upload results to GitHub Security tab
4. Fail on CRITICAL vulnerabilities

#### **lint.yml - Pre-Build Validation**

**Triggers:**
- Pull requests
- Push to any branch

**Validations:**
1. **Hadolint** - Dockerfile best practices
2. **YAML linting** - Workflow syntax validation
3. **Shellcheck** - Health check script validation

**Common Workflow Features:**
- Minimal permissions (principle of least privilege)
- `secrets: inherit` (compatible with 1Password integration)
- Clear job names for debugging
- Fail fast on errors

### 5. Renovate Dependency Management

**Balanced update strategy** - Regular updates with manual review of breaking changes.

#### **Configuration Overview**

```json
{
  "extends": ["config:base"],
  "packageRules": [
    {
      "matchDatasources": ["docker"],
      "matchPackageNames": ["alpine"],
      "groupName": "alpine base image",
      "automerge": true,
      "automergeType": "pr",
      "matchUpdateTypes": ["patch", "digest"]
    },
    {
      "matchManagers": ["regex"],
      "matchStrings": ["nut-cgi=(?<currentValue>.*?)", "lighttpd=(?<currentValue>.*?)", "curl=(?<currentValue>.*?)"],
      "groupName": "alpine packages",
      "automerge": true,
      "matchUpdateTypes": ["patch"]
    },
    {
      "matchManagers": ["github-actions"],
      "groupName": "github actions",
      "schedule": ["before 3am on Monday"],
      "automerge": true,
      "automergeType": "pr",
      "matchUpdateTypes": ["patch", "minor"]
    }
  ],
  "schedule": ["before 3am on Monday"],
  "timezone": "America/New_York"
}
```

#### **Dependency Categories**

**1. Alpine Base Image (3.23.x)**
- Track minor releases within 3.23.x series
- Group with digest updates for atomic changes
- **Auto-merge**: Patch versions and digests (3.23.0 → 3.23.1)
- **Manual review**: Minor version bumps (3.23.x → 3.24.x)

**2. Alpine Packages (Pinned Versions)**
```dockerfile
RUN apk add --no-cache \
    nut-cgi=2.8.0-r5 \
    lighttpd=1.4.73-r0 \
    curl=8.5.0-r0
```
- Explicit version pinning for reproducibility
- Renovate tracks Alpine 3.23 package repository
- **Auto-merge**: Package revision bumps (-r5 → -r6)
- **Manual review**: Version changes (2.8.0 → 2.8.1)

**Benefits of pinning:**
- Exact build reproducibility
- Clear visibility into changes via PRs
- Rollback capability to known-good versions
- Efficient build caching

**3. GitHub Actions**
- Track action version updates (e.g., `docker/build-push-action@v5`)
- Group all Actions updates into weekly PR
- **Auto-merge**: Patch/minor with passing CI
- **Manual review**: Major version changes

#### **Update Cadence**

- **Schedule**: Weekly checks on Monday mornings (low traffic)
- **Grouping**: Reduce PR noise with grouped updates
- **Security overrides**: Immediate processing regardless of schedule
- **CI requirements**: Must pass all checks before auto-merge

#### **Safety Measures**

- Requires passing CI/CD before merge
- Separate PRs for major/breaking changes
- Conventional commit message format
- PR descriptions include changelog links

### 6. Semantic Versioning Strategy

**Version format**: `vMAJOR.MINOR.PATCH`

#### **Version Bump Triggers**

**Patch (v1.0.x):**
- Alpine package updates within same minor version
- Security fixes (CVE patches)
- Health check script refinements
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
- Requires compose file modifications

#### **Release Process**

1. Create git tag: `git tag v1.0.0`
2. Push tag: `git push origin v1.0.0`
3. GitHub Actions automatically:
   - Builds multi-arch images
   - Creates multiple tag variants
   - Publishes to GHCR
   - Generates release notes

### 7. Compose Stack Migration Strategy

#### **Phase 1: Fork & Build Infrastructure**

**Tasks:**
1. Fork `danielb7390/nut-cgi` to `owine/nut-cgi`
2. Implement new Dockerfile with Alpine 3.23
3. Create all GitHub Actions workflows
4. Configure GHCR publishing and permissions
5. Set up Renovate configuration
6. Tag and publish `v1.0.0` release

**Success criteria:**
- Multi-arch build completes successfully
- Images published to `ghcr.io/owine/nut-cgi`
- Health checks passing
- Renovate creating first PRs

#### **Phase 2: Parallel Testing**

**Tasks:**
1. Deploy forked image in test compose stack
2. Validate health checks in production environment
3. Test `--user` override with volume mounts
4. Verify multi-UPS monitoring functionality
5. Confirm Renovate PR workflow

**Test Compose Configuration:**
```yaml
services:
  nut-cgi-test:
    image: ghcr.io/owine/nut-cgi:v1.0.0
    user: "1000:1000"
    read_only: true
    tmpfs:
      - /tmp:mode=1777
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    volumes:
      - ./hosts.conf:/etc/nut/hosts.conf:ro
    ports:
      - "8001:80"
```

**Validation checklist:**
- [ ] Health checks report healthy status
- [ ] upsstats.cgi accessible and rendering
- [ ] All configured UPS systems visible
- [ ] Volume mounts working correctly
- [ ] No permission errors in logs
- [ ] UID override works as expected

#### **Phase 3: Production Migration**

**Compose File Changes:**

```yaml
# BEFORE
services:
  nut-cgi:
    image: danielb7390/nut-cgi:latest
    volumes:
      - ./hosts.conf:/etc/nut/hosts.conf
    ports:
      - "8000:80"
    restart: unless-stopped

# AFTER
services:
  nut-cgi:
    image: ghcr.io/owine/nut-cgi:v1.0.0  # Version pinned
    user: "1000:1000"                      # Explicit UID
    read_only: true                        # Security hardening
    tmpfs:
      - /tmp:mode=1777                    # Writable temp space
    security_opt:
      - no-new-privileges:true            # Prevent escalation
    cap_drop:
      - ALL                               # Minimal capabilities
    volumes:
      - ./hosts.conf:/etc/nut/hosts.conf:ro
    ports:
      - "8000:80"
    restart: unless-stopped
```

**Deployment Process:**
1. Update compose file with new image reference
2. Document previous image tag in comments for rollback
3. Deploy: `docker-compose pull && docker-compose up -d`
4. Monitor health status and logs for 24 hours
5. Keep upstream image as fallback for 1 week

**Rollback Plan:**
```yaml
# Keep commented for quick rollback
# image: danielb7390/nut-cgi:latest
image: ghcr.io/owine/nut-cgi:v1.0.0
```

Quick rollback command:
```bash
# Edit compose file to use commented fallback
docker-compose pull && docker-compose up -d
```

#### **Post-Migration**

**Renovate Integration:**
1. Renovate monitors `ghcr.io/owine/nut-cgi` for new versions
2. Creates PR updating compose file: `v1.0.0` → `v1.0.1`
3. Review PR with changelog and security scan results
4. Merge and deploy with confidence

**Ongoing Maintenance:**
- Weekly automated dependency PRs
- Security scans report vulnerabilities
- Version-pinned updates under your control
- Clear audit trail of all changes

## Security Considerations

### Container Security

**Runtime Hardening:**
- Non-root user execution (UID 1000)
- Read-only root filesystem
- No new privileges allowed
- All capabilities dropped
- Minimal package footprint

**Build Security:**
- Multi-stage build (no build tools in runtime)
- Version-pinned dependencies
- Trivy vulnerability scanning (HIGH/CRITICAL)
- Supply chain attestations (SBOM, provenance)

**Secrets Management:**
- No secrets in image (UPS configs are non-sensitive)
- GHCR credentials via GitHub Actions OIDC
- 1Password integration for deployment secrets

### Update Security

**Automated Security Updates:**
- Renovate processes security advisories immediately
- Auto-merge for patch-level security fixes
- Weekly vulnerability scans of published images
- GitHub Security tab integration for tracking

**Manual Review Required:**
- Major/minor version changes
- CRITICAL vulnerabilities requiring config changes
- Breaking changes affecting deployments

## Trade-offs and Constraints

### Design Trade-offs

**World-readable configs:**
- **Decision**: Config files mode 0644 (world-readable)
- **Rationale**: Enable `--user` UID override flexibility
- **Trade-off**: Slightly relaxed permissions vs. strict user-only
- **Acceptable because**: UPS configs are non-sensitive network data

**Version pinning:**
- **Decision**: Pin all Alpine package versions explicitly
- **Rationale**: Reproducibility and change control
- **Trade-off**: Slight maintenance overhead vs. automatic updates
- **Mitigated by**: Renovate automation

**Multi-stage build:**
- **Decision**: Builder + runtime stages
- **Rationale**: Minimal runtime image size
- **Trade-off**: Slightly longer build time vs. smaller image
- **Benefit**: Faster pulls, smaller attack surface

### Known Limitations

**Alpine package availability:**
- Limited to packages in Alpine 3.23 repositories
- Older versions may be pruned from repos (6+ months)
- **Mitigation**: Renovate keeps packages current

**Multi-arch build time:**
- Building for 2 architectures increases CI time
- **Mitigation**: Layer caching reduces subsequent builds

**Health check limitations:**
- Can't validate actual UPS communication (requires hosts.conf)
- Only validates nut-cgi web interface functionality
- **Acceptable**: Catch most failure scenarios

## Success Metrics

### Immediate Success (Phase 1)

- [ ] Multi-arch images build successfully
- [ ] Images published to GHCR
- [ ] All workflows passing
- [ ] Renovate creating PRs

### Short-term Success (Phase 2-3)

- [ ] Production deployment successful
- [ ] Health checks consistently green
- [ ] No functional regressions from upstream image
- [ ] First automated Renovate PR merged

### Long-term Success (3+ months)

- [ ] Zero security vulnerabilities (HIGH/CRITICAL)
- [ ] 90%+ automated update merge rate
- [ ] No production incidents related to image
- [ ] Clear audit trail of all dependency changes

## Future Enhancements

**Not in scope for v1.0.0, potential future work:**

1. **Advanced health checks**: Test actual NUT server connectivity
2. **Metrics endpoint**: Prometheus exporter for UPS stats
3. **Configuration templates**: Environment variable substitution in hosts.conf
4. **Multi-config support**: Multiple hosts.conf files for different environments
5. **TLS/SSL support**: HTTPS endpoint with cert management
6. **Authentication**: Basic auth or OAuth for web interface

## References

- **Original project**: https://github.com/danielb7390/nut-cgi
- **Alpine Linux**: https://alpinelinux.org/
- **NUT documentation**: https://networkupstools.org/
- **Docker multi-platform builds**: https://docs.docker.com/build/building/multi-platform/
- **Renovate docs**: https://docs.renovatebot.com/

---

**Next Steps**: Ready to set up implementation plan and create git worktree for development.
