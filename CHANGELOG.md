# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.9.5](https://github.com/owine/nut-cgi/compare/v1.9.4...v1.9.5) (2026-07-27)


### Dependencies

* update actions/checkout action to v7.0.1 ([#84](https://github.com/owine/nut-cgi/issues/84)) ([a590835](https://github.com/owine/nut-cgi/commit/a590835d905732d0ad714bcc6462036c74eb2100))
* update docker/login-action action to v4.5.0 ([#86](https://github.com/owine/nut-cgi/issues/86)) ([cd110f4](https://github.com/owine/nut-cgi/commit/cd110f4fb915f9fc78f5c7bc2cdb7c438aab88f4))
* update docker/login-action action to v4.5.1 ([#88](https://github.com/owine/nut-cgi/issues/88)) ([808e423](https://github.com/owine/nut-cgi/commit/808e423041b59c6afed377e9a76c43a85c7e3d7e))
* update github/codeql-action action to v4.37.3 ([#85](https://github.com/owine/nut-cgi/issues/85)) ([b70edcd](https://github.com/owine/nut-cgi/commit/b70edcd8d1e9a3d4b86930e07927da7228456a4d))

## [1.9.4](https://github.com/owine/nut-cgi/compare/v1.9.3...v1.9.4) (2026-07-16)


### Bug Fixes

* resolve CSP violations from W3C badges and injected scripts ([#82](https://github.com/owine/nut-cgi/issues/82)) ([7454db7](https://github.com/owine/nut-cgi/commit/7454db7626427853012e45913c733a45bff6d72a))


### Dependencies

* update dependency alpine_3_24/lighttpd to v1.4.85-r0 ([#81](https://github.com/owine/nut-cgi/issues/81)) ([0e091a0](https://github.com/owine/nut-cgi/commit/0e091a017a6dc6a7243904d8ee0f44d8284b0c0b))
* update github/codeql-action action to v4.37.1 ([#79](https://github.com/owine/nut-cgi/issues/79)) ([a93fe49](https://github.com/owine/nut-cgi/commit/a93fe4905aac41f622767cac359a671df628aaf9))

## [1.9.3](https://github.com/owine/nut-cgi/compare/v1.9.2...v1.9.3) (2026-07-13)


### Dependencies

* update github/codeql-action action to v4.37.0 ([#77](https://github.com/owine/nut-cgi/issues/77)) ([d94fb84](https://github.com/owine/nut-cgi/commit/d94fb84f0bc49500a3d7bfd5fbc62c6476963785))

## [1.9.2](https://github.com/owine/nut-cgi/compare/v1.9.1...v1.9.2) (2026-07-06)


### Dependencies

* update dependency alpine_3_24/curl to v8.21.0-r0 ([#75](https://github.com/owine/nut-cgi/issues/75)) ([7059a46](https://github.com/owine/nut-cgi/commit/7059a46f8127b8e018ee73ea728b0406727c1084))

## [1.9.1](https://github.com/owine/nut-cgi/compare/v1.9.0...v1.9.1) (2026-06-22)


### Bug Fixes

* run build on push/tag (skipped since changes gate went PR-only) ([#66](https://github.com/owine/nut-cgi/issues/66)) ([cd8c9d4](https://github.com/owine/nut-cgi/commit/cd8c9d4f1e940093721f6508e2bdf45128e0440b))
* run changes job always so push/tag builds aren't skipped ([#68](https://github.com/owine/nut-cgi/issues/68)) ([2b312e4](https://github.com/owine/nut-cgi/commit/2b312e4867e33cae09b3601e0d2b794720624f9f))

## [1.9.0](https://github.com/owine/nut-cgi/compare/v1.8.2...v1.9.0) (2026-06-15)


### Features

* update to Alpine 3.24 ([78dcf92](https://github.com/owine/nut-cgi/commit/78dcf9270775ebecc3eee9b928e0e2564795bf30))

## [1.8.2](https://github.com/owine/nut-cgi/compare/v1.8.1...v1.8.2) (2026-05-04)


### Bug Fixes

* **security:** pin nghttp2-libs to 1.69.0-r0 for CVE-2026-27135 ([f88a7b9](https://github.com/owine/nut-cgi/commit/f88a7b9703f2d67ded5d2f84fdca20df8c5e1ac5))

## [1.8.1](https://github.com/owine/nut-cgi/compare/v1.8.0...v1.8.1) (2026-04-27)


### Bug Fixes

* **security:** pin libxpm to 3.5.19-r0 for CVE-2026-4367 ([25cb219](https://github.com/owine/nut-cgi/commit/25cb219044448794790cda7a5fded4c5f37b161a))

## [1.8.0](https://github.com/owine/nut-cgi/compare/v1.7.0...v1.8.0) (2026-04-07)


### Features

* upgrade NUT to v2.8.5 ([7a650a8](https://github.com/owine/nut-cgi/commit/7a650a882bbc360fc98c00f89b1e6459b143bb35))


### Bug Fixes

* correct semantic commit prefix and add feat: for NUT updates ([58f1e71](https://github.com/owine/nut-cgi/commit/58f1e7114c63acc04bb3b673fd3cd026668a1c03))

## [1.7.0](https://github.com/owine/nut-cgi/compare/v1.6.0...v1.7.0) (2026-04-05)


### Features

* add Repology datasource for automated APK package version tracking ([b163fca](https://github.com/owine/nut-cgi/commit/b163fcae7209d60db1dfc495e34d1e7ef8e10d5e))
* pin APK packages to exact versions for deterministic builds ([40b9102](https://github.com/owine/nut-cgi/commit/40b91022ff2ad4ae87a645a02853e81d2f881436))

## [1.6.0](https://github.com/owine/nut-cgi/compare/v1.5.0...v1.6.0) (2026-04-02)


### Features

* optimize NUT source build for CGI-only targets ([015b386](https://github.com/owine/nut-cgi/commit/015b386d6cf93df5829c53ca4699aef4243863e1))

## [1.5.0](https://github.com/owine/nut-cgi/compare/v1.4.4...v1.5.0) (2026-03-30)


### Features

* add release-please configuration files ([f570c6f](https://github.com/owine/nut-cgi/commit/f570c6f9cb84b1d7c01a44d249f9970d2b0398fc))
* replace Claude Code release workflow with release-please ([bf90d1d](https://github.com/owine/nut-cgi/commit/bf90d1dd671d25c25e21ab69e67d698177151ac5))

## [Unreleased]

## [1.4.4] - 2026-03-17

### Changed
- Update non-major dependencies via Renovate (#27, #29)
- Update `actions/create-github-app-token` action to v3 (#28)
- Update `@anthropic-ai/claude-code` to v2.1.76 (#30)

## [1.4.3] - 2026-03-10

### Fixed
- Add `apk upgrade` to Dockerfile to patch CVEs beyond what the base image provides
- Remove APK version pins in favor of Alpine base image digest for cleaner dependency management
- Ignore hadolint DL3018 for unpinned APK packages

### Changed
- Consolidate Renovate schedule to Mondays with grouped PRs
- Pin `node-version` and `claude-code` for Renovate management
- Update `docker/setup-qemu-action` to v4
- Update `docker/setup-buildx-action` to v4

## [1.4.2] - 2026-03-09

### Fixed
- Pin `zlib=1.3.2-r0` to resolve CVE-2026-22184 security vulnerability
- Use `jq has()` for JSON validation in release workflow
- Add boolean type assertion to release JSON validation

### Changed
- Update `docker/build-push-action` to v7
- Update `docker/login-action` to v4
- Update `docker/metadata-action` to v6
- Update other GitHub Actions dependencies

## [1.4.1] - 2026-02-16

### Changed
- Updated actions/setup-node action to v6 (#16)
- Updated dependency node to v24 (#17)
- Updated github actions (#15)

### Fixed
- Deduplicate v1.4.0 CHANGELOG entries

## [1.4.0] - 2026-02-10

### Added

- Automated weekly release workflow using Claude Code for commit analysis
  - Runs every Monday at 4am CST (10:00 UTC)
  - Analyzes unreleased commits and determines semver bump
  - Updates CHANGELOG.md, creates git tag, and publishes GitHub Release
  - Supports dry-run mode via `workflow_dispatch` for testing
  - Uses GitHub App token to trigger downstream build pipeline on tag push

### Changed

- Renovate schedule moved from Monday to Sunday (before 12pm) so dependency
  PRs are merged before the Monday automated release window

## [1.3.0] - 2026-02-07

### Added

- Source checksum verification for NUT tarball downloads (C1)
  - Downloads `.sha256` file from NUT GitHub release and verifies with `sha256sum -c`
  - Checksum URL auto-updates when Renovate bumps `NUT_VERSION`
  - Build fails immediately on integrity violation
- Security response headers via lighttpd `mod_setenv` (H3)
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Referrer-Policy: no-referrer`
  - `Content-Security-Policy: default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'`
- `upsset.cgi` blocked by default via lighttpd URL access-deny rule (H1)
  - Prevents unauthorized UPS configuration changes (shutdown, battery tests)
  - Override with `ENABLE_UPSSET=true` environment variable when behind authenticated reverse proxy
- `entrypoint.sh` for runtime configuration of `upsset.cgi` access
  - Read-only filesystem compatible (writes modified config to `/tmp`)
  - Uses `exec` for proper PID 1 signal handling
- CI test steps for security header verification and `upsset.cgi` blocking
- Reverse proxy deployment notes on Dockerfile `EXPOSE` and docker-compose.yml

### Changed

- CI/CD permissions scoped per-job instead of workflow-level (H6)
  - `build`: `contents: read`, `packages: write`, `id-token: write`
  - `test`: `contents: read`, `packages: read`
  - `scan`: `contents: read`, `packages: read`, `security-events: write`
  - `promote`: `packages: write`
- CI/CD `run:` blocks no longer use `${{ }}` expressions directly (H5)
  - All expressions moved to step-level `env:` blocks to prevent shell injection
- Container entrypoint changed from `CMD` to `ENTRYPOINT` for entrypoint.sh
- lighttpd server version header hidden (`server.tag = ""`)
- lighttpd directory listing disabled (`dir-listing.activate = "disable"`)
- docker-compose.yml now includes `security_opt: no-new-privileges:true` (H4)
- docker-compose.yml now includes `cap_drop: ALL` (H4)
- Shellcheck linting now covers `entrypoint.sh` in addition to `healthcheck.sh`

## [1.2.1] - 2026-01-07

### Changed

- Updated GitHub Actions to latest versions
- Updated Alpine base image to 3.23.3
- Updated OpenSSL to 3.5.5-r0
- Adjusted Renovate schedule and removed rate limits

## [1.2.0] - 2026-01-06

### Added

- Enhanced health check with multi-tier validation (5 tiers)
- Health check modes: `basic` (default) and `strict` (validates UPS connectivity)
- HTTP headers validation in health check
- lighttpd performance tuning for resource-constrained environments
  - `server.max-connections = 16` (reduced from 1024)
  - `server.max-keep-alive-requests = 4`
  - `server.max-worker = 2` (reduced from 4)
  - `server.max-fds = 128` (reduced from 1024)
- `hosts.conf.example` with comprehensive UPS monitoring examples
- `SECURITY.md` with vulnerability reporting policy and security best practices
- `CHANGELOG.md` (this file) following Keep a Changelog format
- Enhanced Renovate configuration with better commit messages and descriptions
- Dynamic Alpine package version tracking in Renovate
- Comprehensive functional testing suite in CI/CD pipeline
  - Container health verification
  - Web server response testing
  - HTTP headers validation
  - CGI execution testing
  - Health check script testing (basic and strict modes)
  - Non-root user verification
  - Read-only filesystem compatibility testing

### Changed

- CI/CD workflow restructured to build-test-promote pattern
  - Build creates `sha-<commit>` tag only
  - Functional testing and security scanning run in parallel on same image
  - Image promotion with additional tags only occurs after all tests pass
- Docker image tagging strategy:
  - `:main` tag now represents latest tested main branch build (previously `:latest`)
  - `:latest` tag now represents latest tested release only
  - `:sha-<commit>` tags are now documented (for debugging/pinning)
- docker-compose.yml now includes `HEALTHCHECK_MODE` environment variable documentation

### Fixed

- Renovate repology configuration for Alpine 3.23 package tracking
- Renovate custom manager conflict with native Dockerfile manager for Alpine base image

## [1.1.2] - 2026-01-06

### Fixed

- lighttpd logging configuration for read-only filesystem compatibility
  - `server.errorlog` now points to `/dev/stderr`
  - `accesslog.filename` now points to `/dev/stdout`
  - Resolves issues with Docker logging and read-only root filesystem

### Changed

- Simplified example docker-compose.yml for better clarity

## [1.1.1] - 2026-01-05

### Fixed

- CI: Quote `GITHUB_OUTPUT` in shell scripts to satisfy shellcheck
- CI: Improved lint workflow efficiency

### Changed

- Security scanning now targets specific built image SHA instead of `:latest`
- Security scans enabled for release tag builds

## [1.1.0] - 2026-01-05

### Added

- Renovate bot for automated dependency management
  - Auto-merge for Alpine base image patch updates
  - Auto-merge for Alpine APK package revisions
  - Auto-merge for GitHub Actions minor/patch updates
  - Weekly schedule (Monday mornings)
- Comprehensive CI/CD pipeline with GitHub Actions
  - Lint workflow (hadolint, shellcheck, yamllint, actionlint)
  - Multi-architecture build workflow (amd64, arm64)
  - Trivy security scanning workflow
- SBOM and provenance attestations for supply chain security
- Multi-architecture support (linux/amd64, linux/arm64)

### Changed

- All GitHub Actions pinned to specific commit SHAs for security
- Alpine APK packages pinned to specific versions
- NUT version now tracked via `ARG NUT_VERSION=2.8.4`

## [1.0.0] - 2026-01-05

### Added

- Multi-stage Dockerfile building NUT 2.8.4 from source
- Alpine Linux 3.23 as base image (~50MB total size)
- Non-root user execution (UID 1000, GID 1000)
- Flexible UID/GID override support via `--user` flag
- Enhanced health check script with three-tier validation:
  1. Web server responding
  2. CGI execution working
  3. Valid CGI output
- Read-only root filesystem support with tmpfs for `/tmp`
- Security hardening:
  - World-readable NUT configs for UID flexibility
  - lighttpd PID file in `/tmp` (world-writable)
  - Explicit version pinning for all dependencies
- lighttpd web server configuration:
  - Document root: `/usr/lib/cgi-bin/nut`
  - Default index: `upsstats.cgi`
  - Native CGI support
  - Logging to stdout/stderr
- Example docker-compose.yml with security best practices
- Comprehensive documentation:
  - `README.md` with quick start and troubleshooting
  - `CLAUDE.md` with architectural decisions
  - Design documents in `docs/plans/`
- MIT License

### Changed

- Migrated from Debian base image to Alpine Linux (4x size reduction)
- Replaced Alpine APK `nut-cgi` package with source build for latest version

### Removed

- Debian-based Dockerfile
- Default unconfigured site in lighttpd

## [0.1.0] - 2024-12-XX (Pre-Alpine)

### Added

- Initial Debian-based Docker image
- Basic nut-cgi web interface
- lighttpd web server
- Simple health check

---

## Version History Notes

### Version Numbering

- **Patch (x.x.X)**: Bug fixes, dependency updates, security patches
- **Minor (x.X.0)**: New features, non-breaking changes
- **Major (X.0.0)**: Breaking changes, major architectural changes

### Migration from danielb7390/nut-cgi

This project is a fork of [danielb7390/nut-cgi](https://github.com/danielb7390/nut-cgi) with significant enhancements:

- **Alpine Linux** instead of Debian (~200MB → ~50MB)
- **Multi-architecture** support (ARM64 added)
- **Security hardening** (non-root user, pinned dependencies, vulnerability scanning)
- **CI/CD automation** (GitHub Actions, Renovate bot)
- **Enhanced health checks** (three-tier validation)
- **Build from source** (NUT 2.8.4 vs older Alpine package)

## Links

- **Repository**: <https://github.com/owine/nut-cgi>
- **Container Registry**: <https://github.com/owine/nut-cgi/pkgs/container/nut-cgi>
- **Issue Tracker**: <https://github.com/owine/nut-cgi/issues>
- **Security Advisories**: <https://github.com/owine/nut-cgi/security/advisories>

[Unreleased]: https://github.com/owine/nut-cgi/compare/v1.4.4...HEAD
[1.4.4]: https://github.com/owine/nut-cgi/compare/v1.4.3...v1.4.4
[1.4.3]: https://github.com/owine/nut-cgi/compare/v1.4.2...v1.4.3
[1.4.2]: https://github.com/owine/nut-cgi/compare/v1.4.1...v1.4.2
[1.4.1]: https://github.com/owine/nut-cgi/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/owine/nut-cgi/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/owine/nut-cgi/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/owine/nut-cgi/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/owine/nut-cgi/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/owine/nut-cgi/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/owine/nut-cgi/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/owine/nut-cgi/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/owine/nut-cgi/releases/tag/v1.0.0
[0.1.0]: https://github.com/danielb7390/nut-cgi
