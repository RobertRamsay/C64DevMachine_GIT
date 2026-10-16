// Capture consecutive VICE frames of the demo match (screenshot + camera)
//   node vscroll.mjs [skipFrames] [frames] [outdir]
import fs from 'fs';
import { execSync } from 'child_process';
import { Vice, fwd } from './vremote.mjs';

const skip = +(process.argv[2] || 1200), frames = +(process.argv[3] || 60), dir = process.argv[4] || "out/vs", at = process.argv[5] || "IrqBottom";
fs.mkdirSync(dir, { recursive: true });
for (const f of fs.readdirSync(dir)) fs.unlinkSync(dir + '/' + f);
const L = JSON.parse(fs.readFileSync('out/labels.json', 'utf8'));
const C = L.consts, lab = L.labels;
const v = await Vice.start('out/golazo.prg');
try {
  await v.stop();
  await v.cmd(`break $${lab[at].toString(16)}`);
  await v.cmd(`ignore 1 ${skip.toString(16)}`);
  await v.cmd('x', 600000).catch(() => {});      // runs title + demo until the hit
  const rows = [];
  for (let f = 0; f < frames; f++) {
    if (f) await v.cmd('x');
    const cam = [...await v.mem(C.CAM1X, C.CAM1X + 1), ...await v.mem(C.CAM1Y, C.CAM1Y)];
    const s = await v.mem(C.CUR_S, C.CUR_S);
    const png = `${dir}/f${String(f).padStart(3, '0')}.png`;
    await v.cmd(`screenshot "${fwd(png)}" 2`);
    rows.push({ f, camx: cam[0] | cam[1] << 8, camy: cam[2], s: s[0] });
  }
  fs.writeFileSync(dir + '/cam.json', JSON.stringify(rows));
  console.log(rows.map(r => `${r.f}:${r.camx},${r.camy}`).join(' '));
} finally { v.kill(); }
