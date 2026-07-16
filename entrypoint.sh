#!/bin/sh
set -eu

SRC_CONF="/etc/lighttpd/lighttpd.conf"
LIGHTTPD_CONF="${SRC_CONF}"

CSP_MARKER='setenv.add-response-header += ( "Content-Security-Policy"'

# Any override means we serve a rewritten config from /tmp, since the root
# filesystem is read-only in the recommended deployment.
if [ "${ENABLE_UPSSET:-}" = "true" ] || [ -n "${CSP_POLICY:-}" ]; then
    LIGHTTPD_CONF="/tmp/lighttpd.conf"

    # lighttpd resolves relative includes against the config file's own directory.
    # The rewritten config lives in /tmp, which has no mod_*.conf, so the include
    # paths must be absolutised for every override -- not just ENABLE_UPSSET.
    sed 's|^include "mod_|include "/etc/lighttpd/mod_|' "${SRC_CONF}" > "${LIGHTTPD_CONF}"

    if [ "${ENABLE_UPSSET:-}" = "true" ]; then
        # shellcheck disable=SC2016
        sed -i '/$HTTP\["url"\] =~ "^\/upsset\\.cgi"/d' "${LIGHTTPD_CONF}"
    fi

    # Both CSP paths below key off the directive the Dockerfile emits. If that line
    # ever changes shape, they would match nothing and fail silently -- leaving the
    # default policy in place while reporting success, which is the opposite of what
    # the operator asked for. Fail loudly instead.
    if [ -n "${CSP_POLICY:-}" ] && ! grep -qF "${CSP_MARKER}" "${LIGHTTPD_CONF}"; then
        echo "entrypoint: CSP directive not found in lighttpd.conf; CSP_POLICY cannot be applied" >&2
        echo "entrypoint: the Dockerfile's Content-Security-Policy line and CSP_MARKER have diverged" >&2
        exit 1
    fi

    case "${CSP_POLICY:-}" in
        "")
            # Unset: keep the strict policy baked in at build time.
            ;;
        none)
            # Send no CSP header at all, e.g. to let a reverse proxy own the policy.
            sed -i "\|^${CSP_MARKER}|d" "${LIGHTTPD_CONF}"
            ;;
        *)
            # The value is interpolated into a quoted lighttpd string, so a double
            # quote or newline would let it inject arbitrary config directives.
            case "${CSP_POLICY}" in
                *'"'*)
                    echo "entrypoint: CSP_POLICY must not contain double quotes" >&2
                    exit 1
                    ;;
            esac
            if [ "$(printf '%s' "${CSP_POLICY}" | wc -l)" -ne 0 ]; then
                echo "entrypoint: CSP_POLICY must not contain newlines" >&2
                exit 1
            fi

            # Read the policy via ENVIRON rather than sed's replacement text: sed
            # would reinterpret & and \ in the value, awk's ENVIRON does not.
            awk -v marker="${CSP_MARKER}" '
                index($0, marker) == 1 {
                    printf "setenv.add-response-header += ( \"Content-Security-Policy\" => \"%s\" )\n", ENVIRON["CSP_POLICY"]
                    next
                }
                { print }
            ' "${LIGHTTPD_CONF}" > "${LIGHTTPD_CONF}.new"
            mv "${LIGHTTPD_CONF}.new" "${LIGHTTPD_CONF}"
            ;;
    esac
fi

# exec replaces this shell with lighttpd (PID 1 for proper signal handling)
exec lighttpd -D -f "${LIGHTTPD_CONF}"
