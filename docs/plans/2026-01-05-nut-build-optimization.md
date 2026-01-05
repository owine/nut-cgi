# NUT Build Optimization Plan

**Date:** 2026-01-05
**Goal:** Reduce Docker build time by 60% (from 15-20min to 6-9min) by building only CGI components

## Research Summary

The current Dockerfile compiles all NUT drivers (USB, SNMP, serial, neon) even though we only need the CGI programs. CGI programs are pure network clients that don't require any driver code.

**Key insight:** Using `--with-all=no --with-cgi` disables all optional components but re-enables CGI specifically.

## Changes Required

### 1. Dockerfile - Builder Stage

**Current configure flags (lines 31-46):**
```dockerfile
RUN ./configure \
    --prefix=/usr \
    --sysconfdir=/etc/nut \
    --with-cgi \
    --with-cgibindir=/usr/lib/cgi-bin/nut \
    --with-htmlpath=/usr/share/nut/html \
    --with-dev \              # REMOVE - not needed
    --with-serial \           # REMOVE - driver code
    --with-usb \              # REMOVE - driver code
    --with-snmp \             # REMOVE - driver code
    --with-neon \             # REMOVE - driver code
    --with-ssl \              # REMOVE - redundant
    --with-openssl \          # REMOVE - not used by CGI
    --datadir=/usr/share/nut \
    --with-user=nut \
    --with-group=nut
```

**Optimized configure flags:**
```dockerfile
RUN ./configure \
    --prefix=/usr \
    --sysconfdir=/etc/nut \
    --with-cgi \
    --with-cgibindir=/usr/lib/cgi-bin/nut \
    --with-htmlpath=/usr/share/nut/html \
    --with-all=no \           # ADD - disable all optional features
    --datadir=/usr/share/nut \
    --with-user=nut \
    --with-group=nut
```

### 2. Dockerfile - Build Dependencies

**Current packages (lines 8-20):**
```dockerfile
RUN apk add --no-cache \
    build-base \
    autoconf \
    automake \
    libtool \
    pkgconfig \
    libusb-dev \      # REMOVE - for USB drivers
    neon-dev \        # REMOVE - for XML/HTTP drivers
    net-snmp-dev \    # REMOVE - for SNMP drivers
    openssl-dev \     # REMOVE - not used by CGI
    libmodbus-dev \   # REMOVE - for Modbus drivers
    gd-dev \          # KEEP - required for graph generation
    curl              # KEEP - for downloading source
```

**Optimized packages:**
```dockerfile
# hadolint ignore=DL3018
RUN apk add --no-cache \
    build-base \
    autoconf \
    automake \
    libtool \
    pkgconfig \
    gd-dev \
    curl
```

### 3. Dockerfile - Runtime Dependencies

**Current packages (lines 67-78):**
```dockerfile
RUN apk add --no-cache \
    lighttpd=1.4.82-r0 \     # KEEP - web server
    curl=8.17.0-r1 \         # KEEP - health checks
    libusb=1.0.29-r0 \       # REMOVE - USB driver library
    neon=0.35.0-r0 \         # REMOVE - XML/HTTP library
    net-snmp-libs=5.9.4-r2 \ # REMOVE - SNMP library
    openssl=3.5.4-r0 \       # KEEP - system TLS
    libmodbus=3.1.10-r0 \    # REMOVE - Modbus library
    gd=2.3.3-r10             # KEEP - graph rendering
```

**Optimized packages:**
```dockerfile
RUN apk add --no-cache \
    lighttpd=1.4.82-r0 \
    curl=8.17.0-r1 \
    openssl=3.5.4-r0 \
    gd=2.3.3-r10 && \
    lighttpd -v && \
    curl --version
```

## Implementation Steps

### Step 1: Update Dockerfile
1. Edit builder stage build dependencies (remove 5 packages)
2. Edit configure flags (add `--with-all=no`, remove 6 flags)
3. Edit runtime dependencies (remove 4 packages)

### Step 2: Local Testing
```bash
# Build single-arch for testing
docker build -t nut-cgi:test-optimized .

# Verify CGI binaries exist
docker run --rm nut-cgi:test-optimized ls -la /usr/lib/cgi-bin/nut/

# Expected output:
# -rwxr-xr-x upsstats.cgi
# -rwxr-xr-x upsstats-single.cgi
# -rwxr-xr-x upsset.cgi
# -rwxr-xr-x upsimage.cgi

# Verify HTML templates
docker run --rm nut-cgi:test-optimized ls -la /etc/nut/*.html

# Test runtime
docker run -d --name nut-test -p 8080:80 \
  -v /tmp/hosts.conf:/etc/nut/hosts.conf:ro \
  nut-cgi:test-optimized

# Wait for health check
sleep 10

# Test CGI execution
curl http://localhost:8080/upsstats.cgi

# Should return HTML with UPS status (or connection error if no UPS configured)

# Check health status
docker ps | grep nut-test
# Should show (healthy)

# Cleanup
docker stop nut-test && docker rm nut-test
```

### Step 3: Measure Improvements
```bash
# Time the build
time docker build -t nut-cgi:test-optimized .

# Compare sizes
docker images | grep nut-cgi

# Check build logs for any warnings
docker build --progress=plain -t nut-cgi:test-optimized . 2>&1 | tee build.log
```

### Step 4: Commit and Push
```bash
git add Dockerfile
git commit -m "perf: optimize NUT build to compile only CGI components

- Use --with-all=no to disable all optional features
- Re-enable only CGI with --with-cgi
- Remove unnecessary driver build dependencies (libusb-dev, neon-dev, net-snmp-dev, libmodbus-dev, openssl-dev)
- Remove unnecessary runtime dependencies (libusb, neon, net-snmp-libs, libmodbus)
- Keep only required packages: gd (graph rendering), lighttpd (web server), curl (health checks)

Build time improvement: ~60% reduction (15-20min → 6-9min for multi-arch)
Image size reduction: ~20% smaller runtime image

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push origin main
```

### Step 5: Create Release
After CI/CD passes:
```bash
git tag -a v1.1.0 -m "Release v1.1.0: Build Time Optimization

Performance improvements:
- 60% faster multi-arch builds (6-9min vs 15-20min)
- Smaller Docker images (~20% reduction)
- Reduced build dependencies
- No functional changes to CGI programs

🤖 Generated with [Claude Code](https://claude.com/claude-code)"

git push origin v1.1.0
```

## Expected Results

**Actual Baseline (measured 2026-01-05):**
- Multi-arch build time: 37 minutes (run #20723994778)
- Runtime image size: 82.3MB (ghcr.io/owine/nut-cgi:latest)

| Metric | Before (Actual) | After (Target) | Improvement |
|--------|-----------------|----------------|-------------|
| Multi-arch build time | 37 min | 15-17 min | 55-60% faster |
| Runtime image size | 82.3MB | 65-70MB | 15-20% smaller |
| Builder image size | ~600-700MB | ~400-450MB | 35% smaller |
| Build dependencies | 12 packages | 7 packages | 5 removed |
| Runtime dependencies | 7 packages | 4 packages | 3 removed |

## Validation Checklist

Before merging:
- [ ] All four CGI binaries present (/usr/lib/cgi-bin/nut/*.cgi)
- [ ] HTML templates copied correctly (/etc/nut/*.html)
- [ ] Health check passes (container shows "healthy")
- [ ] CGI execution works (curl returns HTML, not errors)
- [ ] No missing library errors in logs
- [ ] Multi-arch build succeeds (amd64 + arm64)
- [ ] Build time measured and documented
- [ ] Image size compared and documented

## Risks & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Missing dependencies at runtime | Low | High | Test thoroughly with health checks |
| Configure fails with --with-all=no | Low | High | Test locally first, check NUT docs |
| CGI functionality broken | Low | High | Full integration test before merge |
| Build time not improved as expected | Medium | Low | Document actual results |

## Rollback Plan

If optimization causes issues:
```bash
# Revert the commit
git revert HEAD

# Or restore from v1.0.0
git checkout v1.0.0 -- Dockerfile
git commit -m "chore: rollback to v1.0.0 Dockerfile"
```

## References

- [NUT Optional Features Documentation](https://networkupstools.org/docs/user-manual.chunked/aphs04.html)
- [NUT Configure Options](https://github.com/networkupstools/nut/blob/master/docs/configure.txt)
- Research findings: Task agent a3f742c
