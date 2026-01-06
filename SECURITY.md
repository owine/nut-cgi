# Security Policy

## Overview

The security of the nut-cgi project is a top priority. This document outlines our security practices, supported versions, and how to report vulnerabilities responsibly.

## Supported Versions

We provide security updates for the following versions:

| Version | Supported          | Notes                                      |
| ------- | ------------------ | ------------------------------------------ |
| latest  | :white_check_mark: | Main branch, receives all updates          |
| v1.x.x  | :white_check_mark: | Current major version, actively maintained |
| < v1.0  | :x:                | Pre-release versions, no longer supported  |

**Recommendation:** Always use the latest released version (tagged with `v*.*.*`) in production environments.

## Security Features

### Built-in Security Measures

1. **Non-root User Execution**
   - Container runs as UID 1000 by default
   - Supports `--user` override for custom UID/GID requirements
   - No privilege escalation capabilities

2. **Read-only Root Filesystem**
   - Supports `read_only: true` in docker-compose
   - Only `/tmp` requires write access (via tmpfs)
   - Prevents runtime modifications to system files

3. **Dependency Management**
   - All Alpine packages are version-pinned for reproducibility
   - Weekly Renovate bot updates with security priority
   - Automated Trivy vulnerability scanning (HIGH/CRITICAL)

4. **Supply Chain Security**
   - SBOM (Software Bill of Materials) attestations
   - Provenance attestations for build reproducibility
   - SHA256 digest pinning for base images

5. **Minimal Attack Surface**
   - Alpine Linux base (~50MB total image size)
   - Only essential packages installed
   - No build tools in runtime image

### Recommended Production Hardening

Apply these security options in production deployments:

```yaml
services:
  nut-cgi:
    image: ghcr.io/owine/nut-cgi:v1.0.0  # Pin to specific version
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
```

## Reporting a Vulnerability

We take security vulnerabilities seriously and appreciate responsible disclosure.

### How to Report

**Preferred Method:** GitHub Security Advisories
1. Go to https://github.com/owine/nut-cgi/security/advisories
2. Click "Report a vulnerability"
3. Fill out the advisory form with details

**Alternative Method:** Email
- Send detailed report to: [Your security contact email]
- Use GPG key: [Optional: Your GPG key ID]
- Include "SECURITY" in the subject line

### What to Include

Please provide the following information:

1. **Vulnerability Description**
   - Type of issue (e.g., injection, XSS, privilege escalation)
   - Attack vector and prerequisites
   - Potential impact assessment

2. **Reproduction Steps**
   - Detailed steps to reproduce the vulnerability
   - Proof-of-concept code if applicable
   - Affected versions

3. **Environment Details**
   - Docker version
   - Host OS and architecture
   - Relevant configuration (hosts.conf, docker-compose.yml)

4. **Suggested Fix** (optional)
   - Proposed patches or mitigations
   - Alternative approaches

### Response Timeline

| Stage                  | Timeline      |
| ---------------------- | ------------- |
| Initial Response       | Within 48 hours |
| Vulnerability Triage   | Within 7 days   |
| Fix Development        | Varies by severity |
| Patch Release          | ASAP for CRITICAL |
| Public Disclosure      | After fix release |

**Severity Levels:**
- **CRITICAL:** Immediate action, released within 24-48 hours
- **HIGH:** Prioritized, released within 7 days
- **MEDIUM:** Scheduled for next release
- **LOW:** Addressed in regular maintenance cycle

## Security Scanning

### Automated Scans

1. **Trivy Vulnerability Scanner**
   - Runs weekly (Monday 00:00 UTC)
   - Triggered after every build
   - Scans for HIGH and CRITICAL vulnerabilities
   - Results published to GitHub Security tab

2. **Dependency Updates**
   - Renovate bot monitors all dependencies
   - Security alerts bypasses schedule (immediate processing)
   - Auto-merge for patch-level security updates

### Manual Security Testing

We recommend these security tests before deploying in production:

```bash
# 1. Scan the container image
docker pull ghcr.io/owine/nut-cgi:latest
trivy image --severity HIGH,CRITICAL ghcr.io/owine/nut-cgi:latest

# 2. Test security options
docker run --rm \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  -v $(pwd)/hosts.conf:/etc/nut/hosts.conf:ro \
  ghcr.io/owine/nut-cgi:latest

# 3. Verify non-root execution
docker run --rm ghcr.io/owine/nut-cgi:latest id
# Expected: uid=1000(nut) gid=1000(nut)
```

## Known Security Considerations

### Configuration File Permissions

**Consideration:** `/etc/nut/hosts.conf` is mounted as world-readable (mode 0644)

**Rationale:** The `hosts.conf` file contains only UPS monitoring endpoints (hostname/IP + port), which are non-sensitive network configuration data. This enables flexible UID/GID override via `--user` flag.

**Security Impact:** Low - hosts.conf should never contain credentials (use `upsd.users` on the UPS server for authentication)

**Mitigation:** If you have sensitive network topology concerns:
- Use Docker secrets or environment variables for truly sensitive data
- Restrict host-level access to the hosts.conf file
- Run container with matching UID/GID and set stricter permissions

### lighttpd CGI Execution

**Consideration:** CGI scripts run with same privileges as lighttpd process (UID 1000)

**Security Impact:** Low - CGI programs are read-only executables, no user input processing

**Mitigation:** Container runs in read-only filesystem mode, preventing runtime modifications

### Network Exposure

**Consideration:** Web interface exposed on port 80 (HTTP, not HTTPS)

**Rationale:** Intended for internal network use behind reverse proxy or VPN

**Mitigation for Internet Exposure:**
- Use reverse proxy (nginx, Traefik, Caddy) with TLS termination
- Implement authentication at reverse proxy level
- Use VPN or wireguard for remote access
- Apply firewall rules to restrict access

Example Traefik configuration:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.nut-cgi.rule=Host(`ups.example.com`)"
  - "traefik.http.routers.nut-cgi.tls=true"
  - "traefik.http.routers.nut-cgi.middlewares=auth"
  - "traefik.http.middlewares.auth.basicauth.users=user:$$apr1$$..."
```

## Security Update Policy

### Semantic Versioning for Security

We follow semantic versioning with security considerations:

- **Patch (v1.0.x):** Security fixes, no breaking changes
- **Minor (v1.x.0):** New security features, backward compatible
- **Major (vx.0.0):** Security-related breaking changes

### Security-Related Changes

The following trigger PATCH releases:
- HIGH/CRITICAL vulnerability fixes in dependencies
- Security misconfigurations discovered in lighttpd/Alpine
- Exploitable bugs in health check or CGI handling

The following trigger MINOR releases:
- New security hardening features
- Additional security options in docker-compose
- Enhanced vulnerability scanning

## Compliance and Standards

This project follows:

- **CIS Docker Benchmark** - Container hardening guidelines
- **OWASP Docker Security** - Application security best practices
- **Alpine Linux Security** - Upstream security advisories
- **Network UPS Tools Security** - NUT project security policies

## Additional Resources

- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Alpine Linux Security](https://alpinelinux.org/security/)
- [Network UPS Tools Security](https://networkupstools.org/docs/security.html)
- [GitHub Security Advisories](https://github.com/owine/nut-cgi/security/advisories)

## Contact

For security-related questions or concerns:
- GitHub Issues: https://github.com/owine/nut-cgi/issues (for non-sensitive discussions)
- Security Advisories: https://github.com/owine/nut-cgi/security/advisories (for vulnerabilities)

---

**Last Updated:** 2026-01-06
