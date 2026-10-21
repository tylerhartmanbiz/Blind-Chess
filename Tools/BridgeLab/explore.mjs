// BridgeLab explorer (setup-flow edition): compact logs only.
import { webkit, chromium, devices } from 'playwright';
const profile = process.argv[2] || 'webkit-iphone';
const log = (...a) => console.log(`[${profile}] ` + a.map(x => typeof x === 'string' ? x : JSON.stringify(x)).join(' '));
const engine = profile.startsWith('webkit') ? webkit : chromium;
const browser = await engine.launch({ headless: process.env.HEADED !== '1' });
const ctx = await browser.newContext({ ...devices['iPhone 13'], locale: 'en-US' });
const page = await ctx.newPage();
await page.goto('https://www.chess.com/play/computer', { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForTimeout(7000);

const UI = () => {
  const vis = el => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  const btns = [...document.querySelectorAll('button, [role=button], [role=radio], input[type=radio], label')].filter(vis)
    .map(b => (b.innerText || b.getAttribute('aria-label') || b.getAttribute('data-cy') || '').trim().replace(/\s+/g, ' ').slice(0, 30) + (b.getAttribute('aria-pressed') || b.getAttribute('aria-checked') ? '[' + (b.getAttribute('aria-pressed') || b.getAttribute('aria-checked')) + ']' : '')).filter(Boolean);
  const colorish = [...document.querySelectorAll('*')].filter(e => vis(e) && e.children.length < 4 && /(^|[\s-])(white|black|random)([\s-]|$)|color-select|select-color|play-as/i.test(String(e.className.baseVal ?? e.className) + ' ' + (e.getAttribute('aria-label') || '') + ' ' + (e.getAttribute('data-cy') || '')))
    .slice(0, 12).map(e => e.tagName + '.' + String(e.className.baseVal ?? e.className).slice(0, 70) + ' aria=' + e.getAttribute('aria-label') + ' cy=' + e.getAttribute('data-cy'));
  const modal = [...document.querySelectorAll('[class*=modal], [role=dialog]')].filter(vis).map(m => m.innerText.replace(/\s+/g, ' ').slice(0, 160))[0] || null;
  const sb = document.querySelector('.board-layout-sidebar, #board-layout-sidebar');
  const b = document.querySelector('wc-chess-board'); const g = b && b.game;
  let gs = null; try { gs = g && { pa: g.getPlayingAs(), turn: g.getTurn(), mode: g.getMode().name, over: g.isGameOver(), n: g.getHistorySANs().length, hdr: g.getHeaders().White + ' v ' + g.getHeaders().Black, flipped: b.classList.contains('flipped') || (b.getAttribute('class')||'').includes('flipped') }; } catch (e) { gs = 'ERR ' + e.message; }
  return { btns, colorish, modal, sidebar: sb ? sb.innerText.replace(/\s+/g, ' ').slice(0, 400) : null, gs };
};
const clickText = (t) => page.evaluate((t) => { const vis = el => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  const re = new RegExp('^' + t + '$', 'i');
  const b = [...document.querySelectorAll('button, [role=button], [role=radio], label, [aria-label]')].filter(vis).find(x => re.test((x.innerText || '').trim()) || re.test(x.getAttribute('aria-label') || ''));
  if (!b) return false; b.click(); return (b.innerText || b.getAttribute('aria-label') || '').trim().slice(0, 30) + '<' + b.tagName + '.' + String(b.className).slice(0, 60) + '>'; }, t);
const step = async (label, t, wait = 2500) => { const r = t ? await clickText(t) : null; if (t) await page.waitForTimeout(wait); log('STEP', label, 'click', t, '->', r, JSON.stringify(await page.evaluate(UI))); return r; };

await step('load');
await step('close-modal', 'Close');
// Is a game already live? Try engine copy promotion probe meanwhile.
log('PROMO', await page.evaluate(() => { const g = document.querySelector('wc-chess-board').game; const out = {};
  try { const c = g.getJCEGameCopy(); c.load('7k/P7/8/8/8/8/8/K7 w - - 0 1'); out.copyMoves = JSON.stringify(c.moves()).slice(0, 600); out.copyKeys = Object.keys(c).join(','); } catch (e) { out.copyErr = e.message; }
  try { out.lmfs = JSON.stringify(g.getLegalMovesForSquare('e2')).slice(0, 300); } catch (e) { out.lmfsErr = e.message; }
  try { out.isLegal = String(g.isLegalMove.toString()).slice(0, 300); out.moveSrc = String(g.move.toString()).slice(0, 300); out.resignSrc = g.resign.toString().slice(0, 300); out.undoSrc = g.undo.toString().slice(0, 300); } catch (e) { out.srcErr = e.message; }
  return out; }));
await step('play', 'Play');
await step('choose?', 'Choose');
await step('after');
// resign the auto game to reach game-over modal, then New Bot
await step('resign1', 'Resign', 1500);
await step('resign2', 'Resign', 3000);
await step('newbot', 'New Bot', 3000);
await step('choose', 'Choose', 3000);
await step('black', 'Black', 1500);
await step('play2', 'Play', 4000);
await step('settle', null);
await page.waitForTimeout(3000);
await step('settle2', null);
log('URL', page.url());
// Rematch path
await step('r1', 'Resign', 1500); await step('r2', 'Resign', 3000);
await step('rematch', 'Rematch', 4000);
await page.waitForTimeout(3000); await step('rematch-settle', null);
// reload mid-game behaviour
await page.reload({ waitUntil: 'domcontentloaded' }); await page.waitForTimeout(7000);
await step('reloaded', null);
await browser.close();
