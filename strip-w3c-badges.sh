#!/bin/sh
# Strip W3C validator badges from NUT's upsstats HTML templates.
#
# NUT's stock templates hotlink two validator badges from jigsaw.w3.org and
# www.w3.org. Our Content-Security-Policy sets img-src 'self' data:, so browsers
# block them and they render as broken images. Their check/referer links are dead
# anyway: we also send Referrer-Policy: no-referrer, so the validators receive no
# referer to check.
#
# Run at build time against the templates NUT installs, rather than vendoring our
# own copies, so NUT version bumps keep delivering upstream template fixes.
#
# Each badge is an <a> whose href is a known W3C validator URL, wrapping an <img>.
# The anchor spans several lines in some templates, and in upsstats-single.html
# the closing </a> shares its line with a trailing </div>. So this excises the
# exact <a>...</a> span and preserves whatever surrounds it on the boundary lines
# -- deleting whole lines would take that </div> with it.
set -eu

if [ "$#" -eq 0 ]; then
    echo "usage: $0 <template>..." >&2
    exit 2
fi

for template in "$@"; do
    [ -f "$template" ] || { echo "strip-w3c-badges: no such file: $template" >&2; exit 1; }

    awk '
    BEGIN {
        # Literal anchor openings, identical across every upsstats template.
        badge[1] = "<a href=\"https://jigsaw.w3.org/css-validator/check/referer\">"
        badge[2] = "<a href=\"https://validator.w3.org/check?uri=referer\">"
        n = 2
        in_badge = 0
    }
    {
        line = $0
        out = ""
        while (line != "") {
            if (in_badge) {
                close_at = index(line, "</a>")
                if (close_at == 0) { line = ""; break }   # anchor continues onto the next line
                line = substr(line, close_at + 4)         # keep the tail, e.g. a trailing </div>
                in_badge = 0
                continue
            }

            # Find whichever badge anchor opens earliest on this line.
            first = 0
            for (i = 1; i <= n; i++) {
                at = index(line, badge[i])
                if (at > 0 && (first == 0 || at < first)) first = at
            }
            if (first == 0) { out = out line; break }     # no badge here; emit as-is

            out = out substr(line, 1, first - 1)          # keep text before the anchor
            line = substr(line, first)
            in_badge = 1
        }

        # Drop lines that held nothing but badge markup; keep genuinely blank ones.
        if (out != "" || (!in_badge && $0 == "")) print out
    }
    END {
        if (in_badge) {
            print "strip-w3c-badges: unterminated badge anchor" > "/dev/stderr"
            exit 1
        }
    }
    ' "$template" > "$template.stripped"

    mv "$template.stripped" "$template"

    # Fail loudly if upstream reflowed the markup and the strip silently no-opped,
    # rather than shipping broken images again.
    if grep -q 'jigsaw\.w3\.org\|valid-html401\|validator\.w3\.org' "$template"; then
        echo "strip-w3c-badges: W3C references survive in $template; upstream markup changed" >&2
        exit 1
    fi
done
