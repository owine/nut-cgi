# Multi-stage build for minimal runtime image
FROM alpine:3.23.2@sha256:865b95f46d98cf867a156fe4a135ad3fe50d2056aa3f25ed31662dff6da4eb62 AS builder

# NUT version to build from source
ARG NUT_VERSION=2.8.3

# Install build dependencies for NUT compilation
RUN apk add --no-cache \
    build-base=0.5-r3 \
    autoconf=2.72-r1 \
    automake=1.18.1-r0 \
    libtool=2.5.4-r2 \
    pkgconf=2.5.1-r0 \
    gd-dev=2.3.3-r10 \
    curl=8.17.0-r1

# Download and extract NUT source
WORKDIR /build
RUN curl -L https://github.com/networkupstools/nut/releases/download/v${NUT_VERSION}/nut-${NUT_VERSION}.tar.gz -o nut.tar.gz && \
    tar -xzf nut.tar.gz && \
    rm nut.tar.gz

# Build NUT with CGI support
WORKDIR /build/nut-${NUT_VERSION}
RUN ./configure \
    --prefix=/usr \
    --sysconfdir=/etc/nut \
    --with-cgi \
    --with-cgibindir=/usr/lib/cgi-bin/nut \
    --with-htmlpath=/usr/share/nut/html \
    --with-all=no \
    --datadir=/usr/share/nut \
    --with-user=nut \
    --with-group=nut && \
    make && \
    make install DESTDIR=/build/rootfs && \
    # Copy sample HTML templates to /etc/nut (where CGI programs expect them)
    cp /build/rootfs/etc/nut/upsstats.html.sample /build/rootfs/etc/nut/upsstats.html && \
    cp /build/rootfs/etc/nut/upsstats-single.html.sample /build/rootfs/etc/nut/upsstats-single.html && \
    # shellcheck disable=SC2015
    cp /build/rootfs/etc/nut/upsset.conf.sample /build/rootfs/etc/nut/upsset.conf 2>/dev/null || true

# ============================================================================
# Runtime Stage - Minimal footprint with pinned versions
# ============================================================================
FROM alpine:3.23.2@sha256:865b95f46d98cf867a156fe4a135ad3fe50d2056aa3f25ed31662dff6da4eb62

# Image metadata
LABEL org.opencontainers.image.title="nut-cgi" \
      org.opencontainers.image.description="Network UPS Tools CGI interface with lighttpd on Alpine Linux" \
      org.opencontainers.image.vendor="owine" \
      org.opencontainers.image.source="https://github.com/owine/nut-cgi" \
      org.opencontainers.image.licenses="MIT"

# Install runtime dependencies with pinned versions
RUN apk add --no-cache \
    lighttpd=1.4.82-r0 \
    curl=8.17.0-r1 \
    openssl=3.5.4-r0 \
    gd=2.3.3-r10 && \
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

# Configure lighttpd for non-root operation and arbitrary UID support
RUN mkdir -p /var/log/lighttpd /var/lib/lighttpd && \
    # Make directories accessible by any UID (for --user override)
    chown -R nut:nut /var/log/lighttpd /var/lib/lighttpd && \
    chmod 755 /var/log/lighttpd /var/lib/lighttpd && \
    # Disable default unconfigured site
    rm -f /etc/lighttpd/conf.d/*-unconfigured.conf

# Configure lighttpd: set document root, index file, PID location, and CGI
RUN sed -i 's|^server.document-root.*|server.document-root = "/usr/lib/cgi-bin/nut"|' /etc/lighttpd/lighttpd.conf && \
    sed -i 's|^index-file.names.*|index-file.names = ( "upsstats.cgi" )|' /etc/lighttpd/lighttpd.conf && \
    sed -i 's|^server.pid-file.*|server.pid-file = "/tmp/lighttpd.pid"|' /etc/lighttpd/lighttpd.conf && \
    # Ensure mod_cgi.conf is included (uncomment if needed)
    sed -i 's|^#.*\(include.*mod_cgi.conf.*\)|\1|' /etc/lighttpd/lighttpd.conf && \
    # Add CGI configuration
    echo '' >> /etc/lighttpd/lighttpd.conf && \
    echo '# CGI configuration for nut' >> /etc/lighttpd/lighttpd.conf && \
    echo 'cgi.assign = ( ".cgi" => "" )' >> /etc/lighttpd/lighttpd.conf

# Make NUT config directory world-readable for --user UID override compatibility
RUN chmod 755 /etc/nut && \
    # Ensure CGI binaries are executable
    chmod 755 /usr/lib/cgi-bin/nut/*.cgi

# Copy health check script with execute permissions for any user
COPY --chmod=0755 healthcheck.sh /healthcheck.sh

# Switch to non-root user for runtime
# Can be overridden with docker run --user <uid>:<gid>
USER nut

# Expose HTTP port
EXPOSE 80

# Health check using enhanced script
# - interval=30s: Check every 30 seconds
# - timeout=10s: Allow 10s for CGI processing
# - start-period=15s: Grace period for container initialization
# - retries=3: Require 3 consecutive failures before unhealthy
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD ["/healthcheck.sh"]

# Run lighttpd in foreground mode
CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/lighttpd.conf"]
