#!/bin/sh
# Enhanced health check for nut-cgi with three-tier validation
# Supports execution by any UID (for --user override compatibility)

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
if echo "$response" | grep -qi "error\|failed\|not found"; then
    echo "WARN: nut-cgi returned error content"
    exit 1
fi

echo "OK: nut-cgi healthy"
exit 0
