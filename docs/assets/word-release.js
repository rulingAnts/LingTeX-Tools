// LingTeX Tools site: point the LingTeX-Word links at the newest word-v* release
// that has its files.
//
// The links are written for the release current when a page was edited; this
// asks GitHub for the newest Word release that has its files and moves them.
// Anything that fails leaves the written links in place. Elements carry
// data-word="exe", "winzip", "maczip" (the Mac download, a .dmg since beta.6),
// "guide", "release", "version" (text) or "macext" (text: the Mac file's
// extension).
//
// Newest by date is not enough (#7, 2026-09-21): a release can exist with no
// files. beta.6's were deleted after it was published (beta.1 and beta.2 are
// empty too), and while beta.6 was the newest word-v release this script chose
// it, found nothing to point at, and left every link on beta.6's deleted files:
// "Not Found" for every download. So a release counts only when it carries all
// three downloads (Windows installer, Windows zip, Mac file), empty or partial
// ones are skipped for the next older one, and that one release supplies every
// link and the version text, so the page never names one version and downloads
// another. A key the chosen release lacks (the guide, say) keeps its written link.
//
// wordLinks() is that choice alone, without the page, so
// LingTeX-Word/tools/word-release.test.mjs can run it in node.
(function () {
    var pick = {
        exe:    function (n) { return /^LingTeX-Word-Setup-.*\.exe$/.test(n); },
        winzip: function (n) { return /-windows\.zip$/.test(n); },
        maczip: function (n) { return /-macos\.(dmg|zip)$/.test(n); },
        guide:  function (n) { return /^LingTeX-Word-Guide-.*\.pdf$/.test(n); }
    };
    // A release is chosen only with all of these; the guide is used when present.
    var needed = ['exe', 'winzip', 'maczip'];

    // Only links into this repository's releases are written into the page.
    function releaseUrl(u) {
        return typeof u === 'string' &&
               u.indexOf('https://github.com/rulingAnts/LingTeX-Tools/releases/') === 0;
    }

    // One release -> { data-word key: href or text }, or null when it lacks a
    // needed download.
    function linksOf(rel) {
        if (!releaseUrl(rel.html_url)) return null;
        var links = { version: rel.tag_name.replace(/^word-v/, ''), release: rel.html_url };
        Object.keys(pick).forEach(function (k) {
            for (var j = 0; j < rel.assets.length; j++) {
                var a = rel.assets[j];
                if (a && typeof a.name === 'string' && pick[k](a.name) &&
                    releaseUrl(a.browser_download_url)) {
                    links[k] = a.browser_download_url;
                    if (k === 'maczip') links.macext = a.name.replace(/^.*(\.[a-z]+)$/, '$1');
                    return;
                }
            }
        });
        for (var i = 0; i < needed.length; i++) {
            if (!links[needed[i]]) return null;
        }
        return links;
    }

    // The API's release list -> the links of the newest non-draft word-v release
    // that has its files, or null (then nothing on the page changes).
    function wordLinks(list) {
        if (!Array.isArray(list)) return null;
        var rels = list.filter(function (r) {
            return r && !r.draft && typeof r.tag_name === 'string' && /^word-v/.test(r.tag_name) &&
                   typeof r.published_at === 'string' && Array.isArray(r.assets);
        });
        // Newest first. The API's own order is not by date (on 2026-10-02 it
        // listed beta.9, beta.8, beta.10, beta.7).
        rels.sort(function (a, b) {
            return a.published_at < b.published_at ? 1 : a.published_at > b.published_at ? -1 : 0;
        });
        for (var i = 0; i < rels.length; i++) {
            var links = linksOf(rels[i]);
            if (links) return links;
        }
        return null;
    }

    if (typeof module === 'object' && module && module.exports) {
        module.exports = { wordLinks: wordLinks };
    }
    if (typeof window === 'undefined' || !window.fetch) return;
    // per_page=30 holds every release (13 on 2026-10-02, word-v and the LaTeX
    // tools' v* together). Raise it (the API allows 100) before the repository
    // nears 30, or the newest Word release can fall off this one page.
    fetch('https://api.github.com/repos/rulingAnts/LingTeX-Tools/releases?per_page=30',
          { headers: { Accept: 'application/vnd.github+json' } })
        .then(function (r) { return r.ok ? r.json() : null; })
        .then(function (list) {
            var links = wordLinks(list);
            if (!links) return;
            document.querySelectorAll('[data-word]').forEach(function (el) {
                var k = el.getAttribute('data-word');
                if (!Object.prototype.hasOwnProperty.call(links, k)) return;
                if (k === 'version' || k === 'macext') el.textContent = links[k];
                else el.href = links[k];
            });
        })
        .catch(function () {});
})();
