#!/usr/bin/env node
// Compiles every Catppuccin userstyle with the current DMS palette and publishes
// the per-site CSS blocks MatugenFox injects into matching pages.
//
//   node build.mjs [--force] [--only youtube,github] [--jobs 6] [--mode dark|light]
//
// Output: <out>/gen-<hash>-<time>/{index.json,blocks/<sha256>.css}, with
// <out>/current pointing at the newest generation. The pointer is swapped
// atomically, so the native host never reads a half-written generation.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { Worker } from 'node:worker_threads';
import { fileURLToPath } from 'node:url';

import { SLOTS, buildSlots } from './palette.mjs';
import { solveFilter } from './filter-solver.mjs';
import { splitCompiled } from './split.mjs';

const BUILDER_VERSION = 1;
const KEEP_GENERATIONS = 3;
const PRIORITY = ['youtube', 'github', 'twitter'];
const HERE = path.dirname(fileURLToPath(import.meta.url));
const HOME = os.homedir();

const HEADER = /\/\*\s*==UserStyle==[\s\S]*?==\/UserStyle==\s*\*\//;
const STD_IMPORT = /@import\s+(?:url\(\s*)?["']https:\/\/userstyles\.catppuccin\.com\/lib\/std\/v1\.less["']\s*\)?\s*;/;

const sha256 = text => createHash('sha256').update(text).digest('hex');
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const log = msg => console.log(`[${new Date().toISOString()}] ${msg}`);

function writeFileAtomic(file, content) {
  const tmp = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, content);
  fs.renameSync(tmp, file);
}

function parseArgs(argv) {
  const args = {
    force: false,
    only: null,
    mode: null,
    jobs: Math.max(1, Math.min(6, os.cpus().length - 1)),
    out: path.join(HOME, '.cache/matugenfox/userstyles'),
    bundle: path.join(HOME, '.cache/matugenfox/catppuccin'),
    dms: path.join(HOME, '.cache/DankMaterialShell/dms-colors.json'),
    stamp: path.join(HOME, '.cache/matugenfox/palette.json'),
    session: path.join(HOME, '.local/state/DankMaterialShell/session.json'),
    vars: path.join(HOME, '.config/matugenfox/userstyle-vars.json'),
  };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    const value = () => {
      if (i + 1 >= argv.length) throw new Error(`${flag} needs a value`);
      return argv[++i];
    };
    switch (flag) {
      case '--force': args.force = true; break;
      case '--only': args.only = new Set(value().split(',').filter(Boolean)); break;
      case '--jobs': args.jobs = Math.max(1, Number(value()) || 1); break;
      case '--mode': args.mode = value(); break;
      case '--out': args.out = value(); break;
      case '--bundle': args.bundle = value(); break;
      case '--dms': args.dms = value(); break;
      case '--stamp': args.stamp = value(); break;
      default: throw new Error(`unknown argument: ${flag}`);
    }
  }
  return args;
}

// DMS writes dms-colors.json a moment after matugen triggers this build. Wait
// until it agrees with the palette matugen rendered and has stopped changing.
async function loadDmsColors(args) {
  let stamp = null;
  try { stamp = readJson(args.stamp); } catch { /* first run, or triggered by hand */ }
  const want = stamp?.primary?.toLowerCase();
  const deadline = Date.now() + 5000;
  let lastMtime = -1;
  let stableSince = Date.now();

  for (;;) {
    let data = null;
    let mtime = -1;
    try {
      mtime = fs.statSync(args.dms).mtimeMs;
      data = readJson(args.dms);
    } catch { /* mid-write */ }

    if (mtime !== lastMtime) {
      lastMtime = mtime;
      stableSince = Date.now();
    }
    if (data?.colors) {
      const primaries = [data.colors.dark?.primary, data.colors.light?.primary].map(v => v?.toLowerCase());
      if ((!want || primaries.includes(want)) && Date.now() - stableSince >= 300) return { data, stamp };
    }
    if (Date.now() > deadline) {
      if (data?.colors) {
        log('dms-colors.json never matched the palette matugen rendered; using it as it is');
        return { data, stamp };
      }
      throw new Error(`cannot read ${args.dms}`);
    }
    await sleep(100);
  }
}

function resolveMode(args, data, stamp) {
  if (args.mode === 'dark' || args.mode === 'light') return args.mode;
  const want = stamp?.primary?.toLowerCase();
  const dark = data.colors.dark?.primary?.toLowerCase();
  const light = data.colors.light?.primary?.toLowerCase();
  if (want && want === dark && want !== light) return 'dark';
  if (want && want === light && want !== dark) return 'light';
  try {
    return readJson(args.session).isLightMode ? 'light' : 'dark';
  } catch {
    return 'dark';
  }
}

function solveFilters(outDir, slots) {
  const cacheFile = path.join(outDir, 'filter-cache.json');
  let cache = {};
  try { cache = readJson(cacheFile); } catch { /* cold cache */ }
  let changed = false;
  const filters = {};
  for (const slot of SLOTS) {
    const hex = slots[slot];
    if (!cache[hex]) {
      cache[hex] = solveFilter(hex).filter;
      changed = true;
    }
    filters[slot] = cache[hex];
  }
  if (changed) writeFileAtomic(cacheFile, JSON.stringify(cache));
  return filters;
}

// The vendored std library holds one palette line per flavour in each of its two
// maps (colours, then filters). The active flavour's lines get the DMS values;
// the other flavours keep Catppuccin's, so every lookup stays valid.
function makeStdLib(stdText, flavor, slots, filters) {
  const colours = SLOTS.map(slot => `@${slot}: ${slots[slot]};`).join(' ');
  const filterValues = SLOTS.map(slot => `@${slot}: ${filters[slot]};`).join(' ');
  const line = new RegExp(`^(\\s*@${flavor}:\\s*)\\{.*\\};[ \\t]*$`, 'gm');
  let seen = 0;
  const text = stdText.replace(line, (_, lead) => (++seen === 1 ? `${lead}{ ${colours} };` : `${lead}{ ${filterValues} };`));
  if (seen !== 2) throw new Error(`Catppuccin std library layout changed: found ${seen} "@${flavor}" palette lines, expected 2`);
  return text;
}

// Serialises a UserCSS variable the way Stylus hands it to Less.
function serializeVar(v) {
  const raw = v.value ?? v.default;
  switch (v.type) {
    case 'select':
    case 'dropdown':
    case 'image': {
      const options = v.options ?? [];
      const option = options.find(o => o.name === raw) ?? options.find(o => o.value === raw);
      return option ? option.value : raw;
    }
    case 'checkbox':
      return String(raw) === '1' || raw === true ? '1' : '0';
    case 'range':
    case 'number':
      return `${raw}${v.units ?? ''}`;
    default:
      return raw;
  }
}

function prepareSource(entry, stdPath, flavor, overrides) {
  const values = {};
  for (const [name, v] of Object.entries(entry.usercssData?.vars ?? {})) values[name] = serializeVar(v);
  Object.assign(values, overrides);
  values.lightFlavor = flavor;
  values.darkFlavor = flavor;
  values.accentColor = 'mauve';

  const body = entry.sourceCode.replace(HEADER, '');
  if (!STD_IMPORT.test(body)) return { error: 'does not import the Catppuccin std v1 library' };
  const header = Object.entries(values).map(([name, value]) => `@${name}: ${value};`).join('\n');
  return { source: `${header}\n${body.replace(STD_IMPORT, `@import "${stdPath}";`)}` };
}

const slugify = name =>
  name.replace(/\s*Catppuccin\s*$/i, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'style';

function compileAll(jobs, tasks) {
  return new Promise(resolve => {
    const results = new Map();
    if (!tasks.length) return resolve(results);
    let next = 0;
    let live = 0;

    const spawn = () => {
      const worker = new Worker(new URL('./compile-worker.mjs', import.meta.url));
      let current = null;
      live++;
      const feed = () => {
        if (next >= tasks.length) {
          worker.terminate();
          return;
        }
        current = tasks[next++];
        worker.postMessage(current);
      };
      worker.on('message', msg => {
        results.set(msg.id, msg);
        feed();
      });
      worker.on('error', err => {
        if (current) results.set(current.id, { id: current.id, error: `compiler crashed: ${err.message}` });
        current = null;
      });
      worker.on('exit', () => {
        live--;
        if (next < tasks.length) spawn();
        else if (live === 0) resolve(results);
      });
      feed();
    };
    for (let i = 0; i < Math.min(jobs, tasks.length); i++) spawn();
  });
}

function prune(outDir, keep) {
  const generations = fs.readdirSync(outDir)
    .filter(name => name.startsWith('gen-'))
    .map(name => ({ name, mtime: fs.statSync(path.join(outDir, name)).mtimeMs }))
    .sort((a, b) => b.mtime - a.mtime);
  for (const { name } of generations.slice(KEEP_GENERATIONS)) {
    if (name !== `gen-${keep}`) fs.rmSync(path.join(outDir, name), { recursive: true, force: true });
  }
  const stale = Date.now() - 10 * 60 * 1000;
  for (const name of fs.readdirSync(outDir)) {
    const full = path.join(outDir, name);
    if (name.startsWith('.tmp-gen-') && fs.statSync(full).mtimeMs < stale) fs.rmSync(full, { recursive: true, force: true });
  }
}

async function main() {
  const started = performance.now();
  const args = parseArgs(process.argv.slice(2));
  fs.mkdirSync(args.out, { recursive: true });

  const { data, stamp } = await loadDmsColors(args);
  const mode = resolveMode(args, data, stamp);
  const flavor = mode === 'light' ? 'latte' : 'mocha';
  const dank16 = Object.fromEntries(Object.entries(data.dank16 ?? {}).map(([key, v]) => [key, v?.[mode] ?? v?.default]));
  const slots = buildSlots(data.colors[mode], dank16, mode);
  const filters = solveFilters(args.out, slots);

  const bundleText = fs.readFileSync(path.join(args.bundle, 'import.json'), 'utf8');
  const stdText = fs.readFileSync(path.join(args.bundle, 'std-v1.less'), 'utf8');
  const lessVersion = readJson(path.join(HERE, 'node_modules/less/package.json')).version;
  let overrides = {};
  try { overrides = readJson(args.vars); } catch { /* optional */ }

  const paletteHash = sha256(JSON.stringify({
    slots, filters, mode, overrides,
    bundle: sha256(bundleText), std: sha256(stdText), less: lessVersion, builder: BUILDER_VERSION,
    only: args.only ? [...args.only].sort() : null,
  }));
  if (!args.force) {
    try {
      if (readJson(path.join(args.out, 'current/index.json')).paletteHash === paletteHash) {
        log(`palette unchanged (${mode}, accent ${slots.mauve}); nothing to build`);
        return 0;
      }
    } catch { /* no current generation */ }
  }

  const gen = `${paletteHash.slice(0, 12)}-${Math.floor(Date.now() / 1000)}`;
  const tmpDir = path.join(args.out, `.tmp-gen-${gen}-${process.pid}`);
  const blocksDir = path.join(tmpDir, 'blocks');
  fs.mkdirSync(blocksDir, { recursive: true });
  const stdPath = path.join(tmpDir, 'dms-std.less');
  fs.writeFileSync(stdPath, makeStdLib(stdText, flavor, slots, filters));

  const entries = JSON.parse(bundleText).filter(entry => entry && typeof entry.sourceCode === 'string');
  const styles = [];
  const failed = [];
  const tasks = [];
  const ids = new Map();
  for (const entry of entries) {
    const name = entry.usercssData?.name ?? entry.name ?? 'Unnamed';
    let id = slugify(name);
    const count = (ids.get(id) ?? 0) + 1;
    ids.set(id, count);
    if (count > 1) id = `${id}-${count}`;
    if (args.only && !args.only.has(id)) continue;

    const prepared = prepareSource(entry, stdPath, flavor, overrides[id] ?? {});
    if (prepared.error) {
      failed.push({ id, name, error: prepared.error });
      continue;
    }
    styles.push({ id, name });
    tasks.push({ id, source: prepared.source, filename: path.join(tmpDir, `${id}.user.less`) });
  }
  const rank = id => (PRIORITY.includes(id) ? PRIORITY.indexOf(id) : PRIORITY.length);
  tasks.sort((a, b) => rank(a.id) - rank(b.id));

  const results = await compileAll(args.jobs, tasks);

  const published = [];
  const written = new Set();
  const warnings = [];
  let bytes = 0;
  // Bundle order, not compile order: it decides injection order when several
  // styles match one page.
  for (const style of styles) {
    const result = results.get(style.id);
    if (!result || result.error) {
      failed.push({ ...style, error: result?.error ?? 'no result from the compiler' });
      continue;
    }
    let split;
    try {
      split = splitCompiled(result.css);
    } catch (err) {
      failed.push({ ...style, error: `split: ${err.message}` });
      continue;
    }
    if (!split.blocks.length) {
      failed.push({ ...style, error: 'no site blocks after compiling' });
      continue;
    }
    for (const warning of split.warnings) warnings.push(`${style.id}: ${warning}`);
    for (const block of split.blocks) {
      if (written.has(block.hash)) continue;
      fs.writeFileSync(path.join(blocksDir, `${block.hash}.css`), block.css);
      written.add(block.hash);
      bytes += block.bytes;
    }
    published.push({
      id: style.id,
      name: style.name,
      blocks: split.blocks.map(({ hash, bytes: size, matchers }) => ({ hash, bytes: size, matchers })),
    });
  }

  if (!published.length) {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    log(`no style compiled; keeping the previous generation. First failure: ${failed[0]?.id}: ${failed[0]?.error}`);
    return 1;
  }

  const index = {
    format: 1,
    gen,
    paletteHash,
    createdAt: Date.now() / 1000,
    mode,
    flavor,
    palette: slots,
    source: { bundleSha256: sha256(bundleText), less: lessVersion, builder: BUILDER_VERSION },
    stats: {
      total: entries.length,
      ok: published.length,
      failed,
      warnings,
      bytes,
      ms: Math.round(performance.now() - started),
    },
    styles: published,
  };
  writeFileAtomic(path.join(tmpDir, 'index.json'), JSON.stringify(index));

  fs.renameSync(tmpDir, path.join(args.out, `gen-${gen}`));
  const link = path.join(args.out, 'current');
  const tmpLink = `${link}.tmp-${process.pid}`;
  fs.rmSync(tmpLink, { force: true });
  fs.symlinkSync(`gen-${gen}`, tmpLink);
  fs.renameSync(tmpLink, link);
  prune(args.out, gen);

  log(`published gen-${gen}: ${published.length}/${entries.length} styles, ${failed.length} failed, ` +
    `${(bytes / 1048576).toFixed(1)} MiB, ${index.stats.ms} ms (${mode}, accent ${slots.mauve})`);
  for (const f of failed) log(`  failed ${f.id}: ${f.error}`);
  return 0;
}

main().then(
  code => process.exit(code),
  err => {
    log(`build failed: ${err.stack ?? err.message}`);
    process.exit(1);
  },
);
