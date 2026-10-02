#!/bin/sh
# check-site-links.sh  --  LingTeX Tools site (docs/, served by GitHub Pages)
#
# DO THE SITE'S DOWNLOAD LINKS STILL DOWNLOAD? Read-only: it asks GitHub for
# each link (HEAD, following redirects) and changes nothing.
#
# Issue #7 (2026-09-21): both LingTeX-Word download buttons said "Not Found".
# The written links named word-v0.1.0-beta.6, whose files had been deleted
# after it was published, and docs/assets/word-release.js, which moves the
# links to the newest release at run time, chose that same empty release. The
# script now skips releases without their files, but the written links are what
# anyone gets whom it misses: no JavaScript, api.github.com blocked by a filter,
# the API's hourly limit used up on a shared network, or a click before the
# reply arrives. So they must work on their own, and this checks that they do.
#
# It takes every link into this repository's releases written in
# docs/**/*.html -- releases/download/..., releases/tag/... and
# releases/latest/download/... -- and fails any that does not end in 200.
# latest/download links are checked too: they break silently the day a release
# renames a file, which is what KNOWN below is.
#
# Usage:  sh LingTeX-Word/tools/check-site-links.sh
# Exit:   0 every link answers 200 (KNOWN failures excepted), 1 otherwise.
#         Needs curl and the network.

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
docs="$repo/docs"

# KNOWN failures: reported, not counted. Each entry needs a reason and stays
# only while its decision is open.
#   lingtex-tools-firefox.xpi (docs/latex/index.html, the Firefox button):
#   releases/latest is v0.3.3, which ships lingtex-tools-firefox.zip, not .xpi
#   (only v0.2.0 had an .xpi). Whether the page should link the .zip or the
#   release should ship an .xpi is an open product decision, so this script
#   does not pretend it passes and does not fail every run over it either.
known="
https://github.com/rulingAnts/LingTeX-Tools/releases/latest/download/lingtex-tools-firefox.xpi
"

if [ ! -d "$docs" ]; then
    echo "no docs/ at $docs"
    exit 1
fi

urls=$(find "$docs" -name '*.html' -exec grep -ohE \
        'https://github\.com/rulingAnts/LingTeX-Tools/releases/(download|tag|latest/download)/[^"'"'"' <>)]+' {} + |
       sort -u)

if [ -z "$urls" ]; then
    echo "  FAIL  no release links found under $docs (has the pattern drifted?)"
    exit 1
fi

fails=0 known_hit=0 n=0
where() {
    # file:line of each use, relative to the repository
    grep -rnF --include='*.html' "$1" "$docs" | cut -d: -f1,2 | sed "s|^$repo/||; s|^|        used at |"
}

for u in $urls; do
    n=$((n + 1))
    code=$(curl -sIL --retry 2 --max-time 60 -o /dev/null -w '%{http_code}' "$u")
    is_known=0
    case "$known" in *"
$u
"*) is_known=1 ;; esac
    if [ "$code" = "200" ]; then
        if [ $is_known = 1 ]; then
            echo "  OK    $code  $u  (listed as KNOWN: take it off the list)"
        else
            echo "  OK    $code  $u"
        fi
    elif [ $is_known = 1 ]; then
        known_hit=$((known_hit + 1))
        echo "  KNOWN $code  $u"
        where "$u"
    else
        fails=$((fails + 1))
        echo "  FAIL  $code  $u"
        where "$u"
    fi
done

echo ""
if [ $fails -eq 0 ]; then
    echo "ALL PASS -- $n release links checked, $known_hit KNOWN failure(s) reported"
    exit 0
fi
echo "PROBLEMS -- $fails of $n release links do not answer 200"
exit 1
