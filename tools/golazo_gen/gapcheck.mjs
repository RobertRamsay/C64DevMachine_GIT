// screenshots: any pixel between the HUD bar and the pitch's first line
// means a sprite drew over the split. node gapcheck.mjs dir
import fs from 'fs';
import { readPng } from './zoom.mjs';
const dir = process.argv[2] || 'out/vs';
const files = fs.readdirSync(dir).filter(f => f.endsWith('.png')).sort();
let bad = 0;
for (const f of files) {
  const im = readPng(dir + '/' + f);
  let ps = 47; while (ps < 100) { const o = (ps * im.w + 201) * 3; if (im.rgb[o] + im.rgb[o + 1] + im.rgb[o + 2] > 60) break; ps++; }
  let n = 0;
  for (let y = 46; y < ps; y++) for (let x = 32; x < 352; x++) { const o = (y * im.w + x) * 3; if (im.rgb[o] + im.rgb[o + 1] + im.rgb[o + 2] > 60) n++; }
  // HUD rows (above the bar): sprite colours there (skin/shirt) mean overlap
  let h = 0;
  for (let y = 32; y < 43; y++) for (let x = 32; x < 352; x++) { const o = (y * im.w + x) * 3; const r = im.rgb[o], g = im.rgb[o + 1], b = im.rgb[o + 2]; if (r > 150 && g < 140 && b < 140) h++; }
  if (n || h) { bad++; console.log(f, 'gap pixels', n, 'reddish HUD pixels', h, 'pitch from line', ps); }
}
console.log(files.length, 'frames,', bad, 'with sprite pixels above the pitch');
