// contact sheet: node sheet.mjs out.png cols y0 y1 frame1.png frame2.png ...
import { readPng, writeRgbPng } from './zoom.mjs';
const [out, colsS, y0S, y1S, ...files] = process.argv.slice(2);
const cols = +colsS, y0 = +y0S, y1 = +y1S;
const imgs = files.map(readPng);
const w = imgs[0].w, h = y1 - y0, rows = Math.ceil(imgs.length / cols), gap = 4;
const W = cols * (w + gap), H = rows * (h + gap);
const rgb = Buffer.alloc(W * H * 3, 255);
imgs.forEach((im, i) => {
  const ox = (i % cols) * (w + gap), oy = Math.floor(i / cols) * (h + gap);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const s = ((y + y0) * im.w + x) * 3, d = ((oy + y) * W + ox + x) * 3;
    rgb[d] = im.rgb[s]; rgb[d + 1] = im.rgb[s + 1]; rgb[d + 2] = im.rgb[s + 2];
  }
});
writeRgbPng(out, W, H, rgb);
console.log(out, W, H);
