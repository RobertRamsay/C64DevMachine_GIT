// ALIEN BREED 64 text: HUD template, messages, text pages and the title
// screen. The font is the Dev Machine template font in ASCII order, so a
// screen code is the ASCII code (32-95). Text colours are 0-7: the screens
// run in multicolour char mode, where 8+ would make a font char multicolour.

export const MSG_LEN = 36;
const enc = s => [...s.toUpperCase()].map(c => { const v = c.charCodeAt(0); if (v < 32 || v > 95) throw new Error('char not in font: ' + c); return v; });

// ------------------------------------------------------------ HUD
// rows 22-24 of both screens; the HUD shows columns 1-37
export function buildHud() {
  const rows = [
    ' ENERGY ########  LIVES 9  AMMO 999     ',
    ' KEYS 9   CREDITS 999999  SCORE 999999  ',
    ' ' + ' '.repeat(MSG_LEN) + '   ',
  ];
  const chars = [], cols = [];
  rows.forEach((r, ri) => {
    if (r.length !== 40) throw new Error('HUD row ' + ri + ' is ' + r.length);
    [...r].forEach((ch, i) => {
      chars.push(ch === '#' ? 1 : ch === '9' ? 48 : ch.charCodeAt(0));
      cols.push(ri === 2 ? 7 : ch === '#' ? 5 : ch === '9' ? 1 : 3);
    });
  });
  const O = {
    HUD_O_ENERGY: rows[0].indexOf('#'), HUD_O_LIVES: rows[0].indexOf('LIVES') + 6, HUD_O_AMMO: rows[0].indexOf('AMMO') + 5,
    HUD_O_KEYS: 40 + rows[1].indexOf('KEYS') + 5, HUD_O_CREDITS: 40 + rows[1].indexOf('CREDITS') + 8,
    HUD_O_SCORE: 40 + rows[1].indexOf('SCORE') + 6, HUD_O_MSG: 81,
  };
  return { chars, cols, O };
}

// ------------------------------------------------------------ TEXTS asset
export const INTEX_ROWS = [8, 10, 12, 14, 16];
export const PAGE_SCORE = [15, 20];
export function buildTexts(base) {
  const out = [], C = {};
  const at = () => base + out.length;
  const msg = (name, s) => { if (s.length > MSG_LEN) throw new Error('message too long: ' + s); C[name] = at(); out.push(...enc(s.padEnd(MSG_LEN))); };
  const str = (name, row, col, colour, s) => {
    if (row > 20 || col + s.length > 38) throw new Error(`text past column 37: ${s}`);
    if (colour > 7) throw new Error('text colour must be 0-7');
    if (name) C[name] = at();
    const a = at(); out.push(row, col, colour, ...enc(s), 0); return a;
  };
  const centre = (row, colour, s) => str(null, row, Math.max(0, Math.floor((38 - s.length) / 2)), colour, s);
  const page = (name, strings) => { const a = strings.map(f => f()); C[name] = at(); for (const p of a) out.push(p & 255, p >> 8); out.push(0, 0); };

  msg('TX_MSG_D1', 'DECK 1  INTEX CONTROL');
  msg('TX_MSG_D2', 'DECK 2  REACTOR  - RED ALERT -');
  msg('TX_GOAL1', 'LOCATE THE LIFT TO DECK 2');
  msg('TX_GOAL2', 'DESTROY THE 4 REACTOR CORES');
  msg('TX_GOAL3', 'ALL CORES DOWN - REACH THE LIFT');
  msg('TX_MSG_DEAD', 'MARINE DOWN');
  msg('TX_MSG_OPEN', 'DOOR OPENED');
  msg('TX_MSG_LOCKED', 'DOOR LOCKED - FIND A KEY');
  msg('TX_MSG_KEY', 'KEY COLLECTED');
  msg('TX_MSG_AMMO', 'AMMO CLIP  +50 ROUNDS');
  msg('TX_MSG_MED', 'FIRST AID  +ENERGY');
  msg('TX_MSG_CRED', 'CREDITS  +1000');
  msg('TX_MSG_LIFTLOCK', 'LIFT LOCKED - REACTOR STILL ONLINE');
  msg('TX_MSG_NOAMMO', 'OUT OF AMMO - FIND A CLIP');
  msg('TX_MSG_SD', 'WARNING - SELF DESTRUCT ACTIVATED');
  msg('TX_MSG_CORE', 'REACTOR CORE DESTROYED');
  const timer = 'SELF DESTRUCT 0:00  RUN FOR THE LIFT';
  msg('TX_MSG_TIMER', timer);
  C.TIMER_O = timer.indexOf('0:00');

  // Intex status line
  str('TX_INT_OK', 18, 3, 5, 'TRANSACTION APPROVED       ');
  str('TX_INT_POOR', 18, 3, 2, 'INSUFFICIENT CREDITS       ');

  const scoreLine = () => str(null, PAGE_SCORE[0], 12, 1, 'SCORE   ');
  const fire = () => centre(19, 7, 'PRESS FIRE');
  page('PG_INTEX', [
    () => str(null, 1, 1, 3, 'INTEX NETWORK SYSTEMS   TERMINAL 7.2'),
    () => str(null, 2, 1, 5, '------------------------------------'),
    () => str(null, 3, 1, 3, 'ISRC-4 RESEARCH STATION  STATUS RED'),
    () => str(null, 5, 3, 5, 'CREDITS'),
    () => str(null, INTEX_ROWS[0], 3, 3, 'AMMO CLIP    50 ROUNDS     1000 CR'),
    () => str(null, INTEX_ROWS[1], 3, 3, 'FIRST AID    24 ENERGY     1500 CR'),
    () => str(null, INTEX_ROWS[2], 3, 3, 'KEY PASS     ONE DOOR      2500 CR'),
    () => str(null, INTEX_ROWS[3], 3, 3, 'EXTRA LIFE   ONE MARINE   10000 CR'),
    () => str(null, INTEX_ROWS[4], 3, 3, 'LOG OFF'),
    () => str(null, 19, 1, 5, 'UP DOWN SELECT     FIRE CONFIRM'),   // row 20 runs into the HUD split
  ]);
  C.INTEX_CRED_AT = 5 * 40 + 12;
  page('PG_DONE', [
    () => centre(5, 1, 'DECK 1 CLEARED'),
    () => centre(8, 3, 'THE LIFT DROPS TO DECK 2.'),
    () => centre(10, 3, 'THE REACTOR IS OVERRUN.'),
    () => centre(11, 3, 'SHOOT OUT ALL FOUR CORES,'),
    () => centre(12, 3, 'THEN RUN FOR THE LIFT.'),
    scoreLine, fire,
  ]);
  page('PG_WIN', [
    () => centre(5, 1, 'MISSION COMPLETE'),
    () => centre(8, 3, 'ISRC-4 IS GONE.'),
    () => centre(10, 3, 'YOU MADE IT OUT - FOR NOW.'),
    () => centre(12, 6, 'THE BREED WILL BE BACK.'),
    scoreLine, fire,
  ]);
  page('PG_OVER0', [
    () => centre(5, 2, 'GAME OVER'),
    () => centre(9, 3, 'THE BREED HAS TAKEN THE STATION.'),
    scoreLine, fire,
  ]);
  page('PG_OVER1', [
    () => centre(5, 2, 'GAME OVER'),
    () => centre(9, 3, 'THE STATION SELF-DESTRUCTED'),
    () => centre(10, 3, 'WITH YOU STILL ON BOARD.'),
    scoreLine, fire,
  ]);
  C.PAGE_SCORE_AT = PAGE_SCORE[0] * 40 + PAGE_SCORE[1];
  return { bytes: out, C };
}
