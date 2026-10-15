// Run a PRG in the bundled VICE for N seconds (emulated, warp) and save a
// screenshot, optionally with monitor commands (e.g. joystick pokes).
//
//   node vice.mjs file.prg seconds out.png [moncommands.txt]
import { spawnSync } from 'child_process';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const VICE = path.join(HERE, '..', '..', 'C64DevMachine_win.yyp', 'datafiles', 'vice', 'win', 'bin', 'x64sc.exe');

export function runVice(prg, seconds, png, extra = []) {
  const cycles = Math.round(seconds * 985248);
  if (fs.existsSync(png)) fs.unlinkSync(png);
  const args = ['-default', '-silent', '+sound', '-warp', '-minimized', '-autostartprgmode', '1',
    '-limitcycles', String(cycles), '-exitscreenshot', path.resolve(png), ...extra, '-autostart', path.resolve(prg)];
  const r = spawnSync(VICE, args, { encoding: 'utf8', timeout: 300000 });
  return { ok: fs.existsSync(png), status: r.status, out: (r.stdout || '') + (r.stderr || '') };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [prg, secs, png, mon] = process.argv.slice(2);
  const extra = mon ? ['-moncommands', path.resolve(mon)] : [];
  const r = runVice(prg, +secs, png, extra);
  console.log(r.ok ? 'screenshot ' + png : 'NO SCREENSHOT', 'exit', r.status);
  if (!r.ok) console.log(r.out.slice(-2000));
}
