/* ═══════════════════════════════════════════
   MatugenFox Toolbar Popup — per-site and global switches
   ═══════════════════════════════════════════ */

'use strict';

const $ = id => document.getElementById(id);
let config = mergeConfig();
let site = { themeable: false, styles: [] };

function render() {
    const globalOn = config.webThemeEnabled !== false;
    $('toggle-global').checked = globalOn;
    $('global-hint').textContent = globalOn ? 'On everywhere a style exists' : 'Off on every website';

    const siteToggle = $('toggle-site');
    if (!site.themeable || !site.host) {
        $('site-host').textContent = 'This page';
        $('site-style').textContent = 'Browser pages cannot be styled';
        siteToggle.checked = false;
        siteToggle.disabled = true;
        $('site-hint').textContent = '';
        $('row-site').classList.add('is-disabled');
        return;
    }

    const siteOn = !MFMatchers.siteListed(config.disabledSites, site.host);
    $('site-host').textContent = MFMatchers.siteKey(site.host);
    $('site-host').title = site.host;
    $('site-style').textContent = site.styles.length
        ? `Catppuccin style: ${site.styles.join(', ')}`
        : 'No Catppuccin style for this site';
    siteToggle.checked = siteOn && globalOn;
    siteToggle.disabled = !globalOn;
    $('row-site').classList.toggle('is-disabled', !globalOn);
    $('site-hint').textContent = !globalOn
        ? 'Website styling is off everywhere'
        : siteOn ? 'On for every page of this site' : 'Off here until you switch it back on';
}

async function update(partialUpdate) {
    Object.assign(config, partialUpdate);
    render();
    await browser.runtime.sendMessage({ type: 'UPDATE_CONFIG', partialUpdate });
}

$('toggle-site').addEventListener('change', e => {
    // Turning a site back on also clears any parent domain that was switched off.
    const key = MFMatchers.siteKey(site.host);
    const rest = (config.disabledSites || []).filter(s => !MFMatchers.siteListed([s], key));
    update({ disabledSites: e.target.checked ? rest : [...rest, key] });
});

$('toggle-global').addEventListener('change', e => update({ webThemeEnabled: e.target.checked }));

$('open-settings').addEventListener('click', () => {
    browser.runtime.openOptionsPage();
    window.close();
});

async function init() {
    const [stored, tabs] = await Promise.all([
        browser.storage.local.get(['config', 'themeData']),
        browser.tabs.query({ active: true, currentWindow: true }),
    ]);
    config = mergeConfig(stored.config);
    if (stored.themeData?.colors) applySelfTheme(stored.themeData.colors);

    const url = tabs[0]?.url || '';
    const [state, status] = await Promise.all([
        browser.runtime.sendMessage({ type: 'GET_SITE_STATE', url }).catch(() => null),
        browser.runtime.sendMessage({ type: 'GET_STATUS' }).catch(() => null),
    ]);
    if (state) site = state;
    render();

    const statusEl = $('popup-status');
    if (!status?.connected) {
        statusEl.textContent = 'Helper not connected';
        statusEl.classList.add('is-warning');
    } else if (!state?.built) {
        statusEl.textContent = 'Styles are still being built';
        statusEl.classList.add('is-warning');
    } else {
        statusEl.textContent = `${status.userstyles?.ok ?? 0} site styles ready`;
    }
}

init();
