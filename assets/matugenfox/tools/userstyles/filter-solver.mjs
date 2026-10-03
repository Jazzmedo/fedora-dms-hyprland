// Finds a CSS filter chain that paints a black element in a target colour.
//
// Catppuccin recolours icons and logos with precomputed filter strings, one per
// palette slot, so custom palettes need their own. This is a port of the widely
// used SPSA "hex to CSS filter" solver, with the random source replaced by a
// PRNG seeded from the colour so the same hex always yields the same string.

class Color {
  constructor(r, g, b) { this.set(r, g, b); }

  set(r, g, b) {
    this.r = clamp(r);
    this.g = clamp(g);
    this.b = clamp(b);
  }

  hueRotate(angle = 0) {
    const rad = (angle / 180) * Math.PI;
    const sin = Math.sin(rad);
    const cos = Math.cos(rad);
    this.multiply([
      0.213 + cos * 0.787 - sin * 0.213, 0.715 - cos * 0.715 - sin * 0.715, 0.072 - cos * 0.072 + sin * 0.928,
      0.213 - cos * 0.213 + sin * 0.143, 0.715 + cos * 0.285 + sin * 0.14, 0.072 - cos * 0.072 - sin * 0.283,
      0.213 - cos * 0.213 - sin * 0.787, 0.715 - cos * 0.715 + sin * 0.715, 0.072 + cos * 0.928 + sin * 0.072,
    ]);
  }

  sepia(value = 1) {
    this.multiply([
      0.393 + 0.607 * (1 - value), 0.769 - 0.769 * (1 - value), 0.189 - 0.189 * (1 - value),
      0.349 - 0.349 * (1 - value), 0.686 + 0.314 * (1 - value), 0.168 - 0.168 * (1 - value),
      0.272 - 0.272 * (1 - value), 0.534 - 0.534 * (1 - value), 0.131 + 0.869 * (1 - value),
    ]);
  }

  saturate(value = 1) {
    this.multiply([
      0.213 + 0.787 * value, 0.715 - 0.715 * value, 0.072 - 0.072 * value,
      0.213 - 0.213 * value, 0.715 + 0.285 * value, 0.072 - 0.072 * value,
      0.213 - 0.213 * value, 0.715 - 0.715 * value, 0.072 + 0.928 * value,
    ]);
  }

  multiply(m) {
    const r = clamp(this.r * m[0] + this.g * m[1] + this.b * m[2]);
    const g = clamp(this.r * m[3] + this.g * m[4] + this.b * m[5]);
    const b = clamp(this.r * m[6] + this.g * m[7] + this.b * m[8]);
    this.r = r;
    this.g = g;
    this.b = b;
  }

  brightness(value = 1) { this.linear(value); }
  contrast(value = 1) { this.linear(value, -(0.5 * value) + 0.5); }

  linear(slope = 1, intercept = 0) {
    this.r = clamp(this.r * slope + intercept * 255);
    this.g = clamp(this.g * slope + intercept * 255);
    this.b = clamp(this.b * slope + intercept * 255);
  }

  invert(value = 1) {
    this.r = clamp((value + (this.r / 255) * (1 - 2 * value)) * 255);
    this.g = clamp((value + (this.g / 255) * (1 - 2 * value)) * 255);
    this.b = clamp((value + (this.b / 255) * (1 - 2 * value)) * 255);
  }

  hsl() {
    const r = this.r / 255;
    const g = this.g / 255;
    const b = this.b / 255;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    let h = 0;
    let s = 0;
    const l = (max + min) / 2;
    if (max !== min) {
      const d = max - min;
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
      if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
      else if (max === g) h = (b - r) / d + 2;
      else h = (r - g) / d + 4;
      h /= 6;
    }
    return { h: h * 100, s: s * 100, l: l * 100 };
  }
}

function clamp(value) {
  return value > 255 ? 255 : value < 0 ? 0 : value;
}

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

class Solver {
  constructor(target, random) {
    this.target = target;
    this.targetHSL = target.hsl();
    this.reusedColor = new Color(0, 0, 0);
    this.random = random;
  }

  solve() {
    const result = this.solveNarrow(this.solveWide());
    return { values: result.values, loss: result.loss };
  }

  solveWide() {
    const A = 5;
    const c = 15;
    const a = [60, 180, 18000, 600, 1.2, 1.2];
    let best = { loss: Infinity };
    for (let i = 0; best.loss > 25 && i < 3; i++) {
      const initial = [50, 20, 3750, 50, 100, 100];
      const result = this.spsa(A, a, c, initial, 1000);
      if (result.loss < best.loss) best = result;
    }
    return best;
  }

  solveNarrow(wide) {
    const A = wide.loss;
    const c = 2;
    const A1 = A + 1;
    const a = [0.25 * A1, 0.25 * A1, A1, 0.25 * A1, 0.2 * A1, 0.2 * A1];
    return this.spsa(A, a, c, wide.values, 500);
  }

  spsa(A, a, c, values, iters) {
    const alpha = 1;
    const gamma = 0.16666666666666666;
    let best = null;
    let bestLoss = Infinity;
    const deltas = new Array(6);
    const highArgs = new Array(6);
    const lowArgs = new Array(6);

    for (let k = 0; k < iters; k++) {
      const ck = c / Math.pow(k + 1, gamma);
      for (let i = 0; i < 6; i++) {
        deltas[i] = this.random() > 0.5 ? 1 : -1;
        highArgs[i] = values[i] + ck * deltas[i];
        lowArgs[i] = values[i] - ck * deltas[i];
      }
      const lossDiff = this.loss(highArgs) - this.loss(lowArgs);
      for (let i = 0; i < 6; i++) {
        const g = (lossDiff / (2 * ck)) * deltas[i];
        const ak = a[i] / Math.pow(A + k + 1, alpha);
        values[i] = fix(values[i] - ak * g, i);
      }
      const loss = this.loss(values);
      if (loss < bestLoss) {
        best = values.slice(0);
        bestLoss = loss;
      }
    }
    return { values: best, loss: bestLoss };

    function fix(value, idx) {
      let max = 100;
      if (idx === 2) max = 7500;
      else if (idx === 4 || idx === 5) max = 200;
      if (idx === 3) {
        if (value > max) value %= max;
        else if (value < 0) value = max + (value % max);
      } else if (value < 0) value = 0;
      else if (value > max) value = max;
      return value;
    }
  }

  loss(filters) {
    const color = this.reusedColor;
    color.set(0, 0, 0);
    color.invert(filters[0] / 100);
    color.sepia(filters[1] / 100);
    color.saturate(filters[2] / 100);
    color.hueRotate(filters[3] * 3.6);
    color.brightness(filters[4] / 100);
    color.contrast(filters[5] / 100);
    const hsl = color.hsl();
    return (
      Math.abs(color.r - this.target.r) + Math.abs(color.g - this.target.g) + Math.abs(color.b - this.target.b) +
      Math.abs(hsl.h - this.targetHSL.h) + Math.abs(hsl.s - this.targetHSL.s) + Math.abs(hsl.l - this.targetHSL.l)
    );
  }
}

const GOOD_ENOUGH = 1;
const MAX_ATTEMPTS = 8;

export function solveFilter(hex) {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex).trim());
  if (!m) throw new Error(`not a hex colour: ${hex}`);
  const n = parseInt(m[1], 16);
  const target = new Color((n >> 16) & 255, (n >> 8) & 255, n & 255);
  const random = mulberry32(n ^ 0x9e3779b9);

  let best = null;
  for (let attempt = 0; attempt < MAX_ATTEMPTS && !(best && best.loss < GOOD_ENOUGH); attempt++) {
    const result = new Solver(target, random).solve();
    if (!best || result.loss < best.loss) best = result;
  }
  const v = best.values;
  const fmt = (idx, multiplier = 1) => Math.round(v[idx] * multiplier);
  const filter = `brightness(0) saturate(100%) invert(${fmt(0)}%) sepia(${fmt(1)}%) saturate(${fmt(2)}%) ` +
    `hue-rotate(${fmt(3, 3.6)}deg) brightness(${fmt(4)}%) contrast(${fmt(5)}%)`;
  return { filter, loss: best.loss };
}
