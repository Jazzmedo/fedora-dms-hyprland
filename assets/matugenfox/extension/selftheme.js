/* ═══════════════════════════════════════════
   MatugenFox Self-Theming — options page and popup
   ═══════════════════════════════════════════ */

'use strict';

// ─── Self-Theming ───
const THEME_MAP = {
    '--primary': '--mg-accent',
    '--on_primary': '--mg-on-accent',
    '--background': '--mg-bg-0',
    '--surface': '--mg-bg-1',
    '--surface_container': '--mg-bg-2',
    '--surface_container_high': '--mg-bg-3',
    '--on_surface': '--mg-text-0',
    '--on_surface_variant': '--mg-text-1',
    '--outline': '--mg-border',
    '--outline_variant': '--mg-border',
    '--error': '--mg-error',
    '--secondary': '--mg-accent',
};

function applySelfTheme(colors) {
    if (!colors) return;
    const root = document.documentElement;
    let accentSet = false;
    for (const [src, target] of Object.entries(THEME_MAP)) {
        if (colors[src]) {
            root.style.setProperty(target, colors[src]);
            if (target === '--mg-accent') accentSet = true;
        }
    }
    if (!accentSet) {
        for (const [key, value] of Object.entries(colors)) {
            if (key.includes('primary') && !key.includes('on') && !key.includes('container') && !key.includes('inverse')) {
                root.style.setProperty('--mg-accent', value);
                break;
            }
        }
    }
    const accent = root.style.getPropertyValue('--mg-accent');
    if (accent && accent.startsWith('#')) {
        let c = accent.replace('#', '');
        if (c.length === 3) c = c.split('').map(x => x + x).join('');
        const rgb = parseInt(c.slice(0, 2), 16) + ',' + parseInt(c.slice(2, 4), 16) + ',' + parseInt(c.slice(4, 6), 16);
        root.style.setProperty('--mg-accent-dim', `rgba(${rgb}, 0.15)`);
        root.style.setProperty('--mg-accent-glow', `rgba(${rgb}, 0.4)`);
    }
}
