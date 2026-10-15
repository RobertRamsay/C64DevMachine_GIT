// Human-control tests on the headless 6502 sim: drive the joysticks
// frame by frame and check that the game reacts as designed.
//   node humantest.mjs
import { Sim } from './sim.mjs';

const UP = 1, DOWN = 2, LEFT = 4, RIGHT = 8, FIRE = 16;
let pass = 0, fail = 0;
const ok = (cond, name, info = '') => { if (cond) pass++; else fail++; console.log((cond ? 'PASS ' : 'FAIL ') + name + (info ? '  (' + info + ')' : '')); };

class T {
  constructor(humans = 1, seed = 0x5A) {
    this.s = new Sim({ humans, seed });
    this.s.script = null;
    this.m = this.s.mem; this.C = this.s.C; this.L = this.s.L;
    this.calls = {};
    const names = ['DoPass', 'DoShootOrLong', 'Shoot', 'LongBall', 'StartSlide', 'SwitchNearest', 'DoLongKick', 'DoCross', 'Kick', 'Steal', 'SlidePoke', 'ThrowIn', 'Goal', 'OutEnd', 'PassTo'];
    const ad = {}; for (const n of names) if (this.L[n] !== undefined) ad[this.L[n]] = n;
    this.s.cpu.trace = (c, pc) => { const n = ad[pc]; if (n) this.calls[n] = (this.calls[n] || 0) + 1; };
  }
  g(n) { return this.m[this.C[n]]; }
  pos(i) { return this.s.pos(i); }
  run(n, p2 = 0, p1 = 0) { for (let i = 0; i < n; i++) { this.s.joy = [p2, p1]; this.s.step(); } }
  until(fn, max, p2 = 0, p1 = 0) { for (let i = 0; i < max; i++) { if (fn()) return i; this.run(1, p2, p1); } return -1; }
  tap(port = 0, frames = 3) { this.run(frames, port === 0 ? FIRE : 0, port === 1 ? FIRE : 0); this.run(1); }
  hold(port, frames, dir = 0) { this.run(frames, port === 0 ? FIRE | dir : 0, port === 1 ? FIRE | dir : 0); this.run(1, port === 0 ? dir : 0, port === 1 ? dir : 0); }
  reset() { this.calls = {}; }
  kickoff() { this.run(3); this.tap(0); this.run(5); }
  // put the human (port p) on the ball at (x, y), facing right
  giveBall(p, x, y) {
    const C = this.C, m = this.m, me = m[C.CTRL1 + p];
    m[C.PXL + me] = x & 255; m[C.PXH + me] = x >> 8; m[C.PYL + me] = y & 255; m[C.PYH + me] = y >> 8;
    m[C.PSTATE + me] = 0; m[C.PCOOL + me] = 0; m[C.OWNER] = me; m[C.PDIR + me] = 0;
    return me;
  }
  // park everybody but the listed players far away in their own corners
  clear(...keep) {
    const C = this.C, m = this.m;
    for (let q = 0; q < 22; q++) {
      if (keep.includes(q)) continue;
      const x = q < 11 ? 40 : 980, y = 70 + (q % 11) * 8;
      m[C.PXL + q] = x & 255; m[C.PXH + q] = x >> 8; m[C.PYL + q] = y; m[C.PYH + q] = 0; m[C.PSTATE + q] = 0;
    }
  }
}

// ---------------------------------------------------------------- kick-off
{
  const t = new T(1);
  ok(t.g('GSTATE') === 1 && t.g('RS_TYPE') === 3, 'match starts with a kick-off restart');
  const taker = t.g('OWNER');
  ok(taker < 11, 'C64 (port 2) kicks off', 'owner ' + taker);
  ok(t.g('CTRL1') === taker, 'port 2 controls the kick-off taker', 'ctrl ' + t.g('CTRL1'));
  t.run(40);
  ok(t.g('GSTATE') === 1, 'kick-off waits for the human');
  t.reset(); t.tap(0);
  ok(t.calls.DoPass >= 1, 'tap fire at kick-off passes', JSON.stringify(t.calls));
  ok(t.g('GSTATE') === 0, 'play is on after the kick-off');
  const to = t.g('PASS_TO');
  ok(to < 11 && to !== taker, 'pass goes to a team-mate', 'to ' + to);
  ok(t.g('CTRL1') === to, 'control switches to the receiver', 'ctrl ' + t.g('CTRL1'));
  const n = t.until(() => t.g('OWNER') === to, 120);
  ok(n >= 0, 'receiver collects the pass', 'frames ' + n + ' owner ' + t.g('OWNER'));
}

// ---------------------------------------------------------------- dribble + shot
{
  const t = new T(1);
  t.kickoff();
  t.s.joy = [0, 0];
  const me = t.giveBall(0, 600, 212);
  t.clear(me, 11);
  t.run(1);
  const x0 = t.pos(me).x;
  t.run(60, RIGHT);
  const x1 = t.pos(me).x;
  ok(t.g('OWNER') === me && x1 - x0 > 50, 'dribble right with the ball', `x ${x0} -> ${x1}, owner ${t.g('OWNER')}`);
  t.run(30, UP);
  ok(t.pos(me).y < 212 - 15, 'dribble up', 'y ' + t.pos(me).y);
  // now shoot from ~140 px
  t.giveBall(0, 770, 212); t.clear(me, 11);
  t.run(2, RIGHT);
  t.reset();
  t.hold(0, 24, RIGHT);
  ok(t.calls.Shoot >= 1, 'hold + release fire near goal shoots', JSON.stringify(t.calls));
  const vx = (t.m[t.C.VXH + 22] << 8 | t.m[t.C.VXL + 22]) << 16 >> 16;
  ok(vx > 512, 'the shot flies towards the right goal', 'vx ' + (vx / 256).toFixed(2));
  const r = t.until(() => t.g('GSTATE') !== 0 || t.g('OWNER') < 22, 120);
  ok(r >= 0, 'the shot ends in a goal, save or goal kick', `gstate ${t.g('GSTATE')} owner ${t.g('OWNER')} score ${t.g('SCORE0')}-${t.g('SCORE1')}`);
}

// ---------------------------------------------------------------- long ball from deep
{
  const t = new T(1);
  t.kickoff();
  const me = t.giveBall(0, 300, 212); t.clear(me);
  t.run(2, RIGHT); t.reset();
  t.hold(0, 30, RIGHT);
  ok(t.calls.LongBall >= 1 && !t.calls.Shoot, 'held fire far from goal plays a long ball', JSON.stringify(t.calls));
  ok(t.m[t.C.BZH] > 0 || t.m[t.C.BVZH] > 0, 'the long ball is lofted', 'z ' + t.m[t.C.BZH] + ' vz ' + t.m[t.C.BVZH]);
}

// ---------------------------------------------------------------- tackles, switching
{
  const t = new T(1);
  t.kickoff();
  const C = t.C, m = t.m, me = t.g('CTRL1');
  // opponent 20 has the ball right next to us
  t.clear(me, 20);
  const set = (p, x, y) => { m[C.PXL + p] = x & 255; m[C.PXH + p] = x >> 8; m[C.PYL + p] = y; m[C.PYH + p] = 0; m[C.PSTATE + p] = 0; m[C.PCOOL + p] = 0; };
  set(20, 500, 200); set(me, 485, 200); m[C.OWNER] = 20; m[C.PDIR + me] = 0;
  t.run(1, RIGHT); t.reset();
  t.tap(0, 2);
  ok(t.calls.StartSlide >= 1, 'fire near an opponent with the ball slides', JSON.stringify(t.calls));
  ok(m[C.PSTATE + me] === 1 || t.calls.SlidePoke, 'player is sliding', 'state ' + m[C.PSTATE + me]);
  t.run(30, RIGHT);
  ok(t.calls.SlidePoke >= 1 || t.g('OWNER') !== 20, 'the slide wins the ball', `owner ${t.g('OWNER')} ${JSON.stringify(t.calls)}`);

  // far from the ball: fire switches to the man nearest the ball
  const t2 = new T(1);
  t2.kickoff();
  const me2 = t2.g('CTRL1');
  t2.m[C.OWNER] = 255;
  const bx = 300; t2.m[C.PXL + 22] = bx & 255; t2.m[C.PXH + 22] = bx >> 8; t2.m[C.PYL + 22] = 120;
  const far = 9; t2.m[C.CTRL1] = far; t2.m[C.PXL + far] = 0; t2.m[C.PXH + far] = 3;
  t2.reset(); t2.tap(0, 2);
  ok(t2.calls.SwitchNearest >= 1 && t2.g('CTRL1') !== far, 'fire away from the ball switches player', `ctrl ${far} -> ${t2.g('CTRL1')}`);
}

// ---------------------------------------------------------------- restarts taken by the human
{
  const t = new T(1);
  t.kickoff();
  const C = t.C, m = t.m;
  // VIC player kicks it out over the top line: C64 throw-in
  t.clear(20);
  m[C.OWNER] = 255; m[C.LASTTOUCH] = 20;
  m[C.PXL + 22] = 400 & 255; m[C.PXH + 22] = 400 >> 8; m[C.PYL + 22] = 74; m[C.PYH + 22] = 0;
  m[C.VYL + 22] = 0x00; m[C.VYH + 22] = 0xFD; m[C.VXL + 22] = 0; m[C.VXH + 22] = 0;
  const n = t.until(() => t.g('GSTATE') === 1, 30);
  ok(n >= 0 && t.g('RS_TYPE') === 0, 'ball over the touchline gives a throw-in', 'rs ' + t.g('RS_TYPE'));
  ok(t.g('RS_TEAM') === 0, 'throw-in to the C64 team', 'team ' + t.g('RS_TEAM'));
  const w = t.until(() => { const o = t.g('OWNER'); return o < 22 && t.m[C.PSTATE + o] === 7; }, 300);
  const taker = t.g('OWNER');
  ok(w >= 0 && taker < 11, 'a C64 player waits with the ball', 'owner ' + taker + ' state ' + m[C.PSTATE + taker]);
  ok(t.g('CTRL1') === taker, 'port 2 controls the thrower', 'ctrl ' + t.g('CTRL1'));
  t.run(100);
  ok(t.g('GSTATE') === 1, 'the throw waits for the human');
  t.reset(); t.tap(0);
  ok(t.calls.DoPass >= 1 && t.g('GSTATE') === 0, 'tap fire takes the throw-in', JSON.stringify(t.calls));
}

// ---------------------------------------------------------------- keeper holds, human releases
{
  const t = new T(1);
  t.kickoff();
  const C = t.C, m = t.m;
  // the C64 keeper (0) catches a ball
  t.clear(0);
  m[C.PXL + 22] = 140; m[C.PXH + 22] = 0; m[C.PYL + 22] = 212; m[C.PYH + 22] = 0;
  m[C.PXL + 0] = 138; m[C.PXH + 0] = 0; m[C.PYL + 0] = 212; m[C.PYH + 0] = 0;
  m[C.VXL + 22] = 0; m[C.VXH + 22] = 0; m[C.VYL + 22] = 0; m[C.VYH + 22] = 0; m[C.OWNER] = 255; m[C.BZH] = 0;
  const n = t.until(() => t.g('OWNER') === 0, 40);
  ok(n >= 0, 'keeper picks up the loose ball', 'owner ' + t.g('OWNER'));
  ok(m[C.PSTATE + 0] === 6 && t.g('CTRL1') === 0, 'keeper holds it and port 2 controls him', 'state ' + m[C.PSTATE + 0] + ' ctrl ' + t.g('CTRL1'));
  t.reset(); t.hold(0, 25, RIGHT);
  ok((t.calls.LongBall || t.calls.DoShootOrLong || t.calls.DoLongKick) >= 1 && t.g('OWNER') === 255, 'held fire: keeper kicks it long', JSON.stringify(t.calls));
}

// ---------------------------------------------------------------- two players
{
  const t = new T(3);
  ok(t.g('CTRL2') >= 11 && t.g('CTRL2') < 22, 'port 1 controls a VIC player', 'ctrl2 ' + t.g('CTRL2'));
  t.kickoff();
  // follow whoever port 1 controls (it switches to the man nearest the ball)
  let moved = 0;
  for (let i = 0; i < 40; i++) { const me = t.g('CTRL2'), y0 = t.pos(me).y; t.run(1, 0, DOWN); if (t.g('CTRL2') === me) moved += t.pos(me).y - y0; }
  ok(moved > 25, 'port 1 joystick moves the VIC player', 'moved ' + moved + ' px down');
}

// ---------------------------------------------------------------- whole match, half time, full time
{
  const t = new T(1, 0x33);
  t.kickoff();
  let half2 = -1, full = -1, f = 0;
  for (; f < 40000; f++) {
    t.run(1, f % 90 < 3 ? FIRE : 0);       // keep taking restarts
    if (half2 < 0 && t.g('HALF') === 2) half2 = f;
    if (t.g('MODE') === 0) { full = f; break; }
  }
  ok(half2 > 8100, 'second half starts after 45 game minutes', 'frame ' + half2);
  ok(full > half2 + 8100, 'full time returns to the title', 'frame ' + full + ' score ' + t.g('SCORE0') + '-' + t.g('SCORE1'));
}

// ---------------------------------------------------------------- demo ends on fire
{
  const t = new T(0);
  t.run(300);
  ok(t.g('MODE') === 1, 'demo match runs');
  t.tap(0, 2);
  ok(t.g('MODE') === 0, 'fire during the demo goes back to the title');
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
