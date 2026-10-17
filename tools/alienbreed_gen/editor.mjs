// Round trip through a running, paired Dev Machine (MCP bridge):
//   node editor.mjs           - build out/ALIEN_BREED_editor.json, load it,
//                               native build, compare C:\C64Temp\program.prg
//                               with out/alienbreed.prg
// Only the SFX and MUSIC macro columns (and the JSRs into them) may differ.
import { spawn, execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BRIDGE = path.join(HERE, '..', 'cdm-mcp', 'bridge.mjs');
const PROJECT = path.join(HERE, 'out', 'ALIEN_BREED_editor.json');
const EDITOR_PRG = 'C:/C64Temp/program.prg';

export async function mcp() {
  const p = spawn(process.execPath, [BRIDGE], { stdio: ['pipe', 'pipe', 'ignore'] });
  let buf = '', id = 0;
  const wait = new Map();
  p.stdout.on('data', d => {
    buf += d;
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const l = buf.slice(0, i); buf = buf.slice(i + 1);
      if (!l.trim()) continue;
      const m = JSON.parse(l);
      if (wait.has(m.id)) { wait.get(m.id)(m); wait.delete(m.id); }
    }
  });
  const rpc = (method, params) => new Promise((res, rej) => {
    const n = ++id;
    const t = setTimeout(() => rej(new Error(method + ' timed out')), 60000);
    wait.set(n, m => { clearTimeout(t); res(m); });
    p.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: n, method, params }) + '\n');
  });
  await rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'alienbreed-gen', version: '1' } });
  p.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  const call = async (name, args = {}) => {
    const r = await rpc('tools/call', { name, arguments: args });
    const text = (r.result?.content || []).map(c => c.text).join('');
    if (r.error || r.result?.isError) throw new Error(name + ': ' + (text || JSON.stringify(r.error)));
    try { return JSON.parse(text); } catch { return text; }
  };
  return { call, close: () => p.kill() };
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  execFileSync(process.execPath, [path.join(HERE, 'build.mjs'), PROJECT], { stdio: 'inherit', cwd: HERE });
  const ed = await mcp();
  try {
    let key = (await ed.call('cdm_project_summary', { limit: 1 })).workspace_key;
    const ld = await ed.call('cdm_load_project', { expected_workspace: key, path: PROJECT.replace(/\\/g, '/'), discard_unsaved: true });
    console.log('loaded', ld.loaded);
    key = (await ed.call('cdm_project_summary', { limit: 1 })).workspace_key;
    const before = fs.existsSync(EDITOR_PRG) ? fs.statSync(EDITOR_PRG).mtimeMs : 0;
    await ed.call('cdm_build', { expected_workspace: key, run: false });
    let st;
    for (let i = 0; i < 60; i++) {
      await sleep(1500);
      try { st = await ed.call('cdm_build_status'); } catch { continue; }
      if (['built', 'failed', 'attention_required'].includes(st.state)) break;
    }
    console.log('build', st.state, st.message);
    if (st.state !== 'built') process.exit(1);
    if (fs.statSync(EDITOR_PRG).mtimeMs === before) throw new Error('program.prg was not rewritten');
  } finally { ed.close(); }
  execFileSync(process.execPath, [path.join(HERE, 'compare.mjs'), EDITOR_PRG, path.join(HERE, 'out', 'alienbreed.prg')], { stdio: 'inherit', cwd: HERE });
}
