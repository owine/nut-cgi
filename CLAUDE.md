# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker image project for the Network UPS Tools (NUT) CGI web interface, built on Alpine Linux with security
hardening and multi-architecture support. It provides a small containerized web interface for monitoring UPS
(Uninterruptible Power Supply) systems across a network.

**Versions are not restated in this document.** The Alpine release, the NUT release, and every APK pin live in the
`Dockerfile`; the current release version is the latest published GitHub Release (`gh release view`). Read those
rather than trusting a number written here.

**Key Technologies:**
- Alpine Linux (base image; release pinned in `Dockerfile`)
- lighttpd (web server)
- nut-cgi (Network UPS Tools CGI programs, compiled from source; release pinned via `ARG NUT_VERSION`)
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

1. **Builder Stage**: Compiles NUT (`ARG NUT_VERSION`) from the upstream release tarball —
   downloads it, verifies its SHA256, runs `./configure --with-cgi`, builds only the CGI
   programs and their dependencies, strips debug symbols, and strips the W3C validator
   badges from NUT's HTML templates
2. **Runtime Stage**: Final minimal image with only required packages

**Key Architectural Decisions:**

- **Version Pinning**: Alpine base image is digest-pinned; APK packages are individually version-pinned
  - Direct APK packages use exact version pinning (`<package>=<version>`) for deterministic builds;
    transitive packages are left to apk, which installs the repository's current build
  - Renovate manages the base image version and digest updates
  - When updating the Alpine base image, APK package versions must be updated to match the new Alpine release

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

Tiered validation in `healthcheck.sh`:

1. **Tier 1**: Web server responding (HTTP success status)
2. **Tier 2**: CGI execution working (non-empty response)
3. **Tier 3**: Valid CGI infrastructure (no template/server errors)
4. **Tier 4**: Valid HTTP response headers (`Content-Type` present)
5. **Tier 5**: UPS connectivity — **strict mode only**

Tiers 1-4 validate infrastructure and always run. Tier 5 runs only when
`HEALTHCHECK_MODE=strict`, and fails the check if no UPS is reachable.

Configuration: 30s interval, 10s timeout, 15s start period, 3 retries

**Why Tier 5 is opt-in:** a UPS being unreachable is usually a network or UPS
problem, not a container problem. Reporting the container unhealthy for it would
make Docker restart a perfectly healthy web server. `strict` exists for deployments
that would rather surface UPS loss through container health.

### CI/CD Pipeline

The workflows in `.github/workflows/` provide automation:

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
   - Triggers: Push to main, published release, PRs (build only)

3. **`release-drafter.yml`**: Release notes via release-drafter
   - Refreshes one draft GitHub Release on every push to main
   - Publishing the draft (by a human) creates the git tag and fires `build.yml`
   - Uses the Conventional Commit type of each PR title to section entries and pick the version bump
   - Uses only the default `GITHUB_TOKEN`; no secrets

### Dependency Management

Renovate bot automatically manages updates with this strategy:

- **Alpine APK packages**: Extracted by Renovate's built-in `dockerfile` manager as datasource `apk`, looked up
  against the Alpine release line set by `registryUrls` (`branch=v3.XX`) in `.github/renovate.json`; auto-merge updates
- **Alpine base image digest**: Auto-merge (same version rebuild, no APK changes)
- **Alpine base image version**: Manual review required (APK pins and the `apk` `registryUrls` branch must be updated)
- **GitHub Actions**: Auto-merge minor/patch updates
- **Non-major dependencies**: Catch-all group for remaining deps, auto-merge minor/patch
- **NUT source**: Manual review required
- **Commit type**: `deps:` (a releasable type, drafts a patch release)
- **Schedule**: Weekly on Mondays
- **Security overrides**: Immediate processing regardless of schedule

All auto-merges require passing CI/CD checks.

**Alpine version bump procedure:** When upgrading Alpine across a minor release (3.X → 3.Y),
update all three in the same PR:
1. The `FROM alpine:` base image tag and digest in `Dockerfile`
2. All APK package version pins in `Dockerfile` (query new versions with `apk policy`)
3. The `branch=v3.X` in the `apk` datasource's `registryUrls` in `.github/renovate.json` (→ `branch=v3.Y`) —
   it must match the base image, or Renovate will propose pins from the old release line

### Automated Releases

The `release-drafter.yml` workflow uses [release-drafter](https://github.com/release-drafter/release-drafter):

1. Every push to `main` refreshes a single **draft** GitHub Release
2. The draft previews the next version and its release notes, built from the PRs merged since the last release
3. A human publishes the draft from the Releases page when they want to release
4. Publishing creates the `vX.Y.Z` tag and fires `release: published`, which runs `build.yml` to build, test, scan and
   promote the versioned image

`.github/release-drafter.yml` only `_extends` the shared fleet config in `owine/renovate-config`
(`release-drafter.yml` at its root). Change categories or templates there, not here.

A draft always exists. If only hidden types merged since the last release, it reads `_No user-facing changes._` with a
patch version — don't publish that.

The publish run starts as the human who published, which is why no App token is needed. Never let a workflow publish
the release with `GITHUB_TOKEN`: events from that token don't trigger other workflows, so `build.yml` would not run and
the release would ship without an image.

CHANGELOG.md is frozen at v1.10.1; later release notes live only on GitHub Releases.

### Conventional Commit Standards

This project uses [Conventional Commits](https://www.conventionalcommits.org/) to drive release notes and version bumps
via release-drafter, which reads the **PR title**, not the commits in it. PRs are squash-merged, so the title
becomes the commit subject — write it as a conventional commit.

**Releasable types** (listed in the draft, trigger version bumps):

| Type | Bump | Description |
|------|------|-------------|
| `feat:` | Minor | New features or capabilities |
| `fix:` | Patch | Bug fixes, security patches |
| `perf:` | Patch | Performance improvements |
| `revert:` | Patch | Reverts |
| `deps:` | Patch | Dependency updates (used by Renovate) |

**Non-releasable types** (no version bump, hidden from the release notes):

`chore:`, `build:`, `ci:`, `docs:`, `refactor:`, `style:`, `test:`

These PRs ship in the next release when a releasable PR is present, but do not appear in its notes. A PR title with no
conventional type is listed unsectioned and drafts a patch.

**Breaking changes:** Append `!` after the type **in the PR title** (e.g., `feat!:`, `fix(api)!:`) to trigger a major
version bump. A `BREAKING CHANGE:` footer in the PR body is ignored.

**Scopes** are optional and informational (e.g., `fix(security):`, `deps(alpine):`). They do not affect version bumps or
changelog grouping.

**Examples:**
```
feat: add upsset.cgi access control          → minor bump
fix(security): patch CVE-2026-XXXXX          → patch bump
deps: update alpine base image digest        → patch bump
ci: add path filters to workflows            → no bump
feat!: change hosts.conf format              → major bump
```

## Image Tagging Strategy

Published to `ghcr.io/owine/nut-cgi` with multiple tag variants:

- `vX.Y.Z` - Exact semantic version (production pinning)
- `vX.Y` - Latest patch in that minor series
- `vX` - Latest minor in that major series
- `latest` - Latest released version
- `sha-<commit>` - Commit-specific builds
- `main` - Main branch builds

Tags are applied by the `promote` job in `build.yml`, which runs only after the Trivy
scan and functional tests pass. A release whose scan fails gets a git tag and a GitHub
Release but **no image** — check that `promote` ran before assuming a version is pullable.

Releases before v1.2.0 were published without the `v` prefix (e.g. `1.1.2`).

**Production best practice**: Pin to an exact `vX.Y.Z` version. The current release is the
latest published GitHub Release (`gh release view`).

## Key Files

`ls` and `git ls-files` show the full layout, so it is not mirrored here. These are the files whose
purpose is not obvious from the name:

| File | Purpose |
|---|---|
| `Dockerfile` | Multi-stage build. Compiles NUT from source in the builder; owns every version pin. |
| `entrypoint.sh` | Applies the runtime env-var overrides by rewriting the lighttpd config into `/tmp`. |
| `healthcheck.sh` | Tiered health validation; honours `HEALTHCHECK_MODE`. |
| `strip-w3c-badges.sh` | Build-time removal of NUT's hotlinked W3C badges. Fails the build if upstream markup drifts past its matcher. |
| `hosts.conf.example` | Annotated template for the config users mount at `/etc/nut/hosts.conf`. |
| `.github/renovate.json` | Dependency automation, including the `apk` `registryUrls` that fixes the Alpine release line for APK pins. |
| `.github/workflows/build.yml` | Multi-arch build, Trivy scan, publish, and tag promotion. |
| `.github/release-drafter.yml` | Extends the shared fleet release-drafter config in `owine/renovate-config`. Override nothing here unless the tag shape changes. |

## Important Implementation Details

### UID/GID Flexibility

The image supports runtime UID override while maintaining security:

- Default user: `nut` (UID 1000, GID 1000)
- Override example: `docker run --user 1001:1001 ...`
- Configs at `/etc/nut/*` are mode 0644 (world-readable)
- lighttpd PID file in `/tmp/lighttpd.pid` (world-writable location)
- Health check script executable by any UID

**Rationale**: UPS host configurations are non-sensitive network data, so relaxed config permissions are acceptable for
deployment flexibility.

### Lighttpd Configuration

The Dockerfile configures lighttpd via sed commands:

- Document root: `/usr/lib/cgi-bin/nut`
- Default index: `upsstats.cgi`
- CGI enabled for `.cgi` files
- PID file: `/tmp/lighttpd.pid` (any UID can write)
- Logging: stdout/stderr (Docker best practice)

### Runtime Configuration Overrides

The image supports three env vars:

| Variable | Values | Read by | Effect |
|---|---|---|---|
| `HEALTHCHECK_MODE` | `basic` (default), `strict` | `healthcheck.sh` | `strict` adds Tier 5 (UPS connectivity) |
| `ENABLE_UPSSET` | `true` | `entrypoint.sh` | Drops the `upsset.cgi` deny rule |
| `CSP_POLICY` | policy string, or `none` | `entrypoint.sh` | Replaces the CSP header; `none` omits it |

`ENABLE_UPSSET` and `CSP_POLICY` work by rewriting the config to `/tmp/lighttpd.conf`
(the root filesystem is read-only in the recommended deployment).

**Any new override must go through the same single rewrite path.** That path
absolutises `include "mod_` → `include "/etc/lighttpd/mod_`, which is not cosmetic:
lighttpd resolves relative includes against the config file's own directory, and
`/tmp` contains no `mod_*.conf`. An override that rewrites the config on its own
branch without this fixup will fail to start.

The CSP is emitted as its own `setenv.add-response-header += ( ... )` directive rather
than as an entry in the main header array, so the entrypoint can replace or delete
that one line without stranding a trailing comma in the array.

`CSP_POLICY` is interpolated into a quoted lighttpd string, so the entrypoint rejects
values containing double quotes or newlines, and injects the value via awk's
`ENVIRON[]` rather than a sed replacement (sed would reinterpret `&` and `\`).

### NUT HTML Templates

The image does not vendor its own templates: the builder copies NUT's
`upsstats*.html.sample` files and `strip-w3c-badges.sh` removes the two hotlinked W3C
validator badges from them. The badges violate `img-src 'self' data:` and render
broken, and their `check/referer` links are dead anyway under `Referrer-Policy: no-referrer`.

Stripping rather than vendoring keeps NUT version bumps delivering upstream template
fixes. The tradeoff is that upstream markup changes could make the strip silently
no-op, so the script **fails the build** if any W3C reference survives. If a NUT bump
fails at that step, upstream reflowed the badge markup and the matcher in
`strip-w3c-badges.sh` needs updating — do not simply bypass it.

### Version Pinning Philosophy

The Alpine base image is digest-pinned (`alpine:<version>@sha256:...`) for exact reproducibility. Direct APK packages
are individually version-pinned (`<package>=<version>`) following the
[hassio-addons pattern](https://github.com/hassio-addons/addon-ssh) for fully deterministic builds.
When updating the Alpine base image to a new version, APK package versions must also be updated to
match the new Alpine release's repository. Renovate manages the base image version and digest.

## Configuration

User-facing configuration is documented in `README.md` and is not duplicated here:

- **`hosts.conf` format** — see "Configuration" in `README.md`; annotated examples live in
  `hosts.conf.example`
- **Environment variables** — see "Runtime Configuration Overrides" above for how they are
  implemented, and `README.md` for user-facing guidance
- **Production hardening** — `docker-compose.yml` is the working example, with every security
  option commented in place. It is executable, so it cannot drift from what actually runs.
  `SECURITY.md` covers the reasoning.

When configuration behaviour changes, update the code and `README.md`. This file should
describe *how it is built*, not restate *how it is used*.

## Migration Context

This project is forked from `danielb7390/nut-cgi` with these improvements:

- **Base image**: Debian → Alpine (substantially smaller)
- **Multi-architecture**: Added ARM64 support
- **Security**: Non-root user, vulnerability scanning, hardened configs
- **Automation**: CI/CD pipeline with GitHub Actions
- **Dependency management**: Renovate bot for automatic updates
- **Enhanced health checks**: Tiered validation vs. simple HTTP check

The migration maintains backward compatibility with `hosts.conf` format and UPS monitoring functionality.

## Semantic Versioning Policy

The draft's version bump is determined automatically by release-drafter from PR-title conventional commit prefixes
(see [Conventional Commit Standards](#conventional-commit-standards) above).

**Patch (v1.0.x):**
- Alpine package updates within same minor version
- Security fixes (CVE patches)
- Health check refinements
- Documentation updates

**Minor (v1.x.0):**
- Alpine minor version updates (3.X → 3.Y)
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

- **Release notes**: [GitHub Releases](https://github.com/owine/nut-cgi/releases); `CHANGELOG.md` is frozen at v1.10.1
- **Security policy**: `SECURITY.md` - Threat model, hardening, and vulnerability reporting
- **NUT documentation**: https://networkupstools.org/docs/
- **Alpine packages**: https://pkgs.alpinelinux.org/packages
