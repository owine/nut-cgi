# Multi-stage build for minimal runtime image
FROM alpine:3.23.3@sha256:25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659 AS builder

# NUT version to build from source
ARG NUT_VERSION=2.8.4

# Install build dependencies for NUT compilation
# Package versions are locked by the Alpine base image digest
# hadolint ignore=DL3018
RUN apk upgrade --no-cache && \
    apk add --no-cache \
    build-base \
    autoconf \
    automake \
    libtool \
    pkgconf \
    gd-dev \
    curl

# Download, verify checksum, and extract NUT source
WORKDIR /build
RUN curl -L https://github.com/networkupstools/nut/releases/download/v${NUT_VERSION}/nut-${NUT_VERSION}.tar.gz -o nut-${NUT_VERSION}.tar.gz && \
    curl -L https://github.com/networkupstools/nut/releases/download/v${NUT_VERSION}/nut-${NUT_VERSION}.tar.gz.sha256 -o nut-${NUT_VERSION}.tar.gz.sha256 && \
    sha256sum -c nut-${NUT_VERSION}.tar.gz.sha256 && \
    tar -xzf nut-${NUT_VERSION}.tar.gz && \
    rm nut-${NUT_VERSION}.tar.gz nut-${NUT_VERSION}.tar.gz.sha256

# Build NUT with CGI support
WORKDIR /build/nut-${NUT_VERSION}
RUN ./configure \
    --prefix=/usr \
    --sysconfdir=/etc/nut \
    --with-cgi \
    --with-cgibindir=/usr/lib/cgi-bin/nut \
    --with-htmlpath=/usr/share/nut/html \
    --with-all=no \
    --without-ssl \
    --without-nss \
    --without-openssl \
    --disable-static \
    --datadir=/usr/share/nut \
    --with-user=nut \
    --with-group=nut && \
    # Parallel compilation for faster builds
    make -j"$(nproc)" && \
    make install DESTDIR=/build/rootfs && \
    # Strip debug symbols from binaries for smaller image
    find /build/rootfs/usr/lib -name '*.so*' -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true && \
    find /build/rootfs/usr/lib/cgi-bin -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true && \
    # Copy sample HTML templates to /etc/nut (where CGI programs expect them)
    cp /build/rootfs/etc/nut/upsstats.html.sample /build/rootfs/etc/nut/upsstats.html && \
    cp /build/rootfs/etc/nut/upsstats-single.html.sample /build/rootfs/etc/nut/upsstats-single.html && \
    # shellcheck disable=SC2015
    cp /build/rootfs/etc/nut/upsset.conf.sample /build/rootfs/etc/nut/upsset.conf 2>/dev/null || true

# ============================================================================
# Runtime Stage - Minimal footprint
# ============================================================================
FROM alpine:3.23.3@sha256:25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659

# Image metadata
LABEL org.opencontainers.image.title="nut-cgi" \
      org.opencontainers.image.description="Network UPS Tools CGI interface with lighttpd on Alpine Linux" \
      org.opencontainers.image.vendor="owine" \
      org.opencontainers.image.source="https://github.com/owine/nut-cgi" \
      org.opencontainers.image.licenses="MIT"

# Install runtime dependencies
# Package versions are locked by the Alpine base image digest
# hadolint ignore=DL3018
RUN apk upgrade --no-cache && \
    apk add --no-cache \
    lighttpd \
    curl \
    openssl \
    gd \
    zlib && \
    # Verify installations
    lighttpd -v && \
    curl --version

# Copy compiled NUT binaries, libraries, and CGI programs from builder
COPY --from=builder /build/rootfs/usr/lib/*.so* /usr/lib/
COPY --from=builder /build/rootfs/usr/cgi-bin /usr/lib/cgi-bin/nut
COPY --from=builder /build/rootfs/usr/share/nut /usr/share/nut
COPY --from=builder /build/rootfs/etc/nut /etc/nut

# Create non-root user with fixed UID/GID for default operation
# UID 1000 is standard for first user, ensures compatibility
RUN addgroup -g 1000 nut && \
    adduser -D -u 1000 -G nut -h /home/nut nut

# Disable default unconfigured site
RUN rm -f /etc/lighttpd/conf.d/*-unconfigured.conf

# Configure lighttpd: set document root, index file, PID location, logging, and CGI
# hadolint ignore=SC2016
RUN sed -i 's|^server.document-root.*|server.document-root = "/usr/lib/cgi-bin/nut"|' /etc/lighttpd/lighttpd.conf && \
    sed -i 's|^index-file.names.*|index-file.names = ( "upsstats.cgi" )|' /etc/lighttpd/lighttpd.conf && \
    sed -i 's|^server.pid-file.*|server.pid-file = "/tmp/lighttpd.pid"|' /etc/lighttpd/lighttpd.conf && \
    # Configure logging to stderr/stdout (Docker/read-only filesystem compatible)
    sed -i 's|^server.errorlog.*|server.errorlog = "/dev/stderr"|' /etc/lighttpd/lighttpd.conf && \
    sed -i 's|^accesslog.filename.*|accesslog.filename = "/dev/stdout"|' /etc/lighttpd/lighttpd.conf && \
    # Ensure mod_cgi.conf is included (uncomment if needed)
    sed -i 's|^#.*\(include.*mod_cgi.conf.*\)|\1|' /etc/lighttpd/lighttpd.conf && \
    # Add CGI configuration
    echo '' >> /etc/lighttpd/lighttpd.conf && \
    echo '# CGI configuration for nut' >> /etc/lighttpd/lighttpd.conf && \
    echo 'cgi.assign = ( ".cgi" => "" )' >> /etc/lighttpd/lighttpd.conf && \
    # Performance tuning for resource-constrained environments
    echo '' >> /etc/lighttpd/lighttpd.conf && \
    echo '# Performance tuning for CGI workload' >> /etc/lighttpd/lighttpd.conf && \
    echo 'server.max-connections = 16    # Limit concurrent connections (default: 1024)' >> /etc/lighttpd/lighttpd.conf && \
    echo 'server.max-keep-alive-requests = 4  # Keep-alive requests per connection' >> /etc/lighttpd/lighttpd.conf && \
    echo 'server.max-worker = 2          # Worker processes for CGI (default: 4)' >> /etc/lighttpd/lighttpd.conf && \
    echo 'server.max-fds = 128           # Max file descriptors (default: 1024)' >> /etc/lighttpd/lighttpd.conf && \
    # Security headers
    echo '' >> /etc/lighttpd/lighttpd.conf && \
    echo '# Security headers' >> /etc/lighttpd/lighttpd.conf && \
    echo 'server.modules += ( "mod_setenv" )' >> /etc/lighttpd/lighttpd.conf && \
    echo 'setenv.add-response-header = (' >> /etc/lighttpd/lighttpd.conf && \
    echo '  "X-Content-Type-Options" => "nosniff",' >> /etc/lighttpd/lighttpd.conf && \
    echo '  "X-Frame-Options" => "DENY",' >> /etc/lighttpd/lighttpd.conf && \
    echo '  "Referrer-Policy" => "no-referrer",' >> /etc/lighttpd/lighttpd.conf && \
    echo "  \"Content-Security-Policy\" => \"default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'\"" >> /etc/lighttpd/lighttpd.conf && \
    echo ')' >> /etc/lighttpd/lighttpd.conf && \
    # Hide server version and disable directory listing
    echo 'server.tag = ""' >> /etc/lighttpd/lighttpd.conf && \
    echo 'dir-listing.activate = "disable"' >> /etc/lighttpd/lighttpd.conf && \
    # Block upsset.cgi by default (administrative interface - security risk)
    echo '' >> /etc/lighttpd/lighttpd.conf && \
    echo '# Block upsset.cgi by default (use ENABLE_UPSSET=true to allow)' >> /etc/lighttpd/lighttpd.conf && \
    echo '$HTTP["url"] =~ "^/upsset\.cgi" { url.access-deny = ("") }' >> /etc/lighttpd/lighttpd.conf

# Make NUT config directory world-readable for --user UID override compatibility
RUN chmod 755 /etc/nut && \
    # Ensure CGI binaries are executable
    chmod 755 /usr/lib/cgi-bin/nut/*.cgi

# Copy health check and entrypoint scripts with execute permissions for any user
COPY --chmod=0755 healthcheck.sh /healthcheck.sh
COPY --chmod=0755 entrypoint.sh /entrypoint.sh

# Switch to non-root user for runtime
# Can be overridden with docker run --user <uid>:<gid>
USER nut

# NOTE: This container exposes plain HTTP on port 80.
# For production use, deploy behind a reverse proxy (e.g., Traefik, nginx)
# that provides TLS termination and authentication.
EXPOSE 80

# Health check using enhanced script
# - interval=30s: Check every 30 seconds
# - timeout=10s: Allow 10s for CGI processing
# - start-period=15s: Grace period for container initialization
# - retries=3: Require 3 consecutive failures before unhealthy
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD ["/healthcheck.sh"]

# Run via entrypoint (handles ENABLE_UPSSET env var)
ENTRYPOINT ["/entrypoint.sh"]
