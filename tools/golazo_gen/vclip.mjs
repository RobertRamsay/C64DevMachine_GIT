// scan the demo frame by frame at the $FC IRQ; screenshot frames where
// the camera moves vertically (and the one before)
//   node vscroll2.mjs skip frames maxShots outdir
import fs from 'fs';
import { Vice, fwd } from './vremote.mjs';
const [skip, frames, maxShots, dir] = [+(process.argv[2] || 1500), +(process.argv[3] || 600), +(process.argv[4] || 40), process.argv[5] || 'out/vs'];
fs.mkdirSync(dir, { recursive: true });
for (const f of fs.readdirSync(dir)) fs.unlinkSync(dir + '/' + f);
const L = JSON.parse(fs.readFileSync('out/labels.json', 'utf8'));
const C = L.consts, lab = L.labels;
const v = await Vice.start('out/golazo.prg');
const rows = [];
try {
  await v.stop();
  await v.cmd(`break $${lab.IrqBottom.toString(16)}`);
  await v.cmd(`ignore 1 ${skip.toString(16)}`);
  await v.cmd('x', 600000);
  let prevY = -1, shots = 0, lastShot = -9;
  for (let f = 0; f < frames && shots < maxShots; f++) {
    if (f) await v.cmd('x');
    const y = (await v.mem(C.CAM1Y, C.CAM1Y))[0], s = (await v.mem(C.CUR_S, C.CUR_S))[0];
    const r = { f, y, s };
    const fixm = (await v.mem(C.FIXM, C.FIXM))[0]; r.fixm = fixm;
    if (process.env.FIX ? fixm : (prevY >= 0 && y !== prevY)) {
      const png = `${dir}/f${String(f).padStart(3, '0')}.png`;
      await v.cmd(`screenshot "${fwd(png)}" 2`); shots++; r.png = png;
    }
    rows.push(r); prevY = y;
  }
} finally { v.kill(); }
fs.writeFileSync(dir + '/cam.json', JSON.stringify(rows));
console.log(rows.filter(r => r.png).map(r => `${r.f}:y${r.y}s${r.s}`).join(' '));
