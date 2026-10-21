// BridgeLab explorer v4: setup screen (bot list, play-as selector, Play CTA). Compact logs only.
import { webkit, devices } from 'playwright';
const log = (...a) => console.log('[x] ' + a.map(x => typeof x === 'string' ? x : JSON.stringify(x)).join(' '));
const browser = await webkit.launch({ headless: true });
const ctx = await browser.newContext({ ...devices['iPhone 13'], locale: 'en-US' });
const page = await ctx.newPage();
await page.goto('https://www.chess.com/play/computer', { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForTimeout(7000);
const GS = () => { const b = document.querySelector('wc-chess-board'); const g = b && b.game; const vis = el => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  let gs; try { gs = { pa: g.getPlayingAs(), turn: g.getTurn(), mode: g.getMode().name, over: g.isGameOver(), sans: g.getHistorySANs().join(' '), hdr: g.getHeaders().White + ' v ' + g.getHeaders().Black, flipped: b.classList.contains('flipped') }; } catch (e) { gs = 'ERR ' + e.message; }
  const btns = [...document.querySelectorAll('button')].filter(vis).map(b => (b.innerText.trim() || ('@' + b.getAttribute('aria-label'))).replace(/\s+/g, ' ').slice(0, 25));
  const modal = [...document.querySelectorAll('[class*=modal]')].filter(vis).map(m => m.innerText.replace(/\s+/g, ' ').slice(0, 120))[0] || null;
  return { gs, btns, modal, cta: !!document.querySelector('[class*=bot-selection-cta]'), url: location.pathname }; };
const html = (sel, n = 2500) => page.evaluate(([s, n]) => { const e = document.querySelector(s); return e ? e.outerHTML.replace(/\s+/g, ' ').slice(0, n) : 'NONE ' + s; }, [sel, n]);
log('initial', await page.evaluate(GS));
log('initial-sidebar', await page.evaluate(() => { const s = document.querySelector('.board-layout-sidebar, #board-layout-sidebar'); return s ? s.innerText.replace(/\s+/g, ' ').slice(0, 300) : null; }));
// close any modal
await page.evaluate(() => { const b = [...document.querySelectorAll('button[aria-label=Close]')][0]; if (b) b.click(); });
await page.waitForTimeout(1500);
log('after-close', await page.evaluate(GS));
await page.reload({ waitUntil: 'domcontentloaded' }); await page.waitForTimeout(7000);
log('reloaded', await page.evaluate(GS));
log('PLAYAS', await html('.play-as-selector-component', 3000));
log('CTA', await html('[class*=bot-selection-cta]', 800));
log('BOTTILE', await html('[class*=bot-selection] [data-bot-id], [class*=bot-component], [class*=bot-selection-bot]', 1200));
log('SELECTED-BOT', await page.evaluate(() => [...document.querySelectorAll('[class*=selected]')].slice(0, 5).map(e => e.tagName + '.' + String(e.className).slice(0, 80) + ' ' + [...e.attributes].filter(a => a.name.startsWith('data') || a.name === 'aria-label').map(a => a.name + '=' + a.value.slice(0, 40)).join(' '))));
log('OPTIONS-BTN', await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => x.innerText.trim() === 'Options'); return b ? b.outerHTML.slice(0, 400) : null; }));
// open Options to see what's inside
await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => x.innerText.trim() === 'Options'); if (b) b.click(); });
await page.waitForTimeout(1500);
log('options-open', await page.evaluate(GS));
log('options-sidebar', await page.evaluate(() => { const s = document.querySelector('.board-layout-sidebar, #board-layout-sidebar'); return s ? s.innerText.replace(/\s+/g, ' ').slice(0, 500) : null; }));
log('PLAYAS2', await html('.play-as-selector-component', 3000));
// choose black inside play-as selector
log('pick-black', await page.evaluate(() => { const root = document.querySelector('.play-as-selector-component') || document; const c = [...root.querySelectorAll('*')].find(e => /black/i.test((e.getAttribute('aria-label') || '') + ' ' + (e.getAttribute('data-cy') || '') + ' ' + (e.getAttribute('title') || '') + ' ' + String(e.className))); if (!c) return 'none'; (c.closest('button,[role=button],[role=radio],label') || c).click(); return c.tagName + '.' + String(c.className).slice(0, 80); }));
await page.waitForTimeout(1000);
log('PLAYAS3', await html('.play-as-selector-component', 1500));
await page.evaluate(() => { const b = document.querySelector('[class*=bot-selection-cta] button, button[class*=bot-selection-cta]') || [...document.querySelectorAll('button')].find(x => x.innerText.trim() === 'Play'); if (b) b.click(); });
for (let i = 0; i < 4; i++) { await page.waitForTimeout(2500); log('after-play-' + i, await page.evaluate(GS)); }
log('URL', page.url());
// pick a different bot from the list: click the 3rd bot avatar we can find, then Play
await page.reload({ waitUntil: 'domcontentloaded' }); await page.waitForTimeout(7000);
log('reloaded2', await page.evaluate(GS));
await browser.close();
