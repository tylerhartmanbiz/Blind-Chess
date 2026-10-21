// BridgeLab explorer: loads chess.com/play/computer as a guest and dumps DOM + game API facts.
// Usage: node explore.mjs <profile> <outdir>   profile = webkit-iphone | chromium-iphone | chromium-desktop
import { webkit, chromium, devices } from 'playwright';
import fs from 'node:fs';

const profile = process.argv[2] || 'webkit-iphone';
const out = process.argv[3] || 'out';
fs.mkdirSync(out, { recursive: true });
const log = (...a) => { const s = a.map(x => typeof x === 'string' ? x : JSON.stringify(x)).join(' '); console.log(`[${profile}] ${s}`); fs.appendFileSync(`${out}/log.txt`, s + '\n'); };
const save = (name, obj, print = true) => { const txt = typeof obj === 'string' ? obj : JSON.stringify(obj); fs.writeFileSync(`${out}/${name}`, txt); if (print && !name.endsWith('.html')) console.log(`[${profile}] FILE ${name} ${txt.slice(0, 12000)}`); };

const engine = profile.startsWith('webkit') ? webkit : chromium;
const ctxOpts = profile.endsWith('iphone') ? { ...devices['iPhone 13'] } : { viewport: { width: 1280, height: 900 } };
ctxOpts.locale = 'en-US';
const headless = process.env.HEADED !== '1';
const browser = await engine.launch({ headless });
const ctx = await browser.newContext(ctxOpts);
const page = await ctx.newPage();
page.on('console', m => { if (m.type() === 'error') fs.appendFileSync(`${out}/console.txt`, m.text() + '\n'); });
let shot = 0;
const snap = async (label) => { try { await page.screenshot({ path: `${out}/${String(++shot).padStart(2, '0')}-${label}.png` }); } catch (e) { log('shot fail', e.message); } };

const t0 = Date.now();
let resp;
try { resp = await page.goto('https://www.chess.com/play/computer', { waitUntil: 'domcontentloaded', timeout: 60000 }); }
catch (e) { log('goto error', e.message); }
log('status', resp && resp.status(), 'url', page.url(), 'ms', Date.now() - t0);
await page.waitForTimeout(8000);
await snap('loaded');
const title = await page.title();
const bodyText = (await page.evaluate(() => document.body ? document.body.innerText.slice(0, 3000) : '')) || '';
log('title', title);
const challenged = /just a moment|verify you are human|attention required|cf-chl|captcha/i.test(title + bodyText);
log('challenge?', challenged);
save('body-initial.txt', bodyText);
save('html-initial.html', await page.content());

const DUMP_UI = () => {
  const vis = el => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  const buttons = [...document.querySelectorAll('button, [role=button], a.cc-button-component')].filter(vis).slice(0, 80).map(b => ({
    text: (b.innerText || b.getAttribute('aria-label') || '').trim().slice(0, 60), cls: String(b.className).slice(0, 120),
    cy: b.getAttribute('data-cy'), aria: b.getAttribute('aria-label') }));
  const modals = [...document.querySelectorAll('[class*=modal], [class*=Modal], [role=dialog]')].filter(vis).map(m => ({ cls: String(m.className).slice(0, 120), text: m.innerText.slice(0, 300) }));
  const board = document.querySelector('wc-chess-board, chess-board, #board-single, .board');
  return { url: location.href, buttons, modals, boardTag: board && board.tagName, boardId: board && board.id, boardCls: board && String(board.className),
    hasGame: !!(board && board.game), customEls: [...new Set([...document.querySelectorAll('*')].map(e => e.tagName.toLowerCase()).filter(t => t.includes('-')))] };
};
const PROBE_API = () => {
  const res = {};
  const board = document.querySelector('wc-chess-board') || document.querySelector('chess-board');
  if (!board) return { noBoard: true };
  const chain = (o) => { const out = []; let p = o, d = 0; while (p && p !== Object.prototype && d < 8) { out.push({ ctor: p.constructor && p.constructor.name, props: Object.getOwnPropertyNames(p).map(n => { let t; try { const desc = Object.getOwnPropertyDescriptor(p, n); t = desc.get ? 'getter' : typeof desc.value; } catch (e) { t = '?'; } return n + ':' + t; }) }); p = Object.getPrototypeOf(p); d++; } return out; };
  res.boardChain = chain(board).map(c => ({ ctor: c.ctor, props: c.props.filter(x => !/^(on|aria|webkit)/.test(x)).slice(0, 200) })).slice(0, 2);
  res.boardOwnKeys = Object.keys(board).slice(0, 100);
  const g = board.game;
  res.gameType = typeof g;
  if (!g) return res;
  res.gameChain = chain(g);
  res.gameOwnKeys = Object.keys(g);
  const calls = {};
  const seen = new Set();
  let p = g;
  while (p && p !== Object.prototype) {
    for (const n of Object.getOwnPropertyNames(p)) {
      if (seen.has(n)) continue; seen.add(n);
      if (!/^(get|is|has|can)/.test(n)) continue;
      let f; try { f = g[n]; } catch (e) { continue; }
      if (typeof f !== 'function' || f.length > 0) continue;
      try { let v = f.call(g); let s; try { s = JSON.stringify(v, (k, val) => typeof val === 'function' ? '[fn]' : val); } catch (e) { s = String(v); } calls[n] = (s === undefined ? 'undefined' : s).slice(0, 400); }
      catch (e) { calls[n] = 'THROW ' + e.message; }
    }
    p = Object.getPrototypeOf(p);
  }
  res.calls = calls;
  for (const n of ['move', 'on', 'off', 'addListener', 'removeListener', 'emit', 'getLegalMoves', 'resign', 'undo', 'takeback', 'load', 'setOptions', 'getOptions', 'markings', 'moveForward', 'moveBackward']) {
    try { res['src_' + n] = typeof g[n] === 'function' ? g[n].toString().slice(0, 600) : typeof g[n]; } catch (e) { res['src_' + n] = 'ERR'; }
  }
  return res;
};
const DUMP_BOARD_DOM = () => {
  const board = document.querySelector('wc-chess-board') || document.querySelector('chess-board');
  if (!board) return null;
  const pieces = [...board.querySelectorAll('.piece')].slice(0, 4).map(p => p.outerHTML.slice(0, 300));
  const children = [...board.children].map(c => c.tagName + '.' + String(c.className.baseVal ?? c.className).slice(0, 80));
  const r = board.getBoundingClientRect();
  const ml = document.querySelector('wc-simple-move-list, .move-list, vertical-move-list, wc-vertical-move-list, .play-controller-moves');
  return { rect: [r.x, r.y, r.width, r.height], flipped: board.classList.contains('flipped'), children, pieces, shadow: !!board.shadowRoot,
    moveListTag: ml && ml.tagName, moveListCls: ml && String(ml.className), moveListHTML: ml && ml.outerHTML.slice(0, 2500) };
};

const SIDEBAR = () => {
  const sb = document.querySelector('.board-layout-sidebar, #board-layout-sidebar, [class*=sidebar]');
  const vis = el => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  const colorEls = [...document.querySelectorAll('[class*=color], [data-cy*=color], [class*=Color]')].filter(vis).slice(0, 20).map(e => ({ tag: e.tagName, cls: String(e.className).slice(0, 100), text: (e.innerText || '').slice(0, 40), aria: e.getAttribute('aria-label'), cy: e.getAttribute('data-cy') }));
  const bots = [...document.querySelectorAll('[class*=bot-]')].filter(vis).slice(0, 15).map(e => ({ tag: e.tagName, cls: String(e.className).slice(0, 100), text: (e.innerText || '').slice(0, 40), attrs: [...e.attributes].map(a => a.name + '=' + a.value.slice(0, 40)).join(' ') }));
  return { sidebarCls: sb && String(sb.className).slice(0, 100), sidebarText: sb ? sb.innerText.slice(0, 1500) : null, colorEls, bots };
};
const gstate = () => { const b = document.querySelector('wc-chess-board'); const g = b && b.game; if (!g) return null; const r = {}; for (const n of ['getFEN', 'getPlayingAs', 'getTurn', 'isGameOver', 'getResult', 'getMode', 'getHistorySANs', 'getPGN']) { try { r[n] = typeof g[n] === 'function' ? g[n]() : 'n/a'; } catch (e) { r[n] = 'THROW ' + e.message; } } try { r.modeName = g.getMode && g.getMode().name; } catch (e) { } return JSON.stringify(r).slice(0, 1500); };

save('ui-0.json', await page.evaluate(DUMP_UI));
save('sidebar-0.json', await page.evaluate(SIDEBAR));
log('gstate0', await page.evaluate(gstate));
save('api-setup.json', await page.evaluate(PROBE_API));
save('board-dom-setup.json', await page.evaluate(DUMP_BOARD_DOM));

// Walk the setup flow by clicking likely buttons with a JS click (Playwright click timed out on an overlay before).
const clicks = [];
for (let i = 0; i < 8; i++) {
  const ui = await page.evaluate(DUMP_UI);
  const cand = ui.buttons.find(b => /^(close|play|choose|start|continue|let's go!?|skip|got it|no thanks|start game)$/i.test(b.text));
  log('iter', i, 'cand', cand && cand.text, 'gstate', await page.evaluate(gstate));
  if (!cand) break;
  if (i === 2) { save('sidebar-2.json', await page.evaluate(SIDEBAR)); }
  const ok = await page.evaluate((t) => { const vis = el => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
    const b = [...document.querySelectorAll('button, [role=button], a.cc-button-component')].filter(vis).find(x => (x.innerText || x.getAttribute('aria-label') || '').trim() === t);
    if (!b) return false; b.click(); return true; }, cand.text);
  clicks.push(cand.text + (ok ? '' : '(miss)'));
  await page.waitForTimeout(2500);
  save(`sidebar-after-${i}.json`, await page.evaluate(SIDEBAR));
  await snap(`step${i}`);
}
log('clicks', clicks);
save('api-game.json', await page.evaluate(PROBE_API));
save('board-dom.json', await page.evaluate(DUMP_BOARD_DOM));

// Play a few moves through the API, then resign via the UI and observe the game-over flow.
const play = await page.evaluate(async () => {
  const b = document.querySelector('wc-chess-board'); const g = b && b.game; if (!g) return 'no game';
  const ev = []; window.__ev = ev;
  g.on('all', (e) => ev.push({ type: e.type, d: JSON.stringify(e.data, (k, v) => typeof v === 'function' ? '[fn]' : v)?.slice(0, 300) }));
  const out = [];
  for (let k = 0; k < 6; k++) {
    for (let w = 0; w < 40 && g.getTurn() !== g.getPlayingAs(); w++) await new Promise(r => setTimeout(r, 250));
    const lm = g.getLegalMoves(); if (!lm.length) break;
    const m = lm[Math.floor(lm.length / 2)];
    try { g.move({ from: m.from, to: m.to, userGenerated: true, animate: false }); out.push(m.san); } catch (e) { out.push('ERR ' + e.message); }
    await new Promise(r => setTimeout(r, 1500));
  }
  return { out, fen: g.getFEN(), types: [...new Set(ev.map(e => e.type))] };
});
log('play', play);
save('board-dom-mid.json', await page.evaluate(DUMP_BOARD_DOM));
save('ui-mid.json', await page.evaluate(DUMP_UI));
// find resign control
const resign = await page.evaluate(async () => {
  const vis = el => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  const all = [...document.querySelectorAll('button, [role=button], [aria-label], [data-cy]')].filter(vis);
  const cands = all.filter(e => /resign|abort|flag/i.test((e.getAttribute('aria-label') || '') + (e.getAttribute('data-cy') || '') + (e.innerText || '') + String(e.className)));
  const info = cands.slice(0, 10).map(e => ({ tag: e.tagName, aria: e.getAttribute('aria-label'), cy: e.getAttribute('data-cy'), text: (e.innerText || '').slice(0, 30), cls: String(e.className).slice(0, 100) }));
  const btn = cands.find(e => e.tagName === 'BUTTON') || cands[0];
  if (btn) btn.click();
  await new Promise(r => setTimeout(r, 1500));
  const after = [...document.querySelectorAll('button')].filter(vis).map(e => (e.innerText || e.getAttribute('aria-label') || '').trim()).filter(Boolean).slice(0, 40);
  const yes = [...document.querySelectorAll('button')].filter(vis).find(e => /^(yes|resign|confirm)$/i.test((e.innerText || '').trim()));
  if (yes) { yes.click(); }
  await new Promise(r => setTimeout(r, 3000));
  return { info, clicked: btn && (btn.getAttribute('aria-label') || btn.innerText), after, confirmed: yes && yes.innerText };
});
log('resign', resign);
await snap('after-resign');
log('gstate-over', await page.evaluate(gstate));
log('events', await page.evaluate(() => (window.__ev || []).filter(e => !/UpdateModeOptions|Highlight|Marking|Arrow/.test(e.type)).slice(-25)));
save('ui-over.json', await page.evaluate(DUMP_UI));
save('api-over.json', await page.evaluate(PROBE_API));
save('body-over.txt', await page.evaluate(() => document.body.innerText.slice(0, 2500)));
save('html-over.html', await page.content());
log('done', Date.now() - t0, 'ms');
await browser.close();
