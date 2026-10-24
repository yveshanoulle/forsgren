// canon: browser_gate v5
// Scripts/browser_gate.mjs (forsgren#205)
//
// The browser gate's engine: serves a built site on 127.0.0.1 (loopback only),
// opens each required page in the installed Chrome through puppeteer-core and
// checks it. Run through Scripts/gate_browser.sh, which owns the arguments and
// the exit-trap idiom; self-test: Scripts/test_gate_browser.sh.
//
//   node Scripts/browser_gate.mjs <site-dir> <manifest.json> <exceptions.txt> <baseline.txt> <variants.txt>
//
// Changelog of the canon (the baseline format is the same in every version, so
// no version needs a migration):
//   v5 = v4 plus the exits (forsgren#381, found by another estate repository):
//        Chrome is closed and its profile folder removed on every way out: the
//        end, an error, and SIGINT, SIGTERM or SIGHUP (exit 130, 143, 129),
//        through one idempotent release() (the browser closed in 5 s, then
//        killed; the server; the profile). The mkdtemp and the launch sit
//        inside the try, puppeteer's own signal handlers are off, and Chrome
//        runs on a pipe, so it ends by itself if this process is killed with
//        SIGKILL. The profile folder is removed with retries, since Chrome's
//        helpers can still write into it a moment after a signal that came
//        during the first page (forsgren#383, before any copy took v5). The
//        findings and the exit statuses 0, 1 and 2 are unchanged.
//   v4 = v3 plus the CLS interval from the load (forsgren#377, decision #380):
//        the observation interval (default 1000 ms) starts right after the
//        page load, whatever the document checks and axe take, with no second
//        read after axe; and the sideways measurement without scrollbar room
//        (scrollbar-gutter off while measuring), so it no longer depends on
//        the machine's scrollbar style.
//   v3 = v2 plus the sideways measurement at two widths (forsgren#350,
//        decision #365).
//   v2 = v1 plus the variants (estate issue 305).
//
// Per page: axe-core serious and critical violations, a doctype, a charset
// declared by the document itself (the server sends none), zero console
// errors and page errors, zero failed requests (a status >= 400 read from the
// RESPONSE, plus network failures, plus any request that leaves loopback), and
// a layout shift (CLS), observed for a fixed interval at a fixed viewport. The
// CLS is printed unrounded with the viewport, the browser version and the
// interval. Then sideways scrolling (forsgren#350): at a laptop and a phone
// width (SIDEWAYS_VIEWPORTS), the page must not be wider than the window and no
// table wider than the box it sits in (its parent, the scroll box when it has
// one): scrollWidth above clientWidth is red, naming the width and the overflow
// in pixels. One rule for every page with a table. The CLS is measured at
// VIEWPORT alone, as in v2.
//
// Variants (v2, estate issue 305): every page is checked once per variant, each
// on its own, because a site may have more than one look. A variant is a row of
// the variants file, data per site, `name|how to apply`, a closed vocabulary:
//   scheme:light | scheme:dark   emulate that prefers-color-scheme;
//   attr:<attribute>=<value>     set that attribute on <html> before the first
//                                paint (a manual theme switch), the colour
//                                scheme emulated light.
// The variant is applied to the page, never by clicking its controls. A missing
// file, no row, a duplicate name, an unknown how and a malformed row are exit 2.
// A site with one look has one row, light|scheme:light.
//
// Exceptions (closed format, fail-closed, a reason on every row):
//   resource|reason              a resource path that may answer an error;
//   external|<url prefix>|reason a request to that prefix is blocked (no
//                                network), counted and shown, not failed.
// Every row must match something, so a stale row is red.
//
// The baseline (estate issue 305, closed format, fail-closed, a reason on
// every row, shrink-only):
//   axe|<variant>|<page>|<rule>|<selector>|reason   one serious or critical axe
//                                                   finding, in that variant;
//   cls|<variant>|<page>|<value>|reason             the page's CLS in that
//                                                   variant, as measured;
//   sideways|<variant>|<page>|<viewport>|<what>|<px>|reason
//                                                   one sideways overflow (v3,
//                                                   forsgren#350, decision
//                                                   #364): <viewport> one of
//                                                   SIDEWAYS_VIEWPORTS (390x844),
//                                                   <what> `the page` or
//                                                   `table N`, <px> as measured.
// A row names a variant of the variants file, or it is exit 2: a row without a
// variant is malformed, there is no default.
// Every baselined finding is printed as a WARN and counted. A finding that is
// not in the baseline is red (new); a baselined axe finding that is gone is red
// (stale); a CLS above its recorded value is red (grew), a CLS below it is red
// (lower the row), and a CLS above 0 with no row is red. A sideways overflow
// is judged as a CLS: above its row red (grew), below it red (shrink the row),
// equal a WARN, with no row red, and a row whose overflow is gone red (stale).
// A missing baseline file is exit 2.
//
// axe-core is an automated accessibility gate, not proof of complete WCAG
// compliance.
//
// Security (estate issue 305, #302): the pages come from the commit under test,
// pull requests included, and their scripts run in Chrome. Chrome gets a
// fresh temporary profile, a scrubbed environment, the sandbox, and loopback
// only (see CHROME_ARGS); the server serves the site directory and nothing else.
//
// Exit 0 green, 1 findings, 2 the gate could not run (Chrome, arguments,
// manifest or exceptions unusable). Nothing is guessed.

import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = process.env.FORSGREN_NODE_ROOT || path.resolve(here, '..');
const require = createRequire(path.join(root, 'package.json'));
const puppeteer = require('puppeteer-core');
const axe = require('axe-core');

const VIEWPORT = { width: 1280, height: 800, deviceScaleFactor: 1 };
// The widths sideways scrolling is measured at (forsgren#350): a laptop and a
// phone. The first is VIEWPORT, the one the other checks use.
const SIDEWAYS_VIEWPORTS = [VIEWPORT, { width: 390, height: 844, deviceScaleFactor: 1 }];
const sizeOf = (viewport) => `${viewport.width}x${viewport.height}`;
// An overflow in whole pixels scrolls sideways when it is above 0.
const scrollsSideways = (px) => px > 0;
// The layout-shift measurement: this many cold loads, each read after this
// interval. The defaults are the real gate. A self-test case that never asserts
// on layout shift shortens them through the environment (forsgren#247); an unset
// variable keeps the default, an unusable one stops the gate (exit 2).
function envPositive(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  if (!/^[1-9][0-9]*$/.test(raw)) die(`${name} must be a positive integer, got '${raw}'`);
  return Number(raw);
}
const CLS_INTERVAL_MS = envPositive('FORSGREN_CLS_INTERVAL_MS', 1000);
// The nav is injected by a script racing the first paint, so one load can show a
// shift another does not: a page's CLS is the largest of this many cold loads.
const CLS_LOADS = envPositive('FORSGREN_CLS_LOADS', 5);
const NAV_TIMEOUT_MS = 30000;
// The baseline's keys and the CLS comparison, one place each: what a finding
// is matched on, and how two CLS values are compared (exactly).
const axeKey = (variant, page, rule, selector) => `axe|${variant}|${page}|${rule}|${selector}`;
const clsKey = (variant, page) => `${variant}|${page}`;
const sidewaysKey = (variant, page, viewport, what) => `sideways|${variant}|${page}|${viewport}|${what}`;
const compared = (value) => value;
const GATING_IMPACTS = ['serious', 'critical'];
const CHROME_CANDIDATES = [
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
];
const TYPES = {
  '.html': 'text/html',
  '.css': 'text/css',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.js': 'text/javascript',
  '.json': 'application/json',
  '.txt': 'text/plain',
};
// Chrome runs the pages' own scripts, so it is launched as bare as it goes:
// a fresh empty profile (made here, removed after), a scrubbed environment
// (no token, no SSH agent, no HOME of the user), the sandbox ON (no
// --no-sandbox), no extensions or background services, and a resolver that
// answers only 127.0.0.1, so a name never reaches a DNS server. The request
// interception below is the second wall: a request that leaves loopback is red.
const CHROME_ARGS = [
  '--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE 127.0.0.1',
  '--proxy-server=direct://',
  '--proxy-bypass-list=*',
  '--disable-extensions',
  '--disable-sync',
  '--disable-background-networking',
  '--disable-component-update',
  '--no-first-run',
  '--no-default-browser-check',
  '--password-store=basic',
  '--use-mock-keychain',
];

function die(message) {
  console.error(`browser-gate: ${message}`);
  process.exit(2);
}

function chromePath() {
  const named = process.env.FORSGREN_CHROME;
  if (named) {
    if (!fs.existsSync(named)) die(`FORSGREN_CHROME does not exist: ${named}`);
    return named;
  }
  const found = CHROME_CANDIDATES.find((candidate) => fs.existsSync(candidate));
  if (!found) die('no Chrome found (set FORSGREN_CHROME, or install Google Chrome)');
  return found;
}

function readPages(manifestFile) {
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
  } catch (error) {
    die(`cannot read the pages manifest ${manifestFile}: ${error.message}`);
  }
  const pages = manifest.requiredPages;
  if (!Array.isArray(pages) || pages.length === 0) {
    die(`${manifestFile} lists no requiredPages: nothing to open is not clean`);
  }
  return pages;
}

// Exceptions: `resource|reason` and `external|<url prefix>|reason`, one per
// line; comments and blanks skipped.
function readExceptions(file) {
  if (!fs.existsSync(file)) die(`exceptions file not found: ${file}`);
  const resources = new Map();
  const externals = new Map();
  fs.readFileSync(file, 'utf8').split('\n').forEach((line, index) => {
    if (line.trim() === '' || line.startsWith('#')) return;
    const at = `${file} line ${index + 1}`;
    const fields = line.split('|').map((field) => field.trim());
    if (fields[0] === 'external') {
      if (fields.length !== 3) die(`${at}: an external row is external|<url prefix>|reason`);
      const [, prefix, reason] = fields;
      if (!/^https?:\/\/./.test(prefix)) die(`${at}: the external prefix must start with http:// or https://`);
      if (reason === '') die(`${at}: ${prefix} has no reason; an exception names its reason`);
      if (externals.has(prefix)) die(`${at}: ${prefix} is listed twice`);
      externals.set(prefix, { reason, used: false });
      return;
    }
    if (fields.length !== 2) die(`${at}: a row is resource|reason or external|<url prefix>|reason`);
    const [resource, reason] = fields;
    if (!resource.startsWith('/')) die(`${at}: the resource must be a path starting with /`);
    if (reason === '') die(`${at}: ${resource} has no reason; an exception names its reason`);
    resources.set(resource, { reason, used: false });
  });
  return { resources, externals };
}

// The variants: `name|how to apply`, one per line; comments and blanks skipped.
// How: scheme:light, scheme:dark or attr:<attribute>=<value>.
function readVariants(file) {
  if (!fs.existsSync(file)) die(`variants file not found: ${file}`);
  const variants = new Map();
  fs.readFileSync(file, 'utf8').split('\n').forEach((line, index) => {
    if (line.trim() === '' || line.startsWith('#')) return;
    const at = `${file} line ${index + 1}`;
    const fields = line.split('|').map((field) => field.trim());
    if (fields.length !== 2) die(`${at}: a row is name|how to apply`);
    const [name, how] = fields;
    if (!/^[a-z][a-z0-9-]*$/.test(name)) die(`${at}: the variant name is lower-case letters, digits and dashes`);
    if (variants.has(name)) die(`${at}: variant ${name} is listed twice`);
    const attribute = /^attr:([A-Za-z][A-Za-z0-9_-]*)=([A-Za-z0-9_-]+)$/.exec(how);
    if (how === 'scheme:light' || how === 'scheme:dark') {
      variants.set(name, { name, how, scheme: how.slice(7), attr: null });
    } else if (attribute) {
      variants.set(name, { name, how, scheme: 'light', attr: { name: attribute[1], value: attribute[2] } });
    } else {
      die(`${at}: ${name}: unknown how to apply '${how}' (scheme:light, scheme:dark or attr:<attribute>=<value>)`);
    }
  });
  if (variants.size === 0) die(`${file} lists no variant: nothing to check is not clean`);
  return variants;
}

// The baseline: `axe|<variant>|<page>|<rule>|<selector>|reason` and
// `cls|<variant>|<page>|<value>|reason`. A selector may contain `|`; the reason
// may not. Every row names a variant of the variants file.
function readBaseline(file, variants) {
  if (!fs.existsSync(file)) die(`baseline file not found: ${file}`);
  const axeRows = new Map();
  const clsRows = new Map();
  const sidewaysRows = new Map();
  const knownVariant = (at, variant) => {
    if (!variants.has(variant)) die(`${at}: '${variant}' is not a variant of the variants file (a row starts with its variant)`);
  };
  fs.readFileSync(file, 'utf8').split('\n').forEach((line, index) => {
    if (line.trim() === '' || line.startsWith('#')) return;
    const at = `${file} line ${index + 1}`;
    const fields = line.split('|').map((field) => field.trim());
    const reason = fields[fields.length - 1];
    if (fields[0] === 'axe') {
      if (fields.length < 6) die(`${at}: a row is axe|<variant>|<page>|<rule>|<selector>|reason`);
      const [, variant, page, rule] = fields;
      const selector = fields.slice(4, -1).join('|');
      knownVariant(at, variant);
      if (!page.startsWith('/') || rule === '' || selector === '') die(`${at}: a row is axe|<variant>|<page>|<rule>|<selector>|reason, the page starting with /`);
      if (reason === '') die(`${at}: ${variant} ${page} ${rule} ${selector} has no reason; a baseline row names its reason`);
      const key = axeKey(variant, page, rule, selector);
      if (axeRows.has(key)) die(`${at}: ${key} is listed twice`);
      axeRows.set(key, { key, reason, seen: false });
    } else if (fields[0] === 'cls') {
      if (fields.length !== 5) die(`${at}: a row is cls|<variant>|<page>|<value>|reason`);
      const [, variant, page, text] = fields;
      knownVariant(at, variant);
      if (!page.startsWith('/')) die(`${at}: the page must start with /`);
      if (!/^[0-9]+(\.[0-9]+)?([eE]-?[0-9]+)?$/.test(text) || Number(text) <= 0) die(`${at}: ${page} CLS value must be a positive number`);
      if (reason === '') die(`${at}: ${variant} ${page} CLS has no reason; a baseline row names its reason`);
      const key = clsKey(variant, page);
      if (clsRows.has(key)) die(`${at}: ${variant} ${page} CLS is listed twice`);
      clsRows.set(key, { variant, page, text, value: Number(text), reason, seen: false });
    } else if (fields[0] === 'sideways') {
      readSidewaysRow(at, fields, knownVariant, sidewaysRows);
    } else {
      die(`${at}: unknown row kind (axe, cls or sideways)`);
    }
  });
  return { axeRows, clsRows, sidewaysRows };
}

// One `sideways|<variant>|<page>|<viewport>|<what>|<px>|reason` row (v3).
function readSidewaysRow(at, fields, knownVariant, rows) {
  if (fields.length !== 7) die(`${at}: a row is sideways|<variant>|<page>|<viewport>|<what>|<px>|reason`);
  const [, variant, page, viewport, what, text, reason] = fields;
  knownVariant(at, variant);
  if (!page.startsWith('/')) die(`${at}: the page must start with /`);
  if (!SIDEWAYS_VIEWPORTS.some((known) => sizeOf(known) === viewport)) {
    die(`${at}: '${viewport}' is not a viewport the gate measures (${SIDEWAYS_VIEWPORTS.map(sizeOf).join(', ')})`);
  }
  if (what === '') die(`${at}: a sideways row names what scrolls (the page, or table N)`);
  if (!/^[1-9][0-9]*$/.test(text)) die(`${at}: ${page} ${viewport} ${what}: the overflow must be a positive whole number of pixels`);
  if (reason === '') die(`${at}: ${variant} ${page} ${viewport} ${what} has no reason; a baseline row names its reason`);
  const key = sidewaysKey(variant, page, viewport, what);
  if (rows.has(key)) die(`${at}: ${key} is listed twice`);
  rows.set(key, { key, text, px: Number(text), reason, seen: false });
}

function serve(siteDir) {
  const base = path.resolve(siteDir);
  const server = http.createServer((request, response) => {
    let pathname = decodeURIComponent(new URL(request.url, 'http://x').pathname);
    if (pathname.endsWith('/')) pathname += 'index.html';
    const file = path.join(base, pathname);
    const inside = file === base || file.startsWith(base + path.sep);
    if (!inside || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
      response.writeHead(404, { 'Content-Type': 'text/plain' });
      response.end('not found');
      return;
    }
    // No charset in the header: the document has to declare its own.
    response.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(response);
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

// What scrolls sideways on the page as it is laid out now: the page itself,
// then each table's box, in document order, each with its overflow in pixels.
// The room a vertical scrollbar takes from every box on the page is the
// system's choice, not the page's: a classic scrollbar is 15 px and, with the
// page's `scrollbar-gutter: stable` (forsgren#153), reserved even where Chrome
// hides it; an overlay scrollbar takes none. The same page measured 15 px
// wider or narrower after the system's scrollbar style changed, and after the
// #377 reorder (forsgren#377, .1). So the measurement takes the gutter and the
// vertical overflow away first and gives them back: the number is the layout
// without any scrollbar room, the same on every machine and in every order.
function measureSideways() {
  const found = [];
  const root = document.scrollingElement;
  const html = document.documentElement;
  html.style.setProperty('scrollbar-gutter', 'auto', 'important');
  html.style.setProperty('overflow-y', 'hidden', 'important');
  found.push({ what: 'the page', box: 'the window', px: root.scrollWidth - root.clientWidth });
  document.querySelectorAll('table').forEach((table, index) => {
    const box = table.parentElement;
    found.push({ what: `table ${index + 1}`, box: 'its box', px: box.scrollWidth - box.clientWidth });
  });
  html.style.removeProperty('overflow-y');
  html.style.removeProperty('scrollbar-gutter');
  return found;
}

const OBSERVE_SHIFTS = `
  window.__shifts = [];
  new PerformanceObserver((list) => {
    for (const entry of list.getEntries()) {
      if (!entry.hadRecentInput) window.__shifts.push(entry.value);
    }
  }).observe({ type: 'layout-shift', buffered: true });
`;

// One page's findings. `used` collects the exception rows that matched.
class PageCheck {
  constructor(page, origin, variant, pagePath, exceptions, baseline) {
    this.page = page;
    this.origin = origin;
    this.variant = variant.name;
    this.pagePath = pagePath;
    this.label = `${variant.name} ${pagePath}`;
    this.exceptions = exceptions.resources;
    this.externals = exceptions.externals;
    this.baseline = baseline;
    this.findings = [];
    this.warnings = [];
    this.baselinedAxe = 0;
    this.baselinedCls = 0;
    this.baselinedSideways = 0;
    this.externalBlocked = 0;
    this.blocked = new Set();
    this.exceptedUrls = new Set();
    this.nonGating = 0;
    this.cls = 0;
  }

  // Excepted responses, once each: the page is loaded again to measure the CLS.
  get excepted() {
    return this.exceptedUrls.size;
  }

  resourceOf(url) {
    return url.startsWith(this.origin) ? url.slice(this.origin.length) : url;
  }

  // The row for a resource, marked used, or undefined.
  exception(url) {
    const row = this.exceptions.get(this.resourceOf(url).split('?')[0]);
    if (row) row.used = true;
    return row;
  }

  find(text) {
    const line = `FAIL: ${this.label}: ${text}`;
    if (!this.findings.includes(line)) this.findings.push(line);
  }

  // A warning once per page: the page is loaded again to measure the CLS.
  // True when it is new.
  warn(text) {
    const line = `WARN: ${text}`;
    if (this.warnings.includes(line)) return false;
    this.warnings.push(line);
    return true;
  }

  // The external row whose prefix starts the URL, marked used, or undefined.
  externalRow(url) {
    for (const [prefix, row] of this.externals) {
      if (url.startsWith(prefix)) {
        row.used = true;
        return row;
      }
    }
    return undefined;
  }

  listen() {
    const { page } = this;
    page.on('response', (response) => {
      if (response.status() < 400) return;
      if (this.exception(response.url())) {
        this.exceptedUrls.add(response.url());
        return;
      }
      this.find(`request ${this.resourceOf(response.url())} -> ${response.status()}`);
    });
    page.on('requestfailed', (request) => {
      if (this.blocked.has(request.url())) return;
      if (this.exception(request.url())) return;
      const reason = request.failure()?.errorText ?? 'unknown';
      this.find(`request ${this.resourceOf(request.url())} failed: ${reason}`);
    });
    page.on('console', (message) => {
      if (message.type() !== 'error') return;
      const where = message.location().url ?? '';
      if (this.exception(where) || this.blocked.has(where)) return;
      this.find(`console error: ${message.text()}`);
    });
    page.on('pageerror', (error) => this.find(`page error: ${error.message}`));
    page.on('request', (request) => {
      const url = request.url();
      if (url.startsWith(this.origin) || url.startsWith('data:') || url.startsWith('about:')) {
        request.continue();
        return;
      }
      this.blocked.add(url);
      const external = this.externalRow(url);
      if (external) {
        if (this.warn(`external blocked: ${this.label}: ${url} (${external.reason})`)) this.externalBlocked += 1;
      } else {
        this.find(`request ${url} leaves loopback`);
      }
      request.abort('blockedbyclient');
    });
  }

  async checkDocument() {
    const { doctype, charset } = await this.page.evaluate(() => ({
      doctype: document.doctype ? document.doctype.name : '',
      charset: Boolean(document.querySelector('meta[charset]')),
    }));
    if (doctype.toLowerCase() !== 'html') this.find('doctype missing or not html');
    if (!charset) this.find('charset not declared by a meta charset');
  }

  async checkAxe() {
    await this.page.evaluate(axe.source);
    const result = await this.page.evaluate(() => axe.run(document, { resultTypes: ['violations'] }));
    for (const violation of result.violations) {
      if (!GATING_IMPACTS.includes(violation.impact)) {
        this.nonGating += 1;
        continue;
      }
      for (const node of violation.nodes) this.judgeAxeNode(violation, node.target.join(' '));
    }
  }

  // One axe finding against the baseline: listed is a WARN, not listed is new.
  judgeAxeNode(violation, selector) {
    const row = this.baseline.axeRows.get(axeKey(this.variant, this.pagePath, violation.id, selector));
    if (row) {
      if (row.seen) return;
      row.seen = true;
      this.baselinedAxe += 1;
      this.warn(`baselined axe ${violation.id} (${violation.impact}): ${this.label}: ${selector}`);
      return;
    }
    this.find(`axe ${violation.id} (${violation.impact}): ${selector} (new, not in the baseline)`);
  }

  // The shift of the load in progress, read after the fixed interval.
  async shiftOfThisLoad() {
    await new Promise((resolve) => setTimeout(resolve, CLS_INTERVAL_MS));
    const shifts = await this.page.evaluate(() => window.__shifts);
    return shifts.reduce((sum, value) => sum + value, 0);
  }

  async checkLayoutShift() {
    let cls = await this.shiftOfThisLoad();
    for (let load = 1; load < CLS_LOADS; load += 1) {
      await this.page.reload({ waitUntil: 'load', timeout: NAV_TIMEOUT_MS });
      cls = Math.max(cls, await this.shiftOfThisLoad());
    }
    this.cls = cls;
    const conditions = `viewport ${VIEWPORT.width}x${VIEWPORT.height}, interval ${CLS_INTERVAL_MS} ms, largest of ${CLS_LOADS} cold loads`;
    const row = this.baseline.clsRows.get(clsKey(this.variant, this.pagePath));
    if (!row) {
      if (cls !== 0) this.find(`CLS ${cls} (${conditions}); no baseline row`);
      return;
    }
    row.seen = true;
    if (compared(cls) > compared(row.value)) {
      this.find(`CLS ${cls} grew above the recorded ${row.text} (${conditions})`);
    } else if (compared(cls) < compared(row.value)) {
      this.find(`CLS ${cls} is below the recorded ${row.text}: lower the row, or remove it at 0 (${conditions})`);
    } else {
      this.baselinedCls += 1;
      this.warn(`baselined CLS ${this.label}: ${cls} (${conditions})`);
    }
  }

  // Sideways scrolling at each width (forsgren#350), after the layout shift
  // was read, so the resize moves nothing that is measured.
  async checkSideways() {
    for (const viewport of SIDEWAYS_VIEWPORTS) {
      await this.page.setViewport(viewport);
      for (const { what, box, px } of await this.page.evaluate(measureSideways)) {
        if (scrollsSideways(px)) this.judgeSideways(sizeOf(viewport), what, `${what} is ${px} px wider than ${box}`, px);
      }
    }
  }

  // One sideways overflow against the baseline (v3), as a CLS is judged.
  judgeSideways(viewport, what, overflow, px) {
    const row = this.baseline.sidewaysRows.get(sidewaysKey(this.variant, this.pagePath, viewport, what));
    if (!row) {
      this.find(`scrolls sideways at ${viewport}: ${overflow}`);
      return;
    }
    row.seen = true;
    if (px > row.px) {
      this.find(`scrolls sideways at ${viewport}: ${overflow}, above the recorded ${row.text} px (grew)`);
    } else if (px < row.px) {
      this.find(`scrolls sideways at ${viewport}: ${overflow}, below the recorded ${row.text} px: shrink the row`);
    } else {
      this.baselinedSideways += 1;
      this.warn(`baselined sideways scroll: ${this.label}: at ${viewport} ${overflow}`);
    }
  }
}

// The script that sets the variant's attribute on <html> before the page's own
// scripts and first paint. <html> may not exist yet at document start, so it
// waits for it.
function attributeScript(attr) {
  return `(() => {
    const set = () => document.documentElement.setAttribute(${JSON.stringify(attr.name)}, ${JSON.stringify(attr.value)});
    if (document.documentElement) { set(); return; }
    new MutationObserver((records, observer) => {
      if (document.documentElement) { set(); observer.disconnect(); }
    }).observe(document, { childList: true });
  })();`;
}

// What main() has open, so that every way out closes it: the end, an error
// (release() in main's finally) and a signal (below). Whoever made the profile
// directory removes it.
const live = { browser: null, server: null, profile: null };
const CLOSE_TIMEOUT_MS = 5000;
let releasing = null;

function release() {
  releasing ||= (async () => {
    const { browser, server, profile } = live;
    if (browser) {
      const child = browser.process();
      let timer;
      const closed = browser.close().catch(() => {});
      const late = new Promise((resolve) => { timer = setTimeout(resolve, CLOSE_TIMEOUT_MS); });
      await Promise.race([closed, late]);
      clearTimeout(timer);
      if (child && child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
    }
    if (server) server.close();
    // Chrome's helper processes can still write into the profile for a moment
    // after the browser closed (a signal during the first page): retry, so the
    // folder is gone when the run ends (forsgren#383).
    if (profile) fs.rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
  })();
  return releasing;
}

// A signal ends the run like an error would: close, remove, exit 128 + number.
for (const [name, code] of [['SIGINT', 130], ['SIGTERM', 143], ['SIGHUP', 129]]) {
  process.on(name, () => {
    release().finally(() => process.exit(code));
  });
}

async function checkPage(browser, origin, variant, pagePath, exceptions, baseline) {
  const page = await browser.newPage();
  await page.setViewport(VIEWPORT);
  // Fixed conditions: the machine's own colour scheme must not decide the result.
  await page.emulateMediaFeatures([{ name: 'prefers-color-scheme', value: variant.scheme }]);
  if (variant.attr) await page.evaluateOnNewDocument(attributeScript(variant.attr));
  await page.setCacheEnabled(false);
  await page.setRequestInterception(true);
  await page.evaluateOnNewDocument(OBSERVE_SHIFTS);
  const check = new PageCheck(page, origin, variant, pagePath, exceptions, baseline);
  check.listen();
  try {
    await page.goto(origin + pagePath, { waitUntil: 'load', timeout: NAV_TIMEOUT_MS });
    // The CLS interval starts at the load (forsgren#377), before the document
    // and axe checks, whose duration is the machine's: read after them, a slow
    // machine saw shifts a fast one had not yet had.
    await check.checkLayoutShift();
    await check.checkDocument();
    await check.checkAxe();
    await check.checkSideways();
  } catch (error) {
    check.find(`could not be checked: ${error.message}`);
  }
  await page.close();
  return check;
}

async function main() {
  const [siteDir, manifestFile, exceptionsFile, baselineFile, variantsFile] = process.argv.slice(2);
  if (!siteDir || !manifestFile || !exceptionsFile || !baselineFile || !variantsFile) die('usage: browser_gate.mjs <site-dir> <manifest.json> <exceptions.txt> <baseline.txt> <variants.txt>');
  if (!fs.statSync(siteDir, { throwIfNoEntry: false })?.isDirectory()) die(`site dir not found: ${siteDir}`);
  const pages = readPages(manifestFile);
  const exceptions = readExceptions(exceptionsFile);
  const variants = readVariants(variantsFile);
  const baseline = readBaseline(baselineFile, variants);
  const executablePath = chromePath();

  const server = await serve(siteDir);
  live.server = server;
  const origin = `http://127.0.0.1:${server.address().port}`;
  const checks = [];
  let version;
  try {
    live.profile = fs.mkdtempSync(path.join(os.tmpdir(), 'browser-gate-'));
    live.browser = await puppeteer.launch({
      executablePath,
      headless: true,
      userDataDir: live.profile,
      args: CHROME_ARGS,
      env: { PATH: '/usr/bin:/bin', HOME: live.profile, TMPDIR: live.profile, LANG: 'C' },
      // The signals are handled above, once, with the profile; the pipe makes
      // Chrome end by itself when this process dies without a chance to close it.
      handleSIGINT: false,
      handleSIGTERM: false,
      handleSIGHUP: false,
      pipe: true,
    });
    version = await live.browser.version();
    for (const variant of variants.values()) {
      for (const pagePath of pages) checks.push(await checkPage(live.browser, origin, variant, pagePath, exceptions, baseline));
    }
  } finally {
    await release();
  }

  const findings = checks.flatMap((check) => check.findings);
  for (const [resource, row] of exceptions.resources) {
    if (!row.used) findings.push(`FAIL: exception ${resource} matched nothing (${row.reason}); remove it`);
  }
  for (const [prefix, row] of exceptions.externals) {
    if (!row.used) findings.push(`FAIL: stale external exception: ${prefix} was requested by no page (${row.reason}); remove it`);
  }
  for (const row of baseline.axeRows.values()) {
    if (!row.seen) findings.push(`FAIL: stale baseline row: ${row.key} is no longer found; remove it`);
  }
  for (const row of baseline.clsRows.values()) {
    if (!row.seen) findings.push(`FAIL: stale baseline row: cls|${row.variant}|${row.page}|${row.text} was not measured; remove it`);
  }
  for (const row of baseline.sidewaysRows.values()) {
    if (!row.seen) findings.push(`FAIL: stale baseline row: ${row.key}|${row.text} no longer scrolls sideways; remove it`);
  }
  const warnings = checks.flatMap((check) => check.warnings);
  if (warnings.length > 0) console.log(warnings.join('\n'));
  if (findings.length > 0) {
    console.log(findings.join('\n'));
    process.exit(1);
  }
  const sum = (key) => checks.reduce((total, check) => total + check[key], 0);
  const clsWorst = Math.max(...checks.map((check) => check.cls));
  console.log(
    `OK: browser gate: ${pages.length} pages x ${variants.size} variants (${[...variants.keys()].join(', ')}), ${checks.length} checks, axe serious+critical 0 new (${sum('baselinedAxe')} axe findings baselined, ${sum('nonGating')} moderate or minor not gated), ` +
    `doctype and charset present, console errors 0, failed requests 0 (${sum('excepted')} excepted), ` +
    `${sum('externalBlocked')} external requests blocked (listed), ` +
    `CLS worst ${clsWorst} (${sum('baselinedCls')} pages with a baselined CLS), ` +
    `no new sideways scroll at ${SIDEWAYS_VIEWPORTS.map(sizeOf).join(' and ')} (${sum('baselinedSideways')} baselined) ` +
    `(viewport ${VIEWPORT.width}x${VIEWPORT.height}, ${version}, interval ${CLS_INTERVAL_MS} ms)`,
  );
}

main().catch((error) => die(error.stack || error.message));
