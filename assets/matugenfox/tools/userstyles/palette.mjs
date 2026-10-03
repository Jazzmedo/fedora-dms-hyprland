// Maps the DMS Material 3 palette onto Catppuccin's 26 colour slots.
//
// Catppuccin styles lean on the *shape* of its palette: a strictly ordered
// neutral ramp from crust to text, and a fixed set of recognisable hues. DMS
// roles don't line up with that one-to-one (containers can be flatter than the
// ramp, and dank16 is harmonised toward the accent so its "blue" is not blue),
// so slots are chosen by lightness and hue, not by role name, and computed when
// no role fits. All maths is in OKLab/OKLCH.

export const SLOTS = [
  'rosewater', 'flamingo', 'pink', 'mauve', 'red', 'maroon', 'peach', 'yellow', 'green', 'teal',
  'sky', 'sapphire', 'blue', 'lavender', 'text', 'subtext1', 'subtext0', 'overlay2', 'overlay1',
  'overlay0', 'surface2', 'surface1', 'surface0', 'base', 'mantle', 'crust',
];

export const CATPPUCCIN = {
  latte: {
    rosewater: '#dc8a78', flamingo: '#dd7878', pink: '#ea76cb', mauve: '#8839ef', red: '#d20f39',
    maroon: '#e64553', peach: '#fe640b', yellow: '#df8e1d', green: '#40a02b', teal: '#179299',
    sky: '#04a5e5', sapphire: '#209fb5', blue: '#1e66f5', lavender: '#7287fd', text: '#4c4f69',
    subtext1: '#5c5f77', subtext0: '#6c6f85', overlay2: '#7c7f93', overlay1: '#8c8fa1',
    overlay0: '#9ca0b0', surface2: '#acb0be', surface1: '#bcc0cc', surface0: '#ccd0da',
    base: '#eff1f5', mantle: '#e6e9ef', crust: '#dce0e8',
  },
  mocha: {
    rosewater: '#f5e0dc', flamingo: '#f2cdcd', pink: '#f5c2e7', mauve: '#cba6f7', red: '#f38ba8',
    maroon: '#eba0ac', peach: '#fab387', yellow: '#f9e2af', green: '#a6e3a1', teal: '#94e2d5',
    sky: '#89dceb', sapphire: '#74c7ec', blue: '#89b4fa', lavender: '#b4befe', text: '#cdd6f4',
    subtext1: '#bac2de', subtext0: '#a6adc8', overlay2: '#9399b2', overlay1: '#7f849c',
    overlay0: '#6c7086', surface2: '#585b70', surface1: '#45475a', surface0: '#313244',
    base: '#1e1e2e', mantle: '#181825', crust: '#11111b',
  },
};

// ---------------------------------------------------------------- colour maths ---

const clamp01 = v => Math.min(1, Math.max(0, v));

export function parseHex(hex) {
  const m = /^#?([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(String(hex).trim());
  if (!m) throw new Error(`not a hex colour: ${hex}`);
  const n = parseInt(m[1], 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255].map(v => v / 255);
}

const toLinear = c => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const fromLinear = c => (c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055);

export function toOklab(hex) {
  const [r, g, b] = parseHex(hex).map(toLinear);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
}

function oklabToLinear([L, a, b]) {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
}

const inGamut = rgb => rgb.every(v => v >= -1e-4 && v <= 1 + 1e-4);
const linearToHex = rgb =>
  '#' + rgb.map(v => Math.round(clamp01(fromLinear(clamp01(v))) * 255).toString(16).padStart(2, '0')).join('');

// Gamut-maps by lowering chroma, which keeps lightness and hue intact.
export function oklchToHex(L, C, H) {
  const l = clamp01(L);
  const h = (H * Math.PI) / 180;
  let c = Math.max(0, C);
  for (let i = 0; i < 60; i++) {
    const rgb = oklabToLinear([l, c * Math.cos(h), c * Math.sin(h)]);
    if (inGamut(rgb)) return linearToHex(rgb);
    c *= 0.92;
  }
  return linearToHex(oklabToLinear([l, 0, 0]));
}

export function toOklch(hex) {
  const [L, a, b] = toOklab(hex);
  let H = (Math.atan2(b, a) * 180) / Math.PI;
  if (H < 0) H += 360;
  return [L, Math.hypot(a, b), H];
}

export const lightness = hex => toOklab(hex)[0];

export function setLightness(hex, L) {
  const [, C, H] = toOklch(hex);
  return oklchToHex(L, C, H);
}

export function mix(a, b, t) {
  const A = toOklab(a);
  const B = toOklab(b);
  const lab = A.map((v, i) => v + (B[i] - v) * t);
  const rgb = oklabToLinear(lab);
  if (inGamut(rgb)) return linearToHex(rgb);
  return oklchToHex(lab[0], Math.hypot(lab[1], lab[2]), (Math.atan2(lab[2], lab[1]) * 180) / Math.PI);
}

function luminance(hex) {
  const [r, g, b] = parseHex(hex).map(toLinear);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrast(a, b) {
  const x = luminance(a);
  const y = luminance(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
}

export function hueDistance(a, b) {
  const d = Math.abs(a - b) % 360;
  return d > 180 ? 360 - d : d;
}

export function deltaE(a, b) {
  const A = toOklab(a);
  const B = toOklab(b);
  return Math.hypot(A[0] - B[0], A[1] - B[1], A[2] - B[2]);
}

// Moves fg's lightness away from bg until the WCAG contrast ratio is met.
export function ensureContrast(fg, bg, min) {
  if (contrast(fg, bg) >= min) return fg;
  const [L, C, H] = toOklch(fg);
  const dir = lightness(bg) < 0.5 ? 1 : -1;
  for (let step = 1; step <= 100; step++) {
    const candidate = oklchToHex(L + dir * step * 0.01, C, H);
    if (contrast(candidate, bg) >= min) return candidate;
  }
  return dir > 0 ? '#ffffff' : '#000000';
}

// ------------------------------------------------------------------- mapping ---

// Where each neutral sits between base (0) and text (1) in Catppuccin's ramps.
const RAMP = {
  surface0: 0.13, surface1: 0.25, surface2: 0.37, overlay0: 0.48,
  overlay1: 0.59, overlay2: 0.7, subtext0: 0.8, subtext1: 0.9,
};
// DMS roles a neutral may adopt when their lightness is close to its ramp position.
const SNAP = {
  surface0: 'surface_container_high', surface1: 'surface_container_highest',
  surface2: 'surface_bright', overlay1: 'outline', subtext1: 'on_surface_variant',
};
const NEUTRAL_ORDER = ['base', 'surface0', 'surface1', 'surface2', 'overlay0', 'overlay1', 'overlay2', 'subtext0', 'subtext1', 'text'];
const DARKER_ROLES = ['surface_container_low', 'surface_container', 'surface_dim', 'surface_container_lowest'];
const SNAP_TOLERANCE = 0.035;
const MIN_STEP = 0.012;
const ACCENT_CONTRAST = 3;
const HUE_WINDOW = 35;
const HARMONY_SHARE = 0.15;
const HARMONY_CAP = 12;

const pick = (m3, role) => {
  const v = m3?.[role];
  return typeof v === 'string' && /^#[0-9a-f]{6}$/i.test(v) ? v.toLowerCase() : null;
};

export function buildSlots(m3, dank16, mode) {
  const ref = CATPPUCCIN[mode === 'light' ? 'latte' : 'mocha'];
  const out = {};

  // Neutrals.
  out.base = pick(m3, 'surface') ?? pick(m3, 'background') ?? ref.base;
  out.text = ensureContrast(pick(m3, 'on_surface') ?? pick(m3, 'on_background') ?? ref.text, out.base, 7);
  const Lb = lightness(out.base);
  const dir = Math.sign(lightness(out.text) - Lb) || 1;

  const within = (role, lo, hi) => {
    const v = pick(m3, role);
    return v && lightness(v) >= lo && lightness(v) <= hi ? v : null;
  };
  // Mantle and crust are darker than base in both Catppuccin flavours.
  out.mantle = DARKER_ROLES.map(r => within(r, Lb - 0.045, Lb - 0.012)).find(Boolean) ?? setLightness(out.base, Lb - 0.027);
  const Lm = lightness(out.mantle);
  out.crust = DARKER_ROLES.map(r => within(r, Lm - 0.06, Lm - 0.02)).find(Boolean) ?? setLightness(out.mantle, Lm - 0.033);

  for (const [slot, t] of Object.entries(RAMP)) {
    const target = mix(out.base, out.text, t);
    const snapped = SNAP[slot] && pick(m3, SNAP[slot]);
    out[slot] = snapped && Math.abs(lightness(snapped) - lightness(target)) <= SNAP_TOLERANCE ? snapped : target;
  }
  // The ramp must stay strictly ordered from base to text; a snapped role that
  // breaks the order gives way to its computed position.
  for (let i = 1; i < NEUTRAL_ORDER.length - 1; i++) {
    const slot = NEUTRAL_ORDER[i];
    const prev = lightness(out[NEUTRAL_ORDER[i - 1]]);
    if ((lightness(out[slot]) - prev) * dir >= MIN_STEP) continue;
    let candidate = mix(out.base, out.text, RAMP[slot]);
    if ((lightness(candidate) - prev) * dir < MIN_STEP) candidate = setLightness(candidate, prev + dir * MIN_STEP);
    out[slot] = candidate;
  }
  out.subtext0 = ensureContrast(out.subtext0, out.base, 4.5);
  out.subtext1 = ensureContrast(out.subtext1, out.base, 5.5);

  // Accents from Material roles.
  out.mauve = ensureContrast(pick(m3, 'primary') ?? ref.mauve, out.base, ACCENT_CONTRAST);
  const secondary = pick(m3, 'secondary');
  out.lavender = secondary && contrast(secondary, out.base) >= ACCENT_CONTRAST
    ? secondary
    : ensureContrast(mix(out.mauve, out.text, 0.3), out.base, ACCENT_CONTRAST);

  // Hue slots: computed at Catppuccin's hue with the lightness and chroma of
  // DMS's own semantic tones, nudged a little toward the accent.
  const tones = ['color1', 'color2', 'color3'].map(k => dank16?.[k]).filter(v => typeof v === 'string').map(toOklch);
  const meanL = tones.length ? tones.reduce((s, t) => s + t[0], 0) / tones.length : lightness(ref.green);
  const meanC = tones.length ? tones.reduce((s, t) => s + t[1], 0) / tones.length : 0.1;
  const accentHue = toOklch(out.mauve)[2];
  const computeHue = slot => {
    const [, refC, refH] = toOklch(ref[slot]);
    const signed = ((accentHue - refH + 540) % 360) - 180;
    const shift = Math.max(-HARMONY_CAP, Math.min(HARMONY_CAP, signed * HARMONY_SHARE));
    return ensureContrast(oklchToHex(meanL, Math.min(refC, Math.max(0.07, meanC)), refH + shift), out.base, ACCENT_CONTRAST);
  };
  const fromDank = (slot, key) => {
    const hex = typeof dank16?.[key] === 'string' ? dank16[key] : null;
    if (hex) {
      const [, C, H] = toOklch(hex);
      if (C > 0.03 && hueDistance(H, toOklch(ref[slot])[2]) <= HUE_WINDOW) return ensureContrast(hex.toLowerCase(), out.base, ACCENT_CONTRAST);
    }
    return computeHue(slot);
  };
  const error = pick(m3, 'error');
  const [, errorC, errorH] = error ? toOklch(error) : [0, 0, 0];
  out.red = error && errorC > 0.03 && hueDistance(errorH, toOklch(ref.red)[2]) <= HUE_WINDOW
    ? ensureContrast(error, out.base, ACCENT_CONTRAST)
    : computeHue('red');
  out.green = fromDank('green', 'color2');
  out.yellow = fromDank('yellow', 'color3');
  out.maroon = fromDank('maroon', 'color9');
  out.teal = fromDank('teal', 'color6');
  out.blue = fromDank('blue', 'color4');
  for (const slot of ['peach', 'sky', 'sapphire']) out[slot] = computeHue(slot);

  const tertiary = pick(m3, 'tertiary');
  out.pink = tertiary && contrast(tertiary, out.base) >= ACCENT_CONTRAST && deltaE(tertiary, out.lavender) >= 0.05
    ? tertiary
    : computeHue('pink');
  out.flamingo = mix(out.pink, out.text, 0.35);
  out.rosewater = mix(out.mauve, out.text, 0.55);

  return Object.fromEntries(SLOTS.map(slot => [slot, out[slot].toLowerCase()]));
}
