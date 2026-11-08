// canon: check_privacy_posture_urls v1
// v1 (forsgren#654): judges srcset on img and source, audio src, track src, embed src and object data for Scripts/check_privacy_posture.sh, every srcset candidate by the WHATWG "parse a srcset attribute" algorithm, every host by the built-in WHATWG URL
// Scripts/check_privacy_posture_urls.mjs
//
// The URL half of Scripts/check_privacy_posture.sh, which calls it once per
// run. Node's standard library only: no HTML parser package is available in
// this estate, and this gate adds no dependency.
//
// WHY NODE. A srcset cannot be split on commas: a valid data URL holds commas,
// and a candidate carries descriptors. What a browser does with one is the
// WHATWG "parse a srcset attribute" algorithm, and what host a URL reaches is
// the WHATWG URL parser, which Node has built in and shell does not.
//
// WHAT IT READS. Standard input: one file path per line. Its two arguments: the
// site's own exact hosts and its own subdomain suffixes, each a space-separated
// list in lower case, from the own: rows the gate has already validated.
// `node Scripts/check_privacy_posture_urls.mjs "<hosts>" "<suffixes>" < files`
//
// WHAT IT PRINTS. One line per finding on standard output, `file: tag (why:
// url)`, or `file: a resource tag that is not a complete tag`. No findings, no
// output. Exit 0 whether or not it found anything; any other exit means it did
// not finish, and the gate turns that into its own exit 2.
//
// THE TAGS. A tag is read as the HTML tokenizer reads one: any letter case,
// over any number of lines, attribute by attribute, so data-srcset is not read
// as srcset and a > inside a quoted value does not end the tag. Like the gate's
// other tag checks it reads every occurrence in the file, comments and scripts
// included, and a file with more tag openings than complete tags is a finding:
// it fails closed rather than guessing.
//
// ONE URL RULE. Every attribute goes through urlFinding, the one function a
// later step can route the other resource attributes through.

import { readFileSync } from 'node:fs';

// The tags this script judges and the attribute that fetches on each. The src
// of img and source stays with the gate's own media check.
const JUDGED = {
  img: ['srcset'],
  source: ['srcset'],
  audio: ['src'],
  track: ['src'],
  embed: ['src'],
  object: ['data'],
};

const TAG_NAMES = Object.keys(JUDGED).join('|');
const TAG_DELIMITER = '[\\t\\n\\f\\r />]';

// Two bases that differ in scheme and host: what resolves onto each of them is
// relative, and what takes its scheme from them is scheme-relative.
const BASE_ONE = { href: 'https://base-one.invalid/page/', host: 'base-one.invalid' };
const BASE_TWO = { href: 'http://base-two.invalid/page/', host: 'base-two.invalid' };

const ASCII_WHITESPACE = new Set(['\t', '\n', '\f', '\r', ' ']);
const isWhitespace = (c) => ASCII_WHITESPACE.has(c);
const SHOWN_CHARS = 200;

function main() {
  if (process.argv.length !== 4) {
    console.error('check_privacy_posture_urls.mjs: want two arguments, the own hosts and the own subdomain suffixes');
    process.exit(2);
  }
  const own = {
    hosts: new Set(words(process.argv[2])),
    suffixes: words(process.argv[3]),
  };
  const files = readFileSync(0, 'utf8').split('\n').filter((line) => line !== '');
  const lines = files.flatMap((file) => fileFindings(file, readFileSync(file, 'utf8'), own));
  if (lines.length > 0) console.log(lines.join('\n'));
}

function words(list) {
  return list.split(/\s+/).filter((word) => word !== '');
}

function fileFindings(file, text, own) {
  const lines = [];
  const open = new RegExp(`<(${TAG_NAMES})(?=${TAG_DELIMITER})`, 'gi');
  const total = (text.match(open) ?? []).length;
  let found = 0;
  for (let match = open.exec(text); match !== null; match = open.exec(text)) {
    const tag = readAttributes(text, open.lastIndex);
    if (tag === null) break;
    found += 1;
    open.lastIndex = tag.end;
    const shown = text.slice(match.index, tag.end).replace(/\s+/g, ' ').slice(0, SHOWN_CHARS);
    for (const finding of tagFindings(match[1].toLowerCase(), tag.attributes, own)) {
      lines.push(`${file}: ${shown} (${finding})`);
    }
  }
  if (found !== total) lines.push(`${file}: a resource tag that is not a complete tag`);
  return lines;
}

// readAttributes <text> <from>: the tag's attributes from just after its name,
// as the HTML tokenizer's attribute states read them, and where the tag ends.
// Null when the text ends inside the tag. A name with no = has no value.
function readAttributes(text, from) {
  const attributes = [];
  const skip = (pos, test) => {
    let at = pos;
    while (at < text.length && test(text[at])) at += 1;
    return at;
  };
  let pos = from;
  for (;;) {
    pos = skip(pos, (c) => isWhitespace(c) || c === '/');
    if (pos >= text.length) return null;
    if (text[pos] === '>') return { attributes, end: pos + 1 };
    const nameEnd = skip(pos + 1, (c) => !isWhitespace(c) && c !== '/' && c !== '>' && c !== '=');
    const name = text.slice(pos, nameEnd).toLowerCase();
    pos = skip(nameEnd, isWhitespace);
    if (text[pos] !== '=') {
      attributes.push({ name, value: null, quote: null });
      continue;
    }
    pos = skip(pos + 1, isWhitespace);
    if (pos >= text.length) return null;
    const quote = text[pos];
    if (quote === '"' || quote === "'") {
      const close = text.indexOf(quote, pos + 1);
      if (close < 0) return null;
      attributes.push({ name, value: text.slice(pos + 1, close), quote });
      pos = close + 1;
    } else {
      const valueEnd = skip(pos, (c) => !isWhitespace(c) && c !== '>');
      attributes.push({ name, value: text.slice(pos, valueEnd), quote: null });
      pos = valueEnd;
    }
  }
}

function tagFindings(tagName, attributes, own) {
  const findings = [];
  for (const attribute of attributes) {
    if (!JUDGED[tagName].includes(attribute.name) || attribute.value === null) continue;
    if (attribute.quote !== '"') {
      findings.push(`${attribute.name} is not double-quoted: ${attribute.value}`);
    } else if (attribute.name === 'srcset') {
      for (const url of srcsetCandidateUrls(attribute.value)) {
        addFinding(findings, url, urlFinding(url, own, { dataAllowed: true }));
      }
    } else {
      addFinding(findings, attribute.value, urlFinding(attribute.value, own, { dataAllowed: false }));
    }
  }
  return findings;
}

function addFinding(findings, url, why) {
  if (why !== null) findings.push(`${why}: ${url.slice(0, SHOWN_CHARS)}`);
}

// srcsetCandidateUrls <value>: the URL of every candidate, in order, by the
// WHATWG "parse a srcset attribute" algorithm. Its descriptors are read only to
// find where the candidate ends: every URL is judged, even one whose candidate
// a browser would drop for a bad descriptor, because that is the safe side.
function srcsetCandidateUrls(input) {
  const urls = [];
  let pos = 0;
  for (;;) {
    while (pos < input.length && (isWhitespace(input[pos]) || input[pos] === ',')) pos += 1;
    if (pos >= input.length) return urls;
    const start = pos;
    while (pos < input.length && !isWhitespace(input[pos])) pos += 1;
    let url = input.slice(start, pos);
    if (url.endsWith(',')) {
      url = url.replace(/,+$/, '');
    } else {
      pos = afterDescriptors(input, pos);
    }
    urls.push(url);
  }
}

// afterDescriptors <input> <pos>: the position after this candidate's
// descriptors. The algorithm's tokenizer ends a candidate at a comma outside
// parentheses or at the end of the input; its "in descriptor" and "after
// descriptor" states differ only in collecting the descriptor text, which this
// does not need.
function afterDescriptors(input, from) {
  let inParens = false;
  for (let pos = from; pos < input.length; pos += 1) {
    const c = input[pos];
    if (inParens) {
      if (c === ')') inParens = false;
    } else if (c === '(') {
      inParens = true;
    } else if (c === ',') {
      return pos + 1;
    }
  }
  return input.length;
}

// urlFinding <value> <own> <{dataAllowed}>: null when the value is fine, else
// the reason. The same policy as the gate's media_value_ok: a relative path, or
// https on an own host; a protocol-relative, http, other-scheme or userinfo URL
// or a character reference other than &amp; is a finding. Hosts are read by the
// WHATWG URL parser, as a browser reads them. A data URL contacts no host, and
// only a srcset candidate may be one: an embed or object could run a data:
// document, and that document could load anything.
function urlFinding(raw, own, { dataAllowed }) {
  if (raw.replaceAll('&amp;', '').includes('&')) return 'a character reference other than &amp;';
  const value = raw.replaceAll('&amp;', '&');
  let first;
  let second;
  try {
    first = new URL(value, BASE_ONE.href);
    second = new URL(value, BASE_TWO.href);
  } catch {
    return 'not a URL a browser can read';
  }
  if (first.hostname === BASE_ONE.host && second.hostname === BASE_TWO.host) return null;
  if (first.protocol !== second.protocol) return 'a protocol-relative URL';
  if (first.protocol === 'data:' && dataAllowed) return null;
  if (first.protocol !== 'https:') return `not https (${first.protocol})`;
  if (first.username !== '' || first.password !== '') return 'a URL with a user name or password';
  return hostIsOwn(first.hostname, own) ? null : `host ${first.hostname} is not an own host`;
}

function hostIsOwn(host, own) {
  return own.hosts.has(host)
    || own.suffixes.some((suffix) => host.length > suffix.length + 1 && host.endsWith(`.${suffix}`));
}

main();
