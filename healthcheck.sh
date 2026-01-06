#!/bin/sh
# Enhanced health check for nut-cgi with multi-tier validation
# Supports execution by any UID (for --user override compatibility)
#
# Health check modes (set via HEALTHCHECK_MODE environment variable):
#   basic  - Validate infrastructure only (web server + CGI execution) [default]
#   strict - Validate infrastructure + UPS connectivity

# Get health check mode from environment, default to 'basic'
MODE="${HEALTHCHECK_MODE:-basic}"

# Tier 1: Web server responding with valid HTTP status
if ! curl -f -s -o /dev/null http://localhost/upsstats.cgi; then
    echo "ERROR: lighttpd not responding (HTTP error)"
    exit 1
fi

# Tier 2: CGI execution working (non-empty response)
response=$(curl -s http://localhost/upsstats.cgi)
if [ -z "$response" ]; then
    echo "ERROR: nut-cgi not executing (empty response)"
    exit 1
fi

# Tier 3: Valid CGI infrastructure (no template/server errors)
if echo "$response" | grep -qi "can't open template file\|internal server error\|500 error"; then
    echo "ERROR: nut-cgi infrastructure failure"
    exit 1
fi

# Tier 4: HTTP headers validation (verify CGI output, not cached error)
headers=$(curl -s -I http://localhost/upsstats.cgi)
if ! echo "$headers" | grep -qi "Content-Type"; then
    echo "ERROR: Invalid HTTP response headers"
    exit 1
fi

# Tier 5 (strict mode only): UPS connectivity validation
if [ "$MODE" = "strict" ]; then
    # Check for UPS connection errors in response
    if echo "$response" | grep -qi "no UPS found\|data stale\|connection refused\|can't connect to UPS"; then
        echo "ERROR: No reachable UPS systems found (strict mode)"
        exit 1
    fi

    # Verify response contains actual UPS data (not just error page)
    if ! echo "$response" | grep -qi "UPS\|status"; then
        echo "ERROR: Response lacks UPS data (strict mode)"
        exit 1
    fi

    echo "OK: nut-cgi healthy (strict mode - UPS connectivity verified)"
else
    echo "OK: nut-cgi healthy (basic mode - infrastructure validated)"
fi

exit 0
