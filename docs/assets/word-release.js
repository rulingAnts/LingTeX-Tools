// LingTeX Tools site: point the LingTeX-Word links at the newest word-v* release.
//
// The links are written for the release current when a page was edited; this
// asks GitHub for the newest Word release and moves them. Anything that fails
// leaves the written links in place. Elements carry data-word="exe", "winzip",
// "maczip" (the Mac download, a .dmg since beta.6), "guide", "release",
// "version" (text) or "macext" (text: the Mac file's extension).
(function () {
    if (!window.fetch) return;
    var pick = {
        exe:    function (n) { return /^LingTeX-Word-Setup-.*\.exe$/.test(n); },
        winzip: function (n) { return /-windows\.zip$/.test(n); },
        maczip: function (n) { return /-macos\.(dmg|zip)$/.test(n); },
        guide:  function (n) { return /^LingTeX-Word-Guide-.*\.pdf$/.test(n); }
    };
    fetch('https://api.github.com/repos/rulingAnts/LingTeX-Tools/releases?per_page=30',
          { headers: { Accept: 'application/vnd.github+json' } })
        .then(function (r) { return r.ok ? r.json() : null; })
        .then(function (list) {
            if (!list || !list.length) return;
            var rel = null;
            list.forEach(function (r) {
                if (!/^word-v/.test(r.tag_name) || r.draft) return;
                if (!rel || r.published_at > rel.published_at) rel = r;
            });
            if (!rel) return;
            var short = rel.tag_name.replace(/^word-v/, '');
            document.querySelectorAll('[data-word]').forEach(function (el) {
                var k = el.getAttribute('data-word');
                if (k === 'version') { el.textContent = short; return; }
                if (k === 'release') { el.href = rel.html_url; return; }
                var f = pick[k];
                if (!f) return;
                for (var j = 0; j < rel.assets.length; j++) {
                    if (f(rel.assets[j].name)) {
                        el.href = rel.assets[j].browser_download_url;
                        if (k === 'maczip') {
                            var ext = rel.assets[j].name.replace(/^.*(\.[a-z]+)$/, '$1');
                            document.querySelectorAll('[data-word="macext"]').forEach(function (x) { x.textContent = ext; });
                        }
                        return;
                    }
                }
            });
        })
        .catch(function () {});
})();
