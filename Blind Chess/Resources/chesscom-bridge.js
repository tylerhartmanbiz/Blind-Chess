/*
 * chesscom-bridge.js — Blind Chess <-> chess.com (play/computer) bridge.
 *
 * Exposes window.BlindChess. Primary path uses the game API that chess.com's
 * <wc-chess-board> element exposes as `element.game` (getFEN, getPlayingAs,
 * getTurn, getLegalMoves, move, getHistorySANs, getCurrentFullLine, isGameOver,
 * getResult, getPositionInfo, getMode, on/off ...). Falls back to synthetic
 * pointer events on the board when that API is missing.
 *
 * Safe to inject any number of times (document start or end, before or after
 * the board exists). Survives chess.com's SPA navigation (board re-created).
 * Events go to window.webkit.messageHandlers.blindChess.postMessage(obj) when
 * present, and always to window.BlindChess.events (ring buffer, for tests).
 */
(function () {
  'use strict';
  var VERSION = 7;
  var w = window;
  var prev = w.BlindChess;
  if (prev && prev.version === VERSION && prev.__alive) { try { prev.__check('reinject'); } catch (e) {} return 'BlindChess:already'; }
  if (prev && typeof prev.__teardown === 'function') { try { prev.__teardown(); } catch (e) {} }

  var FILES = 'abcdefgh';
  var START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  var events = [];
  var seq = 0;
  var T = { game: null, unbind: null, plies: -1, lastFen: null, pa: null, overSent: false, phase: null, lastEventType: null, gameId: 0, stateSig: null };
  var timers = [];
  var observer = null;

  // ---------------------------------------------------------------- utils
  function now() { return Date.now(); }
  function post(ev) {
    ev.seq = ++seq; ev.ts = now();
    events.push(ev);
    if (events.length > 1000) events.splice(0, events.length - 1000);
    try {
      var h = w.webkit && w.webkit.messageHandlers && w.webkit.messageHandlers.blindChess;
      if (h && typeof h.postMessage === 'function') h.postMessage(JSON.parse(JSON.stringify(ev)));
    } catch (e) { /* never throw into page */ }
    return ev;
  }
  function boardEl() { return document.querySelector('wc-chess-board') || document.querySelector('chess-board'); }
  function gameApi() {
    var b = boardEl();
    var g = b && b.game;
    return g && typeof g.getFEN === 'function' ? g : null;
  }
  function safe(fn, dflt) { try { var v = fn(); return v === undefined ? dflt : v; } catch (e) { return dflt; } }
  function colorChar(n) { return n === 1 ? 'w' : n === 2 ? 'b' : null; }
  function visible(el) { if (!el) return false; var r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; }
  function buttons() { return Array.prototype.slice.call(document.querySelectorAll('button, [role=button]')).filter(visible); }
  function findButton(re, opts) {
    opts = opts || {};
    var list = buttons();
    for (var i = 0; i < list.length; i++) {
      var b = list[i];
      var txt = (b.innerText || '').replace(/\s+/g, ' ').trim();
      var aria = b.getAttribute('aria-label') || '';
      if (opts.textOnly ? re.test(txt) : (re.test(txt) || re.test(aria))) return b;
    }
    return null;
  }
  function uciOfNode(n) {
    if (!n || !n.from || !n.to) return null;
    var promo = '';
    var m = /=([QRBN])/.exec(n.san || '');
    if (m) promo = m[1].toLowerCase();
    else if (n.promotion && typeof n.promotion === 'string') promo = n.promotion.toLowerCase().charAt(0);
    return n.from + n.to + promo;
  }

  // -------------------------------------------------------- game reading
  function mainLine(g) {
    var line = safe(function () { return g.getCurrentFullLine(); }, null);
    if (Array.isArray(line)) return line;
    return null;
  }
  function readGame(g) {
    var line = mainLine(g);
    var sans = line ? line.map(function (n) { return n.san; }) : safe(function () { return g.getHistorySANs(); }, []) || [];
    var fen;
    if (line && line.length) fen = line[line.length - 1].fen;
    else fen = safe(function () { return g.getFingerprints().startingFen; }, null) || safe(function () { return g.getFEN(); }, START_FEN);
    var paNum = safe(function () { return g.getPlayingAs(); }, null);
    if (paNum === 1 || paNum === 2) T.pa = colorChar(paNum);
    var playingAs = T.pa || inferPlayingAs();
    return {
      line: line, sans: sans, fen: fen,
      turn: (fen && fen.split(' ')[1]) || colorChar(safe(function () { return g.getTurn(); }, null)),
      playingAs: playingAs,
      mode: safe(function () { return g.getMode().name; }, null),
      over: !!safe(function () { return g.isGameOver(); }, false)
    };
  }
  function inferPlayingAs() {
    var b = boardEl();
    if (!b) return null;
    return b.classList.contains('flipped') ? 'b' : 'w';
  }
  function setupVisible() {
    // Bot-selection screen (choose bot / colour / "Play") is showing.
    var cta = document.querySelector('[class*="bot-selection-cta"]');
    return !!(cta && visible(cta));
  }
  function gameOverInfo(g, r) {
    if (!r.over) return null;
    var result = safe(function () { return g.getResult(); }, null) || safe(function () { return g.getHeaders().Result; }, null) || '*';
    var info = safe(function () { return g.getPositionInfo(); }, {}) || {};
    var reason = info.checkmate ? 'checkmate' : info.stalemate ? 'stalemate' : info.insufficient ? 'insufficient material'
      : info.threefold ? 'threefold repetition' : info.fiftyMoveRule ? '50-move rule' : null;
    if (!reason) {
      var sub = document.querySelector('.game-over-modal-subtitle-component, [class*="game-over-modal-subtitle"]');
      var t = sub && sub.innerText ? sub.innerText.replace(/\s+/g, ' ').trim() : '';
      if (t) reason = t.replace(/^by\s+/i, '');
      else if (T.lastEventType === 'GameResigned') reason = 'resignation';
      else if (info.draw) reason = 'draw';
      else reason = 'unknown';
    }
    var winner = result === '1-0' ? 'w' : result === '0-1' ? 'b' : result === '1/2-1/2' ? 'draw' : null;
    var userWon = winner && winner !== 'draw' && r.playingAs ? winner === r.playingAs : null;
    return { result: result, reason: reason, winner: winner, userWon: userWon };
  }

  function buildState() {
    var g = gameApi();
    if (!g) {
      return { ok: true, api: false, phase: 'setup', fen: null, playingAs: inferPlayingAs(), turn: null, sanHistory: [], lastMove: null, gameOver: null, inCheck: false, ply: 0 };
    }
    var r = readGame(g);
    var last = r.line && r.line.length ? r.line[r.line.length - 1] : null;
    var gameOver = gameOverInfo(g, r);
    var phase = gameOver ? 'over' : (setupVisible() || r.mode !== 'playing') ? 'setup' : 'playing';
    return {
      ok: true, api: true, phase: phase, fen: r.fen, playingAs: r.playingAs, turn: r.turn,
      sanHistory: r.sans.slice(), ply: r.sans.length,
      lastMove: last ? { from: last.from, to: last.to, san: last.san, uci: uciOfNode(last), by: colorChar(last.color) === r.playingAs ? 'user' : 'opponent' } : null,
      gameOver: gameOver,
      inCheck: /\+$|#$/.test(last && last.san || ''),
      mode: r.mode
    };
  }

  // ---------------------------------------------------------- tracking
  function bind(g) {
    if (T.unbind) { try { T.unbind(); } catch (e) {} T.unbind = null; }
    T.game = g;
    if (!g || typeof g.on !== 'function') return;
    var handler = function (e) {
      var type = e && e.type;
      if (!type) return;
      if (type === 'Move' || type === 'ModeChanged' || type === 'GameResigned' || type === 'ResetGame' || type === 'LoadFen' ||
          type === 'UpdatePGNHeaders' || type === 'MoveBackward' || type === 'MoveForward' || type === 'Undo' || /Game|Over|Result/i.test(type)) {
        if (/Resign|Result|Over|Timeout/i.test(type)) T.lastEventType = type;
        check('event:' + type);
      }
    };
    try { g.on('all', handler); } catch (e) { return; }
    T.unbind = function () { try { if (typeof g.off === 'function') g.off('all', handler); } catch (e) {} };
  }

  function check(why) {
    T.boardRef = boardEl(); T.setupSeen = setupVisible();
    var g = gameApi();
    if (g !== T.game) {
      bind(g);
      if (T.plies >= 0) post({ type: 'boardChanged', why: why });
      T.plies = -1; T.overSent = false; T.pa = null;
    }
    var st = buildState();
    if (!g) { emitStateIfChanged(st); return; }
    var line = mainLine(g);
    var n = st.ply;
    if (T.plies < 0) {
      // first sight of this board: baseline without replaying old moves
      T.plies = n; T.lastFen = st.fen; T.overSent = !!st.gameOver;
      T.gameId++;
      emitStateIfChanged(st, true);
      return;
    }
    if (n < T.plies) {
      if (n === 0) { T.gameId++; T.overSent = false; T.pa = null; st = buildState(); post({ type: 'newGame', playingAs: st.playingAs, fen: st.fen }); }
      else post({ type: 'takeback', ply: n, fen: st.fen, sanHistory: st.sanHistory });
      T.plies = n;
    } else if (T.overSent && !st.gameOver) {
      T.overSent = false; T.gameId++;
      post({ type: 'newGame', playingAs: st.playingAs, fen: st.fen });
    }
    for (var i = T.plies; i < n; i++) {
      var node = line && line[i];
      var color = node ? colorChar(node.color) : (i % 2 === 0 ? 'w' : 'b');
      post({
        type: 'move', ply: i + 1, san: node ? node.san : st.sanHistory[i], uci: uciOfNode(node), from: node && node.from, to: node && node.to,
        fen: node ? node.fen : st.fen, color: color, by: color === st.playingAs ? 'user' : 'opponent', check: /\+$/.test(node && node.san || ''), mate: /#$/.test(node && node.san || '')
      });
    }
    T.plies = n; T.lastFen = st.fen;
    if (st.gameOver && !T.overSent) {
      T.overSent = true;
      var go = st.gameOver;
      post({ type: 'gameOver', result: go.result, reason: go.reason, winner: go.winner, userWon: go.userWon, fen: st.fen, sanHistory: st.sanHistory });
      // the modal subtitle (reason) may render a moment later: send an update if it improves
      if (go.reason === 'unknown' || go.reason === 'draw') setTimeout(function () {
        var s2 = buildState();
        if (s2.gameOver && s2.gameOver.reason !== go.reason) post({ type: 'gameOverReason', reason: s2.gameOver.reason, result: s2.gameOver.result });
      }, 1500);
    }
    emitStateIfChanged(st);
  }
  function emitStateIfChanged(st, force) {
    var sig = [st.phase, st.fen, st.playingAs, st.ply, !!st.gameOver].join('|');
    if (!force && sig === T.stateSig) return;
    T.stateSig = sig;
    post({ type: 'state', state: st });
  }

  // ------------------------------------------------------------- moves
  function parseUci(uci) {
    var m = /^([a-h][1-8])([a-h][1-8])([qrbn])?$/.exec(String(uci || '').trim().toLowerCase());
    return m ? { from: m[1], to: m[2], promo: m[3] || null } : null;
  }
  function legalMoves() {
    var g = gameApi();
    if (!g) return [];
    var list = safe(function () { return g.getLegalMoves(); }, []) || [];
    var out = [];
    list.forEach(function (x) {
      var promo = (x.flags & 8) || x.promotion;
      if (promo) {
        if (x.promotion && typeof x.promotion === 'string') out.push(x.from + x.to + x.promotion.toLowerCase());
        else ['q', 'r', 'b', 'n'].forEach(function (p) { out.push(x.from + x.to + p); });
      } else out.push(x.from + x.to);
    });
    return out.filter(function (v, i, a) { return a.indexOf(v) === i; });
  }

  function move(uci, opts) {
    opts = opts || {};
    var p = parseUci(uci);
    if (!p) return { ok: false, error: 'bad-uci', uci: uci };
    var g = gameApi();
    if (!g || opts.forceDom) return domMove(p, opts);
    var st = buildState();
    if (st.phase === 'over') return { ok: false, error: 'game-over' };
    if (st.phase !== 'playing') return { ok: false, error: 'not-playing', phase: st.phase };
    if (st.playingAs && st.turn !== st.playingAs) return { ok: false, error: 'not-your-turn', turn: st.turn };
    var legal = (safe(function () { return g.getLegalMoves(); }, []) || []).filter(function (x) { return x.from === p.from && x.to === p.to; });
    if (!legal.length) return { ok: false, error: 'illegal', uci: uci };
    var isPromo = legal.some(function (x) { return (x.flags & 8) || x.promotion; });
    if (!isPromo && p.promo) return { ok: false, error: 'illegal', detail: 'not-a-promotion', uci: uci };
    var promo = isPromo ? (p.promo || 'q') : undefined;
    var before = st.ply;
    var spec = { from: p.from, to: p.to, userGenerated: true, animate: false };
    if (promo) spec.promotion = promo;
    var ret, err = null;
    var attempts = [spec];
    if (promo) {
      attempts.push({ from: p.from, to: p.to, promotion: promo.toUpperCase(), userGenerated: true, animate: false });
      var lp = legal.filter(function (x) { return x.promotion && String(x.promotion).toLowerCase() === promo; })[0];
      if (lp) { var c = {}; for (var k in lp) c[k] = lp[k]; c.userGenerated = true; c.animate = false; attempts.push(c); }
    }
    var after = st;
    for (var a = 0; a < attempts.length && after.ply === before; a++) {
      try { ret = g.move(attempts[a]); } catch (e) { err = String(e && e.message || e); }
      after = buildState();
    }
    if (after.ply !== before + 1) return { ok: false, error: 'rejected', detail: err, uci: uci };
    closePromotionDialog();
    check('move');
    var mv = after.lastMove || {};
    return { ok: true, uci: mv.uci || (p.from + p.to + (promo || '')), san: mv.san, fen: after.fen, promotion: promo || null, autoQueen: !!(isPromo && !p.promo) };
  }

  function closePromotionDialog() {
    var b = boardEl();
    if (!b) return;
    var pw = b.querySelector('.promotion-window, [class*="promotion-window"]');
    if (pw && visible(pw)) {
      var close = pw.querySelector('.close-button, [class*="close"]');
      if (close) close.click();
    }
  }

  // DOM fallback: synthetic pointer events on the board (used when the game API is absent).
  function squareCenter(b, sq) {
    var r = b.getBoundingClientRect();
    var f = FILES.indexOf(sq[0]), rank = parseInt(sq[1], 10) - 1;
    var flipped = b.classList.contains('flipped');
    var col = flipped ? 7 - f : f, row = flipped ? rank : 7 - rank;
    var size = r.width / 8;
    return { x: r.left + (col + 0.5) * size, y: r.top + (row + 0.5) * size };
  }
  function fire(target, type, pt) {
    var init = { bubbles: true, cancelable: true, composed: true, clientX: pt.x, clientY: pt.y, pointerId: 1, pointerType: 'mouse', isPrimary: true, button: 0, buttons: type === 'pointerup' || type === 'mouseup' ? 0 : 1, view: w };
    var ev;
    try { ev = /^pointer/.test(type) ? new PointerEvent(type, init) : new MouseEvent(type, init); } catch (e) { ev = new MouseEvent(type.replace('pointer', 'mouse'), init); }
    target.dispatchEvent(ev);
  }
  function domClick(b, sq) {
    var pt = squareCenter(b, sq);
    var target = document.elementFromPoint(pt.x, pt.y) || b;
    fire(target, 'pointerdown', pt); fire(target, 'mousedown', pt);
    fire(target, 'pointerup', pt); fire(target, 'mouseup', pt);
    fire(target, 'click', pt);
  }
  function domMove(p, opts) {
    var b = boardEl();
    if (!b) return { ok: false, error: 'no-board' };
    var before = buildState().ply;
    domClick(b, p.from);
    domClick(b, p.to);
    var promo = p.promo || 'q';
    // promotion picker (if it appeared): pick the requested piece
    setTimeout(function () {
      var pw = b.querySelector('.promotion-window, [class*="promotion-window"]');
      if (pw && visible(pw)) {
        var colour = buildState().playingAs || 'w';
        var piece = pw.querySelector('.promotion-piece.' + colour + promo) || pw.querySelector('[class*="' + colour + promo + '"]');
        if (piece) piece.click();
      }
    }, 50);
    return { ok: true, pending: true, via: 'dom', uci: p.from + p.to + (p.promo || ''), plyBefore: before };
  }

  // ------------------------------------------------- game-level actions
  function resign() {
    var st = buildState();
    if (st.phase !== 'playing') return { ok: false, error: 'not-playing', phase: st.phase };
    var b = findButton(/^resign$/i);
    if (!b) return { ok: false, error: 'no-resign-button' };
    b.click();
    // confirmation ("Are you sure you want to resign?  Cancel | Resign")
    var tries = 0;
    (function confirm() {
      var list = buttons().filter(function (x) { return /^resign$/i.test((x.innerText || '').trim()); });
      var yes = list.filter(function (x) { return x !== b; })[0] || null;
      if (yes) { yes.click(); return; }
      if (++tries < 20) setTimeout(confirm, 100);
    })();
    return { ok: true, pending: true };
  }
  function takeback() {
    var st = buildState();
    if (st.phase !== 'playing') return { ok: false, error: 'not-playing', phase: st.phase };
    var b = findButton(/^undo$/i);
    if (!b) return { ok: false, error: 'no-undo-button' };
    b.click();
    return { ok: true, pending: true, plyBefore: st.ply };
  }
  function hint() {
    var st = buildState();
    if (st.phase !== 'playing') return { ok: false, error: 'not-playing', phase: st.phase };
    var b = findButton(/^(show )?hint$/i);
    if (!b) return { ok: false, error: 'no-hint-button' };
    var g = gameApi();
    var seen = {};
    var arrows0 = safe(function () { return g.getMarkings().arrow; }, {}) || {};
    Object.keys(arrows0).forEach(function (k) { seen[k] = 1; });
    b.click();
    var tries = 0;
    (function poll() {
      var arrows = safe(function () { return g.getMarkings().arrow; }, {}) || {};
      var keys = Object.keys(arrows).filter(function (k) { return !seen[k]; });
      if (!keys.length) keys = Object.keys(arrows);
      for (var i = 0; i < keys.length; i++) {
        var a = arrows[keys[i]];
        var from = a && (a.from || (a.data && a.data.from)), to = a && (a.to || (a.data && a.data.to));
        if (!from && /^[a-h][1-8][a-h][1-8]$/.test(keys[i])) { from = keys[i].slice(0, 2); to = keys[i].slice(2, 4); }
        if (from && to) { post({ type: 'hint', uci: from + to, from: from, to: to }); return; }
      }
      if (++tries < 40) setTimeout(poll, 100);
      else post({ type: 'hint', uci: null, error: 'no-arrow' });
    })();
    return { ok: true, pending: true };
  }
  function closeModal() {
    // game-over modal or first-visit onboarding modal
    var list = document.querySelectorAll('[class*="modal"] button[aria-label="Close"], .cc-modal-close-component, [class*="game-over-modal"] button[aria-label="Close"]');
    for (var i = 0; i < list.length; i++) if (visible(list[i])) { list[i].click(); return true; }
    return false;
  }

  /*
   * startNewGame({ color: 'white'|'black'|'random', rematch: bool })
   * From the game-over modal: "Rematch" (same bot) or "New Bot" (back to setup).
   * From the setup screen: picks the colour in the play-as selector and presses Play.
   * Asynchronous: watch for {type:'newGame'} / {type:'state'} events.
   */
  function startNewGame(opts) {
    opts = opts || {};
    var st = buildState();
    var steps = [];
    if (st.phase === 'over') {
      var re = opts.rematch ? /^rematch$/i : /^new bot$/i;
      var b = findButton(re, { textOnly: true });
      if (!b) return { ok: false, error: 'no-' + (opts.rematch ? 'rematch' : 'new-bot') + '-button' };
      b.click(); steps.push(opts.rematch ? 'rematch' : 'new-bot');
      if (opts.rematch) return { ok: true, pending: true, steps: steps };
    } else if (st.phase === 'playing' && st.ply > 0 && !opts.force) {
      return { ok: false, error: 'game-in-progress' };
    }
    var tries = 0;
    (function setup() {
      if (!setupVisible()) { if (++tries < 40) return setTimeout(setup, 150); post({ type: 'setupFailed', error: 'no-setup-screen' }); return; }
      if (opts.bot && !pickBot(opts.bot)) { post({ type: 'setupFailed', error: 'bot-not-found', bot: opts.bot }); return; }
      if (opts.color) {
        var picked = pickColor(opts.color);
        if (!picked) { post({ type: 'setupFailed', error: 'color-not-found', color: opts.color }); return; }
      }
      setTimeout(function () {
        var play = document.querySelector('[class*="bot-selection-cta"] button, button[class*="bot-selection-cta"]') || findButton(/^play$/i, { textOnly: true });
        if (!play) { post({ type: 'setupFailed', error: 'no-play-button' }); return; }
        play.click();
        post({ type: 'setupDone', color: opts.color || null });
      }, 300);
    })();
    return { ok: true, pending: true, steps: steps };
  }
  function pickColor(color) {
    // Setup screen: .play-as-selector-component > .play-side-selector-option x3 (white, random, black),
    // identified by their background-image (white--sm.svg / random.svg / black--sm.svg).
    var opts = Array.prototype.slice.call(document.querySelectorAll('.play-side-selector-option, [class*="play-side-selector-option"]'));
    if (!opts.length) return false;
    var want = String(color).toLowerCase();
    var idx = { white: 0, random: 1, black: 2 }[want];
    var hit = null;
    opts.forEach(function (o) { var bg = (o.getAttribute('style') || '') + ' ' + (o.getAttribute('aria-label') || ''); if (!hit && bg.toLowerCase().indexOf(want) >= 0) hit = o; });
    if (!hit && idx !== undefined && opts.length === 3) hit = opts[idx];
    if (!hit) return false;
    hit.click();
    return true;
  }
  function pickBot(name) {
    if (!name) return true;
    var li = document.querySelector('li.bot-component[data-bot-selection-name="' + String(name).replace(/"/g, '') + '"]');
    if (!li) return false;
    var img = li.querySelector('img') || li;
    img.click();
    return true;
  }

  // ------------------------------------------------------- page styling
  var STYLE_ID = 'blindchess-style';
  var CSS = [
    /* ads and upsell clutter */
    '#board-layout-ad, .board-layout-ad, [id^="google_ads"], [id*="-ad-"], [class*="ad-banner"], [class*="ad-container"], .bottom-banner-component,',
    'iframe[src*="doubleclick"], iframe[id*="google_ads"], [data-ad-slot], .ad-upgrade-link-link-height, [class*="sidebar-ad"],',
    '.toolbar-mobile-ad, .mobile-ad, [class*="cookie-banner"], #onetrust-banner-sdk, .modal-upgrade-component',
    '{ display: none !important; }',
    /* keep the page from scrolling sideways on a phone */
    'html, body { overflow-x: hidden !important; }',
    'wc-chess-board { touch-action: none; }'
  ].join('\n');
  function ensureStyle() {
    if (!document.head && !document.documentElement) return;
    if (document.getElementById(STYLE_ID)) return;
    var s = document.createElement('style');
    s.id = STYLE_ID;
    s.textContent = CSS;
    (document.head || document.documentElement).appendChild(s);
  }

  // ------------------------------------------------------------ wiring
  var pending = false;
  function schedule(why) {
    if (pending) return;
    pending = true;
    setTimeout(function () { pending = false; try { check(why); } catch (e) {} }, 60);
  }
  function start() {
    ensureStyle();
    try {
      observer = new MutationObserver(function () { ensureStyle(); if (boardEl() !== T.boardRef || setupVisible() !== T.setupSeen) schedule('mutation'); });
      observer.observe(document.documentElement, { childList: true, subtree: true });
    } catch (e) {}
    timers.push(setInterval(function () { try { check('poll'); } catch (e) {} }, 400));
    w.addEventListener('popstate', onNav);
    check('install');
  }
  function onNav() { schedule('navigation'); }

  var api = {
    version: VERSION,
    __alive: true,
    events: events,
    state: function () { try { return buildState(); } catch (e) { return { ok: false, error: String(e && e.message || e) }; } },
    move: function (uci, opts) { try { return move(uci, opts); } catch (e) { return { ok: false, error: 'exception', detail: String(e && e.message || e) }; } },
    legalMoves: function () { try { return legalMoves(); } catch (e) { return []; } },
    resign: function () { try { return resign(); } catch (e) { return { ok: false, error: String(e) }; } },
    takeback: function () { try { return takeback(); } catch (e) { return { ok: false, error: String(e) }; } },
    hint: function () { try { return hint(); } catch (e) { return { ok: false, error: String(e) }; } },
    startNewGame: function (o) { try { return startNewGame(o); } catch (e) { return { ok: false, error: String(e) }; } },
    closeModal: function () { try { return closeModal(); } catch (e) { return false; } },
    eventsSince: function (s) { s = s || 0; return events.filter(function (e) { return e.seq > s; }); },
    __check: function (why) { check(why || 'manual'); },
    __teardown: function () {
      api.__alive = false;
      timers.forEach(clearInterval); timers = [];
      if (observer) { try { observer.disconnect(); } catch (e) {} observer = null; }
      if (T.unbind) { try { T.unbind(); } catch (e) {} T.unbind = null; }
      w.removeEventListener('popstate', onNav);
    }
  };
  w.BlindChess = api;
  if (document.documentElement) start();
  else document.addEventListener('DOMContentLoaded', start);
  return 'BlindChess:installed';
})();
