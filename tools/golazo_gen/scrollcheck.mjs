// every frame: the shown screen buffer must equal the map at the camera cell
import { Sim } from './sim.mjs';
const frames = +(process.argv[2] || 6000);
const sim = new Sim({ humans: 0 });
const m = sim.mem, C = sim.C;
let bad = 0, holds = 0, flips = 0, lastX = -1, lastY = -1, jumps = 0;
for (let f = 0; f < frames; f++) {
  sim.step();
  const front = (m[C.CUR_D018] & 0x10) ? C.SCRB : C.SCRA;
  const cx = m[C.CAM1X] | m[C.CAM1X + 1] << 8, cy = m[C.CAM1Y];
  const c0 = cx >> 3, r0 = cy >> 3;
  let errs = 0;
  for (let r = 0; r < 23; r++) for (let c = 0; c < 39; c++)
    if (m[front + (2 + r) * 40 + c] !== m[C.MAP + (r0 + r) * 128 + c0 + c]) errs++;
  if (errs) { bad++; if (bad < 5) console.log(`f${f} cam ${cx},${cy} cell ${c0},${r0} FRONT ${m[C.FRONTC]},${m[C.FRONTR]} errs ${errs}`); }
  if (lastX >= 0 && (Math.abs(cx - lastX) > 3 || Math.abs(cy - lastY) > 2) && m[C.GSTATE] !== 1) jumps++;
  lastX = cx; lastY = cy;
}
console.log('frames', frames, 'bad frames', bad, 'camera jumps (non restart)', jumps);
