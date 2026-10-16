// Drive the bundled VICE through its text remote monitor: break at an
// address every frame, take screenshots and read memory.
//
//   const v = await Vice.start(prg); await v.cmd('break $1234'); ...
import { spawn } from 'child_process';
import net from 'net';
import path from 'path';
import { fileURLToPath } from 'url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const VICE = path.join(HERE, '..', '..', 'C64DevMachine_win.yyp', 'datafiles', 'vice', 'win', 'bin', 'x64sc.exe');
export const fwd = p => path.resolve(p).replace(/\\/g, '/');
const sleep = ms => new Promise(r => setTimeout(r, ms));

export class Vice {
  static async start(prg, { port = 6510 + (process.pid % 300), warp = true } = {}) {
    const v = new Vice();
    v.proc = spawn(VICE, ['-default', '-silent', '+sound', warp ? '-warp' : '+warp', '-minimized', '-autostartprgmode', '1',
      '-remotemonitor', '-remotemonitoraddress', `ip4://127.0.0.1:${port}`, '-autostart', fwd(prg)], { stdio: 'ignore' });
    for (let i = 0; i < 100; i++) {
      try { await v.connect(port); break; } catch { await sleep(200); }
    }
    if (!v.sock) throw new Error('no remote monitor');
    return v;
  }
  connect(port) {
    return new Promise((res, rej) => {
      const s = net.connect(port, '127.0.0.1');
      s.once('connect', () => { this.sock = s; this.buf = ''; s.on('data', d => { this.buf += d.toString('latin1'); }); res(); });
      s.once('error', rej);
    });
  }
  // send a command and wait for the next monitor prompt
  async cmd(c, timeout = 60000) {
    this.buf = '';
    this.sock.write(c + '\n');
    const t0 = Date.now();
    while (!/\(C:\$[0-9a-f]{4}\) $/.test(this.buf)) {
      if (Date.now() - t0 > timeout) throw new Error('timeout on ' + c + ': ' + this.buf.slice(-200));
      await sleep(5);
    }
    return this.buf;
  }
  // enter the monitor first (connecting does not stop the machine)
  async stop() { this.sock.write('\n'); const t0 = Date.now(); while (!/\(C:\$[0-9a-f]{4}\) $/.test(this.buf)) { if (Date.now() - t0 > 30000) throw new Error('no prompt'); await sleep(5); } }
  async mem(a, b) {
    const out = await this.cmd(`m ${a.toString(16)} ${b.toString(16)}`);
    const bytes = [];
    for (const line of out.split('\n')) {
      const m = line.match(/^>C:([0-9a-f]{4})\s+((?:[0-9a-f]{2}\s+)+)/);
      if (m) for (const h of m[2].trim().split(/\s+/)) bytes.push(parseInt(h, 16));
    }
    return bytes.slice(0, b - a + 1);
  }
  kill() { try { this.sock.end(); } catch { } try { this.proc.kill(); } catch { } }
}
