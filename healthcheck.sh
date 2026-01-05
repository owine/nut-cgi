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

# Tier 3: Valid CGI output (check for CGI infrastructure errors, not UPS connection errors)
# Note: UPS connection errors are expected when no UPS is configured/reachable
if echo "$response" | grep -qi "can't open template file\|internal server error\|500 error"; then
    echo "ERROR: nut-cgi infrastructure failure"
    exit 1
fi

echo "OK: nut-cgi healthy"
exit 0
