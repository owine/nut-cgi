#!/bin/sh
set -e

LIGHTTPD_CONF="/etc/lighttpd/lighttpd.conf"

# If ENABLE_UPSSET is set, remove the upsset.cgi deny rule
# Writes modified config to /tmp (read-only filesystem compatible)
if [ "${ENABLE_UPSSET}" = "true" ]; then
    LIGHTTPD_CONF="/tmp/lighttpd.conf"
    # shellcheck disable=SC2016
    sed -e '/$HTTP\["url"\] =~ "^\/upsset\\.cgi"/d' \
        -e 's|^include "mod_|include "/etc/lighttpd/mod_|' \
        /etc/lighttpd/lighttpd.conf > "${LIGHTTPD_CONF}"
fi

# exec replaces this shell with lighttpd (PID 1 for proper signal handling)
exec lighttpd -D -f "${LIGHTTPD_CONF}"
