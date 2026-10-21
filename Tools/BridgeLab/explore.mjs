// BridgeLab explorer: loads chess.com/play/computer as a guest and dumps DOM + game API facts.
// Usage: node explore.mjs <profile> <outdir>   profile = webkit-iphone | chromium-iphone | chromium-desktop
import { webkit, chromium, devices } from 'playwright';
import fs from 'node:fs';

const profile = process.argv[2] || 'webkit-iphone';
const out = process.argv[3] || 'out';
fs.mkdirSync(out, { recursive: true });
const log = (...a) => { const s = a.map(x => typeof x === 'string' ? x : JSON.stringify(x)).join(' '); console.log(`[${profile}] ${s}`); fs.appendFileSync(`${out}/log.txt`, s + '\n'); };
const save = (name, obj) => fs.writeFileSync(`${out}/${name}`, typeof obj === 'string' ? obj : JSON.stringify(obj, null, 2));

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

save('ui-0.json', await page.evaluate(DUMP_UI));
save('api-setup.json', await page.evaluate(PROBE_API));

// Walk the setup flow by clicking likely buttons.
const clicks = [];
for (let i = 0; i < 10; i++) {
  const ui = await page.evaluate(DUMP_UI);
  save(`ui-${i + 1}.json`, ui);
  const playing = await page.evaluate(() => { const b = document.querySelector('wc-chess-board'); try { return !!(b && b.game && b.game.getPlayingAs && b.game.getPlayingAs()); } catch (e) { return false; } });
  const cand = ui.buttons.find(b => /^(play|choose|start|continue|let's go!?|skip|got it|close|no thanks)$/i.test(b.text) || /play|choose|start/i.test(b.cy || ''));
  log('iter', i, 'playing?', playing, 'cand', cand);
  if (!cand) break;
  try {
    if (cand.cy) await page.click(`[data-cy="${cand.cy}"]`, { timeout: 5000 });
    else await page.getByRole('button', { name: cand.text, exact: true }).first().click({ timeout: 5000 });
    clicks.push(cand.text || cand.cy);
  } catch (e) { log('click fail', e.message.slice(0, 200)); break; }
  await page.waitForTimeout(2500);
  await snap(`step${i}`);
}
log('clicks', clicks);
save('api-game.json', await page.evaluate(PROBE_API));
save('board-dom.json', await page.evaluate(DUMP_BOARD_DOM));
save('html-game.html', await page.content());

// Try a move via the game API if present, observing events.
const moveTry = await page.evaluate(async () => {
  const b = document.querySelector('wc-chess-board'); const g = b && b.game; if (!g) return 'no game';
  const ev = [];
  const names = ['Move', 'move', 'ModeChanged', 'GameOver', 'ResetGame', 'LoadFen', 'UpdateOptions', 'MoveBackward', 'MoveForward', 'all'];
  const listen = [];
  for (const n of names) { try { if (g.on) { g.on(n, (e) => ev.push({ n, e: JSON.stringify(e, (k, v) => typeof v === 'function' ? '[fn]' : (k === 'game' ? '[game]' : v))?.slice(0, 500) })); listen.push(n); } } catch (e) { listen.push(n + ':ERR ' + e.message); } }
  const r = { listen };
  try { r.fenBefore = g.getFEN(); } catch (e) { r.fenErr = e.message; }
  try { r.playingAs = g.getPlayingAs(); } catch (e) { }
  try { r.turn = g.getTurn(); } catch (e) { }
  let lm; try { lm = g.getLegalMoves(); r.legalSample = JSON.stringify(lm.slice(0, 3)).slice(0, 800); r.legalCount = lm.length; } catch (e) { r.legalErr = e.message; }
  const mine = r.playingAs === r.turn;
  r.mine = mine;
  if (lm && lm.length && mine) {
    const m = lm.find(x => x.from === 'e2' && x.to === 'e4') || lm.find(x => x.from === 'e7' && x.to === 'e5') || lm[0];
    try { r.moveRet = JSON.stringify(g.move({ ...m, userGenerated: true, animate: false }), (k, v) => typeof v === 'function' ? '[fn]' : v)?.slice(0, 500); } catch (e) { r.moveErr = e.message; }
  }
  await new Promise(res => setTimeout(res, 8000));
  try { r.fenAfter = g.getFEN(); } catch (e) { }
  r.events = ev.slice(0, 30);
  window.__ev = ev;
  return r;
});
save('move-try.json', moveTry);
log('moveTry', moveTry);
await snap('after-move');
save('board-dom-after.json', await page.evaluate(DUMP_BOARD_DOM));
save('api-after.json', await page.evaluate(PROBE_API));
log('done', Date.now() - t0, 'ms');
await browser.close();
