# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/owine/nut-cgi/compare/v1.1.2...HEAD
[1.1.2]: https://github.com/owine/nut-cgi/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/owine/nut-cgi/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/owine/nut-cgi/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/owine/nut-cgi/releases/tag/v1.0.0
[0.1.0]: https://github.com/danielb7390/nut-cgi
