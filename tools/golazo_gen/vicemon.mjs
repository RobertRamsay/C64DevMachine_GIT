// Run VICE until a breakpoint (address, after N hits) then run monitor
// commands (output in the monitor log), dump RAM, and kill VICE.
//
//   import { atBreak } from './vicemon.mjs'
//   atBreak({ prg, addr, hits, cmds: ['m dd00 dd0f'], dump: 'out/mem.bin', setup: [...] })
import { spawn } from 'child_process';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const VICE = path.join(HERE, '..', '..', 'C64DevMachine_win.yyp', 'datafiles', 'vice', 'win', 'bin', 'x64sc.exe');
const fwd = p => path.resolve(p).replace(/\\/g, '/');

export function atBreak({ prg, addr, hits = 0, cmds = [], dump = null, setup = [], timeout = 90000, shot = null, warp = true }) {
  return new Promise(res => {
    const tag = path.join(HERE, 'out', 'mon_' + process.pid + '_' + Date.now());
    const log = tag + '.log', done = tag + '.done';
    for (const f of [log, done]) if (fs.existsSync(f)) fs.unlinkSync(f);
    if (dump && fs.existsSync(dump)) fs.unlinkSync(dump);
    const lines = [...setup, `break $${addr.toString(16)}`];
    if (hits) lines.push(`ignore 1 ${hits.toString(16)}`);
    // each command runs on its own checkpoint at the same address
    const all = [...cmds];
    if (shot) all.push(`screenshot "${fwd(shot)}" 2`);
    if (dump) all.push(`bsave "${fwd(dump)}" 0 0000 ffff`);
    all.push(`bsave "${fwd(done)}" 0 0000 0001`);
    all.forEach((c, i) => {
      if (i > 0) { lines.push(`break $${addr.toString(16)}`); if (hits) lines.push(`ignore ${i + 1} ${hits.toString(16)}`); }
      lines.push(`command ${i + 1} "${c.replace(/"/g, '\\"')}"`);
    });
    fs.writeFileSync(tag + '.mon', lines.join('\n') + '\n');
    const args = ['-default', '-silent', '+sound', warp ? '-warp' : '+warp', '-minimized', '-autostartprgmode', '1',
      '-monlog', '-monlogname', fwd(log), '-moncommands', fwd(tag + '.mon'), '-autostart', fwd(prg)];
    const p = spawn(VICE, args, { stdio: 'ignore' });
    const t0 = Date.now();
    const iv = setInterval(() => {
      if (fs.existsSync(done) || Date.now() - t0 > timeout) {
        clearInterval(iv);
        setTimeout(() => {
          try { p.kill(); } catch { }
          const text = fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '';
          res({ ok: fs.existsSync(done), log: text });
        }, 400);
      }
    }, 200);
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [prg, addr, hits, ...cmds] = process.argv.slice(2);
  atBreak({ prg, addr: parseInt(addr, 16), hits: +hits, cmds }).then(r => { console.log(r.ok ? 'OK' : 'TIMEOUT'); console.log(r.log.slice(-3000)); });
}
