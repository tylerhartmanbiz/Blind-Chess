// BridgeLab end-to-end test of "Blind Chess/Resources/chesscom-bridge.js" against the live
// https://www.chess.com/play/computer as a guest, in WebKit with iPhone emulation.
// Usage: node test.mjs <profile> <outdir>
// Prints compact "RESULT" / "GAME" / "SUMMARY" lines (the CI log is the report).
import { webkit, chromium, devices } from 'playwright';
import { Chess } from 'chess.js';
import fs from 'node:fs';
import path from 'node:path';

const profile = process.argv[2] || 'webkit-iphone';
const out = process.argv[3] || 'out';
fs.mkdirSync(out, { recursive: true });
const BRIDGE = fs.readFileSync(path.resolve('../../Blind Chess/Resources/chesscom-bridge.js'), 'utf8');
const t0 = Date.now();
const el = () => ((Date.now() - t0) / 1000).toFixed(0) + 's';
const log = (...a) => console.log(`[${el()}] ` + a.map(x => typeof x === 'string' ? x : JSON.stringify(x)).join(' '));
const results = [];
const result = (name, pass, detail = '') => { results.push({ name, pass, detail }); log('RESULT', pass ? 'PASS' : 'FAIL', name, typeof detail === 'string' ? detail : JSON.stringify(detail)); };
const coverage = { castleK: 0, castleQ: 0, enPassant: 0, promoQ: 0, promoN: 0, promoR: 0, promoB: 0, checksGiven: 0, checksReceived: 0, domFallbackMoves: 0 };
const fenMismatch = []; const legalMismatch = []; const games = [];
const sleep = ms => new Promise(r => setTimeout(r, ms));

const engine = profile.startsWith('webkit') ? webkit : chromium;
const browser = await engine.launch({ headless: process.env.HEADED !== '1' });
const ctx = await browser.newContext({ ...devices['iPhone 13'], locale: 'en-US' });
// Fake WKScriptMessageHandler so we can count native-bound messages.
await ctx.addInitScript(() => {
  window.__posted = [];
  if (!window.webkit) window.webkit = {};
  if (!window.webkit.messageHandlers) window.webkit.messageHandlers = {};
  window.webkit.messageHandlers.blindChess = { postMessage: (m) => window.__posted.push(m) };
});
// Inject at document start, before the board exists (like a WKUserScript at .atDocumentStart).
await ctx.addInitScript({ content: BRIDGE });
const page = await ctx.newPage();
page.on('pageerror', e => log('pageerror', String(e).slice(0, 200)));

const S = () => page.evaluate(() => window.BlindChess && window.BlindChess.state());
const M = (uci, opts) => page.evaluate(([u, o]) => window.BlindChess.move(u, o), [uci, opts || {}]);
const EV = (since = 0) => page.evaluate((s) => window.BlindChess ? window.BlindChess.eventsSince(s) : [], since);
const lastSeq = async () => page.evaluate(() => { const e = window.BlindChess && window.BlindChess.events; return e && e.length ? e[e.length - 1].seq : 0; });
const shot = async (n) => { try { await page.screenshot({ path: `${out}/${n}.png` }); } catch (e) { } };
async function waitFor(fn, ms = 30000, step = 200) { const end = Date.now() + ms; while (Date.now() < end) { const v = await fn(); if (v) return v; await sleep(step); } return null; }

// ------------------------------------------------------------- move policy
const VAL = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };
function uciOf(m) { return m.from + m.to + (m.promotion || ''); }
const SCRIPTS = { wk: ['g1f3', 'e2e3', 'f1e2', 'e1g1'], wq: ['d2d4', 'b1c3', 'c1f4', 'd1d2', 'e1c1'], bk: ['g8f6', 'e7e6', 'f8e7', 'e8g8'], bq: ['d7d5', 'b8c6', 'c8f5', 'd8d7', 'e8c8'] };
let script = null;
function pickMove(fen, seenFens) {
  const c = new Chess(fen);
  const moves = c.moves({ verbose: true });
  const legalU = moves.map(uciOf);
  const scripted = script ? script.find(u => legalU.includes(u) && !script.done.has(u)) : null;
  let best = null, bestScore = -1e9;
  for (const m of moves) {
    let s = 0;
    if (m.captured) s += VAL[m.captured];
    if (m.promotion) {
      s += VAL[m.promotion] - 1;
      // coverage-driven underpromotion: knight, rook, bishop once each, then queens
      const want = !coverage.promoN ? 'n' : !coverage.promoR ? 'r' : !coverage.promoB ? 'b' : 'q';
      if (m.promotion === want) s += 12;
    }
    if (m.flags.includes('e')) s += 20;
    if (scripted && uciOf(m) === scripted) s += 25;
    if (m.flags.includes('k') && !coverage.castleK) s += 15;
    if (m.flags.includes('q') && !coverage.castleQ) s += 15;
    if (m.flags.includes('k') || m.flags.includes('q')) s += 1;
    if (m.piece === 'p') { const r = parseInt(m.to[1], 10); s += 0.15 * (m.color === 'w' ? r : 9 - r); }
    c.move(m);
    if (c.isCheckmate()) { c.undo(); return m; }
    if (c.inCheck()) s += 0.3;
    if (c.isStalemate() || c.isThreefoldRepetition() || c.isInsufficientMaterial()) s -= 30;
    if (seenFens.has(c.fen().split(' ').slice(0, 4).join(' '))) s -= 2;
    let worst = 0;
    for (const r of c.moves({ verbose: true })) {
      let loss = r.captured ? VAL[r.captured] : 0;
      if (r.promotion) loss += VAL[r.promotion] - 1;
      c.move(r); if (c.isCheckmate()) loss = 1000; c.undo();
      if (loss > worst) worst = loss;
    }
    c.undo();
    s -= worst;
    if (scripted && uciOf(m) === scripted && worst > (m.captured ? VAL[m.captured] : 0)) s -= 25;
    s += Math.random() * 0.05;
    if (s > bestScore) { bestScore = s; best = m; }
  }
  return best;
}
const norm = f => f.split(' ').slice(0, 3).join(' ');

// ------------------------------------------------------------------ helpers
async function dismissModals() { await page.evaluate(() => window.BlindChess && window.BlindChess.closeModal()); }
async function ensureGame(color, label) {
  // Bring the page into phase 'playing' with the requested colour.
  let st = await S();
  if (st.phase === 'playing' && st.ply === 0 && (!color || st.playingAs === color[0])) return st;
  if (st.phase === 'playing' && st.ply > 0) { await page.evaluate(() => window.BlindChess.resign()); await waitFor(async () => (await S()).phase === 'over', 10000); st = await S(); }
  const r = await page.evaluate((c) => window.BlindChess.startNewGame({ color: c }), color);
  log('startNewGame', label, color, r);
  const ok = await waitFor(async () => { const s = await S(); return s.phase === 'playing' ? s : null; }, 20000);
  await dismissModals();
  return ok || await S();
}

async function playGame({ label, color, maxPlies = 140, extras = {}, castle = null }) {
  script = castle ? Object.assign(SCRIPTS[castle].slice(), { done: new Set() }) : null;
  const st0 = await ensureGame(color, label);
  const seq0 = await lastSeq();
  const g = { label, color: st0.playingAs, startPhase: st0.phase, userMoves: 0, oppWaitTimeouts: 0, errors: [], result: null };
  if (st0.phase !== 'playing') { g.errors.push('not-playing:' + st0.phase); games.push(g); result(`${label}: game started as ${color}`, false, st0); return g; }
  result(`${label}: game started, playingAs=${st0.playingAs}`, !color || st0.playingAs === color[0], { playingAs: st0.playingAs });
  const seen = new Set();
  let ply = st0.ply;
  while (true) {
    // wait for our turn or game over
    const st = await waitFor(async () => { const s = await S(); return (s.phase === 'over' || (s.phase === 'playing' && s.turn === s.playingAs)) ? s : null; }, 45000);
    if (!st) { g.oppWaitTimeouts++; g.errors.push('timeout waiting for bot at ply ' + ply); break; }
    // consistency: FEN vs SAN history
    const c = new Chess();
    let replayOk = true;
    for (const san of st.sanHistory) { try { c.move(san); } catch (e) { replayOk = false; break; } }
    if (!replayOk || norm(c.fen()) !== norm(st.fen)) fenMismatch.push({ label, ply: st.ply, fen: st.fen, replay: replayOk ? c.fen() : 'replay-failed' });
    if (st.phase === 'over') { g.result = st.gameOver; break; }
    if (st.ply >= maxPlies) { g.result = 'cap'; break; }
    seen.add(st.fen.split(' ').slice(0, 4).join(' '));
    // legal move set cross-check
    const mine = (await page.evaluate(() => window.BlindChess.legalMoves())).sort();
    const ref = new Chess(st.fen).moves({ verbose: true }).map(uciOf).sort();
    const refNoPromo = ref; // bridge expands promotions to 4 entries, as does chess.js
    if (JSON.stringify(mine) !== JSON.stringify(refNoPromo)) legalMismatch.push({ label, ply: st.ply, extra: mine.filter(x => !ref.includes(x)).slice(0, 5), missing: ref.filter(x => !mine.includes(x)).slice(0, 5) });

    // scenario hooks at specific plies
    if (extras.onTurn) await extras.onTurn(st, g);
    const st2 = await S();
    if (st2.phase !== 'playing' || st2.turn !== st2.playingAs) continue;
    const m = pickMove(st2.fen, seen);
    if (script && script.includes(uciOf(m))) script.done.add(uciOf(m));
    if (m.flags.includes('k') || m.flags.includes('q')) script = null;
    const useDom = extras.domAtUserMove !== undefined && g.userMoves >= extras.domAtUserMove && !g.domDone && !m.promotion && !/[kqe]/.test(m.flags);
    if (useDom) g.domDone = true;
    const r = await M(uciOf(m), useDom ? { forceDom: true } : {});
    if (useDom) {
      const moved = await waitFor(async () => (await S()).ply === st2.ply + 1, 5000);
      result(`${label}: DOM pointer-event fallback move ${uciOf(m)}`, !!moved, r);
      if (moved) coverage.domFallbackMoves++;
      if (!moved) { const r2 = await M(uciOf(m)); g.errors.push('dom fallback failed, api retry ' + JSON.stringify(r2)); }
    } else if (!r.ok) { g.errors.push(`move ${uciOf(m)} failed: ${JSON.stringify(r)}`); log('MOVEFAIL', label, uciOf(m), r, st2.fen); break; }
    else {
      if (r.san !== m.san && !(r.san || '').startsWith(m.san.replace(/[+#]$/, ''))) g.errors.push(`san mismatch ${r.san} vs ${m.san}`);
      if (m.promotion) {
        coverage['promo' + m.promotion.toUpperCase()]++;
        const dlg = await page.evaluate(() => { const p = document.querySelector('.promotion-window, [class*="promotion-window"]'); if (!p) return false; const r = p.getBoundingClientRect(); return r.width > 0 && r.height > 0; });
        result(`${label}: promotion ${r.san} (asked ${m.promotion}) no stuck dialog`, !dlg && new RegExp('=' + m.promotion.toUpperCase()).test(r.san || ''), { san: r.san, dialog: dlg });
      }
      if (m.flags.includes('e')) { coverage.enPassant++; result(`${label}: en passant ${r.san}`, true, r.fen); }
      if (m.flags.includes('k')) { coverage.castleK++; result(`${label}: castle kingside ${r.san}`, r.san === 'O-O' || r.san === 'O-O+', r.san); }
      if (m.flags.includes('q')) { coverage.castleQ++; result(`${label}: castle queenside ${r.san}`, /^O-O-O/.test(r.san || ''), r.san); }
      if (/\+$/.test(r.san || '')) coverage.checksGiven++;
    }
    g.userMoves++;
    ply = st2.ply + 1;
  }
  // gameOver may land a moment later
  await sleep(1500);
  const fin = await S();
  if (!g.result || g.result === 'cap') g.result = fin.gameOver || g.result;
  const evs = (await EV(seq0));
  const moveEvs = evs.filter(e => e.type === 'move');
  const plies = fin.ply;
  // Replay the event stream: each 'move' must be exactly the next ply; 'takeback' truncates.
  const seqList = st0.sanHistory.slice(); const seqErr = [];
  for (const e of evs) {
    if (e.type === 'move') { if (e.ply !== seqList.length + 1) seqErr.push(`ply ${e.ply} after ${seqList.length}`); seqList.length = e.ply - 1; seqList.push(e.san); }
    else if (e.type === 'takeback') seqList.length = e.ply;
    else if (e.type === 'newGame') seqList.length = 0;
  }
  const opp = moveEvs.filter(e => e.by === 'opponent');
  const wrongBy = moveEvs.filter(e => (e.color === fin.playingAs) !== (e.by === 'user'));
  coverage.checksReceived += opp.filter(e => e.check).length;
  const sanMatch = JSON.stringify(seqList) === JSON.stringify(fin.sanHistory);
  const takebacks = evs.filter(e => e.type === 'takeback').length;
  g.plies = plies; g.oppEvents = opp.length; g.gameOverEvents = evs.filter(e => e.type === 'gameOver').length;
  result(`${label}: move events exactly once per ply (${moveEvs.length} events, ${plies} plies, ${takebacks} takeback evts)`, seqErr.length === 0 && sanMatch && wrongBy.length === 0, { seqErr: seqErr.slice(0, 3), sanMatch, wrongBy: wrongBy.length });
  // DOM move list vs bridge history
  const domSans = await page.evaluate(() => [...document.querySelectorAll('wc-simple-move-list .node, .move-list .node')].map(n => (n.querySelector('.node-highlight-content') || n).innerText.replace(/\s+/g, '').trim()).filter(Boolean));
  const domOk = domSans.length === 0 || JSON.stringify(domSans.map(s => s.replace(/[!?]+$/, ''))) === JSON.stringify(fin.sanHistory);
  result(`${label}: DOM move list matches sanHistory`, domOk, domOk ? `${domSans.length} nodes` : { dom: domSans.slice(-6), bridge: fin.sanHistory.slice(-6) });
  if (fin.phase === 'over') {
    result(`${label}: gameOver event exactly once (${JSON.stringify(fin.gameOver)})`, g.gameOverEvents === 1, { events: g.gameOverEvents });
  }
  const posted = await page.evaluate(() => window.__posted.length);
  const total = await page.evaluate(() => window.BlindChess.events[window.BlindChess.events.length - 1].seq);
  result(`${label}: webkit.messageHandlers received every event`, posted === total, { posted, total });
  log('GAME', label, JSON.stringify({ color: g.color, plies, userMoves: g.userMoves, result: g.result, oppEvents: g.oppEvents, errors: g.errors.slice(0, 3), sans: fin.sanHistory.join(' ') }));
  games.push(g);
  await shot(label.replace(/\W+/g, '_'));
  return g;
}

// ------------------------------------------------------------------- run
try {
  const resp = await page.goto('https://www.chess.com/play/computer', { waitUntil: 'domcontentloaded', timeout: 60000 });
  log('loaded', resp && resp.status(), await page.title());
  const challenged = /just a moment|verify you are human/i.test(await page.title());
  result('no bot challenge (Cloudflare) on load', !challenged, await page.title());
  if (challenged) throw new Error('challenged');
  const ready = await waitFor(async () => { const s = await S(); return s && s.api ? s : null; }, 30000);
  result('bridge injected at document start and found board game API', !!ready, ready && { phase: ready.phase, playingAs: ready.playingAs });
  await sleep(2500);
  await dismissModals();
  await sleep(800);
  // idempotency: inject the same script again by evaluate (like didFinish evaluateJavaScript)
  const again = await page.evaluate(BRIDGE);
  const listeners = await page.evaluate(() => { const g = document.querySelector('wc-chess-board').game; return (g.getContext().api.listeners || []).filter(l => l.type === 'all').length; }).catch(() => null);
  result('second injection is a no-op', again === 'BlindChess:already', { again, allListeners: listeners });
  log('state0', await S());

  // Game 1: white (guest's first visit auto-starts a game vs the default bot)
  await playGame({
    label: 'G1-white', color: 'white', maxPlies: 160, castle: 'wk', extras: {
      domAtUserMove: 2,
      onTurn: async (st, g) => {
        if (st.ply === 0) {
          const bad = await M('e2e5'); result('illegal move rejected (e2e5)', !bad.ok && bad.error === 'illegal', bad);
          const bad2 = await M('zz99'); result('malformed UCI rejected', !bad2.ok && bad2.error === 'bad-uci', bad2);
          const bad3 = await M('e2e4q'); result('promotion suffix on non-promotion rejected', !bad3.ok, bad3);
          // rapid double call in one JS turn
          const dbl = await page.evaluate(() => [window.BlindChess.move('e2e4'), window.BlindChess.move('d2d4')]);
          const s = await S();
          result('rapid double move: first ok, second rejected, one ply added', dbl[0].ok && !dbl[1].ok && s.ply === 1, { r: dbl.map(x => x.ok ? x.san : x.error), ply: s.ply });
          // not your turn (bot to move now)
          const nyt = await M('d2d4');
          result('move when not your turn rejected', !nyt.ok && (nyt.error === 'not-your-turn'), nyt);
          g.userMoves++;
        }
        if (st.ply === 8 && !g.hinted) {
          g.hinted = true;
          const s0 = await lastSeq();
          const h = await page.evaluate(() => window.BlindChess.hint());
          const ev = await waitFor(async () => (await EV(s0)).find(e => e.type === 'hint'), 8000);
          const lm = new Chess(st.fen).moves({ verbose: true });
          const legal = ev && (ev.uci ? lm.some(m => m.from + m.to === ev.uci) : ev.square ? lm.some(m => m.from === ev.square) : false);
          result('hint() reports chess.com hint (legal move, or movable piece square)', !!(h.ok && ev && legal), { h: h.ok, ev: ev && { uci: ev.uci, square: ev.square, note: ev.note } });
          await page.evaluate(() => { const g = document.querySelector('wc-chess-board').game; try { g.clearMarkings(); } catch (e) { } });
        }
        if (st.ply === 14 && !g.tookBack) {
          g.tookBack = true;
          const s0 = await lastSeq();
          const r = await page.evaluate(() => window.BlindChess.takeback());
          const ok = await waitFor(async () => { const s = await S(); return s.ply < st.ply ? s : null; }, 6000);
          const evs = await EV(s0);
          result('takeback() (Undo) rewinds and posts takeback event', !!(r.ok && ok && evs.some(e => e.type === 'takeback' || e.type === 'newGame')), { r, plyAfter: ok && ok.ply, ev: evs.filter(e => e.type !== 'state').map(e => e.type) });
          await sleep(1500);
        }
      }
    }
  });

  // Game 2: black via startNewGame (game-over modal -> New Bot -> colour -> Play)
  await playGame({ label: 'G2-black', color: 'black', maxPlies: 160, castle: 'bq' });

  // Game 3: white, then reload mid-game
  const g3 = await playGame({ label: 'G3-white-reload', color: 'white', maxPlies: 12 });
  const before = await S();
  await page.reload({ waitUntil: 'domcontentloaded' });
  const afterReload = await waitFor(async () => { const s = await S(); return s && s.api ? s : null; }, 30000);
  await sleep(3000);
  const ar = await S();
  result('page reload mid-game: bridge re-installs and reports a coherent state', !!(afterReload && ar.ok && (ar.phase === 'setup' || ar.phase === 'playing')),
    { before: { phase: before.phase, ply: before.ply }, after: { phase: ar.phase, ply: ar.ply, playingAs: ar.playingAs } });
  log('NOTE reload: game still live right after reload?', ar.ply === before.ply && ar.phase === 'playing');
  if (ar.phase === 'setup') {
    // chess.com keeps the guest's unfinished game locally: pressing Play with the same colour resumes it?
    await page.evaluate(() => window.BlindChess.startNewGame({ color: 'white' }));
    const res = await waitFor(async () => { const s = await S(); return s.phase === 'playing' ? s : null; }, 15000);
    await sleep(2000);
    const r2 = await S();
    log('NOTE reload+Play(same colour):', JSON.stringify({ phase: r2.phase, ply: r2.ply, playingAs: r2.playingAs, sameHistory: JSON.stringify(r2.sanHistory.slice(0, before.ply)) === JSON.stringify(before.sanHistory) }));
    result('after reload, startNewGame({color}) gets back to a playable game', !!res, { ply: r2.ply, playingAs: r2.playingAs });
    if (r2.phase === 'playing' && r2.turn === r2.playingAs) {
      const m = pickMove(r2.fen, new Set());
      const mv = await M(uciOf(m));
      result('move after reload works', mv.ok, mv);
    }
  }
  // Game 4: black from the setup screen, then resign after a few moves
  await playGame({
    label: 'G4-black-resign', color: 'black', maxPlies: 200, extras: {
      onTurn: async (st) => {
        if (st.ply >= 10) {
          const s0 = await lastSeq();
          const r = await page.evaluate(() => window.BlindChess.resign());
          const ev = await waitFor(async () => (await EV(s0)).find(e => e.type === 'gameOver'), 8000);
          result('resign() ends the game with gameOver(reason resignation)', !!(r.ok && ev && /resign/i.test(ev.reason)), { r, ev: ev && { result: ev.result, reason: ev.reason, userWon: ev.userWon } });
        }
      }
    }
  });
  // Rematch path
  const rm = await page.evaluate(() => window.BlindChess.startNewGame({ rematch: true }));
  const rms = await waitFor(async () => { const s = await S(); return s.phase === 'playing' && s.ply <= 1 ? s : null; }, 15000);
  result('startNewGame({rematch:true}) starts a new game', !!(rm.ok && rms), { rm, phase: rms && rms.phase, playingAs: rms && rms.playingAs });
} catch (e) {
  log('FATAL', String(e && e.stack || e).slice(0, 600));
  result('harness completed without exception', false, String(e).slice(0, 200));
}
await shot('final');
result('state() FEN consistent with SAN history after every turn', fenMismatch.length === 0, { mismatches: fenMismatch.length, first: fenMismatch[0] });
result('legalMoves() matches chess.js on every turn', legalMismatch.length === 0, { mismatches: legalMismatch.length, first: legalMismatch[0] });
const passed = results.filter(r => r.pass).length;
log('COVERAGE', JSON.stringify(coverage));
log('SUMMARY', JSON.stringify({ passed, failed: results.length - passed, games: games.map(g => ({ label: g.label, color: g.color, plies: g.plies, result: g.result, errors: g.errors.length })) }));
fs.writeFileSync(`${out}/results.json`, JSON.stringify({ results, coverage, games, fenMismatch, legalMismatch }, null, 1));
await browser.close();
process.exit(0);
