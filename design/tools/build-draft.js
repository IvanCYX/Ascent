#!/usr/bin/env node
// Renders the r3 design canvas into one static page, design/draft.html.
//
//   node design/tools/build-draft.js <canvas project dir> design/draft.html
//
// The canvas dir is the canvas Artifact's `project/` folder (canvas.json plus one .dc.html per board), as saved by
// reading the Artifact. Each board's script runs once with its default props; its template is filled in and the
// result is embedded as a sandboxed iframe, so board styles never clash. Clicks inside a frame jump to the frame
// they link to. Boards listed in SUPERSEDED are left out.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const SUPERSEDED = {
  'Progress.dc.html': 'replaced by Progress detail · by scale',
  'NormalGrade.dc.html': 'replaced by Your normal grade · all scales',
};

const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);
const RAW = new Set(['style', 'script']);

/* ── Parsing ─────────────────────────────────────────────────────────── */

function parseAttrs(src) {
  const attrs = [];
  const re = /([^\s=\/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
  let m;
  while ((m = re.exec(src))) attrs.push({ name: m[1], value: m[2] ?? m[3] ?? m[4] ?? null });
  return attrs;
}

/** A small HTML tree: { tag, attrs, children } or { text }. The format requires closed, quoted markup. */
function parse(html) {
  const root = { tag: '#root', attrs: [], children: [] };
  const stack = [root];
  let i = 0;
  while (i < html.length) {
    const top = stack[stack.length - 1];
    if (html.startsWith('<!--', i)) {
      const end = html.indexOf('-->', i);
      i = end < 0 ? html.length : end + 3;
      continue;
    }
    if (html[i] === '<' && html[i + 1] === '/') {
      const end = html.indexOf('>', i);
      const name = html.slice(i + 2, end).trim();
      i = end + 1;
      for (let k = stack.length - 1; k > 0; k--) {
        if (stack[k].tag === name) { stack.length = k; break; }
      }
      continue;
    }
    if (html[i] === '<' && /[A-Za-z]/.test(html[i + 1] || '')) {
      // find the tag end, skipping quoted attribute values
      let j = i + 1, q = null;
      for (; j < html.length; j++) {
        const c = html[j];
        if (q) { if (c === q) q = null; } else if (c === '"' || c === "'") q = c; else if (c === '>') break;
      }
      const inner = html.slice(i + 1, j);
      const selfClose = inner.endsWith('/');
      const nameMatch = /^[^\s\/>]+/.exec(inner);
      const tag = nameMatch[0];
      const node = { tag, attrs: parseAttrs(inner.slice(tag.length).replace(/\/$/, '')), children: [] };
      top.children.push(node);
      i = j + 1;
      if (RAW.has(tag.toLowerCase())) {
        const close = html.indexOf(`</${tag}>`, i);
        node.children.push({ text: html.slice(i, close) });
        i = close + tag.length + 3;
      } else if (!selfClose && !VOID.has(tag.toLowerCase())) {
        stack.push(node);
      }
      continue;
    }
    const next = html.indexOf('<', i + 1);
    const end = next < 0 ? html.length : next;
    top.children.push({ text: html.slice(i, end) });
    i = end;
  }
  return root;
}

/* ── Rendering ───────────────────────────────────────────────────────── */

const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const HOLE = /\{\{\s*([^}]+?)\s*\}\}/g;

function lookup(expr, scopes) {
  const e = expr.trim();
  if (e === 'true') return true;
  if (e === 'false') return false;
  if (e === 'null') return null;
  if (/^-?\d+(\.\d+)?$/.test(e)) return Number(e);
  if (/^(['"]).*\1$/.test(e)) return e.slice(1, -1);
  const [head, ...rest] = e.split('.');
  let v;
  for (let k = scopes.length - 1; k >= 0; k--) if (head in scopes[k]) { v = scopes[k][head]; break; }
  for (const key of rest) v = v == null ? undefined : v[key];
  return v;
}

const fill = (s, scopes) => s.replace(HOLE, (_, e) => {
  const v = lookup(e, scopes);
  return v == null || typeof v === 'function' ? '' : esc(v);
});

function renderAttrs(attrs, scopes, linkFor) {
  let out = '';
  for (const { name, value } of attrs) {
    if (/^hint-/.test(name)) continue;
    if (value == null) { out += ` ${name}`; continue; }
    const whole = /^\{\{\s*([^}]+?)\s*\}\}$/.exec(value);
    if (/^on[A-Z]/.test(name)) continue; // event handlers do nothing in a static frame
    if (whole) {
      const v = lookup(whole[1], scopes);
      if (v == null || typeof v === 'function') continue;
      if (v === false && !name.startsWith('aria-')) continue;
      if (v === true && !name.startsWith('aria-')) { out += ` ${name}`; continue; }
      out += ` ${name}="${esc(v)}"`;
      continue;
    }
    if (name === 'href' && /\.dc\.html$/.test(value)) {
      out += ` href="#${linkFor(value)}" target="_top"`;
      continue;
    }
    out += ` ${name}="${fill(value, scopes)}"`;
  }
  return out;
}

function render(node, scopes, linkFor) {
  if (node.text != null) return fill(node.text, scopes);
  const kids = () => node.children.map(c => render(c, scopes, linkFor)).join('');
  if (node.tag === '#root') return kids();
  if (node.tag === 'helmet') return '';
  if (node.tag === 'sc-if') {
    const v = node.attrs.find(a => a.name === 'value');
    const m = v && /^\{\{\s*([^}]+?)\s*\}\}$/.exec(v.value);
    return m && lookup(m[1], scopes) ? kids() : '';
  }
  if (node.tag === 'sc-for') {
    const list = node.attrs.find(a => a.name === 'list');
    const as = (node.attrs.find(a => a.name === 'as') || {}).value || 'item';
    const m = list && /^\{\{\s*([^}]+?)\s*\}\}$/.exec(list.value);
    const items = (m && lookup(m[1], scopes)) || [];
    return items.map((item, $index) =>
      node.children.map(c => render(c, [...scopes, { [as]: item, $index }], linkFor)).join('')).join('');
  }
  const open = `<${node.tag}${renderAttrs(node.attrs, scopes, linkFor)}>`;
  if (VOID.has(node.tag.toLowerCase())) return open;
  return `${open}${kids()}</${node.tag}>`;
}

/* ── One board ───────────────────────────────────────────────────────── */

const decode = s => s.replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, '&');

function renderBoard(file, linkFor) {
  const src = fs.readFileSync(file, 'utf8');
  const title = (/<title>([\s\S]*?)<\/title>/.exec(src) || [])[1] || '';
  const body = /<x-dc>([\s\S]*?)<\/x-dc>/.exec(src)[1];
  const helmet = (/<helmet>([\s\S]*?)<\/helmet>/.exec(body) || [])[1] || '';
  const scriptMatch = /<script type="text\/x-dc"[^>]*?data-props='([^']*)'[^>]*>([\s\S]*?)<\/script>/.exec(src);
  let vals = {};
  if (scriptMatch) {
    const defs = JSON.parse(decode(scriptMatch[1]));
    const props = {};
    for (const [k, d] of Object.entries(defs)) if (!k.startsWith('$') && d && 'default' in d) props[k] = d.default;
    const sandbox = {
      Math, JSON, Number, String, Array, Object, Date, parseInt, parseFloat, isNaN,
      DCLogic: class { constructor(p) { this.props = p || {}; this.state = {}; } setState() {} forceUpdate() {} },
    };
    vm.createContext(sandbox);
    const Component = vm.runInContext(`${scriptMatch[2]}\n;Component`, sandbox, { filename: path.basename(file) });
    vals = new Component(props).renderVals();
  }
  const scopes = [vals];
  const tree = parse(body);
  const html = render(tree, scopes, linkFor);
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>${title}</title>`
    + `<style>html,body{margin:0}</style>${fill(helmet, scopes)}</head><body>${html.trim()}</body></html>`;
}

/* ── The page ────────────────────────────────────────────────────────── */

function main() {
  const [dir, out] = process.argv.slice(2);
  if (!dir || !out) { console.error('usage: build-draft.js <canvas project dir> <out.html>'); process.exit(1); }
  const canvas = JSON.parse(fs.readFileSync(path.join(dir, 'canvas.json'), 'utf8'));
  const slug = f => 'frame-' + f.replace(/\.dc\.html$/, '').replace(/[^A-Za-z0-9]+/g, '-').toLowerCase();
  const titles = Object.values(canvas.notes || {}).filter(n => n.kind === 'title1').sort((a, b) => a.y - b.y);
  const rowOf = b => {
    let row = 0;
    titles.forEach((t, i) => { if (b.y >= t.y) row = i; });
    return row;
  };
  const rows = titles.map(t => ({ title: t.text, boards: [] }));
  for (const [file, b] of Object.entries(canvas.boards)) {
    if (SUPERSEDED[file]) continue;
    rows[rowOf(b)].boards.push({ file, ...b });
  }
  rows.forEach(r => r.boards.sort((a, b) => a.y - b.y || a.x - b.x));

  const frames = rows.map((r, ri) => {
    const figs = r.boards.map(b => {
      const doc = renderBoard(path.join(dir, b.file), slug);
      return `
      <figure class="frame" id="${slug(b.file)}">
        <figcaption>${esc(b.title || b.file)}</figcaption>
        <div class="screen" style="max-width:${b.w}px">
          <iframe title="${esc(b.title || b.file)}" width="${b.w}" height="${b.h}" loading="lazy" sandbox="allow-top-navigation-by-user-activation" srcdoc="${esc(doc)}"></iframe>
        </div>
      </figure>`;
    }).join('');
    return `
    <section class="row" id="row-${ri + 1}" aria-labelledby="row-${ri + 1}-title">
      <h2 id="row-${ri + 1}-title">${esc(r.title)}</h2>
      <div class="frames">${figs}
      </div>
    </section>`;
  }).join('');

  const toc = rows.map((r, ri) => `<a href="#row-${ri + 1}">${esc(r.title)}</a>`).join('');
  const left = Object.entries(SUPERSEDED).map(([f, why]) => `${f.replace('.dc.html', '')} (${why})`).join('; ');
  const built = new Date().toISOString().slice(0, 10);

  const page = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ascent design draft</title>
<!-- Generated by design/tools/build-draft.js from the r3 design canvas. Do not edit by hand; rebuild instead. -->
<style>
:root{
  --ground:#F5F5F4; --surface:#FFFFFF; --text:#0E1013; --secondary:#5F5E5A; --hairline:rgba(14,16,19,.08);
  --font:-apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue",sans-serif;
  color-scheme:light;
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){ --ground:#0A0A0A; --surface:#161616; --text:#F2F3F5; --secondary:#A1A1A1; --hairline:rgba(255,255,255,.08); color-scheme:dark; }
}
:root[data-theme="dark"]{ --ground:#0A0A0A; --surface:#161616; --text:#F2F3F5; --secondary:#A1A1A1; --hairline:rgba(255,255,255,.08); color-scheme:dark; }
*,*::before,*::after{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;background:var(--ground);color:var(--text);font:400 15px/1.5 var(--font);-webkit-font-smoothing:antialiased}
.wrap{max-width:2000px;margin:0 auto;padding:0 16px 96px}
header{padding:48px 0 20px}
h1{font-size:34px;line-height:1.1;font-weight:700;letter-spacing:-.02em;margin:0}
header p{max-width:720px;margin:12px 0 0;color:var(--secondary);text-wrap:pretty}
nav{position:sticky;top:0;z-index:2;display:flex;flex-wrap:wrap;gap:6px;padding:12px 0;background:var(--ground);border-bottom:1px solid var(--hairline)}
nav a{color:var(--text);text-decoration:none;font-size:14px;font-weight:600;padding:8px 14px;border-radius:18px;background:var(--surface)}
nav a:hover{opacity:.8}
nav a:focus-visible{outline:2px solid var(--text);outline-offset:2px}
.row{padding-top:40px;scroll-margin-top:120px}
h2{font-size:24px;font-weight:700;letter-spacing:-.01em;margin:0 0 20px}
.frames{display:flex;flex-wrap:wrap;gap:40px 32px;align-items:flex-start}
.frame{margin:0;min-width:0;max-width:100%;scroll-margin-top:130px}
figcaption{font-size:13px;font-weight:600;color:var(--secondary);margin:0 0 10px}
.screen{overflow-x:auto;border-radius:24px;box-shadow:0 0 0 1px var(--hairline)}
iframe{display:block;border:0;border-radius:24px}
footer{margin-top:48px;color:var(--secondary);font-size:13px}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>Ascent design draft</h1>
    <p>Every screen of the current r3 design, rendered from the design canvas on ${built}. The written spec is
    <code>design/DESIGN.md</code>; the canvas is the editable source. Frames are static: tap a tab or a link inside one to
    jump to the frame it opens.</p>
  </header>
  <nav aria-label="Rows">${toc}</nav>
  <main>${frames}
  </main>
  <footer>Left out as superseded: ${esc(left)}. Rebuild with <code>node design/tools/build-draft.js &lt;canvas project dir&gt; design/draft.html</code>.</footer>
</div>
</body>
</html>
`;
  fs.writeFileSync(out, page);
  console.log(`wrote ${out}: ${rows.reduce((n, r) => n + r.boards.length, 0)} frames in ${rows.length} rows, ${(page.length / 1024).toFixed(0)} KB`);
}

main();
