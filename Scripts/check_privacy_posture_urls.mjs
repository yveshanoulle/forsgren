// canon: check_privacy_posture_urls v3
// v3 (forsgren#659): CSS @import in style elements and .css files, input type=image and SVG href and xlink:href go through urlFinding; an @import or a style element it cannot read is a finding
// v2 (forsgren#656): a URL with a user name or password is a finding in every resource attribute and CSS url(), whatever its host, read by the built-in WHATWG URL through the one function urlFinding; the host policy of each tag is unchanged
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
// WHAT ELSE. A tag whose attribute fetches only under a condition names it in
// READ_WHEN: an input fetches its src only when its type is image. The SVG
// elements of SVG_HREF_TAGS are judged on href and on the legacy xlink:href, so
// a local #fragment passes and another host does not; an <a> is a link, and an
// outbound link is no finding. An @import is read in a .css file and inside a
// style element, by the CSS tokenizer's rules below: cssImports only identifies
// the URLs, and cssFindings, its caller, applies the policy.
//
// THESE ARE THE MECHANISMS IT KNOWS. Reading them closes the gaps they were, and
// proves nothing about a mechanism this script does not read.
//
// ONE URL RULE. Every attribute goes through urlFinding. For the tags of JUDGED
// it is the whole policy. For the tags of USER_INFO_ONLY and for CSS url() it
// is the user-info rule alone: the host policy of those stays in the gate's
// shell checks, which differ from this one (an iframe has its own allow-list, a
// script or stylesheet may not be absolute at all), and neither their verdict
// nor what they accept moves here. A browser connects to the host after the @,
// so an allowed name before it proves nothing, and a shell pattern that stops
// at the first : never sees that. These are read in a pass of their own that
// adds no other finding: no quote rule, no count of incomplete tags.

import { readFileSync } from 'node:fs';

// The tags this script judges in full and the attribute that fetches on each.
// The src of img and source stays with the gate's own media check.
const SVG_HREF = ['href', 'xlink:href'];

// The SVG elements with a reference attribute, lower case as the tags are read.
const SVG_HREF_TAGS = [
  'image', 'use', 'feimage', 'script', 'lineargradient', 'radialgradient', 'pattern', 'filter', 'textpath', 'tref',
  'altglyph', 'glyphref', 'cursor', 'font-face-uri', 'color-profile', 'mpath', 'animate', 'animatemotion',
  'animatecolor', 'animatetransform', 'set', 'discard', 'hatch',
];

const JUDGED = {
  img: ['srcset'],
  source: ['srcset'],
  audio: ['src'],
  track: ['src'],
  embed: ['src'],
  object: ['data'],
  input: ['src'],
  ...Object.fromEntries(SVG_HREF_TAGS.map((tag) => [tag, SVG_HREF])),
};

// The tags of JUDGED that fetch only when their attributes say so.
const READ_WHEN = { input: isImageInput };

// The attributes whose host policy is the gate's own shell check: only the
// user-info rule is applied to them here. img, video and source list src and
// poster because the gate's media check reads both on all three.
const USER_INFO_ONLY = {
  iframe: ['src'],
  script: ['src'],
  link: ['href'],
  img: ['src', 'poster'],
  video: ['src', 'poster'],
  source: ['src', 'poster'],
};

// A CSS url(), in any letter case, with its three spellings of the value.
const CSS_URL = /\burl\(\s*(?:"([^"]*)"|'([^']*)'|([^\s)'"]*))/gi;

// The named character references that can spell what ends or splits a URL's
// authority. A letter or digit spelled as a reference is read by the numeric
// form or changes no delimiter, so the 2000-odd other names are not needed.
const URL_REFERENCES = {
  amp: '&', AMP: '&', colon: ':', commat: '@', sol: '/', bsol: '\\', quest: '?', num: '#', Tab: '\t', NewLine: '\n',
};

const TAG_DELIMITER = '[\\t\\n\\f\\r />]';

const STYLE_TAG = { style: [] };
const STYLE_END = /<\/style[\t\n\f\r />]/gi;

// What makes a style element's text mean something else inside an inline SVG,
// where the HTML parser reads markup and character references that it does not
// read in a plain style element. The two readings can disagree on what is CSS,
// so such a text is a finding: tags, comments, numeric references, named ones
// other than &amp;, and &quot, which needs no semicolon.
const STYLE_NOT_CSS = /<[a-z!?/]|&(?:#|quot|(?!amp;)[a-z][a-z0-9]*;)/i;

// The tokens of CSS Syntax this script needs, each anchored at a position. A
// name holds escapes; a string's closing quote is left out so that a string
// that never closes can be told from one that does; a bare url() value may hold
// no quote, parenthesis, white space or control character.
const CSS_COMMENT_OPEN = '/*';
const CSS_NAME = /(?:[-\w\u{80}-\u{10ffff}]|\\[0-9a-f]{1,6}(?:\r\n|[ \t\n\f\r])?|\\[^0-9a-f\n\f\r])+/iuy;
const CSS_STRING = {
  '"': /"((?:[^"\\\n\f\r]|\\\r\n|\\[\s\S])*)/y,
  "'": /'((?:[^'\\\n\f\r]|\\\r\n|\\[\s\S])*)/y,
};
const CSS_BARE_URL = /(?:[^"'()\\ \t\n\f\r\x00-\x08\x0b\x0e-\x1f\x7f]|\\[^\n\f\r])*/y;
const CSS_BAD_URL_REST = /(?:[^)\\]|\\[\s\S])*\)?/y;

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
  const imports = file.endsWith('.css') ? cssFindings(file, text, own) : styleFindings(file, text, own);
  return [...new Set([...judgedFindings(file, text, own), ...userInfoFindings(file, text, own), ...imports])];
}

function tagOpening(table) {
  return new RegExp(`<(${Object.keys(table).join('|')})(?=${TAG_DELIMITER})`, 'gi');
}

function shownText(text, start, end) {
  return text.slice(start, end).replace(/\s+/g, ' ').slice(0, SHOWN_CHARS);
}

function judgedFindings(file, text, own) {
  const lines = [];
  const open = tagOpening(JUDGED);
  const total = (text.match(open) ?? []).length;
  let found = 0;
  for (let match = open.exec(text); match !== null; match = open.exec(text)) {
    const tag = readAttributes(text, open.lastIndex);
    if (tag === null) break;
    found += 1;
    open.lastIndex = tag.end;
    const shown = shownText(text, match.index, tag.end);
    for (const finding of tagFindings(match[1].toLowerCase(), tag.attributes, own)) {
      lines.push(`${file}: ${shown} (${finding})`);
    }
  }
  if (found !== total) lines.push(`${file}: a resource tag that is not a complete tag`);
  return lines;
}

// userInfoFindings <file> <text> <own>: the user-info rule over the tags of
// USER_INFO_ONLY and every CSS url(). It never moves past a tag it read, so a
// stray quote cannot hide the next tag, and it skips a tag that never closes.
function userInfoFindings(file, text, own) {
  const lines = [];
  const judge = (url, shown) => {
    const why = urlFinding(url, own, { hostJudged: false });
    if (why !== null) lines.push(`${file}: ${shown} (${why}: ${url.slice(0, SHOWN_CHARS)})`);
  };
  const open = tagOpening(USER_INFO_ONLY);
  for (let match = open.exec(text); match !== null; match = open.exec(text)) {
    const tag = readAttributes(text, open.lastIndex);
    if (tag === null) continue;
    const names = USER_INFO_ONLY[match[1].toLowerCase()];
    for (const attribute of tag.attributes) {
      if (names.includes(attribute.name) && attribute.value !== null) {
        judge(attribute.value, shownText(text, match.index, tag.end));
      }
    }
  }
  for (const match of text.matchAll(CSS_URL)) {
    judge(unescapeCss(match[1] ?? match[2] ?? match[3]), shownText(text, match.index, match.index + match[0].length));
  }
  return lines;
}

// styleFindings <file> <text> <own>: the @import rules of every style element of
// an HTML file. The text of an element runs to its end tag, or to the end of the
// file. It never moves past an element it read, so an opening inside a comment
// cannot hide the next one; the findings of both are the same line, kept once.
function styleFindings(file, text, own) {
  const lines = [];
  const open = tagOpening(STYLE_TAG);
  for (let match = open.exec(text); match !== null; match = open.exec(text)) {
    const tag = readAttributes(text, open.lastIndex);
    if (tag === null) {
      lines.push(`${file}: a resource tag that is not a complete tag`);
      continue;
    }
    const body = text.slice(tag.end, styleEnd(text, tag.end));
    if (STYLE_NOT_CSS.test(body)) {
      lines.push(`${file}: ${shownText(text, match.index, tag.end)} (markup or a character reference inside a style element)`);
    }
    lines.push(...cssFindings(file, body, own));
  }
  return lines;
}

function styleEnd(text, from) {
  STYLE_END.lastIndex = from;
  const end = STYLE_END.exec(text);
  return end === null ? text.length : end.index;
}

// cssFindings <file> <css> <own>: the policy over the URLs cssImports found. An
// @import with no URL it could read is a finding: it fails closed. CSS has no
// character references, so an ampersand is written as &amp; for urlFinding,
// which reads values as an attribute holds them.
function cssFindings(file, css, own) {
  const lines = [];
  for (const item of cssImports(css)) {
    const shown = shownText(css, item.start, item.end);
    if (item.url === null) {
      lines.push(`${file}: ${shown} (an @import whose URL cannot be read)`);
      continue;
    }
    const why = urlFinding(item.url.replaceAll('&', '&amp;'), own, { dataAllowed: false });
    if (why !== null) lines.push(`${file}: ${shown} (${why}: ${item.url.slice(0, SHOWN_CHARS)})`);
  }
  return lines;
}

// cssImports <css>: every @import of the text as `{start, end, url}`, the url
// read from its quoted string or url(), or null when it cannot be read. It walks
// the text as the CSS tokenizer does, so an @import inside a comment or a string
// is not one, and a stray quote in a url() does not swallow the rule after it.
// An @import where CSS would ignore it, after a rule or inside a block, is still
// reported: that is the safe side.
function cssImports(css) {
  const imports = [];
  let pos = cssSkipFiller(css, 0);
  while (pos < css.length) {
    if (isCssQuote(css[pos])) {
      pos = cssString(css, pos).end;
    } else if (css[pos] === '@') {
      pos = afterAtRule(css, pos, imports);
    } else {
      const name = cssName(css, pos);
      if (name === null) {
        pos += 1;
      } else {
        pos = isCssUrl(css, name) ? cssUrlValue(css, name.end + 1).end : name.end;
      }
    }
    pos = cssSkipFiller(css, pos);
  }
  return imports;
}

// afterAtRule <css> <at> <imports>: where to go on after the @ at that position,
// adding to imports when it opens an @import.
function afterAtRule(css, at, imports) {
  const name = cssName(css, at + 1);
  if (name === null) return at + 1;
  if (name.value.toLowerCase() !== 'import') return name.end;
  const item = readImport(css, at, name.end);
  imports.push(item);
  return item.end;
}

// readImport <css> <start> <from>: the URL after an @import's name: a string, or
// url( directly after its name. Anything else, src() among it, has no URL here.
function readImport(css, start, from) {
  const pos = cssSkipFiller(css, from);
  if (isCssQuote(css[pos])) {
    const string = cssString(css, pos);
    return { start, end: string.end, url: string.text };
  }
  const name = cssName(css, pos);
  if (name !== null && isCssUrl(css, name)) {
    const value = cssUrlValue(css, name.end + 1);
    return { start, end: value.end, url: value.url };
  }
  return { start, end: name === null ? pos : name.end, url: null };
}

function isCssQuote(c) {
  return c === '"' || c === "'";
}

function isCssUrl(css, name) {
  return name.value.toLowerCase() === 'url' && css[name.end] === '(';
}

function matchAt(pattern, css, pos) {
  pattern.lastIndex = pos;
  return pattern.exec(css);
}

// cssSkipFiller <css> <from>: past white space and comments. A comment that
// never closes runs to the end of the text, as it does in a browser.
function cssSkipFiller(css, from) {
  let pos = from;
  for (;;) {
    pos = skipWhile(css, pos, isWhitespace);
    if (!css.startsWith(CSS_COMMENT_OPEN, pos)) return pos;
    const close = css.indexOf('*/', pos + CSS_COMMENT_OPEN.length);
    if (close < 0) return css.length;
    pos = close + 2;
  }
}

function cssName(css, pos) {
  const found = matchAt(CSS_NAME, css, pos);
  return found === null ? null : { value: unescapeCss(found[0]), end: pos + found[0].length };
}

// cssString <css> <from>: the string opening at from. Its text is null when a
// raw newline or the end of the text comes before the closing quote.
function cssString(css, from) {
  const found = matchAt(CSS_STRING[css[from]], css, from);
  const end = from + found[0].length;
  return css[end] === css[from] ? { text: unescapeCss(found[1]), end: end + 1 } : { text: null, end };
}

// cssUrlValue <css> <from>: the value of a url( whose parenthesis ended at from.
// Quoted, it is a function, so comments may follow the string and only the
// closing parenthesis may end it. Bare, it is one token: comments are not read in
// it, and what it cannot hold makes it unreadable (url null) up to its parenthesis.
function cssUrlValue(css, from) {
  const pos = skipWhile(css, from, isWhitespace);
  if (isCssQuote(css[pos])) {
    const string = cssString(css, pos);
    const after = cssSkipFiller(css, string.end);
    return css[after] === ')' && string.text !== null ? { url: string.text, end: after + 1 } : { url: null, end: after };
  }
  const found = matchAt(CSS_BARE_URL, css, pos);
  const after = skipWhile(css, pos + found[0].length, isWhitespace);
  if (css[after] === ')') return { url: unescapeCss(found[0]), end: after + 1 };
  return { url: null, end: after + matchAt(CSS_BAD_URL_REST, css, after)[0].length };
}

// unescapeCss <value>: the value with CSS escapes read, as a browser reads them
// before it fetches: an escaped newline is nothing, a hex escape takes the one
// white space that may end it (U+FFFD for what is no code point), and any other
// backslash is the character after it.
function unescapeCss(value) {
  return value.replace(/\\(?:\r\n|[\n\f\r])|\\([0-9a-fA-F]{1,6})(?:\r\n|[ \t\n\f\r])?|\\([\s\S])/gu, (whole, hex, char) => {
    if (char !== undefined) return char;
    if (hex === undefined) return '';
    const code = parseInt(hex, 16);
    const invalid = code === 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff);
    return invalid ? '�' : String.fromCodePoint(code);
  });
}

function skipWhile(text, from, test) {
  let at = from;
  while (at < text.length && test(text[at])) at += 1;
  return at;
}

// readAttributes <text> <from>: the tag's attributes from just after its name,
// as the HTML tokenizer's attribute states read them, and where the tag ends.
// Null when the text ends inside the tag. A name with no = has no value.
function readAttributes(text, from) {
  const attributes = [];
  const skip = (pos, test) => skipWhile(text, pos, test);
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

function isImageInput(attributes) {
  return attributes.some((attribute) => attribute.name === 'type' && attribute.value !== null
    && decodeReferences(attribute.value).toLowerCase() === 'image');
}

function tagFindings(tagName, attributes, own) {
  const findings = [];
  if (READ_WHEN[tagName]?.(attributes) === false) return findings;
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

// urlFinding <value> <own> <{dataAllowed, hostJudged}>: null when the value is
// fine, else the reason. A URL with a user name or password is a finding first,
// whatever its host. With hostJudged false that is all it asks. Otherwise the
// same policy as the gate's media_value_ok: a relative path, or https on an own
// host; a protocol-relative, http or other-scheme URL or a character reference
// other than &amp; is a finding. Hosts are read by the WHATWG URL parser, as a
// browser reads them. A data URL contacts no host, and only a srcset candidate
// may be one: an embed or object could run a data: document, and that document
// could load anything.
function urlFinding(raw, own, { dataAllowed, hostJudged = true }) {
  if (hasUserInfo(raw)) return 'a URL with a user name or password';
  if (!hostJudged) return null;
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
  return hostIsOwn(first.hostname, own) ? null : `host ${first.hostname} is not an own host`;
}

// hasUserInfo <raw>: does the WHATWG URL parser, as a browser reads the value,
// find a user name or password in it? Character references are read first, as
// the HTML parser does before any URL is parsed. Both bases are asked because
// `https:user@host` is a relative path on an https page and a user name on an
// http one. A value the parser refuses fetches nothing and has no user-info.
function hasUserInfo(raw) {
  const value = decodeReferences(raw);
  return [BASE_ONE, BASE_TWO].some((base) => {
    try {
      const url = new URL(value, base.href);
      return url.username !== '' || url.password !== '';
    } catch {
      return false;
    }
  });
}

// decodeReferences <value>: numeric character references and URL_REFERENCES
// read in one pass, so &amp;#64; stays the text &#64; as it does in a browser.
function decodeReferences(value) {
  return value.replace(/&#x([0-9a-f]+);?|&#([0-9]+);?|&([A-Za-z]+);/gi, (whole, hex, decimal, name) => {
    if (name !== undefined) return URL_REFERENCES[name] ?? whole;
    const code = hex !== undefined ? parseInt(hex, 16) : parseInt(decimal, 10);
    return code <= 0x10ffff ? String.fromCodePoint(code) : whole;
  });
}

function hostIsOwn(host, own) {
  return own.hosts.has(host)
    || own.suffixes.some((suffix) => host.length > suffix.length + 1 && host.endsWith(`.${suffix}`));
}

main();
