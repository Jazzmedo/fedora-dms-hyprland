/* ═══════════════════════════════════════════
   MatugenFox Userstyle Matchers
   ═══════════════════════════════════════════ */

// Evaluates the @-moz-document matchers of compiled userstyle blocks. Injected
// CSS can't carry them, so the extension decides which blocks a URL gets.
//
// Semantics follow Firefox: domain() matches the host or any subdomain,
// url-prefix() and url() compare the whole URL, and regexp() must match the
// entire URL.

'use strict';

(function (root) {
    const THEMEABLE = new Set(['http:', 'https:', 'file:', 'ftp:']);
    const compiled = new WeakMap();

    function compileMatcher(matcher) {
        const cached = compiled.get(matcher);
        if (cached) return cached;
        const value = String(matcher.v ?? '');
        let test;
        switch (matcher.t) {
            case 'domain': {
                const domain = value.toLowerCase();
                test = url => url.hostname === domain || url.hostname.endsWith('.' + domain);
                break;
            }
            case 'url-prefix':
                test = url => url.href.startsWith(value);
                break;
            case 'url':
                test = url => url.href === value;
                break;
            case 'regexp': {
                let re = null;
                try { re = new RegExp('^(?:' + value + ')$'); } catch { /* never matches */ }
                test = url => !!re && re.test(url.href);
                break;
            }
            default:
                test = () => false;
        }
        compiled.set(matcher, test);
        return test;
    }

    function parseUrl(href) {
        try {
            const url = new URL(href);
            return THEMEABLE.has(url.protocol) ? url : null;
        } catch {
            return null;
        }
    }

    function blockMatches(block, href) {
        const url = parseUrl(href);
        return !!url && (block.matchers || []).some(m => compileMatcher(m)(url));
    }

    // Hashes of every block that applies to href, in style then block order.
    function matchBlocks(index, href) {
        const url = parseUrl(href);
        if (!url || !index || !Array.isArray(index.styles)) return [];
        const hashes = [];
        const seen = new Set();
        for (const style of index.styles) {
            for (const block of style.blocks || []) {
                if (seen.has(block.hash)) continue;
                if ((block.matchers || []).some(m => compileMatcher(m)(url))) {
                    seen.add(block.hash);
                    hashes.push(block.hash);
                }
            }
        }
        return hashes;
    }

    // A list of sites typed by the user, one per line: a hostname
    // ("search.example.com") matches it and its subdomains; a URL with a path
    // ("https://example.com/searx/") matches only under that path. Blank
    // lines and lines starting with # are ignored, as is anything unparseable.
    function parseSiteList(text) {
        const out = [];
        const seen = new Set();
        for (const raw of String(text || '').split(/\r?\n/)) {
            const line = raw.trim();
            if (!line || line.startsWith('#')) continue;
            let matcher;
            try {
                const url = new URL(/^[a-z][a-z0-9+.-]*:\/\//i.test(line) ? line : `https://${line}`);
                if (!url.hostname || /\s/.test(line)) continue;
                const path = url.pathname.replace(/\/+$/, '');
                matcher = path
                    ? { t: 'url-prefix', v: `${url.protocol}//${url.host}${path}` }
                    : { t: 'domain', v: url.hostname.toLowerCase() };
            } catch {
                continue;
            }
            const key = `${matcher.t} ${matcher.v}`;
            if (!seen.has(key)) {
                seen.add(key);
                out.push(matcher);
            }
        }
        return out;
    }

    // A site as the user thinks of it: the hostname without a leading "www.".
    function siteKey(host) {
        return String(host || '').toLowerCase().replace(/^www\./, '');
    }

    // Whether a hostname is covered by a list of site keys, subdomains included.
    function siteListed(list, host) {
        const key = siteKey(host);
        return !!key && (list || []).some(s => key === s || key.endsWith(`.${s}`));
    }

    const api = { compileMatcher, blockMatches, matchBlocks, parseSiteList, siteKey, siteListed };
    root.MFMatchers = api;
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
